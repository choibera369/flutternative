import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/korean_strings.dart';
import '../providers/ble_providers.dart';

/// 기기 검색 화면
class DeviceScanScreen extends ConsumerStatefulWidget {
  const DeviceScanScreen({super.key});

  @override
  ConsumerState<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends ConsumerState<DeviceScanScreen> {
  @override
  void initState() {
    super.initState();
    // 화면 진입 시 자동 스캔 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scanControllerProvider.notifier).startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isScanning = ref.watch(isScanningProvider).valueOrNull ?? false;
    final devices = ref.watch(discoveredDevicesProvider).valueOrNull ?? [];
    final scanState = ref.watch(scanControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(KoreanStrings.screenScanTitle),
        actions: [
          if (isScanning)
            IconButton(
              onPressed: () {
                ref.read(scanControllerProvider.notifier).stopScan();
              },
              icon: const Icon(Icons.stop),
              tooltip: KoreanStrings.stopScan,
            ),
        ],
      ),
      body: Column(
        children: [
          // 스캔 상태 표시
          if (isScanning)
            const LinearProgressIndicator()
          else if (scanState.hasError)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getErrorMessage(scanState.error),
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ref.read(scanControllerProvider.notifier).startScan();
                    },
                    child: const Text(KoreanStrings.actionRetry),
                  ),
                ],
              ),
            ),

          // 기기 목록
          Expanded(
            child: devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isScanning
                              ? Icons.bluetooth_searching
                              : Icons.bluetooth_disabled,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isScanning
                              ? KoreanStrings.deviceSearching
                              : KoreanStrings.emptySearchResults,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return _DeviceListTile(
                        device: device,
                        onTap: () => _connectToDevice(device),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: !isScanning
          ? FloatingActionButton.extended(
              onPressed: () {
                ref.read(scanControllerProvider.notifier).startScan();
              },
              icon: const Icon(Icons.refresh),
              label: const Text(KoreanStrings.scanForDevices),
            )
          : null,
    );
  }

  String _getErrorMessage(Object? error) {
    if (error == null) return KoreanStrings.errorUnknown;
    return error.toString();
  }

  Future<void> _connectToDevice(ScannedDevice device) async {
    // 스캔 중지
    await ref.read(scanControllerProvider.notifier).stopScan();

    if (!mounted) return;

    // 연결 중 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text('${device.name} 연결 중...'),
          ],
        ),
      ),
    );

    // 기기 유형에 따라 연결
    try {
      switch (device.deviceType) {
        case DeviceType.xiaomiScale:
          await ref
              .read(scaleConnectionProvider.notifier)
              .connect(device.id);
          break;
        case DeviceType.ihealthBloodPressure:
          await ref
              .read(bpConnectionProvider.notifier)
              .connect(device.id);
          break;
        case DeviceType.ihealthGlucose:
          await ref
              .read(glucoseConnectionProvider.notifier)
              .connect(device.id);
          break;
        case DeviceType.unknown:
          // 다이얼로그 닫기
          if (mounted) Navigator.of(context).pop();
          _showDeviceTypeDialog(device);
          return;
      }

      if (mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
        Navigator.of(context).pop(device); // 스캔 화면 닫기
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('연결 실패: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showDeviceTypeDialog(ScannedDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기기 유형 선택'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${device.name}의 유형을 선택하세요.'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.monitor_weight_outlined),
              title: const Text(KoreanStrings.deviceScale),
              onTap: () {
                Navigator.pop(context);
                _connectAsDeviceType(device, DeviceType.xiaomiScale);
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_outline),
              title: const Text(KoreanStrings.deviceBloodPressure),
              onTap: () {
                Navigator.pop(context);
                _connectAsDeviceType(device, DeviceType.ihealthBloodPressure);
              },
            ),
            ListTile(
              leading: const Icon(Icons.water_drop_outlined),
              title: const Text(KoreanStrings.deviceGlucose),
              onTap: () {
                Navigator.pop(context);
                _connectAsDeviceType(device, DeviceType.ihealthGlucose);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(KoreanStrings.actionCancel),
          ),
        ],
      ),
    );
  }

  Future<void> _connectAsDeviceType(
    ScannedDevice device,
    DeviceType type,
  ) async {
    // 연결 중 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text('${device.name} 연결 중...'),
          ],
        ),
      ),
    );

    try {
      switch (type) {
        case DeviceType.xiaomiScale:
          await ref
              .read(scaleConnectionProvider.notifier)
              .connect(device.id);
          break;
        case DeviceType.ihealthBloodPressure:
          await ref
              .read(bpConnectionProvider.notifier)
              .connect(device.id);
          break;
        case DeviceType.ihealthGlucose:
          await ref
              .read(glucoseConnectionProvider.notifier)
              .connect(device.id);
          break;
        case DeviceType.unknown:
          if (mounted) Navigator.of(context).pop();
          return;
      }

      if (mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
        Navigator.of(context).pop(device); // 스캔 화면 닫기
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('연결 실패: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

/// 기기 목록 타일
class _DeviceListTile extends StatelessWidget {
  const _DeviceListTile({
    required this.device,
    required this.onTap,
  });

  final ScannedDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getDeviceColor(device.deviceType).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getDeviceIcon(device.deviceType),
            color: _getDeviceColor(device.deviceType),
          ),
        ),
        title: Text(
          device.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Row(
          children: [
            Text(
              _getDeviceTypeName(device.deviceType),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: 8),
            _SignalStrengthIndicator(strength: device.signalStrength),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  IconData _getDeviceIcon(DeviceType type) {
    switch (type) {
      case DeviceType.xiaomiScale:
        return Icons.monitor_weight_outlined;
      case DeviceType.ihealthBloodPressure:
        return Icons.favorite_outline;
      case DeviceType.ihealthGlucose:
        return Icons.water_drop_outlined;
      case DeviceType.unknown:
        return Icons.bluetooth;
    }
  }

  Color _getDeviceColor(DeviceType type) {
    switch (type) {
      case DeviceType.xiaomiScale:
        return Colors.blue;
      case DeviceType.ihealthBloodPressure:
        return Colors.red;
      case DeviceType.ihealthGlucose:
        return Colors.purple;
      case DeviceType.unknown:
        return Colors.grey;
    }
  }

  String _getDeviceTypeName(DeviceType type) {
    switch (type) {
      case DeviceType.xiaomiScale:
        return KoreanStrings.deviceXiaomiScale;
      case DeviceType.ihealthBloodPressure:
        return KoreanStrings.deviceIHealthBP;
      case DeviceType.ihealthGlucose:
        return KoreanStrings.deviceIHealthGlucose;
      case DeviceType.unknown:
        return '알 수 없는 기기';
    }
  }
}

/// 신호 강도 표시기
class _SignalStrengthIndicator extends StatelessWidget {
  const _SignalStrengthIndicator({required this.strength});

  final int strength;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        final isActive = index < strength;
        return Container(
          width: 4,
          height: 8 + (index * 3).toDouble(),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: isActive
                ? _getStrengthColor(strength)
                : Colors.grey.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Color _getStrengthColor(int strength) {
    if (strength >= 3) return Colors.green;
    if (strength >= 2) return Colors.orange;
    return Colors.red;
  }
}
