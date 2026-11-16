package biblioteca

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

func TestGeminiApiKeysDeteccion(t *testing.T) {
	// Limpiar variables primero
	t.Setenv("GEMINI_API_KEY", "")
	t.Setenv("GEMINI_API_KEYS", "")
	t.Setenv("API_KEY1", "key-1")
	t.Setenv("API_KEY2", "key-2")
	t.Setenv("API_KEY3", "key-3")
	t.Setenv("API_KEY4", "key-4")

	keys := geminiApiKeys()
	if len(keys) != 4 {
		t.Fatalf("esperadas 4 keys, got %d", len(keys))
	}
	if keys[0] != "key-1" || keys[1] != "key-2" || keys[2] != "key-3" || keys[3] != "key-4" {
		t.Errorf("orden o valores de keys incorrectos: %v", keys)
	}
}

func TestRuletaRotacionAnteFallo(t *testing.T) {
	t.Setenv("API_KEY1", "key-1")
	t.Setenv("API_KEY2", "key-2")
	t.Setenv("API_KEY3", "key-3")
	t.Setenv("API_KEY4", "key-4")
	t.Setenv("GEMINI_API_KEY", "")

	ruletaMu.Lock()
	indiceClave = 0
	ruletaMu.Unlock()

	var intentosMu sync.Mutex
	keysRecibidas := []string{}

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		intentosMu.Lock()
		apiKey := r.Header.Get("x-goog-api-key")
		keysRecibidas = append(keysRecibidas, apiKey)
		intentosMu.Unlock()

		if apiKey == "key-1" {
			// Simular fallo (rate limit 429) en la primera clave
			w.WriteHeader(http.StatusTooManyRequests)
			w.Write([]byte(`{"error": "Resource exhausted"}`))
			return
		}

		// La segunda clave responde con éxito
		resp := geminiResponse{
			Candidates: []struct {
				Content struct {
					Parts []struct {
						Text string `json:"text"`
					} `json:"parts"`
				} `json:"content"`
			}{
				{
					Content: struct {
						Parts []struct {
							Text string `json:"text"`
						} `json:"parts"`
					}{
						Parts: []struct {
							Text string `json:"text"`
						}{
							{Text: `{"resultado": "ok"}`},
						},
					},
				},
			},
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}))
	defer ts.Close()

	geminiBaseURL = ts.URL
	defer func() { geminiBaseURL = "" }()

	res, err := llamarGemini("test prompt")
	if err != nil {
		t.Fatalf("llamada falló inesperadamente: %v", err)
	}

	if !strings.Contains(res, "resultado") {
		t.Errorf("respuesta inesperada: %s", res)
	}

	intentosMu.Lock()
	defer intentosMu.Unlock()

	if len(keysRecibidas) != 2 {
		t.Fatalf("se esperaban 2 intentos, se hicieron %d: %v", len(keysRecibidas), keysRecibidas)
	}
	if keysRecibidas[0] != "key-1" || keysRecibidas[1] != "key-2" {
		t.Errorf("secuencia de claves recibidas incorrecta: %v", keysRecibidas)
	}

	// El índice activo debe quedar en la clave 2 (índice 1)
	ruletaMu.Lock()
	activo := indiceClave
	ruletaMu.Unlock()
	if activo != 1 {
		t.Errorf("el índice activo esperado es 1 (key-2), got %d", activo)
	}
}

func TestRuletaVuelveAKey1DesdeKey4(t *testing.T) {
	t.Setenv("API_KEY1", "key-1")
	t.Setenv("API_KEY2", "key-2")
	t.Setenv("API_KEY3", "key-3")
	t.Setenv("API_KEY4", "key-4")
	t.Setenv("GEMINI_API_KEY", "")

	// Empezar deliberadamente en key-4 (índice 3)
	ruletaMu.Lock()
	indiceClave = 3
	ruletaMu.Unlock()

	var intentosMu sync.Mutex
	keysRecibidas := []string{}

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		intentosMu.Lock()
		apiKey := r.Header.Get("x-goog-api-key")
		keysRecibidas = append(keysRecibidas, apiKey)
		intentosMu.Unlock()

		if apiKey == "key-4" {
			// Simular fallo en la última clave
			w.WriteHeader(http.StatusTooManyRequests)
			w.Write([]byte(`{"error": "Resource exhausted"}`))
			return
		}

		if apiKey == "key-1" {
			// key-1 responde con éxito tras el ciclo
			resp := geminiResponse{
				Candidates: []struct {
					Content struct {
						Parts []struct {
							Text string `json:"text"`
						} `json:"parts"`
					} `json:"content"`
				}{
					{
						Content: struct {
							Parts []struct {
								Text string `json:"text"`
							} `json:"parts"`
						}{
							Parts: []struct {
								Text string `json:"text"`
							}{
								{Text: `{"resultado": "vuelto_a_key1"}`},
							},
						},
					},
				},
			}
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(resp)
			return
		}

		w.WriteHeader(http.StatusBadRequest)
	}))
	defer ts.Close()

	geminiBaseURL = ts.URL
	defer func() { geminiBaseURL = "" }()

	res, err := llamarGemini("test prompt")
	if err != nil {
		t.Fatalf("llamada falló inesperadamente: %v", err)
	}

	if !strings.Contains(res, "vuelto_a_key1") {
		t.Errorf("respuesta inesperada: %s", res)
	}

	intentosMu.Lock()
	defer intentosMu.Unlock()

	if len(keysRecibidas) != 2 {
		t.Fatalf("se esperaban 2 intentos (key-4 -> key-1), se hicieron %d: %v", len(keysRecibidas), keysRecibidas)
	}
	if keysRecibidas[0] != "key-4" || keysRecibidas[1] != "key-1" {
		t.Errorf("secuencia de claves recibidas incorrecta: %v (esperado [key-4, key-1])", keysRecibidas)
	}
}

func TestRuletaTodasFallan(t *testing.T) {
	t.Setenv("API_KEY1", "key-1")
	t.Setenv("API_KEY2", "key-2")
	t.Setenv("API_KEY3", "key-3")
	t.Setenv("API_KEY4", "key-4")
	t.Setenv("GEMINI_API_KEY", "")

	ruletaMu.Lock()
	indiceClave = 0
	ruletaMu.Unlock()

	var intentosMu sync.Mutex
	keysRecibidas := []string{}

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		intentosMu.Lock()
		keysRecibidas = append(keysRecibidas, r.Header.Get("x-goog-api-key"))
		intentosMu.Unlock()
		w.WriteHeader(http.StatusTooManyRequests)
		w.Write([]byte(`{"error": "All exhausted"}`))
	}))
	defer ts.Close()

	geminiBaseURL = ts.URL
	defer func() { geminiBaseURL = "" }()

	_, err := llamarGemini("test prompt")
	if err == nil {
		t.Fatal("se esperaba error ya que todas las claves fallaron")
	}

	intentosMu.Lock()
	defer intentosMu.Unlock()

	if len(keysRecibidas) != 4 {
		t.Fatalf("se esperaban exactamente 4 intentos (todas las claves), se hicieron %d: %v", len(keysRecibidas), keysRecibidas)
	}
	if keysRecibidas[0] != "key-1" || keysRecibidas[1] != "key-2" || keysRecibidas[2] != "key-3" || keysRecibidas[3] != "key-4" {
		t.Errorf("orden de intentos incorrecto: %v", keysRecibidas)
	}
}
