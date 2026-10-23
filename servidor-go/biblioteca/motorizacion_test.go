package biblioteca

import (
	"strings"
	"testing"
)

// TestPromptMotorizacionRestringeVocabulario valida que el prompt ofrezca
// exactamente los valores de los enums de la app (TipoCombustible y
// TipoTransmision en app/lib/models/enums.dart).
func TestPromptMotorizacionRestringeVocabulario(t *testing.T) {
	prompt := construirPromptMotorizacion("Kia", "Sportage", 2002, "")

	for _, combustible := range []string{"gasolina", "diesel", "hibrido", "electrico", "gas"} {
		if !strings.Contains(prompt, combustible) {
			t.Errorf("el prompt no ofrece el combustible canónico %q", combustible)
		}
	}
	for _, tipo := range []string{"manual", "automatica", "cvt", "dct", "automatedManual"} {
		if !strings.Contains(prompt, tipo) {
			t.Errorf("el prompt no ofrece el tipo de transmisión canónico %q", tipo)
		}
	}
	for _, drivetrain := range []string{"FWD", "RWD", "AWD", "4WD"} {
		if !strings.Contains(prompt, drivetrain) {
			t.Errorf("el prompt no ofrece el drivetrain canónico %q", drivetrain)
		}
	}
	for _, campo := range []string{"potenciaHp", "torqueNm"} {
		if !strings.Contains(prompt, campo) {
			t.Errorf("el prompt no pide el campo %q", campo)
		}
	}
	// Factores de conversión exactos — sin ellos Gemini puede reportar
	// PS/kW como HP sin convertir (mal etiquetado silencioso).
	for _, factor := range []string{"1.341", "0.9863", "1.3558"} {
		if !strings.Contains(prompt, factor) {
			t.Errorf("el prompt debe incluir el factor de conversión %s", factor)
		}
	}
	if !strings.Contains(prompt, "NO inventes") {
		t.Error("el prompt debe instruir explícitamente a no inventar datos")
	}
}

// TestInvestigarMotorizacionSinApiKey: sin GEMINI_API_KEY la búsqueda
// devuelve listas vacías y no error (los campos quedan manuales en la app).
func TestInvestigarMotorizacionSinApiKey(t *testing.T) {
	t.Setenv("GEMINI_API_KEY", "")

	resp := investigarMotorizacion("Kia", "Sportage", 2002, "")
	if len(resp.Motores) != 0 || len(resp.Transmisiones) != 0 {
		t.Errorf("sin API key debe devolver listas vacías, got %d motores y %d transmisiones",
			len(resp.Motores), len(resp.Transmisiones))
	}
}

// TestParsearRespuestaMotorizacion: el parseo es tolerante POR ÍTEM — un
// "cilindros" en string no tumba toda la respuesta (regresión: antes un
// Unmarshal directo del struct tipado la vaciaba completa) y los ítems
// basura se descartan solos.
func TestParsearRespuestaMotorizacion(t *testing.T) {
	resp := parsearRespuestaMotorizacion(`{
		"motores": [
			{"codigo": "K4J", "cilindrada": "1.4", "cilindros": "4", "potenciaHp": "98 HP"},
			"no soy un mapa",
			{"cilindros": 4}
		],
		"transmisiones": [
			{"codigo": "JR5", "marchas": "5"}
		],
		"drivetrain": "FWD"
	}`)

	if len(resp.Motores) != 1 {
		t.Fatalf("motores = %d, esperado 1 (basura sin código se descarta)", len(resp.Motores))
	}
	m := resp.Motores[0]
	if m.Codigo != "K4J" {
		t.Errorf("codigo = %q, esperado K4J", m.Codigo)
	}
	if m.Cilindrada != 1.4 || m.Cilindros != 4 {
		t.Errorf("cilindrada=%v cilindros=%d, esperado 1.4/4 (strings tolerados)",
			m.Cilindrada, m.Cilindros)
	}
	if m.PotenciaHP == nil || *m.PotenciaHP != 98 {
		t.Errorf("potenciaHp = %v, esperado *98", m.PotenciaHP)
	}
	if len(resp.Transmisiones) != 1 || resp.Transmisiones[0].Marchas != 5 {
		t.Errorf("transmisiones/marchas mal parseadas: %v", resp.Transmisiones)
	}
	if resp.Drivetrain != "FWD" {
		t.Errorf("drivetrain = %q, esperado FWD", resp.Drivetrain)
	}

	// JSON roto → listas vacías, sin panic.
	resp = parsearRespuestaMotorizacion("no pude encontrar datos")
	if len(resp.Motores) != 0 || len(resp.Transmisiones) != 0 {
		t.Errorf("texto sin JSON debe dar listas vacías, got %d/%d",
			len(resp.Motores), len(resp.Transmisiones))
	}
}

// TestParsearRespuestaMotorizacionCodigoPlaceholder: Gemini a veces
// escribe "Desconocido"/"N/A" como código (regresión real: las cajas del
// Kia Sportage 2002). Con descripcion cae a ella; sin descripcion la
// opción se descarta.
func TestParsearRespuestaMotorizacionCodigoPlaceholder(t *testing.T) {
	resp := parsearRespuestaMotorizacion(`{
		"motores": [
			{"codigo": "Desconocido", "descripcion": "2.0L I4", "combustible": "gasolina"}
		],
		"transmisiones": [
			{"codigo": "Desconocido", "descripcion": "manual 5 velocidades", "tipo": "manual", "marchas": 5},
			{"codigo": "N/A", "tipo": "automatica"}
		]
	}`)

	if len(resp.Motores) != 1 || resp.Motores[0].Codigo != "2.0L I4" {
		t.Errorf("motor con codigo placeholder debe caer a la descripcion: %v", resp.Motores)
	}
	if len(resp.Transmisiones) != 1 {
		t.Fatalf("transmision placeholder sin descripcion debe descartarse, got %d: %v",
			len(resp.Transmisiones), resp.Transmisiones)
	}
	if resp.Transmisiones[0].Codigo != "manual 5 velocidades" {
		t.Errorf("caja placeholder debe caer a la descripcion, got %q",
			resp.Transmisiones[0].Codigo)
	}
}

// TestExtraerJSON valida la limpieza de markdown/texto alrededor del JSON.
func TestExtraerJSON(t *testing.T) {
	casos := []struct {
		nombre   string
		entrada  string
		esperado string
	}{
		{"json limpio", `{"items": []}`, `{"items": []}`},
		{"con fence markdown", "```json\n{\"items\": [{\"id\": 1}]}\n```", `{"items": [{"id": 1}]}`},
		{"con texto alrededor", "Según la búsqueda:\n{\"motores\": []}\nEspero que sirva.", `{"motores": []}`},
		{"llave suelta en prosa posterior", "{\"motores\": [{\"codigo\": \"K4J\"}]}\nNota: {\"motores\": []} significa sin datos.", `{"motores": [{"codigo": "K4J"}]}`},
		{"sin json", "no pude encontrar datos", "no pude encontrar datos"},
	}

	for _, caso := range casos {
		t.Run(caso.nombre, func(t *testing.T) {
			got := extraerJSON(caso.entrada)
			if got != caso.esperado {
				t.Errorf("extraerJSON() = %q, esperado %q", got, caso.esperado)
			}
		})
	}
}
