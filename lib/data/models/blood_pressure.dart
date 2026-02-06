import 'package:json_annotation/json_annotation.dart';

part 'blood_pressure.g.dart';

/// 혈압 상태 분류
enum BloodPressureCategory {
  /// 정상 (< 120/80)
  normal,

  /// 주의 (120-129 / < 80)
  elevated,

  /// 고혈압 1단계 (130-139 / 80-89)
  hypertensionStage1,

  /// 고혈압 2단계 (>= 140 / >= 90)
  hypertensionStage2,

  /// 고혈압 위기 (> 180 / > 120)
  hypertensiveCrisis,

  /// 저혈압 (< 90/60)
  hypotension,
}

/// 혈압 측정 데이터 (iHealth Track)
@JsonSerializable()
class BloodPressureReading {
  const BloodPressureReading({
    required this.id,
    required this.timestamp,
    required this.systolic,
    required this.diastolic,
    this.pulse,
    this.meanArterialPressure,
    this.irregularPulseDetected = false,
    this.cuffFitDetected,
    this.movementDetected,
    this.measurementStatus,
    this.userId,
    this.deviceId,
    this.syncedAt,
  });

  /// 고유 ID
  final String id;

  /// 측정 시간
  final DateTime timestamp;

  /// 수축기 혈압 (mmHg)
  final int systolic;

  /// 이완기 혈압 (mmHg)
  final int diastolic;

  /// 맥박 (bpm)
  final int? pulse;

  /// 평균 동맥압 (mmHg)
  final int? meanArterialPressure;

  /// 불규칙 맥박 감지 여부
  final bool irregularPulseDetected;

  /// 커프 착용 상태 감지
  final bool? cuffFitDetected;

  /// 움직임 감지
  final bool? movementDetected;

  /// 측정 상태 코드
  final int? measurementStatus;

  /// 사용자 ID
  final String? userId;

  /// 측정 기기 ID
  final String? deviceId;

  /// 서버 동기화 시간
  final DateTime? syncedAt;

  /// 혈압 분류
  BloodPressureCategory get category {
    if (systolic > 180 || diastolic > 120) {
      return BloodPressureCategory.hypertensiveCrisis;
    }
    if (systolic < 90 || diastolic < 60) {
      return BloodPressureCategory.hypotension;
    }
    if (systolic >= 140 || diastolic >= 90) {
      return BloodPressureCategory.hypertensionStage2;
    }
    if (systolic >= 130 || diastolic >= 80) {
      return BloodPressureCategory.hypertensionStage1;
    }
    if (systolic >= 120) {
      return BloodPressureCategory.elevated;
    }
    return BloodPressureCategory.normal;
  }

  /// Nombre de la categoría de presión arterial
  String get categoryName {
    switch (category) {
      case BloodPressureCategory.normal:
        return 'Normal';
      case BloodPressureCategory.elevated:
        return 'Elevada';
      case BloodPressureCategory.hypertensionStage1:
        return 'Hipertensión Etapa 1';
      case BloodPressureCategory.hypertensionStage2:
        return 'Hipertensión Etapa 2';
      case BloodPressureCategory.hypertensiveCrisis:
        return 'Crisis hipertensiva';
      case BloodPressureCategory.hypotension:
        return 'Hipotensión';
    }
  }

  /// 평균 동맥압 계산 (측정값이 없는 경우)
  int get calculatedMAP {
    if (meanArterialPressure != null) return meanArterialPressure!;
    return ((2 * diastolic + systolic) / 3).round();
  }

  factory BloodPressureReading.fromJson(Map<String, dynamic> json) =>
      _$BloodPressureReadingFromJson(json);

  Map<String, dynamic> toJson() => _$BloodPressureReadingToJson(this);

