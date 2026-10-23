package biblioteca

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"

	"github.com/carmain/servidor-go/shared"
	"github.com/gin-gonic/gin"
)

// cacheComponentes guarda búsquedas de información por código (motor o
// transmisión) en memoria, indexadas por "tipo|CODIGO". Thread-safe.
//
// Como la cache de motorizaciones, solo se guardan resultados encontrados:
// un código sin datos (o con error de Gemini) se reintenta la próxima vez.
var cacheComponentes = struct {
	mu   sync.RWMutex
	data map[string]*respuestaComponente
}{data: make(map[string]*respuestaComponente)}

// respuestaComponente es lo que devuelve GET /api/componente.
//
// Opcion lleva un shared.OpcionMotor o shared.OpcionTransmision según el
// parámetro tipo — el cliente sabe cuál pidió y cómo parsearlo. Nunca se
// devuelve error HTTP por "no encontrado": encontrado=false y la app deja
// los campos manuales.
type respuestaComponente struct {
	Encontrado bool `json:"encontrado"`
	Opcion     any  `json:"opcion,omitempty"`
	DesdeCache bool `json:"desdeCache"`
}

// ComponenteHandler maneja GET /api/componente.
//
// Busca la información de un código de motor o de transmisión concreto:
// el usuario del formulario puede escribir el código directamente y la
// app auto-rellena los detalles (combustible, cilindrada, marchas...).
// Usa Gemini con búsqueda web (grounding con Google Search).
//
// Query params: tipo (motor|transmision), codigo.
// Respuesta: {encontrado, opcion?, desdeCache}
func (h *Handler) ComponenteHandler(c *gin.Context) {
	tipo := c.Query("tipo")
	// En mayúsculas para que "k4j" y "K4J" compartan entrada de cache.
	codigo := strings.ToUpper(strings.TrimSpace(c.Query("codigo")))

	if codigo == "" || (tipo != "motor" && tipo != "transmision") {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "parámetros requeridos: tipo (motor|transmision), codigo",
		})
		return
	}

	clave := fmt.Sprintf("%s|%s", tipo, codigo)

	// 1. Buscar en cache
	cacheComponentes.mu.RLock()
	resp, ok := cacheComponentes.data[clave]
	cacheComponentes.mu.RUnlock()
	if ok {
		log.Printf("[componente] servido desde cache: %s %s", tipo, codigo)
		hit := *resp
		hit.DesdeCache = true
		c.JSON(http.StatusOK, hit)
		return
	}

	// 2. Investigar con Gemini + búsqueda web
	resp = investigarComponente(tipo, codigo)

	log.Printf("[componente] %s %s: encontrado=%v", tipo, codigo, resp.Encontrado)

	// 3. Cachear solo si se encontró (ver comentario en la cache)
	if resp.Encontrado {
		cacheComponentes.mu.Lock()
		cacheComponentes.data[clave] = resp
		cacheComponentes.mu.Unlock()
	}

	c.JSON(http.StatusOK, resp)
}

// investigarComponente consulta a Gemini la información de un código de
// motor o de transmisión. Ante cualquier problema (sin key, error de API,
// JSON ilegible, sin datos) devuelve encontrado=false — nunca un error:
// es un asistente del formulario, no un paso crítico.
func investigarComponente(tipo, codigo string) *respuestaComponente {
	if geminiApiKey() == "" {
		log.Println("[componente] GEMINI_API_KEY no configurada — sin datos")
		return &respuestaComponente{}
	}

	texto, err := llamarGemini(construirPromptComponente(tipo, codigo))
	if err != nil {
		log.Printf("[componente] error llamando a Gemini: %v", err)
		return &respuestaComponente{}
	}

	return parsearRespuestaComponente(tipo, texto)
}

