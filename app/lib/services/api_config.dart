/// Configuración horneada en el build.
///
/// [kApiKeyDelBuild] es la shared secret del servidor, inyectada al
/// compilar con `flutter build apk --dart-define=API_KEY=...`. Los
/// usuarios finales no la ven ni la teclean: separa "dispositivos con
/// la app" del internet aleatorio que encuentra la URL pública. El campo
/// de Ajustes es solo un override de desarrollo.
const String kApiKeyDelBuild = String.fromEnvironment('API_KEY');
