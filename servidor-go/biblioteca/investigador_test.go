package biblioteca

import (
	"strings"
	"testing"

	"github.com/carmain/servidor-go/shared"
)

// Vocabulario canónico del contrato con la app móvil
// (enums en app/lib/models/enums.dart). Si un valor de aquí deja de
// existir en la app, este test lo detecta antes de que llegue a producción.
var categoriasValidas = map[string]bool{
	"motor": true, "transmision": true, "frenos": true, "refrigeracion": true,
	"diferencial": true, "suspension": true, "neumaticos": true, "electrico": true,
	"escape": true, "inspeccion": true,
}

var componentesValidos = map[string]bool{
	"motor": true, "transmision": true, "diferencial": true, "transferCase": true,
	"frenos": true, "suspension": true, "otro": true,
}

var confianzasValidas = map[string]bool{
	"alta": true, "media": true, "baja": true,
}

func configPrueba(drivetrain string) shared.ConfigVehiculo {
	return shared.ConfigVehiculo{
		Marca:       "Toyota",
		Modelo:      "Supra",
		Anio:        1997,
		Drivetrain:  drivetrain,
		MotorCodigo: "2JZ-GTE",
		TransCodigo: "R154",
	}
}

// TestPlanFallbackUsaVocabularioCanonico valida que el plan de fallback
// solo emita valores que la app móvil sabe parsear.
func TestPlanFallbackUsaVocabularioCanonico(t *testing.T) {
	for _, drivetrain := range []string{"FWD", "RWD", "AWD", "4WD"} {
		plan := planFallback(configPrueba(drivetrain))
		if len(plan.Items) == 0 {
			t.Fatalf("drivetrain %s: el plan de fallback no tiene ítems", drivetrain)
		}

		for _, item := range plan.Items {
			if !categoriasValidas[item.Categoria] {
				t.Errorf("drivetrain %s: categoría inválida %q en ítem %q", drivetrain, item.Categoria, item.ID)
			}
			if !componentesValidos[item.ComponenteAplica] {
				t.Errorf("drivetrain %s: componenteAplica inválido %q en ítem %q", drivetrain, item.ComponenteAplica, item.ID)
			}
			if item.Fuente != "ia" {
				t.Errorf("drivetrain %s: fuente inválida %q en ítem %q (esperada \"ia\")", drivetrain, item.Fuente, item.ID)
			}
			if !confianzasValidas[item.Confianza] {
				t.Errorf("drivetrain %s: confianza inválida %q en ítem %q", drivetrain, item.Confianza, item.ID)
			}
			if item.IntervaloKm <= 0 {
				t.Errorf("drivetrain %s: intervaloKm inválido (%d) en ítem %q", drivetrain, item.IntervaloKm, item.ID)
			}
		}
	}
}

// TestPlanFallbackAWDIncluyeDiferencialYTransfer valida que AWD/4WD
// agreguen el servicio de diferencial y transfer case.
func TestPlanFallbackAWDIncluyeDiferencialYTransfer(t *testing.T) {
	for _, drivetrain := range []string{"AWD", "4WD"} {
		ids := map[string]bool{}
		for _, item := range planFallback(configPrueba(drivetrain)).Items {
			ids[item.ID] = true
		}
		if !ids["diferencial-fluido"] {
			t.Errorf("drivetrain %s: falta el servicio de diferencial", drivetrain)
		}
		if !ids["transfer-case"] {
			t.Errorf("drivetrain %s: falta el servicio de transfer case", drivetrain)
		}
	}
}

// TestPromptRestringeVocabularioCanonico valida que el prompt de Claude
// ofrezca exactamente el vocabulario del contrato (y no el retirado).
func TestPromptRestringeVocabularioCanonico(t *testing.T) {
	prompt := construirPrompt(configPrueba("RWD"))

	for categoria := range categoriasValidas {
		if !strings.Contains(prompt, categoria) {
			t.Errorf("el prompt no ofrece la categoría canónica %q", categoria)
		}
	}
	for _, componente := range []string{"transferCase", "otro"} {
		if !strings.Contains(prompt, componente) {
			t.Errorf("el prompt no ofrece el componente canónico %q", componente)
		}
	}
	if strings.Contains(prompt, "fluidos | filtros") {
		t.Error("el prompt aún ofrece el vocabulario retirado (fluidos | filtros)")
	}
	if strings.Contains(prompt, "transfer-case") {
		t.Error("el prompt ofrece \"transfer-case\" en vez del canónico \"transferCase\"")
	}
}
