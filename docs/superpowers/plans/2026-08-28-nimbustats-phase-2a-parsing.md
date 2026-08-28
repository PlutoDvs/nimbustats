# Phase 2A — Parsing Domain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `packages/nimbus_domain/lib/src/parsing/` — a pure-Dart engine that turns a bank SMS into a typed, exact `ParsedMessage`, and refuses to turn anything else into one.

**Architecture:** A message is normalized once, tokenized into literal / number / date-like runs, and the user's role taps drive a regex generator that escapes every literal and substitutes tolerant named groups. Matching runs templates by priority and returns a sealed outcome — matched, no match, or malformed — so a template bug is visible rather than silent. Nothing here touches drift, Flutter, or Android; 2B wires it to the database and the UI.

**Tech Stack:** Dart 3.13.1, `package:test`, `package:meta`, `package:crypto` (SHA-256, added in Task 8). No new package needs the network — `crypto-3.0.7` is already in the local pub cache and pinned in `pubspec.lock`.

**Spec:** `docs/superpowers/specs/2026-08-20-nimbustats-design.md` (§"1. Capture pipeline", `message_templates` table)
**Brief:** `docs/phases/phase-2-capture.md` (all `[2A]` sections)
**Conventions:** `docs/phases/CONVENTIONS.md`

## Global Constraints

- **Flutter 3.47.1 / Dart 3.13.1.** Do not bump the SDK or any dependency as a side effect.
- **`nimbus_domain` must not depend on** `flutter`, `drift`, `sqlite3`, `flutter_riverpod`, `nimbus_data`, or `nimbus_design`. Enforced by `test/architecture_test.dart`, not by discipline.
- **`TxDirection` is off-limits.** It is `enum TxDirection { expense, income }` in `packages/nimbus_data/lib/src/tables/transactions_table.dart` — importing it would break the boundary above. 2A defines its own `ParsedDirection`; 2B maps between them.
- **Money is always `int` minor units.** `double` must never represent money. `Money` wraps `int minorUnits`.
- **No `print`. No swallowed exceptions. No hardcoded fallback that masks an error.** A parse that cannot be done exactly must surface, never round quietly.
- **Scope is 2A only.** No schema v10, no Kotlin, no UI, no `CaptureIngestor`, no merchant rules, no `MessageSource`. Those are `[2B]`.
- **Owned paths:** `packages/nimbus_domain/lib/src/parsing/**`, `packages/nimbus_domain/test/parsing/**`. The barrel `lib/nimbus_domain.dart` is shared — append one `export` per line in alphabetical position.
- **TDD order is mandatory:** failing test → observe the failure → minimal implementation → observe the pass → broader suite → commit.
- **Per-commit rollback tags:** before implementing each task, tag the parent commit `pre-<slug>`.
- **Branch:** `phase/2-capture`. **Half-gate tag at the end:** `phase-2a-complete`.

### Commands

```bash
# single test file
cd packages/nimbus_domain && dart test test/parsing/<file>_test.dart

# the full gate, run before every commit
dart analyze --fatal-infos
dart test test/architecture_test.dart
cd packages/nimbus_domain && dart test
```

`dart pub get` must be run as `dart pub get --offline` — pub.dev archive access is currently 403 (DEFERRED D3). Everything needed is cached.

---

## File structure

All paths under `packages/nimbus_domain/`.

| File | Responsibility |
|---|---|
| `lib/src/parsing/message_normalizer.dart` | The one normalization contract. Digits, Arabic letter variants, bidi controls, ZWNJ, whitespace. Idempotent. |
| `lib/src/parsing/token.dart` | `TokenType`, `Token` — a run of text with its offsets. |
| `lib/src/parsing/message_tokenizer.dart` | Splits a normalized message into literal / number / date-like runs. |
| `lib/src/parsing/field_role.dart` | `FieldRole` enum, `RoleAssignment`, `FieldMap` with JSON codec. |
| `lib/src/parsing/regex_generator.dart` | `GeneratedTemplate`, `RegexGenerator` — escape everything, tolerant named groups, both-end anchoring. |
| `lib/src/parsing/amount_parser.dart` | Captured digit run → exact `Money`, applying `amountScale`. |
| `lib/src/parsing/date_parser.dart` | Captured date-like run → `DateKey` via `AppCalendar`. |
| `lib/src/parsing/parsed_direction.dart` | `ParsedDirection` — the domain-side debit/credit, independent of `TxDirection`. |
| `lib/src/parsing/direction_rule.dart` | Sealed `DirectionRule`: fixed or keyword-driven, with JSON codec. |
| `lib/src/parsing/message_template.dart` | `MessageTemplate` value type + JSON codec; validates `amountScale`. |
| `lib/src/parsing/parsed_message.dart` | `ParsedMessage` result and sealed `MatchOutcome`. |
| `lib/src/parsing/template_matcher.dart` | Priority-ordered matching; normalizes internally so callers cannot forget. |
| `lib/src/parsing/dedup_hash.dart` | `dedupHash` — SHA-256 over sender + normalized body + minute bucket. |
| `test/parsing/corpus/sample_messages.dart` | Synthetic corpus: matches **and** near-misses. |

**Design decisions locked here, so tasks do not relitigate them:**

1. **Normalization happens exactly once, inside `MessageNormalizer.normalize`.** Every other entry point (`TemplateMatcher.match`, `dedupHash`) calls it rather than asking the caller to. Two normalization paths that drift apart is how a template silently stops matching.
2. **The generated regex is anchored at both ends (`^…$`).** This trades some recall for the guarantee that an OTP cannot match a purchase template unless it has the same whole-message shape. For money, that is the correct side of the trade. When a bank varies its trailing text, the answer is a second template, not a loosened anchor.
3. **Unassigned number and date tokens become *tolerant non-capturing* groups**, not literals. A template built from a sample whose balance was `500,000` must still match tomorrow's balance.
4. **Higher `priority` is tried first; ties break by ascending `id`.** Determinism matters — two templates matching one message must resolve the same way on every run.
5. **`amountScale` is a divisor.** Iranian banks quote Rial; the app stores Toman; `amountScale: 10` means divide by 10. A division that is not exact throws rather than truncating.
6. **A regex match with an unparseable amount is `MatchOutcome.malformed`, never `noMatch` and never a guessed number.** 2B logs it and surfaces the raw message; the user loses nothing.
7. **`RegExpMatch.namedGroup()` throws `ArgumentError` for a group the pattern does not define** (verified on Dart 3.13.1). So the matcher reads roles from the `FieldMap`, never by probing for a group name.

---

## Task 1: MessageNormalizer

**Files:**
- Create: `packages/nimbus_domain/lib/src/parsing/message_normalizer.dart`
- Test: `packages/nimbus_domain/test/parsing/message_normalizer_test.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (add one export, alphabetical)

**Interfaces:**
- Consumes: `Digits.toLatin(String) → String` from `lib/src/money/digits.dart`.
- Produces: `MessageNormalizer.normalize(String input) → String`. Every later task calls this and assumes its output: Latin digits only, Persian letter forms, no bidi controls, single spaces, trimmed.

**Why this is first.** The tokenizer, the regex generator, the matcher and the dedup hash all operate on normalized text. If normalization changes after templates are stored, every stored regex silently stops matching. Fixing the contract before anything depends on it is the whole point of the ordering.

**A note on writing these files.** Every invisible character in the implementation and the tests is written as a `\u{...}` escape, never pasted raw. A reviewer cannot see a raw ZWNJ, and neither can you when the test that depends on it fails.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/parsing/message_normalizer_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

/// Invisible characters are written as escapes so a reader can see what a
/// failing expectation is actually about.
const zwnj = '\u{200C}';
const rlm = '\u{200F}';
const lrm = '\u{200E}';
const bom = '\u{FEFF}';

void main() {
  group('MessageNormalizer', () {
    test('Persian digits become Latin', () {
      expect(MessageNormalizer.normalize('\u{06F1}\u{06F2}\u{06F3}'), '123');
    });

    test('Arabic-Indic digits become Latin', () {
      expect(MessageNormalizer.normalize('\u{0665}\u{0660}\u{0660}'), '500');
    });

    test('Arabic kaf and yeh fold to their Persian forms', () {
      // The same bank name typed on an Arabic keyboard must normalize to the
      // same bytes as one typed on a Persian keyboard, or the user needs one
      // template per keyboard layout.
      const arabic = 'بانك ملي';
      const persian = 'بانک ملی';
      expect(MessageNormalizer.normalize(arabic), persian);
      expect(MessageNormalizer.normalize(persian), persian);
    });

    test('bidi controls are removed, not turned into spaces', () {
      // A stray space here would break an otherwise-correct template, and
      // these marks are invisible in every log you would debug it with.
      expect(MessageNormalizer.normalize('$rlm123$lrm,456$bom'), '123,456');
    });

    test('ZWNJ and a real space normalize to the same text', () {
      // Banks spell the same compound word both ways across message
      // revisions. Folding both to a space makes one template cover both.
      expect(
        MessageNormalizer.normalize('خرید${zwnj}اینترنتی'),
        MessageNormalizer.normalize('خرید اینترنتی'),
      );
    });

    test('newlines, tabs and NBSP collapse into single spaces', () {
      expect(MessageNormalizer.normalize('a\n\nb\tc\u{00A0}d'), 'a b c d');
    });

    test('leading and trailing whitespace is trimmed', () {
      expect(MessageNormalizer.normalize('  card 1234  '), 'card 1234');
    });

    test('Arabic numeric separators become their Latin equivalents', () {
      expect(MessageNormalizer.normalize('12\u{066B}50'), '12.50');
      expect(MessageNormalizer.normalize('123\u{066C}456'), '123,456');
    });

    test('normalization is idempotent', () {
      // Templates are generated from normalized text and matched against
      // normalized text. If normalize were not a fixed point, a message could
      // match on capture and fail on re-parse after a bug fix.
      const raw = '  بانك${zwnj}ملي \u{06F1}\u{06F2}\u{06F3}$rlm\nریال ';
      final once = MessageNormalizer.normalize(raw);
      expect(MessageNormalizer.normalize(once), once);
    });

    test('a plain Latin message is returned unchanged', () {
      expect(MessageNormalizer.normalize('Purchase 1,250 card 4321'),
          'Purchase 1,250 card 4321');
    });

    test('a whitespace-only message normalizes to empty', () {
      expect(MessageNormalizer.normalize('   \n\t '), '');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/nimbus_domain && dart test test/parsing/message_normalizer_test.dart`
Expected: FAIL to compile — `Undefined name 'MessageNormalizer'`.

- [ ] **Step 3: Write the minimal implementation**

Create `packages/nimbus_domain/lib/src/parsing/message_normalizer.dart`:

```dart
import '../money/digits.dart';

/// The single normalization contract for captured messages.
///
/// Every template regex is generated from normalized text and matched against
/// normalized text. Two normalization paths that drift apart is how a stored
/// template silently stops matching a bank that changed nothing, so there is
/// exactly one: this function. The tokenizer, the matcher and the dedup hash
/// all route through it rather than asking their callers to remember.
///
/// The output alphabet is deliberately small: Latin digits, Persian letter
/// forms, no invisible formatting, single spaces, trimmed.
abstract final class MessageNormalizer {
  /// Zero-width non-joiner. Folded to a space rather than deleted, because
  /// banks spell the same compound word with a ZWNJ in one revision and a
  /// plain space in the next; folding both to a space makes one template
  /// cover both spellings.
  static const _zwnj = '\u{200C}';

  /// Invisible bidi, joiner and byte-order marks. Deleted outright — folding
  /// these to a space would insert a word boundary that is not in the
  /// message, and they are invisible in exactly the logs you would use to
  /// debug the resulting mismatch. ZWNJ (U+200C) is deliberately absent from
  /// this class; it is handled above.
  static final _invisible = RegExp(
    '[\u{200B}\u{200D}-\u{200F}\u{202A}-\u{202E}\u{2066}-\u{2069}\u{FEFF}]',
  );

  static final _whitespace = RegExp(r'\s+');

  /// Code points whose Persian counterpart is a different rune. They look
  /// alike and type alike; only the bytes differ, which is why an unfolded
  /// message fails to match a template built from a folded one.
  static const _folds = <String, String>{
    '\u{0643}': '\u{06A9}', // ARABIC KAF            -> PERSIAN KEHEH
    '\u{064A}': '\u{06CC}', // ARABIC YEH            -> FARSI YEH
    '\u{0649}': '\u{06CC}', // ARABIC ALEF MAKSURA   -> FARSI YEH
    '\u{066B}': '.', // ARABIC DECIMAL SEPARATOR
    '\u{066C}': ',', // ARABIC THOUSANDS SEPARATOR
  };

  static String normalize(String input) {
    var text = Digits.toLatin(input);
    text = text.replaceAll(_invisible, '');
    text = text.replaceAll(_zwnj, ' ');

    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_folds[char] ?? char);
    }

    return buffer.toString().replaceAll(_whitespace, ' ').trim();
  }
}
```

- [ ] **Step 4: Export it from the barrel**

In `packages/nimbus_domain/lib/nimbus_domain.dart`, insert in alphabetical position — after the `src/money/...` exports and before `src/prediction/...`:

```dart
export 'src/parsing/message_normalizer.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/nimbus_domain && dart test test/parsing/message_normalizer_test.dart`
Expected: PASS, 11 tests.

- [ ] **Step 6: Run the full gate**

