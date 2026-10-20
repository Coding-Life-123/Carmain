package biblioteca

import (
	"math"
	"strings"
	"testing"

	"github.com/carmain/servidor-go/shared"
)

// TestPromptComponenteRestringeVocabulario valida que los prompts de código
// ofrezcan exactamente los valores de los enums de la app (TipoCombustible
// y TipoTransmision en app/lib/models/enums.dart).
func TestPromptComponenteRestringeVocabulario(t *testing.T) {
	promptMotor := construirPromptComponente("motor", "K4J")
	for _, combustible := range []string{"gasolina", "diesel", "hibrido", "electrico", "gas"} {
		if !strings.Contains(promptMotor, combustible) {
			t.Errorf("el prompt de motor no ofrece el combustible canónico %q", combustible)
		}
	}
	if !strings.Contains(promptMotor, "NO inventes") {
		t.Error("el prompt de motor debe instruir explícitamente a no inventar datos")
	}
	for _, campo := range []string{"potenciaHp", "torqueNm"} {
		if !strings.Contains(promptMotor, campo) {
			t.Errorf("el prompt de motor debe pedir el campo %q", campo)
		}
	}
	for _, factor := range []string{"1.341", "0.9863", "1.3558"} {
		if !strings.Contains(promptMotor, factor) {
			t.Errorf("el prompt de motor debe incluir el factor de conversión %s", factor)
		}
	}

	promptTrans := construirPromptComponente("transmision", "JR5")
	for _, tipo := range []string{"manual", "automatica", "cvt", "dct", "automatedManual"} {
		if !strings.Contains(promptTrans, tipo) {
			t.Errorf("el prompt de transmisión no ofrece el tipo canónico %q", tipo)
		}
	}
	if !strings.Contains(promptTrans, "NO inventes") {
		t.Error("el prompt de transmisión debe instruir explícitamente a no inventar datos")
	}
}

// TestParsearRespuestaComponente valida el parseo tolerante de la respuesta
// de Gemini (números como strings incluidos) y el criterio de "encontrado":
// un código sin ningún detalle no sirve para auto-rellenar nada.
func TestParsearRespuestaComponente(t *testing.T) {
	// Motor con datos completos; cilindros llega como string, la potencia
	// como texto con unidad y otra en kW (debe CONVERTIR, no re-etiquetar).
	resp := parsearRespuestaComponente("motor",
		`{"codigo": "K4J", "descripcion": "1.4L I4 16V", "combustible": "gasolina", "cilindrada": 1.4, "cilindros": "4", "potenciaHp": "98 HP", "torqueNm": 127}`)
	if !resp.Encontrado {
		t.Fatal("debe ser encontrado con datos completos")
	}
	op, ok := resp.Opcion.(shared.OpcionMotor)
	if !ok {
		t.Fatalf("Opcion debe ser OpcionMotor, got %T", resp.Opcion)
	}
	if op.Cilindros != 4 {
		t.Errorf("cilindros como string debe parsearse a 4, got %d", op.Cilindros)
	}
	if op.Combustible != "gasolina" {
		t.Errorf("combustible = %q, esperado %q", op.Combustible, "gasolina")
	}
	if op.Cilindrada != 1.4 {
		t.Errorf("cilindrada = %v, esperado 1.4", op.Cilindrada)
	}
	if op.PotenciaHP == nil || *op.PotenciaHP != 98 {
		t.Errorf("potenciaHp con unidad debe parsearse a 98, got %v", op.PotenciaHP)
	}
	if op.TorqueNm == nil || *op.TorqueNm != 127 {
		t.Errorf("torqueNm = %v, esperado 127", op.TorqueNm)
	}

	// Potencia declarada en kW: convierte con el factor exacto.
	resp = parsearRespuestaComponente("motor",
		`{"codigo": "M156", "potenciaHp": "141 kW"}`)
	if !resp.Encontrado {
		t.Fatal("con potencia debe ser encontrado")
	}
	op = resp.Opcion.(shared.OpcionMotor)
	if op.PotenciaHP == nil || *op.PotenciaHP != 141*1.341 {
		t.Errorf("141 kW debe convertir a %v HP, got %v", 141*1.341, op.PotenciaHP)
	}

	// Un código con SOLO potencia/torque igual auto-rellena algo.
	resp = parsearRespuestaComponente("motor",
		`{"codigo": "MAGIC", "potenciaHp": 400}`)
	if !resp.Encontrado {
		t.Error("potencia sola debe contar como encontrado")
	}

	// Solo el código → no encontrado (nada que auto-rellenar, y no se
	// cachea para reintentar la próxima vez).
	resp = parsearRespuestaComponente("motor", `{"codigo": "XYZ"}`)
	if resp.Encontrado {
		t.Error("un código sin detalles no cuenta como encontrado")
	}

	// Transmisión con tipo y marchas.
	resp = parsearRespuestaComponente("transmision",
		`{"codigo": "JR5", "tipo": "manual", "marchas": 5}`)
	if !resp.Encontrado {
		t.Fatal("la transmisión con tipo y marchas debe ser encontrada")
	}
	opT, ok := resp.Opcion.(shared.OpcionTransmision)
	if !ok {
		t.Fatalf("Opcion debe ser OpcionTransmision, got %T", resp.Opcion)
	}
	if opT.Marchas != 5 || opT.Tipo != "manual" {
		t.Errorf("marchas=%d tipo=%q, esperado 5/manual", opT.Marchas, opT.Tipo)
	}

	// Texto sin JSON → no encontrado, sin panic.
	resp = parsearRespuestaComponente("motor", "no pude encontrar datos del código")
	if resp.Encontrado {
		t.Error("texto sin JSON no debe ser encontrado")
	}
}

