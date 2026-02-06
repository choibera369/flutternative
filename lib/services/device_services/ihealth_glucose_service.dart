import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/constants/ble_uuids.dart';
import '../../data/models/glucose_reading.dart';
import 'base_device_service.dart';

/// Record Access Control Point (RACP) 명령어
class RacpCommand {
  static const reportAllRecords = [
    0x01,
    0x01,
  ]; // Report stored records - All records
  static const reportFirstRecord = [
    0x01,
    0x05,
  ]; // Report stored records - First record
  static const reportLastRecord = [
    0x01,
    0x06,
  ]; // Report stored records - Last record
  static const deleteAllRecords = [
    0x02,
    0x01,
  ]; // Delete stored records - All records
  static const reportNumberOfRecords = [
    0x04,
    0x01,
  ]; // Report number of stored records
  static const abortOperation = [0x03]; // Abort operation
}

/// RACP 응답 코드
enum RacpResponseCode {
  success(1),
  opCodeNotSupported(2),
  invalidOperator(3),
  operatorNotSupported(4),
  invalidOperand(5),
  noRecordsFound(6),
  abortUnsuccessful(7),
  procedureNotCompleted(8),
  operandNotSupported(9);

  const RacpResponseCode(this.value);
  final int value;

  static RacpResponseCode fromValue(int value) {
    return RacpResponseCode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RacpResponseCode.opCodeNotSupported,
    );
  }
}

/// iHealth Gluco+ 혈당계 서비스
class IHealthGlucoseService extends BaseDeviceService<GlucoseReading> {
  IHealthGlucoseService({required super.bleCore, super.deviceId});

  /// 저장된 레코드 수
  final _recordCountSubject = BehaviorSubject<int?>.seeded(null);

  Stream<int?> get recordCountStream => _recordCountSubject.stream;

  int? get recordCount => _recordCountSubject.value;

  /// 다운로드 진행률 (0-100%)
  final _downloadProgressSubject = BehaviorSubject<int>.seeded(0);

  Stream<int> get downloadProgressStream => _downloadProgressSubject.stream;

  int get downloadProgress => _downloadProgressSubject.value;

  /// Context 데이터 임시 저장
  final Map<int, List<int>> _contextDataMap = {};

  /// RACP 구독
  StreamSubscription<List<int>>? _racpSubscription;

  /// Context 구독
  StreamSubscription<List<int>>? _contextSubscription;

  @override
  Uuid get serviceUuid => BleUuids.glucoseService;

  @override
  Uuid get measurementCharacteristicUuid => BleUuids.glucoseMeasurement;

  @override
  Future<void> onConnected() async {
    measurementStateSubject.add(MeasurementState.ready);

    // Context 알림 구독
    try {
      final contextStream = bleCore.subscribeToCharacteristic(
        deviceId: deviceId!,
        serviceUuid: serviceUuid,
        characteristicUuid: BleUuids.glucoseMeasurementContext,
      );

      _contextSubscription = contextStream.listen((data) {
        if (data.length >= 3) {
          // Sequence number (bytes 1-2)
          final seqNum = data[1] | (data[2] << 8);
          _contextDataMap[seqNum] = data;
        }
      }, onError: (_) {});
    } catch (_) {
      // Context가 지원되지 않을 수 있음
    }

    // RACP 알림 구독
    try {
      final racpStream = bleCore.subscribeToCharacteristic(
        deviceId: deviceId!,
        serviceUuid: serviceUuid,
        characteristicUuid: BleUuids.recordAccessControlPoint,
      );

      _racpSubscription = racpStream.listen((data) {
        _handleRacpResponse(data);
      }, onError: (_) {});
    } catch (_) {
      // RACP가 지원되지 않을 수 있음
    }
  }

  @override
  Future<void> subscribeToMeasurements() async {
    final stream = bleCore.subscribeToCharacteristic(
      deviceId: deviceId!,
      serviceUuid: serviceUuid,
      characteristicUuid: measurementCharacteristicUuid,
    );

    notificationSubscription = stream.listen(
      (data) async {
        try {
          final measurement = await parseData(data);
          if (measurement != null) {
            _addMeasurementInternal(measurement);
          }
        } catch (e) {
          // 파싱 에러
        }
      },
      onError: (error) {
        measurementStateSubject.add(MeasurementState.error);
      },
    );
  }

