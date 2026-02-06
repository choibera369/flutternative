import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/ble_core_service.dart';
export '../../services/ble_core_service.dart' show ScannedDevice, DeviceType;
import '../../services/device_services/base_device_service.dart';
import '../../services/device_services/xiaomi_scale_service.dart';
import '../../services/device_services/ihealth_bp_service.dart';
import '../../services/device_services/ihealth_glucose_service.dart';
import '../../data/models/body_composition.dart';
import '../../data/models/blood_pressure.dart';
import '../../data/models/glucose_reading.dart';

// ============================================================
// Core BLE Providers
// ============================================================

/// BLE Core Service Provider
final bleCoreServiceProvider = Provider<BleCoreService>((ref) {
  return BleCoreService.instance;
});

/// BLE 상태 Provider
final bleStatusProvider = StreamProvider<BleStatus>((ref) {
  final bleCore = ref.watch(bleCoreServiceProvider);
  return bleCore.bleStatusStream;
});

/// 스캔 중 여부 Provider
final isScanningProvider = StreamProvider<bool>((ref) {
  final bleCore = ref.watch(bleCoreServiceProvider);
  return bleCore.isScanningStream;
});

/// 검색된 기기 목록 Provider
final discoveredDevicesProvider = StreamProvider<List<ScannedDevice>>((ref) {
  final bleCore = ref.watch(bleCoreServiceProvider);
  return bleCore.discoveredDevicesStream;
});

/// 스캔 컨트롤러 Provider
final scanControllerProvider =
    StateNotifierProvider<ScanController, AsyncValue<void>>((ref) {
  final bleCore = ref.watch(bleCoreServiceProvider);
  return ScanController(bleCore);
});

class ScanController extends StateNotifier<AsyncValue<void>> {
  ScanController(this._bleCore) : super(const AsyncValue.data(null));

  final BleCoreService _bleCore;

