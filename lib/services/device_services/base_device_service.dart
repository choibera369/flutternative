import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart' as uuid_pkg;

import '../ble_core_service.dart';
import '../../core/errors/ble_exceptions.dart';

/// 측정 상태
enum MeasurementState {
  /// 유휴 상태
  idle,

  /// 측정 대기 중 (연결됨, 측정 시작 전)
  ready,

  /// 측정 중
  measuring,

  /// 측정 완료
  completed,

  /// 오류 발생
  error,
}

/// 기기 서비스 추상 클래스
///
/// 각 기기별 서비스는 이 클래스를 상속받아 구현
abstract class BaseDeviceService<T> {
  BaseDeviceService({
    required this.bleCore,
    String? deviceId,
  }) : _deviceId = deviceId;

  final BleCoreService bleCore;
  String? _deviceId;

  /// 현재 연결된 기기 ID
  String? get deviceId => _deviceId;

  /// 측정 상태 스트림 (서브클래스에서 접근 가능)
  @protected
  final measurementStateSubject =
      BehaviorSubject<MeasurementState>.seeded(MeasurementState.idle);

  Stream<MeasurementState> get measurementStateStream =>
      measurementStateSubject.stream;

  MeasurementState get measurementState => measurementStateSubject.value;

  /// 최근 측정 데이터 스트림 (서브클래스에서 접근 가능)
  @protected
  final latestMeasurementSubject = BehaviorSubject<T?>.seeded(null);

  Stream<T?> get latestMeasurementStream => latestMeasurementSubject.stream;

  T? get latestMeasurement => latestMeasurementSubject.value;

  /// 측정 데이터 히스토리 스트림 (서브클래스에서 접근 가능)
  @protected
  final measurementHistorySubject = BehaviorSubject<List<T>>.seeded([]);

  Stream<List<T>> get measurementHistoryStream =>
      measurementHistorySubject.stream;

  List<T> get measurementHistory => measurementHistorySubject.value;

  /// 에러 스트림
  @protected
  final errorSubject = BehaviorSubject<BleException?>.seeded(null);

  Stream<BleException?> get errorStream => errorSubject.stream;

  BleException? get lastError => errorSubject.value;

  /// Characteristic 구독 관리 (서브클래스에서 접근 가능)
  @protected
  StreamSubscription<List<int>>? notificationSubscription;

  /// 기기에 연결
  Future<void> connect(String deviceId) async {
    _deviceId = deviceId;
    measurementStateSubject.add(MeasurementState.idle);
    errorSubject.add(null);

    try {
      await bleCore.connect(deviceId);

      // 연결 성공 후 서비스 검색
      await bleCore.discoverServices(deviceId);

      // 기기별 초기화
      await onConnected();

      // onConnected에서 이미 상태를 변경했으면 덮어쓰지 않음
      if (measurementState == MeasurementState.idle) {
        measurementStateSubject.add(MeasurementState.ready);
      }
    } catch (e) {
      final exception = BleExceptionHandler.fromException(e);
      errorSubject.add(exception);
      measurementStateSubject.add(MeasurementState.error);
      rethrow;
    }
  }

  /// 기기 연결 해제
  Future<void> disconnect() async {
    await stopMeasurement();

    if (_deviceId != null) {
      await bleCore.disconnect(_deviceId!);
      await onDisconnected();
    }

    measurementStateSubject.add(MeasurementState.idle);
    _deviceId = null;
  }

  /// 측정 시작
  Future<void> startMeasurement() async {
    if (_deviceId == null) {
      throw const ConnectionFailedException('Device not connected');
    }

    if (measurementState == MeasurementState.measuring) {
      return;
    }

    measurementStateSubject.add(MeasurementState.measuring);
    errorSubject.add(null);

    try {
      await subscribeToMeasurements();
    } catch (e) {
      final exception = BleExceptionHandler.fromException(e);
      errorSubject.add(exception);
      measurementStateSubject.add(MeasurementState.error);
      rethrow;
    }
  }

  /// 측정 중지
  Future<void> stopMeasurement() async {
    await notificationSubscription?.cancel();
    notificationSubscription = null;

    if (measurementState == MeasurementState.measuring) {
      measurementStateSubject.add(MeasurementState.ready);
    }
  }

  /// Characteristic 알림 구독
  Future<void> subscribeToMeasurements() async {
    final stream = bleCore.subscribeToCharacteristic(
      deviceId: _deviceId!,
      serviceUuid: serviceUuid,
      characteristicUuid: measurementCharacteristicUuid,
    );

    notificationSubscription = stream.listen(
      (data) async {
        try {
          final measurement = await parseData(data);
          if (measurement != null) {
            _addMeasurement(measurement);
          }
        } catch (e) {
          final exception = e is BleException
              ? e
              : DataParseException(e.toString(), data);
          errorSubject.add(exception);
        }
      },
      onError: (error) {
        final exception = BleExceptionHandler.fromException(error);
        errorSubject.add(exception);
        measurementStateSubject.add(MeasurementState.error);
      },
    );
  }

  /// 측정 데이터 추가
  void _addMeasurement(T measurement) {
    latestMeasurementSubject.add(measurement);

    final history = List<T>.from(measurementHistorySubject.value);
    history.insert(0, measurement);

    // 최대 100개 유지
    if (history.length > 100) {
      history.removeLast();
    }

    measurementHistorySubject.add(history);
    measurementStateSubject.add(MeasurementState.completed);

    // 측정 완료 후 다시 준비 상태로
    Future.delayed(const Duration(seconds: 2), () {
      if (measurementState == MeasurementState.completed) {
        measurementStateSubject.add(MeasurementState.ready);
      }
    });
  }

  /// 히스토리 초기화
  void clearHistory() {
    measurementHistorySubject.add([]);
    latestMeasurementSubject.add(null);
  }

  /// 리소스 해제
  Future<void> dispose() async {
    await disconnect();
    await measurementStateSubject.close();
    await latestMeasurementSubject.close();
    await measurementHistorySubject.close();
    await errorSubject.close();
  }

  /// 고유 ID 생성
  String generateId() {
    return const uuid_pkg.Uuid().v4();
  }

  // ============================================================
  // 서브클래스에서 구현해야 하는 추상 멤버
  // ============================================================

  /// 서비스 UUID
  Uuid get serviceUuid;

  /// 측정 Characteristic UUID
  Uuid get measurementCharacteristicUuid;

  /// BLE 데이터 파싱
  Future<T?> parseData(List<int> data);

  /// 연결 완료 후 초기화 (서브클래스에서 오버라이드)
  Future<void> onConnected() async {}

  /// 연결 해제 후 정리 (서브클래스에서 오버라이드)
  Future<void> onDisconnected() async {}
}