// parsearRespuestaComponente extrae la opción del texto de Gemini. Separado
// de investigarComponente para poder testear el parseo sin llamar a la API.
func parsearRespuestaComponente(tipo, texto string) *respuestaComponente {
	var crudo map[string]any
	if err := json.Unmarshal([]byte(extraerJSON(texto)), &crudo); err != nil {
		log.Printf("[componente] error parseando respuesta de Gemini: %v", err)
		return &respuestaComponente{}
	}

	if tipo == "motor" {
		op := parsearOpcionMotor(crudo)
		if opcionMotorTieneDatos(op) {
			return &respuestaComponente{Encontrado: true, Opcion: op}
		}
		return &respuestaComponente{}
	}

	op := parsearOpcionTransmision(crudo)
	if opcionTransmisionTieneDatos(op) {
		return &respuestaComponente{Encontrado: true, Opcion: op}
	}
	return &respuestaComponente{}
}

// codigosPlaceholder: valores que Gemini escribe en "codigo" cuando no
// conoce el código de fábrica (visto en producción: "Desconocido" en las
// cajas de un Kia Sportage 2002). No sirven ni como dato ni como
// identificador — se degradan a la descripcion.
var codigosPlaceholder = map[string]bool{
	"desconocido": true, "unknown": true, "n/a": true, "na": true,
	"no disponible": true, "not available": true, "ninguno": true,
	"none": true, "?": true, "-": true,
}

// codigoUtil degrada códigos placeholder a la descripcion (un nombre
// descriptivo corto es honesto y editable; el tipo/marchas siguen
// alimentando el autollenado). Sin descripcion útil → "" y la opción se
// descarta en el router.
func codigoUtil(codigo, descripcion string) string {
	codigo = strings.TrimSpace(codigo)
	descripcion = strings.TrimSpace(descripcion)
	if codigo == "" || codigosPlaceholder[strings.ToLower(codigo)] {
		if descripcion != "" && !codigosPlaceholder[strings.ToLower(descripcion)] {
			return descripcion
		}
		return ""
	}
	return codigo
}

// parsearOpcionMotor extrae los campos con tolerancia de tipos: Gemini a
// veces devuelve números como strings ("cilindros": "4") y el contrato con
// la app espera números de verdad.
func parsearOpcionMotor(crudo map[string]any) shared.OpcionMotor {
	op := shared.OpcionMotor{Codigo: textoComponente(crudo, "codigo")}
	op.Descripcion = textoComponente(crudo, "descripcion")
	op.Combustible = textoComponente(crudo, "combustible")
	op.Aspiracion = textoComponente(crudo, "aspiracion")
	if v, ok := numeroComponente(crudo, "cilindrada"); ok {
		op.Cilindrada = v
	}
	if v, ok := numeroComponente(crudo, "cilindros"); ok {
		op.Cilindros = int(v)
	}
	if v, ok := numeroTolerante(crudo["potenciaHp"], "HP"); ok {
		op.PotenciaHP = &v
	}
	if v, ok := numeroTolerante(crudo["torqueNm"], "Nm"); ok {
		op.TorqueNm = &v
	}
	op.Codigo = codigoUtil(op.Codigo, op.Descripcion)
	return op
}

// parsearOpcionTransmision extrae los campos con la misma tolerancia.
func parsearOpcionTransmision(crudo map[string]any) shared.OpcionTransmision {
	op := shared.OpcionTransmision{Codigo: textoComponente(crudo, "codigo")}
	op.Descripcion = textoComponente(crudo, "descripcion")
	op.Tipo = textoComponente(crudo, "tipo")
	if v, ok := numeroComponente(crudo, "marchas"); ok {
		op.Marchas = int(v)
	}
	op.Codigo = codigoUtil(op.Codigo, op.Descripcion)
	return op
}

// Un código sin ningún detalle no sirve para auto-rellenar nada — cuenta
// como "no encontrado" (y no se cachea, para reintentar la próxima vez).
func opcionMotorTieneDatos(op shared.OpcionMotor) bool {
	return op.Descripcion != "" || op.Combustible != "" ||
		op.Cilindrada > 0 || op.Cilindros > 0 || op.Aspiracion != "" ||
		op.PotenciaHP != nil || op.TorqueNm != nil
}

func opcionTransmisionTieneDatos(op shared.OpcionTransmision) bool {
	return op.Descripcion != "" || op.Tipo != "" || op.Marchas > 0
}

