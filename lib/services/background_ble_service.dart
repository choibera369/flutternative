import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

import '../core/constants/ble_uuids.dart';
import '../data/models/blood_pressure.dart';
import '../data/models/body_composition.dart';
import 'supabase_service.dart';

/// 백그라운드 BLE 서비스 상태
enum BackgroundBleState {
  stopped,
  scanning,
  connecting,
  connected,
  receiving,
  error,
}

/// 자동 연결 BLE 서비스 (Omron 혈압계 + Xiaomi 체중계)
class BackgroundBleService {
  BackgroundBleService._();

  static BackgroundBleService? _instance;
  static BackgroundBleService get instance =>
      _instance ??= BackgroundBleService._();

  final FlutterReactiveBle _ble = FlutterReactiveBle();

  /// 플랫폼 채널
  static const _channel = MethodChannel('com.invinco.flutternative/background_ble');

  /// 상태 스트림
  final _stateSubject = BehaviorSubject<BackgroundBleState>.seeded(BackgroundBleState.stopped);
  Stream<BackgroundBleState> get stateStream => _stateSubject.stream;
  BackgroundBleState get state => _stateSubject.value;

  /// 혈압 측정 데이터 스트림
  final _bpSubject = BehaviorSubject<BloodPressureReading?>.seeded(null);
  Stream<BloodPressureReading?> get measurementStream => _bpSubject.stream;
  BloodPressureReading? get latestMeasurement => _bpSubject.value;

  /// 체중 측정 데이터 스트림
  final _weightSubject = BehaviorSubject<BodyComposition?>.seeded(null);
  Stream<BodyComposition?> get weightStream => _weightSubject.stream;
  BodyComposition? get latestWeight => _weightSubject.value;

  /// 연결 로그 스트림
  final _logSubject = BehaviorSubject<String>.seeded('');
  Stream<String> get logStream => _logSubject.stream;

  /// BLE 어댑터 상태 구독
  StreamSubscription<BleStatus>? _bleStatusSubscription;

  /// 스캔/연결 구독
  StreamSubscription<DiscoveredDevice>? _scanSubscription;

  /// Xiaomi 체중계 연결 관련
  StreamSubscription<ConnectionStateUpdate>? _xiaomiConnectionSubscription;
  StreamSubscription<List<int>>? _xiaomiNotificationSubscription;
  String? _connectedXiaomiId;

  /// Omron 혈압계 연결 관련
  StreamSubscription<ConnectionStateUpdate>? _omronConnectionSubscription;
  StreamSubscription<List<int>>? _omronNotificationSubscription;
  String? _connectedOmronId;

  /// 스캔 재시작 타이머
  Timer? _scanRestartTimer;

  /// 측정값 표시 타이머 (60초 후 스탠드바이 모드로 전환)
  Timer? _weightDisplayTimer;
  Timer? _bpDisplayTimer;
  static const _displayDuration = Duration(seconds: 20);

  /// 중복 전송 방지
  List<int>? _lastWeightRawData;  // 마지막 처리된 광고 원본 바이트 (스캔 dedup)
  DateTime? _lastWeightProcessedAt;  // 마지막 체중 데이터 처리 시각
  bool _finalMeasurementDone = false;  // 최종 측정 완료 플래그 (다시 올라가면 리셋)
  DateTime? _lastBpSentAt;
  int? _lastBpSentSystolic;
  int? _lastBpSentDiastolic;
  static const _bpDeduplicateWindow = Duration(seconds: 30);

  /// 체성분 계산용 사용자 프로필 (기본값 설정)
  int _userAge = 30;
  double _userHeight = 170.0; // cm
  bool _userIsMale = true;

  /// 사용자 프로필 설정
  void setUserProfile({required int age, required double height, required bool isMale}) {
    _userAge = age;
    _userHeight = height;
    _userIsMale = isMale;
    _log('사용자 프로필 설정: 나이=$age, 키=$height cm, 성별=${isMale ? "남" : "여"}');
  }

  /// 완전 초기화 (서비스 stop → 상태 클리어 → 서비스 start)
  /// 스캔 구독, 타이머, 연결 등 모든 리소스를 해제하고 처음부터 다시 시작
  Future<void> resetToStandby() async {
    _log('═══ 완전 초기화 시작 ═══');

    // 1. 서비스 완전 중지 (모든 구독, 타이머, 연결 해제)
    await stop();

    // 2. 모든 내부 상태 초기화
    // _finalMeasurementDone = true → 체중계가 아직 광고 중인 이전 최종값 무시
    // 새로 올라가면 중간값(isWeightRemoved=false)이 이 플래그를 false로 리셋
    _finalMeasurementDone = true;
    _lastWeightRawData = null;
    _lastWeightProcessedAt = null;
    _lastBpSentAt = null;
    _lastBpSentSystolic = null;
    _lastBpSentDiastolic = null;
    _lastXiaomiLogTime = null;
    _omronConnectAttemptCount = 0;
    _xiaomiConnectAttemptCount = 0;
    _bondedOmronAddress = null;
    _bondedOmronName = null;
    _bondedXiaomiAddress = null;
    _bondedXiaomiName = null;

    // 3. 표시 초기화
    _weightSubject.add(null);
    _bpSubject.add(null);
    _uploadStatusSubject.add('');

    // 4. 서비스 재시작
    _log('서비스 재시작...');
    await start();

    _log('═══ 완전 초기화 완료 ═══');
  }

  /// 페어링된 Omron 연결 시도 타이머
  Timer? _bondedOmronTimer;

  /// 페어링된 Omron 기기 정보
  String? _bondedOmronAddress;
  String? _bondedOmronName;

  /// 페어링된 Xiaomi 연결 시도 타이머
  Timer? _bondedXiaomiTimer;

  /// 페어링된 Xiaomi 기기 정보
  String? _bondedXiaomiAddress;
  String? _bondedXiaomiName;

  /// 서비스 실행 여부
  bool _isRunning = false;

  /// Omron 연결 쿨다운 (연결 끊김 후 재연결까지 대기)
  bool _omronCooldown = false;
  Timer? _omronCooldownTimer;

  /// Omron 연결 진행 중 플래그 (중복 연결 방지)
  bool _omronConnecting = false;

