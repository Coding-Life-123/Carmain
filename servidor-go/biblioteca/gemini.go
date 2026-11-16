package biblioteca

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// --- Tipos para la API de Gemini (Google AI) ---

// geminiRequest es el cuerpo de una petición a generateContent.
type geminiRequest struct {
	Contents []geminiContent `json:"contents"`
	Tools    []geminiTool    `json:"tools,omitempty"`
}

type geminiContent struct {
	Role  string       `json:"role"`
	Parts []geminiPart `json:"parts"`
}

type geminiPart struct {
	Text string `json:"text"`
}

// geminiTool activa el grounding con Google Search — la "búsqueda web"
// del proyecto. Sin ella, Gemini responde solo desde su conocimiento.
type geminiTool struct {
	GoogleSearch map[string]any `json:"google_search,omitempty"`
}

// geminiResponse es la parte de la respuesta que nos interesa: el texto
// de cada candidato (el metadata de grounding viaja aparte y se ignora).
type geminiResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
}

var (
	ruletaMu       sync.Mutex
	indiceClave    int
	geminiBaseURL  string // para testing; si está vacía usa el endpoint oficial de Google
	httpClientMock *http.Client
)

// geminiApiKeys retorna la lista de API keys configuradas en el entorno.
// Admite claves numeradas (API_KEY1..API_KEY4, GEMINI_API_KEY1..),
// una lista separada por comas (GEMINI_API_KEYS) o una clave única (GEMINI_API_KEY).
func geminiApiKeys() []string {
	var keys []string
	for i := 1; i <= 20; i++ {
		k := strings.TrimSpace(os.Getenv(fmt.Sprintf("API_KEY%d", i)))
		if k == "" {
			k = strings.TrimSpace(os.Getenv(fmt.Sprintf("GEMINI_API_KEY%d", i)))
		}
		if k == "" {
			k = strings.TrimSpace(os.Getenv(fmt.Sprintf("API_KEY_%d", i)))
		}
		if k == "" {
			k = strings.TrimSpace(os.Getenv(fmt.Sprintf("GEMINI_API_KEY_%d", i)))
		}
		if k != "" {
			keys = append(keys, k)
		}
	}

	if raw := strings.TrimSpace(os.Getenv("GEMINI_API_KEYS")); raw != "" {
		for _, part := range strings.Split(raw, ",") {
			part = strings.TrimSpace(part)
			if part != "" {
				keys = append(keys, part)
			}
		}
	}

	if single := strings.TrimSpace(os.Getenv("GEMINI_API_KEY")); single != "" {
		yaExiste := false
		for _, exist := range keys {
			if exist == single {
				yaExiste = true
				break
			}
		}
		if !yaExiste {
			keys = append(keys, single)
		}
	}

	return keys
}

// geminiApiKey retorna la clave activa de Gemini (vacía si no hay ninguna configurada).
// Mantiene compatibilidad con las comprobaciones "if geminiApiKey() == ''"
// en investigador, motorizacion y componente.
func geminiApiKey() string {
	keys := geminiApiKeys()
	if len(keys) == 0 {
		return ""
	}
	ruletaMu.Lock()
	defer ruletaMu.Unlock()
	return keys[indiceClave%len(keys)]
}

// geminiModelo retorna el modelo a usar; configurable con GEMINI_MODEL.
func geminiModelo() string {
	m := os.Getenv("GEMINI_MODEL")
	if m == "" {
		m = "gemini-2.5-flash"
	}
	return m
}

// ejecutarLlamadaGemini hace la petición HTTP a la API de Gemini con una clave concreta.
func ejecutarLlamadaGemini(prompt, apiKey string) (string, error) {
	reqBody := geminiRequest{
		Contents: []geminiContent{{
			Role:  "user",
			Parts: []geminiPart{{Text: prompt}},
		}},
		Tools: []geminiTool{{GoogleSearch: map[string]any{}}},
	}

	bodyJSON, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("error marshalling request: %w", err)
	}

	endpoint := geminiBaseURL
	if endpoint == "" {
		endpoint = fmt.Sprintf(
			"https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent",
			geminiModelo())
	}

	req, err := http.NewRequest("POST", endpoint, bytes.NewReader(bodyJSON))
	if err != nil {
		return "", fmt.Errorf("error creando request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-goog-api-key", apiKey)

	client := httpClientMock
	if client == nil {
		client = &http.Client{Timeout: 60 * time.Second}
	}

	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("error en llamada HTTP: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("Gemini respondió %d: %s", resp.StatusCode, string(body))
	}

	var apiResp geminiResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return "", fmt.Errorf("error decodeando respuesta: %w", err)
	}

	var sb strings.Builder
	for _, cand := range apiResp.Candidates {
		for _, part := range cand.Content.Parts {
			sb.WriteString(part.Text)
		}
	}
	texto := strings.TrimSpace(sb.String())
	if texto == "" {
		return "", errors.New("respuesta de Gemini sin contenido")
	}

	return texto, nil
}

