package biblioteca

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"sync"

	"github.com/carmain/servidor-go/shared"
	"github.com/gin-gonic/gin"
)

// cacheMotorizaciones guarda búsquedas de motorización en memoria, indexadas
// por "marca|modelo|anio|trim". Thread-safe.
//
// Solo se cachean respuestas con resultados: una búsqueda vacía (sin API key,
// sin datos, o con error) se reintenta la próxima vez.
var cacheMotorizaciones = struct {
	mu   sync.RWMutex
	data map[string]*shared.RespuestaMotorizacion
}{data: make(map[string]*shared.RespuestaMotorizacion)}

// MotorizacionHandler maneja GET /api/motorizacion.
//
// Busca las motorizaciones de fábrica de un modelo/año usando Gemini con
// búsqueda web (grounding con Google Search). La app la consulta mientras
// el usuario llena el formulario para auto-rellenar motor y transmisión.
//
// Query params: marca, modelo, anio (requeridos), trim (opcional).
// Respuesta: {motores, transmisiones, desdeCache}
//
// Sin GEMINI_API_KEY devuelve listas vacías — la app simplemente deja
// los campos manuales.
func (h *Handler) MotorizacionHandler(c *gin.Context) {
	marca := c.Query("marca")
	modelo := c.Query("modelo")
	anioStr := c.Query("anio")
	trim := c.Query("trim")

	if marca == "" || modelo == "" || anioStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "parámetros requeridos: marca, modelo, anio",
		})
		return
	}

	anio, err := strconv.Atoi(anioStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "anio debe ser un número entero"})
		return
	}

	clave := fmt.Sprintf("%s|%s|%d|%s", marca, modelo, anio, trim)

	// 1. Buscar en cache
	cacheMotorizaciones.mu.RLock()
	resp, ok := cacheMotorizaciones.data[clave]
	cacheMotorizaciones.mu.RUnlock()
	if ok {
		log.Printf("[motorizacion] servido desde cache para %s %s %d", marca, modelo, anio)
		// Copia con el flag en true — el objeto cacheado vive con
		// DesdeCache=false (así se serializó al generarse) y no se muta
		// bajo el RLock de otros hits.
		hit := *resp
		hit.DesdeCache = true
		c.JSON(http.StatusOK, hit)
		return
	}

	// 2. Investigar con Gemini + búsqueda web
	resp = investigarMotorizacion(marca, modelo, anio, trim)
	resp.DesdeCache = false

	log.Printf("[motorizacion] %s %s %d: %d motores, %d transmisiones",
		marca, modelo, anio, len(resp.Motores), len(resp.Transmisiones))

	// 3. Cachear solo si hay resultados (ver comentario en la cache)
	if len(resp.Motores) > 0 || len(resp.Transmisiones) > 0 {
		cacheMotorizaciones.mu.Lock()
		cacheMotorizaciones.data[clave] = resp
		cacheMotorizaciones.mu.Unlock()
	}

	c.JSON(http.StatusOK, resp)
}

// investigarMotorizacion consulta a Gemini las motorizaciones de fábrica
// de un modelo/año. Ante cualquier problema (sin key, error de API, JSON
// ilegible) retorna listas vacías — nunca un error: la búsqueda es un
// asistente del formulario, no un paso crítico.
func investigarMotorizacion(marca, modelo string, anio int, trim string) *shared.RespuestaMotorizacion {
	vacia := &shared.RespuestaMotorizacion{
		Motores:       []shared.OpcionMotor{},
		Transmisiones: []shared.OpcionTransmision{},
	}

	if geminiApiKey() == "" {
		log.Println("[motorizacion] GEMINI_API_KEY no configurada — sin sugerencias")
		return vacia
	}

	texto, err := llamarGemini(construirPromptMotorizacion(marca, modelo, anio, trim))
	if err != nil {
		log.Printf("[motorizacion] error llamando a Gemini: %v", err)
		return vacia
	}

	return parsearRespuestaMotorizacion(texto)
}

