import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/background_ble_service.dart';

/// 백그라운드 서비스 상태 Provider
final backgroundBleStateProvider = StreamProvider<BackgroundBleState>((ref) {
  return BackgroundBleService.instance.stateStream;
});

/// 백그라운드 서비스 로그 Provider
final backgroundBleLogProvider = StreamProvider<String>((ref) {
  return BackgroundBleService.instance.logStream;
});

/// 백그라운드 서비스 최신 측정값 Provider
final backgroundMeasurementProvider = StreamProvider((ref) {
  return BackgroundBleService.instance.measurementStream;
});

/// 백그라운드 서비스 제어 화면
class BackgroundServiceScreen extends ConsumerStatefulWidget {
  const BackgroundServiceScreen({super.key});

  @override
  ConsumerState<BackgroundServiceScreen> createState() =>
      _BackgroundServiceScreenState();
}

class _BackgroundServiceScreenState
    extends ConsumerState<BackgroundServiceScreen> {
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 로그 스트림 구독
    BackgroundBleService.instance.logStream.listen((log) {
      if (mounted && log.isNotEmpty) {
        setState(() {
          _logs.add(log);
          if (_logs.length > 100) {
            _logs.removeAt(0);
          }
        });
        // 스크롤 맨 아래로
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(backgroundBleStateProvider).valueOrNull ??
        BackgroundBleState.stopped;
    final latestMeasurement = ref.watch(backgroundMeasurementProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servicio de conexión automática'),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _logs.clear();
              });
            },
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Borrar log',
          ),
        ],
      ),
      body: Column(
        children: [
          // 상태 카드
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StateIcon(state: state),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Servicio en segundo plano',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getStateText(state),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _getStateColor(state),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // 시작/중지 버튼
                      FilledButton.icon(
                        onPressed: () async {
                          if (state == BackgroundBleState.stopped) {
                            await BackgroundBleService.instance.start();
                          } else {
                            await BackgroundBleService.instance.stop();
                          }
                        },
                        icon: Icon(
                          state == BackgroundBleState.stopped
                              ? Icons.play_arrow
                              : Icons.stop,
                        ),
                        label: Text(
                          state == BackgroundBleState.stopped ? 'Iniciar' : 'Detener',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: state == BackgroundBleState.stopped
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  if (latestMeasurement != null) ...[
                    const Divider(height: 24),
                    Text(
                      'Última medición',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.favorite, color: Colors.red, size: 32),
                        const SizedBox(width: 12),
                        Text(
                          '${latestMeasurement.systolic}/${latestMeasurement.diastolic}',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('mmHg'),
                            if (latestMeasurement.pulse != null)
                              Text(
                                'Pulso: ${latestMeasurement.pulse}',
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hora: ${_formatTime(latestMeasurement.timestamp)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 사용 방법 안내
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Instrucciones (Omron)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildStep(theme, '1', 'Medir con tensiómetro (botón START)'),
                    _buildStep(theme, '2', 'Medición completa → Conexión y envío automático'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Sin emparejamiento - Totalmente automático',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // 로그 영역
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Log',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_logs.length}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _logs.isEmpty
                  ? Center(
                      child: Text(
                        'No hay registros',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontFamily: 'monospace',
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        return Text(
                          log,
                          style: TextStyle(
                            color: _getLogColor(log),
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _getStateText(BackgroundBleState state) {
    switch (state) {
      case BackgroundBleState.stopped:
        return 'Detenido';
      case BackgroundBleState.scanning:
        return 'Buscando dispositivos...';
      case BackgroundBleState.connecting:
        return 'Conectando...';
      case BackgroundBleState.connected:
        return 'Conectado';
      case BackgroundBleState.receiving:
        return 'Esperando datos';
      case BackgroundBleState.error:
        return 'Error';
    }
  }

  Color _getStateColor(BackgroundBleState state) {
    switch (state) {
      case BackgroundBleState.stopped:
        return Colors.grey;
      case BackgroundBleState.scanning:
        return Colors.blue;
      case BackgroundBleState.connecting:
        return Colors.orange;
      case BackgroundBleState.connected:
        return Colors.green;
      case BackgroundBleState.receiving:
        return Colors.green;
      case BackgroundBleState.error:
        return Colors.red;
    }
  }

  Color _getLogColor(String log) {
    if (log.contains('error') || log.contains('fallo') || log.contains('Error') || log.contains('denegado')) {
      return Colors.red[300]!;
    }
    if (log.contains('conectado') || log.contains('completado') || log.contains('éxito') || log.contains('★')) {
      return Colors.green[300]!;
    }
    if (log.contains('advertencia') || log.contains('Warning')) {
      return Colors.orange[300]!;
    }
    if (log.contains('presión arterial')) {
      return Colors.cyan[300]!;
    }
    return Colors.grey[400]!;
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  Widget _buildStep(ThemeData theme, String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// 상태 아이콘
class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.state});

  final BackgroundBleState state;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    bool showProgress = false;

    switch (state) {
      case BackgroundBleState.stopped:
        icon = Icons.stop_circle_outlined;
        color = Colors.grey;
        break;
      case BackgroundBleState.scanning:
        icon = Icons.bluetooth_searching;
        color = Colors.blue;
        showProgress = true;
        break;
      case BackgroundBleState.connecting:
        icon = Icons.bluetooth_connected;
        color = Colors.orange;
        showProgress = true;
        break;
      case BackgroundBleState.connected:
        icon = Icons.bluetooth_connected;
        color = Colors.green;
        break;
      case BackgroundBleState.receiving:
        icon = Icons.sync;
        color = Colors.green;
        showProgress = true;
        break;
      case BackgroundBleState.error:
        icon = Icons.error_outline;
        color = Colors.red;
        break;
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        if (showProgress)
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(color.withValues(alpha: 0.3)),
            ),
          ),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
      ],
    );
  }
}
