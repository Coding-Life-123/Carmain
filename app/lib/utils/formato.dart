import 'package:flutter/services.dart';

// Formateadores compartidos por todas las pantallas, para que un mismo
// dato (km, fecha, moneda) se vea igual en el dashboard, el detalle y los formularios.

/// Formatea un entero con separador de miles (punto): 125000 -> "125.000".
String formatearNumero(int valor) {
  final negativo = valor < 0;
  final str = valor.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write('.');
    buffer.write(str[i]);
  }
  return negativo ? '-$buffer' : buffer.toString();
}

/// Kilometraje con unidad: 125000 -> "125.000 km".
String formatearKm(int km) => '${formatearNumero(km)} km';

/// Formatea un valor monetario en Pesos Colombianos (COP): 85000 -> "$ 85.000".
String formatearCop(num valor) {
  final entero = valor.round();
  if (entero < 0) {
    return '-\$ ${formatearNumero(entero.abs())}';
  }
  return '\$ ${formatearNumero(entero)}';
}

/// Fecha como dd/MM/yyyy.
String formatearFecha(DateTime fecha) {
  final d = fecha.day.toString().padLeft(2, '0');
  final m = fecha.month.toString().padLeft(2, '0');
  return '$d/$m/${fecha.year}';
}

/// Parsea un texto de costo en Pesos Colombianos (COP) respetando la convención
/// local: el punto '.' es separador de miles y la coma ',' es decimal.
///
/// Soporta:
/// - "85000" -> 85000.0
/// - "85.000" -> 85000.0
/// - "1.200.000" -> 1200000.0
/// - "$ 1.200.000" -> 1200000.0
/// - "85.000,50" -> 85000.5
/// - "85000,50" -> 85000.5
/// - "85.5" (un solo punto no agrupado de a 3) -> 85.5
///
/// Retorna `null` si no es un número válido, es negativo o supera 999.999.999 COP.
double? parsearCop(String? texto) {
  if (texto == null) return null;
  var limpio = texto.replaceAll(r'$', '').trim();
  if (limpio.isEmpty) return null;

  // Si contiene puntos y comas, ej 1.200.000,50
  if (limpio.contains('.') && limpio.contains(',')) {
    // Puntos son miles, coma es decimal
    limpio = limpio.replaceAll('.', '').replaceAll(',', '.');
  } else if (limpio.contains('.')) {
    // Si contiene solo puntos, verificar si son separadores de miles
    final partes = limpio.split('.');
    final esSeparadorMiles =
        partes.length > 1 && partes.skip(1).every((p) => p.length == 3);
    if (esSeparadorMiles) {
      limpio = limpio.replaceAll('.', '');
    }
  } else if (limpio.contains(',')) {
    // Coma aislada es decimal
    limpio = limpio.replaceAll(',', '.');
  }

  final valor = double.tryParse(limpio);
  if (valor == null || valor < 0 || valor > 999999999) return null;
  return valor;
}

/// Formateador de entrada para campos de moneda COP que agrega separadores de miles (puntos)
/// en tiempo real mientras el usuario escribe solo dígitos.
class CopInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Mantener solo dígitos
    final digitos = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digitos.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final valorInt = int.tryParse(digitos);
    if (valorInt == null) return oldValue;

    final nuevoTexto = formatearNumero(valorInt);

    return TextEditingValue(
      text: nuevoTexto,
      selection: TextSelection.collapsed(offset: nuevoTexto.length),
    );
  }
}
