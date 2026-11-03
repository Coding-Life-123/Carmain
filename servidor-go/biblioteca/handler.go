package biblioteca

import (
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/carmain/servidor-go/relay"
	"github.com/carmain/servidor-go/shared"
	"github.com/gin-gonic/gin"
)

// Handler contiene las dependencias compartidas entre los handlers REST.
type Handler struct {
	Cache *Cache
}

// NewHandler crea un nuevo conjunto de handlers con la cache global.
func NewHandler() *Handler {
	return &Handler{
		Cache: GetCache(),
	}
}

// crearSesionRequest es el cuerpo de POST /api/sesion.
type crearSesionRequest struct {
	VehiculoID       string                 `json:"vehiculoId" binding:"required"`
	DuracionSegundos int                    `json:"duracionSegundos"`
	DeviceID         string                 `json:"deviceId,omitempty"`
	Snapshot         map[string]interface{} `json:"snapshot,omitempty"`
}

// PlanHandler maneja GET /api/plan.
// Recibe la configuración del vehículo como query params, busca en cache,
// y si no existe investiga con IA, guarda en cache y devuelve el plan.
//
// Query params: marca, modelo, anio, trim, drivetrain, motorCodigo, transCodigo
// Respuesta: {plan, desdeCache, tieneSwaps, requiereReview}
func (h *Handler) PlanHandler(c *gin.Context) {
	// Leer query params
	marca := c.Query("marca")
	modelo := c.Query("modelo")
	anioStr := c.Query("anio")
	drivetrain := normalizarDrivetrain(c.Query("drivetrain"))
	motorCodigo := c.Query("motorCodigo")
	transCodigo := c.Query("transCodigo")
	trim := c.Query("trim")

	// Validar campos requeridos
	if marca == "" || modelo == "" || anioStr == "" || drivetrain == "" || motorCodigo == "" || transCodigo == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "parámetros requeridos: marca, modelo, anio, drivetrain, motorCodigo, transCodigo",
		})
		return
	}

	anio, err := strconv.Atoi(anioStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "anio debe ser un número entero"})
		return
	}

	motorEsSwap := c.Query("motorEsSwap") == "true"
	motorOriginal := c.Query("motorOriginal")
	transEsSwap := c.Query("transEsSwap") == "true"
	transOriginal := c.Query("transOriginal")
	combustible := c.Query("combustible")
	aspiracion := c.Query("aspiracion")
	transTipo := c.Query("transTipo")

	var cilindradaPtr *float64
	if v, err := strconv.ParseFloat(c.Query("cilindrada"), 64); err == nil && v > 0 {
		cilindradaPtr = &v
	}
	var cilindrosPtr *int
	if v, err := strconv.Atoi(c.Query("cilindros")); err == nil && v > 0 {
		cilindrosPtr = &v
	}
	var potenciaPtr *int
	if v, err := strconv.Atoi(c.Query("potenciaHp")); err == nil && v > 0 {
		potenciaPtr = &v
	}
	var torquePtr *int
	if v, err := strconv.Atoi(c.Query("torqueNm")); err == nil && v > 0 {
		torquePtr = &v
	}
	var marchasPtr *int
	if v, err := strconv.Atoi(c.Query("transMarchas")); err == nil && v > 0 {
		marchasPtr = &v
	}

	tieneSwaps := motorEsSwap || transEsSwap

	// Construir configuración del vehículo
	config := shared.ConfigVehiculo{
		Marca:         marca,
		Modelo:        modelo,
		Anio:          anio,
		Trim:          trim,
		Drivetrain:    drivetrain,
		MotorCodigo:   motorCodigo,
		TransCodigo:   transCodigo,
		MotorEsSwap:   motorEsSwap,
		MotorOriginal: motorOriginal,
		TransEsSwap:   transEsSwap,
		TransOriginal: transOriginal,
		Combustible:   combustible,
		Cilindrada:    cilindradaPtr,
		Cilindros:     cilindrosPtr,
		Aspiracion:    aspiracion,
		PotenciaHP:    potenciaPtr,
		TorqueNm:      torquePtr,
		TransTipo:     transTipo,
		TransMarchas:  marchasPtr,
	}

	// 1. Buscar en cache
	if plan := h.Cache.Get(config); plan != nil {
		log.Printf("[handler] plan servido desde cache para %s %s %d (swaps: %t)", marca, modelo, anio, tieneSwaps)
		c.JSON(http.StatusOK, shared.RespuestaPlan{
			Plan:           plan,
			DesdeCache:     true,
			TieneSwaps:     tieneSwaps,
			RequiereReview: false,
		})
		return
	}

	// 2. Investigar con IA (o fallback si no hay API key / falla Gemini)
	plan, esFallback, err := InvestigarPlan(config)
	if err != nil {
		log.Printf("[handler] error investigando plan: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "error generando plan de mantenimiento"})
		return
	}

	// 3. Guardar en cache SOLO planes investigados: un fallback producto de
	// un fallo transitorio de Gemini (429, timeout, red) no debe quedar
	// cacheado hasta reiniciar el proceso — la próxima solicitud reintenta.
	if !esFallback {
		h.Cache.Set(config, plan)
		log.Printf("[handler] plan generado y cacheado para %s %s %d (%d ítems, swaps: %t)", marca, modelo, anio, len(plan.Items), tieneSwaps)
	} else {
		log.Printf("[handler] plan de fallback (no cacheado) para %s %s %d (swaps: %t)", marca, modelo, anio, tieneSwaps)
	}

	// 4. El plan de fallback requiere revisión — se calcula por procedencia
	// real, no por la presencia de la API key (que puede fallar a mitad).
	requiereReview := esFallback

	c.JSON(http.StatusOK, shared.RespuestaPlan{
		Plan:           plan,
		DesdeCache:     false,
		TieneSwaps:     tieneSwaps,
		RequiereReview: requiereReview,
	})
}

