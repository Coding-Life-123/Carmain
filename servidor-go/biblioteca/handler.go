package biblioteca

import (
	"log"
	"net/http"
	"os"
	"strconv"
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
	VehiculoID        string `json:"vehiculoId" binding:"required"`
	DuracionSegundos  int    `json:"duracionSegundos"`
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
	drivetrain := c.Query("drivetrain")
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

	// 2. Investigar con IA (o fallback si no hay API key)
	plan, err := InvestigarPlan(config)
	if err != nil {
		log.Printf("[handler] error investigando plan: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "error generando plan de mantenimiento"})
		return
	}

	// 3. Guardar en cache
	h.Cache.Set(config, plan)
	log.Printf("[handler] plan generado y cacheado para %s %s %d (%d ítems)", marca, modelo, anio, len(plan.Items))

	// 4. Determinar si requiere review (plan de fallback lo requiere)
	requiereReview := os.Getenv("ANTHROPIC_API_KEY") == ""

	c.JSON(http.StatusOK, shared.RespuestaPlan{
		Plan:           plan,
		DesdeCache:     false,
		TieneSwaps:     false,
		RequiereReview: requiereReview,
	})
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
