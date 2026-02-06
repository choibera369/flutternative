import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/constants/ble_uuids.dart';
import '../../data/models/body_composition.dart';
import '../supabase_service.dart';
import 'base_device_service.dart';

/// 사용자 프로필 정보 (체성분 계산에 필요)
class UserProfile {
  const UserProfile({
    required this.age,
    required this.height,
    required this.isMale,
  });

  final int age;
  final double height; // cm
  final bool isMale;
}

/// Xiaomi Mi Body Composition Scale 2 서비스
class XiaomiScaleService extends BaseDeviceService<BodyComposition> {
  XiaomiScaleService({
    required super.bleCore,
    super.deviceId,
    this.userProfile,
  });

  /// 체성분 계산을 위한 사용자 프로필
  UserProfile? userProfile;

  /// 안정화된 측정만 저장할지 여부
  bool onlyStabilizedMeasurements = true;

  /// 임시 측정값 (안정화 전)
  final _unstabilizedSubject = BehaviorSubject<BodyComposition?>.seeded(null);

  Stream<BodyComposition?> get unstabilizedStream =>
      _unstabilizedSubject.stream;

  BodyComposition? get unstabilizedMeasurement => _unstabilizedSubject.value;

  @override
  Uuid get serviceUuid => BleUuids.bodyCompositionService;

  @override
  Uuid get measurementCharacteristicUuid => BleUuids.bodyCompositionMeasurement;

  @override
  Future<void> onConnected() async {
    print('>>> XiaomiScale onConnected - starting measurement');
    // 체중계는 연결 즉시 측정 시작
    await startMeasurement();
    print('>>> XiaomiScale measurement state: $measurementState');
  }

  @override
  Future<void> subscribeToMeasurements() async {
    // Body Composition Service의 알림 구독
    final stream = bleCore.subscribeToCharacteristic(
      deviceId: deviceId!,
      serviceUuid: serviceUuid,
      characteristicUuid: measurementCharacteristicUuid,
    );

    // Weight Scale Service도 함께 구독 (fallback)
    Stream<List<int>>? weightStream;
    try {
      weightStream = bleCore.subscribeToCharacteristic(
        deviceId: deviceId!,
        serviceUuid: BleUuids.weightScaleService,
        characteristicUuid: BleUuids.weightMeasurement,
      );
    } catch (_) {
      // Weight Scale Service가 없을 수 있음
    }

    // 두 스트림 병합
    final mergedStream = weightStream != null
        ? Rx.merge([stream, weightStream])
        : stream;

    notificationSubscription = mergedStream.listen(
      (data) async {
        try {
          final measurement = await parseData(data);
          if (measurement != null) {
            // 체중계에서 내려갔으면 측정 완료로 처리
            if (measurement.isWeightRemoved) {
              print('>>> Weight removed! Completing measurement: ${measurement.weight} kg');
              // 측정 완료 처리
              _addMeasurementInternal(measurement);
              _unstabilizedSubject.add(null);
            } else {
              // 측정 중 - 실시간 표시용
              print('>>> Updating unstabilized: ${measurement.weight} kg');
              _unstabilizedSubject.add(measurement);
            }
          }
        } catch (e) {
          print('>>> Parse error: $e');
        }
      },
      onError: (error) {
        print('>>> Stream error: $error');
      },
    );
  }

  void _addMeasurementInternal(BodyComposition measurement) {
    print('>>> _addMeasurementInternal called: ${measurement.weight} kg');
    var finalMeasurement = measurement;

    // 사용자 프로필이 있으면 체성분 계산 (임피던스 없이도 추정 가능)
    if (userProfile != null) {
      finalMeasurement = measurement.calculateBodyComposition(
        age: userProfile!.age,
        height: userProfile!.height,
        isMale: userProfile!.isMale,
      );
      print('>>> 체성분 계산 완료: BMI=${finalMeasurement.bmi}, 체지방=${finalMeasurement.bodyFatPercentage}%');
    } else {
      print('>>> 사용자 프로필 없음 - 체성분 계산 건너뜀');
    }

    // 부모 클래스의 측정 추가 로직 사용
    latestMeasurementSubject.add(finalMeasurement);

    final history = List<BodyComposition>.from(measurementHistorySubject.value);
    history.insert(0, finalMeasurement);

    if (history.length > 100) {
      history.removeLast();
    }

    measurementHistorySubject.add(history);
    measurementStateSubject.add(MeasurementState.completed);

    // 불안정한 측정값 초기화
    _unstabilizedSubject.add(null);

    // Supabase에 체성분 데이터 업로드
    SupabaseMeasurementService.instance.saveBodyComposition(finalMeasurement).then(
      (success) {
        if (success) {
          print('>>> Supabase: 체중 데이터 전송 완료');
        } else {
          print('>>> Supabase: 체중 데이터 전송 실패');
        }
      },
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (measurementState == MeasurementState.completed) {
        measurementStateSubject.add(MeasurementState.ready);
      }
    });
  }

  @override
  Future<BodyComposition?> parseData(List<int> data) async {
    // Xiaomi Mi Body Composition Scale 2 포맷 (13 bytes):
    // [0]: 0x02 (패킷 타입)
    // [1]: 플래그
    //      - Bit 5 (0x20): 체중 안정화 + 체중계에서 내려감
    //      - Bit 7 (0x80): 임피던스 측정 완료
    // [2-3]: 연도 (little endian)
    // [4]: 월
    // [5]: 일
    // [6]: 시
    // [7]: 분
    // [8]: 초
    // [9-10]: 임피던스 (little endian, 0x0000 또는 0xffxx = 미측정)
    // [11-12]: 체중 (little endian, 0.005 kg 단위 = catty)

    if (data.length < 13) {
      print('Scale data too short: ${data.length} bytes');
      return null;
    }

    // 디버그 출력
    print('Scale raw: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}');

    // 플래그 파싱
    final flags = data[1];
    final isWeightRemoved = (flags & 0x20) != 0;
    final hasImpedance = (flags & 0x80) != 0;

    // 체중 파싱 (bytes 11-12, 0.005 kg = catty 단위)
    final weightRaw = data[11] | (data[12] << 8);
    final weight = weightRaw * 0.005;

    // 너무 낮은 체중은 무시 (아직 올라가지 않음)
    if (weight < 5.0) {
      print('Weight too low: $weight kg (raw: $weightRaw)');
      return null;
    }

    // 임피던스 파싱
    int? impedance;
    if (hasImpedance) {
      final impRaw = data[9] | (data[10] << 8);
      // 0xffxx는 미측정/무효 값
      if (impRaw < 0xff00 && impRaw > 0) {
        impedance = impRaw;
      }
    }

    // 안정화 여부: isWeightRemoved가 true면 측정 완료
    final isStabilized = isWeightRemoved;

    print('Parsed: ${weight.toStringAsFixed(2)} kg, stable=$isStabilized, removed=$isWeightRemoved, imp=$impedance');

    return BodyComposition(
      id: generateId(),
      timestamp: DateTime.now(),
      weight: double.parse(weight.toStringAsFixed(2)),
      impedance: impedance,
      isStabilized: isStabilized,
      isWeightRemoved: isWeightRemoved,
      deviceId: deviceId,
    );
  }

  /// 사용자 프로필 설정
  void setUserProfile(UserProfile profile) {
    userProfile = profile;
  }

  @override
  Future<void> dispose() async {
    await _unstabilizedSubject.close();
    await super.dispose();
  }
}