// normalizarDrivetrain lleva el drivetrain al vocabulario canónico del
// contrato (FWD|RWD|AWD|4WD, ver shared.ConfigVehiculo). La app nueva envía
// las etiquetas, pero versiones instaladas pueden enviar el nombre del enum
// Dart en minúsculas ('fwd', 'awd', 'fourWd') — sin esto, el fallback omite
// diferencial y transfer case en AWD/4WD y el prompt de IA se degrada.
func normalizarDrivetrain(s string) string {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "fwd":
		return "FWD"
	case "rwd":
		return "RWD"
	case "awd":
		return "AWD"
	case "4wd", "fourwd":
		return "4WD"
	}
	return s
}

// CrearSesionHandler maneja POST /api/sesion.
// Crea una sesión con código único y la registra en memoria.
//
// Body: {vehiculoId, duracionSegundos, deviceId, snapshot}
// Respuesta: {codigo, expiraEn}
func (h *Handler) CrearSesionHandler(c *gin.Context) {
	var req crearSesionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "body inválido: " + err.Error()})
		return
	}
	// Cap de higiene: vehiculoId viaja en body, no en query params —
	// CapsMiddleware no lo cubre.
	if len(req.VehiculoID) > 64 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "vehiculoId excede 64 caracteres"})
		return
	}

	// Duración por defecto: 24 horas para facilitar el flujo asíncrono con el taller
	duracion := 24 * time.Hour
	if req.DuracionSegundos > 0 {
		duracion = time.Duration(req.DuracionSegundos) * time.Second
	}

	// Generar código único legible (6 caracteres, ej: A7F9K2)
	codigo := shared.Sesiones.GenerarCodigoUnico()

	// Registrar sesión en memoria
	sesion := shared.Sesiones.Crear(codigo, req.VehiculoID, duracion, req.Snapshot)
	if req.DeviceID != "" {
		shared.Sesiones.AsignarDueno(codigo, req.DeviceID)
	}
	log.Printf("[handler] sesión creada: codigo=%s vehiculo=%s duracion=%v", codigo, req.VehiculoID, duracion)

	c.JSON(http.StatusCreated, gin.H{
		"codigo":     sesion.Codigo,
		"tokenLargo": sesion.TokenLargo,
		"expiraEn":   sesion.ExpiraEn,
	})
}

func enmascararClave(clave string) string {
	if len(clave) > 8 {
		return clave[:4] + "..." + clave[len(clave)-4:]
	}
	return clave
}

