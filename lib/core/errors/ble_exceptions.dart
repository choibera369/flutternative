import '../constants/app_strings.dart';

/// BLE 관련 기본 예외 클래스
sealed class BleException implements Exception {
  const BleException(this.message, this.code);

  final String message;
  final String code;

  /// 사용자에게 표시할 친화적인 메시지
  String get userMessage;

  @override
  String toString() => '$runtimeType: $message (code: $code)';
}

/// 블루투스가 비활성화된 경우
class BleDisabledException extends BleException {
  const BleDisabledException([
    String message = 'Bluetooth is disabled',
  ]) : super(message, 'BLE_DISABLED');

  @override
  String get userMessage => AppStrings.errorBleDisabled;
}

/// 블루투스 LE가 지원되지 않는 경우
class BleNotSupportedException extends BleException {
  const BleNotSupportedException([
    String message = 'Bluetooth LE is not supported on this device',
  ]) : super(message, 'BLE_NOT_SUPPORTED');

  @override
  String get userMessage => AppStrings.errorBleNotSupported;
}

/// 위치 권한이 없는 경우 (Android BLE 스캔에 필요)
class LocationPermissionException extends BleException {
  const LocationPermissionException([
    String message = 'Location permission is required for BLE scanning',
  ]) : super(message, 'LOCATION_PERMISSION_DENIED');

  @override
  String get userMessage => AppStrings.errorLocationPermission;
}

/// 블루투스 권한이 없는 경우
class BluetoothPermissionException extends BleException {
  const BluetoothPermissionException([
    String message = 'Bluetooth permission is required',
  ]) : super(message, 'BLUETOOTH_PERMISSION_DENIED');

  @override
  String get userMessage => AppStrings.errorBluetoothPermission;
}

/// 연결 시간 초과
class ConnectionTimeoutException extends BleException {
  const ConnectionTimeoutException([
    String message = 'Connection timed out',
    this.deviceId,
  ]) : super(message, 'CONNECTION_TIMEOUT');

  final String? deviceId;

  @override
  String get userMessage => AppStrings.errorConnectionTimeout;
}

/// 연결 실패
class ConnectionFailedException extends BleException {
  const ConnectionFailedException([
    String message = 'Failed to connect to device',
    this.deviceId,
    this.cause,
  ]) : super(message, 'CONNECTION_FAILED');

  final String? deviceId;
  final Object? cause;

  @override
  String get userMessage => AppStrings.errorConnectionFailed;
}

/// 기기를 찾을 수 없는 경우
class DeviceNotFoundException extends BleException {
  const DeviceNotFoundException([
    String message = 'Device not found',
    this.deviceId,
  ]) : super(message, 'DEVICE_NOT_FOUND');

  final String? deviceId;

  @override
  String get userMessage => AppStrings.errorDeviceNotFound;
}

/// 측정 실패
class MeasurementFailedException extends BleException {
  const MeasurementFailedException([
    String message = 'Measurement failed',
    this.cause,
  ]) : super(message, 'MEASUREMENT_FAILED');

  final Object? cause;

  @override
  String get userMessage => AppStrings.errorMeasurementFailed;
}

/// 데이터 파싱 실패
class DataParseException extends BleException {
  const DataParseException([
    String message = 'Failed to parse data',
    this.rawData,
  ]) : super(message, 'DATA_PARSE_FAILED');

  final List<int>? rawData;

  @override
  String get userMessage => AppStrings.errorDataParseFailed;
}

/// 서비스 검색 실패
class ServiceDiscoveryException extends BleException {
  const ServiceDiscoveryException([
    String message = 'Failed to discover services',
    this.deviceId,
  ]) : super(message, 'SERVICE_DISCOVERY_FAILED');

  final String? deviceId;

  @override
  String get userMessage => AppStrings.errorConnectionFailed;
}

/// Characteristic 찾을 수 없음
class CharacteristicNotFoundException extends BleException {
  const CharacteristicNotFoundException([
    String message = 'Characteristic not found',
    this.characteristicUuid,
  ]) : super(message, 'CHARACTERISTIC_NOT_FOUND');

  final String? characteristicUuid;

  @override
  String get userMessage => AppStrings.errorConnectionFailed;
}

/// 알 수 없는 BLE 오류
class UnknownBleException extends BleException {
  const UnknownBleException([
    String message = 'Unknown BLE error occurred',
    this.cause,
  ]) : super(message, 'UNKNOWN_ERROR');

  final Object? cause;

  @override
  String get userMessage => AppStrings.errorUnknown;
}

/// BLE 예외 변환 유틸리티
class BleExceptionHandler {
  BleExceptionHandler._();

  /// 일반 예외를 BleException으로 변환
  static BleException fromException(Object error) {
    if (error is BleException) {
      return error;
    }

    final message = error.toString().toLowerCase();

    if (message.contains('bluetooth') && message.contains('off')) {
      return const BleDisabledException();
    }

    if (message.contains('permission')) {
      if (message.contains('location')) {
        return const LocationPermissionException();
      }
      return const BluetoothPermissionException();
    }

    if (message.contains('timeout')) {
      return const ConnectionTimeoutException();
    }

    if (message.contains('not found')) {
      return const DeviceNotFoundException();
    }

    return UnknownBleException(error.toString(), error);
  }
}
