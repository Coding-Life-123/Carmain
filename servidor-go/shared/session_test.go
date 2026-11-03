package shared

import (
	"fmt"
	"testing"
	"time"
)

func TestSesionesTokenLargoYCodigoCorto(t *testing.T) {
	m := &ManejadorSesiones{
		sesiones: make(map[string]*SesionRelay),
	}

	snapshot := map[string]interface{}{"marca": "Toyota", "modelo": "Supra"}
	s := m.Crear("", "veh-1", 1*time.Hour, snapshot)

	if len(s.Codigo) != 6 {
		t.Fatalf("código corto esperado de 6 caracteres, got %s", s.Codigo)
	}
	if len(s.TokenLargo) != 32 {
		t.Fatalf("token largo esperado de 32 caracteres hex, got %s", s.TokenLargo)
	}

	// Validar por código corto
	s1, ok1 := m.Validar(s.Codigo)
	if !ok1 || s1 == nil {
		t.Fatal("validación por código corto falló")
	}
	if s1.ConsultadaEn == nil {
		t.Fatal("ConsultadaEn debería haberse inicializado al validar")
	}

	// Validar por token largo
	s2, ok2 := m.Validar(s.TokenLargo)
	if !ok2 || s2 == nil {
		t.Fatal("validación por token largo falló")
	}
	if s1 != s2 {
		t.Fatal("código corto y token largo deben referenciar la misma sesión")
	}
}

func TestGuardarPropuestaIdempotenciaYLimite(t *testing.T) {
	m := &ManejadorSesiones{
		sesiones: make(map[string]*SesionRelay),
	}

	s := m.Crear("ABC123", "veh-1", 1*time.Hour, nil)

	p1 := map[string]interface{}{
		"id":          "uuid-1",
		"kilometraje": 50000,
	}

	// Primer guardado: exitoso, no existía
	guardado, yaExistia := m.GuardarPropuesta(s.Codigo, p1)
	if !guardado || yaExistia {
		t.Fatalf("primer guardado esperado guardado=true, yaExistia=false; got (%v, %v)", guardado, yaExistia)
	}

	// Reintento con mismo ID (idempotencia)
	guardado2, yaExistia2 := m.GuardarPropuesta(s.Codigo, p1)
	if !guardado2 || !yaExistia2 {
		t.Fatalf("reintento esperado guardado=true, yaExistia=true; got (%v, %v)", guardado2, yaExistia2)
	}

	propuestas, ok := m.ObtenerPropuestas(s.Codigo)
	if !ok || len(propuestas) != 1 {
		t.Fatalf("se esperaba exactamente 1 propuesta en el buzón tras reintento, got %d", len(propuestas))
	}

	// Probar límite de 20 propuestas
	for i := 2; i <= 20; i++ {
		p := map[string]interface{}{"id": fmt.Sprintf("uuid-%d", i), "i": i}
		m.GuardarPropuesta(s.Codigo, p)
	}

	// Propuesta 21 debe ser rechazada
	p21 := map[string]interface{}{"id": "uuid-21"}
	guardado21, _ := m.GuardarPropuesta(s.Codigo, p21)
	if guardado21 {
		t.Fatal("se esperaba rechazo al superar el límite de 20 propuestas por sesión")
	}
}

func TestLimpiarExpiradas(t *testing.T) {
	m := &ManejadorSesiones{
		sesiones: make(map[string]*SesionRelay),
	}

	// Sesión que expira en el pasado
	s := m.Crear("EXPIR1", "veh-exp", -1*time.Minute, nil)

	if _, ok := m.Validar(s.Codigo); ok {
		t.Fatal("sesión con fecha pasada no debe ser válida")
	}

	eliminadas := m.LimpiarExpiradas()
	if eliminadas < 2 { // tanto por código como por tokenLargo
		t.Fatalf("se esperaban al menos 2 entradas eliminadas, got %d", eliminadas)
	}
}