// TestInvestigarComponenteSinApiKey: sin GEMINI_API_KEY no hay datos —
// encontrado=false y la app deja los campos manuales.
func TestInvestigarComponenteSinApiKey(t *testing.T) {
	t.Setenv("GEMINI_API_KEY", "")

	resp := investigarComponente("motor", "K4J")
	if resp.Encontrado {
		t.Error("sin API key no debe encontrar nada")
	}
}

// TestNumeroTolerante valida la normalización de potencia/torque: números,
// strings con unidad (convertidos con factor exacto si son conocidos,
// rechazados si no), y formatos ambiguos → rechazados.
func TestNumeroTolerante(t *testing.T) {
	casos := []struct {
		entrada any
		unidad  string
		valor   float64
		ok      bool
	}{
		{255.0, "HP", 255, true},
		{"255", "HP", 255, true},
		{"255 HP", "HP", 255, true},
		{"255hp", "HP", 255, true},
		{"350 Nm", "Nm", 350, true},
		{"141 kW", "HP", 141 * 1.341, true},  // convierte, no re-etiqueta
		{"190 PS", "HP", 190 * 0.9863, true}, //
		{"184 lb-ft", "Nm", 184 * 1.3558, true},
		{"35 kgm", "Nm", 35 * 9.8067, true},
		{"110 wattios", "HP", 0, false}, // unidad desconocida → rechazar
		{"1,255", "HP", 1255, true},     // coma de miles con 3 dígitos
		{"1,200 Nm", "Nm", 1200, true},
		{"255,5", "HP", 0, false}, // coma decimal ambigua → rechazar
		{"1.200", "HP", 0, false}, // punto de miles ambiguo → rechazar
		{"254.79", "HP", 254.79, true},
		{0, "HP", 0, false},
		{-10.0, "HP", 0, false},
		{"", "HP", 0, false},
		{"no numérico", "HP", 0, false},
		{nil, "HP", 0, false},
		{true, "HP", 0, false},
		{255.0, "kg", 0, false}, // unidad sin vocabulario
	}
	for _, caso := range casos {
		v, ok := numeroTolerante(caso.entrada, caso.unidad)
		// Tolerancia en vez de igualdad exacta: el producto constante del
		// caso puede redondear distinto que el producto en runtime.
		if ok != caso.ok || (ok && math.Abs(v-caso.valor) > 1e-9) {
			t.Errorf("numeroTolerante(%v, %q) = (%v, %v), esperado (%v, %v)",
				caso.entrada, caso.unidad, v, ok, caso.valor, caso.ok)
		}
	}
}
