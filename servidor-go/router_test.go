package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/carmain/servidor-go/seguridad"
	"github.com/gin-gonic/gin"
)

// Tests de integración del cableado completo (nuevoRouter): health
// público, auth en el resto, caps y rate limit a través del router.
// Con GEMINI_API_KEY vacía los handlers responden offline (planes
// fallback, listas vacías) — ningún test toca la red.

const paramsPlan = "/api/plan?marca=Renault&modelo=Megane&anio=2012&drivetrain=FWD&motorCodigo=K4J&transCodigo=JR5"

func pedirJSON(r *gin.Engine, metodo, ruta, apiKey, body string) *httptest.ResponseRecorder {
	var req *http.Request
	if body != "" {
		req = httptest.NewRequest(metodo, ruta, bytes.NewBufferString(body))
		req.Header.Set("Content-Type", "application/json")
	} else {
		req = httptest.NewRequest(metodo, ruta, nil)
	}
	if apiKey != "" {
		req.Header.Set("X-Api-Key", apiKey)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestHealthPublicoSinKey(t *testing.T) {
	t.Setenv("GEMINI_API_KEY", "")
	r := nuevoRouter("secreta", seguridad.NewRateLimiter(60, time.Minute))

	w := pedirJSON(r, http.MethodGet, "/api/health", "", "")
	if w.Code != http.StatusOK {
		t.Fatalf("health esperado 200, got %d", w.Code)
	}
	if !strings.Contains(w.Body.String(), `"ok"`) {
		t.Errorf("health debe devolver status ok, got %s", w.Body.String())
	}
}

func TestEndpointsProtegidosSinKey401(t *testing.T) {
	t.Setenv("GEMINI_API_KEY", "")
	r := nuevoRouter("secreta", seguridad.NewRateLimiter(60, time.Minute))

	rutas := []struct{ metodo, ruta string }{
		{http.MethodGet, paramsPlan},
		{http.MethodGet, "/api/motorizacion?marca=A&modelo=B&anio=2000"},
		{http.MethodGet, "/api/componente?tipo=motor&codigo=K4J"},
		{http.MethodPost, "/api/sesion"},
		{http.MethodGet, "/relay?sesion=x"},
	}
	for _, ruta := range rutas {
		w := pedirJSON(r, ruta.metodo, ruta.ruta, "", "")
		if w.Code != http.StatusUnauthorized {
			t.Errorf("%s sin key esperado 401, got %d", ruta.ruta, w.Code)
		}
		if !strings.Contains(w.Body.String(), "API key") {
			t.Errorf("%s: el 401 debe venir del middleware de auth, got %s",
				ruta.ruta, w.Body.String())
		}
	}
}

func TestPlanConKeyCorrecta(t *testing.T) {
	t.Setenv("GEMINI_API_KEY", "")
	r := nuevoRouter("secreta", seguridad.NewRateLimiter(60, time.Minute))

	w := pedirJSON(r, http.MethodGet, paramsPlan, "secreta", "")
	if w.Code != http.StatusOK {
		t.Fatalf("plan con key correcta esperado 200, got %d: %s",
			w.Code, w.Body.String())
	}
}

func TestSinAPIKeyTodoFunciona(t *testing.T) {
	// Regresión de compatibilidad LAN: sin API_KEY, todo como siempre.
	t.Setenv("GEMINI_API_KEY", "")
	r := nuevoRouter("", seguridad.NewRateLimiter(60, time.Minute))

	if w := pedirJSON(r, http.MethodGet, paramsPlan, "", ""); w.Code != http.StatusOK {
		t.Errorf("sin API_KEY el plan debe responder 200, got %d", w.Code)
	}
	if w := pedirJSON(r, http.MethodGet, "/api/motorizacion?marca=A&modelo=B&anio=2000", "", ""); w.Code != http.StatusOK {
		t.Errorf("sin API_KEY motorizacion debe responder 200, got %d", w.Code)
	}
}

func TestCapsATravesDelRouter(t *testing.T) {
	t.Setenv("GEMINI_API_KEY", "")
	r := nuevoRouter("secreta", seguridad.NewRateLimiter(60, time.Minute))

	ruta := "/api/motorizacion?marca=" + strings.Repeat("a", 65) + "&modelo=B&anio=2000"
	if w := pedirJSON(r, http.MethodGet, ruta, "secreta", ""); w.Code != http.StatusBadRequest {
		t.Errorf("marca de 65 chars esperado 400, got %d", w.Code)
	}
}

func TestSesionVehiculoIdLargo400(t *testing.T) {
	t.Setenv("GEMINI_API_KEY", "")
	r := nuevoRouter("secreta", seguridad.NewRateLimiter(60, time.Minute))

	body := `{"vehiculoId":"` + strings.Repeat("v", 65) + `","duracionSegundos":600}`
	if w := pedirJSON(r, http.MethodPost, "/api/sesion", "secreta", body); w.Code != http.StatusBadRequest {
		t.Errorf("vehiculoId de 65 chars esperado 400, got %d", w.Code)
	}

	// Con 64 exactos pasa (el handler responde 201 Created).
	body = `{"vehiculoId":"` + strings.Repeat("v", 64) + `","duracionSegundos":600}`
	if w := pedirJSON(r, http.MethodPost, "/api/sesion", "secreta", body); w.Code != http.StatusCreated {
		t.Errorf("vehiculoId de 64 chars debe pasar, got %d: %s", w.Code, w.Body.String())
	}
}

func TestRateLimitATravesDelRouter(t *testing.T) {
	t.Setenv("GEMINI_API_KEY", "")
	rl := seguridad.NewRateLimiter(3, time.Minute)
	r := nuevoRouter("secreta", rl)

	for i := 1; i <= 3; i++ {
		if w := pedirJSON(r, http.MethodGet, paramsPlan, "secreta", ""); w.Code != http.StatusOK {
			t.Fatalf("petición %d dentro del límite esperada 200, got %d", i, w.Code)
		}
	}
	w := pedirJSON(r, http.MethodGet, paramsPlan, "secreta", "")
	if w.Code != http.StatusTooManyRequests {
		t.Errorf("petición 4 esperada 429, got %d", w.Code)
	}
	if w.Header().Get("Retry-After") == "" {
		t.Error("el 429 debe traer Retry-After")
	}

	// El health NO está rate-limited.
	if w := pedirJSON(r, http.MethodGet, "/api/health", "", ""); w.Code != http.StatusOK {
		t.Errorf("health debe seguir disponible tras agotar el límite, got %d", w.Code)
	}
}
