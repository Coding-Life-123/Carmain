package webmecanico_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/carmain/servidor-go/webmecanico"
	"github.com/gin-gonic/gin"
)

func TestWebMecanicoHandler(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()

	handler := webmecanico.Handler()
	r.GET("/m", handler)
	r.GET("/m/*path", handler)

	t.Run("sirve index.html en /m", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/m", nil)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)

		if w.Code != http.StatusOK {
			t.Fatalf("se esperaba status 200, se obtuvo %d (Location: %s)", w.Code, w.Header().Get("Location"))
		}
		if !strings.Contains(w.Body.String(), "<title>CarMain · Ficha de Taller</title>") {
			t.Errorf("contenido no incluye el título esperado: %s", w.Body.String())
		}
		cc := w.Header().Get("Cache-Control")
		if !strings.Contains(cc, "no-cache") {
			t.Errorf("cache-control esperado no-cache, se obtuvo %s", cc)
		}
	})

	t.Run("sirve index.html como fallback para rutas virtuales SPA", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/m/ficha/ABC123", nil)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)

		if w.Code != http.StatusOK {
			t.Fatalf("se esperaba status 200, se obtuvo %d (Location: %s)", w.Code, w.Header().Get("Location"))
		}
		if !strings.Contains(w.Body.String(), "CarMain") {
			t.Errorf("contenido fallback no incluye CarMain")
		}
	})
}