```bash
dart analyze --fatal-infos
cd packages/nimbus_domain && dart test
```
Expected: clean analyze, every test passes.

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-message-normalizer HEAD
git add packages/nimbus_domain/lib/src/parsing/message_normalizer.dart \
        packages/nimbus_domain/test/parsing/message_normalizer_test.dart \
        packages/nimbus_domain/lib/nimbus_domain.dart
git commit -m "feat: one normalization contract for captured messages

Every template regex is generated from normalized text and matched
against normalized text. Two normalization paths that drift apart is how
a stored template silently stops matching a bank that changed nothing,
so there is exactly one entry point and everything downstream routes
through it.

ZWNJ folds to a space rather than being deleted because banks spell the
same compound word both ways across message revisions. Bidi marks are
deleted rather than folded because a space there would invent a word
boundary the message does not contain -- and both are invisible in the
logs you would debug the mismatch with, so every one of them is written
as an escape in the source."
```

---

## Task 2: Tokenizer

**Files:**
- Create: `packages/nimbus_domain/lib/src/parsing/token.dart`
- Create: `packages/nimbus_domain/lib/src/parsing/message_tokenizer.dart`
- Test: `packages/nimbus_domain/test/parsing/message_tokenizer_test.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (two exports, alphabetical)

**Interfaces:**
- Consumes: `MessageNormalizer.normalize` from Task 1.
- Produces:
  - `enum TokenType { word, number, dateLike, whitespace }`
  - `Token({required TokenType type, required String text, required int start, required int end})` with `==`, `hashCode`, `toString`.
  - `MessageTokenizer.tokenize(String normalized) → List<Token>`

**Why word runs and not literal blobs.** The spec's teach flow is "the tokenizer splits it, highlighting every number, date-like run, and **word-run**". If consecutive non-numeric text collapsed into one token, `خرید از فروشگاه رفاه مبلغ` would be a single tappable unit and the user could never mark just `فروشگاه رفاه` as the merchant — the whole feature would be unusable on the most common message shape. Whitespace is its own token kind so the generator can emit `\s+` for it while keeping the reconstruction invariant exact.

