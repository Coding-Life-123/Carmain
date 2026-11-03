package webmecanico

import (
	"embed"
	"io/fs"
	"mime"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
)

//go:embed dist/*
var distFS embed.FS

// Handler sirve los archivos estáticos de la SPA web-mecanico.
// Todas las rutas bajo /m o /m/* que no coincidan con un asset estático
// retornan index.html para soportar el routing SPA del lado del cliente.
func Handler() gin.HandlerFunc {
	subFS, err := fs.Sub(distFS, "dist")
	if err != nil {
		panic("error iniciando filesystem embebido de web-mecanico: " + err.Error())
	}

	indexHTML, err := fs.ReadFile(subFS, "index.html")
	if err != nil {
		panic("no se encontro index.html en dist embebido: " + err.Error())
	}

	return func(c *gin.Context) {
		reqPath := c.Param("path")
		reqPath = strings.TrimPrefix(reqPath, "/")

		// Si es la raíz o index.html, servir index.html
		if reqPath == "" || reqPath == "index.html" {
			servirIndex(c, indexHTML)
			return
		}

		// Leer archivo solicitado en el dist embebido
		data, err := fs.ReadFile(subFS, reqPath)
		if err != nil {
			// Si no existe (rutas virtuales SPA), servir index.html
			servirIndex(c, indexHTML)
			return
		}

		// Cabeceras de cache
		if strings.HasPrefix(reqPath, "assets/") {
			// Assets de Vite con hash inmutable por 1 año
			c.Header("Cache-Control", "public, max-age=31536000, immutable")
		} else {
			c.Header("Cache-Control", "no-cache")
		}

		ext := filepath.Ext(reqPath)
		mimeType := mime.TypeByExtension(ext)
		if mimeType == "" {
			mimeType = "application/octet-stream"
		}

		c.Data(http.StatusOK, mimeType, data)
	}
}

func servirIndex(c *gin.Context, indexHTML []byte) {
	c.Header("Cache-Control", "no-cache, no-store, must-revalidate")
	c.Data(http.StatusOK, "text/html; charset=utf-8", indexHTML)
}
