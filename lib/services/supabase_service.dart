import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/blood_pressure.dart';
import '../data/models/body_composition.dart';

/// Supabase 측정 데이터 업로드 서비스
///
/// BLE 기기에서 수신된 혈압/체중 데이터를 measurements 테이블에 저장합니다.
/// 네트워크 오류 시 로그만 남기고 앱 흐름을 중단하지 않습니다.
class SupabaseMeasurementService {
  SupabaseMeasurementService._();

  static SupabaseMeasurementService? _instance;
  static SupabaseMeasurementService get instance =>
      _instance ??= SupabaseMeasurementService._();

  /// Supabase 설정
  /// TODO: .env 또는 설정 화면에서 로드
  static const supabaseUrl = 'https://qujlhyskdhutqdzbstzv.supabase.co';
  static const supabaseAnonKey = 'sb_publishable_pJlAzFKAcyWNyvGDkfsZ-w_WT-jckCx';

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// 현재 환자 ID (의사 웹에서 설정하거나 설문 완료 시 할당)
  String? _patientId;

  /// 환자 ID 설정
  void setPatientId(String? id) {
    _patientId = id;
    debugPrint('>>> Supabase: patient_id = $id');
  }

  String? get patientId => _patientId;

  /// Supabase 초기화
  ///
  /// main() 및 backgroundMain()에서 호출합니다.
  /// 이미 초기화된 경우 건너뜁니다.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      _initialized = true;
      debugPrint('>>> Supabase 초기화 완료');
    } catch (e) {
      debugPrint('>>> Supabase 초기화 실패: $e');
    }
  }

  SupabaseClient get _client => Supabase.instance.client;

  /// 혈압 측정 데이터 저장
  Future<bool> saveBloodPressure(BloodPressureReading reading) async {
    if (!_initialized) {
      debugPrint('>>> Supabase 미초기화 - 혈압 저장 건너뜀');
      return false;
    }

    try {
      await _client.from('measurements').insert({
        'patient_id': _patientId,
        'device_type': 'blood_pressure',
        'systolic': reading.systolic,
        'diastolic': reading.diastolic,
        'heart_rate': reading.pulse,
        'measured_at': reading.timestamp.toIso8601String(),
      });

      debugPrint('>>> Supabase: 혈압 저장 완료 '
          '${reading.systolic}/${reading.diastolic}');
      return true;
    } catch (e) {
      debugPrint('>>> Supabase: 혈압 저장 실패 - $e');
      return false;
    }
  }

  /// 마지막 에러 메시지 (디버그용)
  String? lastError;

  /// 체중/체성분 측정 데이터 저장
  Future<bool> saveBodyComposition(BodyComposition composition) async {
    if (!_initialized) {
      lastError = 'no inicializado';
      return false;
    }

    // 1차: 전체 컬럼 시도
    try {
      final data = <String, dynamic>{
        'patient_id': _patientId,
        'device_type': 'scale',
        'weight': composition.weight,
        'impedance': composition.impedance,
        'measured_at': composition.timestamp.toIso8601String(),
      };

      if (composition.bodyFatPercentage != null) data['body_fat'] = composition.bodyFatPercentage;
      if (composition.muscleMass != null) data['muscle_mass'] = composition.muscleMass;
      if (composition.bmi != null) data['bmi'] = composition.bmi;
      if (composition.waterPercentage != null) data['body_water'] = composition.waterPercentage;
      if (composition.boneMass != null) data['bone_mass'] = composition.boneMass;
      if (composition.visceralFat != null) data['visceral_fat'] = composition.visceralFat;
      if (composition.basalMetabolism != null) data['basal_metabolism'] = composition.basalMetabolism;
      if (composition.proteinPercentage != null) data['protein'] = composition.proteinPercentage;
      if (composition.metabolicAge != null) data['body_age'] = composition.metabolicAge;

      debugPrint('>>> Supabase: INSERT 시도 - $data');
      await _client.from('measurements').insert(data);

      lastError = null;
      debugPrint('>>> Supabase: 체중 저장 완료');
      return true;
    } catch (e) {
      debugPrint('>>> Supabase: 1차 실패 - $e');

      // 2차: 최소 컬럼만 재시도
      try {
        await _client.from('measurements').insert({
          'device_type': 'scale',
          'weight': composition.weight,
          'measured_at': composition.timestamp.toIso8601String(),
        });
        lastError = null;
        debugPrint('>>> Supabase: 최소 컬럼 저장 완료');
        return true;
      } catch (e2) {
        lastError = '$e2';
        debugPrint('>>> Supabase: 최소 컬럼도 실패 - $e2');
        return false;
      }
    }
  }
}
