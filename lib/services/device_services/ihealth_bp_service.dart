import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/constants/ble_uuids.dart';
import '../../data/models/blood_pressure.dart';
import 'base_device_service.dart';

/// iHealth Track 혈압계 서비스
class IHealthBPService extends BaseDeviceService<BloodPressureReading> {
  IHealthBPService({required super.bleCore, super.deviceId});

  /// 중간 커프 압력 스트림 (측정 중 실시간 압력)
  final _cuffPressureSubject = BehaviorSubject<int?>.seeded(null);

  Stream<int?> get cuffPressureStream => _cuffPressureSubject.stream;

  int? get currentCuffPressure => _cuffPressureSubject.value;

  /// 측정 진행 상태 (0-100%)
  final _progressSubject = BehaviorSubject<int>.seeded(0);

  Stream<int> get progressStream => _progressSubject.stream;

  int get progress => _progressSubject.value;

  StreamSubscription<List<int>>? _cuffPressureSubscription;

  /// Keep-alive 타이머
  Timer? _keepAliveTimer;

  @override
  Uuid get serviceUuid => BleUuids.bloodPressureService;

  @override
  Uuid get measurementCharacteristicUuid => BleUuids.bloodPressureMeasurement;

  @override
  Future<void> onConnected() async {
    print('>>> iHealth BP onConnected - starting subscription immediately');
    // 연결 즉시 구독 시작 (연결이 빨리 끊어지므로 대기하지 않음)
    measurementStateSubject.add(MeasurementState.measuring);
    await subscribeToMeasurements();
  }

  /// Jiuan 프로토콜 사용 여부
  bool _useJiuanProtocol = false;

  /// 이미 구독 중인지 여부
  bool _isSubscribed = false;

  @override
  Future<void> subscribeToMeasurements() async {
    // 이미 구독 중이면 무시
    if (_isSubscribed) {
      print('>>> iHealth BP: Already subscribed, skipping');
      return;
    }
    _isSubscribed = true;
    print('>>> iHealth BP subscribeToMeasurements - starting subscription');

    // 먼저 서비스 검색 결과 확인
    final services = await bleCore.discoverServices(deviceId!);

    // 1. Jiuan 자체 프로토콜 확인 (KN-550BT 등)
    final hasJiuanService = services.any((s) => s.id == BleUuids.jiuanCustomService);
    if (hasJiuanService) {
      print('>>> iHealth BP: Found Jiuan custom protocol!');
      _useJiuanProtocol = true;
      await _subscribeToJiuanProtocol();
      return;
    }

    // 2. 표준 Blood Pressure Service 확인
    final hasBpService = services.any((s) => s.id == serviceUuid);
    if (hasBpService) {
      print('>>> iHealth BP: Found standard Blood Pressure Service');
      await _subscribeToStandardBpProtocol();
      return;
    }

    // 3. 지원되지 않는 기기
    print('>>> iHealth BP: No supported protocol found!');
    print('>>> Available services:');
    for (final service in services) {
      print('>>>   ${service.id}');
    }
    measurementStateSubject.add(MeasurementState.error);
  }

