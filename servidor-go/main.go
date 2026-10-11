package main

import (
	"log"
	"net/http"
	"os"

	"github.com/carmain/servidor-go/biblioteca"
	"github.com/carmain/servidor-go/relay"
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	// Cargar variables de entorno desde .env si existe
	if err := godotenv.Load(); err != nil {
		log.Println("[main] no se pudo cargar .env, usando variables de entorno del sistema")
	}

	// Configurar gin
	r := gin.Default()
	r.Use(corsMiddleware())

	// Inicializar handlers
	h := biblioteca.NewHandler()

	// Grupo /api — endpoints REST
	api := r.Group("/api")
	{
		api.GET("/plan", h.PlanHandler)
		api.POST("/sesion", h.CrearSesionHandler)
		api.DELETE("/sesion/:codigo", h.RevocarSesionHandler)
	}

	// /relay — WebSocket para compartido entre dispositivos
	r.GET("/relay", relay.Handler)

	// Determinar puerto (default 8080)
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("[main] servidor escuchando en :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("[main] error al iniciar servidor: %v", err)
	}
}

// corsMiddleware es un middleware básico de CORS para permitir
// peticiones desde el frontend (móvil o web).
func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}
