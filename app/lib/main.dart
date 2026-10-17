import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/crear_vehiculo/crear_vehiculo_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/detalle_vehiculo/detalle_vehiculo_screen.dart';
import 'screens/registrar_mantenimiento/registrar_mantenimiento_screen.dart';

void main() {
  runApp(const ProviderScope(child: CarMainApp()));
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