  /// Jiuan 자체 프로토콜 구독 (KN-550BT 등)
  Future<void> _subscribeToJiuanProtocol() async {
    try {
      print('>>> iHealth BP: Preparing Jiuan protocol connection...');

      // 최소 대기 (연결이 빨리 끊어지므로 지연 최소화)
      await Future.delayed(const Duration(milliseconds: 100));

      // Notify characteristic 구독
      print('>>> Subscribing to Jiuan notify characteristic...');
      final stream = bleCore.subscribeToCharacteristic(
        deviceId: deviceId!,
        serviceUuid: BleUuids.jiuanCustomService,
        characteristicUuid: BleUuids.jiuanNotifyCharacteristic,
      );
      print('>>> iHealth BP subscribed to Jiuan notify characteristic');

      // 즉시 시간 동기화 명령 전송 (연결 유지용)
      await _sendTimeSyncCommand();

      print('>>> Waiting for data from device... (press START on the blood pressure monitor)');
      print('>>> NOTE: Connection may drop after ~10 seconds. Start measurement quickly!');

      // Keep-alive 비활성화 - 이 기기는 측정 완료 시에만 데이터 전송
      // _startKeepAlive();

      notificationSubscription = stream.listen(
        (data) async {
          print('>>> Jiuan data received (${data.length} bytes): ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}');
          try {
            final measurement = _parseJiuanData(data);
            if (measurement != null) {
              print('>>> Jiuan parsed: ${measurement.systolic}/${measurement.diastolic} mmHg, pulse=${measurement.pulse}');
              _addMeasurementInternal(measurement);
            }
          } catch (e) {
            print('>>> Jiuan parse error: $e');
          }
        },
        onError: (error) {
          print('>>> Jiuan stream error: $error');
          print('>>> ============================================');
          print('>>> 연결이 끊어졌습니다!');
          print('>>> 해결 방법:');
          print('>>> 1. 안드로이드 설정 → 블루투스');
          print('>>> 2. 새 기기 페어링 → KN-550BT 선택');
          print('>>> 3. 페어링 완료 후 앱에서 다시 연결');
          print('>>> ============================================');
          measurementStateSubject.add(MeasurementState.error);
        },
        onDone: () {
          print('>>> Jiuan stream closed');
          _stopKeepAlive();
          _isSubscribed = false;
          if (measurementState == MeasurementState.measuring) {
            measurementStateSubject.add(MeasurementState.error);
          }
        },
      );

      // 구독 성공 - 측정 대기 상태로 변경
      measurementStateSubject.add(MeasurementState.ready);
      print('>>> iHealth BP ready - waiting for measurement from device');
    } catch (e) {
      print('>>> Jiuan subscription failed: $e');
      print('>>> TIP: Try pairing the device in Android Bluetooth settings first.');
      measurementStateSubject.add(MeasurementState.error);
    }
  }

  /// 시간 동기화 명령 전송 (연결 유지용)
  Future<void> _sendTimeSyncCommand() async {
    try {
      final now = DateTime.now();

      // Jiuan 시간 동기화 프로토콜 (추정)
      // 형식: [cmd, year_high, year_low, month, day, hour, minute, second]
      final command = [
        0x01, // 명령 타입 (시간 동기화)
        (now.year >> 8) & 0xFF,
        now.year & 0xFF,
        now.month,
        now.day,
        now.hour,
        now.minute,
        now.second,
      ];

      print('>>> Sending time sync command: ${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}');

      await bleCore.writeCharacteristic(
        deviceId: deviceId!,
        serviceUuid: BleUuids.jiuanCustomService,
        characteristicUuid: BleUuids.jiuanWriteCharacteristic,
        value: command,
      );

      print('>>> Time sync command sent successfully');
    } catch (e) {
      print('>>> Time sync command failed: $e');
      // 실패해도 계속 진행 - 일부 기기는 이 명령이 필요 없을 수 있음
    }
  }

