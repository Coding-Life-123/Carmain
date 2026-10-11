package relay

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/carmain/servidor-go/shared"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

// upgrader configura el upgrade de HTTP a WebSocket.
// CheckOrigin permite todos los orígenes (CORS se maneja en middleware de gin).
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

// conexion representa una conexión WebSocket activa de un dispositivo.
type conexion struct {
	ws       *websocket.Conn
	deviceID string
	mu       sync.Mutex // protege escrituras concurrentes al WebSocket
}

// sesionConexiones agrupa las conexiones activas de una sesión de relay.
type sesionConexiones struct {
	conexiones map[string]*conexion // deviceID → conexion
	mu         sync.RWMutex
}

// Hub es el hub global del relay que rutea mensajes entre dispositivos
// de la misma sesión. Los mensajes son efímeros: se entregan al destinatario
// y se descartan. No hay persistencia.
type Hub struct {
	sesiones map[string]*sesionConexiones // código de sesión → conexiones
	mu       sync.RWMutex
}

// hubGlobal es la instancia compartida del hub de relay.
var hubGlobal = &Hub{
	sesiones: make(map[string]*sesionConexiones),
}

// obtenerOcrearSesion obtiene el grupo de conexiones para una sesión,
// creándolo si no existe. Thread-safe con doble check.
func (h *Hub) obtenerOcrearSesion(codigo string) *sesionConexiones {
	h.mu.RLock()
	s, ok := h.sesiones[codigo]
	h.mu.RUnlock()
	if ok {
		return s
	}

	h.mu.Lock()
	defer h.mu.Unlock()
	// Doble check: pudo haberse creado entre el RUnlock y el Lock
	if s, ok := h.sesiones[codigo]; ok {
		return s
	}
	s = &sesionConexiones{
		conexiones: make(map[string]*conexion),
	}
	h.sesiones[codigo] = s
	return s
}

// registrar añade una conexión a una sesión.
func (h *Hub) registrar(codigo, deviceID string, conn *conexion) {
	s := h.obtenerOcrearSesion(codigo)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.conexiones[deviceID] = conn
}

// desregistrar elimina una conexión de una sesión.
// Si la sesión queda sin conexiones, la limpia del hub.
func (h *Hub) desregistrar(codigo, deviceID string) {
	h.mu.RLock()
	s, ok := h.sesiones[codigo]
	h.mu.RUnlock()
	if !ok {
		return
	}

	// Eliminar la conexión del dispositivo de la sesión
	s.mu.Lock()
	delete(s.conexiones, deviceID)
	s.mu.Unlock()

	// Limpiar la sesión del hub si no tiene más conexiones.
	// Importante: adquirimos h.mu antes de s.mu para evitar deadlock.
	h.mu.Lock()
	s, ok = h.sesiones[codigo]
	if ok {
		s.mu.RLock()
		empty := len(s.conexiones) == 0
		s.mu.RUnlock()
		if empty {
			delete(h.sesiones, codigo)
		}
	}
	h.mu.Unlock()
}

// rutear envía un mensaje al dispositivo destinatario dentro de la sesión.
// Retorna true si el mensaje se entregó, false si el destinatario no existe.
func (h *Hub) rutear(codigo, deviceID string, msg []byte) bool {
	h.mu.RLock()
	s, ok := h.sesiones[codigo]
	h.mu.RUnlock()
	if !ok {
		return false
	}

	s.mu.RLock()
	conn, ok := s.conexiones[deviceID]
	s.mu.RUnlock()
	if !ok {
		return false
	}

	conn.mu.Lock()
	defer conn.mu.Unlock()
	return conn.ws.WriteMessage(websocket.TextMessage, msg) == nil
}

// Handler maneja el upgrade WebSocket para el relay.
// Query param: ?sesion=<código de sesión>
//
// Protocolo:
// 1. El dispositivo se conecta con ?sesion=CODIGO
// 2. El primer mensaje debe ser un MensajeRelay con campo "de" = deviceID (identificación)
// 3. Los mensajes subsecuentes se rutean al destinatario indicado en "para"
// 4. El payload viaja cifrado E2EE — el relay no lo descifra, solo lo rutea
func Handler(c *gin.Context) {
	codigoSesion := c.Query("sesion")
	if codigoSesion == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "parámetro 'sesion' requerido"})
		return
	}

	// Validar que la sesión existe y está activa
	if _, ok := shared.Sesiones.Validar(codigoSesion); !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "sesión inválida o expirada"})
		return
	}

	// Upgrade a WebSocket
	ws, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("[relay] error upgrade websocket: %v", err)
		return
	}
	defer ws.Close()

	// El primer mensaje debe ser de identificación del dispositivo
	_, msg, err := ws.ReadMessage()
	if err != nil {
		log.Printf("[relay] error leyendo identificación: %v", err)
		return
	}

	var ident shared.MensajeRelay
	if err := json.Unmarshal(msg, &ident); err != nil {
		log.Printf("[relay] error parseando identificación: %v", err)
		ws.WriteJSON(gin.H{"error": "mensaje de identificación inválido"})
		return
	}

	deviceID := ident.De
	if deviceID == "" {
		ws.WriteJSON(gin.H{"error": "deviceID requerido en campo 'de'"})
		return
	}

	// Registrar conexión en el hub
	conn := &conexion{ws: ws, deviceID: deviceID}
	hubGlobal.registrar(codigoSesion, deviceID, conn)
	log.Printf("[relay] dispositivo %s conectado a sesión %s", deviceID, codigoSesion)

	defer func() {
		hubGlobal.desregistrar(codigoSesion, deviceID)
		log.Printf("[relay] dispositivo %s desconectado de sesión %s", deviceID, codigoSesion)
	}()

	// Loop de lectura: rutear mensajes al destinatario
	for {
		_, msg, err := ws.ReadMessage()
		if err != nil {
			// Error o cierre de conexión
			break
		}

		var m shared.MensajeRelay
		if err := json.Unmarshal(msg, &m); err != nil {
			log.Printf("[relay] mensaje inválido de %s: %v", deviceID, err)
			continue
		}

		// Asegurar timestamp
		m.Timestamp = time.Now().UnixMilli()

		// Serializar mensaje para ruteo
		msgBytes, err := json.Marshal(m)
		if err != nil {
			log.Printf("[relay] error serializando mensaje de %s: %v", deviceID, err)
			continue
		}

		// Rutar al destinatario indicado en "para"
		if m.Para != "" {
			if !hubGlobal.rutear(codigoSesion, m.Para, msgBytes) {
				log.Printf("[relay] destinatario %s no encontrado en sesión %s", m.Para, codigoSesion)
				// Enviar ack de error al remitente
				ack := shared.MensajeRelay{
					Tipo:      "ack",
					De:        "relay",
					Para:      deviceID,
					SesionID:  codigoSesion,
					Timestamp: time.Now().UnixMilli(),
				}
				ackBytes, _ := json.Marshal(ack)
				conn.mu.Lock()
				ws.WriteMessage(websocket.TextMessage, ackBytes)
				conn.mu.Unlock()
			}
		}
	}
}
