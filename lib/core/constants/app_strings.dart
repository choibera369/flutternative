/// Cadenas de texto en español para la interfaz
class AppStrings {
  AppStrings._();

  // ============================================================
  // App general
  // ============================================================

  static const appName = 'Medición de Salud';
  static const appDescription = 'Recopilación de datos BLE de salud';

  // ============================================================
  // Tabs / Navegación
  // ============================================================

  static const tabHome = 'Inicio';
  static const tabDevices = 'Dispositivos';
  static const tabHistory = 'Historial';
  static const tabSettings = 'Ajustes';

  // ============================================================
  // Dispositivos
  // ============================================================

  static const deviceScale = 'Báscula';
  static const deviceBloodPressure = 'Tensiómetro';
  static const deviceGlucose = 'Glucómetro';

  static const deviceXiaomiScale = 'Báscula Xiaomi';
  static const deviceIHealthBP = 'Tensiómetro iHealth';
  static const deviceIHealthGlucose = 'Glucómetro iHealth';

  static const deviceConnected = 'Conectado';
  static const deviceDisconnected = 'Desconectado';
  static const deviceConnecting = 'Conectando...';
  static const deviceSearching = 'Buscando...';
  static const deviceNotFound = 'No se encontraron dispositivos';

  static const scanForDevices = 'Buscar dispositivos';
  static const stopScan = 'Detener búsqueda';
  static const connectDevice = 'Conectar';
  static const disconnectDevice = 'Desconectar';

  // ============================================================
  // Etiquetas de medición
  // ============================================================

  // Báscula
  static const labelWeight = 'Peso';
  static const labelBmi = 'IMC';
  static const labelBodyFat = 'Grasa corporal';
  static const labelMuscleMass = 'Masa muscular';
  static const labelWaterPercentage = 'Agua corporal';
  static const labelBoneMass = 'Masa ósea';
  static const labelVisceralFat = 'Grasa visceral';
  static const labelBasalMetabolism = 'Met. basal';
  static const labelMetabolicAge = 'Edad met.';
  static const labelProteinPercentage = 'Proteína';

  // Tensiómetro
  static const labelSystolic = 'Sistólica';
  static const labelDiastolic = 'Diastólica';
  static const labelPulse = 'Pulso';
  static const labelIrregularPulse = 'Pulso irregular';
  static const labelMeanArterialPressure = 'Presión arterial media';

  // Glucómetro
  static const labelGlucose = 'Glucosa';
  static const labelMealContext = 'Estado alimentario';
  static const labelFasting = 'Ayuno';
  static const labelPostprandial = 'Postprandial';
  static const labelCasual = 'Casual';

  // ============================================================
  // Unidades
  // ============================================================

  static const unitKg = 'kg';
  static const unitLb = 'lb';
  static const unitPercent = '%';
  static const unitKcal = 'kcal';
  static const unitMmHg = 'mmHg';
  static const unitBpm = 'bpm';
  static const unitMgDl = 'mg/dL';
  static const unitMmolL = 'mmol/L';
  static const unitYears = 'años';

  // ============================================================
  // Mensajes de estado
  // ============================================================

  static const statusReady = 'Listo para medir';
  static const statusMeasuring = 'Midiendo...';
  static const statusComplete = 'Medición completa';
  static const statusFailed = 'Medición fallida';
  static const statusSyncing = 'Sincronizando...';
  static const statusSynced = 'Sincronizado';
  static const statusOffline = 'Sin conexión';

  // ============================================================
  // Mensajes de error
  // ============================================================

  static const errorBleDisabled = 'Bluetooth está desactivado. Active Bluetooth en la configuración.';
  static const errorBleNotSupported = 'Este dispositivo no soporta Bluetooth LE.';
  static const errorLocationPermission = 'Se requiere permiso de ubicación. Concédalo en la configuración.';
  static const errorBluetoothPermission = 'Se requiere permiso de Bluetooth. Concédalo en la configuración.';
  static const errorConnectionTimeout = 'Tiempo de conexión agotado. Intente de nuevo.';
  static const errorConnectionFailed = 'La conexión falló. Verifique que el dispositivo esté encendido.';
  static const errorDeviceNotFound = 'No se encontró el dispositivo. Verifique que esté encendido y cerca.';
  static const errorMeasurementFailed = 'La medición falló. Intente de nuevo.';
  static const errorDataParseFailed = 'Error al analizar los datos.';
  static const errorNetworkFailed = 'Error de red.';
  static const errorUnknown = 'Error desconocido.';

  // ============================================================
  // Botones / Acciones
  // ============================================================

  static const actionRetry = 'Reintentar';
  static const actionCancel = 'Cancelar';
  static const actionConfirm = 'Confirmar';
  static const actionSave = 'Guardar';
  static const actionDelete = 'Eliminar';
  static const actionSync = 'Sincronizar';
  static const actionOpenSettings = 'Abrir ajustes';
  static const actionGrantPermission = 'Conceder permiso';

  // ============================================================
  // Permisos
  // ============================================================

  static const permissionBluetoothTitle = 'Permiso de Bluetooth';
  static const permissionBluetoothMessage = 'Se necesita permiso de Bluetooth para conectar dispositivos de salud.';
  static const permissionLocationTitle = 'Permiso de ubicación';
  static const permissionLocationMessage = 'Se necesita permiso de ubicación para buscar dispositivos BLE.';

  // ============================================================
  // Títulos de pantalla
  // ============================================================

  static const screenHomeTitle = 'Panel principal';
  static const screenDevicesTitle = 'Gestión de dispositivos';
  static const screenScanTitle = 'Buscar dispositivos';
  static const screenHistoryTitle = 'Historial de mediciones';
  static const screenSettingsTitle = 'Ajustes';
  static const screenDetailTitle = 'Detalles';

  // ============================================================
  // Mensajes de estado vacío
  // ============================================================

  static const emptyDevices = 'No hay dispositivos conectados.\nPulse buscar para agregar dispositivos.';
  static const emptyHistory = 'No hay historial de mediciones.\nConecte un dispositivo y comience a medir.';
  static const emptySearchResults = 'No se encontraron dispositivos.\nVerifique que estén encendidos.';

  // ============================================================
  // Tiempo
  // ============================================================

  static const today = 'Hoy';
  static const yesterday = 'Ayer';
  static const lastMeasurement = 'Última medición';
  static const measurementTime = 'Hora de medición';
}
