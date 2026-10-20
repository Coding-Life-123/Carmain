package biblioteca

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
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

// geminiApiKey retorna la API key configurada (vacía si no hay).
func geminiApiKey() string {
	return os.Getenv("GEMINI_API_KEY")
}

// geminiModelo retorna el modelo a usar; configurable con GEMINI_MODEL.
func geminiModelo() string {
	m := os.Getenv("GEMINI_MODEL")
	if m == "" {
		m = "gemini-2.5-flash"
	}
	return m
}

// llamarGemini envía un prompt a la API de Gemini con grounding de Google
// Search y retorna el texto de la respuesta (concatenando todas las partes
// de todos los candidatos).
//
// Es el único punto de contacto con la API: tanto la investigación de
// planes como la búsqueda de motorizaciones pasan por aquí.
func llamarGemini(prompt string) (string, error) {
	apiKey := geminiApiKey()
	if apiKey == "" {
		return "", errors.New("GEMINI_API_KEY no configurada")
	}

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

	url := fmt.Sprintf(
		"https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent",
		geminiModelo())

	req, err := http.NewRequest("POST", url, bytes.NewReader(bodyJSON))
	if err != nil {
		return "", fmt.Errorf("error creando request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-goog-api-key", apiKey)

	client := &http.Client{Timeout: 60 * time.Second}
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
