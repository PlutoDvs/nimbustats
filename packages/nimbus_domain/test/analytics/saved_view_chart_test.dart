import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  test('every chart kind round-trips through its stored name', () {
    for (final chart in SavedViewChart.values) {
      expect(SavedViewChart.parse(chart.name), chart);
    }
  });

  test('an unknown name is a format error, never a guess', () {
    expect(() => SavedViewChart.parse('sparkline'),
        throwsA(isA<FormatException>()));
  });
}
