package shared

import "time"

// ConfigVehiculo es la clave de cache para la biblioteca de planes.
// Identifica una configuración única de vehículo para buscar/generar su plan.
type ConfigVehiculo struct {
	Marca       string `json:"marca"`
	Modelo      string `json:"modelo"`
	Anio        int    `json:"anio"`
	Trim        string `json:"trim,omitempty"`
	Drivetrain  string `json:"drivetrain"` // FWD | RWD | AWD | 4WD
	MotorCodigo string `json:"motorCodigo"`
	TransCodigo string `json:"transCodigo"`
}

// ItemMantenimiento es un ítem individual del plan.
type ItemMantenimiento struct {
	ID                 string  `json:"id"`
	Categoria          string  `json:"categoria"`
	Descripcion        string  `json:"descripcion"`
	ComponenteAplica   string  `json:"componenteAplica"`
	IntervaloKm        int     `json:"intervaloKm"`
	IntervaloMeses     *int    `json:"intervaloMeses,omitempty"`
	IntervaloSeveroKm  *int    `json:"intervaloSeveroKm,omitempty"`
	Fuente             string  `json:"fuente"`  // OEM | web | ia
	Confianza          string  `json:"confianza"` // alta | media | baja
}

// PlanMantenimiento es el plan completo cacheado en la biblioteca central.
type PlanMantenimiento struct {
	ID              string               `json:"id"`
	Config          ConfigVehiculo      `json:"config"`
	Version         int                  `json:"version"`
	FechaGeneracion time.Time            `json:"fechaGeneracion"`
	Items           []ItemMantenimiento  `json:"items"`
}

// SolicitudPlan es lo que el móvil envía para obtener un plan.
type SolicitudPlan struct {
	Marca       string `json:"marca" binding:"required"`
	Modelo      string `json:"modelo" binding:"required"`
	Anio        int    `json:"anio" binding:"required"`
	Trim        string `json:"trim"`
	Drivetrain  string `json:"drivetrain" binding:"required"`
	MotorCodigo string `json:"motorCodigo" binding:"required"`
	TransCodigo string `json:"transCodigo" binding:"required"`
}

// RespuestaPlan es lo que el servidor devuelve.
type RespuestaPlan struct {
	Plan           *PlanMantenimiento `json:"plan"`
	DesdeCache     bool               `json:"desdeCache"`
	TieneSwaps     bool               `json:"tieneSwaps"`
	RequiereReview bool               `json:"requiereReview"`
}

// SesionRelay representa una sesión de compartido entre dueño y mecánico.
type SesionRelay struct {
	Codigo         string     `json:"codigo"` // código/invite
	VehiculoID     string     `json:"vehiculoId"`
	DuenoDeviceID  string     `json:"duenoDeviceId"`
	MecanicoDevice string     `json:"mecanicoDevice,omitempty"`
	Activa         bool       `json:"activa"`
	CreadaEn       time.Time  `json:"creadaEn"`
	ExpiraEn       time.Time  `json:"expiraEn"`
}

// MensajeRelay es un mensaje que rutea el relay entre dispositivos.
// El payload va cifrado E2EE — el relay no puede leerlo.
type MensajeRelay struct {
	Tipo      string `json:"tipo"` // snapshot | registro | revocacion | ack
	De        string `json:"de"`   // device ID remitente
	Para      string `json:"para"` // device ID destinatario
	SesionID  string `json:"sesionId"`
	Payload   []byte `json:"payload"` // blob cifrado
	Timestamp int64  `json:"timestamp"`
}