  /// 서비스 시작
  Future<void> start() async {
    if (_isRunning) {
      _log('이미 실행 중');
      return;
    }

    _log('서비스 시작...');

    // Android: 포그라운드 서비스 시작 전 권한 확인 필수
    if (Platform.isAndroid) {
      final hasPermissions = await _checkAndRequestPermissions();
      if (!hasPermissions) {
        _log('블루투스 권한이 거부됨 - 서비스 시작 불가');
        _stateSubject.add(BackgroundBleState.error);
        return;
      }

      // 포그라운드 서비스 시작 (권한 획득 후)
      try {
        await _channel.invokeMethod('startForegroundService');
        _log('포그라운드 서비스 시작됨');
      } catch (e) {
        _log('포그라운드 서비스 시작 실패: $e');
        _stateSubject.add(BackgroundBleState.error);
        return;
      }
    }

    _isRunning = true;

    // 페어링된 기기들 확인 (Omron용)
    await _findBondedDevices();

    // 페어링된 Omron이 있으면 주기적으로 연결 시도
    if (_bondedOmronAddress != null) {
      _startBondedOmronConnectionLoop();
    }

    // Xiaomi 체중계는 BLE 광고 데이터에서 직접 읽으므로 GATT 연결 불필요
    // 스캔만으로 데이터 수집 가능
    if (_bondedXiaomiAddress != null) {
      _log('[체중계] Xiaomi 페어링됨 - 스캔 모드로 데이터 수집');
    }

    // BLE 어댑터 상태 모니터링 시작
    _bleStatusSubscription?.cancel();
    _bleStatusSubscription = _ble.statusStream.listen((status) {
      _log('BLE 어댑터 상태: $status');
      if (status == BleStatus.ready) {
        // BLE 준비됨 → 스캔이 없으면 시작
        if (_scanSubscription == null && _isRunning) {
          _log('BLE 준비 완료 → 스캔 시작');
          _startScan();
        }
      } else {
        // BLE 비활성 → 스캔 중지 후 대기
        _log('BLE 비활성 ($status) → 스캔 일시 중지, 복구 대기 중');
        _stopScan();
        _scanRestartTimer?.cancel();
        _scanRestartTimer = null;
      }
    });

    // BLE 준비 상태 확인 후 스캔 시작
    final bleStatus = _ble.status;
    _log('현재 BLE 상태: $bleStatus');
    if (bleStatus == BleStatus.ready) {
      await _startScan();
    } else {
      _log('BLE 미준비 ($bleStatus) - BLE 켜짐 대기 중...');
      _stateSubject.add(BackgroundBleState.scanning);
    }
  }

  /// 블루투스 권한 확인 및 요청
  Future<bool> _checkAndRequestPermissions() async {
    _log('블루투스 권한 확인 중...');

    try {
      // Android 12+ (API 31+) 필수 권한
      final bluetoothScan = await Permission.bluetoothScan.request();
      final bluetoothConnect = await Permission.bluetoothConnect.request();
      final location = await Permission.locationWhenInUse.request();

      _log('권한 상태 - 스캔: $bluetoothScan, 연결: $bluetoothConnect, 위치: $location');

      if (bluetoothScan.isDenied || bluetoothConnect.isDenied) {
        _log('블루투스 권한 거부됨');
        return false;
      }

      if (location.isDenied) {
        _log('위치 권한 거부됨 (BLE 스캔에 필요)');
        return false;
      }

      // Android 13+ (API 33+) 알림 권한 (포그라운드 서비스 필수)
      final notification = await Permission.notification.request();
      _log('알림 권한 상태: $notification');

      // 알림 권한은 거부되어도 서비스 시작은 가능 (알림이 안 보일 수 있음)
      if (notification.isDenied) {
        _log('알림 권한 거부됨 (서비스는 동작하지만 알림이 안 보일 수 있음)');
      }

      _log('필수 권한 승인됨');
      return true;
    } catch (e) {
      _log('권한 요청 중 오류: $e');
      return false;
    }
  }