**The invariant that matters.** Concatenating every token's `text` must reproduce the input exactly, and `input.substring(t.start, t.end)` must equal `t.text`. Task 4 rebuilds the message from these tokens; a tokenizer that can drop or duplicate a character would emit a regex for a message that was never sent. Both are asserted.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/parsing/message_tokenizer_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('MessageTokenizer', () {
    test('each word is its own token so a merchant can be tapped', () {
      // If consecutive text collapsed into one token, the user could never
      // mark just the merchant inside a longer sentence.
      final tokens = MessageTokenizer.tokenize('kharid az forushgah refah');
      expect(
          tokens.where((t) => t.type == TokenType.word).map((t) => t.text),
          ['kharid', 'az', 'forushgah', 'refah']);
    });

    test('whitespace is its own token kind', () {
      final tokens = MessageTokenizer.tokenize('a b');
      expect(tokens.map((t) => t.type),
          [TokenType.word, TokenType.whitespace, TokenType.word]);
    });

    test('an amount keeps its separators inside one number token', () {
      final tokens = MessageTokenizer.tokenize('mablagh 1,250,000 rial');
      expect(tokens.where((t) => t.type == TokenType.number).map((t) => t.text),
          ['1,250,000']);
    });

    test('a Jalali date is one date-like token, not three numbers', () {
      final tokens = MessageTokenizer.tokenize('tarikh 1403/05/12');
      expect(
          tokens.where((t) => t.type == TokenType.dateLike).map((t) => t.text),
          ['1403/05/12']);
      expect(tokens.where((t) => t.type == TokenType.number), isEmpty);
    });

    test('an ISO date is date-like too', () {
      final tokens = MessageTokenizer.tokenize('on 2026-08-28 ok');
      expect(
          tokens.where((t) => t.type == TokenType.dateLike).map((t) => t.text),
          ['2026-08-28']);
    });

    test('a bare digit is a number token', () {
      final tokens = MessageTokenizer.tokenize('card 7');
      expect(tokens.last.type, TokenType.number);
      expect(tokens.last.text, '7');
    });

    test('a trailing sentence period is its own word token', () {
      // The amount parser must not inherit a dangling separator to guess at.
      final tokens = MessageTokenizer.tokenize('total 1,250.');
      expect(tokens.map((t) => '${t.type.name}:${t.text}'),
          ['word:total', 'whitespace: ', 'number:1,250', 'word:.']);
    });

    test('concatenating every token reproduces the input exactly', () {
      const input = 'kharid 1,250,000 R az forushgah 1403/05/12 karp 6037';
      expect(MessageTokenizer.tokenize(input).map((t) => t.text).join(), input);
    });

    test('offsets index back into the input', () {
      const input = 'kharid 1,250 az X';
      for (final token in MessageTokenizer.tokenize(input)) {
        expect(input.substring(token.start, token.end), token.text);
      }
    });

    test('an empty message produces no tokens', () {
      expect(MessageTokenizer.tokenize(''), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/nimbus_domain && dart test test/parsing/message_tokenizer_test.dart`
Expected: FAIL to compile — `Undefined name 'MessageTokenizer'`.

- [ ] **Step 3: Write the minimal implementation**

Create `packages/nimbus_domain/lib/src/parsing/token.dart`:

```dart
import 'package:meta/meta.dart';

/// What a run of text is, for the purpose of assigning it a role.
///
/// `word` is a single word rather than a whole run of text between numbers,
/// because the teach flow needs the user to be able to tap exactly the
/// merchant inside a longer sentence. `dateLike` is its own kind so
/// `1403/05/12` does not tokenize into three numbers.
enum TokenType { word, number, dateLike, whitespace }

/// A contiguous run of the normalized message, with its offsets.
///
/// Offsets are kept so the teach-template UI can highlight exactly what the
/// user tapped, and so the regex generator can rebuild the message.
@immutable
final class Token {
  const Token({
    required this.type,
    required this.text,
    required this.start,
    required this.end,
  });

  final TokenType type;
  final String text;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is Token &&
      other.type == type &&
      other.text == text &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(type, text, start, end);

  @override
  String toString() => 'Token(${type.name}, "$text", $start..$end)';
}
```

Create `packages/nimbus_domain/lib/src/parsing/message_tokenizer.dart`:

```dart
import 'token.dart';

/// Splits a normalized message into the runs a user can assign roles to.
///
/// The input must already have been through `MessageNormalizer.normalize`;
/// the patterns below assume Latin digits and single spaces.
abstract final class MessageTokenizer {
  /// Tried before [_number] at every position, so `1403/05/12` stays one
  /// token instead of collapsing into three numbers and two words.
  static final _dateLike = RegExp(r'\d{1,4}[/-]\d{1,2}[/-]\d{1,4}');

  /// A digit run that may carry grouping separators but must begin and end
  /// with a digit, so a trailing sentence period is left to the next word
  /// rather than handed to the amount parser as a dangling separator.
  static final _number = RegExp(r'\d[\d,.]*\d|\d');

  static final _whitespace = RegExp(r'\s+');

  /// Anything contiguous that is neither space nor digit. Punctuation stays
  /// attached to its word; the generator escapes it either way.
  static final _word = RegExp(r'[^\s\d]+');

  /// Order matters: the first pattern that matches at a position wins.
  static const _order = <TokenType>[
    TokenType.dateLike,
    TokenType.number,
    TokenType.whitespace,
    TokenType.word,
  ];

  static RegExp _patternFor(TokenType type) => switch (type) {
        TokenType.dateLike => _dateLike,
        TokenType.number => _number,
        TokenType.whitespace => _whitespace,
        TokenType.word => _word,
      };

  static List<Token> tokenize(String normalized) {
    final tokens = <Token>[];
    var i = 0;
    while (i < normalized.length) {
      var matched = false;
      for (final type in _order) {
        final match = _patternFor(type).matchAsPrefix(normalized, i);
        if (match == null) continue;
        tokens.add(
            Token(type: type, text: match[0]!, start: i, end: match.end));
        i = match.end;
        matched = true;
        break;
      }
      if (!matched) {
        // Unreachable: the four patterns cover every code point. Throwing
        // beats an infinite loop if that ever stops being true.
        throw StateError('tokenizer stalled at offset $i');
      }
    }
    return tokens;
  }
}
```

- [ ] **Step 4: Export both from the barrel**

In `packages/nimbus_domain/lib/nimbus_domain.dart`, in alphabetical position:

```dart
export 'src/parsing/message_tokenizer.dart';
export 'src/parsing/token.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/nimbus_domain && dart test test/parsing/message_tokenizer_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 6: Run the full gate**

```bash
dart analyze --fatal-infos
cd packages/nimbus_domain && dart test
```

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-message-tokenizer HEAD
git add packages/nimbus_domain/lib/src/parsing/token.dart \
        packages/nimbus_domain/lib/src/parsing/message_tokenizer.dart \
        packages/nimbus_domain/test/parsing/message_tokenizer_test.dart \
        packages/nimbus_domain/lib/nimbus_domain.dart
git commit -m "feat: tokenize a message into the runs a user can tap

Words are separate tokens rather than one run of text between numbers.
The teach flow needs the user to tap exactly the merchant inside a
longer sentence, and a single blob token would make the most common
message shape untaggable.

Date-like runs are matched before number runs so 1403/05/12 stays one
token. Tokens carry their offsets and the test asserts that
concatenating them reproduces the input byte for byte -- the regex
generator rebuilds the message from these tokens, so a tokenizer that
could drop a character would emit a regex for a message that was never
sent."
```

---

## Task 3: Role model and field map

**Files:**
- Create: `packages/nimbus_domain/lib/src/parsing/field_role.dart`
- Test: `packages/nimbus_domain/test/parsing/field_role_test.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (one export)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `enum FieldRole { amount, merchant, date, card, balance }` — `role.name` doubles as the regex named-group name, so the values must stay valid Dart group names (letters only).
  - `RoleAssignment({required int startIndex, required int endIndex, required FieldRole role})` plus `RoleAssignment.single(int index, FieldRole role)`. A range, not a single index, because a merchant is routinely two words (`فروشگاه رفاه`) and a card number tokenizes as number/word/number.
  - `FieldMap` with `FieldMap.of(Iterable<FieldRole>)`, `FieldMap.fromJson(Map<String, Object?>)`, `toJson()`, `Set<FieldRole> get roles`, `bool has(FieldRole)`, `String groupFor(FieldRole)`.

**Why `FieldMap` exists at all.** The `message_templates` table has a `field_map` JSON column, and Task 7's matcher must know which roles a stored regex actually defines. It cannot discover that by probing: `RegExpMatch.namedGroup()` throws `ArgumentError` for a group the pattern does not define (verified on Dart 3.13.1), so a probe-based matcher would crash on the first template without a merchant — the exact case the brief calls out as "still useful".

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/parsing/field_role_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('FieldRole', () {
    test('every role name is a valid regex group name', () {
      // role.name is used verbatim as (?<name>...), so a value with an
      // underscore or digit would produce a regex that does not compile.
      for (final role in FieldRole.values) {
        expect(role.name, matches(RegExp(r'^[A-Za-z]+$')),
            reason: '${role.name} cannot be a named capture group');
      }
    });
  });

  group('RoleAssignment', () {
    test('single() covers exactly one token', () {
      final a = RoleAssignment.single(3, FieldRole.amount);
      expect(a.startIndex, 3);
      expect(a.endIndex, 3);
    });

    test('a range covers several tokens, for a two-word merchant', () {
      const a = RoleAssignment(
          startIndex: 8, endIndex: 10, role: FieldRole.merchant);
      expect(a.endIndex - a.startIndex, 2);
    });
  });

  group('FieldMap', () {
    test('the group name for a role is the role name', () {
      final map = FieldMap.of([FieldRole.amount]);
      expect(map.groupFor(FieldRole.amount), 'amount');
    });

    test('has() reports only the roles that were assigned', () {
      final map = FieldMap.of([FieldRole.amount, FieldRole.date]);
      expect(map.has(FieldRole.amount), isTrue);
      expect(map.has(FieldRole.merchant), isFalse);
    });

    test('groupFor throws for a role the template does not define', () {
      // Callers must ask has() first. Returning null here would invite the
      // caller to pass null into namedGroup and get an ArgumentError from
      // deep inside the regex engine instead.
      final map = FieldMap.of([FieldRole.amount]);
      expect(() => map.groupFor(FieldRole.merchant), throwsArgumentError);
    });

    test('JSON round-trips', () {
      final map = FieldMap.of([FieldRole.amount, FieldRole.merchant]);
      expect(FieldMap.fromJson(map.toJson()), map);
    });

    test('fromJson rejects an unknown role rather than dropping it', () {
      // A silently dropped role means a template that quietly stops
      // capturing the amount. Loud beats subtle.
      expect(() => FieldMap.fromJson({'amount': 'amount', 'wat': 'wat'}),
          throwsFormatException);
    });

    test('two maps with the same roles are equal', () {
      expect(FieldMap.of([FieldRole.amount, FieldRole.date]),
          FieldMap.of([FieldRole.date, FieldRole.amount]));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/nimbus_domain && dart test test/parsing/field_role_test.dart`
Expected: FAIL to compile — `Undefined name 'FieldRole'`.

- [ ] **Step 3: Write the minimal implementation**

Create `packages/nimbus_domain/lib/src/parsing/field_role.dart`:

```dart
import 'package:meta/meta.dart';

/// What a tapped run of a message means.
///
/// The enum name is used verbatim as a regex named capture group, so every
/// value must remain a bare sequence of letters.
enum FieldRole { amount, merchant, date, card, balance }

/// A contiguous run of tokens the user assigned to one role.
///
/// This is a range rather than a single index because a merchant is routinely
/// two words and a card number tokenizes as number / word / number.
@immutable
final class RoleAssignment {
  const RoleAssignment({
    required this.startIndex,
    required this.endIndex,
    required this.role,
  });

  const RoleAssignment.single(int index, this.role)
      : startIndex = index,
        endIndex = index;

  final int startIndex;
  final int endIndex;
  final FieldRole role;

  @override
  bool operator ==(Object other) =>
      other is RoleAssignment &&
      other.startIndex == startIndex &&
      other.endIndex == endIndex &&
      other.role == role;

  @override
  int get hashCode => Object.hash(startIndex, endIndex, role);

  @override
  String toString() => 'RoleAssignment(${role.name}, $startIndex..$endIndex)';
}

/// Which named group carries which role, as persisted in the
/// `message_templates.field_map` column.
///
/// The matcher consults this instead of probing the compiled regex, because
/// `RegExpMatch.namedGroup` throws for a group the pattern does not define --
/// which is every template for a bank that does not print a merchant.
@immutable
final class FieldMap {
  const FieldMap._(this._roles);

  factory FieldMap.of(Iterable<FieldRole> roles) =>
      FieldMap._(Set.unmodifiable(roles));

  factory FieldMap.fromJson(Map<String, Object?> json) {
    final roles = <FieldRole>{};
    for (final key in json.keys) {
      final role = FieldRole.values.where((r) => r.name == key).firstOrNull;
      if (role == null) {
        throw FormatException('unknown field role "$key"');
      }
      roles.add(role);
    }
    return FieldMap.of(roles);
  }

  final Set<FieldRole> _roles;

  Set<FieldRole> get roles => _roles;

  bool has(FieldRole role) => _roles.contains(role);

  /// The regex group name carrying [role].
  ///
  /// Throws if the template does not define it -- callers ask [has] first.
  String groupFor(FieldRole role) {
    if (!has(role)) {
      throw ArgumentError.value(
          role.name, 'role', 'this template defines no such group');
    }
    return role.name;
  }

  Map<String, Object?> toJson() =>
      <String, Object?>{for (final role in _roles) role.name: role.name};

  @override
  bool operator ==(Object other) =>
      other is FieldMap &&
      other._roles.length == _roles.length &&
      other._roles.containsAll(_roles);

  @override
  int get hashCode =>
      Object.hashAllUnordered(_roles.map((r) => r.name));

  @override
  String toString() =>
      'FieldMap(${(_roles.map((r) => r.name).toList()..sort()).join(', ')})';
}
```

- [ ] **Step 4: Export it from the barrel**

```dart
export 'src/parsing/field_role.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/nimbus_domain && dart test test/parsing/field_role_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 6: Run the full gate**

```bash
dart analyze --fatal-infos
cd packages/nimbus_domain && dart test
```

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-field-role HEAD
git add packages/nimbus_domain/lib/src/parsing/field_role.dart \
        packages/nimbus_domain/test/parsing/field_role_test.dart \
        packages/nimbus_domain/lib/nimbus_domain.dart
git commit -m "feat: the role model a tapped token maps onto

A RoleAssignment is a token range rather than one index, because a
merchant is routinely two words and a card number tokenizes as number /
word / number.

FieldMap exists so the matcher can ask which roles a stored template
defines instead of probing the compiled regex: namedGroup throws for a
group the pattern does not define, which is every template for a bank
that prints no merchant -- exactly the case the brief requires to keep
working."
```

---

## Task 4: Regex generator

**Files:**
- Create: `packages/nimbus_domain/lib/src/parsing/regex_generator.dart`
- Test: `packages/nimbus_domain/test/parsing/regex_generator_test.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (one export)

**Interfaces:**
- Consumes: `Token`, `TokenType` (Task 2); `FieldRole`, `RoleAssignment`, `FieldMap` (Task 3); `MessageNormalizer.normalize` (Task 1) in tests.
- Produces:
  - `GeneratedTemplate({required String regex, required FieldMap fieldMap})`
  - `RegexGenerator.generate({required List<Token> tokens, required List<RoleAssignment> assignments}) → GeneratedTemplate`
  - `RegexGenerator.merchantMaxLength` (`40`)

**This is the task where a mistake costs real money.** Four rules carry that weight, and each has a test:

1. **Every word is escaped.** `RegExp.escape` on each whitespace-separated piece, rejoined with `\s+`, so a literal `.` cannot become "any character".
2. **Unassigned numbers and dates become tolerant *non-capturing* groups.** A template built from a sample whose balance read `5,000,000` must still match tomorrow's balance.
3. **The regex is anchored `^…$`.** This is what stops an OTP from matching a purchase template. It costs recall — a bank that appends variable trailing text needs a second template — and that is the correct side of the trade for money.
4. **At least one unassigned word must survive as a literal anchor.** A regex made entirely of tolerant groups matches nearly anything; generating one is rejected rather than saved.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/parsing/regex_generator_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

/// A synthetic Persian purchase SMS. Not a real bank's wording.
const purchaseSample = 'بانک نمونه\nخرید از فروشگاه رفاه\n'
    'مبلغ ۱,۲۵۰,۰۰۰ ریال\nمانده ۵,۰۰۰,۰۰۰\nتاریخ ۱۴۰۳/۰۵/۱۲';

/// Token indices in the normalized sample, confirmed by the tokenizer test
/// above: 8..10 is "فروشگاه رفاه", 14 is the amount, 24 is the date.
GeneratedTemplate buildPurchaseTemplate() {
  final tokens =
      MessageTokenizer.tokenize(MessageNormalizer.normalize(purchaseSample));
  return RegexGenerator.generate(
    tokens: tokens,
    assignments: const [
      RoleAssignment(startIndex: 8, endIndex: 10, role: FieldRole.merchant),
      RoleAssignment.single(14, FieldRole.amount),
      RoleAssignment.single(24, FieldRole.date),
    ],
  );
}

void main() {
  group('RegexGenerator', () {
    test('the generated regex matches its own sample and captures each role',
        () {
      final template = buildPurchaseTemplate();
      final match = RegExp(template.regex)
          .firstMatch(MessageNormalizer.normalize(purchaseSample));
      expect(match, isNotNull);
      expect(match!.namedGroup('merchant'), 'فروشگاه رفاه');
      expect(match.namedGroup('amount'), '1,250,000');
      expect(match.namedGroup('date'), '1403/05/12');
    });

    test('an unassigned number is tolerant, not baked in', () {
      // The balance was 5,000,000 in the sample. A template that only
      // matches that balance is worthless after the next purchase.
      final template = buildPurchaseTemplate();
      final other = MessageNormalizer.normalize(
          'بانک نمونه خرید از قهوه ونک مبلغ ۹۸,۷۶۵ ریال '
          'مانده ۱,۱۱۱ تاریخ ۱۴۰۳/۰۶/۰۱');
      final match = RegExp(template.regex).firstMatch(other);
      expect(match, isNotNull);
      expect(match!.namedGroup('amount'), '98,765');
      expect(match.namedGroup('merchant'), 'قهوه ونک');
    });

    test('it does NOT match an OTP from the same sender', () {
      // The single most important assertion in this file. A regex that turns
      // an OTP into a 12,345-Toman expense is worse than one that matches
      // nothing at all.
      final template = buildPurchaseTemplate();
      final otp = MessageNormalizer.normalize('بانک نمونه رمز پویا ۱۲۳۴۵');
      expect(RegExp(template.regex).hasMatch(otp), isFalse);
    });

    test('it does NOT match a promotional message', () {
      final template = buildPurchaseTemplate();
      final promo = MessageNormalizer.normalize(
          'بانک نمونه وام ۵۰۰,۰۰۰,۰۰۰ ریالی ویژه مشتریان');
      expect(RegExp(template.regex).hasMatch(promo), isFalse);
    });

    test('trailing text breaks the anchor', () {
      final template = buildPurchaseTemplate();
      final withTail =
          '${MessageNormalizer.normalize(purchaseSample)} tabligh';
      expect(RegExp(template.regex).hasMatch(withTail), isFalse);
    });

    test('variable whitespace is tolerated', () {
      final tokens = MessageTokenizer.tokenize('total 1,250 ok');
      final template = RegexGenerator.generate(
          tokens: tokens,
          assignments: const [RoleAssignment.single(2, FieldRole.amount)]);
      expect(RegExp(template.regex).hasMatch('total   1,250    ok'), isTrue);
    });

    test('literal punctuation is escaped, not treated as a metacharacter', () {
      final tokens = MessageTokenizer.tokenize('a.b 5 c');
      final template = RegexGenerator.generate(
          tokens: tokens,
          assignments: const [RoleAssignment.single(2, FieldRole.amount)]);
      expect(RegExp(template.regex).hasMatch('a.b 5 c'), isTrue);
      expect(RegExp(template.regex).hasMatch('axb 5 c'), isFalse);
    });

    test('the field map reports exactly the assigned roles', () {
      final template = buildPurchaseTemplate();
      expect(template.fieldMap.roles,
          {FieldRole.merchant, FieldRole.amount, FieldRole.date});
      expect(template.fieldMap.has(FieldRole.balance), isFalse);
    });

    test('a template with no amount is rejected', () {
      final tokens = MessageTokenizer.tokenize('kharid 1,250 rial');
      expect(
          () => RegexGenerator.generate(
              tokens: tokens,
              assignments: const [
                RoleAssignment.single(0, FieldRole.merchant)
              ]),
          throwsArgumentError);
    });

    test('the same role twice is rejected', () {
      final tokens = MessageTokenizer.tokenize('kharid 1,250 rial');
      expect(
          () => RegexGenerator.generate(tokens: tokens, assignments: const [
                RoleAssignment.single(2, FieldRole.amount),
                RoleAssignment.single(0, FieldRole.amount),
              ]),
          throwsArgumentError);
    });

    test('an out-of-range token index is rejected', () {
      final tokens = MessageTokenizer.tokenize('kharid 1,250 rial');
      expect(
          () => RegexGenerator.generate(tokens: tokens, assignments: const [
                RoleAssignment.single(2, FieldRole.amount),
                RoleAssignment.single(99, FieldRole.merchant),
              ]),
          throwsArgumentError);
    });

    test('overlapping ranges are rejected', () {
      final tokens = MessageTokenizer.tokenize('kharid 1,250 rial');
      expect(
          () => RegexGenerator.generate(tokens: tokens, assignments: const [
                RoleAssignment.single(2, FieldRole.amount),
                RoleAssignment(
                    startIndex: 1, endIndex: 3, role: FieldRole.merchant),
              ]),
          throwsArgumentError);
    });

    test('a template with no literal anchor is rejected', () {
      // Every token assigned or tolerant means a regex that matches nearly
      // any message of that shape. Refuse to build it.
      final tokens = MessageTokenizer.tokenize('1,250');
      expect(
          () => RegexGenerator.generate(
              tokens: tokens,
              assignments: const [RoleAssignment.single(0, FieldRole.amount)]),
          throwsArgumentError);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/nimbus_domain && dart test test/parsing/regex_generator_test.dart`
Expected: FAIL to compile — `Undefined name 'RegexGenerator'`.

- [ ] **Step 3: Write the minimal implementation**

Create `packages/nimbus_domain/lib/src/parsing/regex_generator.dart`:

```dart
import 'package:meta/meta.dart';

import 'field_role.dart';
import 'token.dart';

/// A regex plus the roles its named groups carry.
@immutable
final class GeneratedTemplate {
  const GeneratedTemplate({required this.regex, required this.fieldMap});

  final String regex;
  final FieldMap fieldMap;

  @override
  bool operator ==(Object other) =>
      other is GeneratedTemplate &&
      other.regex == regex &&
      other.fieldMap == fieldMap;

  @override
  int get hashCode => Object.hash(regex, fieldMap);

  @override
  String toString() => 'GeneratedTemplate($regex)';
}

/// Turns a tokenized sample plus the user's role taps into a regex.
///
/// Four rules carry the weight here, and each exists because breaking it
/// costs the user money rather than convenience:
///
/// 1. Every word is escaped, so a literal `.` cannot become "any character".
/// 2. Unassigned numbers and dates become *tolerant non-capturing* groups. A
///    template built from a sample whose balance read 5,000,000 must still
///    match tomorrow's balance.
/// 3. The regex is anchored at both ends. This is what stops an OTP from
///    matching a purchase template. It costs recall -- a bank that appends
///    variable trailing text needs a second template -- and that is the
///    correct side of the trade when the output is a transaction.
/// 4. At least one unassigned word must survive as a literal anchor. A regex
///    made entirely of tolerant groups matches nearly anything.
abstract final class RegexGenerator {
  /// A merchant capture is bounded and lazy. Unbounded `.+` between two
  /// tolerant groups is how a template swallows half a message.
  static const merchantMaxLength = 40;

  static const _groupPatterns = <FieldRole, String>{
    FieldRole.amount: r'[\d,.]+',
    FieldRole.balance: r'[\d,.]+',
    FieldRole.date: r'\d{1,4}[/-]\d{1,2}[/-]\d{1,4}',
    FieldRole.card: r'[\dXx*\-]+',
    FieldRole.merchant: '.{1,$merchantMaxLength}?',
  };

  static String _escapeWord(String text) =>
      text.split(RegExp(r'\s+')).map(RegExp.escape).join(r'\s+');

  static GeneratedTemplate generate({
    required List<Token> tokens,
    required List<RoleAssignment> assignments,
  }) {
    final sorted = [...assignments]
      ..sort((a, b) => a.startIndex.compareTo(b.startIndex));

    final roles = <FieldRole>{};
    var previousEnd = -1;
    for (final assignment in sorted) {
      if (assignment.startIndex < 0 ||
          assignment.endIndex >= tokens.length ||
          assignment.endIndex < assignment.startIndex) {
        throw ArgumentError.value(
            '${assignment.startIndex}..${assignment.endIndex}',
            'assignment',
            'token range out of bounds');
      }
      if (!roles.add(assignment.role)) {
        throw ArgumentError.value(
            assignment.role.name, 'assignment', 'role assigned more than once');
      }
      if (assignment.startIndex <= previousEnd) {
        throw ArgumentError.value(
            assignment.role.name, 'assignment', 'token ranges overlap');
      }
      previousEnd = assignment.endIndex;
    }

    if (!roles.contains(FieldRole.amount)) {
      throw ArgumentError('a template with no amount can never build a '
          'transaction; assign FieldRole.amount');
    }

    final byStart = {for (final a in sorted) a.startIndex: a};
    final buffer = StringBuffer('^');
    var anchorChars = 0;
    var i = 0;

    while (i < tokens.length) {
      final assignment = byStart[i];
      if (assignment != null) {
        buffer.write('(?<${assignment.role.name}>'
            '${_groupPatterns[assignment.role]})');
        i = assignment.endIndex + 1;
        continue;
      }

      final token = tokens[i];
      switch (token.type) {
        case TokenType.word:
          buffer.write(_escapeWord(token.text));
          anchorChars += token.text.length;
        case TokenType.whitespace:
          buffer.write(r'\s+');
        case TokenType.number:
          buffer.write(r'(?:[\d,.]+)');
        case TokenType.dateLike:
          buffer.write(r'(?:\d{1,4}[/-]\d{1,2}[/-]\d{1,4})');
      }
      i++;
    }
    buffer.write(r'$');

    if (anchorChars == 0) {
      throw ArgumentError('every token is a tolerant group, so this regex '
          'would match unrelated messages; leave at least one word unassigned '
          'as an anchor');
    }

    return GeneratedTemplate(
        regex: buffer.toString(), fieldMap: FieldMap.of(roles));
  }
}
```

- [ ] **Step 4: Export it from the barrel**

```dart
export 'src/parsing/regex_generator.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/nimbus_domain && dart test test/parsing/regex_generator_test.dart`
Expected: PASS, 13 tests.

- [ ] **Step 6: Run the full gate**

```bash
dart analyze --fatal-infos
cd packages/nimbus_domain && dart test
```

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-regex-generator HEAD
git add packages/nimbus_domain/lib/src/parsing/regex_generator.dart \
        packages/nimbus_domain/test/parsing/regex_generator_test.dart \
        packages/nimbus_domain/lib/nimbus_domain.dart
git commit -m "feat: generate a template regex from tapped tokens

Escape every word, make every unassigned number and date tolerant, and
anchor the whole thing at both ends. The anchoring is the point: it
costs recall against banks that append variable trailing text, and in
exchange an OTP cannot match a purchase template. A regex that turns an
OTP into a 12,345-Toman expense is worse than one that matches nothing.

Generating a regex with no unassigned word left as a literal anchor is
refused outright rather than saved, because such a pattern matches
nearly any message of the same shape."
```

---
## Task 5: Amount and date parsing

**Files:**
- Create: `packages/nimbus_domain/lib/src/parsing/amount_parser.dart`
- Create: `packages/nimbus_domain/lib/src/parsing/date_parser.dart`
- Test: `packages/nimbus_domain/test/parsing/amount_parser_test.dart`
- Test: `packages/nimbus_domain/test/parsing/date_parser_test.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (two exports)

**Interfaces:**
- Consumes: `Money`, `Currency` (`lib/src/money/`), `DateKey`, `AppCalendar`, `GregorianCalendar`, `JalaliCalendar` (`lib/src/calendar/`). All four calendar classes have `const` constructors and `AppCalendar.keyOf(int year, int month, int day) → DateKey`.
- Produces:
  - `AmountParser.parse(String captured, {required Currency currency, int amountScale = 1}) → Money`
  - `DateParser.parse(String captured, {required AppCalendar calendar}) → DateKey`

**The separator problem, decided once.** Iranian SMS group thousands with `,` *and* with `.`, so `1.250.000` and `1,250,000` are the same number. The rules, in order:

1. **If the currency has no decimal digits (Toman), every separator is a grouping separator.** This removes the ambiguity entirely for the app's primary currency.
2. Otherwise, if both `,` and `.` appear, the one occurring **last** is the decimal separator.
3. Otherwise, a lone separator kind is a **grouping** separator when every group after the first is exactly three digits, and a decimal separator when it is not.
4. A fraction with more digits than the currency allows is a `FormatException`, not a rounding.

**`amountScale` is a divisor and must divide exactly.** Banks quote Rial; the app stores Toman; `amountScale: 10` divides by ten. A remainder means the template's scale is wrong, and truncating would understate the expense by up to nine minor units on every capture forever. Throwing surfaces it on the first message instead.

- [ ] **Step 1: Write the failing tests**

Create `packages/nimbus_domain/test/parsing/amount_parser_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('AmountParser', () {
    test('a comma-grouped Toman amount parses exactly', () {
      expect(AmountParser.parse('1,250,000', currency: Currency.toman),
          const Money(1250000));
    });

    test('a dot-grouped amount parses the same way for Toman', () {
      // Iranian SMS use both separators for grouping. Toman has no decimal
      // digits, so a dot cannot mean anything else.
      expect(AmountParser.parse('1.250.000', currency: Currency.toman),
          const Money(1250000));
    });

    test('amountScale converts a Rial quote into Toman', () {
      expect(
          AmountParser.parse('12,500,000',
              currency: Currency.toman, amountScale: 10),
          const Money(1250000));
    });

    test('a scale that does not divide exactly throws', () {
      // Truncating here would understate every captured expense forever.
      expect(
          () => AmountParser.parse('12,500,005',
              currency: Currency.toman, amountScale: 10),
          throwsFormatException);
    });

    test('a decimal currency keeps its fraction', () {
      expect(AmountParser.parse('12.50', currency: Currency.usd),
          const Money(1250));
    });

    test('a decimal currency still groups with commas', () {
      expect(AmountParser.parse('1,234.50', currency: Currency.usd),
          const Money(123450));
    });

    test('European ordering is read by last-separator-wins', () {
      expect(AmountParser.parse('1.234,50', currency: Currency.usd),
          const Money(123450));
    });

    test('more fraction digits than the currency allows throws', () {
      expect(() => AmountParser.parse('12.505', currency: Currency.usd),
          throwsFormatException);
    });

    test('a non-numeric capture throws rather than yielding zero', () {
      // A silent Money.zero here is a captured expense that vanishes.
      expect(() => AmountParser.parse('abc', currency: Currency.toman),
          throwsFormatException);
      expect(() => AmountParser.parse('', currency: Currency.toman),
          throwsFormatException);
    });

    test('a non-positive scale is a programming error', () {
      expect(
          () => AmountParser.parse('100',
              currency: Currency.toman, amountScale: 0),
          throwsArgumentError);
    });
  });
}
```

Create `packages/nimbus_domain/test/parsing/date_parser_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('DateParser', () {
    const jalali = JalaliCalendar();
    const gregorian = GregorianCalendar();

    test('a Jalali year-first date resolves through the Jalali calendar', () {
      expect(DateParser.parse('1403/05/12', calendar: jalali),
          jalali.keyOf(1403, 5, 12));
    });

    test('a Gregorian year is detected even when the active calendar is Jalali',
        () {
      // The year is unambiguous: no Jalali year is 2026. Trusting the active
      // calendar here would place the transaction 621 years away.
      expect(DateParser.parse('2026-08-28', calendar: jalali),
          gregorian.keyOf(2026, 8, 28));
    });

    test('a Jalali year is detected even when the active calendar is Gregorian',
        () {
      expect(DateParser.parse('1403/05/12', calendar: gregorian),
          jalali.keyOf(1403, 5, 12));
    });

    test('a day-first date with a four-digit year is read day/month/year', () {
      expect(DateParser.parse('28-08-2026', calendar: gregorian),
          gregorian.keyOf(2026, 8, 28));
    });

    test('a two-part date is rejected rather than guessed', () {
      // The matcher falls back to the message receipt date, which is right
      // far more often than a guessed year.
      expect(() => DateParser.parse('05/12', calendar: jalali),
          throwsFormatException);
    });

    test('a two-digit year is rejected rather than guessed', () {
      expect(() => DateParser.parse('03/05/12', calendar: jalali),
          throwsFormatException);
    });

    test('an out-of-range month throws', () {
      expect(() => DateParser.parse('1403/13/12', calendar: jalali),
          throwsFormatException);
    });

    test('garbage throws', () {
      expect(() => DateParser.parse('x/y/z', calendar: jalali),
          throwsFormatException);
    });
  });
}
```

- [ ] **Step 2: Run both tests to verify they fail**

Run: `cd packages/nimbus_domain && dart test test/parsing/amount_parser_test.dart test/parsing/date_parser_test.dart`
Expected: FAIL to compile — `Undefined name 'AmountParser'`, `Undefined name 'DateParser'`.

- [ ] **Step 3: Write the minimal implementations**

Create `packages/nimbus_domain/lib/src/parsing/amount_parser.dart`:

```dart
import '../money/currency.dart';
import '../money/money.dart';

/// Turns a captured digit run into exact [Money].
///
/// Iranian SMS group thousands with both `,` and `.`, so `1.250.000` and
/// `1,250,000` are the same number. The rules, in order:
///
/// 1. A currency with no decimal digits (Toman) treats every separator as a
///    grouping separator. That removes the ambiguity for the primary currency.
/// 2. When both separators appear, the one occurring last is the decimal.
/// 3. A lone separator kind groups when every group after the first is
///    exactly three digits, and is a decimal point when it is not.
/// 4. A fraction longer than the currency allows is an error, not a rounding.
abstract final class AmountParser {
  static final _shape = RegExp(r'^[\d.,]+$');

  static Money parse(
    String captured, {
    required Currency currency,
    int amountScale = 1,
  }) {
    if (amountScale < 1) {
      throw ArgumentError.value(
          amountScale, 'amountScale', 'must be a positive divisor');
    }

    final text = captured.trim();
    if (text.isEmpty ||
        !_shape.hasMatch(text) ||
        !text.contains(RegExp(r'\d'))) {
      throw FormatException('not a number', captured);
    }

    final decimalSeparator = _decimalSeparatorOf(text, currency);

    final String wholeText;
    final String fractionText;
    if (decimalSeparator == null) {
      wholeText = text.replaceAll(RegExp(r'[.,]'), '');
      fractionText = '';
    } else {
      final cut = text.lastIndexOf(decimalSeparator);
      wholeText = text.substring(0, cut).replaceAll(RegExp(r'[.,]'), '');
      fractionText = text.substring(cut + 1).replaceAll(RegExp(r'[.,]'), '');
    }

    if (fractionText.length > currency.decimalDigits) {
      throw FormatException(
          'more fraction digits than ${currency.code} allows', captured);
    }

    final whole = int.tryParse(wholeText.isEmpty ? '0' : wholeText);
    final fraction = int.tryParse(fractionText.isEmpty ? '0' : fractionText);
    if (whole == null || fraction == null) {
      throw FormatException('not a number', captured);
    }

    var padded = fraction;
    for (var i = fractionText.length; i < currency.decimalDigits; i++) {
      padded *= 10;
    }

    final minorUnits = whole * currency.minorUnitsPerMajor + padded;
    if (minorUnits % amountScale != 0) {
      // A remainder means the template's scale is wrong. Truncating would
      // understate every capture from this template, forever and silently.
      throw FormatException(
          'amount does not divide evenly by amountScale $amountScale',
          captured);
    }
    return Money(minorUnits ~/ amountScale);
  }

  static String? _decimalSeparatorOf(String text, Currency currency) {
    if (currency.decimalDigits == 0) return null;

    final lastDot = text.lastIndexOf('.');
    final lastComma = text.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      return lastDot > lastComma ? '.' : ',';
    }

    final separator = lastDot >= 0 ? '.' : (lastComma >= 0 ? ',' : null);
    if (separator == null) return null;

    final groups = text.split(separator);
    final grouped =
        groups.skip(1).every((group) => group.length == 3);
    return grouped ? null : separator;
  }
}
```

Create `packages/nimbus_domain/lib/src/parsing/date_parser.dart`:

```dart
import '../calendar/calendar.dart';
import '../calendar/date_key.dart';
import '../calendar/gregorian_calendar.dart';
import '../calendar/jalali_calendar.dart';

/// Turns a captured date-like run into a [DateKey].
///
/// The year decides the calendar, not the user's active setting: no Jalali
/// year is 2026 and no Gregorian year is 1403, so trusting the active
/// calendar for an unambiguous year would place the transaction six centuries
/// away. Anything genuinely ambiguous -- a two-digit year, a two-part date --
/// throws, and the matcher falls back to the message's receipt date, which is
/// right far more often than a guess.
abstract final class DateParser {
  static const _gregorian = GregorianCalendar();
  static const _jalali = JalaliCalendar();

  static DateKey parse(String captured, {required AppCalendar calendar}) {
    final parts = captured.trim().split(RegExp(r'[/-]'));
    if (parts.length != 3) {
      throw FormatException('expected three date components', captured);
    }

    final numbers = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null) throw FormatException('not a date', captured);
      numbers.add(value);
    }

    final int year;
    final int month;
    final int day;
    if (parts.first.length == 4) {
      year = numbers[0];
      month = numbers[1];
      day = numbers[2];
    } else if (parts.last.length == 4) {
      day = numbers[0];
      month = numbers[1];
      year = numbers[2];
    } else {
      throw FormatException('no four-digit year to anchor the date', captured);
    }

    if (month < 1 || month > 12 || day < 1 || day > 31) {
      throw FormatException('date component out of range', captured);
    }

    return _calendarFor(year, calendar).keyOf(year, month, day);
  }

  static AppCalendar _calendarFor(int year, AppCalendar active) {
    if (year >= 1900 && year <= 2200) return _gregorian;
    if (year >= 1200 && year <= 1500) return _jalali;
    return active;
  }
}
```

- [ ] **Step 4: Export both from the barrel**

```dart
export 'src/parsing/amount_parser.dart';
export 'src/parsing/date_parser.dart';
```

- [ ] **Step 5: Run both tests to verify they pass**

Run: `cd packages/nimbus_domain && dart test test/parsing/amount_parser_test.dart test/parsing/date_parser_test.dart`
Expected: PASS, 18 tests.

- [ ] **Step 6: Run the full gate**

```bash
dart analyze --fatal-infos
cd packages/nimbus_domain && dart test
```

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-amount-date-parsing HEAD
git add packages/nimbus_domain/lib/src/parsing/amount_parser.dart \
        packages/nimbus_domain/lib/src/parsing/date_parser.dart \
        packages/nimbus_domain/test/parsing/amount_parser_test.dart \
        packages/nimbus_domain/test/parsing/date_parser_test.dart \
        packages/nimbus_domain/lib/nimbus_domain.dart
git commit -m "feat: parse captured amounts and dates exactly or not at all

Iranian SMS group thousands with both , and . so the separator rules are
settled once here, and a zero-decimal currency treats every separator as
grouping -- which removes the ambiguity entirely for Toman.

amountScale divides and must divide exactly. Banks quote Rial while the
app stores Toman, and a truncated remainder would understate every
capture from that template forever, silently. Throwing surfaces a wrong
scale on the first message instead of the thousandth.

The year picks the calendar rather than the user's active setting: no
Jalali year is 2026. A two-digit year throws instead of guessing, and
the matcher falls back to the receipt date."
```

---

## Task 6: Direction rule

**Files:**
- Create: `packages/nimbus_domain/lib/src/parsing/parsed_direction.dart`
- Create: `packages/nimbus_domain/lib/src/parsing/direction_rule.dart`
- Test: `packages/nimbus_domain/test/parsing/direction_rule_test.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (two exports)

**Interfaces:**
- Produces:
  - `enum ParsedDirection { debit, credit }`
  - `sealed class DirectionRule` with `ParsedDirection resolve(String normalizedBody)`, `Map<String, Object?> toJson()`, `factory DirectionRule.fromJson(Map<String, Object?>)`
  - `FixedDirectionRule(ParsedDirection direction)`
  - `KeywordDirectionRule({required List<String> debitKeywords, required List<String> creditKeywords, required ParsedDirection fallback})`

**Why `ParsedDirection` and not `TxDirection`.** `TxDirection { expense, income }` lives in `packages/nimbus_data/lib/src/tables/transactions_table.dart`. Importing it into `nimbus_domain` would fail `test/architecture_test.dart`, which forbids `nimbus_domain → nimbus_data`. 2A therefore speaks debit/credit and 2B maps `debit → expense`, `credit → income` at the ingestion boundary.

**Ambiguity resolves to the fallback, deliberately.** A transfer notification can contain both a withdrawal and a deposit word. Picking whichever keyword appears first would be a coin flip that looks like a decision; the fallback is at least a stated one, and a test pins it.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/parsing/direction_rule_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('FixedDirectionRule', () {
    test('always resolves to its direction', () {
      const rule = FixedDirectionRule(ParsedDirection.debit);
      expect(rule.resolve('anything at all'), ParsedDirection.debit);
      expect(rule.resolve(''), ParsedDirection.debit);
    });

    test('JSON round-trips', () {
      const rule = FixedDirectionRule(ParsedDirection.credit);
      expect(DirectionRule.fromJson(rule.toJson()), rule);
    });
  });

  group('KeywordDirectionRule', () {
    const rule = KeywordDirectionRule(
      debitKeywords: ['برداشت', 'خرید'],
      creditKeywords: ['واریز'],
      fallback: ParsedDirection.debit,
    );

    test('a debit keyword resolves to debit', () {
      expect(rule.resolve('خرید از فروشگاه'), ParsedDirection.debit);
    });

    test('a credit keyword resolves to credit', () {
      expect(rule.resolve('واریز حقوق'), ParsedDirection.credit);
    });

    test('neither keyword falls back', () {
      expect(rule.resolve('تراکنش انجام شد'), ParsedDirection.debit);
    });

    test('both keywords fall back rather than picking the first', () {
      // A transfer notice can carry both words. Whichever-comes-first is a
      // coin flip dressed as a decision.
      expect(rule.resolve('برداشت و واریز'), ParsedDirection.debit);
    });

    test('JSON round-trips', () {
      expect(DirectionRule.fromJson(rule.toJson()), rule);
    });
  });

  group('DirectionRule.fromJson', () {
    test('an unknown kind throws rather than defaulting to debit', () {
      // Defaulting here would book incoming salary as an expense.
      expect(() => DirectionRule.fromJson({'kind': 'wat'}),
          throwsFormatException);
    });

    test('a missing kind throws', () {
      expect(() => DirectionRule.fromJson({}), throwsFormatException);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/nimbus_domain && dart test test/parsing/direction_rule_test.dart`
Expected: FAIL to compile — `Undefined name 'DirectionRule'`.

- [ ] **Step 3: Write the minimal implementation**

Create `packages/nimbus_domain/lib/src/parsing/parsed_direction.dart`:

```dart
/// Which way money moved, as the parsing layer sees it.
///
/// Deliberately not `TxDirection`: that enum lives in `nimbus_data`, and
/// `nimbus_domain` is forbidden from depending on it by
/// `test/architecture_test.dart`. Phase 2B maps debit to expense and credit
/// to income at the ingestion boundary.
enum ParsedDirection { debit, credit }
```

Create `packages/nimbus_domain/lib/src/parsing/direction_rule.dart`:

```dart
import 'package:meta/meta.dart';

import 'parsed_direction.dart';

/// How a template decides whether a message is money out or money in.
@immutable
sealed class DirectionRule {
  const DirectionRule();

  factory DirectionRule.fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    return switch (kind) {
      'fixed' => FixedDirectionRule(_directionOf(json['direction'])),
      'keyword' => KeywordDirectionRule(
          debitKeywords: _stringsOf(json['debitKeywords']),
          creditKeywords: _stringsOf(json['creditKeywords']),
          fallback: _directionOf(json['fallback']),
        ),
      _ => throw FormatException('unknown direction rule kind "$kind"'),
    };
  }

  ParsedDirection resolve(String normalizedBody);

  Map<String, Object?> toJson();

  static ParsedDirection _directionOf(Object? value) =>
      ParsedDirection.values.where((d) => d.name == value).firstOrNull ??
      (throw FormatException('unknown direction "$value"'));

  static List<String> _stringsOf(Object? value) => switch (value) {
        final List<Object?> list => list.map((e) => e.toString()).toList(),
        _ => throw FormatException('expected a keyword list, got "$value"'),
      };
}

/// Every message from this template moves money the same way.
@immutable
final class FixedDirectionRule extends DirectionRule {
  const FixedDirectionRule(this.direction);

  final ParsedDirection direction;

  @override
  ParsedDirection resolve(String normalizedBody) => direction;

  @override
  Map<String, Object?> toJson() =>
      {'kind': 'fixed', 'direction': direction.name};

  @override
  bool operator ==(Object other) =>
      other is FixedDirectionRule && other.direction == direction;

  @override
  int get hashCode => direction.hashCode;
}

/// The message's own wording decides.
///
/// A body carrying both a debit and a credit word -- a transfer notice --
/// resolves to [fallback] rather than to whichever appeared first. Ordering
/// would be a coin flip dressed up as a decision.
@immutable
final class KeywordDirectionRule extends DirectionRule {
  const KeywordDirectionRule({
    required this.debitKeywords,
    required this.creditKeywords,
    required this.fallback,
  });

  final List<String> debitKeywords;
  final List<String> creditKeywords;
  final ParsedDirection fallback;

  @override
  ParsedDirection resolve(String normalizedBody) {
    final debit = debitKeywords.any(normalizedBody.contains);
    final credit = creditKeywords.any(normalizedBody.contains);
    if (debit && !credit) return ParsedDirection.debit;
    if (credit && !debit) return ParsedDirection.credit;
    return fallback;
  }

  @override
  Map<String, Object?> toJson() => {
        'kind': 'keyword',
        'debitKeywords': debitKeywords,
        'creditKeywords': creditKeywords,
        'fallback': fallback.name,
      };

  @override
  bool operator ==(Object other) =>
      other is KeywordDirectionRule &&
      other.fallback == fallback &&
      _sameList(other.debitKeywords, debitKeywords) &&
      _sameList(other.creditKeywords, creditKeywords);

  @override
  int get hashCode => Object.hash(
        fallback,
        Object.hashAll(debitKeywords),
        Object.hashAll(creditKeywords),
      );

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
```

- [ ] **Step 4: Export both from the barrel**

```dart
export 'src/parsing/direction_rule.dart';
export 'src/parsing/parsed_direction.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/nimbus_domain && dart test test/parsing/direction_rule_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 6: Run the full gate**

```bash
dart analyze --fatal-infos
cd packages/nimbus_domain && dart test
```

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-direction-rule HEAD
git add packages/nimbus_domain/lib/src/parsing/parsed_direction.dart \
        packages/nimbus_domain/lib/src/parsing/direction_rule.dart \
        packages/nimbus_domain/test/parsing/direction_rule_test.dart \
        packages/nimbus_domain/lib/nimbus_domain.dart
git commit -m "feat: tell debits from credits, fixed or by keyword

ParsedDirection rather than TxDirection: that enum lives in nimbus_data
and the architecture test forbids nimbus_domain from importing it. 2B
maps debit to expense at the ingestion boundary.

A body carrying both a withdrawal and a deposit word resolves to the
rule's stated fallback rather than to whichever appeared first, because
ordering would be a coin flip dressed as a decision. An unknown rule
kind in stored JSON throws instead of defaulting to debit -- defaulting
would book incoming salary as an expense."
```

---

## Task 7: MessageTemplate

**Files:**
- Create: `packages/nimbus_domain/lib/src/parsing/message_template.dart`
- Test: `packages/nimbus_domain/test/parsing/message_template_test.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (one export)

**Interfaces:**
- Consumes: `FieldMap` (Task 3), `DirectionRule` (Task 6).
- Produces: `MessageTemplate({required String id, required String name, required String senderPattern, required String regex, required FieldMap fieldMap, required int amountScale, required DirectionRule directionRule, required int priority, required bool enabled, String? packageName, String? sampleBody})`, with `RegExp compiled()`, `bool matchesSender(String sender)`, `toJson()`, `fromJson()`.

**Scope note.** `default_category_id`, `default_payment_method_id`, `match_count` and `last_matched_at` are database columns on `message_templates` but carry no parsing behavior, so they stay out of the domain type. 2B maps them alongside. Adding them here would be speculative surface with no test to justify it.

**`priority` is descending.** Higher is tried first, ties broken by ascending `id`. Two templates matching the same message must resolve identically on every run, and the id tiebreak is what makes that true rather than dependent on list order.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/parsing/message_template_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

MessageTemplate template({
  String id = 't1',
  int amountScale = 1,
  int priority = 0,
  bool enabled = true,
  String senderPattern = r'^BANK$',
}) =>
    MessageTemplate(
      id: id,
      name: 'purchase',
      senderPattern: senderPattern,
      regex: r'^kharid (?<amount>[\d,.]+)$',
      fieldMap: FieldMap.of([FieldRole.amount]),
      amountScale: amountScale,
      directionRule: const FixedDirectionRule(ParsedDirection.debit),
      priority: priority,
      enabled: enabled,
    );

void main() {
  group('MessageTemplate', () {
    test('compiled() returns a usable RegExp', () {
      final match = template().compiled().firstMatch('kharid 1,250');
      expect(match?.namedGroup('amount'), '1,250');
    });

    test('matchesSender applies the sender pattern', () {
      expect(template().matchesSender('BANK'), isTrue);
      expect(template().matchesSender('OTHER'), isFalse);
    });

    test('a sender pattern that is not a valid regex throws on construction',
        () {
      // Better here than as a crash in the middle of ingesting a message.
      expect(() => template(senderPattern: '['), throwsFormatException);
    });

    test('a regex that does not compile throws on construction', () {
      expect(
          () => MessageTemplate(
                id: 't',
                name: 'bad',
                senderPattern: r'^X$',
                regex: '(?<amount>',
                fieldMap: FieldMap.of([FieldRole.amount]),
                amountScale: 1,
                directionRule:
                    const FixedDirectionRule(ParsedDirection.debit),
                priority: 0,
                enabled: true,
              ),
          throwsFormatException);
    });

    test('a non-positive amountScale is rejected', () {
      expect(() => template(amountScale: 0), throwsArgumentError);
    });

    test('a field map claiming a group the regex lacks is rejected', () {
      // The matcher trusts the field map. A map that lies produces an
      // ArgumentError from deep inside the regex engine at capture time.
      expect(
          () => MessageTemplate(
                id: 't',
                name: 'lying',
                senderPattern: r'^X$',
                regex: r'^kharid (?<amount>[\d,.]+)$',
                fieldMap:
                    FieldMap.of([FieldRole.amount, FieldRole.merchant]),
                amountScale: 1,
                directionRule:
                    const FixedDirectionRule(ParsedDirection.debit),
                priority: 0,
                enabled: true,
              ),
          throwsArgumentError);
    });

    test('JSON round-trips', () {
      final original = template(amountScale: 10, priority: 5);
      expect(MessageTemplate.fromJson(original.toJson()), original);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/nimbus_domain && dart test test/parsing/message_template_test.dart`
Expected: FAIL to compile — `Undefined name 'MessageTemplate'`.

- [ ] **Step 3: Write the minimal implementation**

Create `packages/nimbus_domain/lib/src/parsing/message_template.dart`:

```dart
import 'package:meta/meta.dart';

import 'direction_rule.dart';
import 'field_role.dart';

/// A learned message format, as persisted in `message_templates`.
///
/// Everything that can be wrong with a template is checked in the
/// constructor: an uncompilable regex, an invalid sender pattern, a
/// non-positive scale, or a field map claiming a group the regex does not
/// define. Each of those would otherwise surface as an exception in the
/// middle of ingesting a real message, which is the worst possible moment.
@immutable
final class MessageTemplate {
  MessageTemplate({
    required this.id,
    required this.name,
    required this.senderPattern,
    required this.regex,
    required this.fieldMap,
    required this.amountScale,
    required this.directionRule,
    required this.priority,
    required this.enabled,
    this.packageName,
    this.sampleBody,
  }) {
    if (amountScale < 1) {
      throw ArgumentError.value(
          amountScale, 'amountScale', 'must be a positive divisor');
    }
    try {
      _compiled = RegExp(regex);
      _sender = RegExp(senderPattern);
    } on FormatException catch (error) {
      throw FormatException('template $id has an invalid pattern: '
          '${error.message}');
    }
    for (final role in fieldMap.roles) {
      if (!_compiled.pattern.contains('(?<${role.name}>')) {
        throw ArgumentError.value(role.name, 'fieldMap',
            'template $id declares this role but its regex defines no such '
                'group');
      }
    }
  }

  factory MessageTemplate.fromJson(Map<String, Object?> json) =>
      MessageTemplate(
        id: json['id']! as String,
        name: json['name']! as String,
        senderPattern: json['senderPattern']! as String,
        regex: json['regex']! as String,
        fieldMap: FieldMap.fromJson(
            (json['fieldMap']! as Map).cast<String, Object?>()),
        amountScale: json['amountScale']! as int,
        directionRule: DirectionRule.fromJson(
            (json['directionRule']! as Map).cast<String, Object?>()),
        priority: json['priority']! as int,
        enabled: json['enabled']! as bool,
        packageName: json['packageName'] as String?,
        sampleBody: json['sampleBody'] as String?,
      );

  final String id;
  final String name;
  final String senderPattern;
  final String regex;
  final FieldMap fieldMap;

  /// Divisor applied to the parsed amount. Banks quote Rial, the app stores
  /// Toman, so an Iranian template carries 10.
  final int amountScale;
  final DirectionRule directionRule;

  /// Higher is tried first; [TemplateMatcher] breaks ties by ascending [id].
  final int priority;
  final bool enabled;
  final String? packageName;
  final String? sampleBody;

  late final RegExp _compiled;
  late final RegExp _sender;

  RegExp compiled() => _compiled;

  bool matchesSender(String sender) => _sender.hasMatch(sender);

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'senderPattern': senderPattern,
        'regex': regex,
        'fieldMap': fieldMap.toJson(),
        'amountScale': amountScale,
        'directionRule': directionRule.toJson(),
        'priority': priority,
        'enabled': enabled,
        if (packageName != null) 'packageName': packageName,
        if (sampleBody != null) 'sampleBody': sampleBody,
      };

  @override
  bool operator ==(Object other) =>
      other is MessageTemplate &&
      other.id == id &&
      other.name == name &&
      other.senderPattern == senderPattern &&
      other.regex == regex &&
      other.fieldMap == fieldMap &&
      other.amountScale == amountScale &&
      other.directionRule == directionRule &&
      other.priority == priority &&
      other.enabled == enabled &&
      other.packageName == packageName &&
      other.sampleBody == sampleBody;

  @override
  int get hashCode => Object.hash(id, name, senderPattern, regex, fieldMap,
      amountScale, directionRule, priority, enabled, packageName, sampleBody);

  @override
  String toString() => 'MessageTemplate($id, $name, priority $priority)';
}
```

- [ ] **Step 4: Export it from the barrel**

```dart
export 'src/parsing/message_template.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/nimbus_domain && dart test test/parsing/message_template_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 6: Run the full gate**

```bash
dart analyze --fatal-infos
cd packages/nimbus_domain && dart test
```

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-message-template HEAD
git add packages/nimbus_domain/lib/src/parsing/message_template.dart \
        packages/nimbus_domain/test/parsing/message_template_test.dart \
        packages/nimbus_domain/lib/nimbus_domain.dart
git commit -m "feat: the learned template, validated at construction

Everything that can be wrong with a template is checked in the
constructor rather than at capture time: an uncompilable regex, a bad
sender pattern, a non-positive scale, and a field map claiming a group
the regex does not define. The matcher trusts the field map, so a map
that lies would otherwise surface as an ArgumentError from inside the
regex engine while a real message was being ingested.

Database-only columns -- default category, hit counts -- stay out of the
domain type; they carry no parsing behavior and 2B maps them alongside."
```

---

## Task 8: TemplateMatcher

**Files:**
- Create: `packages/nimbus_domain/lib/src/parsing/parsed_message.dart`
- Create: `packages/nimbus_domain/lib/src/parsing/template_matcher.dart`
- Test: `packages/nimbus_domain/test/parsing/template_matcher_test.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (two exports)

**Interfaces:**
- Consumes: every earlier task.
- Produces:
  - `ParsedMessage({required String templateId, required Money amount, required ParsedDirection direction, required DateKey date, String? merchant, String? card, Money? balance})`
  - `sealed class MatchOutcome` with `MatchedMessage(ParsedMessage message)`, `NoMatchingTemplate()`, `MalformedMatch({required String templateId, required String reason})`
  - `TemplateMatcher.match({required String sender, required String rawBody, required DateTime receivedAt, required Iterable<MessageTemplate> templates, required Currency currency, required AppCalendar calendar}) → MatchOutcome`

**Three decisions this task encodes:**

1. **The matcher normalizes `rawBody` itself.** Callers cannot forget, and there is no second normalization path to drift.
2. **A regex match with an unparseable amount is `MalformedMatch`, never `NoMatchingTemplate` and never a guessed number.** Falling through to the next template would let a lower-priority template claim a message the right one already recognised; returning "no match" would hide a template bug as a missing template. 2B logs the reason and keeps the raw message.
3. **A missing date falls back to `receivedAt`.** The brief is explicit that a message without every field is still useful.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/parsing/template_matcher_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

const jalali = JalaliCalendar();
final receivedAt = DateTime(2026, 8, 28, 10, 30);

MessageTemplate purchase({
  String id = 'a',
  int priority = 0,
  bool enabled = true,
  int amountScale = 1,
  String regex = r'^kharid (?<amount>[\d,.]+) rial$',
  Iterable<FieldRole> roles = const [FieldRole.amount],
}) =>
    MessageTemplate(
      id: id,
      name: 'purchase',
      senderPattern: r'^BANK$',
      regex: regex,
      fieldMap: FieldMap.of(roles),
      amountScale: amountScale,
      directionRule: const FixedDirectionRule(ParsedDirection.debit),
      priority: priority,
      enabled: enabled,
    );

MatchOutcome run(
  String body,
  List<MessageTemplate> templates, {
  String sender = 'BANK',
}) =>
    TemplateMatcher.match(
      sender: sender,
      rawBody: body,
      receivedAt: receivedAt,
      templates: templates,
      currency: Currency.toman,
      calendar: jalali,
    );

void main() {
  group('TemplateMatcher', () {
    test('a matching template yields the parsed amount', () {
      final outcome = run('kharid 1,250 rial', [purchase()]);
      expect(outcome, isA<MatchedMessage>());
      final parsed = (outcome as MatchedMessage).message;
      expect(parsed.amount, const Money(1250));
      expect(parsed.direction, ParsedDirection.debit);
      expect(parsed.templateId, 'a');
    });

    test('it normalizes the body itself', () {
      // Persian digits and a bidi mark, exactly as a real SMS arrives.
      final outcome =
          run('kharid \u{06F1},\u{06F2}\u{06F5}\u{06F0}\u{200F} rial',
              [purchase()]);
      expect((outcome as MatchedMessage).message.amount, const Money(1250));
    });

    test('the highest priority template wins', () {
      final outcome = run('kharid 1,250 rial', [
        purchase(id: 'low', priority: 1),
        purchase(id: 'high', priority: 9),
      ]);
      expect((outcome as MatchedMessage).message.templateId, 'high');
    });

    test('equal priorities break by ascending id, not list order', () {
      // Determinism matters: the same inbox must parse the same way twice.
      final forward = run('kharid 1,250 rial',
          [purchase(id: 'b'), purchase(id: 'a')]);
      final reverse = run('kharid 1,250 rial',
          [purchase(id: 'a'), purchase(id: 'b')]);
      expect((forward as MatchedMessage).message.templateId, 'a');
      expect((reverse as MatchedMessage).message.templateId, 'a');
    });

    test('disabled templates are skipped', () {
      final outcome = run('kharid 1,250 rial', [purchase(enabled: false)]);
      expect(outcome, isA<NoMatchingTemplate>());
    });

    test('a template whose sender pattern does not match is skipped', () {
      final outcome =
          run('kharid 1,250 rial', [purchase()], sender: 'SOMEONE');
      expect(outcome, isA<NoMatchingTemplate>());
    });

    test('no template at all is a clean no-match', () {
      expect(run('ramz 12345', [purchase()]), isA<NoMatchingTemplate>());
    });

    test('amountScale is applied', () {
      final outcome = run('kharid 12,500 rial', [purchase(amountScale: 10)]);
      expect((outcome as MatchedMessage).message.amount, const Money(1250));
    });

    test('an unparseable amount is malformed, never a guessed number', () {
      final outcome =
          run('kharid 12,505 rial', [purchase(id: 'x', amountScale: 10)]);
      expect(outcome, isA<MalformedMatch>());
      expect((outcome as MalformedMatch).templateId, 'x');
    });

    test('a missing date falls back to the receipt date', () {
      // A message without every field is still worth keeping.
      final outcome = run('kharid 1,250 rial', [purchase()]);
      expect((outcome as MatchedMessage).message.date,
          DateKey.fromDateTime(receivedAt));
    });

    test('a captured date is used when present', () {
      final outcome = run('kharid 1,250 rial 1403/05/12', [
        purchase(
          regex: r'^kharid (?<amount>[\d,.]+) rial '
              r'(?<date>\d{1,4}[/-]\d{1,2}[/-]\d{1,4})$',
          roles: const [FieldRole.amount, FieldRole.date],
        )
      ]);
      expect((outcome as MatchedMessage).message.date, jalali.keyOf(1403, 5, 12));
    });

    test('an unparseable date falls back rather than failing the match', () {
      // Losing the whole transaction over a malformed date would be worse
      // than booking it on the day it arrived.
      final outcome = run('kharid 1,250 rial 99/99/99', [
        purchase(
          regex: r'^kharid (?<amount>[\d,.]+) rial '
              r'(?<date>\d{1,4}[/-]\d{1,2}[/-]\d{1,4})$',
          roles: const [FieldRole.amount, FieldRole.date],
        )
      ]);
      expect((outcome as MatchedMessage).message.date,
          DateKey.fromDateTime(receivedAt));
    });

    test('a template with no merchant group still parses', () {
      // namedGroup throws for an undefined group, so the matcher must read
      // roles from the field map rather than probing.
      final outcome = run('kharid 1,250 rial', [purchase()]);
      expect((outcome as MatchedMessage).message.merchant, isNull);
      expect(outcome.message.amount, const Money(1250));
    });

    test('a merchant group is captured when the template defines one', () {
      final outcome = run('kharid az refah 1,250 rial', [
        purchase(
          regex: r'^kharid az (?<merchant>.{1,40}?) (?<amount>[\d,.]+) rial$',
          roles: const [FieldRole.merchant, FieldRole.amount],
        )
      ]);
      expect((outcome as MatchedMessage).message.merchant, 'refah');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/nimbus_domain && dart test test/parsing/template_matcher_test.dart`
Expected: FAIL to compile — `Undefined name 'TemplateMatcher'`.

- [ ] **Step 3: Write the minimal implementation**

Create `packages/nimbus_domain/lib/src/parsing/parsed_message.dart`:

```dart
import 'package:meta/meta.dart';

import '../calendar/date_key.dart';
import '../money/money.dart';
import 'parsed_direction.dart';

/// Everything a template could extract from one message.
@immutable
final class ParsedMessage {
  const ParsedMessage({
    required this.templateId,
    required this.amount,
    required this.direction,
    required this.date,
    this.merchant,
    this.card,
    this.balance,
  });

  final String templateId;
  final Money amount;
  final ParsedDirection direction;

  /// Never null: a template without a date group falls back to the date the
  /// message arrived, which is right far more often than dropping the
  /// transaction would be.
  final DateKey date;
  final String? merchant;
  final String? card;
  final Money? balance;

  @override
  String toString() =>
      'ParsedMessage($templateId, $amount, ${direction.name}, $date)';
}

/// What matching a message produced.
///
/// A sealed result rather than a nullable [ParsedMessage] because "no
/// template recognised this" and "a template recognised it and then produced
/// nonsense" need different handling: the first is a prompt to teach a
/// template, the second is a bug to surface.
@immutable
sealed class MatchOutcome {
  const MatchOutcome();
}

final class MatchedMessage extends MatchOutcome {
  const MatchedMessage(this.message);
  final ParsedMessage message;
}

final class NoMatchingTemplate extends MatchOutcome {
  const NoMatchingTemplate();
}

final class MalformedMatch extends MatchOutcome {
  const MalformedMatch({required this.templateId, required this.reason});
  final String templateId;
  final String reason;
}
```

Create `packages/nimbus_domain/lib/src/parsing/template_matcher.dart`:

```dart
import '../calendar/calendar.dart';
import '../calendar/date_key.dart';
import '../money/currency.dart';
import 'amount_parser.dart';
import 'date_parser.dart';
import 'field_role.dart';
import 'message_normalizer.dart';
import 'message_template.dart';
import 'parsed_message.dart';

/// Applies stored templates to an incoming message, in priority order.
abstract final class TemplateMatcher {
  static MatchOutcome match({
    required String sender,
    required String rawBody,
    required DateTime receivedAt,
    required Iterable<MessageTemplate> templates,
    required Currency currency,
    required AppCalendar calendar,
  }) {
    // Normalized here rather than by the caller: one path, nothing to forget.
    final body = MessageNormalizer.normalize(rawBody);

    final candidates = templates
        .where((t) => t.enabled && t.matchesSender(sender))
        .toList()
      ..sort((a, b) {
        final byPriority = b.priority.compareTo(a.priority);
        return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
      });

    for (final template in candidates) {
      final match = template.compiled().firstMatch(body);
      if (match == null) continue;

      String? group(FieldRole role) =>
          template.fieldMap.has(role) ? match.namedGroup(role.name) : null;

      final rawAmount = group(FieldRole.amount);
      if (rawAmount == null) {
        return MalformedMatch(
            templateId: template.id,
            reason: 'matched but captured no amount');
      }

      try {
        final amount = AmountParser.parse(rawAmount,
            currency: currency, amountScale: template.amountScale);

        final rawBalance = group(FieldRole.balance);
        final balance = rawBalance == null
            ? null
            : AmountParser.parse(rawBalance,
                currency: currency, amountScale: template.amountScale);

        return MatchedMessage(ParsedMessage(
          templateId: template.id,
          amount: amount,
          direction: template.directionRule.resolve(body),
          date: _dateOf(group(FieldRole.date), receivedAt, calendar),
          merchant: group(FieldRole.merchant)?.trim(),
          card: group(FieldRole.card),
          balance: balance,
        ));
      } on FormatException catch (error) {
        // The template claimed this message and then produced nonsense. That
        // is a template bug, not a missing template, and falling through to a
        // lower-priority template would let the wrong one claim the message.
        return MalformedMatch(
            templateId: template.id, reason: error.message);
      }
    }

    return const NoMatchingTemplate();
  }

  /// A malformed date costs the transaction its exact day, not its existence.
  static DateKey _dateOf(
      String? captured, DateTime receivedAt, AppCalendar calendar) {
    if (captured == null) return DateKey.fromDateTime(receivedAt);
    try {
      return DateParser.parse(captured, calendar: calendar);
    } on FormatException {
      return DateKey.fromDateTime(receivedAt);
    }
  }
}
```


- [ ] **Step 4: Export both from the barrel**

```dart
export 'src/parsing/parsed_message.dart';
export 'src/parsing/template_matcher.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/nimbus_domain && dart test test/parsing/template_matcher_test.dart`
Expected: PASS, 14 tests.

- [ ] **Step 6: Run the full gate**

```bash
dart analyze --fatal-infos
cd packages/nimbus_domain && dart test
```

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-template-matcher HEAD
git add packages/nimbus_domain/lib/src/parsing/parsed_message.dart \
        packages/nimbus_domain/lib/src/parsing/template_matcher.dart \
        packages/nimbus_domain/test/parsing/template_matcher_test.dart \
        packages/nimbus_domain/lib/nimbus_domain.dart
git commit -m "feat: match a message against stored templates by priority

The outcome is sealed rather than nullable. 'No template recognised
this' is a prompt to teach one; 'a template recognised it and then
produced nonsense' is a bug to surface. Collapsing both into null would
hide the second inside the first, and falling through to the next
template on a bad amount would let a lower-priority template claim a
message the right one already matched.

Ties break by ascending id so the same inbox parses identically twice.
A missing or malformed date falls back to the receipt date: losing the
whole transaction over a bad date field would be worse than booking it
on the day it arrived."
```

---

## Task 9: Dedup hash

**Files:**
- Create: `packages/nimbus_domain/lib/src/parsing/dedup_hash.dart`
- Test: `packages/nimbus_domain/test/parsing/dedup_hash_test.dart`
- Modify: `packages/nimbus_domain/pubspec.yaml` (add `crypto`)
- Modify: `test/architecture_test.dart` (assert the new dependency, per CONVENTIONS §1)
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (one export)

**Interfaces:**
- Produces: `String dedupHash({required String sender, required String body, required DateTime receivedAt})` — 64 lowercase hex characters.

**The new dependency is safe to add offline.** `crypto-3.0.7` is already in the local pub cache and pinned in `pubspec.lock` as a transitive dependency, so `dart pub get --offline` resolves it without touching pub.dev (currently 403 — DEFERRED D3). This was verified before the plan was written.

**Why SHA-256 rather than a hand-rolled 64-bit hash.** `captured_messages.dedup_hash` is `UNIQUE` at the database level, so a collision does not merely risk a duplicate — it makes the second message **unstorable**, and the raw message is lost. Losing raw messages is the one thing the capture design refuses to do. A 64-bit hash's birthday bound is reachable for a chatty inbox over years; SHA-256's is not.

**The minute bucket is a deliberate, tested trade.** Two byte-identical messages from the same sender inside the same minute hash the same and the second is dropped. Two genuinely separate identical purchases a minute apart are rarer than one carrier retry, and double-counting money is worse than missing a rare duplicate purchase. The boundary is sharp — 10:00:59 and 10:01:00 differ — which the tests state rather than leave to be discovered.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/parsing/dedup_hash_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  final at = DateTime.utc(2026, 8, 28, 10, 0, 15);

  group('dedupHash', () {
    test('is 64 lowercase hex characters', () {
      expect(dedupHash(sender: 'BANK', body: 'kharid 1,250', receivedAt: at),
          matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('is stable for the same inputs', () {
      expect(dedupHash(sender: 'BANK', body: 'x', receivedAt: at),
          dedupHash(sender: 'BANK', body: 'x', receivedAt: at));
    });

    test('a different sender gives a different hash', () {
      expect(dedupHash(sender: 'BANK', body: 'x', receivedAt: at),
          isNot(dedupHash(sender: 'OTHER', body: 'x', receivedAt: at)));
    });

    test('a different body gives a different hash', () {
      expect(dedupHash(sender: 'BANK', body: 'x', receivedAt: at),
          isNot(dedupHash(sender: 'BANK', body: 'y', receivedAt: at)));
    });

    test('normalization is inside the hash', () {
      // The same message re-delivered with Persian digits or a stray bidi
      // mark must dedup, or a carrier retry becomes a second expense.
      expect(
        dedupHash(sender: 'BANK', body: '1,250\u{200F}', receivedAt: at),
        dedupHash(
            sender: 'BANK',
            body: '\u{06F1},\u{06F2}\u{06F5}\u{06F0}',
            receivedAt: at),
      );
    });

    test('the same minute collapses to one hash', () {
      // Documented and deliberate: double-counting money is worse than
      // missing a genuine repeat purchase inside the same minute.
      expect(
        dedupHash(
            sender: 'BANK',
            body: 'x',
            receivedAt: DateTime.utc(2026, 8, 28, 10, 0, 1)),
        dedupHash(
            sender: 'BANK',
            body: 'x',
            receivedAt: DateTime.utc(2026, 8, 28, 10, 0, 59)),
      );
    });

    test('the next minute is a different hash', () {
      expect(
        dedupHash(
            sender: 'BANK',
            body: 'x',
            receivedAt: DateTime.utc(2026, 8, 28, 10, 0, 59)),
        isNot(dedupHash(
            sender: 'BANK',
            body: 'x',
            receivedAt: DateTime.utc(2026, 8, 28, 10, 1, 0))),
      );
    });

    test('the same instant hashes the same in any time zone', () {
      final utc = DateTime.utc(2026, 8, 28, 10, 0, 15);
      expect(dedupHash(sender: 'BANK', body: 'x', receivedAt: utc),
          dedupHash(sender: 'BANK', body: 'x', receivedAt: utc.toLocal()));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/nimbus_domain && dart test test/parsing/dedup_hash_test.dart`
Expected: FAIL to compile — `Undefined name 'dedupHash'`.

- [ ] **Step 3: Add the dependency**

In `packages/nimbus_domain/pubspec.yaml`, under `dependencies:`:

```yaml
  crypto: ^3.0.7
```

Then, from the workspace root:

```bash
dart pub get --offline
```

Expected: `Got dependencies!`. It resolves from the local cache; pub.dev is not reachable (D3).

- [ ] **Step 4: Update the architecture test**

CONVENTIONS §1 requires a new package dependency to be reflected in `test/architecture_test.dart` in the same commit. In the `nimbus_domain is pure Dart with no infrastructure dependencies` test, after the forbidden-list loop, add:

```dart
    // crypto is Phase 2A's one new runtime dependency: captured_messages
    // .dedup_hash is UNIQUE at the database level, so a hash collision does
    // not merely risk a duplicate -- it makes the second message unstorable
    // and loses the raw text. SHA-256 rather than a hand-rolled 64-bit hash
    // is the difference between that being impossible and being unlikely.
    expect(deps, contains('crypto'));
```

- [ ] **Step 5: Write the minimal implementation**

Create `packages/nimbus_domain/lib/src/parsing/dedup_hash.dart`:

```dart
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'message_normalizer.dart';

/// Milliseconds in the bucket two deliveries must share to be called the
/// same message.
const _bucketMillis = 60 * 1000;

/// A stable identity for one captured message.
///
/// Stored in `captured_messages.dedup_hash`, which is `UNIQUE` at the
/// database level: double-counting is made structurally impossible rather
/// than merely checked for in Dart.
///
/// SHA-256 rather than something cheaper because that UNIQUE constraint turns
/// a collision into *data loss* -- the colliding message cannot be stored at
/// all, and the whole capture design rests on never losing a raw message.
///
/// The body is normalized first, so the same message re-delivered with
/// Persian digits or a stray bidi mark still dedups; a carrier retry must not
/// become a second expense.
///
/// The receipt time is bucketed to the minute, which is a deliberate trade:
/// two byte-identical messages from one sender inside the same minute
/// collapse to one. Double-counting money is worse than missing a genuine
/// repeat purchase that fast. The boundary is sharp -- 10:00:59 and 10:01:00
/// are different buckets -- and the database constraint, not this function,
/// is the real guard.
String dedupHash({
  required String sender,
  required String body,
  required DateTime receivedAt,
}) {
  final bucket = receivedAt.toUtc().millisecondsSinceEpoch ~/ _bucketMillis;
  final payload = '$sender|${MessageNormalizer.normalize(body)}|$bucket';
  return sha256.convert(utf8.encode(payload)).toString();
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/nimbus_domain && dart test test/parsing/dedup_hash_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 7: Export it and run the full gate**

Add to the barrel:

```dart
export 'src/parsing/dedup_hash.dart';
```

```bash
dart analyze --fatal-infos
dart test test/architecture_test.dart
cd packages/nimbus_domain && dart test
```

- [ ] **Step 8: Tag and commit**

```bash
git tag pre-dedup-hash HEAD
git add packages/nimbus_domain/lib/src/parsing/dedup_hash.dart \
        packages/nimbus_domain/test/parsing/dedup_hash_test.dart \
        packages/nimbus_domain/pubspec.yaml \
        packages/nimbus_domain/lib/nimbus_domain.dart \
        test/architecture_test.dart pubspec.lock
git commit -m "feat: a stable identity for a captured message

dedup_hash is UNIQUE at the database level, so a collision does not
merely risk a duplicate -- it makes the colliding message unstorable and
loses the raw text, which is the one thing the capture design refuses to
do. That is why this is SHA-256 and not a cheaper hand-rolled hash, and
why crypto is worth a new runtime dependency on nimbus_domain. The
architecture test asserts it in the same commit, per CONVENTIONS.

The body is normalized inside the hash so a carrier retry with Persian
digits does not become a second expense. Bucketing receipt time to the
minute is deliberate and tested: two identical messages in one minute
collapse, because double-counting money is worse than missing a repeat
purchase that fast."
```

---

## Task 10: Corpus test with near-misses

**Files:**
- Create: `packages/nimbus_domain/test/parsing/corpus/sample_messages.dart`
- Test: `packages/nimbus_domain/test/parsing/corpus_test.dart`
- Modify: `docs/phases/README.md` (status board row for Phase 2)

**Interfaces:**
- Consumes: everything.
- Produces: no library code. This task exists to prove the pieces work together on realistic input, and to fail loudly when a future change makes a template greedy.

**Why this is its own commit.** It is the only test that answers the brief's sharpest requirement — *"a regex that also matches an OTP message is worse than one that matches nothing"* — end to end rather than per-unit. It is also the test most likely to catch a regression introduced three phases from now.

**Corpus content is synthetic.** These are invented messages in the shape of Iranian bank SMS, not captured user data. Real bodies belong in 2B's on-device verification, not in a committed test fixture.

- [ ] **Step 1: Write the corpus and the failing test**

Create `packages/nimbus_domain/test/parsing/corpus/sample_messages.dart`:

```dart
/// Synthetic messages in the shape of Iranian bank SMS. Invented, not
/// captured -- real message bodies are user data and do not belong in a
/// committed fixture.
library;

/// A message the purchase template is expected to parse, with what it should
/// yield. Amounts are in Toman after the template's amountScale is applied.
typedef ExpectedMatch = ({
  String label,
  String body,
  int amountMinorUnits,
  String? merchant,
});

/// A message from the same sender that must NOT parse. Each one is a shape a
/// greedy regex would happily swallow.
typedef NearMiss = ({String label, String body});

const purchaseSample = 'بانک نمونه\nخرید از فروشگاه رفاه\n'
    'مبلغ ۱۲,۵۰۰,۰۰۰ ریال\nمانده ۵۰,۰۰۰,۰۰۰\nتاریخ ۱۴۰۳/۰۵/۱۲';

const expectedMatches = <ExpectedMatch>[
  (
    label: 'the sample itself',
    body: purchaseSample,
    amountMinorUnits: 1250000,
    merchant: 'فروشگاه رفاه',
  ),
  (
    label: 'a different merchant, amount, balance and date',
    body: 'بانک نمونه خرید از قهوه ونک مبلغ ۹۸۷,۶۵۰ ریال '
        'مانده ۱,۱۱۱,۱۱۰ تاریخ ۱۴۰۳/۰۶/۰۱',
    amountMinorUnits: 98765,
    merchant: 'قهوه ونک',
  ),
  (
    label: 'Latin digits instead of Persian',
    body: 'بانک نمونه خرید از دیجی کالا مبلغ 5,000,000 ریال '
        'مانده 1,000,000 تاریخ 1403/07/02',
    amountMinorUnits: 500000,
    merchant: 'دیجی کالا',
  ),
  (
    label: 'a single-word merchant',
    body: 'بانک نمونه خرید از اسنپ مبلغ ۴۵۰,۰۰۰ ریال '
        'مانده ۲,۰۰۰,۰۰۰ تاریخ ۱۴۰۳/۰۵/۱۳',
    amountMinorUnits: 45000,
    merchant: 'اسنپ',
  ),
];

const nearMisses = <NearMiss>[
  (
    label: 'a one-time password',
    body: 'بانک نمونه رمز پویا ۱۲۳۴۵ اعتبار ۲ دقیقه',
  ),
  (
    label: 'a balance-only notification',
    body: 'بانک نمونه مانده حساب شما ۵۰,۰۰۰,۰۰۰ ریال',
  ),
  (
    label: 'a loan advertisement carrying a large number',
    body: 'بانک نمونه وام ۵۰۰,۰۰۰,۰۰۰ ریالی ویژه مشتریان',
  ),
  (
    label: 'a deposit, which this template must not claim as a purchase',
    body: 'بانک نمونه واریز به حساب مبلغ ۱۲,۵۰۰,۰۰۰ ریال '
        'مانده ۵۰,۰۰۰,۰۰۰ تاریخ ۱۴۰۳/۰۵/۱۲',
  ),
  (
    label: 'the purchase shape with trailing marketing text',
    body: 'بانک نمونه خرید از فروشگاه رفاه مبلغ ۱۲,۵۰۰,۰۰۰ ریال '
        'مانده ۵۰,۰۰۰,۰۰۰ تاریخ ۱۴۰۳/۰۵/۱۲ همراه بانک را نصب کنید',
  ),
];
```

Create `packages/nimbus_domain/test/parsing/corpus_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'corpus/sample_messages.dart';

/// Builds the purchase template the way the teach flow would: normalize the
/// sample, tokenize it, tap the merchant, the amount and the date.
MessageTemplate buildTemplate() {
  final tokens =
      MessageTokenizer.tokenize(MessageNormalizer.normalize(purchaseSample));

  int indexOfWord(String word) {
    final index = tokens.indexWhere(
        (t) => t.type == TokenType.word && t.text == word);
    if (index < 0) throw StateError('corpus drifted: no word "$word"');
    return index;
  }

  final merchantStart = indexOfWord('فروشگاه');
  final amountIndex =
      tokens.indexWhere((t) => t.type == TokenType.number);
  final dateIndex =
      tokens.indexWhere((t) => t.type == TokenType.dateLike);

  final generated = RegexGenerator.generate(
    tokens: tokens,
    assignments: [
      RoleAssignment(
          startIndex: merchantStart,
          endIndex: merchantStart + 2,
          role: FieldRole.merchant),
      RoleAssignment.single(amountIndex, FieldRole.amount),
      RoleAssignment.single(dateIndex, FieldRole.date),
    ],
  );

  return MessageTemplate(
    id: 'purchase',
    name: 'purchase',
    senderPattern: r'^BANK$',
    regex: generated.regex,
    fieldMap: generated.fieldMap,
    // The sample quotes Rial; the app stores Toman.
    amountScale: 10,
    directionRule: const KeywordDirectionRule(
      debitKeywords: ['خرید'],
      creditKeywords: ['واریز'],
      fallback: ParsedDirection.debit,
    ),
    priority: 10,
    enabled: true,
    sampleBody: purchaseSample,
  );
}

MatchOutcome run(MessageTemplate template, String body) =>
    TemplateMatcher.match(
      sender: 'BANK',
      rawBody: body,
      receivedAt: DateTime.utc(2026, 8, 28, 10, 0),
      templates: [template],
      currency: Currency.toman,
      calendar: const JalaliCalendar(),
    );

void main() {
  final template = buildTemplate();

  group('corpus: messages that must parse', () {
    for (final sample in expectedMatches) {
      test(sample.label, () {
        final outcome = run(template, sample.body);
        expect(outcome, isA<MatchedMessage>(),
            reason: 'should have parsed: ${sample.body}');
        final parsed = (outcome as MatchedMessage).message;
        expect(parsed.amount, Money(sample.amountMinorUnits));
        expect(parsed.merchant, sample.merchant);
        expect(parsed.direction, ParsedDirection.debit);
      });
    }
  });

  group('corpus: near-misses that must NOT parse', () {
    for (final sample in nearMisses) {
      test(sample.label, () {
        // A regex that also matches an OTP is worse than one that matches
        // nothing: the first invents an expense, the second asks to be
        // taught. Never a MatchedMessage here.
        expect(run(template, sample.body), isNot(isA<MatchedMessage>()),
            reason: 'must not have parsed: ${sample.body}');
      });
    }
  });

  test('every captured amount survives a round trip through dedupHash', () {
    // Two deliveries of one message must collapse; two different messages
    // must not.
    final first = dedupHash(
        sender: 'BANK',
        body: purchaseSample,
        receivedAt: DateTime.utc(2026, 8, 28, 10, 0, 5));
    final retry = dedupHash(
        sender: 'BANK',
        body: purchaseSample,
        receivedAt: DateTime.utc(2026, 8, 28, 10, 0, 45));
    final different = dedupHash(
        sender: 'BANK',
        body: expectedMatches[1].body,
        receivedAt: DateTime.utc(2026, 8, 28, 10, 0, 5));

    expect(retry, first);
    expect(different, isNot(first));
  });
}
```

- [ ] **Step 2: Run the corpus test**

Run: `cd packages/nimbus_domain && dart test test/parsing/corpus_test.dart`
Expected: PASS, 10 tests.

**If a near-miss parses, do not loosen the assertion.** Tighten the generator. The near-miss list is the specification; the regex is the implementation.

- [ ] **Step 3: Run the whole Phase 2A definition of done**

```bash
dart analyze --fatal-infos
dart test test/architecture_test.dart
cd packages/nimbus_domain && dart test
cd ../nimbus_data && dart test
cd ../../app && flutter test
cd ../packages/nimbus_design && flutter test
```

Expected: everything green. Phase 1 shipped 342 passing tests; 2A adds roughly 100 more and must not change any existing count.

- [ ] **Step 4: Update the status board**

In `docs/phases/README.md`, change the Phase 2 row's status to note 2A is complete and 2B is not:

```
| 2 — Capture | [phase-2-capture.md](phase-2-capture.md) | **2A complete** (2026-08-28) — parsing domain green; 2B not started | `phase-2-complete` |
```

- [ ] **Step 5: Tag and commit**

```bash
git tag pre-parsing-corpus HEAD
git add packages/nimbus_domain/test/parsing/corpus/sample_messages.dart \
        packages/nimbus_domain/test/parsing/corpus_test.dart \
        docs/phases/README.md
git commit -m "test: prove the parser on a corpus of matches and near-misses

The near-miss list is the specification and the regex is the
implementation: an OTP, a balance notice, a loan advert, a deposit, and
the purchase shape with trailing marketing text all reach the matcher
and none of them may produce a transaction. A regex that also matches an
OTP invents an expense; one that matches nothing merely asks to be
taught.

If a near-miss ever starts parsing, tighten the generator rather than
the assertion.

Messages are synthetic, in the shape of Iranian bank SMS. Real bodies
are user data and belong in 2B's on-device verification."
```

- [ ] **Step 6: Tag the half-gate**

Only after every command in Step 3 is green:

```bash
git tag phase-2a-complete
git tag --list 'phase-*-complete'   # expect phase-0-complete and phase-2a-complete
```

Phase 2B gates on this tag existing, along with `phase-0-complete` and `phase-1-complete`. Note that `phase-1-complete` is still withheld on DEFERRED **D1** (Google Maven unreachable), so 2B remains blocked on the network even once 2A is done. 2A itself has no such dependency, which is why it is worth doing now.

---

## Self-review

**Spec coverage.** The brief's 2A scope list maps onto tasks as: tokenizer → 2; role model + field map → 3; digit normalization → 1; regex generator → 4; `TemplateMatcher` with priority → 8; `amount_scale` → 5; `direction_rule` → 6; `dedupHash` → 9; corpus with near-misses → 10. Task 7 (`MessageTemplate`) is additional: the brief implies a persisted template but never names the type, and the matcher needs one. The brief's eight-item outline became ten tasks because `MessageTemplate` and the corpus are each separately rejectable by a reviewer.

**Ordering differs from the brief's outline,** which lists digit normalization third. Normalization is first here because the tokenizer, the generator, the matcher and the hash all consume normalized text; building them against un-normalized input and retrofitting would invalidate every template generated in between.

**Verified before writing, not assumed:**
- `crypto-3.0.7` resolves offline from the local pub cache with `dart pub get --offline`, and `sha256.convert(utf8.encode('abc'))` returns the published SHA-256 vector.
- `RegExp.escape('a.b(c)')` → `a\.b\(c\)`; `namedGroup` returns `null` for an unmatched optional group but **throws `ArgumentError`** for a group the pattern does not define. Task 3's `FieldMap` and Task 8's `group()` helper exist because of that second fact.
- `TxDirection { expense, income }` is in `nimbus_data`, so `ParsedDirection` is required rather than preferred.
- `AppCalendar.keyOf(year, month, day) → DateKey`; `GregorianCalendar` and `JalaliCalendar` both have `const` constructors.
- Tasks 1, 2 and 4 were executed as standalone Dart programs before being written down. Every assertion in them passes, including the OTP and promo rejections and the regex the generator emits for the Persian sample.

**Not verified, and to watch during execution:**
- Tasks 3 and 5 through 10 are written from the same interfaces but were not run end to end. Expect small fixes — particularly the exact token indices in Task 4's `buildPurchaseTemplate` and Task 10's corpus, which is why Task 10 looks its indices up by content instead of hardcoding them.
- `FieldMap` uses `firstOrNull`, which comes from `dart:core`'s `Iterable` extension in Dart 3. If the analyzer objects, `package:collection` is *not* the answer — use `where(...).cast<FieldRole?>().firstWhere((r) => true, orElse: () => null)` or a plain loop rather than adding a dependency.
