import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

import '../core/constants/ble_uuids.dart';
import '../core/errors/ble_exceptions.dart';

/// BLE 연결 상태
enum BleConnectionState {
  /// 연결 안됨
  disconnected,

  /// 연결 중
  connecting,

  /// 연결됨
  connected,

  /// 연결 해제 중
  disconnecting,
}

/// 검색된 기기 정보 (앱 내부용)
class ScannedDevice {
  const ScannedDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.deviceType,
    this.serviceUuids = const [],
    this.manufacturerData,
  });

  final String id;
  final String name;
  final int rssi;
  final DeviceType deviceType;
  final List<Uuid> serviceUuids;
  final List<int>? manufacturerData;

  /// RSSI 기반 신호 강도 (0-4)
  int get signalStrength {
    if (rssi >= -50) return 4;
    if (rssi >= -60) return 3;
    if (rssi >= -70) return 2;
    if (rssi >= -80) return 1;
    return 0;
  }
}

/// 기기 유형
enum DeviceType {
  /// 샤오미 체중계
  xiaomiScale,

  /// iHealth 혈압계
  ihealthBloodPressure,

  /// iHealth 혈당계
  ihealthGlucose,

  /// 알 수 없는 기기
  unknown,
}

/// BLE 핵심 서비스
///
/// BLE 스캔, 연결, 서비스 검색 등 핵심 기능 제공
class BleCoreService {
  BleCoreService._();

  static BleCoreService? _instance;
  static BleCoreService get instance => _instance ??= BleCoreService._();

  final FlutterReactiveBle _ble = FlutterReactiveBle();

  /// 플랫폼 채널 (본딩된 기기 조회용)
  static const _channel = MethodChannel('com.invinco.flutternative/bluetooth');

  /// BLE 상태 스트림
  Stream<BleStatus> get bleStatusStream => _ble.statusStream;

  /// 현재 BLE 상태
  BleStatus get currentStatus => _ble.status;

  // 스캔 관련
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  final _discoveredDevicesSubject = BehaviorSubject<List<ScannedDevice>>.seeded([]);
  final _isScanning = BehaviorSubject<bool>.seeded(false);

  /// 검색된 기기 목록 스트림
  Stream<List<ScannedDevice>> get discoveredDevicesStream =>
      _discoveredDevicesSubject.stream;

  /// 현재 검색된 기기 목록
  List<ScannedDevice> get discoveredDevices => _discoveredDevicesSubject.value;

  /// 스캔 중 여부 스트림
  Stream<bool> get isScanningStream => _isScanning.stream;

  /// 스캔 중 여부
  bool get isScanning => _isScanning.value;

  // 연결 관리
  final Map<String, StreamSubscription<ConnectionStateUpdate>> _connectionSubscriptions = {};
  final Map<String, BehaviorSubject<BleConnectionState>> _connectionStates = {};

  /// 특정 기기의 연결 상태 스트림
  Stream<BleConnectionState> connectionStateStream(String deviceId) {
    _connectionStates[deviceId] ??=
        BehaviorSubject<BleConnectionState>.seeded(BleConnectionState.disconnected);
    return _connectionStates[deviceId]!.stream;
  }

  /// 특정 기기의 현재 연결 상태
  BleConnectionState connectionState(String deviceId) {
    return _connectionStates[deviceId]?.value ?? BleConnectionState.disconnected;
  }

  /// 권한 확인 및 요청
  Future<void> checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      // Android 12+ (API 31+)
      final bluetoothScan = await Permission.bluetoothScan.request();
      final bluetoothConnect = await Permission.bluetoothConnect.request();
      final location = await Permission.locationWhenInUse.request();

      if (bluetoothScan.isDenied || bluetoothConnect.isDenied) {
        throw const BluetoothPermissionException();
      }

