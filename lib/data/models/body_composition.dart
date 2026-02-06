import 'package:json_annotation/json_annotation.dart';

part 'body_composition.g.dart';

/// 체성분 측정 데이터 (Xiaomi Mi Body Composition Scale 2)
@JsonSerializable()
class BodyComposition {
  const BodyComposition({
    required this.id,
    required this.timestamp,
    required this.weight,
    this.bmi,
    this.bodyFatPercentage,
    this.muscleMass,
    this.waterPercentage,
    this.boneMass,
    this.visceralFat,
    this.basalMetabolism,
    this.metabolicAge,
    this.proteinPercentage,
    this.impedance,
    this.isStabilized = true,
    this.isWeightRemoved = false,
    this.deviceId,
    this.userId,
    this.syncedAt,
  });

  /// 고유 ID
  final String id;

  /// 측정 시간
  final DateTime timestamp;

  /// 체중 (kg)
  final double weight;

  /// BMI (Body Mass Index)
  final double? bmi;

  /// 체지방률 (%)
  final double? bodyFatPercentage;

  /// 근육량 (kg)
  final double? muscleMass;

  /// 체수분 (%)
  final double? waterPercentage;

  /// 골격량 (kg)
  final double? boneMass;

  /// 내장지방 레벨 (1-59)
  final int? visceralFat;

  /// 기초대사량 (kcal)
  final int? basalMetabolism;

  /// 대사 연령 (세)
  final int? metabolicAge;

  /// 단백질 (%)
  final double? proteinPercentage;

  /// 임피던스 값 (체성분 계산에 사용)
  final int? impedance;

  /// 측정 안정화 여부
  final bool isStabilized;

  /// 체중계에서 내려감 (측정 완료)
  final bool isWeightRemoved;

  /// 측정 기기 ID
  final String? deviceId;

  /// 사용자 ID
  final String? userId;

  /// 서버 동기화 시간
  final DateTime? syncedAt;

  /// 체성분 데이터가 있는지 (단순 체중만이 아닌)
  bool get hasBodyComposition =>
      bodyFatPercentage != null ||
      muscleMass != null ||
      waterPercentage != null;

  factory BodyComposition.fromJson(Map<String, dynamic> json) =>
      _$BodyCompositionFromJson(json);

  Map<String, dynamic> toJson() => _$BodyCompositionToJson(this);

  /// Xiaomi Scale BLE 데이터에서 파싱
  factory BodyComposition.fromBleData({
    required String id,
    required List<int> data,
    String? deviceId,
    String? userId,
  }) {
    // Xiaomi Scale의 Weight Measurement 데이터 파싱
    // 데이터 포맷: [flags(1), weight_low(1), weight_high(1), ...]

    if (data.length < 10) {
      throw FormatException('Invalid data length: ${data.length}');
    }

    final flags = data[0];
    final isStabilized = (flags & 0x20) != 0;
    final hasImpedance = (flags & 0x02) != 0;

    // 체중 파싱 (little-endian, 단위: 0.01 kg 또는 0.01 lb)
    final weightRaw = data[1] | (data[2] << 8);
    final isLb = (flags & 0x01) != 0;
    final weight = isLb ? weightRaw * 0.01 * 0.453592 : weightRaw * 0.005;

    // 임피던스 파싱 (있는 경우)
    int? impedance;
    if (hasImpedance && data.length >= 12) {
      impedance = data[9] | (data[10] << 8);
    }

    // 년월일 파싱
    final year = data[3] | (data[4] << 8);
    final month = data[5];
    final day = data[6];
    final hour = data[7];
    final minute = data[8];
    final second = data.length > 9 ? data[9] : 0;

    DateTime timestamp;
    try {
      timestamp = DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      timestamp = DateTime.now();
    }

    return BodyComposition(
      id: id,
      timestamp: timestamp,
      weight: weight,
      impedance: impedance,
      isStabilized: isStabilized,
      deviceId: deviceId,
      userId: userId,
    );
  }