  void _addMeasurementInternal(GlucoseReading measurement) {
    latestMeasurementSubject.add(measurement);

    final history = List<GlucoseReading>.from(measurementHistorySubject.value);

    // 중복 체크 (sequence number 기반)
    final isDuplicate = history.any(
      (r) => r.sequenceNumber == measurement.sequenceNumber,
    );

    if (!isDuplicate) {
      history.insert(0, measurement);

      if (history.length > 100) {
        history.removeLast();
      }

      measurementHistorySubject.add(history);
    }

    measurementStateSubject.add(MeasurementState.completed);

    // 다운로드 진행률 업데이트
    if (recordCount != null && recordCount! > 0) {
      final progress = ((history.length / recordCount!) * 100).round();
      _downloadProgressSubject.add(progress.clamp(0, 100));
    }
  }

  @override
  Future<GlucoseReading?> parseData(List<int> data) async {
    if (data.length < 3) return null;

    try {
      // Sequence number 추출하여 context 데이터 찾기
      final seqNum = data[1] | (data[2] << 8);
      final contextData = _contextDataMap[seqNum];

      final reading = GlucoseReading.fromBleData(
        id: generateId(),
        data: data,
        contextData: contextData,
        deviceId: deviceId,
      );

      // 사용된 context 데이터 제거
      _contextDataMap.remove(seqNum);

      return reading;
    } catch (e) {
      return null;
    }
  }

  /// RACP 응답 처리
  void _handleRacpResponse(List<int> data) {
    if (data.length < 2) return;

    final opCode = data[0];

    // Number of Records Response (0x05)
    if (opCode == 0x05 && data.length >= 4) {
      final count = data[2] | (data[3] << 8);
      _recordCountSubject.add(count);
      return;
    }

    // Response Code (0x06)
    if (opCode == 0x06 && data.length >= 4) {
      final requestOpCode = data[1];
      final responseCode = RacpResponseCode.fromValue(data[3]);

      if (requestOpCode == 0x01) {
        // Report Stored Records 응답
        if (responseCode == RacpResponseCode.success) {
          // 데이터 전송 완료
          _downloadProgressSubject.add(100);
        } else if (responseCode == RacpResponseCode.noRecordsFound) {
          // 레코드 없음
          _recordCountSubject.add(0);
          _downloadProgressSubject.add(100);
        }
      }
    }
  }

  /// 저장된 레코드 수 조회
  Future<void> getRecordCount() async {
    if (deviceId == null) return;

    await bleCore.writeCharacteristic(
      deviceId: deviceId!,
      serviceUuid: serviceUuid,
      characteristicUuid: BleUuids.recordAccessControlPoint,
      value: RacpCommand.reportNumberOfRecords,
    );
  }

  /// 모든 저장된 레코드 다운로드
  Future<void> downloadAllRecords() async {
    if (deviceId == null) return;

    _downloadProgressSubject.add(0);
    measurementStateSubject.add(MeasurementState.measuring);

    // 먼저 레코드 수 조회
    await getRecordCount();

    // 잠시 대기 후 레코드 요청
    await Future.delayed(const Duration(milliseconds: 500));

    await bleCore.writeCharacteristic(
      deviceId: deviceId!,
      serviceUuid: serviceUuid,
      characteristicUuid: BleUuids.recordAccessControlPoint,
      value: RacpCommand.reportAllRecords,
    );
  }

  /// 마지막 레코드만 다운로드
  Future<void> downloadLastRecord() async {
    if (deviceId == null) return;

    measurementStateSubject.add(MeasurementState.measuring);

    await bleCore.writeCharacteristic(
      deviceId: deviceId!,
      serviceUuid: serviceUuid,
      characteristicUuid: BleUuids.recordAccessControlPoint,
      value: RacpCommand.reportLastRecord,
    );
  }

  /// 모든 레코드 삭제
  Future<void> deleteAllRecords() async {
    if (deviceId == null) return;

    await bleCore.writeCharacteristic(
      deviceId: deviceId!,
      serviceUuid: serviceUuid,
      characteristicUuid: BleUuids.recordAccessControlPoint,
      value: RacpCommand.deleteAllRecords,
    );

    // 로컬 히스토리도 초기화
    clearHistory();
    _recordCountSubject.add(0);
  }

  /// 진행 중인 작업 중단
  Future<void> abortOperation() async {
    if (deviceId == null) return;

    await bleCore.writeCharacteristic(
      deviceId: deviceId!,
      serviceUuid: serviceUuid,
      characteristicUuid: BleUuids.recordAccessControlPoint,
      value: RacpCommand.abortOperation,
    );

    measurementStateSubject.add(MeasurementState.ready);
  }

  @override
  Future<void> stopMeasurement() async {
    await abortOperation();
    await super.stopMeasurement();
  }

  @override
  Future<void> dispose() async {
    await _racpSubscription?.cancel();
    await _contextSubscription?.cancel();
    await _recordCountSubject.close();
    await _downloadProgressSubject.close();
    _contextDataMap.clear();
    await super.dispose();
  }
}
