package biblioteca

import (
	"crypto/sha256"
	"fmt"
	"sync"

	"github.com/carmain/servidor-go/shared"
)

// Cache almacena planes de mantenimiento en memoria, indexados por
// una clave hash derivada de la configuración del vehículo.
// Es thread-safe: usa sync.RWMutex para proteger el mapa interno.
type Cache struct {
	planes map[string]*shared.PlanMantenimiento
	mu     sync.RWMutex
}

// cacheGlobal es la instancia de cache compartida por toda la aplicación.
var cacheGlobal = &Cache{
	planes: make(map[string]*shared.PlanMantenimiento),
}

// generarClave produce una clave hash determinista para una configuración de vehículo.
// Incluye todos los campos relevantes: marca, modelo, año, trim, drivetrain,
// código de motor y código de transmisión.
func generarClave(c shared.ConfigVehiculo) string {
	raw := fmt.Sprintf("%s|%s|%d|%s|%s|%s|%s",
		c.Marca, c.Modelo, c.Anio, c.Trim, c.Drivetrain, c.MotorCodigo, c.TransCodigo)
	h := sha256.Sum256([]byte(raw))
	return fmt.Sprintf("%x", h)
}

// Get busca un plan en cache por configuración de vehículo.
// Retorna el plan si existe, o nil si no está en cache.
func (c *Cache) Get(config shared.ConfigVehiculo) *shared.PlanMantenimiento {
	clave := generarClave(config)

	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.planes[clave]
}

// Set guarda un plan en cache indexado por la configuración de vehículo.
func (c *Cache) Set(config shared.ConfigVehiculo, plan *shared.PlanMantenimiento) {
	clave := generarClave(config)

	c.mu.Lock()
	defer c.mu.Unlock()
	c.planes[clave] = plan
}

// Eliminar remueve un plan del cache por su configuración.
func (c *Cache) Eliminar(config shared.ConfigVehiculo) {
	clave := generarClave(config)

	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.planes, clave)
}

// GetCache devuelve la instancia global de cache.
func GetCache() *Cache {
	return cacheGlobal
}
