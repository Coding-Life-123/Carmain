package main

import (
	"log"
	"os"

	"github.com/joho/godotenv"
)

func main() {
	// Cargar variables de entorno desde .env si existe
	if err := godotenv.Load(); err != nil {
		log.Println("[main] no se pudo cargar .env, usando variables de entorno del sistema")
	}

	// API_KEY activa la autenticación por shared secret (header X-Api-Key
	// en la app). Vacía = modo LAN sin auth, todo funciona como siempre.
	// Nunca loguear el valor.
	apiKey := os.Getenv("API_KEY")

	r := nuevoRouter(apiKey, rateLimitProduccion())

	// Determinar puerto (default 8080)
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("[main] servidor escuchando en :%s (auth por API key: %v)",
		port, apiKey != "")
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("[main] error al iniciar servidor: %v", err)
	}
}
