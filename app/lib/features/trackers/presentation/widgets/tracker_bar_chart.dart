import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One tracker's bars, in its own colour, with a spoken summary.
///
/// The bars say nothing a screen reader can use, so the chart is one semantics
/// node carrying [semanticsLabel], and the bars beneath it are excluded.
/// Touch tooltips are off: fl_chart's default tooltip prints the raw double
/// (an hour reads `3600.0`), and the caption and the summary carry the numbers.
/// Time runs left to right in both scripts, as Phase 3's charts do.
///
/// Each value-axis label is keyed `tracker-axis-label-<value>`, for tests.
class TrackerBarChart extends StatelessWidget {
  const TrackerBarChart({
    super.key,
    required this.values,
    required this.color,
    required this.labelOf,
    required this.axisLabelOf,
    required this.axisStepOf,
    required this.semanticsLabel,
    this.labelEvery = 1,
    this.labelKeyPrefix,
    this.height = 180,
  });

  final List<double> values;
  final Color color;

  /// The label under bar [index], already in the settings' digits.
  final String Function(int index) labelOf;

  /// A value-axis label for [value], already formatted.
  final String Function(double value) axisLabelOf;

  /// The value-axis step for the highest bar, [peak], when the axis has room
  /// for [intervals] steps; null leaves it to fl_chart. See `valueAxisStep`.
  final double? Function(double peak, int intervals) axisStepOf;
  final String semanticsLabel;

  /// Label every n-th bar only. Thirty labels do not fit under a month.
  final int labelEvery;

  /// When set, each label is keyed `<prefix>-<index>` for tests.
  final String? labelKeyPrefix;
  final double height;

  /// The bottom axis's labels, under the bars.
  static const _bottomTitlesSize = 28.0;

  /// fl_chart's own measure when it picks a step: one per 40 pixels of axis.
  static const _pixelsPerStep = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peak = values.fold<double>(0, math.max);
    final step = axisStepOf(
        peak, math.max((height - _bottomTitlesSize) ~/ _pixelsPerStep, 1));
    return Semantics(
      container: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: BarChart(
          BarChartData(
            barGroups: [
              for (final (x, value) in values.indexed)
                BarChartGroupData(x: x, barRods: [
                  BarChartRodData(
                    toY: value,
                    color: color,
                    width: values.length > 12 ? 4 : 10,
                  ),
                ]),
            ],
            gridData: FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: step,
                  getTitlesWidget: (value, meta) {
                    // fl_chart also labels the top of the axis, the highest
                    // bar, which is rarely a step: an hour and five minutes
                    // would read 1:05 above 1:00.
                    if (step != null && !_isStep(value, step)) {
                      return const SizedBox.shrink();
                    }
                    return Text(
                      axisLabelOf(value),
                      key: Key('tracker-axis-label-$value'),
                      style: theme.textTheme.labelSmall,
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: _bottomTitlesSize,
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index % labelEvery != 0) return const SizedBox.shrink();
                    final prefix = labelKeyPrefix;
                    return Text(
                      labelOf(index),
                      key: prefix == null ? null : Key('$prefix-$index'),
                      style: theme.textTheme.labelSmall,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Whether [value] is a whole number of [step]s, allowing for the float
  /// error fl_chart builds up adding a step to itself.
  static bool _isStep(double value, double step) {
    final steps = value / step;
    return (steps - steps.roundToDouble()).abs() < 1e-6;
  }
}