// RevocarSesionHandler maneja DELETE /api/sesion/:codigo.
// Marca la sesión como inactiva.
func (h *Handler) RevocarSesionHandler(c *gin.Context) {
	codigo := c.Param("codigo")
	if codigo == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "código de sesión requerido"})
		return
	}

	if !shared.Sesiones.Revocar(codigo) {
		c.JSON(http.StatusNotFound, gin.H{"error": "sesión no encontrada"})
		return
	}

	log.Printf("[handler] sesión revocada: %s", enmascararClave(codigo))
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// ObtenerSesionPublicaHandler maneja GET /api/sesion/:codigo.
// Permite a la interfaz web del mecánico consultar el snapshot del vehículo sin requerir API key.
// Acepta tanto el código corto como el token largo.
func (h *Handler) ObtenerSesionPublicaHandler(c *gin.Context) {
	codigo := c.Param("codigo")
	if codigo == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "código de sesión requerido"})
		return
	}

	sesion, ok := shared.Sesiones.Validar(codigo)
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "sesión inválida o expirada"})
		return
	}

	c.Header("Cache-Control", "no-store")
	c.Header("Referrer-Policy", "no-referrer")
	c.Header("X-Content-Type-Options", "nosniff")

	c.JSON(http.StatusOK, gin.H{
		"codigo":       sesion.Codigo,
		"tokenLargo":   sesion.TokenLargo,
		"vehiculoId":   sesion.VehiculoID,
		"activa":       sesion.Activa,
		"creadaEn":     sesion.CreadaEn,
		"expiraEn":     sesion.ExpiraEn,
		"consultadaEn": sesion.ConsultadaEn,
		"snapshot":     sesion.Snapshot,
	})
}

// EnviarPropuestaMecanicoHandler maneja POST /api/sesion/:codigo/propuesta.
// La web del mecánico deposita la propuesta de mantenimiento en el buzón store-and-forward.
func (h *Handler) EnviarPropuestaMecanicoHandler(c *gin.Context) {
	codigo := c.Param("codigo")
	if codigo == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "código de sesión requerido"})
		return
	}

	// Límite de tamaño: máx. 64 KB para evitar abusos
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 64*1024)

	var propuesta map[string]interface{}
	if err := c.ShouldBindJSON(&propuesta); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "propuesta inválida: " + err.Error()})
		return
	}

	propuesta["recibidaEn"] = time.Now().UTC().Format(time.RFC3339)

	guardado, yaExistia := shared.Sesiones.GuardarPropuesta(codigo, propuesta)
	if !guardado {
		c.JSON(http.StatusNotFound, gin.H{"error": "sesión inválida, inactiva o buzón lleno"})
		return
	}

	if yaExistia {
		log.Printf("[handler] propuesta duplicada ignorada (idempotencia) para sesión %s", enmascararClave(codigo))
		c.JSON(http.StatusOK, gin.H{"ok": true, "duplicado": true, "mensaje": "propuesta ya registrada"})
		return
	}

	// Notificar al dueño si está conectado al relay WebSocket
	relay.NotificarDueno(codigo, "propuesta_mecanico", propuesta)

	log.Printf("[handler] propuesta guardada en buzón para sesión %s", enmascararClave(codigo))
	c.JSON(http.StatusCreated, gin.H{"ok": true, "mensaje": "propuesta guardada exitosamente"})
}

// ObtenerPropuestasPendientesHandler maneja GET /api/sesion/:codigo/propuestas.
// La app del dueño recupera las propuestas acumuladas en el buzón.
func (h *Handler) ObtenerPropuestasPendientesHandler(c *gin.Context) {
	codigo := c.Param("codigo")
	if codigo == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "código de sesión requerido"})
		return
	}

	propuestas, ok := shared.Sesiones.ObtenerPropuestas(codigo)
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "sesión no encontrada o expirada"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"codigo":     codigo,
		"propuestas": propuestas,
	})
}

// ConfirmarPropuestasHandler maneja POST /api/sesion/:codigo/confirmar.
// La app del dueño confirma que integró las propuestas y limpia el buzón.
func (h *Handler) ConfirmarPropuestasHandler(c *gin.Context) {
	codigo := c.Param("codigo")
	if codigo == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "código de sesión requerido"})
		return
	}

	if !shared.Sesiones.ConfirmarPropuestas(codigo) {
		c.JSON(http.StatusNotFound, gin.H{"error": "sesión no encontrada o inactiva"})
		return
	}

	log.Printf("[handler] propuestas confirmadas y buzón vaciado para sesión %s", codigo)
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
