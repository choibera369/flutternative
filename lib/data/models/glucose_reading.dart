import 'package:json_annotation/json_annotation.dart';

part 'glucose_reading.g.dart';

/// 식사 상태 (혈당 측정 컨텍스트)
enum MealContext {
  /// 공복
  fasting,

  /// 식전
  preprandial,

  /// 식후
  postprandial,

  /// 무관 / 무작위
  casual,

  /// 취침 전
  bedtime,

  /// 알 수 없음
  unknown,
}

/// 혈당 상태 분류
enum GlucoseCategory {
  /// 저혈당 (< 70 mg/dL)
  hypoglycemia,

  /// 정상 (70-99 mg/dL 공복 기준)
  normal,

  /// 당뇨병 전단계 (100-125 mg/dL 공복 기준)
  prediabetes,

  /// 당뇨병 (>= 126 mg/dL 공복 기준)
  diabetes,
}

/// 혈당 측정 데이터 (iHealth Gluco+)
@JsonSerializable()
class GlucoseReading {
  const GlucoseReading({
    required this.id,
    required this.timestamp,
    required this.glucoseMgDl,
    this.mealContext = MealContext.unknown,
    this.sequenceNumber,
    this.sampleType,
    this.sampleLocation,
    this.sensorStatus,
    this.userId,
    this.deviceId,
    this.syncedAt,
  });

  /// 고유 ID
  final String id;

  /// 측정 시간
  final DateTime timestamp;

  /// 혈당 값 (mg/dL)
  final double glucoseMgDl;

  /// 식사 상태
  final MealContext mealContext;

  /// 측정 순번 (기기 내부)
  final int? sequenceNumber;

  /// 샘플 유형 (모세혈, 정맥혈 등)
  final int? sampleType;

  /// 샘플 위치 (손가락, 팔 등)
  final int? sampleLocation;

  /// 센서 상태
  final int? sensorStatus;

  /// 사용자 ID
  final String? userId;

  /// 측정 기기 ID
  final String? deviceId;

  /// 서버 동기화 시간
  final DateTime? syncedAt;

  /// 혈당 값 (mmol/L 단위)
  double get glucoseMmolL => glucoseMgDl / 18.0182;

  /// 혈당 분류 (공복 기준)
  GlucoseCategory get categoryFasting {
    if (glucoseMgDl < 70) return GlucoseCategory.hypoglycemia;
    if (glucoseMgDl < 100) return GlucoseCategory.normal;
    if (glucoseMgDl < 126) return GlucoseCategory.prediabetes;
    return GlucoseCategory.diabetes;
  }

  /// 혈당 분류 (식후 2시간 기준)
  GlucoseCategory get categoryPostprandial {
    if (glucoseMgDl < 70) return GlucoseCategory.hypoglycemia;
    if (glucoseMgDl < 140) return GlucoseCategory.normal;
    if (glucoseMgDl < 200) return GlucoseCategory.prediabetes;
    return GlucoseCategory.diabetes;
  }

  /// 현재 식사 상태에 따른 분류
  GlucoseCategory get category {
    if (mealContext == MealContext.fasting ||
        mealContext == MealContext.preprandial) {
      return categoryFasting;
    }
    if (mealContext == MealContext.postprandial) {
      return categoryPostprandial;
    }
    // casual/unknown인 경우 공복 기준 사용
    return categoryFasting;
  }

  /// Nombre de la categoría de glucosa
  String get categoryName {
    switch (category) {
      case GlucoseCategory.hypoglycemia:
        return 'Hipoglucemia';
      case GlucoseCategory.normal:
        return 'Normal';
      case GlucoseCategory.prediabetes:
        return 'Prediabetes';
      case GlucoseCategory.diabetes:
        return 'Rango diabético';
    }
  }

  /// Nombre del contexto alimentario
  String get mealContextName {
    switch (mealContext) {
      case MealContext.fasting:
        return 'Ayuno';
      case MealContext.preprandial:
        return 'Antes de comer';
      case MealContext.postprandial:
        return 'Después de comer';
      case MealContext.casual:
        return 'Casual';
      case MealContext.bedtime:
        return 'Antes de dormir';
      case MealContext.unknown:
        return 'No especificado';
    }
  }

  factory GlucoseReading.fromJson(Map<String, dynamic> json) =>
      _$GlucoseReadingFromJson(json);

  Map<String, dynamic> toJson() => _$GlucoseReadingToJson(this);

