import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// BLE UUID 상수 정의
class BleUuids {
  BleUuids._();

  // ============================================================
  // Xiaomi Mi Body Composition Scale 2
  // ============================================================

  /// Xiaomi Scale - Body Composition Service (표준 BLE)
  static final bodyCompositionService = Uuid.parse('0000181b-0000-1000-8000-00805f9b34fb');

  /// Xiaomi Scale - Body Composition Measurement Characteristic
  static final bodyCompositionMeasurement = Uuid.parse('00002a9c-0000-1000-8000-00805f9b34fb');

  /// Xiaomi Scale - Weight Scale Service (표준 BLE)
  static final weightScaleService = Uuid.parse('0000181d-0000-1000-8000-00805f9b34fb');

  /// Xiaomi Scale - Weight Measurement Characteristic
  static final weightMeasurement = Uuid.parse('00002a9d-0000-1000-8000-00805f9b34fb');

  /// Xiaomi Scale - Custom Service (샤오미 전용)
  static final xiaomiCustomService = Uuid.parse('00001530-0000-3512-2118-0009af100700');

  /// Xiaomi Scale - Custom Characteristic (샤오미 전용)
  static final xiaomiCustomCharacteristic = Uuid.parse('00001531-0000-3512-2118-0009af100700');

  /// Xiaomi Scale - 서비스 광고 데이터에서 찾을 수 있는 UUID
  static final xiaomiScaleServiceData = Uuid.parse('0000181b-0000-1000-8000-00805f9b34fb');

  // ============================================================
  // iHealth Track (혈압계)
  // ============================================================

  /// iHealth BP - Blood Pressure Service (표준 BLE Health Profile)
  static final bloodPressureService = Uuid.parse('00001810-0000-1000-8000-00805f9b34fb');

  /// iHealth BP - Blood Pressure Measurement Characteristic
  static final bloodPressureMeasurement = Uuid.parse('00002a35-0000-1000-8000-00805f9b34fb');

  /// iHealth BP - Intermediate Cuff Pressure Characteristic
  static final intermediateCuffPressure = Uuid.parse('00002a36-0000-1000-8000-00805f9b34fb');

  /// iHealth BP - Blood Pressure Feature Characteristic
  static final bloodPressureFeature = Uuid.parse('00002a49-0000-1000-8000-00805f9b34fb');

  // ============================================================
  // iHealth Gluco+ (혈당계)
  // ============================================================

  /// iHealth Glucose - Glucose Service (표준 BLE Health Profile)
  static final glucoseService = Uuid.parse('00001808-0000-1000-8000-00805f9b34fb');

  /// iHealth Glucose - Glucose Measurement Characteristic
  static final glucoseMeasurement = Uuid.parse('00002a18-0000-1000-8000-00805f9b34fb');

  /// iHealth Glucose - Glucose Measurement Context Characteristic
  static final glucoseMeasurementContext = Uuid.parse('00002a34-0000-1000-8000-00805f9b34fb');

  /// iHealth Glucose - Glucose Feature Characteristic
  static final glucoseFeature = Uuid.parse('00002a51-0000-1000-8000-00805f9b34fb');

  /// iHealth Glucose - Record Access Control Point
  static final recordAccessControlPoint = Uuid.parse('00002a52-0000-1000-8000-00805f9b34fb');

  // ============================================================
  // Jiuan/iHealth 자체 프로토콜 (KN-550BT 등)
  // ============================================================

  /// Jiuan Custom Service (com.jiuan.dev)
  static final jiuanCustomService = Uuid.parse('636f6d2e-6a69-7561-6e2e-646576000000');

  /// Jiuan Notify Characteristic (sed.jiuan.dev) - 데이터 수신
  static final jiuanNotifyCharacteristic = Uuid.parse('7365642e-6a69-7561-6e2e-646576000000');

  /// Jiuan Write Characteristic (rec.jiuan.dev) - 명령 전송
  static final jiuanWriteCharacteristic = Uuid.parse('7265632e-6a69-7561-6e2e-646576000000');

  // ============================================================
  // 공통 서비스
  // ============================================================

  /// Device Information Service
  static final deviceInformationService = Uuid.parse('0000180a-0000-1000-8000-00805f9b34fb');

  /// Battery Service
  static final batteryService = Uuid.parse('0000180f-0000-1000-8000-00805f9b34fb');

  /// Battery Level Characteristic
  static final batteryLevel = Uuid.parse('00002a19-0000-1000-8000-00805f9b34fb');

  /// Client Characteristic Configuration Descriptor (CCCD)
  static final clientCharacteristicConfig = Uuid.parse('00002902-0000-1000-8000-00805f9b34fb');

  // ============================================================
  // 기기 식별을 위한 이름 패턴
  // ============================================================

  /// Xiaomi Scale 기기 이름 패턴
  static const xiaomiScaleNamePatterns = [
    'MIBCS',
    'MIBFS',        // Mi Body Fat Scale
    'MI SCALE2',
    'MI_SCALE',
    'MI BODY',      // Mi Body Composition Scale
    'BODY COMPOSITION',
    'XMTZC',
    'MISCALE',
  ];

  /// Omron 혈압계 기기 이름 패턴 (표준 BLE 프로토콜)
  static const omronBpNamePatterns = [
    'HEM-',       // HEM-7156T 등
    'HEM',        // HEM7156T (하이픈 없이)
    'BLEsmart_',  // Omron BLE 접두사
    'BLEsmart',   // Omron BLE (언더스코어 없이)
    'OMRON',
  ];

  /// iHealth 혈압계 기기 이름 패턴 (독점 프로토콜 - 비권장)
  static const ihealthBpNamePatterns = [
    'KN-',       // KN-550BT 등 (Jiuan 프로토콜)
    'iHealth',
  ];

  /// iHealth 혈당계 기기 이름 패턴
  static const ihealthGlucoseNamePatterns = [
    'BG',
    'iHealth-BG',
    'GLUCO',
  ];

  /// 스캔 시 찾을 서비스 UUID 목록
  static List<Uuid> get scanServiceUuids => [
    bodyCompositionService,
    weightScaleService,
    bloodPressureService,
    glucoseService,
  ];
}