      if (location.isDenied) {
        throw const LocationPermissionException();
      }
    } else if (Platform.isIOS) {
      final bluetooth = await Permission.bluetooth.request();
      if (bluetooth.isDenied) {
        throw const BluetoothPermissionException();
      }
    }
  }

  /// BLE 상태 확인
  Future<void> ensureBleEnabled() async {
    final status = _ble.status;
    if (status == BleStatus.unsupported) {
      throw const BleNotSupportedException();
    }
    if (status == BleStatus.poweredOff) {
      throw const BleDisabledException();
    }
    if (status == BleStatus.unauthorized) {
      throw const BluetoothPermissionException();
    }
  }

  /// 기기 스캔 시작
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
    List<Uuid>? serviceUuids,
  }) async {
    await checkAndRequestPermissions();
    await ensureBleEnabled();

    // 기존 스캔 중지
    await stopScan();

    // 기기 목록 초기화
    _discoveredDevicesSubject.add([]);
    _isScanning.add(true);

    // 본딩된 기기 먼저 추가 (광고 안 해도 연결 가능)
    await addBondedDevicesToScanList();

    // 모든 기기 스캔 (서비스 UUID 필터 없이)
    // iHealth 등 일부 기기는 광고 패킷에 서비스 UUID를 포함하지 않음
    final scanStream = _ble.scanForDevices(
      withServices: serviceUuids ?? [],
      scanMode: ScanMode.lowLatency,
    );

    _scanSubscription = scanStream.listen(
      (device) {
        final scannedDevice = _mapToScannedDevice(device);
        if (scannedDevice.name.isEmpty) return;

        final currentList = List<ScannedDevice>.from(_discoveredDevicesSubject.value);
        final existingIndex = currentList.indexWhere((d) => d.id == scannedDevice.id);

        if (existingIndex >= 0) {
          currentList[existingIndex] = scannedDevice;
        } else {
          currentList.add(scannedDevice);
        }

        // RSSI 기준 정렬 (강한 신호 우선)
        currentList.sort((a, b) => b.rssi.compareTo(a.rssi));
        _discoveredDevicesSubject.add(currentList);
      },
      onError: (error) {
        _isScanning.add(false);
        throw BleExceptionHandler.fromException(error);
      },
    );

    // 타임아웃 후 자동 중지
    Future.delayed(timeout, () {
      if (_isScanning.value) {
        stopScan();
      }
    });
  }

  /// 기기 스캔 중지
  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning.add(false);
  }

  /// 본딩된(페어링된) 기기 목록 가져오기
  Future<List<ScannedDevice>> getBondedDevices() async {
    if (!Platform.isAndroid) return [];

    try {
      final List<dynamic> result = await _channel.invokeMethod('getBondedDevices');
      final bondedDevices = <ScannedDevice>[];

      for (final device in result) {
        final map = Map<String, dynamic>.from(device);
        final name = map['name'] as String? ?? '';
        final id = map['id'] as String? ?? '';

        if (name.isEmpty || id.isEmpty) continue;

        final deviceType = _identifyDeviceTypeByName(name);
        bondedDevices.add(ScannedDevice(
          id: id,
          name: name,
          rssi: -50, // 본딩된 기기는 RSSI 정보 없음
          deviceType: deviceType,
        ));
      }

      return bondedDevices;
    } catch (e) {
      print('>>> Failed to get bonded devices: $e');
      return [];
    }
  }

  /// 본딩된 기기를 스캔 목록에 추가
  Future<void> addBondedDevicesToScanList() async {
    final bondedDevices = await getBondedDevices();
    print('>>> Found ${bondedDevices.length} bonded devices');

    for (final device in bondedDevices) {
      print('>>> Bonded device: ${device.name} (${device.id}) - ${device.deviceType}');
    }

    // 알려진 기기 유형만 추가
    final knownDevices = bondedDevices
        .where((d) => d.deviceType != DeviceType.unknown)
        .toList();

    if (knownDevices.isNotEmpty) {
      final currentList = List<ScannedDevice>.from(_discoveredDevicesSubject.value);

      for (final bondedDevice in knownDevices) {
        final existingIndex = currentList.indexWhere((d) => d.id == bondedDevice.id);
        if (existingIndex < 0) {
          currentList.add(bondedDevice);
        }
      }

      _discoveredDevicesSubject.add(currentList);
    }
  }

  /// 기기 이름으로 유형 판별
  DeviceType _identifyDeviceTypeByName(String name) {
    final upperName = name.toUpperCase();

    for (final pattern in BleUuids.xiaomiScaleNamePatterns) {
      if (upperName.contains(pattern.toUpperCase())) {
        return DeviceType.xiaomiScale;
      }
    }

    for (final pattern in BleUuids.ihealthBpNamePatterns) {
      if (upperName.contains(pattern.toUpperCase())) {
        return DeviceType.ihealthBloodPressure;
      }
    }

    for (final pattern in BleUuids.ihealthGlucoseNamePatterns) {
      if (upperName.contains(pattern.toUpperCase())) {
        return DeviceType.ihealthGlucose;
      }
    }

    return DeviceType.unknown;
  }

  /// 기기 유형 판별
  DeviceType _identifyDeviceType(DiscoveredDevice device) {
    final name = device.name.toUpperCase();

    // Xiaomi Scale
    for (final pattern in BleUuids.xiaomiScaleNamePatterns) {
      if (name.contains(pattern.toUpperCase())) {
        return DeviceType.xiaomiScale;
      }
    }

    // iHealth 혈압계
    for (final pattern in BleUuids.ihealthBpNamePatterns) {
      if (name.contains(pattern.toUpperCase())) {
        return DeviceType.ihealthBloodPressure;
      }
    }

    // iHealth 혈당계
    for (final pattern in BleUuids.ihealthGlucoseNamePatterns) {
      if (name.contains(pattern.toUpperCase())) {
        return DeviceType.ihealthGlucose;
      }
    }

    // 서비스 UUID로 판별
    final serviceUuids = device.serviceUuids;
    if (serviceUuids.contains(BleUuids.bodyCompositionService) ||
        serviceUuids.contains(BleUuids.weightScaleService)) {
      return DeviceType.xiaomiScale;
    }
    if (serviceUuids.contains(BleUuids.bloodPressureService)) {
      return DeviceType.ihealthBloodPressure;
    }
    if (serviceUuids.contains(BleUuids.glucoseService)) {
      return DeviceType.ihealthGlucose;
    }

    return DeviceType.unknown;
  }

  ScannedDevice _mapToScannedDevice(DiscoveredDevice device) {
    return ScannedDevice(
      id: device.id,
      name: device.name,
      rssi: device.rssi,
      deviceType: _identifyDeviceType(device),
      serviceUuids: device.serviceUuids,
      manufacturerData: device.manufacturerData.isNotEmpty
          ? device.manufacturerData.toList()
          : null,
    );
  }

  /// 기기 연결
  Future<void> connect(
    String deviceId, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await ensureBleEnabled();

    // 이미 연결 중이거나 연결된 경우
    final currentState = connectionState(deviceId);
    if (currentState == BleConnectionState.connecting ||
        currentState == BleConnectionState.connected) {
      return;
    }

    _connectionStates[deviceId] ??=
        BehaviorSubject<BleConnectionState>.seeded(BleConnectionState.disconnected);
    _connectionStates[deviceId]!.add(BleConnectionState.connecting);

    final completer = Completer<void>();

    _connectionSubscriptions[deviceId] = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: timeout,
        )
        .listen(
      (update) {
        switch (update.connectionState) {
          case DeviceConnectionState.connecting:
            _connectionStates[deviceId]!.add(BleConnectionState.connecting);
            break;
          case DeviceConnectionState.connected:
            _connectionStates[deviceId]!.add(BleConnectionState.connected);
            if (!completer.isCompleted) {
              completer.complete();
            }
            break;
          case DeviceConnectionState.disconnecting:
            _connectionStates[deviceId]!.add(BleConnectionState.disconnecting);
            break;
          case DeviceConnectionState.disconnected:
            _connectionStates[deviceId]!.add(BleConnectionState.disconnected);
            if (!completer.isCompleted) {
              completer.completeError(
                ConnectionFailedException('Disconnected', deviceId),
              );
            }
            break;
        }
      },
      onError: (error) {
        _connectionStates[deviceId]!.add(BleConnectionState.disconnected);
        if (!completer.isCompleted) {
          completer.completeError(
            BleExceptionHandler.fromException(error),
          );
        }
      },
    );

    return completer.future;
  }

  /// 기기 연결 해제
  Future<void> disconnect(String deviceId) async {
    await _connectionSubscriptions[deviceId]?.cancel();
    _connectionSubscriptions.remove(deviceId);
    _connectionStates[deviceId]?.add(BleConnectionState.disconnected);
  }

  /// 서비스 검색
  Future<List<Service>> discoverServices(String deviceId) async {
    if (connectionState(deviceId) != BleConnectionState.connected) {
      throw const ConnectionFailedException('Not connected');
    }
    final services = await _ble.getDiscoveredServices(deviceId);

    // 디버그: 검색된 서비스 출력
    print('>>> Discovered ${services.length} services for device $deviceId:');
    for (final service in services) {
      print('>>>   Service: ${service.id}');
      for (final char in service.characteristics) {
        print('>>>     Characteristic: ${char.id}');
        print('>>>       Properties: isReadable=${char.isReadable}, isWritable=${char.isWritableWithResponse || char.isWritableWithoutResponse}, isNotifiable=${char.isNotifiable}, isIndicatable=${char.isIndicatable}');
      }
    }

    return services;
  }

  /// Characteristic 읽기
  Future<List<int>> readCharacteristic({
    required String deviceId,
    required Uuid serviceUuid,
    required Uuid characteristicUuid,
  }) async {
    final characteristic = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
    );
    return _ble.readCharacteristic(characteristic);
  }

  /// Characteristic 쓰기
  Future<void> writeCharacteristic({
    required String deviceId,
    required Uuid serviceUuid,
    required Uuid characteristicUuid,
    required List<int> value,
    bool withResponse = true,
  }) async {
    final characteristic = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
    );
    await _ble.writeCharacteristicWithResponse(characteristic, value: value);
  }

  /// Characteristic 알림 구독
  Stream<List<int>> subscribeToCharacteristic({
    required String deviceId,
    required Uuid serviceUuid,
    required Uuid characteristicUuid,
  }) {
    final characteristic = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
    );
    return _ble.subscribeToCharacteristic(characteristic);
  }

  /// 모든 연결 해제 및 리소스 정리
  Future<void> dispose() async {
    await stopScan();

    for (final deviceId in _connectionSubscriptions.keys.toList()) {
      await disconnect(deviceId);
    }

    await _discoveredDevicesSubject.close();
    await _isScanning.close();

    for (final subject in _connectionStates.values) {
      await subject.close();
    }
    _connectionStates.clear();
  }
}
