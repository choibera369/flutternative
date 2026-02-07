import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_strings.dart';
import '../../services/background_ble_service.dart';
import '../../services/supabase_service.dart';
import 'background_service_screen.dart';

/// 홈 화면 - 체중 + 혈압 측정 결과 표시
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const BackgroundServiceScreen(),
                ),
              );
            },
            icon: const Icon(Icons.settings),
            tooltip: 'Ajustes',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 스탠드바이 리셋 버튼
            _StandbyButton(),

            const SizedBox(height: 16),

            // 체중 측정 결과
            _WeightDisplay(),

            const SizedBox(height: 16),

            // 혈압 측정 결과
            _BloodPressureDisplay(),

            const SizedBox(height: 24),

            // Supabase 업로드 상태
            _SupabaseStatusBar(),

            const SizedBox(height: 16),

            // 서비스 상태 표시 + 재시작 버튼
            _ServiceStatusBar(),

            const SizedBox(height: 16),

            // BLE 연결 로그 (최근)
            _BleLogDisplay(),
          ],
        ),
      ),
    );
  }
}

/// 스탠드바이 리셋 버튼 (완전 초기화)
class _StandbyButton extends StatefulWidget {
  @override
  State<_StandbyButton> createState() => _StandbyButtonState();
}

class _StandbyButtonState extends State<_StandbyButton> {
  bool _resetting = false;

