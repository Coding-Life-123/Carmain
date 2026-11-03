import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/componente.dart';
import '../../models/enums.dart';
import '../../models/motorizacion.dart';
import '../../models/vehiculo.dart';
import '../../providers/providers.dart';
import '../../utils/formato.dart';

/// Pantalla "Crear Vehículo".
///
/// Formulario guiado para dar de alta un vehículo compuesto por chasis,
/// motor y transmisión. Al guardar, se genera un UUID, se persiste localmente
/// y se solicita el plan de mantenimiento al backend mediante
/// [crearVehiculoProvider].
///
/// Con [vehiculoExistente] la misma pantalla funciona como "Editar Vehículo"
/// (CRUD): campos prellenados, mismo id al guardar, y re-solicitud del plan
/// solo si la configuración técnica cambió.
class CrearVehiculoScreen extends ConsumerStatefulWidget {
  const CrearVehiculoScreen({super.key, this.vehiculoExistente});

  final Vehiculo? vehiculoExistente;

  @override
  ConsumerState<CrearVehiculoScreen> createState() =>
      _CrearVehiculoScreenState();
}

class _CrearVehiculoScreenState extends ConsumerState<CrearVehiculoScreen> {
  final _formKey = GlobalKey<FormState>();

  // ─────────────────────────── Controllers ───────────────────────────
  final _marcaController = TextEditingController();
  final _modeloController = TextEditingController();
  final _anioController = TextEditingController();
  final _trimController = TextEditingController();
  final _vinController = TextEditingController();
  final _placaController = TextEditingController();
  DateTime? _fechaMatricula;

  final _motorCodigoController = TextEditingController();
  final _cilindradaController = TextEditingController();
  final _cilindrosController = TextEditingController();
  final _aspiracionController = TextEditingController();
  final _potenciaController = TextEditingController();
  final _torqueController = TextEditingController();

  final _transmisionCodigoController = TextEditingController();
  final _marchasController = TextEditingController();

  final _kilometrajeController = TextEditingController();

  // ─────────────────────────── Estado de selección ───────────────────────────
  Drivetrain _drivetrain = Drivetrain.fwd;
  TipoCombustible _tipoCombustible = TipoCombustible.gasolina;
  TipoTransmision _tipoTransmision = TipoTransmision.manual;
  bool _usoSevero = false;
  bool _mantenimientoAlDia = false;

  // Swaps y componentes
  bool _motorEsSwap = false;
  String? _motorOriginalCodigo;
  bool _transEsSwap = false;
  String? _transOriginalCodigo;

  bool _guardando = false;

  // ─────────────────────────── Búsqueda de motorización ───────────────────────────
  Timer? _debounceBusqueda;
  String? _claveBusqueda; // "marca|modelo|anio|trim" cuando el chasis es buscable
  // ¿El usuario escribió/elegió manualmente? Mientras sea false, las
  // sugerencias pueden auto-rellenar el campo.
  bool _motorTocado = false;
  bool _transTocado = false;
  // ¿El código en pantalla vino de las sugerencias del chasis (autollenado
  // o chip)? Al buscar OTRO vehículo esa elección era del vehículo anterior
  // y ya no aplica: se des-bloquea para que el nuevo lo rellene. Un código
  // tecleado a mano (ej. motor swap) no lleva este flag y sigue protegido.
  bool _motorDeSugerencia = false;
  bool _transDeSugerencia = false;

  // ─────────────────────────── Búsqueda por código ───────────────────────────
  Timer? _debounceCodigo;
  String? _claveInfoMotor; // código de motor en mayúsculas cuando es buscable
  String? _claveInfoTrans; // código de transmisión en mayúsculas cuando es buscable
  // Última info devuelta por la búsqueda de cada código — alimenta el
  // helperText del campo (confirmación visual de que el servidor lo
  // reconoció) y se descarta al cambiar el código.
  OpcionMotor? _infoMotorActual;
  OpcionTransmision? _infoTransActual;
  // ¿El usuario editó este campo a mano? Ningún auto-relleno (chasis ni
  // búsqueda por código) pisa un campo tocado; vaciarlo lo re-activa.
  bool _combustibleTocado = false;
  bool _cilindradaTocado = false;
  bool _cilindrosTocado = false;
  bool _aspiracionTocado = false;
  bool _potenciaTocado = false;
  bool _torqueTocado = false;
  bool _tipoTransTocado = false;
  bool _marchasTocado = false;
  bool _drivetrainTocado = false;

