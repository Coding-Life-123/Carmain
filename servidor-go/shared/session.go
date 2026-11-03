package shared

import (
	"crypto/rand"
	"encoding/hex"
	"math/big"
	"sync"
	"time"
)

// ManejadorSesiones gestiona las sesiones de relay en memoria.
// Es thread-safe: todas las operaciones están protegidas por un RWMutex.
type ManejadorSesiones struct {
	sesiones map[string]*SesionRelay // indexado tanto por codigo corto como por token largo
	mu       sync.RWMutex
}

// Sesiones es la instancia global del manejador de sesiones.
var Sesiones = &ManejadorSesiones{
	sesiones: make(map[string]*SesionRelay),
}

const charsCodigo = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

// GenerarCodigoUnico genera un código corto legible de 6 caracteres (ej. A7F9K2).
func (m *ManejadorSesiones) GenerarCodigoUnico() string {
	m.mu.RLock()
	defer m.mu.RUnlock()

	for {
		codigo := make([]byte, 6)
		for i := 0; i < 6; i++ {
			n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(charsCodigo))))
			codigo[i] = charsCodigo[n.Int64()]
		}
		c := string(codigo)
		if _, exists := m.sesiones[c]; !exists {
			return c
		}
	}
}

// GenerarTokenLargo genera un token seguro de alta entropía (16 bytes = 128 bits en hex).
func (m *ManejadorSesiones) GenerarTokenLargo() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// Crear registra una nueva sesión en memoria con su código, token largo, vehículo y duración.
func (m *ManejadorSesiones) Crear(codigo, vehiculoID string, duracion time.Duration, snapshot any) *SesionRelay {
	ahora := time.Now()
	tokenLargo := m.GenerarTokenLargo()

	m.mu.Lock()
	defer m.mu.Unlock()

	// Si el código viene vacío o colisiona, generar uno nuevo
	if codigo == "" || m.sesiones[codigo] != nil {
		for {
			c := make([]byte, 6)
			for i := 0; i < 6; i++ {
				n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(charsCodigo))))
				c[i] = charsCodigo[n.Int64()]
			}
			codigo = string(c)
			if _, exists := m.sesiones[codigo]; !exists {
				break
			}
		}
	}

	s := &SesionRelay{
		Codigo:     codigo,
		TokenLargo: tokenLargo,
		VehiculoID: vehiculoID,
		Activa:     true,
		CreadaEn:   ahora,
		ExpiraEn:   ahora.Add(duracion),
		Snapshot:   snapshot,
		Propuestas: make([]any, 0),
	}

	m.sesiones[codigo] = s
	m.sesiones[tokenLargo] = s
	return s
}

// Validar verifica que una sesión existe, está activa y no ha expirado.
// Acepta tanto el código corto (6 chars) como el token largo (32 chars hex).
// Marca ConsultadaEn la primera vez que es consultada.
func (m *ManejadorSesiones) Validar(clave string) (*SesionRelay, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	s, ok := m.sesiones[clave]
	if !ok {
		return nil, false
	}

	if !s.Activa || time.Now().After(s.ExpiraEn) {
		return nil, false
	}

	if s.ConsultadaEn == nil {
		ahora := time.Now()
		s.ConsultadaEn = &ahora
	}

	return s, true
}

// Revocar marca una sesión como inactiva. Retorna true si existía.
func (m *ManejadorSesiones) Revocar(clave string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()

	s, ok := m.sesiones[clave]
	if !ok {
		return false
	}

	s.Activa = false
	return true
}

// Eliminar remueve una sesión del mapa en memoria.
func (m *ManejadorSesiones) Eliminar(clave string) {
	m.mu.Lock()
	defer m.mu.Unlock()

	s, ok := m.sesiones[clave]
	if ok {
		delete(m.sesiones, s.Codigo)
		delete(m.sesiones, s.TokenLargo)
	} else {
		delete(m.sesiones, clave)
	}
}

// LimpiarExpiradas elimina todas las sesiones inactivas o vencidas.
func (m *ManejadorSesiones) LimpiarExpiradas() int {
	m.mu.Lock()
	defer m.mu.Unlock()

	ahora := time.Now()
	eliminadas := 0
	for k, s := range m.sesiones {
		if !s.Activa || ahora.After(s.ExpiraEn) {
			delete(m.sesiones, k)
			eliminadas++
		}
	}
	return eliminadas
}

// IniciarLimpiadorPeriodico inicia una goroutine que limpia sesiones periódicamente.
func (m *ManejadorSesiones) IniciarLimpiadorPeriodico(intervalo time.Duration) {
	ticker := time.NewTicker(intervalo)
	go func() {
		for range ticker.C {
			m.LimpiarExpiradas()
		}
	}()
}

// AsignarDueno registra el device ID del dueño en la sesión.
func (m *ManejadorSesiones) AsignarDueno(clave, deviceID string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()

	s, ok := m.sesiones[clave]
	if !ok {
		return false
	}
	s.DuenoDeviceID = deviceID
	return true
}

// AsignarMecanico registra el device ID del mecánico en la sesión.
func (m *ManejadorSesiones) AsignarMecanico(clave, deviceID string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()

	s, ok := m.sesiones[clave]
	if !ok {
		return false
	}
	s.MecanicoDevice = deviceID
	return true
}

// GuardarPropuesta añade una propuesta de mantenimiento al buzón de la sesión.
// Retorna (guardado, yaExistia) garantizando idempotencia si se reenvía el mismo id.
// Aplica un límite de hasta 20 propuestas por sesión.
func (m *ManejadorSesiones) GuardarPropuesta(clave string, propuesta any) (bool, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	s, ok := m.sesiones[clave]
	if !ok || !s.Activa || time.Now().After(s.ExpiraEn) {
		return false, false
	}

	// Límite de propuestas
	if len(s.Propuestas) >= 20 {
		return false, false
	}

	// Idempotencia por id si está presente
	var propID string
	if pMap, ok := propuesta.(map[string]interface{}); ok {
		if id, ok := pMap["id"].(string); ok {
			propID = id
		}
	} else if pV1, ok := propuesta.(PropuestaV1); ok {
		propID = pV1.ID
	}

	if propID != "" {
		for _, existente := range s.Propuestas {
			if eMap, ok := existente.(map[string]interface{}); ok {
				if eMap["id"] == propID {
					return true, true // Idempotente
				}
			} else if eV1, ok := existente.(PropuestaV1); ok {
				if eV1.ID == propID {
					return true, true
				}
			}
		}
	}

	s.Propuestas = append(s.Propuestas, propuesta)
	return true, false
}

// ObtenerPropuestas obtiene todas las propuestas acumuladas en el buzón.
func (m *ManejadorSesiones) ObtenerPropuestas(clave string) ([]any, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	s, ok := m.sesiones[clave]
	if !ok || !s.Activa || time.Now().After(s.ExpiraEn) {
		return nil, false
	}

	propuestas := make([]any, len(s.Propuestas))
	copy(propuestas, s.Propuestas)
	return propuestas, true
}

// ConfirmarPropuestas vacía las propuestas del buzón tras ser integradas por el dueño.
func (m *ManejadorSesiones) ConfirmarPropuestas(clave string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()

	s, ok := m.sesiones[clave]
	if !ok || !s.Activa || time.Now().After(s.ExpiraEn) {
		return false
	}

	s.Propuestas = make([]any, 0)
	return true
}