// llamarGemini envía un prompt a la API de Gemini con grounding de Google Search.
// Implementa un sistema de ruleta (round-robin con failover):
// Si una API_KEY falla (ej. rate limit 429, cuota agotada o error de red),
// automáticamente rota a la siguiente clave (API_KEY1 -> API_KEY2 -> ... -> API_KEY4 -> API_KEY1)
// hasta agotar todas las claves configuradas.
func llamarGemini(prompt string) (string, error) {
	keys := geminiApiKeys()
	if len(keys) == 0 {
		return "", errors.New("GEMINI_API_KEY no configurada")
	}

	ruletaMu.Lock()
	idxInicio := indiceClave % len(keys)
	ruletaMu.Unlock()

	var ultimoErr error
	for i := 0; i < len(keys); i++ {
		idxActual := (idxInicio + i) % len(keys)
		clave := keys[idxActual]
		numClave := idxActual + 1

		log.Printf("[gemini] llamando API con API_KEY%d (%s)...", numClave, enmascararClave(clave))
		texto, err := ejecutarLlamadaGemini(prompt, clave)
		if err == nil {
			ruletaMu.Lock()
			indiceClave = idxActual
			ruletaMu.Unlock()
			if i > 0 {
				log.Printf("[gemini] llamada exitosa tras rotar a API_KEY%d (%s)", numClave, enmascararClave(clave))
			}
			return texto, nil
		}

		ultimoErr = err
		log.Printf("[gemini] fallo con API_KEY%d (%s): %v — rotando a la siguiente clave",
			numClave, enmascararClave(clave), err)

		ruletaMu.Lock()
		indiceClave = (idxActual + 1) % len(keys)
		ruletaMu.Unlock()
	}

	return "", fmt.Errorf("todas las API keys de Gemini fallaron (%d probadas, último error: %w)", len(keys), ultimoErr)
}

// extraerJSON toma el texto de una respuesta de IA y extrae el objeto JSON
// que contenga — por si viene envuelto en markdown (```json ... ```) o con
// texto adicional alrededor.
//
// Dos estrategias, en orden:
//  1. Bloque de código ```json ... ``` si existe — el caso más común cuando
//     la IA ignora la instrucción de responder solo JSON.
//  2. El primer objeto balanceado consciente de strings: una llave suelta
//     en la prosa posterior ("...intervalos en {km}") no contamina el
//     corte como con el esquema primer-'{'-a-último-'}'.
func extraerJSON(texto string) string {
	texto = strings.TrimSpace(texto)

	if i := strings.Index(texto, "```"); i >= 0 {
		resto := texto[i+3:]
		if len(resto) >= 4 && strings.EqualFold(resto[:4], "json") {
			resto = resto[4:]
		}
		if j := strings.Index(resto, "```"); j >= 0 {
			if bloque := strings.TrimSpace(resto[:j]); bloque != "" {
				return bloque
			}
		}
	}

	if i := strings.Index(texto, "{"); i >= 0 {
		profundidad := 0
		enCadena := false
		escape := false
		for j := i; j < len(texto); j++ {
			c := texto[j]
			switch {
			case enCadena:
				if escape {
					escape = false
				} else if c == '\\' {
					escape = true
				} else if c == '"' {
					enCadena = false
				}
			case c == '"':
				enCadena = true
			case c == '{':
				profundidad++
			case c == '}':
				profundidad--
				if profundidad == 0 {
					return texto[i : j+1]
				}
			}
		}
	}

	return texto
}