  @override
  void initState() {
    super.initState();
    // Modo edición: prellenar con los datos guardados. Todos los flags de
    // "tocado" arrancan en true — los datos cargados son del usuario y
    // ningún auto-relleno debe pisarlos hasta que vacíe un campo a propósito
    // (vaciar lo re-activa, como siempre).
    final v = widget.vehiculoExistente;
    if (v != null) {
      _marcaController.text = v.marca;
      _modeloController.text = v.modelo;
      _anioController.text = v.anio.toString();
      _trimController.text = v.trim ?? '';
      _vinController.text = v.vin ?? '';
      _placaController.text = v.placa ?? '';
      _fechaMatricula = v.fechaMatricula;
      _motorCodigoController.text = v.motor.codigo;
      _cilindradaController.text = v.motor.cilindrada?.toString() ?? '';
      _cilindrosController.text = v.motor.cilindros?.toString() ?? '';
      _aspiracionController.text = v.motor.aspiracion ?? '';
      _potenciaController.text = v.motor.potenciaHp?.toString() ?? '';
      _torqueController.text = v.motor.torqueNm?.toString() ?? '';
      _transmisionCodigoController.text = v.transmision.codigo;
      _marchasController.text = v.transmision.marchas?.toString() ?? '';
      _kilometrajeController.text =
          v.kilometrajeActual > 0 ? v.kilometrajeActual.toString() : '';
      _drivetrain = v.drivetrain;
      _tipoCombustible = v.motor.tipoCombustible;
      _tipoTransmision = v.transmision.tipo;
      _usoSevero = v.tipoUso == TipoUso.severo;
      _motorEsSwap = !v.motor.esOriginal;
      _motorOriginalCodigo = v.motor.originalCodigo;
      _transEsSwap = !v.transmision.esOriginal;
      _transOriginalCodigo = v.transmision.originalCodigo;
      _motorTocado = true;
      _transTocado = true;
      _motorDeSugerencia = false; // datos guardados = intención del usuario
      _transDeSugerencia = false;
      _combustibleTocado = true;
      _cilindradaTocado = true;
      _cilindrosTocado = true;
      _aspiracionTocado = true;
      _potenciaTocado = true;
      _torqueTocado = true;
      _tipoTransTocado = true;
      _marchasTocado = true;
      _drivetrainTocado = true;
    }

    // Buscar motorizaciones con debounce mientras se llena el chasis.
    // Se registran DESPUÉS del prefill: asignar .text notifica listeners,
    // y el precargado no debe disparar una búsqueda (llamada a Gemini +
    // fila de estado) en un formulario que ya está completo.
    _marcaController.addListener(_programarBusqueda);
    _modeloController.addListener(_programarBusqueda);
    _anioController.addListener(_programarBusqueda);
    _trimController.addListener(_programarBusqueda);
  }

  @override
  void dispose() {
    _debounceBusqueda?.cancel();
    _debounceCodigo?.cancel();
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _trimController.dispose();
    _vinController.dispose();
    _placaController.dispose();
    _motorCodigoController.dispose();
    _cilindradaController.dispose();
    _cilindrosController.dispose();
    _aspiracionController.dispose();
    _potenciaController.dispose();
    _torqueController.dispose();
    _transmisionCodigoController.dispose();
    _marchasController.dispose();
    _kilometrajeController.dispose();
    super.dispose();
  }

  // ─────────────────────────── Búsqueda de motorización ───────────────────────────

  void _programarBusqueda() {
    _debounceBusqueda?.cancel();
    _debounceBusqueda =
        Timer(const Duration(milliseconds: 800), _ejecutarBusqueda);
  }

  void _ejecutarBusqueda() {
    final marca = _marcaController.text.trim();
    final modelo = _modeloController.text.trim();
    final anio = int.tryParse(_anioController.text.trim());
    final trim = _trimController.text.trim();

    final String? clave;
    if (marca.isNotEmpty &&
        modelo.isNotEmpty &&
        anio != null &&
        anio >= 1900 &&
        anio <= 2100) {
      clave = '$marca|$modelo|$anio|$trim';
    } else {
      clave = null;
    }
    if (clave != _claveBusqueda) {
      debugPrint('[crear_vehiculo] clave de busqueda: $clave');
      setState(() {
        _claveBusqueda = clave;
        // Cambió el chasis: lo que las sugerencias llenaron para el
        // vehículo anterior (autollenado o chip) ya no aplica — se
        // des-bloquea para que el nuevo vehículo lo rellene. Lo tecleado
        // a mano no lleva el flag y queda protegido igual que antes.
        if (_motorDeSugerencia) _motorTocado = false;
        if (_transDeSugerencia) _transTocado = false;
      });
    }
  }