  /// BLE Glucose Measurement 데이터에서 파싱
  /// 표준 BLE Glucose Profile (0x2A18) 데이터 포맷
  factory GlucoseReading.fromBleData({
    required String id,
    required List<int> data,
    List<int>? contextData,
    String? deviceId,
    String? userId,
  }) {
    if (data.length < 3) {
      throw FormatException('Invalid data length: ${data.length}');
    }

    final flags = data[0];

    final hasTimeOffset = (flags & 0x01) != 0;
    final hasConcentration = (flags & 0x02) != 0;
    final isMolL = (flags & 0x04) != 0; // 0 = kg/L (mg/dL), 1 = mol/L
    final hasSampleInfo = (flags & 0x08) != 0;
    final hasSensorStatus = (flags & 0x10) != 0;
    final hasContextInfo = (flags & 0x20) != 0;

    int offset = 1;

    // Sequence Number (2 bytes)
    final sequenceNumber = data[offset] | (data[offset + 1] << 8);
    offset += 2;

    // Base Time (7 bytes)
    DateTime timestamp;
    if (data.length >= offset + 7) {
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

    // Time Offset (optional, 2 bytes)
    if (hasTimeOffset && data.length >= offset + 2) {
      final timeOffset = data[offset] | (data[offset + 1] << 8);
      // timeOffset은 분 단위, signed int16
      final offsetMinutes =
          timeOffset >= 0x8000 ? timeOffset - 0x10000 : timeOffset;
      timestamp = timestamp.add(Duration(minutes: offsetMinutes));
      offset += 2;
    }

    // Glucose Concentration (SFLOAT, 2 bytes)
    double glucoseMgDl = 0;
    if (hasConcentration && data.length >= offset + 2) {
      final raw = data[offset] | (data[offset + 1] << 8);
      final concentration = _parseSFloat(raw);
      offset += 2;

      if (isMolL) {
        // mol/L to mg/dL (1 mmol/L = 18.0182 mg/dL)
        glucoseMgDl = concentration * 1000 * 18.0182;
      } else {
        // kg/L to mg/dL (kg/L * 1000000 = mg/L, mg/L / 10 = mg/dL)
        glucoseMgDl = concentration * 100000;
      }
    }

    // Sample Type and Location (optional, 1 byte)
    int? sampleType;
    int? sampleLocation;
    if (hasSampleInfo && data.length >= offset + 1) {
      final typeLocation = data[offset];
      sampleType = typeLocation & 0x0F;
      sampleLocation = (typeLocation >> 4) & 0x0F;
      offset += 1;
    }

    // Sensor Status (optional, 2 bytes)
    int? sensorStatus;
    if (hasSensorStatus && data.length >= offset + 2) {
      sensorStatus = data[offset] | (data[offset + 1] << 8);
      offset += 2;
    }

    // Parse context data if available
    MealContext mealContext = MealContext.unknown;
    if (hasContextInfo && contextData != null && contextData.isNotEmpty) {
      mealContext = _parseMealContext(contextData);
    }

    return GlucoseReading(
      id: id,
      timestamp: timestamp,
      glucoseMgDl: glucoseMgDl,
      mealContext: mealContext,
      sequenceNumber: sequenceNumber,
      sampleType: sampleType,
      sampleLocation: sampleLocation,
      sensorStatus: sensorStatus,
      deviceId: deviceId,
      userId: userId,
    );
  }

  /// SFLOAT 파싱
  static double _parseSFloat(int raw) {
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
    if (mantissa == 0x07FF ||
        mantissa == 0x0800 ||
        mantissa == 0x07FE ||
        mantissa == 0x0802) {
      return 0;
    }

    double result = mantissa.toDouble();
    if (exponent >= 0) {
      for (int i = 0; i < exponent; i++) {
        result *= 10;
      }
    } else {
      for (int i = 0; i < -exponent; i++) {
        result /= 10;
      }
    }
    return result;
  }

  /// Glucose Measurement Context에서 식사 상태 파싱
  static MealContext _parseMealContext(List<int> contextData) {
    if (contextData.length < 2) return MealContext.unknown;

    final flags = contextData[0];
    final hasMeal = (flags & 0x02) != 0;

    if (!hasMeal) return MealContext.unknown;

    // Carbohydrate ID (1 byte if present)
    int offset = 1;

    // Sequence Number (2 bytes)
    offset += 2;

    // Extended Flags (1 byte if present)
    if ((flags & 0x80) != 0) {
      offset += 1;
    }

    // Carbohydrate (3 bytes if present)
    if ((flags & 0x01) != 0 && contextData.length >= offset + 3) {
      offset += 3;
    }

    // Meal (1 byte if present)
    if ((flags & 0x02) != 0 && contextData.length >= offset + 1) {
      final mealValue = contextData[offset];
      switch (mealValue) {
        case 1:
          return MealContext.preprandial; // Before meal
        case 2:
          return MealContext.postprandial; // After meal
        case 3:
          return MealContext.fasting;
        case 4:
          return MealContext.casual;
        case 5:
          return MealContext.bedtime;
        default:
          return MealContext.unknown;
      }
    }

    return MealContext.unknown;
  }

  GlucoseReading copyWith({
    String? id,
    DateTime? timestamp,
    double? glucoseMgDl,
    MealContext? mealContext,
    int? sequenceNumber,
    int? sampleType,
    int? sampleLocation,
    int? sensorStatus,
    String? userId,
    String? deviceId,
    DateTime? syncedAt,
  }) {
    return GlucoseReading(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      glucoseMgDl: glucoseMgDl ?? this.glucoseMgDl,
      mealContext: mealContext ?? this.mealContext,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      sampleType: sampleType ?? this.sampleType,
      sampleLocation: sampleLocation ?? this.sampleLocation,
      sensorStatus: sensorStatus ?? this.sensorStatus,
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }
}
