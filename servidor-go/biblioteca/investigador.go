package biblioteca

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/carmain/servidor-go/shared"
	"github.com/google/uuid"
)

// planIAResponse es la estructura JSON que se le pide a Gemini que devuelva.
type planIAResponse struct {
	Items             []shared.ItemMantenimiento `json:"items"`
	AlertasIngenieria []shared.AlertaIngenieria  `json:"alertasIngenieria,omitempty"`
}

// InvestigarPlan genera un plan de mantenimiento preventivo para un vehículo
// usando la API de Gemini con búsqueda web (grounding con Google Search).
//
// El segundo valor de retorno indica si el plan es un fallback genérico
// (sin GEMINI_API_KEY o fallo de Gemini). El handler NO cachea los
// fallbacks: un 429 o timeout transitorio no debe dejar envenenada la
// cache con un plan genérico para esa configuración hasta reiniciar el
// proceso — la próxima solicitud reintenta la investigación.
func InvestigarPlan(config shared.ConfigVehiculo) (*shared.PlanMantenimiento, bool, error) {
	if geminiApiKey() == "" {
		log.Println("[investigador] GEMINI_API_KEY no configurada, usando plan de fallback")
		return planFallback(config), true, nil
	}

	plan, err := investigarConGemini(config)
	if err != nil {
		log.Printf("[investigador] error llamando a Gemini: %v — usando fallback", err)
		return planFallback(config), true, nil
	}

	return plan, false, nil
}

// investigarConGemini llama a la API de Gemini y parsea la respuesta.
func investigarConGemini(config shared.ConfigVehiculo) (*shared.PlanMantenimiento, error) {
	texto, err := llamarGemini(construirPrompt(config))
	if err != nil {
		return nil, err
	}

	// Parsear el JSON que devolvió Gemini (extraerJSON limpia markdown
	// o texto adicional alrededor del objeto).
	var planResp planIAResponse
	if err := json.Unmarshal([]byte(extraerJSON(texto)), &planResp); err != nil {
		return nil, fmt.Errorf("error parseando JSON del plan: %w", err)
	}

	// Construir el plan final
	plan := &shared.PlanMantenimiento{
		ID:                uuid.NewString(),
		Config:            config,
		Version:           1,
		FechaGeneracion:   time.Now(),
		Items:             planResp.Items,
		AlertasIngenieria: planResp.AlertasIngenieria,
	}

	return plan, nil
}

func valorIntStr(p *int) string {
	if p == nil {
		return "N/D"
	}
	return fmt.Sprintf("%d", *p)
}

func valorFloatStr(p *float64) string {
	if p == nil {
		return "N/D"
	}
	return fmt.Sprintf("%.1f", *p)
}

