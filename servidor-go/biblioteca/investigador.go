package biblioteca

import (
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/carmain/servidor-go/shared"
	"github.com/google/uuid"
)

// planIAResponse es la estructura JSON que se le pide a Gemini que devuelva.
type planIAResponse struct {
	Items []shared.ItemMantenimiento `json:"items"`
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
		ID:              uuid.NewString(),
		Config:          config,
		Version:         1,
		FechaGeneracion: time.Now(),
		Items:           planResp.Items,
	}

	return plan, nil
}

// construirPrompt genera el prompt para Gemini pidiendo un plan de mantenimiento
// estructurado en JSON, adaptado al drivetrain del vehículo.
//
// IMPORTANTE: los valores de "categoria", "componenteAplica", "fuente" y
// "confianza" son un contrato con la app móvil (enums en app/lib/models/enums.dart).
// El consumidor valida contra enums estrictos — un valor fuera de estos
// conjuntos hace que la app descarte o degrade el ítem.
func construirPrompt(config shared.ConfigVehiculo) string {
	return fmt.Sprintf(`Eres un experto en mantenimiento automotriz. Genera un plan de mantenimiento preventivo para el siguiente vehículo:

- Marca: %s
- Modelo: %s
- Año: %d
- Trim: %s
- Drivetrain: %s
- Código de motor: %s
- Código de transmisión: %s

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
      "confianza": "alta | media | baja"
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
		config.MotorCodigo, config.TransCodigo, config.Drivetrain,
	)
}

// planFallback genera un plan de mantenimiento genérico cuando no hay API key
// o la llamada a Claude falla. Incluye los ítems más comunes con intervalos estándar.
//
// Los valores de Categoria/ComponenteAplica siguen el vocabulario canónico
// del contrato con la app (ver construirPrompt).
func planFallback(config shared.ConfigVehiculo) *shared.PlanMantenimiento {
	meses12 := 12
	meses24 := 24
	meses6 := 6
	kmSevero5k := 5000
	kmSevero10k := 10000
	kmSevero15k := 15000

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
			Descripcion:      "Cambio de fluido de transmisión",
			ComponenteAplica: "transmision",
			IntervaloKm:      60000,
			IntervaloMeses:   &meses24,
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

	// Si es AWD o 4WD, agregar servicio de diferencial y transfer case
	if config.Drivetrain == "AWD" || config.Drivetrain == "4WD" {
		items = append(items, shared.ItemMantenimiento{
			ID:               "diferencial-fluido",
			Categoria:        "diferencial",
			Descripcion:      "Cambio de fluido de diferencial(es)",
			ComponenteAplica: "diferencial",
			IntervaloKm:      60000,
			IntervaloMeses:   &meses24,
			Fuente:           "ia",
			Confianza:        "media",
		})
		items = append(items, shared.ItemMantenimiento{
			ID:               "transfer-case",
			Categoria:        "diferencial",
			Descripcion:      "Cambio de fluido de transfer case",
			ComponenteAplica: "transferCase",
			IntervaloKm:      60000,
			IntervaloMeses:   &meses24,
			Fuente:           "ia",
			Confianza:        "media",
		})
	}

	return &shared.PlanMantenimiento{
		ID:              uuid.NewString(),
		Config:          config,
		Version:         1,
		FechaGeneracion: time.Now(),
		Items:           items,
	}
}