  /// 체성분 계산 (사용자 정보 필요)
  /// 임피던스가 있으면 BIA 기반 정확한 계산, 없으면 BMI 기반 추정
  BodyComposition calculateBodyComposition({
    required int age,
    required double height, // cm
    required bool isMale,
  }) {
    final heightM = height / 100;
    final heightSquared = heightM * heightM;

    // BMI 계산
    final bmi = weight / heightSquared;

    double bodyFat;
    double leanMass;

    // 임피던스가 유효하면 BIA 기반 계산 (더 정확함)
    final hasValidImpedance = impedance != null && impedance! > 0 && impedance! < 3000;

    if (hasValidImpedance) {
      // ========================================
      // 임피던스 기반 계산 (BIA - Bioelectrical Impedance Analysis)
      // Xiaomi/Huami 역공학 공식 기반
      // ========================================
      final imp = impedance!.toDouble();

      // LBM (Lean Body Mass) 계산 - 제지방량
      if (isMale) {
        leanMass = (height * height / imp) * 0.449 +
            weight * 0.680 +
            height * (-0.137) +
            age * (-0.037) -
            8.0;
      } else {
        leanMass = (height * height / imp) * 0.429 +
            weight * 0.699 +
            height * (-0.137) +
            age * (-0.037) -
            8.0;
      }

      // 제지방량 범위 제한
      leanMass = leanMass.clamp(weight * 0.4, weight * 0.95);

      // 체지방률 계산
      final fatMass = weight - leanMass;
      bodyFat = (fatMass / weight) * 100;
      bodyFat = bodyFat.clamp(3.0, 60.0);
    } else {
      // ========================================
      // BMI 기반 추정 (임피던스 없을 때 fallback)
      // Gallagher et al. formula
      // ========================================
      if (isMale) {
        bodyFat = (1.20 * bmi) + (0.23 * age) - 16.2;
      } else {
        bodyFat = (1.20 * bmi) + (0.23 * age) - 5.4;
      }
      bodyFat = bodyFat.clamp(5.0, 60.0);

      final fatMass = weight * (bodyFat / 100);
      leanMass = weight - fatMass;
    }

    // 근육량 계산 - 제지방량의 약 75%
    final muscleMass = leanMass * 0.75;

    // 체수분 계산 - 제지방량의 약 73%
    final waterPercentage = (leanMass * 0.73 / weight) * 100;

    // 골격량 계산
    final boneMass = isMale
        ? 0.029 * weight + 0.18 * heightM - 0.89
        : 0.026 * weight + 0.16 * heightM - 0.64;

    // 내장지방 레벨 계산 (1-30)
    int visceralFat;
    if (isMale) {
      visceralFat = ((age * 0.15) + (bodyFat * 0.35) - 10).round().clamp(1, 30);
    } else {
      visceralFat = ((age * 0.12) + (bodyFat * 0.30) - 8).round().clamp(1, 30);
    }

    // 기초대사량 계산 (Mifflin-St Jeor 공식)
    int basalMetabolism;
    if (isMale) {
      basalMetabolism = (10 * weight + 6.25 * height - 5 * age + 5).round();
    } else {
      basalMetabolism = (10 * weight + 6.25 * height - 5 * age - 161).round();
    }

    // 대사 연령 계산
    final idealBodyFat = isMale ? 15.0 : 23.0;
    final metabolicAge = (age + (bodyFat - idealBodyFat) * 0.5).round().clamp(18, 99);

    // 단백질 비율 계산 - 근육량의 약 20%
    final proteinPercentage = (muscleMass * 0.2 / weight * 100).clamp(10.0, 25.0);

    return BodyComposition(
      id: id,
      timestamp: timestamp,
      weight: weight,
      bmi: double.parse(bmi.toStringAsFixed(1)),
      bodyFatPercentage: double.parse(bodyFat.toStringAsFixed(1)),
      muscleMass: double.parse(muscleMass.toStringAsFixed(1)),
      waterPercentage: double.parse(waterPercentage.toStringAsFixed(1)),
      boneMass: double.parse(boneMass.toStringAsFixed(2)),
      visceralFat: visceralFat,
      basalMetabolism: basalMetabolism,
      metabolicAge: metabolicAge,
      proteinPercentage: double.parse(proteinPercentage.toStringAsFixed(1)),
      impedance: impedance,
      isStabilized: isStabilized,
      isWeightRemoved: isWeightRemoved,
      deviceId: deviceId,
      userId: userId,
    );
  }

  BodyComposition copyWith({
    String? id,
    DateTime? timestamp,
    double? weight,
    double? bmi,
    double? bodyFatPercentage,
    double? muscleMass,
    double? waterPercentage,
    double? boneMass,
    int? visceralFat,
    int? basalMetabolism,
    int? metabolicAge,
    double? proteinPercentage,
    int? impedance,
    bool? isStabilized,
    bool? isWeightRemoved,
    String? deviceId,
    String? userId,
    DateTime? syncedAt,
  }) {
    return BodyComposition(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      weight: weight ?? this.weight,
      bmi: bmi ?? this.bmi,
      bodyFatPercentage: bodyFatPercentage ?? this.bodyFatPercentage,
      muscleMass: muscleMass ?? this.muscleMass,
      waterPercentage: waterPercentage ?? this.waterPercentage,
      boneMass: boneMass ?? this.boneMass,
      visceralFat: visceralFat ?? this.visceralFat,
      basalMetabolism: basalMetabolism ?? this.basalMetabolism,
      metabolicAge: metabolicAge ?? this.metabolicAge,
      proteinPercentage: proteinPercentage ?? this.proteinPercentage,
      impedance: impedance ?? this.impedance,
      isStabilized: isStabilized ?? this.isStabilized,
      isWeightRemoved: isWeightRemoved ?? this.isWeightRemoved,
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }
}
