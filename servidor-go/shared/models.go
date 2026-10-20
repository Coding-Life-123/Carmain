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
//
// El vocabulario de Categoria/ComponenteAplica/Fuente/Confianza lo define
// la app móvil (enums en app/lib/models/enums.dart). El prompt de Claude
// (biblioteca/investigador.go) y planFallback deben ceñirse estrictamente
// a él: la app valida contra enums y degrada los valores desconocidos.
type ItemMantenimiento struct {
	ID                string `json:"id"`
	Categoria         string `json:"categoria"` // motor | transmision | frenos | refrigeracion | diferencial | suspension | neumaticos | electrico | escape | inspeccion
	Descripcion       string `json:"descripcion"`
	ComponenteAplica  string `json:"componenteAplica"` // motor | transmision | diferencial | transferCase | frenos | suspension | otro
	IntervaloKm       int    `json:"intervaloKm"`
	IntervaloMeses    *int   `json:"intervaloMeses,omitempty"`
	IntervaloSeveroKm *int   `json:"intervaloSeveroKm,omitempty"`
	Fuente            string `json:"fuente"`    // oem | web | ia
	Confianza         string `json:"confianza"` // alta | media | baja
}

// PlanMantenimiento es el plan completo cacheado en la biblioteca central.
type PlanMantenimiento struct {
	ID              string              `json:"id"`
	Config          ConfigVehiculo      `json:"config"`
	Version         int                 `json:"version"`
	FechaGeneracion time.Time           `json:"fechaGeneracion"`
	Items           []ItemMantenimiento `json:"items"`
}

// OpcionMotor es una motorización de fábrica ofrecida para un modelo/año.
//
// Combustible sigue el vocabulario del enum TipoCombustible de la app
// (app/lib/models/enums.dart); valores fuera del conjunto se ignoran en
// el cliente.
type OpcionMotor struct {
	Codigo      string  `json:"codigo"`
	Descripcion string  `json:"descripcion,omitempty"`
	Combustible string  `json:"combustible,omitempty"` // gasolina | diesel | hibrido | electrico | gas
	Cilindrada  float64 `json:"cilindrada,omitempty"`  // litros
	Cilindros   int     `json:"cilindros,omitempty"`
	Aspiracion  string  `json:"aspiracion,omitempty"` // NA | Turbo | Twin-Turbo | Supercharger
	// Potencia (caballos de fuerza) y torque (newton-metro). Punteros:
	// nil = desconocido (omitempty lo omite y el formulario queda
	// manual). El parseo tolerante — strings con unidad, conversión
	// kW/PS/lb-ft/kgm con factores exactos — vive en
	// biblioteca.parsearOpcionMotor / numeroTolerante.
	PotenciaHP *float64 `json:"potenciaHp,omitempty"`
	TorqueNm   *float64 `json:"torqueNm,omitempty"`
}

// OpcionTransmision es una caja de fábrica ofrecida para un modelo/año.
//
// Tipo sigue el vocabulario del enum TipoTransmision de la app.
type OpcionTransmision struct {
	Codigo      string `json:"codigo"`
	Descripcion string `json:"descripcion,omitempty"`
	Tipo        string `json:"tipo,omitempty"` // manual | automatica | cvt | dct | automatedManual
	Marchas     int    `json:"marchas,omitempty"`
}

// RespuestaMotorizacion es lo que devuelve GET /api/motorizacion.
type RespuestaMotorizacion struct {
	Motores       []OpcionMotor       `json:"motores"`
	Transmisiones []OpcionTransmision `json:"transmisiones"`
	// Drivetrain típico del modelo/año (FWD|RWD|AWD|4WD) — mismo
	// vocabulario canónico que ConfigVehiculo. Vacío si es mixto/dudoso:
	// la app deja la elección del usuario.
	Drivetrain string `json:"drivetrain,omitempty"`
	DesdeCache bool   `json:"desdeCache"`
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
	Codigo         string    `json:"codigo"` // código/invite
	VehiculoID     string    `json:"vehiculoId"`
	DuenoDeviceID  string    `json:"duenoDeviceId"`
	MecanicoDevice string    `json:"mecanicoDevice,omitempty"`
	Activa         bool      `json:"activa"`
	CreadaEn       time.Time `json:"creadaEn"`
	ExpiraEn       time.Time `json:"expiraEn"`
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
