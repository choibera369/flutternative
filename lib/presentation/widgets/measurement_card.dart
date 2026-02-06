import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/korean_strings.dart';
import '../../data/models/body_composition.dart';
import '../../data/models/blood_pressure.dart';
import '../../data/models/glucose_reading.dart';

/// 측정 데이터 카드 위젯 (공통)
class MeasurementCard extends StatelessWidget {
  const MeasurementCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
    this.timestamp,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final DateTime? timestamp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (timestamp != null)
                          Text(
                            _formatTimestamp(timestamp!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inDays == 0) {
      return '${KoreanStrings.today} ${DateFormat('HH:mm').format(timestamp)}';
    } else if (diff.inDays == 1) {
      return '${KoreanStrings.yesterday} ${DateFormat('HH:mm').format(timestamp)}';
    } else {
      return DateFormat('MM/dd HH:mm').format(timestamp);
    }
  }
}

/// 체성분 카드
class BodyCompositionCard extends StatelessWidget {
  const BodyCompositionCard({
    super.key,
    required this.data,
    this.onTap,
  });

  final BodyComposition data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MeasurementCard(
      title: KoreanStrings.deviceScale,
      icon: Icons.monitor_weight_outlined,
      color: Colors.blue,
      timestamp: data.timestamp,
      onTap: onTap,
      child: Column(
        children: [
          _MainValue(
            value: data.weight.toStringAsFixed(1),
            unit: KoreanStrings.unitKg,
            label: KoreanStrings.labelWeight,
          ),
          if (data.hasBodyComposition) ...[
            const SizedBox(height: 12),
            // 1행: BMI, 체지방률, 근육량
            Row(
              children: [
                if (data.bmi != null)
                  Expanded(
                    child: _SubValue(
                      label: KoreanStrings.labelBmi,
                      value: data.bmi!.toStringAsFixed(1),
                    ),
                  ),
                if (data.bodyFatPercentage != null)
                  Expanded(
                    child: _SubValue(
                      label: KoreanStrings.labelBodyFat,
                      value: '${data.bodyFatPercentage!.toStringAsFixed(1)}%',
                    ),
                  ),
                if (data.muscleMass != null)
                  Expanded(
                    child: _SubValue(
                      label: KoreanStrings.labelMuscleMass,
                      value:
                          '${data.muscleMass!.toStringAsFixed(1)}${KoreanStrings.unitKg}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 2행: 체수분, 골격량, 내장지방
            Row(
              children: [
                if (data.waterPercentage != null)
                  Expanded(
                    child: _SubValue(
                      label: KoreanStrings.labelWaterPercentage,
                      value: '${data.waterPercentage!.toStringAsFixed(1)}%',
                    ),
                  ),
                if (data.boneMass != null)
                  Expanded(
                    child: _SubValue(
                      label: KoreanStrings.labelBoneMass,
                      value:
                          '${data.boneMass!.toStringAsFixed(2)}${KoreanStrings.unitKg}',
                    ),
                  ),
                if (data.visceralFat != null)
                  Expanded(
                    child: _SubValue(
                      label: KoreanStrings.labelVisceralFat,
                      value: '${data.visceralFat}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 3행: 기초대사량, 대사연령, 단백질
            Row(
              children: [
                if (data.basalMetabolism != null)
                  Expanded(
                    child: _SubValue(
                      label: KoreanStrings.labelBasalMetabolism,
                      value:
                          '${data.basalMetabolism}${KoreanStrings.unitKcal}',
                    ),
                  ),
                if (data.metabolicAge != null)
                  Expanded(
                    child: _SubValue(
                      label: KoreanStrings.labelMetabolicAge,
                      value: '${data.metabolicAge}${KoreanStrings.unitYears}',
                    ),
                  ),
                if (data.proteinPercentage != null)
                  Expanded(
                    child: _SubValue(
                      label: KoreanStrings.labelProteinPercentage,
                      value: '${data.proteinPercentage!.toStringAsFixed(1)}%',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 혈압 카드
class BloodPressureCard extends StatelessWidget {
  const BloodPressureCard({
    super.key,
    required this.data,
    this.onTap,
  });

  final BloodPressureReading data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MeasurementCard(
      title: KoreanStrings.deviceBloodPressure,
      icon: Icons.favorite_outline,
      color: _getCategoryColor(data.category),
      timestamp: data.timestamp,
      onTap: onTap,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${data.systolic}',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: _getCategoryColor(data.category),
                ),
              ),
              const Text(
                ' / ',
                style: TextStyle(fontSize: 24),
              ),
              Text(
                '${data.diastolic}',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: _getCategoryColor(data.category),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                KoreanStrings.unitMmHg,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CategoryBadge(
                label: data.categoryName,
                color: _getCategoryColor(data.category),
              ),
              if (data.irregularPulseDetected) ...[
                const SizedBox(width: 8),
                _CategoryBadge(
                  label: KoreanStrings.labelIrregularPulse,
                  color: Colors.orange,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (data.pulse != null)
                Expanded(
                  child: _SubValue(
                    label: KoreanStrings.labelPulse,
                    value: '${data.pulse} ${KoreanStrings.unitBpm}',
                  ),
                ),
              Expanded(
                child: _SubValue(
                  label: KoreanStrings.labelMeanArterialPressure,
                  value: '${data.calculatedMAP} ${KoreanStrings.unitMmHg}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(BloodPressureCategory category) {
    switch (category) {
      case BloodPressureCategory.normal:
        return Colors.green;
      case BloodPressureCategory.elevated:
        return Colors.amber;
      case BloodPressureCategory.hypertensionStage1:
        return Colors.orange;
      case BloodPressureCategory.hypertensionStage2:
        return Colors.red;
      case BloodPressureCategory.hypertensiveCrisis:
        return Colors.red.shade900;
      case BloodPressureCategory.hypotension:
        return Colors.blue;
    }
  }
}

/// 혈당 카드
class GlucoseCard extends StatelessWidget {
  const GlucoseCard({
    super.key,
    required this.data,
    this.onTap,
  });

  final GlucoseReading data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MeasurementCard(
      title: KoreanStrings.deviceGlucose,
      icon: Icons.water_drop_outlined,
      color: _getCategoryColor(data.category),
      timestamp: data.timestamp,
      onTap: onTap,
      child: Column(
        children: [
          _MainValue(
            value: data.glucoseMgDl.toStringAsFixed(0),
            unit: KoreanStrings.unitMgDl,
            label: KoreanStrings.labelGlucose,
            color: _getCategoryColor(data.category),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CategoryBadge(
                label: data.categoryName,
                color: _getCategoryColor(data.category),
              ),
              const SizedBox(width: 8),
              _CategoryBadge(
                label: data.mealContextName,
                color: Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(GlucoseCategory category) {
    switch (category) {
      case GlucoseCategory.hypoglycemia:
        return Colors.blue;
      case GlucoseCategory.normal:
        return Colors.green;
      case GlucoseCategory.prediabetes:
        return Colors.orange;
      case GlucoseCategory.diabetes:
        return Colors.red;
    }
  }
}

/// 메인 측정값 위젯
class _MainValue extends StatelessWidget {
  const _MainValue({
    required this.value,
    required this.unit,
    required this.label,
    this.color,
  });

  final String value;
  final String unit;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: color ?? theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              unit,
              style: TextStyle(
                fontSize: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 서브 측정값 위젯
class _SubValue extends StatelessWidget {
  const _SubValue({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// 카테고리 뱃지 위젯
class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 빈 상태 카드
class EmptyMeasurementCard extends StatelessWidget {
  const EmptyMeasurementCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.message,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.add_circle_outline,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
