package biblioteca

import (
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/carmain/servidor-go/shared"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
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
	VehiculoID       string `json:"vehiculoId" binding:"required"`
	DuracionSegundos int    `json:"duracionSegundos"`
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

	// Construir configuración del vehículo
	config := shared.ConfigVehiculo{
		Marca:       marca,
		Modelo:      modelo,
		Anio:        anio,
		Trim:        trim,
		Drivetrain:  drivetrain,
		MotorCodigo: motorCodigo,
		TransCodigo: transCodigo,
	}

	// 1. Buscar en cache
	if plan := h.Cache.Get(config); plan != nil {
		log.Printf("[handler] plan servido desde cache para %s %s %d", marca, modelo, anio)
		c.JSON(http.StatusOK, shared.RespuestaPlan{
			Plan:           plan,
			DesdeCache:     true,
			TieneSwaps:     false,
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
		log.Printf("[handler] plan generado y cacheado para %s %s %d (%d ítems)", marca, modelo, anio, len(plan.Items))
	} else {
		log.Printf("[handler] plan de fallback (no cacheado) para %s %s %d", marca, modelo, anio)
	}

	// 4. El plan de fallback requiere revisión — se calcula por procedencia
	// real, no por la presencia de la API key (que puede fallar a mitad).
	requiereReview := esFallback

	c.JSON(http.StatusOK, shared.RespuestaPlan{
		Plan:           plan,
		DesdeCache:     false,
		TieneSwaps:     false,
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
// Crea una sesión con código UUID y la registra en memoria.
//
// Body: {vehiculoId, duracionSegundos}
// Respuesta: {codigo}
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

	// Duración por defecto: 1 hora
	duracion := time.Hour
	if req.DuracionSegundos > 0 {
		duracion = time.Duration(req.DuracionSegundos) * time.Second
	}

	// Generar código UUID para la sesión
	codigo := uuid.NewString()

	// Registrar sesión en memoria
	shared.Sesiones.Crear(codigo, req.VehiculoID, duracion)
	log.Printf("[handler] sesión creada: codigo=%s vehiculo=%s duracion=%v", codigo, req.VehiculoID, duracion)

	c.JSON(http.StatusCreated, gin.H{"codigo": codigo})
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

	log.Printf("[handler] sesión revocada: %s", codigo)
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
