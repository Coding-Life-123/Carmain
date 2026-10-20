import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/providers.dart';
import 'screens/crear_vehiculo/crear_vehiculo_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/detalle_vehiculo/detalle_vehiculo_screen.dart';
import 'screens/registrar_mantenimiento/registrar_mantenimiento_screen.dart';

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD32F2F),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD32F2F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
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