  Future<void> _handleReset() async {
    if (_resetting) return;
    setState(() => _resetting = true);
    await BackgroundBleService.instance.resetToStandby();
    if (mounted) setState(() => _resetting = false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _resetting ? null : _handleReset,
        icon: _resetting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const Icon(Icons.restart_alt, size: 22),
        label: Text(
          _resetting ? 'Reiniciando...' : 'Standby',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _resetting ? Colors.grey : Colors.blueGrey,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// 체성분 분석 결과 표시 (몸무게 숫자 없음 - Supabase에만 저장)
class _WeightDisplay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder(
      stream: BackgroundBleService.instance.weightStream,
      builder: (context, snapshot) {
        final weight = snapshot.data;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // 아이콘 & 라벨
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.analytics, color: Colors.blue, size: 28),
                    const SizedBox(width: 8),
                    Text(
                      'Composición corporal',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                if (weight != null && weight.hasBodyComposition) ...[
                  // 측정 시각
                  Text(
                    _formatDateTime(weight.timestamp),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 10개 체성분 항목 - 2열 그리드
                  // 1행: BMI + 체지방률
                  Row(
                    children: [
                      if (weight.bmi != null)
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.speed,
                            label: 'IMC',
                            value: weight.bmi!.toStringAsFixed(1),
                            color: _getBmiColor(weight.bmi!),
                          ),
                        ),
                      const SizedBox(width: 10),
                      if (weight.bodyFatPercentage != null)
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.opacity,
                            label: 'Grasa corporal',
                            value: '${weight.bodyFatPercentage!.toStringAsFixed(1)}%',
                            color: Colors.orange,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // 2행: 근육량 + 체수분
                  Row(
                    children: [
                      if (weight.muscleMass != null)
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.fitness_center,
                            label: 'Masa muscular',
                            value: '${weight.muscleMass!.toStringAsFixed(1)} kg',
                            color: Colors.red,
                          ),
                        ),
                      const SizedBox(width: 10),
                      if (weight.waterPercentage != null)
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.water_drop,
                            label: 'Agua corporal',
                            value: '${weight.waterPercentage!.toStringAsFixed(1)}%',
                            color: Colors.cyan,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // 3행: 골격량 + 내장지방
                  Row(
                    children: [
                      if (weight.boneMass != null)
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.accessibility_new,
                            label: 'Masa ósea',
                            value: '${weight.boneMass!.toStringAsFixed(2)} kg',
                            color: Colors.brown,
                          ),
                        ),
                      const SizedBox(width: 10),
                      if (weight.visceralFat != null)
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.shield,
                            label: 'Grasa visceral',
                            value: '${weight.visceralFat}',
                            color: Colors.deepOrange,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // 4행: 기초대사량 + 대사연령
                  Row(
                    children: [
                      if (weight.basalMetabolism != null)
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.local_fire_department,
                            label: 'Metabolismo basal',
                            value: '${weight.basalMetabolism} kcal',
                            color: Colors.amber,
                          ),
                        ),
                      const SizedBox(width: 10),
                      if (weight.metabolicAge != null)
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.cake,
                            label: 'Edad metabólica',
                            value: '${weight.metabolicAge} años',
                            color: Colors.purple,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // 5행: 단백질 + 임피던스
                  Row(
                    children: [
                      if (weight.proteinPercentage != null)
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.egg,
                            label: 'Proteína',
                            value: '${weight.proteinPercentage!.toStringAsFixed(1)}%',
                            color: Colors.green,
                          ),
                        ),
                      const SizedBox(width: 10),
                      if (weight.impedance != null)
                        Expanded(
                          child: _MetricTile(
                            icon: Icons.electric_bolt,
                            label: 'Impedancia',
                            value: '${weight.impedance} Ω',
                            color: Colors.teal,
                          ),
                        )
                      else
                        const Expanded(child: SizedBox()),
                    ],
                  ),
                ] else if (weight != null && !weight.isWeightRemoved) ...[
                  // 측정 중 (체중계 위에 올라가 있음)
                  const SizedBox(height: 20),
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation(Colors.blue),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Midiendo...',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'No se baje de la báscula',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                ] else ...[
                  // 대기 상태
                  const SizedBox(height: 20),
                  Icon(
                    Icons.monitor_weight_outlined,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sin medición',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Suba a la báscula para analizar',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getBmiColor(double bmi) {
    if (bmi < 18.5) return Colors.blue;
    if (bmi < 25.0) return Colors.green;
    if (bmi < 30.0) return Colors.orange;
    return Colors.red;
  }

  String _formatDateTime(DateTime time) {
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// 체성분 항목 타일 (아이콘 + 라벨 + 큰 값)
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 혈압 측정 결과 표시
class _BloodPressureDisplay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder(
      stream: BackgroundBleService.instance.measurementStream,
      builder: (context, snapshot) {
        final bp = snapshot.data;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // 아이콘 & 라벨
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.favorite, color: Colors.red, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Presión arterial',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 측정값 표시
                if (bp != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${bp.systolic}',
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const Text(
                        '/',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w300,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        '${bp.diastolic}',
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'mmHg',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),

                  // 맥박
                  if (bp.pulse != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timeline, color: Colors.orange, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '${bp.pulse}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'bpm',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 8),
                  Text(
                    _formatDateTime(bp.timestamp),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  const Text(
                    '---/---',
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sin medición',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDateTime(DateTime time) {
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// Supabase 업로드 상태 바
class _SupabaseStatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: BackgroundBleService.instance.uploadStatusStream,
      builder: (context, snapshot) {
        final status = snapshot.data ?? '';
        final isInit = SupabaseMeasurementService.instance.isInitialized;

        if (status.isEmpty && isInit) return const SizedBox.shrink();

        final Color color;
        if (!isInit) {
          color = Colors.red;
        } else if (status.contains('✅')) {
          color = Colors.green;
        } else if (status.contains('❌')) {
          color = Colors.red;
        } else {
          color = Colors.blue;
        }

        final displayText = !isInit
            ? 'Supabase no inicializado ❌'
            : status.isEmpty
                ? 'Supabase conectado'
                : status;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_upload, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                displayText,
                style: TextStyle(color: color, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 서비스 상태 바 (재시작 버튼 포함)
class _ServiceStatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BackgroundBleState>(
      stream: BackgroundBleService.instance.stateStream,
      builder: (context, snapshot) {
        final state = snapshot.data ?? BackgroundBleState.stopped;

        Color color;
        String text;
        IconData icon;

        switch (state) {
          case BackgroundBleState.stopped:
            color = Colors.grey;
            text = 'Servicio detenido';
            icon = Icons.stop_circle_outlined;
            break;
          case BackgroundBleState.scanning:
            color = Colors.blue;
            text = 'Buscando dispositivos...';
            icon = Icons.bluetooth_searching;
            break;
          case BackgroundBleState.connecting:
            color = Colors.orange;
            text = 'Conectando...';
            icon = Icons.bluetooth_connected;
            break;
          case BackgroundBleState.connected:
          case BackgroundBleState.receiving:
            color = Colors.green;
            text = 'Conectado';
            icon = Icons.check_circle;
            break;
          case BackgroundBleState.error:
            color = Colors.red;
            text = 'Error';
            icon = Icons.error_outline;
            break;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (state == BackgroundBleState.scanning ||
                  state == BackgroundBleState.connecting) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
              // 재시작 버튼
              const SizedBox(width: 8),
              InkWell(
                onTap: () async {
                  await BackgroundBleService.instance.stop();
                  await Future.delayed(const Duration(seconds: 1));
                  await BackgroundBleService.instance.start();
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.refresh, color: color, size: 22),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// BLE 연결 로그 표시 (디버그용)
class _BleLogDisplay extends StatefulWidget {
  @override
  State<_BleLogDisplay> createState() => _BleLogDisplayState();
}

class _BleLogDisplayState extends State<_BleLogDisplay> {
  final List<String> _logs = [];
  StreamSubscription<String>? _logSub;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _logSub = BackgroundBleService.instance.logStream.listen((log) {
      if (log.isEmpty) return;
      setState(() {
        _logs.add(log);
        if (_logs.length > 50) _logs.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.terminal, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Log BLE',
                    style: theme.textTheme.titleSmall,
                  ),
                  const Spacer(),
                  Text(
                    '${_logs.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            SizedBox(
              height: 200,
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(8),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[_logs.length - 1 - index];
                  final isError = log.contains('error') || log.contains('fallo') || log.contains('Error') || log.contains('denegado');
                  final isSuccess = log.contains('★') || log.contains('completado') || log.contains('éxito') || log.contains('conectado');
                  return Text(
                    log,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: isError
                          ? Colors.red
                          : isSuccess
                              ? Colors.green
                              : theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