// textoComponente lee un campo string; cualquier otro tipo → "".
func textoComponente(crudo map[string]any, clave string) string {
	if v, ok := crudo[clave].(string); ok {
		return strings.TrimSpace(v)
	}
	return ""
}

// numeroComponente lee un campo numérico aceptando también strings ("4").
func numeroComponente(crudo map[string]any, clave string) (float64, bool) {
	switch v := crudo[clave].(type) {
	case float64:
		return v, true
	case string:
		f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
		return f, err == nil
	}
	return 0, false
}

// Factores de conversión por unidad declarada en el string, según el
// campo: potenciaHp espera HP y torqueNm espera Nm. Sufijo vacío = el
// número ya está en la unidad esperada (contrato del prompt).
var factoresPotencia = map[string]float64{
	"": 1, "hp": 1, "bhp": 1, "kw": 1.341, "ps": 0.9863, "cv": 0.9863,
}

var factoresTorque = map[string]float64{
	"": 1, "nm": 1, "lbft": 1.3558, "ftlb": 1.3558, "kgm": 9.8067, "kgfm": 9.8067,
}

// numeroTolerante normaliza un campo numérico flexible con unidad
// esperada ("HP" o "Nm"): acepta números JSON o strings con la cantidad
// al inicio. Si el string declara una unidad conocida CONVIERTE con el
// factor exacto ("141 kW" → 189.1 HP); una unidad desconocida se
// rechaza — mejor perder el dato (el campo es opcional) que etiquetarlo
// mal. También se rechazan los formatos ambiguos: coma decimal ("255,5")
// y punto con exactamente 3 decimales ("1.200", ¿miles o decimal?).
func numeroTolerante(v any, unidad string) (float64, bool) {
	var factores map[string]float64
	switch unidad {
	case "HP":
		factores = factoresPotencia
	case "Nm":
		factores = factoresTorque
	default:
		return 0, false // sin vocabulario no hay validación posible
	}

	switch n := v.(type) {
	case float64:
		if n > 0 {
			return n, true
		}
	case string:
		s := strings.TrimSpace(n)
		end := 0
		for end < len(s) && (isDigit(s[end]) || s[end] == '.' || s[end] == ',') {
			end++
		}
		if end == 0 {
			return 0, false
		}
		num := s[:end]

		// Unidad declarada: solo letras, en minúsculas ("LB-FT" → "lbft").
		resto := strings.ToLower(s[end:])
		resto = strings.Map(func(r rune) rune {
			if r >= 'a' && r <= 'z' {
				return r
			}
			return -1
		}, resto)
		factor, ok := factores[resto]
		if !ok {
			return 0, false
		}

		// Coma: solo separador de miles con exactamente 3 dígitos
		// después ("1,255" → 1255). Como decimal es ambigua → rechazar.
		for strings.Contains(num, ",") {
			i := strings.IndexByte(num, ',')
			if i+4 > len(num) ||
				!isDigit(num[i+1]) || !isDigit(num[i+2]) || !isDigit(num[i+3]) {
				return 0, false
			}
			num = num[:i] + num[i+1:]
		}
		// Punto con exactamente 3 decimales y entero de 1-3 dígitos:
		// patrón ambiguo de miles ("1.200") → rechazar. El decimal
		// legítimo ("254.79") tiene otro largo y pasa.
		if i := strings.IndexByte(num, '.'); i >= 0 {
			entero, decimales := num[:i], num[i+1:]
			if len(decimales) == 3 && len(entero) >= 1 && len(entero) <= 3 &&
				strings.IndexByte(decimales, '.') < 0 {
				return 0, false
			}
		}

		f, err := strconv.ParseFloat(num, 64)
		if err != nil || f <= 0 {
			return 0, false
		}
		return f * factor, true
	}
	return 0, false
}

func isDigit(b byte) bool { return b >= '0' && b <= '9' }