  // ─────────────────────────── Búsqueda por código ───────────────────────────

  void _programarBusquedaCodigo() {
    _debounceCodigo?.cancel();
    _debounceCodigo =
        Timer(const Duration(milliseconds: 800), _ejecutarBusquedaCodigo);
  }

  void _ejecutarBusquedaCodigo() {
    // En mayúsculas para que "k4j" y "K4J" compartan cache del servidor.
    // Códigos de 1 carácter no valen una llamada a Gemini.
    String? claveMotor;
    final motor = _motorCodigoController.text.trim().toUpperCase();
    if (motor.length >= 2) claveMotor = motor;

    String? claveTrans;
    final trans = _transmisionCodigoController.text.trim().toUpperCase();
    if (trans.length >= 2) claveTrans = trans;

    if (claveMotor != _claveInfoMotor || claveTrans != _claveInfoTrans) {
      debugPrint(
          '[crear_vehiculo] info por codigo: motor=$claveMotor trans=$claveTrans');
      setState(() {
        _claveInfoMotor = claveMotor;
        _claveInfoTrans = claveTrans;
        _infoMotorActual = null; // la info del código anterior ya no aplica
        _infoTransActual = null;
      });
    }
  }

  String _normalizarCodigo(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();

  bool _esCodigoOem(String codigo, List<String> codigosOem) {
    final norm = _normalizarCodigo(codigo);
    if (norm.isEmpty) return true;
    return codigosOem.any((oem) => _normalizarCodigo(oem) == norm);
  }

  void _evaluarSwapsAutomaticos([SugerenciasMotorizacion? sugerencias]) {
    final sugs = sugerencias ??
        (_claveBusqueda != null
            ? ref.read(motorizacionBusquedaProvider(_claveBusqueda!)).value
            : null);

    final existente = widget.vehiculoExistente;
    if (sugs != null) {
      if (sugs.motores.isNotEmpty) {
        final codigosOem = sugs.motores.map((m) => m.codigo).toList();
        _motorOriginalCodigo ??= codigosOem.first;
        final motorActual = _motorCodigoController.text.trim();
        if (motorActual.isNotEmpty) {
          _motorEsSwap = !_esCodigoOem(motorActual, codigosOem);
        }
      }
      if (sugs.transmisiones.isNotEmpty) {
        final codigosOem = sugs.transmisiones.map((t) => t.codigo).toList();
        _transOriginalCodigo ??= codigosOem.first;
        final transActual = _transmisionCodigoController.text.trim();
        if (transActual.isNotEmpty) {
          _transEsSwap = !_esCodigoOem(transActual, codigosOem);
        }
      }
    } else if (existente != null) {
      final motorActual = _motorCodigoController.text.trim();
      final motorOemRef = existente.motor.esOriginal
          ? existente.motor.codigo
          : existente.motor.originalCodigo;
      if (motorOemRef != null && motorActual.isNotEmpty) {
        _motorOriginalCodigo ??= motorOemRef;
        _motorEsSwap = !_esCodigoOem(motorActual, [motorOemRef]);
      }

      final transActual = _transmisionCodigoController.text.trim();
      final transOemRef = existente.transmision.esOriginal
          ? existente.transmision.codigo
          : existente.transmision.originalCodigo;
      if (transOemRef != null && transActual.isNotEmpty) {
        _transOriginalCodigo ??= transOemRef;
        _transEsSwap = !_esCodigoOem(transActual, [transOemRef]);
      }
    }
  }

  /// Auto-rellena motor, transmisión y tracción con las sugerencias —
  /// solo lo que el usuario no haya tocado (nunca pisar su elección).
  void _aplicarSugerencias(SugerenciasMotorizacion sugerencias) {
    if (sugerencias.motores.isNotEmpty && _motorOriginalCodigo == null) {
      _motorOriginalCodigo = sugerencias.motores.first.codigo;
    }
    if (sugerencias.transmisiones.isNotEmpty && _transOriginalCodigo == null) {
      _transOriginalCodigo = sugerencias.transmisiones.first.codigo;
    }
    if (!_motorTocado && sugerencias.motores.isNotEmpty) {
      _llenarMotor(sugerencias.motores.first);
    }
    if (!_transTocado && sugerencias.transmisiones.isNotEmpty) {
      _llenarTransmision(sugerencias.transmisiones.first);
    }
    if (!_drivetrainTocado && sugerencias.drivetrain != null) {
      setState(() => _drivetrain = sugerencias.drivetrain!);
    }
    _evaluarSwapsAutomaticos(sugerencias);
  }

  /// Descripción para el helperText del campo de código — null si no hay
  /// info útil (evita el espacio vacío de un helperText "").
  String? _helperCodigo(String? descripcion) =>
      (descripcion != null && descripcion.isNotEmpty) ? descripcion : null;

  /// ¿El servidor rechazó la petición por API key inválida? Distinto de
  /// "sin conexión": el túnel funciona, la key no coincide — sin esta
  /// distinción el usuario cree que la red está rota.
  bool _esAuthInvalida(Object? error) =>
      error is DioException && error.response?.statusCode == 401;

  String _mensajeErrorServidor(Object? error) => _esAuthInvalida(error)
      ? 'API key inválida — revísala en Ajustes'
      : 'Sin conexión con el servidor — completa a mano';

  /// Rellena los campos del motor con una opción.
  ///
  /// [escribirCodigo]: false cuando la opción viene de la búsqueda por
  /// código — el usuario acaba de escribir ese código, no hay que
  /// reemplazarlo. [forzar]: true para los chips (elección explícita) —
  /// pisa incluso los campos tocados a mano.
  void _llenarMotor(OpcionMotor op,
      {bool escribirCodigo = true, bool forzar = false}) {
    if (escribirCodigo) {
      _motorCodigoController.text = op.codigo;
      _motorDeSugerencia = true; // el código vino de las sugerencias
      _motorEsSwap = false;
      _motorOriginalCodigo = op.codigo;
      // El código buscado a mano ya no está en pantalla: descartar su
      // respuesta en vuelo (y su helperText) para que no pise esta
      // elección cuando llegue.
      _claveInfoMotor = null;
      _infoMotorActual = null;
    }
    if ((forzar || !_combustibleTocado) && op.combustible != null) {
      _tipoCombustible = op.combustible!;
    }
    _reflejarCampo(_cilindradaController, op.cilindrada?.toString(),
        tocado: _cilindradaTocado, forzar: forzar);
    _reflejarCampo(_cilindrosController, op.cilindros?.toString(),
        tocado: _cilindrosTocado, forzar: forzar);
    _reflejarCampo(
        _aspiracionController, op.aspiracion?.isNotEmpty == true ? op.aspiracion : null,
        tocado: _aspiracionTocado, forzar: forzar);
    _reflejarCampo(_potenciaController, op.potenciaHp?.toString(),
        tocado: _potenciaTocado, forzar: forzar);
    _reflejarCampo(_torqueController, op.torqueNm?.toString(),
        tocado: _torqueTocado, forzar: forzar);
    setState(() {});
  }

  void _llenarTransmision(OpcionTransmision op,
      {bool escribirCodigo = true, bool forzar = false}) {
    if (escribirCodigo) {
      _transmisionCodigoController.text = op.codigo;
      _transDeSugerencia = true; // el código vino de las sugerencias
      _transEsSwap = false;
      _transOriginalCodigo = op.codigo;
      // Ídem motor: descartar la búsqueda por código en vuelo.
      _claveInfoTrans = null;
      _infoTransActual = null;
    }
    if ((forzar || !_tipoTransTocado) && op.tipo != null) {
      _tipoTransmision = op.tipo!;
    }
    _reflejarCampo(_marchasController, op.marchas?.toString(),
        tocado: _marchasTocado, forzar: forzar);
    setState(() {});
  }

  /// Escribe (o limpia) un campo de detalle según la opción sugerida.
  ///
  /// Con dato: pisa el valor actual salvo que esté tecleado a mano y la
  /// opción no venga de un chip ([forzar]). Sin dato: limpia el valor
  /// vencido del motor/caja anterior — el campo refleja la opción, no
  /// acumula restos; lo tecleado a mano se conserva (puede ser
  /// conocimiento propio del usuario que la opción no trae).
  void _reflejarCampo(TextEditingController controller, String? valor,
      {required bool tocado, required bool forzar}) {
    if (valor != null) {
      if (forzar || !tocado) controller.text = valor;
    } else if (!tocado) {
      controller.text = '';
    }
  }

  // ─────────────────────────── Guardado ───────────────────────────

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    // En modo edición se conserva el id (y el resto de campos que este
    // formulario no edita) — es una actualización, no un vehículo nuevo.
    final existente = widget.vehiculoExistente;

    // Motor/caja según el formulario. En edición se conservan los campos
    // que este formulario no edita (descripcion, fabricante, esOriginal,
    // originalCodigo, fuente — los datos de swap que guarda el detalle).
    Motor motor = Motor(
      codigo: _motorCodigoController.text.trim(),
      tipoCombustible: _tipoCombustible,
      cilindrada: _cilindradaController.text.trim().isEmpty
          ? null
          : double.tryParse(_cilindradaController.text.trim()),
      cilindros: _cilindrosController.text.trim().isEmpty
          ? null
          : int.tryParse(_cilindrosController.text.trim()),
      aspiracion: _aspiracionController.text.trim().isEmpty
          ? null
          : _aspiracionController.text.trim(),
      potenciaHp: _potenciaController.text.trim().isEmpty
          ? null
          : int.tryParse(_potenciaController.text.trim()),
      torqueNm: _torqueController.text.trim().isEmpty
          ? null
          : int.tryParse(_torqueController.text.trim()),
      esOriginal: !_motorEsSwap,
      originalCodigo: _motorEsSwap ? _motorOriginalCodigo : null,
      fuente: _motorEsSwap ? FuenteComponente.swap : FuenteComponente.oem,
    );
    Transmision transmision = Transmision(
      codigo: _transmisionCodigoController.text.trim(),
      tipo: _tipoTransmision,
      marchas: _marchasController.text.trim().isEmpty
          ? null
          : int.tryParse(_marchasController.text.trim()),
      esOriginal: !_transEsSwap,
      originalCodigo: _transEsSwap ? _transOriginalCodigo : null,
      fuente: _transEsSwap ? FuenteComponente.swap : FuenteComponente.oem,
    );
    if (existente != null) {
      motor = motor.copyWith(
        descripcion: existente.motor.descripcion,
        fabricante: existente.motor.fabricante,
      );
      transmision = transmision.copyWith(
        descripcion: existente.transmision.descripcion,
        fabricante: existente.transmision.fabricante,
      );
    }

    final vehiculo = Vehiculo(
      id: existente?.id ?? const Uuid().v4(),
      propietarioId: existente?.propietarioId ?? 'local',
      marca: _marcaController.text.trim(),
      modelo: _modeloController.text.trim(),
      anio: int.parse(_anioController.text.trim()),
      trim: _trimController.text.trim().isEmpty
          ? null
          : _trimController.text.trim(),
      vin: _vinController.text.trim().isEmpty
          ? null
          : _vinController.text.trim(),
      placa: _placaController.text.trim().isEmpty
          ? null
          : _placaController.text.trim().toUpperCase(),
      fechaMatricula: _fechaMatricula,
      drivetrain: _drivetrain,
      motor: motor,
      transmision: transmision,
      componentesExtra: existente?.componentesExtra ?? const [],
      kilometrajeActual: _kilometrajeController.text.trim().isEmpty
          ? 0
          : int.tryParse(_kilometrajeController.text.trim()) ?? 0,
      tipoUso: _usoSevero ? TipoUso.severo : TipoUso.normal,
      notasUso: existente?.notasUso,
      planMantenimientoId: existente?.planMantenimientoId,
    );

    // ¿Cambió la configuración técnica? Solo entonces se re-solicita el
    // plan (ver actualizarVehiculoProvider): el kilometraje/uso no deben
    // pisar el progreso marcado en el plan vigente.
    final configCambio = existente != null &&
        (existente.marca != vehiculo.marca ||
            existente.modelo != vehiculo.modelo ||
            existente.anio != vehiculo.anio ||
            existente.trim != vehiculo.trim ||
            existente.drivetrain != vehiculo.drivetrain ||
            existente.motor.codigo != vehiculo.motor.codigo ||
            existente.transmision.codigo != vehiculo.transmision.codigo);

    try {
      // invalidate antes del read: los providers de acción no son
      // autoDispose y un miembro del family que ya quedó en error (o ya
      // completó) devolvería el mismo futuro — reintentar debe re-ejecutar.
      if (existente == null) {
        ref.invalidate(crearVehiculoProvider((vehiculo, _mantenimientoAlDia)));
        await ref.read(crearVehiculoProvider((vehiculo, _mantenimientoAlDia)).future);
      } else {
        ref.invalidate(actualizarVehiculoProvider((vehiculo, configCambio)));
        await ref
            .read(actualizarVehiculoProvider((vehiculo, configCambio)).future);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existente == null
              ? 'Vehículo creado'
              : configCambio
                  ? 'Vehículo actualizado — plan regenerado'
                  : 'Vehículo actualizado'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar el vehículo: $e')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ─────────────────────────── UI ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Sugerencias de motorización para la clave actual (null si el chasis
    // aún no es buscable). El provider es autoDispose: claves viejas se
    // descartan solas al dejar de observarse.
    final claveBusqueda = _claveBusqueda;
    final sugerenciasAsync = claveBusqueda == null
        ? null
        : ref.watch(motorizacionBusquedaProvider(claveBusqueda));
    final sugerencias = sugerenciasAsync?.value;

    // Auto-rellenar cuando llegan resultados (una vez por clave).
    // La clave dummy '|' nunca produce datos — solo existe para que el
    // listen sea inofensivo cuando no hay búsqueda activa.
    ref.listen(motorizacionBusquedaProvider(claveBusqueda ?? '|'),
        (prev, next) {
      if (next.hasValue && next.value != null) {
        _aplicarSugerencias(next.value!);
      }
    });

    // Info por código escrito a mano: rellena SOLO los detalles (el código
    // lo acaba de escribir el usuario) y nunca pisa un campo tocado. La
    // descripción queda como helperText del campo — confirmación visual
    // de que el servidor reconoció el código, incluso cuando los valores
    // autollenados coinciden con lo que ya estaba en pantalla.
    // La respuesta puede llegar vencida (un chip/autollenado reescribió el
    // código, o el usuario tecleó otro): solo aplicar si sigue siendo la
    // búsqueda que está en pantalla.
    final claveInfoMotor = _claveInfoMotor;
    ref.listen(infoCodigoMotorProvider(claveInfoMotor ?? '|'),
        (prev, next) {
      if (next.hasValue &&
          next.value != null &&
          _claveInfoMotor == claveInfoMotor) {
        _infoMotorActual = next.value;
        _llenarMotor(next.value!, escribirCodigo: false);
      }
    });
    final claveInfoTrans = _claveInfoTrans;
    ref.listen(infoCodigoTransmisionProvider(claveInfoTrans ?? '|'),
        (prev, next) {
      if (next.hasValue &&
          next.value != null &&
          _claveInfoTrans == claveInfoTrans) {
        _infoTransActual = next.value;
        _llenarTransmision(next.value!, escribirCodigo: false);
      }
    });

    final esEdicion = widget.vehiculoExistente != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(esEdicion ? 'Editar Vehículo' : 'Crear Vehículo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── 1. Identidad del chasis ───
              _FormSectionCard(
                icon: Icons.directions_car_rounded,
                title: 'Identidad del chasis',
                subtitle: 'Información básica del fabricante y modelo',
                children: [
                  TextFormField(
                    controller: _marcaController,
                    decoration: const InputDecoration(
                      labelText: 'Marca *',
                      hintText: 'ej. Toyota',
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _modeloController,
                    decoration: const InputDecoration(
                      labelText: 'Modelo *',
                      hintText: 'ej. Supra',
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: TextFormField(
                          controller: _anioController,
                          decoration: const InputDecoration(
                            labelText: 'Año *',
                            hintText: 'ej. 1995',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Obligatorio';
                            final anio = int.tryParse(v.trim());
                            if (anio == null) return 'Año inválido';
                            if (anio < 1900 || anio > 2100) {
                              return 'Año fuera de rango';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 6,
                        child: TextFormField(
                          controller: _trimController,
                          decoration: const InputDecoration(
                            labelText: 'Trim (opcional)',
                            hintText: 'ej. GR',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _vinController,
                    decoration: const InputDecoration(
                      labelText: 'VIN (opcional)',
                      hintText: '17 caracteres',
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: TextFormField(
                          controller: _placaController,
                          decoration: const InputDecoration(
                            labelText: 'Placa (Colombia)',
                            hintText: 'ej. ABC123',
                          ),
                          textCapitalization: TextCapitalization.characters,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 6,
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _fechaMatricula ?? DateTime.now(),
                              firstDate: DateTime(1960),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() => _fechaMatricula = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Fecha matrícula',
                              suffixIcon: Icon(Icons.calendar_today, size: 18),
                            ),
                            child: Text(
                              _fechaMatricula != null
                                  ? formatearFecha(_fechaMatricula!)
                                  : 'Opcional',
                              style: _fechaMatricula != null
                                  ? null
                                  : TextStyle(
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (sugerenciasAsync != null) ...[
                    const SizedBox(height: 12),
                    if (sugerenciasAsync.isLoading)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text('Buscando motorizaciones…',
                                style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      )
                    else if (sugerenciasAsync.hasError)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _esAuthInvalida(sugerenciasAsync.error)
                                  ? Icons.key_off
                                  : Icons.cloud_off,
                              size: 14,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _mensajeErrorServidor(sugerenciasAsync.error),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.error),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (sugerencias == null ||
                        (sugerencias.motores.isEmpty &&
                            sugerencias.transmisiones.isEmpty))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search_off,
                                size: 14, color: theme.hintColor),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Sin sugerencias para este chasis — completa a mano',
                                style: TextStyle(
                                    fontSize: 12, color: theme.hintColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // ─── 2. Tracción ───
              _FormSectionCard(
                icon: Icons.tune_rounded,
                title: 'Tracción',
                subtitle: 'Selecciona la tracción del vehículo',
                children: [
                  Wrap(
                    spacing: 8,
                    children: Drivetrain.values.map((dt) {
                      final selected = dt == _drivetrain;
                      return ChoiceChip(
                        label: Text(dt.label),
                        selected: selected,
                        onSelected: (_) => setState(() {
                          _drivetrain = dt;
                          _drivetrainTocado = true;
                        }),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ─── 3. Motor ───
              _FormSectionCard(
                icon: Icons.local_gas_station_rounded,
                title: 'Motor',
                subtitle: 'Configuración y especificaciones del motor',
                children: [
                  TextFormField(
                    controller: _motorCodigoController,
                    decoration: InputDecoration(
                      labelText: 'Código *',
                      hintText: 'ej. 2JZ-GTE',
                      helperText: _helperCodigo(_infoMotorActual?.descripcion),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (v) {
                      _motorTocado = v.trim().isNotEmpty;
                      _motorDeSugerencia = false;
                      _evaluarSwapsAutomaticos(sugerencias);
                      _programarBusquedaCodigo();
                      setState(() {});
                    },
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                  ),
                  if (sugerencias != null && sugerencias.motores.length > 1) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final op in sugerencias.motores)
                          ChoiceChip(
                            label: Text(op.codigo),
                            selected:
                                _motorCodigoController.text.trim() == op.codigo,
                            onSelected: (_) {
                              _llenarMotor(op, forzar: true);
                              _motorTocado = true;
                            },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _motorEsSwap
                          ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3)
                          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _motorEsSwap
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _motorEsSwap ? Icons.swap_horiz : Icons.verified_outlined,
                          size: 18,
                          color: _motorEsSwap
                              ? theme.colorScheme.tertiary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _motorEsSwap ? 'Motor Swap detectado' : 'Motor original / OEM',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: _motorEsSwap
                                      ? theme.colorScheme.tertiary
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                              if (_motorEsSwap && _motorOriginalCodigo != null)
                                Text(
                                  'Original de fábrica: $_motorOriginalCodigo',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text('¿Swap?', style: theme.textTheme.bodySmall),
                        Switch(
                          value: _motorEsSwap,
                          onChanged: (v) => setState(() => _motorEsSwap = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TipoCombustible>(
                    initialValue: _tipoCombustible,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de combustible',
                    ),
                    items: TipoCombustible.values
                        .map((tc) => DropdownMenuItem(
                              value: tc,
                              child: Text(tc.label),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _tipoCombustible = v;
                          _combustibleTocado = true;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _cilindradaController,
                          decoration: const InputDecoration(
                            labelText: 'Cilindrada (L, opcional)',
                            hintText: 'ej. 3.0',
                          ),
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          onChanged: (v) =>
                              _cilindradaTocado = v.trim().isNotEmpty,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            if (double.tryParse(v.trim()) == null) {
                              return 'Inválido';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _cilindrosController,
                          decoration: const InputDecoration(
                            labelText: 'Cilindros (opcional)',
                            hintText: 'ej. 6',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) =>
                              _cilindrosTocado = v.trim().isNotEmpty,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            if (int.tryParse(v.trim()) == null) {
                              return 'Inválido';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _potenciaController,
                          decoration: const InputDecoration(
                            labelText: 'Potencia (HP, opcional)',
                            hintText: 'ej. 255',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) =>
                              _potenciaTocado = v.trim().isNotEmpty,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            if (int.tryParse(v.trim()) == null) {
                              return 'Inválido';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _torqueController,
                          decoration: const InputDecoration(
                            labelText: 'Torque (Nm, opcional)',
                            hintText: 'ej. 350',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) =>
                              _torqueTocado = v.trim().isNotEmpty,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            if (int.tryParse(v.trim()) == null) {
                              return 'Inválido';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _aspiracionController,
                    decoration: const InputDecoration(
                      labelText: 'Aspiración (opcional)',
                      hintText: 'NA / Turbo / Twin-Turbo / Supercharger',
                    ),
                    onChanged: (v) =>
                        _aspiracionTocado = v.trim().isNotEmpty,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ─── 4. Transmisión ───
              _FormSectionCard(
                icon: Icons.settings_suggest_rounded,
                title: 'Transmisión',
                subtitle: 'Caja de cambios y relaciones',
                children: [
                  TextFormField(
                    controller: _transmisionCodigoController,
                    decoration: InputDecoration(
                      labelText: 'Código *',
                      hintText: 'ej. R154',
                      helperText: _helperCodigo(_infoTransActual?.descripcion),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (v) {
                      _transTocado = v.trim().isNotEmpty;
                      _transDeSugerencia = false;
                      _evaluarSwapsAutomaticos(sugerencias);
                      _programarBusquedaCodigo();
                      setState(() {});
                    },
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                  ),
                  if (sugerencias != null &&
                      sugerencias.transmisiones.length > 1) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final op in sugerencias.transmisiones)
                          ChoiceChip(
                            label: Text(op.codigo),
                            selected: _transmisionCodigoController.text.trim() ==
                                op.codigo,
                            onSelected: (_) {
                              _llenarTransmision(op, forzar: true);
                              _transTocado = true;
                            },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _transEsSwap
                          ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3)
                          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _transEsSwap
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _transEsSwap ? Icons.swap_horiz : Icons.verified_outlined,
                          size: 18,
                          color: _transEsSwap
                              ? theme.colorScheme.tertiary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _transEsSwap ? 'Transmisión Swap detectada' : 'Transmisión original / OEM',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: _transEsSwap
                                      ? theme.colorScheme.tertiary
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                              if (_transEsSwap && _transOriginalCodigo != null)
                                Text(
                                  'Original de fábrica: $_transOriginalCodigo',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text('¿Swap?', style: theme.textTheme.bodySmall),
                        Switch(
                          value: _transEsSwap,
                          onChanged: (v) => setState(() => _transEsSwap = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TipoTransmision>(
                    initialValue: _tipoTransmision,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                    ),
                    items: TipoTransmision.values
                        .map((tt) => DropdownMenuItem(
                              value: tt,
                              child: Text(tt.label),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _tipoTransmision = v;
                          _tipoTransTocado = true;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _marchasController,
                    decoration: const InputDecoration(
                      labelText: 'Marchas (opcional)',
                      hintText: 'ej. 6',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _marchasTocado = v.trim().isNotEmpty,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      if (int.tryParse(v.trim()) == null) return 'Inválido';
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ─── 5. Kilometraje y uso ───
              _FormSectionCard(
                icon: Icons.speed_rounded,
                title: 'Kilometraje y uso',
                subtitle: 'Determina los intervalos preventivos',
                children: [
                  TextFormField(
                    controller: _kilometrajeController,
                    decoration: const InputDecoration(
                      labelText: 'Kilometraje actual',
                      hintText: 'ej. 120000',
                      suffixText: 'km',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      if (int.tryParse(v.trim()) == null) return 'Inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _usoSevero,
                    onChanged: (v) => setState(() => _usoSevero = v),
                    title: const Text('Uso severo'),
                    subtitle: const Text(
                      'Ciudad, tráfico, remolque o polvo — acorta los intervalos recomendados',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (!esEdicion) ...[
                    const Divider(height: 24),
                    SwitchListTile(
                      value: _mantenimientoAlDia,
                      onChanged: (v) => setState(() => _mantenimientoAlDia = v),
                      title: const Text('Mantenimientos al día'),
                      subtitle: Text(
                        _mantenimientoAlDia
                            ? 'Los mantenimientos arrancarán desde hoy y tu odómetro actual.'
                            : 'Recomendado: los ítems quedarán como "Sin registro" hasta que registres su historial o uses el Asistente de Línea Base.',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),

              // ─── Botón guardar ───
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_guardando
                      ? 'Guardando…'
                      : esEdicion
                          ? 'Guardar cambios'
                          : 'Guardar vehículo'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta para agrupar secciones del formulario con un encabezado con icono,
/// título y subtítulo, dando orden visual al configurador del vehículo.
class _FormSectionCard extends StatelessWidget {
  const _FormSectionCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
