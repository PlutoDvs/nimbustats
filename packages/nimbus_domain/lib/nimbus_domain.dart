/// Pure-Dart domain layer for NimbuStats.
///
/// Exports are added one per line and kept alphabetically sorted so that
/// concurrent phases appending to this barrel merge cleanly.
library;

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
