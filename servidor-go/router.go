package main

import (
	"net/http"
	"time"

	"github.com/carmain/servidor-go/biblioteca"
	"github.com/carmain/servidor-go/relay"
	"github.com/carmain/servidor-go/seguridad"
	"github.com/gin-gonic/gin"
)

// nuevoRouter arma el servidor completo con su política de seguridad.
// Separado de main() para poder testear el cableado (health público, el
// resto protegido) con httptest sin levantar el proceso.
//
// apiKey vacía = sin auth (modo LAN de desarrollo, todo funciona como
// siempre). El rate limit siempre aplica — en LAN limita por IP.
func nuevoRouter(apiKey string, rl *seguridad.RateLimiter) *gin.Engine {
	r := gin.Default()

	// Solo Caddy (localhost) es proxy confiable. Sin esto gin confía en
	// TODOS los proxies: un cliente cualquiera podría spoofear
	// X-Forwarded-For y esquivar el rate limit por IP.
	_ = r.SetTrustedProxies([]string{"127.0.0.1", "::1"})

	// Health público: probe de Caddy/uptime y de la app antes de
	// configurar la API key. No expone nada sensible.
	r.GET("/api/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	h := biblioteca.NewHandler()

	// Todo lo demás detrás del API key cuando está configurada.
	protegido := r.Group("/")
	protegido.Use(seguridad.APIKeyMiddleware(apiKey))
	{
		api := protegido.Group("/api", seguridad.CapsMiddleware(64,
			"marca", "modelo", "trim", "codigo", "motorCodigo", "transCodigo"))
		// Rate limit SOLO en los endpoints que tocan Gemini (cuenta
		// también cache hits: 60/min es holgado para un usuario real y
		// simplifica el razonamiento).
		api.GET("/plan", rl.Middleware(), h.PlanHandler)
		api.GET("/motorizacion", rl.Middleware(), h.MotorizacionHandler)
		api.GET("/componente", rl.Middleware(), h.ComponenteHandler)
		api.POST("/sesion", h.CrearSesionHandler)
		api.DELETE("/sesion/:codigo", h.RevocarSesionHandler)
	}
	// El WebSocket también: el middleware corre en el handshake HTTP del
	// upgrade, antes de que relay.Handler valide la sesión.
	protegido.GET("/relay", relay.Handler)

	return r
}

// rateLimitProduccion es la política por defecto del servidor: 60
// peticiones por minuto por clave/IP — de sobra para el uso real de la
// app (búsquedas con debounce) y un techo firme para un abuso de la
// cuota de Gemini.
func rateLimitProduccion() *seguridad.RateLimiter {
	return seguridad.NewRateLimiter(60, time.Minute)
}
