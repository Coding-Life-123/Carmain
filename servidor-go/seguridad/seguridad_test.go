package seguridad

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func init() { gin.SetMode(gin.TestMode) }

// routerDePrueba arma un gin con el middleware bajo prueba y un handler
// dummy que responde 200 — lo que importa es el veredicto del middleware.
func routerDePrueba(mw ...gin.HandlerFunc) *gin.Engine {
	r := gin.New()
	r.GET("/x", append(mw, func(c *gin.Context) { c.Status(http.StatusOK) })...)
	return r
}

func pedir(r *gin.Engine, apiKeyHeader string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	if apiKeyHeader != "" {
		req.Header.Set("X-Api-Key", apiKeyHeader)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestAPIKeyMiddlewareSinAPIKeyConfigurada(t *testing.T) {
	// apiKey vacía = no-op: compatibilidad LAN.
	r := routerDePrueba(APIKeyMiddleware(""))
	if pedir(r, "").Code != http.StatusOK {
		t.Error("sin API_KEY configurada todo debe pasar sin header")
	}
	if pedir(r, "lo-que-sea").Code != http.StatusOK {
		t.Error("sin API_KEY configurada cualquier header debe pasar")
	}
}

func TestAPIKeyMiddlewareRechazaSinHeader(t *testing.T) {
	r := routerDePrueba(APIKeyMiddleware("secreta"))
	if code := pedir(r, "").Code; code != http.StatusUnauthorized {
		t.Errorf("sin header esperado 401, got %d", code)
	}
}

func TestAPIKeyMiddlewareRechazaKeyIncorrecta(t *testing.T) {
	r := routerDePrueba(APIKeyMiddleware("secreta"))
	if code := pedir(r, "incorrecta").Code; code != http.StatusUnauthorized {
		t.Errorf("key incorrecta esperado 401, got %d", code)
	}
}

func TestAPIKeyMiddlewareAceptaKeyCorrecta(t *testing.T) {
	r := routerDePrueba(APIKeyMiddleware("secreta"))
	if code := pedir(r, "secreta").Code; code != http.StatusOK {
		t.Errorf("key correcta esperado 200, got %d", code)
	}
}

func TestCapsMiddlewareRechazaExceso(t *testing.T) {
	r := gin.New()
	r.GET("/x", CapsMiddleware(64, "marca"), func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/x?marca="+strings.Repeat("a", 65), nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("marca de 65 chars esperado 400, got %d", w.Code)
	}

	req = httptest.NewRequest(http.MethodGet, "/x?marca="+strings.Repeat("a", 64), nil)
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("marca de 64 chars exactos debe pasar, got %d", w.Code)
	}
}

func TestRateLimiterPermiteHastaLimiteYLuego429(t *testing.T) {
	rl := NewRateLimiter(3, 50*time.Millisecond)
	r := routerDePrueba(rl.Middleware())

	for i := 1; i <= 3; i++ {
		if code := pedir(r, "key-a").Code; code != http.StatusOK {
			t.Fatalf("petición %d dentro del límite esperada 200, got %d", i, code)
		}
	}
	if code := pedir(r, "key-a").Code; code != http.StatusTooManyRequests {
		t.Errorf("petición 4 esperada 429, got %d", code)
	}
}

func TestRateLimiterRetryAfterPresente(t *testing.T) {
	rl := NewRateLimiter(1, 50*time.Millisecond)
	r := routerDePrueba(rl.Middleware())
	pedir(r, "key-a") // agota

	w := pedir(r, "key-a")
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("esperado 429, got %d", w.Code)
	}
	if w.Header().Get("Retry-After") == "" {
		t.Error("el 429 debe traer header Retry-After")
	}
}

func TestRateLimiterClavesIndependientes(t *testing.T) {
	rl := NewRateLimiter(1, 50*time.Millisecond)
	r := routerDePrueba(rl.Middleware())

	pedir(r, "key-a") // agota key-a
	if code := pedir(r, "key-b").Code; code != http.StatusOK {
		t.Errorf("key-b no debe verse afectada por key-a, got %d", code)
	}
}

func TestRateLimiterVentanaSeReinicia(t *testing.T) {
	rl := NewRateLimiter(1, 30*time.Millisecond)
	r := routerDePrueba(rl.Middleware())

	pedir(r, "key-a") // agota
	time.Sleep(40 * time.Millisecond)
	if code := pedir(r, "key-a").Code; code != http.StatusOK {
		t.Errorf("tras cerrarse la ventana debe volver a permitir, got %d", code)
	}
}

func TestRateLimiterSinHeaderLimitaPorIP(t *testing.T) {
	// Sin X-Api-Key la clave es la IP — el middleware no debe romper.
	rl := NewRateLimiter(1, 50*time.Millisecond)
	r := routerDePrueba(rl.Middleware())

	if code := pedir(r, "").Code; code != http.StatusOK {
		t.Errorf("primera petición sin key debe pasar, got %d", code)
	}
	if code := pedir(r, "").Code; code != http.StatusTooManyRequests {
		t.Errorf("segunda petición sin key (misma IP) esperada 429, got %d", code)
	}
}
