import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/providers.dart';
import 'screens/crear_vehiculo/crear_vehiculo_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/detalle_vehiculo/detalle_vehiculo_screen.dart';
import 'screens/registrar_mantenimiento/registrar_mantenimiento_screen.dart';

/// Paleta curada — automoción premium: navy profundo, dorado vintage y
/// verde racing. Nada de `fromSeed`: cada rol definido a mano para que
/// la app no se sienta "a lo Google". El dark invierte la jerarquía
/// (crema sobre negro azulado) manteniendo los acentos.
final _esquemaLight = ColorScheme.light(
  primary: const Color(0xFF1A1A2E),
  onPrimary: const Color(0xFFFAF8F5),
  primaryContainer: const Color(0xFFE4E2F0),
  onPrimaryContainer: const Color(0xFF1A1A2E),
  secondary: const Color(0xFFC9A96E),
  onSecondary: const Color(0xFF1A1A2E),
  secondaryContainer: const Color(0xFFF0E6D2),
  onSecondaryContainer: const Color(0xFF5C4A24),
  tertiary: const Color(0xFF2D6A4F),
  onTertiary: const Color(0xFFFAF8F5),
  tertiaryContainer: const Color(0xFFD8EAE0),
  onTertiaryContainer: const Color(0xFF1E4634),
  surface: const Color(0xFFFAF8F5),
  onSurface: const Color(0xFF1A1A2E),
  onSurfaceVariant: const Color(0xFF4A4A58),
  surfaceContainerHighest: const Color(0xFFEDE8E0),
  outline: const Color(0xFFD4C5B0),
  outlineVariant: const Color(0xFFE8E0D4),
  error: const Color(0xFFB33951),
  onError: Color(0xFFFFFFFF),
);

final _esquemaDark = ColorScheme.dark(
  primary: const Color(0xFFE8E0D4),
  onPrimary: const Color(0xFF1A1A2E),
  primaryContainer: const Color(0xFF34344E),
  onPrimaryContainer: const Color(0xFFE8E0D4),
  secondary: const Color(0xFFC9A96E),
  onSecondary: const Color(0xFF1A1A2E),
  secondaryContainer: const Color(0xFF4A3D24),
  onSecondaryContainer: const Color(0xFFE8D9B5),
  tertiary: const Color(0xFF52B788),
  onTertiary: const Color(0xFF0F0F1A),
  tertiaryContainer: const Color(0xFF1E4634),
  onTertiaryContainer: const Color(0xFFB8E6CC),
  surface: const Color(0xFF0F0F1A),
  onSurface: const Color(0xFFE8E0D4),
  onSurfaceVariant: const Color(0xFFB4B0A8),
  surfaceContainerHighest: const Color(0xFF1E1E2E),
  outline: const Color(0xFF8A8578),
  outlineVariant: const Color(0xFF2E2E40),
  error: const Color(0xFFFF6B6B),
  onError: const Color(0xFF0F0F1A),
);

/// Tipografía: Inter para body, Outfit para headings — con los pesos de
/// los títulos reforzados para jerarquía.
TextTheme _textTheme(Brightness brillo) {
  final base = brillo == Brightness.light
      ? ThemeData.light().textTheme
      : ThemeData.dark().textTheme;
  final body = GoogleFonts.interTextTheme(base);
  final headings = GoogleFonts.outfitTextTheme(base);
  return body.copyWith(
    headlineLarge: headings.headlineLarge,
    headlineMedium: headings.headlineMedium,
    headlineSmall: headings.headlineSmall,
    titleLarge: headings.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    titleMedium: headings.titleMedium?.copyWith(fontWeight: FontWeight.w600),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Si shared_preferences falla (plugin roto, disco lleno, prefs corruptas),
  // la app debe arrancar igual — solo se pierde la persistencia de ajustes.
  // Nunca bloquear runApp() por esto: fue la causa de una pantalla negra
  // en release (NoSuchMethodError del plugin por minificación de R8).
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('[main] shared_preferences no disponible ($e) '
        '— arrancando sin persistir ajustes');
  }

  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const CarMainApp(),
  ));
}

class CarMainApp extends StatelessWidget {
  const CarMainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CarMain',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: _esquemaLight,
        useMaterial3: true,
        textTheme: _textTheme(Brightness.light),
      ),
      darkTheme: ThemeData(
        colorScheme: _esquemaDark,
        useMaterial3: true,
        textTheme: _textTheme(Brightness.dark),
      ),
      home: const DashboardScreen(),
      routes: {
        '/crear-vehiculo': (_) => const CrearVehiculoScreen(),
      },
      onGenerateRoute: (settings) {
        final name = settings.name;
        if (name != null) {
          if (name.startsWith('/detalle/')) {
            final id = name.replaceFirst('/detalle/', '');
            return MaterialPageRoute(
              builder: (_) => DetalleVehiculoScreen(vehiculoId: id),
            );
          }
          if (name.startsWith('/registrar/')) {
            final id = name.replaceFirst('/registrar/', '');
            return MaterialPageRoute(
              builder: (_) => RegistrarMantenimientoScreen(vehiculoId: id),
            );
          }
        }
        return null;
      },
    );
  }
}