  /// Keep-alive 시작
  void _startKeepAlive() {
    _stopKeepAlive();
    print('>>> Starting keep-alive timer (every 2 seconds)');
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _sendKeepAlive();
    });
  }

  /// Keep-alive 중지
  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  /// Keep-alive 신호 전송 (시간 동기화 명령 사용)
  Future<void> _sendKeepAlive() async {
    if (deviceId == null) return;

    try {
      // 시간 동기화 명령으로 keep-alive (기기가 인식하는 명령)
      final now = DateTime.now();
      final command = [
        0x01,
        (now.year >> 8) & 0xFF,
        now.year & 0xFF,
        now.month,
        now.day,
        now.hour,
        now.minute,
        now.second,
      ];

      await bleCore.writeCharacteristic(
        deviceId: deviceId!,
        serviceUuid: BleUuids.jiuanCustomService,
        characteristicUuid: BleUuids.jiuanWriteCharacteristic,
        value: command,
      );
      print('>>> Keep-alive sent');
    } catch (e) {
      print('>>> Keep-alive failed: $e');
      _stopKeepAlive();
      _isSubscribed = false;
    }
  }

  /// Jiuan 프로토콜 데이터 파싱
  BloodPressureReading? _parseJiuanData(List<int> data) {
    // Jiuan 프로토콜 형식 (추정 - 실제 데이터 기반으로 조정 필요)
    // 일반적인 혈압 데이터 형식:
    // [header, systolic_high, systolic_low, diastolic_high, diastolic_low, pulse, ...]

    if (data.length < 6) {
      print('>>> Jiuan data too short: ${data.length} bytes');
      return null;
    }

    // 데이터 형식 분석 시도
    // 패턴 1: [type, sys_h, sys_l, dia_h, dia_l, pulse, ...]
    // 패턴 2: [type, sys, dia, pulse, ...]

    int? systolic;
    int? diastolic;
    int? pulse;

    // 첫 바이트가 데이터 타입을 나타낼 수 있음
    final dataType = data[0];
    print('>>> Jiuan data type: 0x${dataType.toRadixString(16)}');

    // 혈압 데이터인지 확인 (일반적으로 특정 타입 코드 사용)
    // 실제 데이터를 보고 조정 필요
    if (data.length >= 4) {
      // 간단한 파싱 시도
      // 많은 기기가 [type, systolic, diastolic, pulse] 형식 사용
      if (data[1] > 50 && data[1] < 250 && // systolic 범위
          data[2] > 30 && data[2] < 150 && // diastolic 범위
          data[3] > 30 && data[3] < 200) { // pulse 범위
        systolic = data[1];
        diastolic = data[2];
        pulse = data[3];
      }
      // 또는 2바이트 값일 수 있음
      else if (data.length >= 7) {
        final sys = (data[1] << 8) | data[2];
        final dia = (data[3] << 8) | data[4];
        final pul = (data[5] << 8) | data[6];

        if (sys > 50 && sys < 250 && dia > 30 && dia < 150 && pul > 30 && pul < 200) {
          systolic = sys;
          diastolic = dia;
          pulse = pul;
        }
      }
    }

    if (systolic == null || diastolic == null) {
      print('>>> Jiuan: Could not parse blood pressure values');
      return null;
    }

    return BloodPressureReading(
      id: generateId(),
      timestamp: DateTime.now(),
      systolic: systolic,
      diastolic: diastolic,
      pulse: pulse,
      deviceId: deviceId,
    );
  }

  /// 표준 Blood Pressure 프로토콜 구독
  Future<void> _subscribeToStandardBpProtocol() async {
    try {
      final bpStream = bleCore.subscribeToCharacteristic(
        deviceId: deviceId!,
        serviceUuid: serviceUuid,
        characteristicUuid: measurementCharacteristicUuid,
      );
      print('>>> iHealth BP subscribed to standard BP measurement characteristic');

      notificationSubscription = bpStream.listen(
        (data) async {
          print('>>> Standard BP data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}');
          try {
            final measurement = await parseData(data);
            if (measurement != null) {
              print('>>> Standard BP parsed: ${measurement.systolic}/${measurement.diastolic} mmHg, pulse=${measurement.pulse}');
              _addMeasurementInternal(measurement);
            }
          } catch (e) {
            print('>>> Standard BP parse error: $e');
          }
        },
        onError: (error) {
          print('>>> Standard BP stream error: $error');
          measurementStateSubject.add(MeasurementState.error);
        },
      );
    } catch (e) {
      print('>>> Standard BP subscription failed: $e');
      measurementStateSubject.add(MeasurementState.error);
      return;
    }

    // Intermediate Cuff Pressure 구독 (있는 경우)
    try {
      final cuffStream = bleCore.subscribeToCharacteristic(
        deviceId: deviceId!,
        serviceUuid: serviceUuid,
        characteristicUuid: BleUuids.intermediateCuffPressure,
      );
      print('>>> iHealth BP subscribed to cuff pressure characteristic');

      _cuffPressureSubscription = cuffStream.listen((data) {
        print('>>> Cuff pressure data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}');
        final pressure = _parseIntermediateCuffPressure(data);
        if (pressure != null) {
          print('>>> Cuff pressure: $pressure mmHg');
          _cuffPressureSubject.add(pressure);
          final estimatedProgress = _estimateProgress(pressure);
          _progressSubject.add(estimatedProgress);
        }
      }, onError: (e) {
        print('>>> Cuff pressure error: $e');
      });
    } catch (e) {
      print('>>> Cuff pressure subscription failed: $e');
    }
  }

  void _addMeasurementInternal(BloodPressureReading measurement) {
    print('>>> iHealth BP _addMeasurementInternal: ${measurement.systolic}/${measurement.diastolic}');
    latestMeasurementSubject.add(measurement);

    final history = List<BloodPressureReading>.from(
      measurementHistorySubject.value,
    );
    history.insert(0, measurement);

    if (history.length > 100) {
      history.removeLast();
    }

    measurementHistorySubject.add(history);
    measurementStateSubject.add(MeasurementState.completed);

    // 측정 완료 시 커프 압력 및 진행률 초기화
    _cuffPressureSubject.add(null);
    _progressSubject.add(100);

    Future.delayed(const Duration(seconds: 3), () {
      if (measurementState == MeasurementState.completed) {
        measurementStateSubject.add(MeasurementState.ready);
        _progressSubject.add(0);
      }
    });
  }

  @override
  Future<BloodPressureReading?> parseData(List<int> data) async {
    if (data.isEmpty) return null;

    try {
      return BloodPressureReading.fromBleData(
        id: generateId(),
        data: data,
        deviceId: deviceId,
      );
    } catch (e) {
      return null;
    }
  }

  /// 중간 커프 압력 파싱
  int? _parseIntermediateCuffPressure(List<int> data) {
    if (data.length < 3) return null;

    // flags (1 byte) + cuff pressure (SFLOAT, 2 bytes)
    final flags = data[0];
    final isKpa = (flags & 0x01) != 0;

    // SFLOAT 파싱
    final raw = data[1] | (data[2] << 8);
    final pressure = _parseSFloat(raw);

    if (isKpa) {
      // kPa to mmHg
      return (pressure * 7.50062).round();
    }
    return pressure.round();
  }

  /// SFLOAT 파싱
  double _parseSFloat(int raw) {
    int mantissa = raw & 0x0FFF;
    int exponent = (raw >> 12) & 0x0F;

    if (mantissa >= 0x0800) mantissa -= 0x1000;
    if (exponent >= 0x08) exponent -= 0x10;

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

  /// 진행률 추정 (커프 압력 기반)
  int _estimateProgress(int pressure) {
    // 일반적인 혈압 측정 과정:
    // 1. 커프 팽창 (0 -> ~180 mmHg) - 0-30%
    // 2. 측정 중 (감압) - 30-90%
    // 3. 완전 감압 - 90-100%

    if (pressure < 30) return 0;
    if (pressure > 180) return 30;

    // 팽창 단계 (30 -> 180)
    if (pressure > 160) {
      return 30;
    }

    // 측정 단계 (180 -> 40)
    // 180에서 시작해서 40까지 감소
    final progressRange = 180 - 40; // 140
    final currentDrop = 180 - pressure;
    final progress = 30 + ((currentDrop / progressRange) * 60).round();

    return progress.clamp(0, 90);
  }

  @override
  Future<void> stopMeasurement() async {
    _stopKeepAlive();
    _isSubscribed = false;
    await _cuffPressureSubscription?.cancel();
    _cuffPressureSubscription = null;
    _cuffPressureSubject.add(null);
    _progressSubject.add(0);
    await super.stopMeasurement();
  }

  @override
  Future<void> dispose() async {
    _stopKeepAlive();
    await _cuffPressureSubscription?.cancel();
    await _cuffPressureSubject.close();
    await _progressSubject.close();
    await super.dispose();
  }
}
