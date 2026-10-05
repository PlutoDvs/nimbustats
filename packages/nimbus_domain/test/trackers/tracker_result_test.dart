import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  test('a tracker key compares by id, and is no other kind of key', () {
    expect(const TrackerKey('cig'), const TrackerKey('cig'));
    expect(const TrackerKey('cig').hashCode, const TrackerKey('cig').hashCode);
    expect(const TrackerKey('cig'), isNot(const TrackerKey('water')));
    expect(const TrackerKey('cig'), isNot(const TagKey('cig', '/cig/')));
  });

  test('buckets compare by key, value and count', () {
    const a = TrackerBucket(key: TrackerKey('cig'), value: 2, count: 2);
    expect(a, const TrackerBucket(key: TrackerKey('cig'), value: 2, count: 2));
    expect(
        a,
        isNot(
            const TrackerBucket(key: TrackerKey('cig'), value: 2, count: 1)));
  });
}