// construirPromptComponente pide a Gemini la información de un código
// concreto, con búsqueda web para verificar datos reales.
//
// IMPORTANTE: "combustible" y "tipo" son un contrato con la app móvil
// (enums TipoCombustible y TipoTransmision en app/lib/models/enums.dart) —
// valores fuera de esos conjuntos se ignoran en el cliente.
func construirPromptComponente(tipo, codigo string) string {
	if tipo == "motor" {
		return fmt.Sprintf(`Eres un experto automotriz con acceso a búsqueda web. Investiga este código de motor de fábrica: %s

Usa la búsqueda web para verificar QUÉ motor es ese código EXACTO — no su prefijo ni su familia: códigos parecidos del mismo fabricante pueden ser motores totalmente distintos. En tu búsqueda incluye el código exacto entre comillas (por ejemplo: "%s" motor especificaciones) y decide SOLO con lo que los resultados digan de ese código exacto.

Devuelve EXCLUSIVAMENTE un JSON válido (sin markdown, sin texto adicional) con esta estructura:

{
  "codigo": "%s",
  "descripcion": "descripción corta incluyendo los vehículos que lo usan (ej. 5.7L V8 — Dodge Ram 1500)",
  "combustible": "gasolina | diesel | hibrido | electrico | gas",
  "cilindrada": 1.4,
  "cilindros": 4,
  "aspiracion": "NA | Turbo | Twin-Turbo | Supercharger",
  "potenciaHp": 255,
  "torqueNm": 350
}

Reglas:
- "combustible" DEBE ser exactamente uno de los valores listados (el consumidor lo valida contra un enum estricto).
- "potenciaHp" es la potencia en caballos de fuerza (HP) y "torqueNm" el torque en newton-metro (Nm): números sin unidad. Si la fuente solo da otra unidad, CONVIERTE exactamente con: 1 kW = 1.341 HP; 1 PS (CV) = 0.9863 HP; 1 lb-ft = 1.3558 Nm; 1 kgm = 9.8067 Nm. NUNCA reportes la cifra de otra unidad sin convertir.
- Campos opcionales (descripcion, cilindrada, cilindros, aspiracion, potenciaHp, torqueNm): omítelos si no los conoces con certeza.
- Una fuente debe mencionar EXACTAMENTE el código "%s" para atribuirle especificaciones — el parecido con otros códigos del mismo fabricante NO basta (familias con prefijos comunes mezclan manuales, automáticas y DCT).
- Si ninguna fuente confirma el código exacto, devuelve {"codigo": "%s"} sin más campos. NO inventes.`, codigo, codigo, codigo, codigo, codigo)
	}

	return fmt.Sprintf(`Eres un experto automotriz con acceso a búsqueda web. Investiga este código de transmisión/caja de fábrica: %s

Usa la búsqueda web para verificar QUÉ caja es ese código EXACTO — no su prefijo ni su familia: códigos parecidos del mismo fabricante pueden ser cajas totalmente distintas (manuales, automáticas, DCT...). En tu búsqueda incluye el código exacto entre comillas (por ejemplo: "%s" transmisión) y decide SOLO con lo que los resultados digan de ese código exacto.

Devuelve EXCLUSIVAMENTE un JSON válido (sin markdown, sin texto adicional) con esta estructura:

{
  "codigo": "%s",
  "descripcion": "descripción corta incluyendo los vehículos que la usan (ej. automática 8 velocidades — BMW 328i)",
  "tipo": "manual | automatica | cvt | dct | automatedManual",
  "marchas": 5
}

Reglas:
- "tipo" DEBE ser exactamente uno de los valores listados (el consumidor lo valida contra un enum estricto).
- Campos opcionales (descripcion, marchas): omítelos si no los conoces con certeza.
- Una fuente debe mencionar EXACTAMENTE el código "%s" para atribuirle tipo o marchas — el parecido con otros códigos del mismo fabricante NO basta (familias con prefijos comunes mezclan manuales, automáticas y DCT).
- Si ninguna fuente confirma el código exacto, devuelve {"codigo": "%s"} sin más campos. NO inventes.`, codigo, codigo, codigo, codigo, codigo)
}
