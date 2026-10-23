// Package seguridad contiene los middlewares que protegen la API cuando
// el servidor está expuesto a internet (VPS): autenticación por shared
// secret, rate limiting en memoria y caps de parámetros.
//
// Sin API_KEY configurada todo es no-op — el servidor se comporta
// exactamente como en el modo LAN de desarrollo.
package seguridad

import (
	"crypto/subtle"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// APIKeyMiddleware exige el header X-Api-Key cuando apiKey está
// configurada. Comparación constant-time: no revela timing del prefijo
// correcto (la diferencia de longitud sí se filtra — ConstantTimeCompare
// retorna inmediato si difieren; fuga aceptable y práctica estándar).
//
// apiKey vacía = middleware no-op (compatibilidad LAN).
func APIKeyMiddleware(apiKey string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if apiKey == "" {
			c.Next()
			return
		}
		provista := c.GetHeader("X-Api-Key")
		if subtle.ConstantTimeCompare([]byte(provista), []byte(apiKey)) != 1 {
			c.AbortWithStatusJSON(http.StatusUnauthorized,
				gin.H{"error": "API key inválida o ausente"})
			return
		}
		c.Next()
	}
}

// RateLimiter es un limitador fixed-window en memoria, por IP. Suficiente
// para proteger la cuota de Gemini de un abuso accidental o
// malintencionado; no pretende ser infraestructura de producción
// multi-instancia.
type RateLimiter struct {
	mu          sync.Mutex
	limite      int
	ventana     time.Duration
	cubetas     map[string]*cubeta
	ultimaPurga time.Time
}

type cubeta struct {
	usos   int
	inicio time.Time
}

// maxCubetas: tope duro del mapa — con IPs rotativas (avalancha IPv6,
// modo LAN sin key) crecería sin límite. Al pasarlo se purga lo expirado
// y se evicta al azar hasta el tope.
const maxCubetas = 4096

func NewRateLimiter(limite int, ventana time.Duration) *RateLimiter {
	return &RateLimiter{
		limite:  limite,
		ventana: ventana,
		cubetas: make(map[string]*cubeta),
	}
}

// Permitir registra un uso de la clave y reporta si pasa el límite.
// reintentoEn es cuánto falta para que la ventana se reinicie (0 si pasó).
func (rl *RateLimiter) Permitir(clave string) (ok bool, reintentoEn time.Duration) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	ahora := time.Now()
	cub, existe := rl.cubetas[clave]
	if !existe || ahora.Sub(cub.inicio) >= rl.ventana {
		// Ventana nueva: reemplaza (o crea) la cubeta.
		rl.cubetas[clave] = &cubeta{usos: 1, inicio: ahora}
		if len(rl.cubetas) > maxCubetas {
			rl.purgar(ahora)
		}
		return true, 0
	}

	cub.usos++
	if cub.usos > rl.limite {
		return false, rl.ventana - ahora.Sub(cub.inicio)
	}
	return true, 0
}

// purgar acota el mapa cuando supera maxCubetas. El escaneo completo está
// amortizado a lo sumo una vez por ventana: bajo avalancha de IPs
// rotativas, un escaneo por inserción sería cuadrático bajo el mutex
// global (medido: 20k IPs → ~6s de CPU serializada). Si tras purgar
// siguen sobrando cubetas frescas, se evicta al azar hasta el tope —
// preferible degradar la cuota de alguien antes que colapsar el mutex.
// Llamado con el lock tomado.
func (rl *RateLimiter) purgar(ahora time.Time) {
	if ahora.Sub(rl.ultimaPurga) >= rl.ventana {
		rl.ultimaPurga = ahora
		for clave, cub := range rl.cubetas {
			if ahora.Sub(cub.inicio) >= rl.ventana {
				delete(rl.cubetas, clave)
			}
		}
	}
	for len(rl.cubetas) > maxCubetas {
		for clave := range rl.cubetas {
			delete(rl.cubetas, clave)
			break
		}
	}
}

// Middleware aplica el rate limit por petición. El balde es por IP del
// cliente: con la key horneada en el build todos los dispositivos
// legítimos comparten la MISMA key, así que contar por key los fundiría
// en un solo balde global — por IP cada dispositivo tiene su cuota.
// Detrás de Caddy, ClientIP() resuelve la IP real (SetTrustedProxies).
func (rl *RateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		if ok, reintentoEn := rl.Permitir(c.ClientIP()); !ok {
			segundos := int(reintentoEn.Seconds()) + 1
			c.Header("Retry-After", strconv.Itoa(segundos))
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "demasiadas peticiones — reintenta en " + strconv.Itoa(segundos) + "s",
			})
			return
		}
		c.Next()
	}
}

// CapsMiddleware rechaza con 400 cualquier query param listado que
// exceda maxChars. Higiene básica contra payloads absurdos en los
// endpoints que alimentan prompts de Gemini.
func CapsMiddleware(maxChars int, params ...string) gin.HandlerFunc {
	return func(c *gin.Context) {
		for _, p := range params {
			if len(c.Query(p)) > maxChars {
				c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{
					"error": "parámetro '" + p + "' excede " + strconv.Itoa(maxChars) + " caracteres",
				})
				return
			}
		}
		c.Next()
	}
}
