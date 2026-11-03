import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_main/models/componente.dart';
import 'package:car_main/models/enums.dart';
import 'package:car_main/models/vehiculo.dart';
import 'package:car_main/widgets/vehiculo_avatar.dart';

void main() {
  group('normalizarMarcaSlug', () {
    test('normaliza marcas directas', () {
      expect(normalizarMarcaSlug('BMW'), 'bmw');
      expect(normalizarMarcaSlug('Toyota'), 'toyota');
      expect(normalizarMarcaSlug('Honda'), 'honda');
      expect(normalizarMarcaSlug('Ford'), 'ford');
    });

    test('normaliza alias y variantes compuestas', () {
      expect(normalizarMarcaSlug('VW'), 'volkswagen');
      expect(normalizarMarcaSlug('Chevy'), 'chevrolet');
      expect(normalizarMarcaSlug('Mercedes-Benz'), 'mercedes-benz');
      expect(normalizarMarcaSlug('Mercedes Benz'), 'mercedes-benz');
      expect(normalizarMarcaSlug('Alfa Romeo'), 'alfa-romeo');
      expect(normalizarMarcaSlug('Land Rover'), 'land-rover');
      expect(normalizarMarcaSlug('Aston Martin'), 'aston-martin');
    });

    test('limpia caracteres extraños y espacios', () {
      expect(normalizarMarcaSlug('  Nissan   '), 'nissan');
      expect(normalizarMarcaSlug('Audi!!'), 'audi');
    });
  });

  group('detectarTipoSilueta heurísticas', () {
    Vehiculo crearVehiculo({
      required String marca,
      required String modelo,
      String? trim,
      TipoCombustible combustible = TipoCombustible.gasolina,
      double? cilindrada,
      String? descMotor,
    }) {
      return Vehiculo(
        id: 'test-v',
        propietarioId: 'local',
        marca: marca,
        modelo: modelo,
        anio: 2024,
        placa: 'ABC-123',
        trim: trim,
        drivetrain: Drivetrain.fourWd,
        tipoUso: TipoUso.normal,
        motor: Motor(
          codigo: 'ENG-TEST',
          tipoCombustible: combustible,
          cilindrada: cilindrada,
          descripcion: descMotor,
        ),
        transmision: const Transmision(codigo: 'TRN-TEST', tipo: TipoTransmision.automatica),
        kilometrajeActual: 10000,
      );
    }

    test('clasifica tractomulas correctamente', () {
      final kenworth = crearVehiculo(marca: 'Kenworth', modelo: 'T800');
      final cascadia = crearVehiculo(marca: 'Freightliner', modelo: 'Cascadia');
      final mack = crearVehiculo(marca: 'Mack', modelo: 'Anthem');
      final motorGrande = crearVehiculo(
        marca: 'Internacional',
        modelo: 'Cabezote',
        cilindrada: 12.0,
      );

      expect(detectarTipoSilueta(kenworth), TipoSiluetaVehiculo.mula);
      expect(detectarTipoSilueta(cascadia), TipoSiluetaVehiculo.mula);
      expect(detectarTipoSilueta(mack), TipoSiluetaVehiculo.mula);
      expect(detectarTipoSilueta(motorGrande), TipoSiluetaVehiculo.mula);
    });

    test('clasifica camiones ligeros / cabover correctamente', () {
      final npr = crearVehiculo(marca: 'Chevrolet', modelo: 'NPR Reward');
      final hino = crearVehiculo(marca: 'Hino', modelo: 'Dutro 300');
      final fuso = crearVehiculo(marca: 'Fuso', modelo: 'Canter');
      final foton = crearVehiculo(marca: 'Fotón', modelo: 'Aumark');

      expect(detectarTipoSilueta(npr), TipoSiluetaVehiculo.camionLigero);
      expect(detectarTipoSilueta(hino), TipoSiluetaVehiculo.camionLigero);
      expect(detectarTipoSilueta(fuso), TipoSiluetaVehiculo.camionLigero);
      expect(detectarTipoSilueta(foton), TipoSiluetaVehiculo.camionLigero);
    });

    test('clasifica camiones pesados / heavy duty / dually correctamente', () {
      final f450 = crearVehiculo(marca: 'Ford', modelo: 'F-450 Super Duty');
      final f350 = crearVehiculo(marca: 'Ford', modelo: 'F-350');
      final silveradoHD = crearVehiculo(marca: 'Chevrolet', modelo: 'Silverado 3500 HD');
      final ram3500 = crearVehiculo(marca: 'RAM', modelo: '3500 Heavy Duty');

      expect(detectarTipoSilueta(f450), TipoSiluetaVehiculo.camionPesado);
      expect(detectarTipoSilueta(f350), TipoSiluetaVehiculo.camionPesado);
      expect(detectarTipoSilueta(silveradoHD), TipoSiluetaVehiculo.camionPesado);
      expect(detectarTipoSilueta(ram3500), TipoSiluetaVehiculo.camionPesado);
    });

    test('clasifica pick-ups correctamente', () {
      final hilux = crearVehiculo(marca: 'Toyota', modelo: 'Hilux');
      final ranger = crearVehiculo(marca: 'Ford', modelo: 'Ranger Raptor');
      final frontier = crearVehiculo(marca: 'Nissan', modelo: 'Frontier PRO-4X');
      final dmax = crearVehiculo(marca: 'Isuzu', modelo: 'D-Max');

      expect(detectarTipoSilueta(hilux), TipoSiluetaVehiculo.pickup);
      expect(detectarTipoSilueta(ranger), TipoSiluetaVehiculo.pickup);
      expect(detectarTipoSilueta(frontier), TipoSiluetaVehiculo.pickup);
      expect(detectarTipoSilueta(dmax), TipoSiluetaVehiculo.pickup);
    });

    test('clasifica vans / furgones cerrados correctamente', () {
      final hiace = crearVehiculo(marca: 'Toyota', modelo: 'HiAce');
      final urvan = crearVehiculo(marca: 'Nissan', modelo: 'Urvan');
      final transit = crearVehiculo(marca: 'Ford', modelo: 'Transit');
      final sprinter = crearVehiculo(marca: 'Mercedes-Benz', modelo: 'Sprinter');

      expect(detectarTipoSilueta(hiace), TipoSiluetaVehiculo.van);
      expect(detectarTipoSilueta(urvan), TipoSiluetaVehiculo.van);
      expect(detectarTipoSilueta(transit), TipoSiluetaVehiculo.van);
      expect(detectarTipoSilueta(sprinter), TipoSiluetaVehiculo.van);
    });

    test('clasifica SUVs / crossovers correctamente incluyendo Toyota Sahara LC300 GXR', () {
      final sahara = crearVehiculo(marca: 'Toyota', modelo: 'Sahara LC300', trim: 'GXR');
      final saharaSimple = crearVehiculo(marca: 'Toyota', modelo: 'Sahara');
      final lc200 = crearVehiculo(marca: 'Toyota', modelo: 'LC200', trim: 'VXR');
      final pradoTxl = crearVehiculo(marca: 'Toyota', modelo: 'Land Cruiser Prado', trim: 'TXL');
      final prado = crearVehiculo(marca: 'Toyota', modelo: 'Land Cruiser Prado');
      final cx30 = crearVehiculo(marca: 'Mazda', modelo: 'CX-30 Grand Touring');
      final tracker = crearVehiculo(marca: 'Chevrolet', modelo: 'Tracker Premier');
      final duster = crearVehiculo(marca: 'Renault', modelo: 'Duster Iconic');
      final wrangler = crearVehiculo(marca: 'Jeep', modelo: 'Wrangler Rubicon');

      expect(detectarTipoSilueta(sahara), TipoSiluetaVehiculo.suv);
      expect(detectarTipoSilueta(saharaSimple), TipoSiluetaVehiculo.suv);
      expect(detectarTipoSilueta(lc200), TipoSiluetaVehiculo.suv);
      expect(detectarTipoSilueta(pradoTxl), TipoSiluetaVehiculo.suv);
      expect(detectarTipoSilueta(prado), TipoSiluetaVehiculo.suv);
      expect(detectarTipoSilueta(cx30), TipoSiluetaVehiculo.suv);
      expect(detectarTipoSilueta(tracker), TipoSiluetaVehiculo.suv);
      expect(detectarTipoSilueta(duster), TipoSiluetaVehiculo.suv);
      expect(detectarTipoSilueta(wrangler), TipoSiluetaVehiculo.suv);
    });

    test('clasifica automóviles / sedanes / coupés por defecto', () {
      final supra = crearVehiculo(marca: 'Toyota', modelo: 'Supra');
      final spark = crearVehiculo(marca: 'Chevrolet', modelo: 'Spark GT');
      final civic = crearVehiculo(marca: 'Honda', modelo: 'Civic Si');
      final corolla = crearVehiculo(marca: 'Toyota', modelo: 'Corolla Sedán');

      expect(detectarTipoSilueta(supra), TipoSiluetaVehiculo.automovil);
      expect(detectarTipoSilueta(spark), TipoSiluetaVehiculo.automovil);
      expect(detectarTipoSilueta(civic), TipoSiluetaVehiculo.automovil);
      expect(detectarTipoSilueta(corolla), TipoSiluetaVehiculo.automovil);
    });
  });

  group('VehiculoAvatar y VehiculoSiluetaFondo widgets', () {
    testWidgets('VehiculoAvatar renderiza exclusivamente el logo de la marca', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VehiculoAvatar(
              marca: 'Toyota',
              size: 60,
            ),
          ),
        ),
      );

      expect(find.byType(VehiculoAvatar), findsOneWidget);
    });

    testWidgets('VehiculoSiluetaFondo renderiza cada una de las 7 morfologías vectoriales',
        (tester) async {
      for (final tipo in TipoSiluetaVehiculo.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VehiculoSiluetaFondo(tipo: tipo),
            ),
          ),
        );

        expect(find.byType(VehiculoSiluetaFondo), findsOneWidget);
        expect(find.byType(CustomPaint), findsWidgets);
      }
    });

    testWidgets('VehiculoSiluetaFondo adapta la silueta automáticamente al pasar Vehiculo',
        (tester) async {
      final vF450 = Vehiculo(
        id: 'v-hd',
        propietarioId: 'local',
        marca: 'Ford',
        modelo: 'F-450 Super Duty',
        anio: 2026,
        placa: 'FRD-450',
        drivetrain: Drivetrain.fourWd,
        tipoUso: TipoUso.severo,
        motor: const Motor(
          codigo: 'PowerStroke-6.7',
          tipoCombustible: TipoCombustible.diesel,
          cilindrada: 6.7,
        ),
        transmision: const Transmision(codigo: 'TorqShift', tipo: TipoTransmision.automatica),
        kilometrajeActual: 25000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VehiculoSiluetaFondo(vehiculo: vF450),
          ),
        ),
      );

      expect(find.byType(VehiculoSiluetaFondo), findsOneWidget);
    });

    testWidgets('renderiza fallback de inicial si la marca está vacía o cargando',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VehiculoAvatar(
              marca: '',
              size: 60,
            ),
          ),
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });
  });
}