// construirPrompt genera el prompt para Gemini pidiendo un plan de mantenimiento
// estructurado en JSON, adaptado al drivetrain del vehículo y a la detección de swaps.
//
// IMPORTANTE: los valores de "categoria", "componenteAplica", "fuente" y
// "confianza" son un contrato con la app móvil (enums en app/lib/models/enums.dart).
// El consumidor valida contra enums estrictos — un valor fuera de estos
// conjuntos hace que la app descarte o degrade el ítem.
func construirPrompt(config shared.ConfigVehiculo) string {
	extraSwap := ""
	if config.MotorEsSwap || config.TransEsSwap {
		extraSwap = fmt.Sprintf(`
VEHÍCULO MODIFICADO CON SWAP:
- Motor Swap: %t (Código actual: %s, Código OEM original: %s)
- Transmisión Swap: %t (Código actual: %s, Código OEM original: %s)
- Combustible: %s, Cilindrada: %s L, Cilindros: %s, Aspiración: %s
- Potencia estimada: %s HP, Torque estimado: %s Nm

INSTRUCCIÓN ESPECIAL DE INGENIERÍA PARA SWAPS:
Este vehículo tiene un tren motriz modificado. Evalúa la asimetría mecánica y cuellos de botella según estos 6 vectores:
1. "torqueDiferencial": Esfuerzo de par sobre corona/piñón y semiejes del chasis.
2. "limiteTransmision": Límite de torque de la caja y fatiga del embrague.
3. "disipacionTermica": Carga térmica para el radiador OEM (especialmente si es turbo o mayor cilindrada).
4. "frenadoMasa": Fatiga de frenos OEM y bujes de tren delantero ante mayor velocidad/masa.
5. "alimentacionCombustible": Caudal de bomba de combustible para evitar mezclas pobres (lean-out).
6. "soportesNvh": Torsión sobre patas de motor adaptadas, cardán y subchasis.

En el JSON debes:
1. Acortar el intervalo de fluido de transmisión y diferencial a 20.000 - 30.000 km (especificando fluido sintético de extrema presión).
2. Incluir ítems preventivos de vigilancia ("esVigilanciaSwap": true):
   - Inspección de tapón magnético en caja y diferencial para detectar viruta/limalla.
   - Re-torqueo de soportes de motor/caja, cardán y subchasis (cada 10.000 km o 6 meses).
   - Inspección de homocinéticas, crucetas y bujes de tren trasero.
   - Si es turbo/sobrealimentado: inspección de mangueras de intercooler, abrazaderas y líneas de combustible.
3. Generar el arreglo "alertasIngenieria" con los cuellos de botella detectados para esta combinación chasis-motor-caja.
`,
			config.MotorEsSwap, config.MotorCodigo, config.MotorOriginal,
			config.TransEsSwap, config.TransCodigo, config.TransOriginal,
			config.Combustible, valorFloatStr(config.Cilindrada), valorIntStr(config.Cilindros), config.Aspiracion,
			valorIntStr(config.PotenciaHP), valorIntStr(config.TorqueNm),
		)
	}

	return fmt.Sprintf(`Eres un experto en mantenimiento e ingeniería automotriz. Genera un plan de mantenimiento preventivo para el siguiente vehículo:

- Marca: %s
- Modelo: %s
- Año: %d
- Trim: %s
- Drivetrain: %s
- Código de motor: %s
- Código de transmisión: %s
%s
Devuelve EXCLUSIVAMENTE un JSON válido (sin markdown, sin texto adicional) con esta estructura:

{
  "items": [
    {
      "id": "identificador-unico",
      "categoria": "motor | transmision | frenos | refrigeracion | diferencial | suspension | neumaticos | electrico | escape | inspeccion",
      "descripcion": "descripción clara del ítem",
      "componenteAplica": "motor | transmision | diferencial | transferCase | frenos | suspension | otro",
      "intervaloKm": 10000,
      "intervaloMeses": 12,
      "intervaloSeveroKm": 5000,
      "fuente": "ia",
      "confianza": "alta | media | baja",
      "esVigilanciaSwap": false
    }
  ],
  "alertasIngenieria": [
    {
      "id": "alerta-1",
      "vector": "torqueDiferencial | limiteTransmision | disipacionTermica | frenadoMasa | alimentacionCombustible | soportesNvh",
      "severidad": "alta | media | recomendacion",
      "componenteAfectado": "nombre del componente",
      "titulo": "título corto de la alerta",
      "diagnostico": "explicación técnica del cuello de botella",
      "recomendacionUpgrade": "recomendación de pieza reforzada o procedimiento"
    }
  ]
}

"categoria" y "componenteAplica" DEBEN ser exactamente uno de los valores listados (sin traducir, sin variantes). Guía de clasificación:
- Aceite de motor, filtros del motor (aire/aceite/combustible), bujías → categoria "motor", componenteAplica "motor"
- Líquido, pastillas y discos de freno → categoria "frenos", componenteAplica "frenos"
- Refrigerante → categoria "refrigeracion", componenteAplica "motor"
- Fluido de transmisión → categoria "transmision", componenteAplica "transmision"
- Fluido de diferencial → categoria "diferencial", componenteAplica "diferencial"
- Transfer case → categoria "diferencial", componenteAplica "transferCase"
- Rotación y reemplazo de neumáticos → categoria "neumaticos", componenteAplica "otro"
- Batería y sistema eléctrico → categoria "electrico", componenteAplica "otro"
- Filtro de cabina y chequeos generales → categoria "inspeccion", componenteAplica "otro"

Consideraciones:
- "intervaloKm" es obligatorio y numérico en todos los ítems.
- Adapta los intervalos al drivetrain (%s): AWD/4WD requieren servicio de diferencial y transfer case.
- Incluye los ítems esenciales: aceite de motor, filtros (aire, aceite, combustible, cabina), frenos, líquido de frenos, refrigerante, bujías, transmisión, batería, neumáticos.
- Para servicio severo (intervaloSeveroKm), considera condiciones de mucho polvo, remolque, tráfico pesado.
- Los intervalos deben ser realistas y basados en buenas prácticas de la industria.
- Asigna "confianza": "alta" para ítems estándar, "media" para ítems que dependen del uso, "baja" si hay incertidumbre.
- Usa "fuente": "ia" para todos los ítems.`,
		config.Marca, config.Modelo, config.Anio, config.Trim, config.Drivetrain,
		config.MotorCodigo, config.TransCodigo, extraSwap, config.Drivetrain,
	)
}