  /// BLE Blood Pressure Measurement 데이터에서 파싱
  /// 표준 BLE Blood Pressure Profile (0x2A35) 데이터 포맷
  factory BloodPressureReading.fromBleData({
    required String id,
    required List<int> data,
    String? deviceId,
    String? userId,
  }) {
    if (data.isEmpty) {
      throw FormatException('Empty data');
    }

    final flags = data[0];

    // Units: 0 = mmHg, 1 = kPa
    final isKpa = (flags & 0x01) != 0;
    final hasTimestamp = (flags & 0x02) != 0;
    final hasPulseRate = (flags & 0x04) != 0;
    final hasUserId = (flags & 0x08) != 0;
    final hasMeasurementStatus = (flags & 0x10) != 0;

    int offset = 1;

    // Systolic (SFLOAT - 2 bytes)
    int systolicRaw = _parseSFloat(data, offset);
    offset += 2;

    // Diastolic (SFLOAT - 2 bytes)
    int diastolicRaw = _parseSFloat(data, offset);
    offset += 2;

    // Mean Arterial Pressure (SFLOAT - 2 bytes)
    int? mapRaw = _parseSFloat(data, offset);
    offset += 2;

    // kPa를 mmHg로 변환 (1 kPa = 7.50062 mmHg)
    final systolic = isKpa ? (systolicRaw * 7.50062).round() : systolicRaw;
    final diastolic = isKpa ? (diastolicRaw * 7.50062).round() : diastolicRaw;
    final meanArterialPressure = (isKpa ? (mapRaw * 7.50062).round() : mapRaw);

    // Timestamp (optional)
    DateTime timestamp;
    if (hasTimestamp && data.length >= offset + 7) {
      final year = data[offset] | (data[offset + 1] << 8);
      final month = data[offset + 2];
      final day = data[offset + 3];
      final hour = data[offset + 4];
      final minute = data[offset + 5];
      final second = data[offset + 6];
      offset += 7;

      try {
        timestamp = DateTime(year, month, day, hour, minute, second);
      } catch (_) {
        timestamp = DateTime.now();
      }
    } else {
      timestamp = DateTime.now();
    }

    // Pulse Rate (optional)
    int? pulse;
    if (hasPulseRate && data.length >= offset + 2) {
      pulse = _parseSFloat(data, offset);
      offset += 2;
    }

    // User ID (optional - skip)
    if (hasUserId && data.length >= offset + 1) {
      offset += 1;
    }

    // Measurement Status (optional)
    int? measurementStatus;
    bool irregularPulse = false;
    bool? cuffFitDetected;
    bool? movementDetected;

    if (hasMeasurementStatus && data.length >= offset + 2) {
      measurementStatus = data[offset] | (data[offset + 1] << 8);

      // 비트 플래그 파싱
      // Bit 0: Body Movement
      // Bit 1: Cuff fit
      // Bit 2: Irregular Pulse
      movementDetected = (measurementStatus & 0x01) != 0;
      cuffFitDetected = (measurementStatus & 0x02) != 0;
      irregularPulse = (measurementStatus & 0x04) != 0;
    }

    return BloodPressureReading(
      id: id,
      timestamp: timestamp,
      systolic: systolic,
      diastolic: diastolic,
      pulse: pulse,
      meanArterialPressure: meanArterialPressure,
      irregularPulseDetected: irregularPulse,
      cuffFitDetected: cuffFitDetected,
      movementDetected: movementDetected,
      measurementStatus: measurementStatus,
      deviceId: deviceId,
      userId: userId,
    );
  }

  /// SFLOAT (IEEE 11073) 파싱
  static int _parseSFloat(List<int> data, int offset) {
    if (data.length < offset + 2) return 0;

    final raw = data[offset] | (data[offset + 1] << 8);

    // SFLOAT: 4-bit exponent + 12-bit mantissa
    int mantissa = raw & 0x0FFF;
    int exponent = (raw >> 12) & 0x0F;

    // Sign extension for mantissa
    if (mantissa >= 0x0800) {
      mantissa -= 0x1000;
    }

    // Sign extension for exponent
    if (exponent >= 0x08) {
      exponent -= 0x10;
    }

    // Special values
    if (mantissa == 0x07FF) return 0; // NaN
    if (mantissa == 0x0800) return 0; // NRes
    if (mantissa == 0x07FE) return 0; // +INFINITY
    if (mantissa == 0x0802) return 0; // -INFINITY

    // Calculate value
    final value = mantissa * _pow10(exponent);
    return value.round();
  }

  static double _pow10(int exp) {
    if (exp >= 0) {
      double result = 1.0;
      for (int i = 0; i < exp; i++) {
        result *= 10.0;
      }
      return result;
    } else {
      double result = 1.0;
      for (int i = 0; i < -exp; i++) {
        result /= 10.0;
      }
      return result;
    }
  }

  BloodPressureReading copyWith({
    String? id,
    DateTime? timestamp,
    int? systolic,
    int? diastolic,
    int? pulse,
    int? meanArterialPressure,
    bool? irregularPulseDetected,
    bool? cuffFitDetected,
    bool? movementDetected,
    int? measurementStatus,
    String? userId,
    String? deviceId,
    DateTime? syncedAt,
  }) {
    return BloodPressureReading(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      systolic: systolic ?? this.systolic,
      diastolic: diastolic ?? this.diastolic,
      pulse: pulse ?? this.pulse,
      meanArterialPressure: meanArterialPressure ?? this.meanArterialPressure,
      irregularPulseDetected:
          irregularPulseDetected ?? this.irregularPulseDetected,
      cuffFitDetected: cuffFitDetected ?? this.cuffFitDetected,
      movementDetected: movementDetected ?? this.movementDetected,
      measurementStatus: measurementStatus ?? this.measurementStatus,
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }
}