  /// 서비스 중지
  Future<void> stop() async {
    _log('서비스 중지...');
    _isRunning = false;

    await _stopScan();
    await _disconnectXiaomi();
    await _disconnectOmron();

    _scanRestartTimer?.cancel();
    _scanRestartTimer = null;

    _bondedOmronTimer?.cancel();
    _bondedOmronTimer = null;

    _bondedXiaomiTimer?.cancel();
    _bondedXiaomiTimer = null;

    _omronCooldownTimer?.cancel();
    _omronCooldownTimer = null;
    _omronCooldown = false;
    _omronConnecting = false;

    _weightDisplayTimer?.cancel();
    _weightDisplayTimer = null;
    _bpDisplayTimer?.cancel();
    _bpDisplayTimer = null;

    await _omronConnectAttempt?.cancel();
    _omronConnectAttempt = null;

    await _xiaomiConnectAttempt?.cancel();
    _xiaomiConnectAttempt = null;

    _bleStatusSubscription?.cancel();
    _bleStatusSubscription = null;

    // Android 포그라운드 서비스 중지
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('stopForegroundService');
      } catch (e) {
        _log('포그라운드 서비스 중지 실패: $e');
      }
    }

    _stateSubject.add(BackgroundBleState.stopped);
  }

  /// BLE 스캔 시작
  Future<void> _startScan() async {
    await _stopScan();

    if (!_isRunning) return;

    // BLE 어댑터 상태 확인 (꺼져 있으면 스캔 불가)
    final bleStatus = _ble.status;
    if (bleStatus != BleStatus.ready) {
      _log('BLE 미준비 ($bleStatus) - 스캔 대기');
      _stateSubject.add(BackgroundBleState.scanning);
      // BLE가 꺼져있으면 재시도하지 않음 - _bleStatusSubscription이 켜질 때 자동 시작
      return;
    }

    _stateSubject.add(BackgroundBleState.scanning);

    try {
      // 모든 BLE 기기 스캔 (이름으로 필터링)
      final scanStream = _ble.scanForDevices(
        withServices: [],  // 필터 없음 - 이름으로 구분
        scanMode: ScanMode.lowLatency,
      );

      _scanSubscription = scanStream.listen(
        (device) => _onDeviceDiscovered(device),
        onError: (error) {
          _log('스캔 에러: $error');
          _scheduleRescan();
        },
      );

      // 10초 후 스캔 재시작 (Android 스캔 throttle 방지: 30초 내 5회 제한)
      _scanRestartTimer?.cancel();
      _scanRestartTimer = Timer(const Duration(seconds: 10), () {
        if (_isRunning) {
          _startScan();
        }
      });
    } catch (e) {
      _log('스캔 시작 실패: $e');
      _scheduleRescan();
    }
  }

  /// 스캔 중지
  Future<void> _stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  /// 페어링된 기기들 찾기 (Omron + Xiaomi)
  Future<void> _findBondedDevices() async {
    try {
      final bondedDevices = await _channel.invokeMethod<List>('getBondedDevices');
      if (bondedDevices == null || bondedDevices.isEmpty) {
        _log('페어링된 BLE 기기 없음');
        return;
      }

      _log('페어링된 기기 ${bondedDevices.length}개 발견');

      for (final device in bondedDevices) {
        final name = device['name'] as String? ?? '';
        final address = device['address'] as String? ?? '';

        // Omron 혈압계인지 확인
        if (_isOmronDevice(name) && _bondedOmronAddress == null) {
          _log('★ 페어링된 Omron 발견: $name');
          _bondedOmronAddress = address;
          _bondedOmronName = name;
        }

        // Xiaomi 체중계인지 확인
        if (_isXiaomiScale(name) && _bondedXiaomiAddress == null) {
          _log('★ 페어링된 Xiaomi 체중계 발견: $name');
          _bondedXiaomiAddress = address;
          _bondedXiaomiName = name;
        }
      }

      if (_bondedOmronAddress == null && _bondedXiaomiAddress == null) {
        _log('페어링된 건강 기기 없음 (Omron/Xiaomi)');
      }
    } catch (e) {
      _log('페어링 기기 확인 실패: $e');
    }
  }

  /// 페어링된 Omron에 주기적 연결 시도 시작
  void _startBondedOmronConnectionLoop() {
    _bondedOmronTimer?.cancel();
    _log('');
    _log('═══════════════════════════════════════════════');
    _log('  Omron 혈압계 연결 대기 중');
    _log('═══════════════════════════════════════════════');
    _log('');
    _log('▶ 혈압 측정 방법:');
    _log('  1. 커프를 팔에 감고 START 버튼 누름');
    _log('  2. 측정 완료까지 대기');
    _log('  3. 측정 완료 후 자동으로 데이터 전송됨');
    _log('');
    _log('※ 처음 연결시: Bluetooth 버튼 3초 누름 (P 표시)');
    _log('');

    // 5초마다 연결 시도 (Omron이 전송 모드일 때 연결됨)
    _bondedOmronTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isRunning) {
        timer.cancel();
        return;
      }

      // 이미 Omron 연결 중이면 스킵
      if (_connectedOmronId != null) return;

      // 페어링된 Omron이 없으면 스킵
      if (_bondedOmronAddress == null) return;

      await _tryConnectToBondedOmron();
    });

    // 즉시 첫 시도
    _tryConnectToBondedOmron();
  }

  /// 페어링된 Omron에 연결 시도 (짧은 타임아웃)
  StreamSubscription<ConnectionStateUpdate>? _omronConnectAttempt;
  int _omronConnectAttemptCount = 0;

  Future<void> _tryConnectToBondedOmron() async {
    // 이미 Omron 연결 중이면 스킵
    if (_connectedOmronId != null) return;
    if (_bondedOmronAddress == null) return;
    if (_omronCooldown || _omronConnecting) return;

    // 이전 연결 시도 취소
    await _omronConnectAttempt?.cancel();
    _omronConnectAttempt = null;

    _omronConnectAttemptCount++;
    // 10번마다 한번씩만 로그 (로그 과다 방지)
    if (_omronConnectAttemptCount % 10 == 1) {
      _log('[혈압계] 연결 대기 중... (혈압 측정 후 자동 연결)');
    }

    _omronConnecting = true;

    try {
      final completer = Completer<bool>();
      Timer? timeoutTimer;

      // 짧은 타임아웃으로 연결 시도 (전송 모드가 아니면 빠르게 실패)
      final connectionStream = _ble.connectToDevice(
        id: _bondedOmronAddress!,
        connectionTimeout: const Duration(seconds: 3),
      );

      timeoutTimer = Timer(const Duration(seconds: 4), () {
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      });

      _omronConnectAttempt = connectionStream.listen(
        (update) async {
          if (update.connectionState == DeviceConnectionState.connected) {
            timeoutTimer?.cancel();
            if (!completer.isCompleted) {
              completer.complete(true);
            }

            // 연결 성공!
            _log('★★★ Omron 혈압계 연결 성공! ★★★');
            _bondedOmronTimer?.cancel();
            _connectedOmronId = _bondedOmronAddress;
            _omronConnecting = false;
            _stateSubject.add(BackgroundBleState.connected);

            // 연결 구독을 유지하고 혈압 서비스 구독
            _omronConnectionSubscription = _omronConnectAttempt;
            _omronConnectAttempt = null; // 소유권 이전

            // GATT 안정화 대기
            await Future.delayed(const Duration(milliseconds: 500));
            if (_connectedOmronId != null) {
              await _subscribeToBloodPressure(_bondedOmronAddress!);
            }

          } else if (update.connectionState == DeviceConnectionState.disconnected) {
            timeoutTimer?.cancel();
            if (!completer.isCompleted) {
              completer.complete(false);
            }
            _omronConnecting = false;
            // 연결 후 끊어진 경우
            if (_connectedOmronId != null) {
              _log('[혈압계] 연결 해제됨');
              _onOmronDisconnected();
            }
          }
        },
        onError: (e) {
          timeoutTimer?.cancel();
          _omronConnecting = false;
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          if (_connectedOmronId != null) {
            _log('[혈압계] 연결 에러: $e');
            _onOmronDisconnected();
          }
        },
      );

      // 연결 결과 대기
      final connected = await completer.future;
      if (!connected) {
        _omronConnecting = false;
        await _omronConnectAttempt?.cancel();
        _omronConnectAttempt = null;
      }
    } catch (e) {
      _omronConnecting = false;
      // 연결 실패 - 조용히 무시 (전송 모드가 아닐 때 정상)
    }
  }

  /// 페어링된 Xiaomi에 주기적 연결 시도 시작
  void _startBondedXiaomiConnectionLoop() {
    _bondedXiaomiTimer?.cancel();
    _log('');
    _log('═══════════════════════════════════════════════');
    _log('  Xiaomi 체중계 연결 대기 중');
    _log('═══════════════════════════════════════════════');
    _log('');
    _log('▶ 체중 측정 방법:');
    _log('  1. 체중계 위에 올라감');
    _log('  2. 측정 완료까지 대기 (화면 깜빡임 멈춤)');
    _log('  3. 체중계에서 내려오면 데이터 전송됨');
    _log('');

    // 3초마다 연결 시도 (체중계가 측정 모드일 때 연결됨)
    _bondedXiaomiTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!_isRunning) {
        timer.cancel();
        return;
      }

      // 이미 Xiaomi 연결 중이면 스킵
      if (_connectedXiaomiId != null) return;

      // 페어링된 Xiaomi가 없으면 스킵
      if (_bondedXiaomiAddress == null) return;

      await _tryConnectToBondedXiaomi();
    });

    // 즉시 첫 시도
    _tryConnectToBondedXiaomi();
  }

  /// 페어링된 Xiaomi에 연결 시도 (짧은 타임아웃)
  StreamSubscription<ConnectionStateUpdate>? _xiaomiConnectAttempt;
  int _xiaomiConnectAttemptCount = 0;

  Future<void> _tryConnectToBondedXiaomi() async {
    // 이미 Xiaomi 연결 중이면 스킵
    if (_connectedXiaomiId != null) return;
    if (_bondedXiaomiAddress == null) return;

    // 이전 연결 시도 취소
    await _xiaomiConnectAttempt?.cancel();
    _xiaomiConnectAttempt = null;

    _xiaomiConnectAttemptCount++;
    // 20번마다 한번씩만 로그 (로그 과다 방지)
    if (_xiaomiConnectAttemptCount % 20 == 1) {
      _log('[체중계] 연결 대기 중... (체중계 위에 올라가면 자동 연결)');
    }

    try {
      final completer = Completer<bool>();
      Timer? timeoutTimer;

      // 짧은 타임아웃으로 연결 시도 (측정 모드가 아니면 빠르게 실패)
      final connectionStream = _ble.connectToDevice(
        id: _bondedXiaomiAddress!,
        connectionTimeout: const Duration(seconds: 2),
      );

      timeoutTimer = Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      });

      _xiaomiConnectAttempt = connectionStream.listen(
        (update) async {
          if (update.connectionState == DeviceConnectionState.connected) {
            timeoutTimer?.cancel();
            if (!completer.isCompleted) {
              completer.complete(true);
            }

            // 연결 성공!
            _log('★★★ Xiaomi 체중계 연결 성공! ★★★');
            _bondedXiaomiTimer?.cancel();
            _connectedXiaomiId = _bondedXiaomiAddress;
            _stateSubject.add(BackgroundBleState.connected);

            // 연결 구독을 유지하고 체중 서비스 구독
            _xiaomiConnectionSubscription = _xiaomiConnectAttempt;
            _xiaomiConnectAttempt = null; // 소유권 이전

            // GATT 안정화 대기 (연결 직후 바로 구독하면 실패할 수 있음)
            await Future.delayed(const Duration(milliseconds: 500));
            if (_connectedXiaomiId != null) {
              await _subscribeToWeight(_bondedXiaomiAddress!);
            }

          } else if (update.connectionState == DeviceConnectionState.disconnected) {
            timeoutTimer?.cancel();
            if (!completer.isCompleted) {
              completer.complete(false);
            }
            // 연결 후 끊어진 경우
            if (_connectedXiaomiId != null) {
              _log('[체중계] 연결 해제됨');
              _onXiaomiDisconnected();
            }
          }
        },
        onError: (e) {
          timeoutTimer?.cancel();
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          if (_connectedXiaomiId != null) {
            _log('[체중계] 연결 에러: $e');
            _onXiaomiDisconnected();
          }
        },
      );

      // 연결 결과 대기
      final connected = await completer.future;
      if (!connected) {
        await _xiaomiConnectAttempt?.cancel();
        _xiaomiConnectAttempt = null;
      }
    } catch (e) {
      // 연결 실패 - 조용히 무시 (측정 모드가 아닐 때 정상)
    }
  }

  /// 기기 발견 시 처리
  void _onDeviceDiscovered(DiscoveredDevice device) {
    // 이름 없는 기기는 무시
    if (device.name.isEmpty) return;

    // Xiaomi 체중계 - 광고(advertisement) 데이터에서 직접 체중 읽기
    // MIBFS는 GATT notification이 아닌 BLE advertisement에 체중 데이터를 담아 보냄
    if (_isXiaomiScale(device.name)) {
      _handleXiaomiAdvertisement(device);
      return;
    }

    // Omron 혈압계 (스캔으로 발견된 경우 - 페어링 안 된 기기용)
    if (_isOmronDevice(device.name) && _connectedOmronId == null && _bondedOmronAddress == null) {
      // 쿨다운 중이거나 이미 연결 시도 중이면 무시
      if (_omronCooldown || _omronConnecting) return;
      _log('★★★ Omron 혈압계 발견 (스캔): ${device.name} ★★★');
      _connectToOmron(device.id, device.name);
      return;
    }
  }

  /// Xiaomi 체중계가 마지막으로 발견된 시간 (로그 과다 방지)
  DateTime? _lastXiaomiLogTime;

  /// Xiaomi 광고 데이터에서 체중 읽기
  void _handleXiaomiAdvertisement(DiscoveredDevice device) {
    // serviceData에서 0x181B (Body Composition) 데이터 확인
    final serviceData = device.serviceData;

    // serviceData 키 중 181b 찾기
    List<int>? weightData;
    for (final entry in serviceData.entries) {
      final uuidStr = entry.key.toString().toLowerCase();
      if (uuidStr.contains('181b')) {
        weightData = entry.value;
        break;
      }
    }

    // serviceData에 없으면 manufacturerData 확인 (일부 Xiaomi 모델)
    if (weightData == null || weightData.isEmpty) {
      final mfData = device.manufacturerData;
      // Xiaomi manufacturer ID = 0x0157, 뒤에 체중 데이터가 올 수 있음
      if (mfData.length >= 15 && mfData[0] == 0x57 && mfData[1] == 0x01) {
        weightData = mfData.sublist(2); // manufacturer ID 이후 데이터
      }
    }

    if (weightData == null || weightData.isEmpty) {
      // 데이터 없는 광고 - 10초마다 로그 (디버그)
      final now = DateTime.now();
      if (_lastXiaomiLogTime == null ||
          now.difference(_lastXiaomiLogTime!) > const Duration(seconds: 10)) {
        _lastXiaomiLogTime = now;
        _log('[체중계] MIBFS 광고 수신 (체중 데이터 없음)');
        if (serviceData.isNotEmpty) {
          for (final entry in serviceData.entries) {
            final hexData = entry.value.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ');
            _log('  serviceData[${entry.key.toString().substring(4, 8)}]: $hexData');
          }
        }
        if (device.manufacturerData.isNotEmpty) {
          final hexData = device.manufacturerData.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ');
          _log('  mfData(${device.manufacturerData.length}B): $hexData');
        }
        _log('  RSSI: ${device.rssi}');
      }
      return;
    }

    // flags 확인 (dedup 판단 전에 먼저 확인)
    final flags = weightData.length >= 2 ? weightData[1] : 0;
    final isWeightRemoved = (flags & 0x20) != 0;

    // 중복 광고 체크 (시간 기반 바이패스 포함)
    final now = DateTime.now();
    final timeSinceLastProcess = _lastWeightProcessedAt != null
        ? now.difference(_lastWeightProcessedAt!)
        : const Duration(seconds: 999);

    if (_lastWeightRawData != null &&
        weightData.length == _lastWeightRawData!.length &&
        timeSinceLastProcess < const Duration(seconds: 2)) {
      bool identical = true;
      for (int i = 0; i < weightData.length; i++) {
        if (weightData[i] != _lastWeightRawData![i]) {
          identical = false;
          break;
        }
      }
      if (identical) return; // 2초 이내 동일한 광고 → 무시
    }

    // 원본 바이트 저장 (중복 방지용)
    _lastWeightRawData = List<int>.from(weightData);
    _lastWeightProcessedAt = now;

    // 로그 출력
    final hexStr = weightData.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ');
    if (isWeightRemoved) {
      _log('★★★ Xiaomi 체중계 측정 완료! ★★★');
      _log('[체중계] 최종 데이터: ${weightData.length} bytes');
      _log('Raw: $hexStr');
    } else {
      _log('[체중계] 측정 중: ${weightData.length} bytes (flags=0x${flags.toRadixString(16)})');
    }

    // 모든 데이터를 파싱 (중간값은 UI만 업데이트, 최종값은 UI+Supabase)
    if (weightData.length >= 10) {
      _parseWeightData(weightData, device.id);
    }
  }

  /// Omron 기기인지 확인
  bool _isOmronDevice(String name) {
    final upperName = name.toUpperCase();
    for (final pattern in BleUuids.omronBpNamePatterns) {
      if (upperName.contains(pattern.toUpperCase())) {
        return true;
      }
    }
    return false;
  }

  /// Xiaomi 체중계인지 확인
  bool _isXiaomiScale(String name) {
    final upperName = name.toUpperCase();
    for (final pattern in BleUuids.xiaomiScaleNamePatterns) {
      if (upperName.contains(pattern.toUpperCase())) {
        return true;
      }
    }
    return false;
  }

  /// Xiaomi 체중계 연결
  Future<void> _connectToXiaomi(String deviceId, String deviceName) async {
    if (_connectedXiaomiId != null) return;

    _log('[체중계] 연결 중: $deviceName');
    _connectedXiaomiId = deviceId;

    try {
      _xiaomiConnectionSubscription = _ble
          .connectToDevice(
            id: deviceId,
            connectionTimeout: const Duration(seconds: 10),
          )
          .listen(
        (update) async {
          switch (update.connectionState) {
            case DeviceConnectionState.connecting:
              _log('[체중계] 연결 중...');
              break;
            case DeviceConnectionState.connected:
              _log('[체중계] 연결됨!');
              // GATT 안정화 대기
              await Future.delayed(const Duration(milliseconds: 500));
              if (_connectedXiaomiId != null) {
                await _subscribeToWeight(deviceId);
              }
              break;
            case DeviceConnectionState.disconnecting:
              _log('[체중계] 연결 해제 중...');
              break;
            case DeviceConnectionState.disconnected:
              _log('[체중계] 연결 해제됨');
              _onXiaomiDisconnected();
              break;
          }
        },
        onError: (error) {
          _log('[체중계] 연결 에러: $error');
          _onXiaomiDisconnected();
        },
      );
    } catch (e) {
      _log('[체중계] 연결 실패: $e');
      _onXiaomiDisconnected();
    }
  }

  /// Omron 혈압계 연결
  Future<void> _connectToOmron(String deviceId, String deviceName) async {
    if (_connectedOmronId != null) return;
    if (_omronConnecting) return;

    _omronConnecting = true;
    _log('[혈압계] 연결 중: $deviceName');
    _connectedOmronId = deviceId;
    _bondedOmronTimer?.cancel(); // 연결되면 주기적 시도 중지

    try {
      _omronConnectionSubscription = _ble
          .connectToDevice(
            id: deviceId,
            connectionTimeout: const Duration(seconds: 10),
          )
          .listen(
        (update) async {
          switch (update.connectionState) {
            case DeviceConnectionState.connecting:
              _log('[혈압계] 연결 중...');
              break;
            case DeviceConnectionState.connected:
              _log('[혈압계] 연결됨!');
              _omronConnecting = false;
              // GATT 안정화 대기 (Omron은 연결 직후 서비스 탐색하면 끊어짐)
              await Future.delayed(const Duration(milliseconds: 500));
              // 대기 중 연결이 끊어졌을 수 있으므로 확인
              if (_connectedOmronId != null) {
                await _subscribeToBloodPressure(deviceId);
              }
              break;
            case DeviceConnectionState.disconnecting:
              _log('[혈압계] 연결 해제 중...');
              break;
            case DeviceConnectionState.disconnected:
              _log('[혈압계] 연결 해제됨');
              _omronConnecting = false;
              _onOmronDisconnected();
              break;
          }
        },
        onError: (error) {
          _log('[혈압계] 연결 에러: $error');
          _omronConnecting = false;
          _onOmronDisconnected();
        },
      );
    } catch (e) {
      _log('[혈압계] 연결 실패: $e');
      _omronConnecting = false;
      _onOmronDisconnected();
    }
  }

  /// Blood Pressure Measurement 구독 (Omron)
  Future<void> _subscribeToBloodPressure(String deviceId) async {
    _stateSubject.add(BackgroundBleState.receiving);

    try {
      // 1. 서비스 탐색 (로깅 최소화하여 빠르게 진행)
      _log('[혈압계] 서비스 탐색 중...');
      await _ble.discoverAllServices(deviceId);
      final services = await _ble.getDiscoveredServices(deviceId);

      _log('[혈압계] 발견된 서비스 수: ${services.length}');

      // 2. Blood Pressure Service 확인
      final bpService = services.where(
        (s) => s.id == BleUuids.bloodPressureService
      ).toList();

      if (bpService.isEmpty) {
        _log('[혈압계] Blood Pressure Service (0x1810) 없음');
        // 서비스 목록을 디버그용으로 출력
        for (final service in services) {
          _log('  서비스: ${service.id}');
        }
        _onOmronDisconnected();
        return;
      }

      _log('[혈압계] √ Blood Pressure Service 발견');

      // 3. 서비스 탐색 후 잠시 대기 (GATT 테이블 안정화)
      await Future.delayed(const Duration(milliseconds: 300));

      // 대기 중 연결이 끊어졌으면 중단
      if (_connectedOmronId == null) return;

      // 4. Blood Pressure Measurement 특성 구독 (Indication 사용)
      final bpChar = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: BleUuids.bloodPressureService,
        characteristicId: BleUuids.bloodPressureMeasurement,
      );

      _omronNotificationSubscription = _ble.subscribeToCharacteristic(bpChar).listen(
        (data) {
          _log('혈압 데이터 수신: ${data.length} bytes');
          _parseBloodPressureData(data, deviceId);
        },
        onError: (error) {
          _log('[혈압계] Indication 에러: $error');
        },
      );

      _log('[혈압계] √ Blood Pressure Measurement 구독 완료');
      _log('[혈압계] 데이터 대기 중... (지금 혈압 측정하세요!)');
    } catch (e) {
      _log('[혈압계] 구독 실패: $e');
      _onOmronDisconnected();
    }
  }

  /// 샤오미 전용 서비스 구독
  StreamSubscription<List<int>>? _xiaomiCustomSubscription;

  /// Body Composition 구독 (Xiaomi)
  Future<void> _subscribeToWeight(String deviceId) async {
    _stateSubject.add(BackgroundBleState.receiving);

    try {
      // 1. 연결 우선순위 높이기 + MTU 요청
      try {
        await _ble.requestConnectionPriority(
          deviceId: deviceId,
          priority: ConnectionPriority.highPerformance,
        );
      } catch (e) {
        _log('[체중계] 연결 우선순위 설정 실패 (무시): $e');
      }

      // 2. 서비스 디스커버리
      _log('[체중계] 서비스 탐색 중...');
      await _ble.discoverAllServices(deviceId);
      final services = await _ble.getDiscoveredServices(deviceId);
      _log('[체중계] 발견된 서비스 수: ${services.length}');
      for (final service in services) {
        final chars = service.characteristics.map((c) => c.id.toString().substring(4, 8)).join(', ');
        _log('  서비스 ${service.id.toString().substring(4, 8)}: [$chars]');
      }

      await Future.delayed(const Duration(milliseconds: 300));

      // 디스커버리 중 연결이 끊어졌으면 중단
      if (_connectedXiaomiId == null) return;

      // 2. 표준 Body Composition Service 구독
      final weightChar = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: BleUuids.bodyCompositionService,
        characteristicId: BleUuids.bodyCompositionMeasurement,
      );

      try {
        _xiaomiNotificationSubscription = _ble.subscribeToCharacteristic(weightChar).listen(
          (data) {
            _log('[체중계] 표준 서비스 데이터: ${data.length} bytes');
            _parseWeightData(data, deviceId);
          },
          onError: (error) {
            _log('[체중계] 표준 서비스 스트림 에러: $error');
          },
        );
        _log('[체중계] √ 표준 서비스(181B) 구독 완료');
      } catch (e) {
        _log('[체중계] ✗ 표준 서비스(181B) 구독 실패: $e');
      }

      // 3. 샤오미 전용 서비스도 구독 시도 (더 자세한 데이터 포함 가능)
      try {
        final customChar = QualifiedCharacteristic(
          deviceId: deviceId,
          serviceId: BleUuids.xiaomiCustomService,
          characteristicId: BleUuids.xiaomiCustomCharacteristic,
        );

        _xiaomiCustomSubscription = _ble.subscribeToCharacteristic(customChar).listen(
          (data) {
            _log('[체중계] 전용 서비스 데이터: ${data.length} bytes');
            _log('Custom Raw: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}');
            // 전용 서비스 데이터도 같은 파서로 처리 시도
            if (data.length >= 13) {
              _parseWeightData(data, deviceId);
            }
          },
          onError: (error) {
            _log('[체중계] 전용 서비스 에러 (무시): $error');
          },
        );
        _log('[체중계] √ 전용 서비스 구독 완료');
      } catch (e) {
        _log('[체중계] 전용 서비스 없음 (정상)');
      }

      _log('[체중계] 데이터 대기 중...');
    } catch (e) {
      _log('[체중계] 구독 실패: $e');
      _onXiaomiDisconnected();
    }
  }

  /// 혈압 데이터 파싱 (IEEE 11073-20601)
  void _parseBloodPressureData(List<int> data, String deviceId) {
    if (data.isEmpty) return;

    _log('Raw BP: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}');

    try {
      final flags = data[0];
      final isKPa = (flags & 0x01) != 0;
      final hasTimestamp = (flags & 0x02) != 0;
      final hasPulseRate = (flags & 0x04) != 0;

      int offset = 1;

      final systolicRaw = _parseSFloat(data, offset);
      offset += 2;

      final diastolicRaw = _parseSFloat(data, offset);
      offset += 2;

      // Mean Arterial Pressure 건너뜀
      offset += 2;

      final systolic = isKPa ? (systolicRaw * 7.50062).round() : systolicRaw.round();
      final diastolic = isKPa ? (diastolicRaw * 7.50062).round() : diastolicRaw.round();

      if (hasTimestamp) {
        offset += 7;
      }

      int? pulse;
      if (hasPulseRate && offset + 2 <= data.length) {
        pulse = _parseSFloat(data, offset).round();
      }

      if (systolic < 50 || systolic > 250 || diastolic < 30 || diastolic > 150) {
        _log('비정상 혈압 값 - 무시됨');
        return;
      }

      // 중복 전송 방지: 30초 이내 동일 혈압이면 무시
      final now = DateTime.now();
      if (_lastBpSentAt != null &&
          _lastBpSentSystolic == systolic &&
          _lastBpSentDiastolic == diastolic &&
          now.difference(_lastBpSentAt!) < _bpDeduplicateWindow) {
        _log('[혈압계] 중복 데이터 무시 ($systolic/$diastolic)');
        return;
      }

      final reading = BloodPressureReading(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        systolic: systolic,
        diastolic: diastolic,
        pulse: pulse,
        deviceId: deviceId,
      );

      _log('');
      _log('═══ 혈압: ${reading.systolic}/${reading.diastolic} mmHg ═══');
      if (pulse != null) {
        _log('    맥박: $pulse bpm');
      }
      _log('');

      _bpSubject.add(reading);
      _lastBpSentAt = now;
      _lastBpSentSystolic = systolic;
      _lastBpSentDiastolic = diastolic;

      // 60초 후 스탠드바이 모드로 전환
      _bpDisplayTimer?.cancel();
      _bpDisplayTimer = Timer(_displayDuration, () {
        _bpSubject.add(null);
        _log('[혈압계] 표시 시간 종료 → 스탠드바이');
      });

      _sendToSupabase('bp', reading);

    } catch (e) {
      _log('혈압 파싱 에러: $e');
    }
  }

  /// 체중 데이터 파싱 (Xiaomi Mi Body Composition Scale 2)
  /// 데이터 포맷 (13 bytes):
  /// [0]: 0x02 (패킷 타입)
  /// [1]: 플래그 - Bit 5(0x20): 체중 안정화/내려감, Bit 7(0x80): 임피던스 측정 완료
  /// [2-3]: 연도 (little endian)
  /// [4]: 월, [5]: 일, [6]: 시, [7]: 분, [8]: 초
  /// [9-10]: 임피던스 (little endian, 0xFFxx = 무효)
  /// [11-12]: 체중 (little endian, 0.005 kg 단위)
  void _parseWeightData(List<int> data, String deviceId) {
    if (data.length < 10) {
      _log('체중 데이터 길이 부족: ${data.length}');
      return;
    }

    try {
      // 데이터 형식 자동 감지
      // 13바이트: [ctrl1][ctrl2][year_lo][year_hi][mon][day][hr][min][sec][imp_lo][imp_hi][wt_lo][wt_hi]
      final flags = data[1];
      final isWeightRemoved = (flags & 0x20) != 0;
      final hasImpedanceFlag = (flags & 0x80) != 0;

      // 체중 위치: 마지막 2바이트 또는 bytes 11-12
      int weightIdx = data.length >= 13 ? 11 : data.length - 2;
      final weightRaw = data[weightIdx] | (data[weightIdx + 1] << 8);
      final weight = weightRaw * 0.005;

      if (weight < 5.0) return;

      // 임피던스 파싱 (bytes 9-10, 13바이트 형식에서만)
      int? impedance;
      if (data.length >= 13) {
        final impRaw = data[9] | (data[10] << 8);
        if (impRaw > 0 && impRaw < 0xFF00) {
          impedance = impRaw;
        }
      }

      if (isWeightRemoved) {
        // ═══ 최종 측정값 (체중계에서 내려감) ═══

        // 이미 이 세션의 최종 측정을 처리했으면 무시
        // (내려오는 순간의 7kg 같은 아티팩트 + 임피던스 변동 반복 방지)
        if (_finalMeasurementDone) {
          return;
        }

        final roundedWeight = double.parse(weight.toStringAsFixed(1));
        _finalMeasurementDone = true;  // 다시 올라갈 때(중간값 수신) 리셋됨

        var measurement = BodyComposition(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          weight: roundedWeight,
          impedance: impedance,
          isStabilized: true,
          isWeightRemoved: true,
          deviceId: deviceId,
        );

        measurement = measurement.calculateBodyComposition(
          age: _userAge,
          height: _userHeight,
          isMale: _userIsMale,
        );

        _log('');
        _log('═══ 체중: ${measurement.weight} kg ═══');
        if (impedance != null) {
          _log('    [BIA 기반 - 임피던스: $impedance Ω]');
        } else {
          _log('    [BMI 기반 추정]');
        }
        if (measurement.bodyFatPercentage != null) {
          _log('    BMI: ${measurement.bmi}, 체지방: ${measurement.bodyFatPercentage}%');
          _log('    근육량: ${measurement.muscleMass}kg, 체수분: ${measurement.waterPercentage}%');
        }
        _log('');

        _weightSubject.add(measurement);

        // 20초 후 스탠드바이 모드로 전환
        _weightDisplayTimer?.cancel();
        _weightDisplayTimer = Timer(_displayDuration, () {
          _weightSubject.add(null);
          _log('[체중계] 표시 시간 종료 → 스탠드바이');
        });

        _sendToSupabase('weight', measurement);
      } else {
        // ═══ 중간 측정값 (체중계 위에 있음) → UI 업데이트 + 측정 세션 시작 ═══
        _finalMeasurementDone = false;  // 새 측정 세션 시작 → 최종값 수신 허용

        final measuringWeight = double.parse(weight.toStringAsFixed(1));
        final measurement = BodyComposition(
          id: 'measuring',
          timestamp: DateTime.now(),
          weight: measuringWeight,
          impedance: null,
          isStabilized: false,
          isWeightRemoved: false,
          deviceId: deviceId,
        );

        _weightSubject.add(measurement);

        // 표시 타이머 리셋 (측정 중에는 표시 유지)
        _weightDisplayTimer?.cancel();
        _weightDisplayTimer = Timer(const Duration(seconds: 30), () {
          _weightSubject.add(null);
          _log('[체중계] 측정 시간 초과 → 스탠드바이');
        });
      }
    } catch (e) {
      _log('체중 파싱 에러: $e');
    }
  }

  /// SFLOAT (16-bit) 파싱
  double _parseSFloat(List<int> data, int offset) {
    if (offset + 2 > data.length) return 0;

    final raw = data[offset] | (data[offset + 1] << 8);

    int mantissa = raw & 0x0FFF;
    int exponent = (raw >> 12) & 0x0F;

    if (mantissa >= 0x0800) {
      mantissa = mantissa - 0x1000;
    }

    if (exponent >= 0x08) {
      exponent = exponent - 0x10;
    }

    return mantissa * _pow10(exponent);
  }

  double _pow10(int exp) {
    if (exp == 0) return 1;
    if (exp > 0) {
      double result = 1;
      for (int i = 0; i < exp; i++) {
        result *= 10;
      }
      return result;
    } else {
      double result = 1;
      for (int i = 0; i < -exp; i++) {
        result /= 10;
      }
      return result;
    }
  }

  /// Supabase 업로드 상태 스트림 (UI 표시용)
  final _uploadStatusSubject = BehaviorSubject<String>.seeded('');
  Stream<String> get uploadStatusStream => _uploadStatusSubject.stream;
  String get lastUploadStatus => _uploadStatusSubject.value;

  /// Supabase로 데이터 전송
  Future<void> _sendToSupabase(String type, dynamic data) async {
    final initialized = SupabaseMeasurementService.instance.isInitialized;
    _log('Supabase 전송 중... ($type) [초기화=$initialized]');
    _uploadStatusSubject.add('전송 중... ($type)');

    if (!initialized) {
      _log('Supabase 미초기화! 전송 불가');
      _uploadStatusSubject.add('❌ Supabase 미초기화');
      return;
    }

    try {
      bool success = false;

      if (type == 'bp' && data is BloodPressureReading) {
        success = await SupabaseMeasurementService.instance
            .saveBloodPressure(data);
      } else if (type == 'weight' && data is BodyComposition) {
        success = await SupabaseMeasurementService.instance
            .saveBodyComposition(data);
      }

      if (success) {
        _log('Supabase 전송 완료 ($type)');
        _uploadStatusSubject.add('✅ $type 전송 완료');
      } else {
        final err = SupabaseMeasurementService.instance.lastError ?? '알 수 없음';
        _log('Supabase 전송 실패 ($type): $err');
        _uploadStatusSubject.add('❌ $err');
      }
    } catch (e) {
      _log('Supabase 전송 에러 ($type): $e');
      _uploadStatusSubject.add('❌ $e');
    }
  }

  /// Xiaomi 연결 해제
  /// 항상 구독을 cancel하여 flutter_reactive_ble 내부 상태를 깨끗이 정리
  /// (RxJava 글로벌 에러 핸들러가 이미 끊어진 기기의 CCCD 에러를 처리함)
  Future<void> _disconnectXiaomi() async {
    try {
      await _xiaomiNotificationSubscription?.cancel();
    } catch (e) {
      _log('[체중계] notification 구독 해제 에러 (무시): $e');
    }
    _xiaomiNotificationSubscription = null;

    try {
      await _xiaomiCustomSubscription?.cancel();
    } catch (e) {
      _log('[체중계] custom 구독 해제 에러 (무시): $e');
    }
    _xiaomiCustomSubscription = null;

    await _xiaomiConnectionSubscription?.cancel();
    _xiaomiConnectionSubscription = null;

    _connectedXiaomiId = null;
  }

  /// Omron 연결 해제
  Future<void> _disconnectOmron() async {
    try {
      await _omronNotificationSubscription?.cancel();
    } catch (e) {
      _log('[혈압계] notification 구독 해제 에러 (무시): $e');
    }
    _omronNotificationSubscription = null;

    await _omronConnectionSubscription?.cancel();
    _omronConnectionSubscription = null;

    _connectedOmronId = null;
  }

  /// Xiaomi 연결 해제 후 처리
  void _onXiaomiDisconnected() {
    _disconnectXiaomi();
    _xiaomiConnectAttemptCount = 0;
    _log('[체중계] 연결 해제 - 다음 측정 시 자동 재연결');

    // 페어링된 Xiaomi가 있으면 bonded 연결 루프 재시작
    if (_isRunning && _bondedXiaomiAddress != null) {
      _startBondedXiaomiConnectionLoop();
    }
  }

  /// Omron 연결 해제 후 처리
  void _onOmronDisconnected() {
    _disconnectOmron();
    _omronConnectAttemptCount = 0; // 카운트 리셋
    _omronConnecting = false;

    // 쿨다운 시작 (3초 동안 재연결 차단)
    _omronCooldown = true;
    _omronCooldownTimer?.cancel();
    _omronCooldownTimer = Timer(const Duration(seconds: 3), () {
      _omronCooldown = false;
      // 쿨다운 종료 후 페어링된 Omron이면 주기적 연결 시도 재시작
      if (_isRunning && _bondedOmronAddress != null) {
        _startBondedOmronConnectionLoop();
      }
    });
  }

  /// 스캔 재시작 예약
  void _scheduleRescan() {
    _scanRestartTimer?.cancel();
    _scanRestartTimer = Timer(const Duration(seconds: 3), () {
      if (_isRunning) {
        _startScan();
      }
    });
  }

  /// 로그 출력
  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] $message';
    print('>>> BLE: $logMessage');
    _logSubject.add(logMessage);
  }

  /// 리소스 해제
  Future<void> dispose() async {
    await stop();
    await _bleStatusSubscription?.cancel();
    _bleStatusSubscription = null;
    await _stateSubject.close();
    await _bpSubject.close();
    await _weightSubject.close();
    await _logSubject.close();
  }
}