// planFallback genera un plan de mantenimiento genérico cuando no hay API key
// o la llamada a Gemini falla. Incluye los ítems más comunes con intervalos estándar
// e ítems de vigilancia y alertas de ingeniería si el vehículo tiene swaps.
func planFallback(config shared.ConfigVehiculo) *shared.PlanMantenimiento {
	meses12 := 12
	meses24 := 24
	meses6 := 6
	kmSevero5k := 5000
	kmSevero10k := 10000
	kmSevero15k := 15000

	kmTransmision := 60000
	mesesTransmision := meses24
	if config.MotorEsSwap || config.TransEsSwap {
		kmTransmision = 25000
		mesesTransmision = meses12
	}

	items := []shared.ItemMantenimiento{
		{
			ID:                "aceite-motor",
			Categoria:         "motor",
			Descripcion:       "Cambio de aceite de motor y filtro",
			ComponenteAplica:  "motor",
			IntervaloKm:       10000,
			IntervaloMeses:    &meses12,
			IntervaloSeveroKm: &kmSevero5k,
			Fuente:            "ia",
			Confianza:         "alta",
		},
		{
			ID:                "filtro-aire",
			Categoria:         "motor",
			Descripcion:       "Reemplazo de filtro de aire del motor",
			ComponenteAplica:  "motor",
			IntervaloKm:       20000,
			IntervaloMeses:    &meses24,
			IntervaloSeveroKm: &kmSevero10k,
			Fuente:            "ia",
			Confianza:         "alta",
		},
		{
			ID:               "filtro-cabina",
			Categoria:        "inspeccion",
			Descripcion:      "Reemplazo de filtro de cabina (aire acondicionado)",
			ComponenteAplica: "otro",
			IntervaloKm:      20000,
			IntervaloMeses:   &meses12,
			Fuente:           "ia",
			Confianza:        "media",
		},
		{
			ID:                "frenos-pastillas",
			Categoria:         "frenos",
			Descripcion:       "Inspección y posible reemplazo de pastillas de freno",
			ComponenteAplica:  "frenos",
			IntervaloKm:       30000,
			IntervaloMeses:    &meses24,
			IntervaloSeveroKm: &kmSevero15k,
			Fuente:            "ia",
			Confianza:         "media",
		},
		{
			ID:               "frenos-fluido",
			Categoria:        "frenos",
			Descripcion:      "Cambio de líquido de frenos",
			ComponenteAplica: "frenos",
			IntervaloKm:      40000,
			IntervaloMeses:   &meses24,
			Fuente:           "ia",
			Confianza:        "alta",
		},
		{
			ID:               "refrigerante",
			Categoria:        "refrigeracion",
			Descripcion:      "Inspección y cambio de refrigerante",
			ComponenteAplica: "motor",
			IntervaloKm:      40000,
			IntervaloMeses:   &meses24,
			Fuente:           "ia",
			Confianza:        "alta",
		},
		{
			ID:               "bujias",
			Categoria:        "motor",
			Descripcion:      "Reemplazo de bujías de encendido",
			ComponenteAplica: "motor",
			IntervaloKm:      60000,
			IntervaloMeses:   &meses24,
			Fuente:           "ia",
			Confianza:        "media",
		},
		{
			ID:               "transmision-fluido",
			Categoria:        "transmision",
			Descripcion:      "Cambio de fluido de transmisión (sintético)",
			ComponenteAplica: "transmision",
			IntervaloKm:      kmTransmision,
			IntervaloMeses:   &mesesTransmision,
			Fuente:           "ia",
			Confianza:        "media",
		},
		{
			ID:               "neumaticos-rotacion",
			Categoria:        "neumaticos",
			Descripcion:      "Rotación de neumáticos",
			ComponenteAplica: "otro",
			IntervaloKm:      10000,
			IntervaloMeses:   &meses6,
			Fuente:           "ia",
			Confianza:        "alta",
		},
		{
			ID:               "bateria",
			Categoria:        "electrico",
			Descripcion:      "Inspección de batería y terminales",
			ComponenteAplica: "otro",
			IntervaloKm:      20000,
			IntervaloMeses:   &meses12,
			Fuente:           "ia",
			Confianza:        "media",
		},
	}

	// Si es AWD o 4WD o RWD con swap, agregar servicio de diferencial
	kmDiferencial := 60000
	mesesDiferencial := meses24
	if config.MotorEsSwap || config.TransEsSwap {
		kmDiferencial = 25000
		mesesDiferencial = meses12
	}

	if config.Drivetrain == "AWD" || config.Drivetrain == "4WD" || (config.Drivetrain == "RWD" && (config.MotorEsSwap || config.TransEsSwap)) {
		items = append(items, shared.ItemMantenimiento{
			ID:               "diferencial-fluido",
			Categoria:        "diferencial",
			Descripcion:      "Cambio de fluido de diferencial (extrema presión / LSD)",
			ComponenteAplica: "diferencial",
			IntervaloKm:      kmDiferencial,
			IntervaloMeses:   &mesesDiferencial,
			Fuente:           "ia",
			Confianza:        "media",
		})
	}
	if config.Drivetrain == "AWD" || config.Drivetrain == "4WD" {
		items = append(items, shared.ItemMantenimiento{
			ID:               "transfer-case",
			Categoria:        "diferencial",
			Descripcion:      "Cambio de fluido de transfer case",
			ComponenteAplica: "transferCase",
			IntervaloKm:      kmDiferencial,
			IntervaloMeses:   &mesesDiferencial,
			Fuente:           "ia",
			Confianza:        "media",
		})
	}

	var alertas []shared.AlertaIngenieria
	if config.MotorEsSwap || config.TransEsSwap {
		// Ítems de vigilancia swap
		items = append(items, shared.ItemMantenimiento{
			ID:               "swap-tapon-magnetico",
			Categoria:        "transmision",
			Descripcion:      "Inspección de tapón magnético en transmisión y diferencial (búsqueda de virutas)",
			ComponenteAplica: "transmision",
			IntervaloKm:      15000,
			IntervaloMeses:   &meses12,
			EsVigilanciaSwap: true,
			Fuente:           "ia",
			Confianza:        "alta",
		})
		items = append(items, shared.ItemMantenimiento{
			ID:               "swap-retorqueo-soportes",
			Categoria:        "inspeccion",
			Descripcion:      "Re-torqueo de soportes de motor, transmisión, cardán y subchasis",
			ComponenteAplica: "otro",
			IntervaloKm:      10000,
			IntervaloMeses:   &meses6,
			EsVigilanciaSwap: true,
			Fuente:           "ia",
			Confianza:        "alta",
		})
		items = append(items, shared.ItemMantenimiento{
			ID:               "swap-inspeccion-semiejes",
			Categoria:        "suspension",
			Descripcion:      "Inspección de juntas homocinéticas, crucetas y bujes de tren trasero",
			ComponenteAplica: "diferencial",
			IntervaloKm:      15000,
			IntervaloMeses:   &meses12,
			EsVigilanciaSwap: true,
			Fuente:           "ia",
			Confianza:        "alta",
		})

		if strings.Contains(strings.ToLower(config.Aspiracion), "turbo") || strings.Contains(strings.ToLower(config.Aspiracion), "supercharger") {
			items = append(items, shared.ItemMantenimiento{
				ID:               "swap-lineas-presion",
				Categoria:        "inspeccion",
				Descripcion:      "Inspección de mangueras de intercooler, abrazaderas y líneas de combustible",
				ComponenteAplica: "motor",
				IntervaloKm:      10000,
				IntervaloMeses:   &meses6,
				EsVigilanciaSwap: true,
				Fuente:           "ia",
				Confianza:        "alta",
			})
		}

		// Alertas de ingeniería para el swap
		alertas = append(alertas, shared.AlertaIngenieria{
			ID:                   "alerta-diff",
			Vector:               "torqueDiferencial",
			Severidad:            "alta",
			ComponenteAfectado:   "Diferencial y Semiejes",
			Titulo:               "Sobrecarga de par torsional sobre diferencial original",
			Diagnostico:          "El incremento de torque del motor actual somete a esfuerzo severo los semiejes y la relación piñón-corona diseñados para el motor OEM.",
			RecomendacionUpgrade: "Inspeccionar limalla en tapón magnético y evaluar upgrade a diferencial LSD reforzado.",
		})
		alertas = append(alertas, shared.AlertaIngenieria{
			ID:                   "alerta-soportes",
			Vector:               "soportesNvh",
			Severidad:            "media",
			ComponenteAfectado:   "Soportes de motor y subchasis",
			Titulo:               "Fatiga en soportes adaptadores y bujes",
			Diagnostico:          "Las patas de motor adaptadas transmiten mayor vibración y torsión al subchasis delantero.",
			RecomendacionUpgrade: "Re-torqueo periódico y uso de bujes de poliuretano de dureza intermedia.",
		})
		alertas = append(alertas, shared.AlertaIngenieria{
			ID:                   "alerta-termica",
			Vector:               "disipacionTermica",
			Severidad:            "media",
			ComponenteAfectado:   "Sistema de Refrigeración",
			Titulo:               "Disipación térmica en vano motor",
			Diagnostico:          "Mayor densidad de potencia requiere controlar picos de temperatura en aceite y refrigerante.",
			RecomendacionUpgrade: "Radiador de aluminio de mayor capacidad y líquido refrigerante de alto rendimiento.",
		})
	}

	return &shared.PlanMantenimiento{
		ID:                uuid.NewString(),
		Config:            config,
		Version:           1,
		FechaGeneracion:   time.Now(),
		Items:             items,
		AlertasIngenieria: alertas,
	}
}