  Future<void> startScan() async {
    state = const AsyncValue.loading();
    try {
      await _bleCore.startScan();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> stopScan() async {
    await _bleCore.stopScan();
  }
}

// ============================================================
// Device Connection Providers
// ============================================================

/// 연결 상태 Provider (기기 ID별)
final connectionStateProvider =
    StreamProvider.family<BleConnectionState, String>((ref, deviceId) {
  final bleCore = ref.watch(bleCoreServiceProvider);
  return bleCore.connectionStateStream(deviceId);
});

// ============================================================
// Xiaomi Scale Providers
// ============================================================

/// Xiaomi Scale Service Provider
final xiaomiScaleServiceProvider = Provider<XiaomiScaleService>((ref) {
  final bleCore = ref.watch(bleCoreServiceProvider);
  return XiaomiScaleService(bleCore: bleCore);
});

/// 체중계 측정 상태 Provider
final scaleMeasurementStateProvider = StreamProvider<MeasurementState>((ref) {
  final service = ref.watch(xiaomiScaleServiceProvider);
  return service.measurementStateStream;
});

/// 체중계 최신 측정값 Provider
final latestBodyCompositionProvider = StreamProvider<BodyComposition?>((ref) {
  final service = ref.watch(xiaomiScaleServiceProvider);
  return service.latestMeasurementStream;
});

/// 체중계 측정 히스토리 Provider
final bodyCompositionHistoryProvider =
    StreamProvider<List<BodyComposition>>((ref) {
  final service = ref.watch(xiaomiScaleServiceProvider);
  return service.measurementHistoryStream;
});

/// 체중계 불안정 측정값 Provider (실시간)
final unstabilizedWeightProvider = StreamProvider<BodyComposition?>((ref) {
  final service = ref.watch(xiaomiScaleServiceProvider);
  return service.unstabilizedStream;
});

/// 체중계 연결 컨트롤러
final scaleConnectionProvider =
    StateNotifierProvider<DeviceConnectionController<BodyComposition>,
        AsyncValue<void>>((ref) {
  final service = ref.watch(xiaomiScaleServiceProvider);
  return DeviceConnectionController(service);
});

// ============================================================
// iHealth Blood Pressure Providers
// ============================================================

/// iHealth BP Service Provider
final ihealthBPServiceProvider = Provider<IHealthBPService>((ref) {
  final bleCore = ref.watch(bleCoreServiceProvider);
  return IHealthBPService(bleCore: bleCore);
});

/// 혈압계 측정 상태 Provider
final bpMeasurementStateProvider = StreamProvider<MeasurementState>((ref) {
  final service = ref.watch(ihealthBPServiceProvider);
  return service.measurementStateStream;
});

/// 혈압계 최신 측정값 Provider
final latestBloodPressureProvider =
    StreamProvider<BloodPressureReading?>((ref) {
  final service = ref.watch(ihealthBPServiceProvider);
  return service.latestMeasurementStream;
});

/// 혈압계 측정 히스토리 Provider
final bloodPressureHistoryProvider =
    StreamProvider<List<BloodPressureReading>>((ref) {
  final service = ref.watch(ihealthBPServiceProvider);
  return service.measurementHistoryStream;
});

/// 혈압계 커프 압력 Provider
final cuffPressureProvider = StreamProvider<int?>((ref) {
  final service = ref.watch(ihealthBPServiceProvider);
  return service.cuffPressureStream;
});

/// 혈압계 측정 진행률 Provider
final bpProgressProvider = StreamProvider<int>((ref) {
  final service = ref.watch(ihealthBPServiceProvider);
  return service.progressStream;
});

/// 혈압계 연결 컨트롤러
final bpConnectionProvider =
    StateNotifierProvider<DeviceConnectionController<BloodPressureReading>,
        AsyncValue<void>>((ref) {
  final service = ref.watch(ihealthBPServiceProvider);
  return DeviceConnectionController(service);
});

// ============================================================
// iHealth Glucose Providers
// ============================================================

/// iHealth Glucose Service Provider
final ihealthGlucoseServiceProvider = Provider<IHealthGlucoseService>((ref) {
  final bleCore = ref.watch(bleCoreServiceProvider);
  return IHealthGlucoseService(bleCore: bleCore);
});

/// 혈당계 측정 상태 Provider
final glucoseMeasurementStateProvider = StreamProvider<MeasurementState>((ref) {
  final service = ref.watch(ihealthGlucoseServiceProvider);
  return service.measurementStateStream;
});

/// 혈당계 최신 측정값 Provider
final latestGlucoseProvider = StreamProvider<GlucoseReading?>((ref) {
  final service = ref.watch(ihealthGlucoseServiceProvider);
  return service.latestMeasurementStream;
});

/// 혈당계 측정 히스토리 Provider
final glucoseHistoryProvider = StreamProvider<List<GlucoseReading>>((ref) {
  final service = ref.watch(ihealthGlucoseServiceProvider);
  return service.measurementHistoryStream;
});

/// 혈당계 레코드 수 Provider
final glucoseRecordCountProvider = StreamProvider<int?>((ref) {
  final service = ref.watch(ihealthGlucoseServiceProvider);
  return service.recordCountStream;
});

/// 혈당계 다운로드 진행률 Provider
final glucoseDownloadProgressProvider = StreamProvider<int>((ref) {
  final service = ref.watch(ihealthGlucoseServiceProvider);
  return service.downloadProgressStream;
});

/// 혈당계 연결 컨트롤러
final glucoseConnectionProvider =
    StateNotifierProvider<GlucoseConnectionController, AsyncValue<void>>((ref) {
  final service = ref.watch(ihealthGlucoseServiceProvider);
  return GlucoseConnectionController(service);
});

// ============================================================
// Connection Controllers
// ============================================================

/// 기기 연결 컨트롤러 (공통)
class DeviceConnectionController<T> extends StateNotifier<AsyncValue<void>> {
  DeviceConnectionController(this._service)
      : super(const AsyncValue.data(null));

  final BaseDeviceService<T> _service;

  Future<void> connect(String deviceId) async {
    state = const AsyncValue.loading();
    try {
      await _service.connect(deviceId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> disconnect() async {
    await _service.disconnect();
    state = const AsyncValue.data(null);
  }

  Future<void> startMeasurement() async {
    try {
      await _service.startMeasurement();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> stopMeasurement() async {
    await _service.stopMeasurement();
  }
}

/// 혈당계 연결 컨트롤러 (추가 기능 포함)
class GlucoseConnectionController extends StateNotifier<AsyncValue<void>> {
  GlucoseConnectionController(this._service)
      : super(const AsyncValue.data(null));

  final IHealthGlucoseService _service;

  Future<void> connect(String deviceId) async {
    state = const AsyncValue.loading();
    try {
      await _service.connect(deviceId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> disconnect() async {
    await _service.disconnect();
    state = const AsyncValue.data(null);
  }

  Future<void> downloadAllRecords() async {
    state = const AsyncValue.loading();
    try {
      await _service.downloadAllRecords();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> downloadLastRecord() async {
    try {
      await _service.downloadLastRecord();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteAllRecords() async {
    try {
      await _service.deleteAllRecords();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> getRecordCount() async {
    try {
      await _service.getRecordCount();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

// ============================================================
// Combined Providers
// ============================================================

/// 연결된 기기 수 Provider
final connectedDeviceCountProvider = Provider<int>((ref) {
  int count = 0;

  final scaleState = ref.watch(scaleMeasurementStateProvider);
  if (scaleState.valueOrNull != null &&
      scaleState.valueOrNull != MeasurementState.idle) {
    count++;
  }

  final bpState = ref.watch(bpMeasurementStateProvider);
  if (bpState.valueOrNull != null &&
      bpState.valueOrNull != MeasurementState.idle) {
    count++;
  }

  final glucoseState = ref.watch(glucoseMeasurementStateProvider);
  if (glucoseState.valueOrNull != null &&
      glucoseState.valueOrNull != MeasurementState.idle) {
    count++;
  }

  return count;
});

/// 모든 최근 측정 데이터 Provider
final allLatestMeasurementsProvider = Provider<AllLatestMeasurements>((ref) {
  return AllLatestMeasurements(
    bodyComposition: ref.watch(latestBodyCompositionProvider).valueOrNull,
    bloodPressure: ref.watch(latestBloodPressureProvider).valueOrNull,
    glucose: ref.watch(latestGlucoseProvider).valueOrNull,
  );
});

class AllLatestMeasurements {
  const AllLatestMeasurements({
    this.bodyComposition,
    this.bloodPressure,
    this.glucose,
  });

  final BodyComposition? bodyComposition;
  final BloodPressureReading? bloodPressure;
  final GlucoseReading? glucose;

  bool get hasAnyData =>
      bodyComposition != null || bloodPressure != null || glucose != null;
}
