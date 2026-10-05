import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One tracker's bars, in its own colour, with a spoken summary.
///
/// The bars say nothing a screen reader can use, so the chart is one semantics
/// node carrying [semanticsLabel], and the bars beneath it are excluded.
/// Touch tooltips are off: fl_chart's default tooltip prints the raw double
/// (an hour reads `3600.0`), and the caption and the summary carry the numbers.
/// Time runs left to right in both scripts, as Phase 3's charts do.
class TrackerBarChart extends StatelessWidget {
  const TrackerBarChart({
    super.key,
    required this.values,
    required this.color,
    required this.labelOf,
    required this.axisLabelOf,
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
  final String semanticsLabel;

  /// Label every n-th bar only. Thirty labels do not fit under a month.
  final int labelEvery;

  /// When set, each label is keyed `<prefix>-<index>` for tests.
  final String? labelKeyPrefix;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  getTitlesWidget: (value, meta) => Text(
                    axisLabelOf(value),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
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
}
