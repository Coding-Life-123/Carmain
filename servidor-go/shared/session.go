package shared

import (
	"sync"
	"time"
)

// ManejadorSesiones gestiona las sesiones de relay en memoria.
// Es thread-safe: todas las operaciones están protegidas por un RWMutex.
type ManejadorSesiones struct {
	sesiones map[string]*SesionRelay
	mu       sync.RWMutex
}

// Sesiones es la instancia global del manejador de sesiones.
var Sesiones = &ManejadorSesiones{
	sesiones: make(map[string]*SesionRelay),
}

// Crear registra una nueva sesión en memoria con su código, vehículo y duración.
// Retorna la sesión creada.
func (m *ManejadorSesiones) Crear(codigo, vehiculoID string, duracion time.Duration) *SesionRelay {
	ahora := time.Now()
	s := &SesionRelay{
		Codigo:     codigo,
		VehiculoID: vehiculoID,
		Activa:     true,
		CreadaEn:   ahora,
		ExpiraEn:   ahora.Add(duracion),
	}

	m.mu.Lock()
	defer m.mu.Unlock()
	m.sesiones[codigo] = s
	return s
}

// Validar verifica que una sesión existe, está activa y no ha expirado.
// Retorna la sesión y true si es válida, nil y false en caso contrario.
func (m *ManejadorSesiones) Validar(codigo string) (*SesionRelay, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	s, ok := m.sesiones[codigo]
	if !ok {
		return nil, false
	}

	// Verificar que esté activa y no expirada
	if !s.Activa || time.Now().After(s.ExpiraEn) {
		return nil, false
	}

	return s, true
}

// Revocar marca una sesión como inactiva. Retorna true si la sesión existía.
func (m *ManejadorSesiones) Revocar(codigo string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()

	s, ok := m.sesiones[codigo]
	if !ok {
		return false
	}

	s.Activa = false
	return true
}

// Eliminar remueve una sesión del mapa en memoria.
// Útil para limpieza periódica de sesiones expiradas.
func (m *ManejadorSesiones) Eliminar(codigo string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.sesiones, codigo)
}

// AsignarDueno registra el device ID del dueño en la sesión.
func (m *ManejadorSesiones) AsignarDueno(codigo, deviceID string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()

	s, ok := m.sesiones[codigo]
	if !ok {
		return false
	}
	s.DuenoDeviceID = deviceID
	return true
}

// AsignarMecanico registra el device ID del mecánico en la sesión.
func (m *ManejadorSesiones) AsignarMecanico(codigo, deviceID string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()

	s, ok := m.sesiones[codigo]
	if !ok {
		return false
	}
	s.MecanicoDevice = deviceID
	return true
}