// parsearRespuestaMotorizacion extrae la respuesta del texto de Gemini
// con parseo tolerante POR ÍTEM (los mismos helpers que /api/componente):
// un motor con campos ilegibles — p. ej. "cilindros": "4" en string — se
// corrige o descarta solo. Un Unmarshal directo del struct tipado
// tumbaría TODA la respuesta por un solo campo en formato inesperado.
//
// Separado de investigarMotorizacion para poder testear el parseo sin
// llamar a la API.
func parsearRespuestaMotorizacion(texto string) *shared.RespuestaMotorizacion {
	vacia := &shared.RespuestaMotorizacion{
		Motores:       []shared.OpcionMotor{},
		Transmisiones: []shared.OpcionTransmision{},
	}

	var crudo struct {
		Motores       []any  `json:"motores"`
		Transmisiones []any  `json:"transmisiones"`
		Drivetrain    string `json:"drivetrain"`
	}
	if err := json.Unmarshal([]byte(extraerJSON(texto)), &crudo); err != nil {
		log.Printf("[motorizacion] error parseando respuesta de Gemini: %v", err)
		return vacia
	}

	resp := &shared.RespuestaMotorizacion{
		Motores:       []shared.OpcionMotor{},
		Transmisiones: []shared.OpcionTransmision{},
		Drivetrain:    crudo.Drivetrain,
	}
	for _, m := range crudo.Motores {
		mapa, ok := m.(map[string]any)
		if !ok {
			continue // ítem basura — no tumba el resto
		}
		op := parsearOpcionMotor(mapa)
		if op.Codigo != "" {
			resp.Motores = append(resp.Motores, op)
		}
	}
	for _, t := range crudo.Transmisiones {
		mapa, ok := t.(map[string]any)
		if !ok {
			continue
		}
		op := parsearOpcionTransmision(mapa)
		if op.Codigo != "" {
			resp.Transmisiones = append(resp.Transmisiones, op)
		}
	}
	return resp
}

// construirPromptMotorizacion pide a Gemini las motorizaciones de fábrica
// de un modelo/año, con búsqueda web para verificar datos reales.
//
// IMPORTANTE: "combustible" y "tipo" son un contrato con la app móvil
// (enums TipoCombustible y TipoTransmision en app/lib/models/enums.dart) —
// valores fuera de esos conjuntos se ignoran en el cliente.
func construirPromptMotorizacion(marca, modelo string, anio int, trim string) string {
	trimTexto := trim
	if trimTexto == "" {
		trimTexto = "(no especificado)"
	}

	return fmt.Sprintf(`Eres un experto automotriz con acceso a búsqueda web. Investiga las motorizaciones de fábrica ofrecidas para este vehículo:

- Marca: %s
- Modelo: %s
- Año: %d
- Trim: %s

Usa la búsqueda web para verificar los datos reales de ese modelo/año específico (códigos de motor y de transmisión que el fabricante usó de fábrica).

Devuelve EXCLUSIVAMENTE un JSON válido (sin markdown, sin texto adicional) con esta estructura:

{
  "drivetrain": "FWD | RWD | AWD | 4WD",
  "motores": [
    {
      "codigo": "código de motor de fábrica (ej. 2JZ-GTE)",
      "descripcion": "descripción corta (ej. 3.0L I6 biturbo)",
      "combustible": "gasolina | diesel | hibrido | electrico | gas",
      "cilindrada": 3.0,
      "cilindros": 6,
      "aspiracion": "NA | Turbo | Twin-Turbo | Supercharger",
      "potenciaHp": 280,
      "torqueNm": 450
    }
  ],
  "transmisiones": [
    {
      "codigo": "código de caja de fábrica (ej. R154)",
      "descripcion": "descripción corta (ej. manual 5 velocidades)",
      "tipo": "manual | automatica | cvt | dct | automatedManual",
      "marchas": 5
    }
  ]
}

Reglas:
- "combustible" y "tipo" DEBEN ser exactamente uno de los valores listados (el consumidor los valida contra enums estrictos).
- "drivetrain" es la tracción de fábrica de ese modelo/año (ej. Mustang → RWD, Golf → FWD). DEBE ser exactamente uno de los valores listados; si el modelo se ofreció con varias tracciones o no estás seguro, OMÍTELO.
- "potenciaHp" es la potencia de esa motorización en caballos de fuerza (HP) y "torqueNm" su torque en newton-metro (Nm): números sin unidad. Si la fuente solo da otra unidad, CONVIERTE exactamente con: 1 kW = 1.341 HP; 1 PS (CV) = 0.9863 HP; 1 lb-ft = 1.3558 Nm; 1 kgm = 9.8067 Nm. NUNCA reportes la cifra de otra unidad sin convertir.
- Lista TODAS las motorizaciones de fábrica de ese modelo/año (típicamente 1 a 4 opciones).
- Usa códigos reales de fábrica; si un código no existe públicamente, usa un nombre descriptivo corto (ej. "Manual 5 velocidades"). NUNCA escribas "Desconocido", "Unknown" o "N/A" como código.
- Campos opcionales (descripcion, cilindrada, cilindros, aspiracion, potenciaHp, torqueNm, marchas): omítelos si no los conoces con certeza.
- Si no encuentras datos confiables del vehículo, devuelve {"motores": [], "transmisiones": []}. NO inventes.`,
		marca, modelo, anio, trimTexto)
}
