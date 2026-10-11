package biblioteca

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/carmain/servidor-go/shared"
	"github.com/google/uuid"
)

// --- Tipos para la API de Anthropic ---

// anthropicRequest es el cuerpo de la petición a la API de mensajes de Anthropic.
type anthropicRequest struct {
	Model     string        `json:"model"`
	MaxTokens int           `json:"max_tokens"`
	Messages  []anthropicMsg `json:"messages"`
}

type anthropicMsg struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// anthropicResponse es la respuesta de la API de Anthropic.
type anthropicResponse struct {
	ID      string `json:"id"`
	Content []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"content"`
	Model      string `json:"model"`
	StopReason string `json:"stop_reason"`
}

// planIAResponse es la estructura JSON que se le pide a Claude que devuelva.
type planIAResponse struct {
	Items []shared.ItemMantenimiento `json:"items"`
}

// InvestigarPlan genera un plan de mantenimiento preventivo para un vehículo
// usando la API de Anthropic Claude (claude-sonnet-5-5).
//
// Si ANTHROPIC_API_KEY no está configurada, retorna un plan genérico de fallback.
// Si la llamada a la API falla, también retorna el fallback con un log de error.
func InvestigarPlan(config shared.ConfigVehiculo) (*shared.PlanMantenimiento, error) {
	apiKey := os.Getenv("ANTHROPIC_API_KEY")
	if apiKey == "" {
		log.Println("[investigador] ANTHROPIC_API_KEY no configurada, usando plan de fallback")
		return planFallback(config), nil
	}

	plan, err := investigarConClaude(config, apiKey)
	if err != nil {
		log.Printf("[investigador] error llamando a Claude API: %v — usando fallback", err)
		return planFallback(config), nil
	}

	return plan, nil
}

// investigarConClaude llama a la API de Anthropic y parsea la respuesta.
func investigarConClaude(config shared.ConfigVehiculo, apiKey string) (*shared.PlanMantenimiento, error) {
	prompt := construirPrompt(config)

	reqBody := anthropicRequest{
		Model:     "claude-sonnet-5-5",
		MaxTokens: 4096,
		Messages: []anthropicMsg{
			{Role: "user", Content: prompt},
		},
	}

	bodyJSON, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("error marshalling request: %w", err)
	}

	req, err := http.NewRequest("POST", "https://api.anthropic.com/v1/messages", bytes.NewReader(bodyJSON))
	if err != nil {
		return nil, fmt.Errorf("error creando request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", apiKey)
	req.Header.Set("anthropic-version", "2023-06-01")

	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("error en llamada HTTP: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("API respondió %d: %s", resp.StatusCode, string(body))
	}

	var apiResp anthropicResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("error decodeando respuesta: %w", err)
	}

	// Extraer el texto de la primera content block
	if len(apiResp.Content) == 0 {
		return nil, fmt.Errorf("respuesta de Claude sin contenido")
	}
	textoRespuesta := apiResp.Content[0].Text

	// Parsear el JSON que devolvió Claude
	var planResp planIAResponse
	if err := json.Unmarshal([]byte(textoRespuesta), &planResp); err != nil {
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

// construirPrompt genera el prompt para Claude pidiendo un plan de mantenimiento
// estructurado en JSON, adaptado al drivetrain del vehículo.
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
      "categoria": "fluidos | filtros | frenos | suspension | transmision | motor | electrico | neumaticos | general",
      "descripcion": "descripción clara del ítem",
      "componenteAplica": "componente al que aplica",
      "intervaloKm": 10000,
      "intervaloMeses": 12,
      "intervaloSeveroKm": 5000,
      "fuente": "ia",
      "confianza": "alta | media | baja"
    }
  ]
}

Consideraciones:
- Adapta los intervalos al drivetrain (%s): AWD/4WD pueden requerir servicio de diferencial y transfer case.
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
			Categoria:         "fluidos",
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
			Categoria:         "filtros",
			Descripcion:       "Reemplazo de filtro de aire del motor",
			ComponenteAplica:  "motor",
			IntervaloKm:       20000,
			IntervaloMeses:    &meses24,
			IntervaloSeveroKm: &kmSevero10k,
			Fuente:            "ia",
			Confianza:         "alta",
		},
		{
			ID:                "filtro-cabina",
			Categoria:         "filtros",
			Descripcion:       "Reemplazo de filtro de cabina (aire acondicionado)",
			ComponenteAplica:  "habitaculo",
			IntervaloKm:       20000,
			IntervaloMeses:    &meses12,
			Fuente:            "ia",
			Confianza:         "media",
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
			ID:                "frenos-fluido",
			Categoria:         "fluidos",
			Descripcion:       "Cambio de líquido de frenos",
			ComponenteAplica:  "frenos",
			IntervaloKm:       40000,
			IntervaloMeses:    &meses24,
			Fuente:            "ia",
			Confianza:         "alta",
		},
		{
			ID:                "refrigerante",
			Categoria:         "fluidos",
			Descripcion:       "Inspección y cambio de refrigerante",
			ComponenteAplica:  "sistema-enfriamiento",
			IntervaloKm:       40000,
			IntervaloMeses:    &meses24,
			Fuente:            "ia",
			Confianza:         "alta",
		},
		{
			ID:                "bujias",
			Categoria:         "motor",
			Descripcion:       "Reemplazo de bujías de encendido",
			ComponenteAplica:  "motor",
			IntervaloKm:       60000,
			IntervaloMeses:    &meses24,
			Fuente:            "ia",
			Confianza:         "media",
		},
		{
			ID:                "transmision-fluido",
			Categoria:         "transmision",
			Descripcion:       "Cambio de fluido de transmisión",
			ComponenteAplica:  "transmision",
			IntervaloKm:       60000,
			IntervaloMeses:    &meses24,
			Fuente:            "ia",
			Confianza:         "media",
		},
		{
			ID:                "neumaticos-rotacion",
			Categoria:         "neumaticos",
			Descripcion:       "Rotación de neumáticos",
			ComponenteAplica:  "neumaticos",
			IntervaloKm:       10000,
			IntervaloMeses:    &meses6,
			Fuente:            "ia",
			Confianza:         "alta",
		},
		{
			ID:                "bateria",
			Categoria:         "electrico",
			Descripcion:       "Inspección de batería y terminales",
			ComponenteAplica:  "sistema-electrico",
			IntervaloKm:       20000,
			IntervaloMeses:    &meses12,
			Fuente:            "ia",
			Confianza:         "media",
		},
	}

	// Si es AWD o 4WD, agregar servicio de diferencial y transfer case
	if config.Drivetrain == "AWD" || config.Drivetrain == "4WD" {
		items = append(items, shared.ItemMantenimiento{
			ID:                "diferencial-fluido",
			Categoria:         "transmision",
			Descripcion:       "Cambio de fluido de diferencial(es)",
			ComponenteAplica:  "diferencial",
			IntervaloKm:       60000,
			IntervaloMeses:    &meses24,
			Fuente:            "ia",
			Confianza:         "media",
		})
		items = append(items, shared.ItemMantenimiento{
			ID:                "transfer-case",
			Categoria:         "transmision",
			Descripcion:       "Cambio de fluido de transfer case",
			ComponenteAplica:  "transfer-case",
			IntervaloKm:       60000,
			IntervaloMeses:    &meses24,
			Fuente:            "ia",
			Confianza:         "media",
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
