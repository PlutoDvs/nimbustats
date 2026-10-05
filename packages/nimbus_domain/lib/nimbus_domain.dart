/// Pure-Dart domain layer for NimbuStats.
///
/// Exports are added one per line and kept alphabetically sorted so that
/// concurrent phases appending to this barrel merge cleanly.
library;

export 'src/analytics/aggregate.dart';
export 'src/analytics/amount_range.dart';
export 'src/analytics/analytics_result.dart';
export 'src/analytics/group_by.dart';
export 'src/analytics/period_boundaries.dart';
export 'src/analytics/query_filters.dart';
export 'src/analytics/query_spec.dart';
export 'src/analytics/reflection_levels.dart';
export 'src/analytics/saved_view_chart.dart';
export 'src/analytics/tag_filter.dart';
export 'src/analytics/view_period.dart';
export 'src/calendar/calendar.dart';
export 'src/calendar/date_key.dart';
export 'src/calendar/gregorian_calendar.dart';
export 'src/calendar/jalali_calendar.dart';
export 'src/entitlements/entitlements.dart';
export 'src/entitlements/feature.dart';
export 'src/money/currency.dart';
export 'src/money/digits.dart';
export 'src/money/money.dart';
export 'src/money/money_format.dart';
export 'src/parsing/amount_parser.dart';
export 'src/parsing/date_parser.dart';
export 'src/parsing/dedup_hash.dart';
export 'src/parsing/direction_rule.dart';
export 'src/parsing/field_role.dart';
export 'src/parsing/message_normalizer.dart';
export 'src/parsing/message_template.dart';
export 'src/parsing/message_tokenizer.dart';
export 'src/parsing/parsed_direction.dart';
export 'src/parsing/parsed_message.dart';
export 'src/parsing/regex_generator.dart';
export 'src/parsing/template_matcher.dart';
export 'src/parsing/token.dart';
export 'src/prediction/category_observation.dart';
export 'src/prediction/category_predictor.dart';
export 'src/prediction/mru_frequency_predictor.dart';
export 'src/trackers/running_timer.dart';
export 'src/trackers/tracker.dart';
export 'src/trackers/tracker_entry.dart';
export 'src/trackers/tracker_group_by.dart';
export 'src/trackers/tracker_query_spec.dart';
export 'src/trackers/tracker_result.dart';
export 'src/trackers/tracker_results.dart';
export 'src/trackers/tracker_type.dart';
export 'src/trackers/tracker_values.dart';
