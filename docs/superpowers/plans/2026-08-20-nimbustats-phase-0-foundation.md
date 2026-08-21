# NimbuStats Phase 0 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the tested, non-visual foundation of NimbuStats — a Dart workspace with compiler-enforced module boundaries, a pure-Dart domain layer (money, dual calendar, entitlements), the SQLite schema with migration tooling, RTL localization, and the screen contract that unblocks UI design.

**Architecture:** Four packages in a Dart pub workspace. `nimbus_domain` is pure Dart with no Flutter and no database dependency, so calendar math, money handling, and entitlement logic are unit-testable without a device. `nimbus_data` is also pure Dart — it owns drift tables and DAOs and receives its database file path by injection, keeping `path_provider` and Flutter out of the data layer. `nimbus_design` holds tokens and theme. `app` is the only package that may depend on everything. A test asserts these boundaries so they cannot erode.

**Tech Stack:** Flutter 3.47.1 / Dart 3.13.1 · drift 2.34.3 (+ drift_dev 2.34.5) · sqlite3 3.5.2 · flutter_riverpod 3.4.2 · shamsi_date 1.1.1 · intl 0.20.3 · uuid 4.6.0 · build_runner 2.16.0

**Spec:** `docs/superpowers/specs/2026-08-20-nimbustats-design.md`

## Global Constraints

- **Flutter 3.47.1 / Dart 3.13.1** (current stable as of 2026-08-19). Recorded in the repo; `pubspec.lock` is committed.
- **`nimbus_domain` MUST NOT depend on** `flutter`, `drift`, `sqlite3`, `flutter_riverpod`, `nimbus_data`, or `nimbus_design`.
- **`nimbus_data` MUST NOT depend on** `flutter`, `flutter_riverpod`, `path_provider`, or `nimbus_design`. It is pure Dart.
- **`nimbus_design` MUST NOT depend on** `drift`, `sqlite3`, or `nimbus_data`.
- **Money is always `int` minor units.** `double` must never represent money anywhere in the codebase.
- **Dates are stored as** `occurred_at_utc` (epoch milliseconds, UTC) **plus** `local_date_key` (`int`, `yyyymmdd`, local Gregorian date).
- **Every table carries** `id TEXT PRIMARY KEY` (UUIDv7), `created_at INTEGER`, `updated_at INTEGER`, `deleted_at INTEGER NULL`.
- **Locales:** `fa` (RTL, primary) and `en` (LTR). Every user-facing string goes through ARB localization — no hardcoded UI text.
- **No `print`.** No silently swallowed exceptions. Lints enforce both.
- **TDD order is mandatory:** write the failing test, run it and observe the failure, implement minimally, run it and observe the pass, commit.
- **Currency:** single active currency per install; Toman (`IRT`, 0 decimal digits) is a first-class option.
- Commit messages follow `type: summary` (`feat:`, `test:`, `chore:`, `docs:`, `fix:`).

---

## File Structure

```
pubspec.yaml                              workspace root; lists members
analysis_options.yaml                     shared lint baseline
test/architecture_test.dart               enforces package boundaries
.github/workflows/ci.yaml                 analyze + test on push

packages/nimbus_domain/                   PURE DART
  lib/nimbus_domain.dart                  public barrel export
  lib/src/money/currency.dart             Currency value type + registry
  lib/src/money/money.dart                Money value type + arithmetic
  lib/src/money/money_format.dart         formatting, parsing, compact forms
  lib/src/money/digits.dart               Persian/Arabic-Indic digit handling
  lib/src/calendar/date_key.dart          DateKey (yyyymmdd) + DateRange
  lib/src/calendar/calendar.dart          AppCalendar interface, CalendarDate, PeriodType
  lib/src/calendar/gregorian_calendar.dart
  lib/src/calendar/jalali_calendar.dart
  lib/src/entitlements/feature.dart       Feature enum
  lib/src/entitlements/entitlements.dart  Entitlements + EntitlementSource
  test/…                                  mirrors lib/src

packages/nimbus_data/                     PURE DART
  lib/nimbus_data.dart                    public barrel export
  lib/src/database/app_database.dart      @DriftDatabase, migrations
  lib/src/database/columns.dart           shared base-column mixin
  lib/src/database/converters.dart        type converters (DateKey, Money, enums)
  lib/src/tables/settings_table.dart
  lib/src/tables/categories_table.dart
  lib/src/tables/tags_table.dart
  lib/src/tables/payment_methods_table.dart
  lib/src/tables/transactions_table.dart
  lib/src/tables/transaction_tags_table.dart
  lib/src/tree/materialized_path.dart     path build/move/subtree-query helpers
  drift_schemas/                          exported schema snapshots per version
  test/…

packages/nimbus_design/                   FLUTTER ONLY
  lib/src/tokens.dart                     colors, type ramp, spacing, radii
  lib/src/theme.dart                      ThemeData builders (light/dark)

app/
  lib/main.dart
  lib/l10n/app_en.arb, app_fa.arb
  l10n.yaml

docs/superpowers/screen-contract.md       Task 12 deliverable
```

---

### Task 1: Toolchain installation and verification

Nothing is installed on this machine — no Flutter, no Dart, no Android SDK, no Android Studio. JDK 17.0.2 is present but `JAVA_HOME` is unset. 108 GB free. **This task is operator-run**; the interactive licence prompt cannot be automated.

**Files:**
- Create: `docs/DEVELOPMENT.md`

**Interfaces:**
- Consumes: nothing
- Produces: a working `flutter` on PATH at 3.47.1 with `flutter doctor` reporting no blocking issues; `docs/DEVELOPMENT.md` recording the exact versions installed.

- [ ] **Step 1: Operator installs the Flutter SDK**

Run in PowerShell:

```powershell
New-Item -ItemType Directory -Force C:\dev | Out-Null
Invoke-WebRequest -Uri "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.1-stable.zip" -OutFile "$env:TEMP\flutter.zip"
Expand-Archive -Path "$env:TEMP\flutter.zip" -DestinationPath C:\dev -Force
[Environment]::SetEnvironmentVariable("Path", "$([Environment]::GetEnvironmentVariable('Path','User'));C:\dev\flutter\bin", "User")
```

Expected: `C:\dev\flutter\bin\flutter.bat` exists. **Open a new terminal** so the PATH change takes effect.

If the download 403s or stalls, the VPN route is the cause (this machine reaches Google endpoints through an Istanbul exit and the route is not always stable). Reconnect and retry — do not substitute a third-party mirror, which would mean trusting an unknown party with the toolchain supply chain.

- [ ] **Step 2: Operator installs the Android SDK command-line tools**

```powershell
New-Item -ItemType Directory -Force C:\dev\android-sdk\cmdline-tools | Out-Null
Invoke-WebRequest -Uri "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" -OutFile "$env:TEMP\cmdline.zip"
Expand-Archive -Path "$env:TEMP\cmdline.zip" -DestinationPath "$env:TEMP\cmdline" -Force
Move-Item "$env:TEMP\cmdline\cmdline-tools" "C:\dev\android-sdk\cmdline-tools\latest"
[Environment]::SetEnvironmentVariable("ANDROID_HOME", "C:\dev\android-sdk", "User")
[Environment]::SetEnvironmentVariable("JAVA_HOME", (Split-Path (Split-Path (Get-Command java).Source)), "User")
```

Open a new terminal, then:

```powershell
& "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat" "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter config --android-sdk C:\dev\android-sdk
```

Expected: `adb` resolves from `C:\dev\android-sdk\platform-tools`.

- [ ] **Step 3: Operator accepts Android licences (interactive — must be run by a human)**

```powershell
flutter doctor --android-licenses
```

Press `y` at each prompt. This cannot be automated; it reads from an interactive stdin.

- [ ] **Step 4: Verify the toolchain and record exact versions**

```powershell
flutter --version
flutter doctor -v
```

Expected: Flutter 3.47.1, Dart 3.13.1, and no red ✗ against "Flutter", "Android toolchain", or "Android licenses". A ✗ against Chrome or Visual Studio is fine and expected — this is an Android-only project.

If `flutter doctor` requests a different Android platform version than `android-36`, install the one it names and re-run.

- [ ] **Step 5: Confirm the native sqlite3 story empirically**

`sqlite3_flutter_libs` is end-of-life; drift ≥ 2.32 with sqlite3 3.x bundles SQLite through build hooks instead. Verify this actually works on this machine before the data layer depends on it:

```powershell
cd $env:TEMP
dart create -t package sqlite_probe
cd sqlite_probe
dart pub add drift sqlite3
dart pub add dev:test
```

Create `test/probe_test.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  test('in-memory sqlite works on the host', () async {
    final db = NativeDatabase.memory();
    await db.ensureOpen(_NoopUser());
    await db.runCustom('CREATE TABLE t (id INTEGER PRIMARY KEY);', const []);
    await db.close();
  });
}

class _NoopUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;
  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
}
```

```powershell
dart test
```

Expected: PASS. If it fails to find a native SQLite library, record the exact error in `docs/DEVELOPMENT.md` and resolve it here — before any DAO code exists — rather than discovering it in Task 9.

- [ ] **Step 6: Write DEVELOPMENT.md and commit**

Record: the exact `flutter --version` output, the Android SDK path, the platform version installed, the sqlite3 probe result, and the note about VPN-dependent access to Google endpoints (commit `pubspec.lock`; a flaky route must never block a build).

```bash
git add docs/DEVELOPMENT.md
git commit -m "docs: record verified toolchain versions and setup steps"
```

---

### Task 2: Workspace scaffold with enforced boundaries

**Files:**
- Create: `pubspec.yaml`, `analysis_options.yaml`, `test/architecture_test.dart`, `.github/workflows/ci.yaml`, `.gitignore`
- Create: `packages/nimbus_domain/pubspec.yaml`, `packages/nimbus_data/pubspec.yaml`, `packages/nimbus_design/pubspec.yaml`, `app/pubspec.yaml`

**Interfaces:**
- Consumes: Task 1's toolchain
- Produces: a resolvable workspace; `dart test test/architecture_test.dart` enforcing the boundary rules listed in Global Constraints.

- [ ] **Step 1: Write the failing architecture test**

`test/architecture_test.dart`:

```dart
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Set<String> runtimeDeps(String packagePath) {
  final file = File('$packagePath/pubspec.yaml');
  if (!file.existsSync()) {
    fail('missing pubspec at $packagePath');
  }
  final doc = loadYaml(file.readAsStringSync()) as YamlMap;
  final deps = doc['dependencies'];
  if (deps is! YamlMap) return <String>{};
  return deps.keys.cast<String>().toSet();
}

void main() {
  test('nimbus_domain is pure Dart with no infrastructure dependencies', () {
    final deps = runtimeDeps('packages/nimbus_domain');
    for (final forbidden in [
      'flutter',
      'drift',
      'sqlite3',
      'flutter_riverpod',
      'nimbus_data',
      'nimbus_design',
    ]) {
      expect(deps, isNot(contains(forbidden)),
          reason: 'nimbus_domain must stay pure; remove $forbidden');
    }
  });

  test('nimbus_data is pure Dart and never reaches the UI', () {
    final deps = runtimeDeps('packages/nimbus_data');
    for (final forbidden in [
      'flutter',
      'flutter_riverpod',
      'path_provider',
      'nimbus_design',
    ]) {
      expect(deps, isNot(contains(forbidden)),
          reason: 'nimbus_data must stay pure; remove $forbidden');
    }
    expect(deps, contains('nimbus_domain'));
  });

  test('nimbus_design never touches persistence', () {
    final deps = runtimeDeps('packages/nimbus_design');
    for (final forbidden in ['drift', 'sqlite3', 'nimbus_data']) {
      expect(deps, isNot(contains(forbidden)),
          reason: 'nimbus_design is presentation only; remove $forbidden');
    }
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/architecture_test.dart`
Expected: FAIL — `missing pubspec at packages/nimbus_domain`.

- [ ] **Step 3: Create the workspace root**

`pubspec.yaml`:

```yaml
name: nimbustats_workspace
publish_to: none

environment:
  sdk: ^3.13.0

workspace:
  - packages/nimbus_domain
  - packages/nimbus_data
  - packages/nimbus_design
  - app

dev_dependencies:
  test: ^1.25.0
  yaml: ^3.1.2
  lints: ^5.0.0
```

`analysis_options.yaml`:

```yaml
include: package:lints/recommended.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    avoid_print: error
    empty_catches: error
    unawaited_futures: error

linter:
  rules:
    - always_declare_return_types
    - prefer_final_locals
    - avoid_dynamic_calls
    - throw_in_finally
    - only_throw_errors
```

- [ ] **Step 4: Create the four member packages**

`packages/nimbus_domain/pubspec.yaml`:

```yaml
name: nimbus_domain
publish_to: none
resolution: workspace

environment:
  sdk: ^3.13.0

dependencies:
  shamsi_date: ^1.1.1
  meta: ^1.15.0

dev_dependencies:
  test: ^1.25.0
```

`packages/nimbus_data/pubspec.yaml`:

```yaml
name: nimbus_data
publish_to: none
resolution: workspace

environment:
  sdk: ^3.13.0

dependencies:
  nimbus_domain: ^0.0.0
  drift: ^2.34.3
  sqlite3: ^3.5.2
  uuid: ^4.6.0

dev_dependencies:
  test: ^1.25.0
  drift_dev: ^2.34.5
  build_runner: ^2.16.0
```

`packages/nimbus_design/pubspec.yaml`:

```yaml
name: nimbus_design
publish_to: none
resolution: workspace

environment:
  sdk: ^3.13.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

`app/pubspec.yaml`:

```yaml
name: nimbustats
publish_to: none
resolution: workspace

environment:
  sdk: ^3.13.0

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  nimbus_domain: ^0.0.0
  nimbus_data: ^0.0.0
  nimbus_design: ^0.0.0
  flutter_riverpod: ^3.4.2
  path_provider: ^2.1.6
  intl: ^0.20.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
  generate: true
```

Create the minimal library files each package needs to resolve: `packages/nimbus_domain/lib/nimbus_domain.dart`, `packages/nimbus_data/lib/nimbus_data.dart`, `packages/nimbus_design/lib/nimbus_design.dart` (each an empty barrel for now), and `app/lib/main.dart` with a bare `void main() {}`.

- [ ] **Step 5: Resolve and run the test to verify it passes**

Run: `flutter pub get` then `dart test test/architecture_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 6: Add CI**

`.github/workflows/ci.yaml`:

```yaml
name: CI
on: [push, pull_request]

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.47.1
          channel: stable
      - run: flutter pub get
      - run: dart analyze --fatal-infos
      - run: dart test test/architecture_test.dart
      - run: dart test
        working-directory: packages/nimbus_domain
      - run: dart test
        working-directory: packages/nimbus_data
```

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock analysis_options.yaml .gitignore test/ packages/ app/ .github/
git commit -m "feat: workspace scaffold with compiler-enforced package boundaries

Boundaries are asserted by a test rather than left to convention, because
folder conventions erode under deadline pressure and pubspec rules do not."
```

---

### Task 3: Money value type

**Files:**
- Create: `packages/nimbus_domain/lib/src/money/currency.dart`, `packages/nimbus_domain/lib/src/money/money.dart`
- Test: `packages/nimbus_domain/test/money/money_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `Currency(code, symbolKey, decimalDigits)`, `Currency.toman`, `Currency.byCode(String)`; `Money(int minorUnits)` with `+`, `-`, `*`, `unary-`, `abs()`, `isNegative`, `compareTo`, `Money.zero`, and `Money.sum(Iterable<Money>)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Money', () {
    test('adds and subtracts without precision loss', () {
      expect(const Money(1500) + const Money(2500), const Money(4000));
      expect(const Money(1000) - const Money(2500), const Money(-1500));
    });

    test('sums an empty iterable to zero', () {
      expect(Money.sum(const []), Money.zero);
    });

    test('sums many values exactly', () {
      final values = List.generate(1000, (i) => Money(i));
      expect(Money.sum(values), const Money(499500));
    });

    test('compares and sorts by minor units', () {
      final list = [const Money(300), const Money(-100), const Money(50)]..sort();
      expect(list, [const Money(-100), const Money(50), const Money(300)]);
    });

    test('equality is by value', () {
      expect(const Money(42), const Money(42));
      expect(const Money(42).hashCode, const Money(42).hashCode);
    });
  });

  group('Currency', () {
    test('toman has no decimal digits', () {
      expect(Currency.toman.code, 'IRT');
      expect(Currency.toman.decimalDigits, 0);
    });

    test('looks up by code and rejects unknown codes', () {
      expect(Currency.byCode('IRT'), Currency.toman);
      expect(() => Currency.byCode('XXX'), throwsArgumentError);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/nimbus_domain && dart test test/money/money_test.dart`
Expected: FAIL — `Money` and `Currency` are undefined.

- [ ] **Step 3: Implement Currency and Money**

`lib/src/money/currency.dart`:

```dart
import 'package:meta/meta.dart';

/// A currency the app can operate in. Only one is active per install.
@immutable
final class Currency {
  const Currency({
    required this.code,
    required this.decimalDigits,
    required this.symbolKey,
  });

  /// ISO-style code. Toman uses `IRT`, which is not an ISO code — Iranian
  /// banks quote Rial (`IRR`) while people think and speak in Toman.
  final String code;

  /// Number of fractional digits. Toman has none.
  final int decimalDigits;

  /// Localization key for the symbol, resolved in the UI layer.
  final String symbolKey;

  static const toman = Currency(code: 'IRT', decimalDigits: 0, symbolKey: 'currency_toman');
  static const usd = Currency(code: 'USD', decimalDigits: 2, symbolKey: 'currency_usd');
  static const eur = Currency(code: 'EUR', decimalDigits: 2, symbolKey: 'currency_eur');
  static const tryLira = Currency(code: 'TRY', decimalDigits: 2, symbolKey: 'currency_try');

  static const all = <Currency>[toman, usd, eur, tryLira];

  static Currency byCode(String code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    throw ArgumentError.value(code, 'code', 'Unknown currency');
  }

  /// Multiplier converting one major unit into minor units.
  int get minorUnitsPerMajor {
    var result = 1;
    for (var i = 0; i < decimalDigits; i++) {
      result *= 10;
    }
    return result;
  }

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'Currency($code)';
}
```

`lib/src/money/money.dart`:

```dart
import 'package:meta/meta.dart';

/// An exact monetary amount in a currency's smallest unit.
///
/// Money is never a `double`. Floating point cannot represent decimal
/// fractions exactly, and rounding drift in a ledger is not recoverable.
@immutable
final class Money implements Comparable<Money> {
  const Money(this.minorUnits);

  final int minorUnits;

  static const zero = Money(0);

  static Money sum(Iterable<Money> values) {
    var total = 0;
    for (final v in values) {
      total += v.minorUnits;
    }
    return Money(total);
  }

  Money operator +(Money other) => Money(minorUnits + other.minorUnits);
  Money operator -(Money other) => Money(minorUnits - other.minorUnits);
  Money operator *(int factor) => Money(minorUnits * factor);
  Money operator -() => Money(-minorUnits);

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;
  Money abs() => Money(minorUnits.abs());

  @override
  int compareTo(Money other) => minorUnits.compareTo(other.minorUnits);

  @override
  bool operator ==(Object other) => other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;

  @override
  String toString() => 'Money($minorUnits)';
}
```

Export both from `lib/nimbus_domain.dart`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart test test/money/money_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add packages/nimbus_domain
git commit -m "feat: exact Money value type and Currency registry

Money wraps integer minor units. Floating point is never used for money
because rounding drift in a ledger cannot be recovered after the fact."
```

---

### Task 4: Money formatting, parsing, and compact display

Toman amounts are large — a lunch is `450000` — so grouping and compact forms are not cosmetic. A chart axis labelled `450000` is unreadable; `۴۵۰ هزار` is not.

**Files:**
- Create: `packages/nimbus_domain/lib/src/money/digits.dart`, `packages/nimbus_domain/lib/src/money/money_format.dart`
- Test: `packages/nimbus_domain/test/money/money_format_test.dart`

**Interfaces:**
- Consumes: `Money`, `Currency` from Task 3
- Produces: `Digits.toLatin(String)`, `Digits.toPersian(String)`; `MoneyFormatter({required Currency currency, required bool persianDigits})` with `format(Money)`, `formatCompact(Money)`, `parse(String) → Money?`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  final toman = MoneyFormatter(currency: Currency.toman, persianDigits: false);
  final tomanFa = MoneyFormatter(currency: Currency.toman, persianDigits: true);
  final usd = MoneyFormatter(currency: Currency.usd, persianDigits: false);

  group('Digits', () {
    test('converts Persian and Arabic-Indic digits to Latin', () {
      expect(Digits.toLatin('۴۵۰۰۰۰'), '450000');
      expect(Digits.toLatin('٤٥٠'), '450');
      expect(Digits.toLatin('12۳٤'), '1234');
    });

    test('converts Latin digits to Persian', () {
      expect(Digits.toPersian('450'), '۴۵۰');
    });
  });

  group('format', () {
    test('groups thousands', () {
      expect(toman.format(const Money(450000)), '450,000');
      expect(toman.format(const Money(1234567)), '1,234,567');
      expect(toman.format(const Money(999)), '999');
    });

    test('renders decimal currencies with their fraction', () {
      expect(usd.format(const Money(1234)), '12.34');
      expect(usd.format(const Money(5)), '0.05');
    });

    test('keeps the minus sign ahead of the digits', () {
      expect(toman.format(const Money(-450000)), '-450,000');
    });

    test('uses Persian digits when asked', () {
      expect(tomanFa.format(const Money(450000)), '۴۵۰٬۰۰۰');
    });
  });

  group('formatCompact', () {
    test('shortens large amounts', () {
      expect(toman.formatCompact(const Money(450000)), '450K');
      expect(toman.formatCompact(const Money(1200000)), '1.2M');
      expect(toman.formatCompact(const Money(3400000000)), '3.4B');
      expect(toman.formatCompact(const Money(999)), '999');
    });

    test('drops a trailing .0', () {
      expect(toman.formatCompact(const Money(2000000)), '2M');
    });
  });

  group('parse', () {
    test('accepts grouped, spaced, and Persian input', () {
      expect(toman.parse('450,000'), const Money(450000));
      expect(toman.parse('450 000'), const Money(450000));
      expect(toman.parse('۴۵۰٬۰۰۰'), const Money(450000));
    });

    test('accepts decimals for decimal currencies', () {
      expect(usd.parse('12.34'), const Money(1234));
      expect(usd.parse('12.3'), const Money(1230));
    });

    test('rejects junk rather than guessing', () {
      expect(toman.parse('abc'), isNull);
      expect(toman.parse(''), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/money/money_format_test.dart`
Expected: FAIL — `Digits` and `MoneyFormatter` are undefined.

- [ ] **Step 3: Implement digit handling and formatting**

`lib/src/money/digits.dart`:

```dart
/// Converts between Latin, Persian (U+06F0–U+06F9) and Arabic-Indic
/// (U+0660–U+0669) digits.
abstract final class Digits {
  static const _persianZero = 0x06F0;
  static const _arabicZero = 0x0660;
  static const _latinZero = 0x30;

  static String toLatin(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= _persianZero && rune <= _persianZero + 9) {
        buffer.writeCharCode(_latinZero + (rune - _persianZero));
      } else if (rune >= _arabicZero && rune <= _arabicZero + 9) {
        buffer.writeCharCode(_latinZero + (rune - _arabicZero));
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  static String toPersian(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= _latinZero && rune <= _latinZero + 9) {
        buffer.writeCharCode(_persianZero + (rune - _latinZero));
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }
}
```

`lib/src/money/money_format.dart`:

```dart
import 'currency.dart';
import 'digits.dart';
import 'money.dart';

/// Formats and parses [Money] for one currency and one digit style.
final class MoneyFormatter {
  const MoneyFormatter({required this.currency, required this.persianDigits});

  final Currency currency;
  final bool persianDigits;

  static const _latinGroupSeparator = ',';
  static const _persianGroupSeparator = '\u066C';

  String format(Money money) {
    final negative = money.isNegative;
    final units = money.abs().minorUnits;
    final divisor = currency.minorUnitsPerMajor;
    final major = units ~/ divisor;
    final minor = units % divisor;

    var text = _group(major.toString());
    if (currency.decimalDigits > 0) {
      text = '$text.${minor.toString().padLeft(currency.decimalDigits, '0')}';
    }
    if (negative) text = '-$text';
    return persianDigits ? Digits.toPersian(text) : text;
  }

  /// Short form for chart axes and dense lists, where full grouping is noise.
  String formatCompact(Money money) {
    final negative = money.isNegative;
    final major = money.abs().minorUnits ~/ currency.minorUnitsPerMajor;

    String text;
    if (major >= 1000000000) {
      text = '${_trim(major / 1000000000)}B';
    } else if (major >= 1000000) {
      text = '${_trim(major / 1000000)}M';
    } else if (major >= 1000) {
      text = '${_trim(major / 1000)}K';
    } else {
      text = major.toString();
    }
    if (negative) text = '-$text';
    return persianDigits ? Digits.toPersian(text) : text;
  }

  /// Returns null for input that is not a number. Never guesses.
  Money? parse(String input) {
    var text = Digits.toLatin(input).trim();
    text = text
        .replaceAll(_latinGroupSeparator, '')
        .replaceAll(_persianGroupSeparator, '')
        .replaceAll('\u00A0', '')
        .replaceAll(' ', '');
    if (text.isEmpty) return null;

    final negative = text.startsWith('-');
    if (negative) text = text.substring(1);

    final parts = text.split('.');
    if (parts.length > 2) return null;
    if (parts.any((p) => p.isNotEmpty && !_isDigits(p))) return null;
    if (parts[0].isEmpty && (parts.length == 1 || parts[1].isEmpty)) return null;

    final major = parts[0].isEmpty ? 0 : int.parse(parts[0]);
    var minor = 0;
    if (parts.length == 2 && currency.decimalDigits > 0) {
      final fraction = parts[1].padRight(currency.decimalDigits, '0');
      if (fraction.length > currency.decimalDigits) return null;
      minor = int.parse(fraction);
    } else if (parts.length == 2 && parts[1].isNotEmpty) {
      return null; // a fraction on a zero-decimal currency is an error
    }

    final total = major * currency.minorUnitsPerMajor + minor;
    return Money(negative ? -total : total);
  }

  static bool _isDigits(String s) {
    for (final unit in s.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return false;
    }
    return true;
  }

  String _group(String digits) {
    final separator = persianDigits ? _persianGroupSeparator : _latinGroupSeparator;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(separator);
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static String _trim(double value) {
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.truncate()
        ? rounded.truncate().toString()
        : rounded.toString();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart test test/money/money_format_test.dart`
Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add packages/nimbus_domain
git commit -m "feat: money formatting, parsing, and compact forms

Toman amounts run to seven digits, so grouping and K/M/B short forms are a
legibility requirement rather than polish. Parsing accepts Persian and
Arabic-Indic digits and returns null on junk instead of guessing."
```

---

### Task 5: DateKey, DateRange, and the calendar interface

**Files:**
- Create: `packages/nimbus_domain/lib/src/calendar/date_key.dart`, `packages/nimbus_domain/lib/src/calendar/calendar.dart`, `packages/nimbus_domain/lib/src/calendar/gregorian_calendar.dart`
- Test: `packages/nimbus_domain/test/calendar/date_key_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `DateKey(int value)` with `.year/.month/.day`, `DateKey.fromParts(y,m,d)`, `DateKey.fromDateTime(DateTime)`, `.toDateTime()`, `.addDays(int)`, `.daysUntil(DateKey)`, `Comparable`; `DateRange(startInclusive, endInclusive)` with `.contains(DateKey)`, `.dayCount`; `enum PeriodType { day, week, month, quarter, year }`; `enum CalendarKind { gregorian, jalali }`; `abstract interface class AppCalendar` with `kind`, `partsOf(DateKey)`, `keyOf(y,m,d)`, `monthLength(y,m)`, `periodContaining(DateKey, PeriodType, {int firstDayOfWeek})`, `shiftPeriod(DateRange, PeriodType, int)`; `GregorianCalendar()`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('DateKey', () {
    test('encodes and decodes yyyymmdd', () {
      final key = DateKey.fromParts(2026, 8, 20);
      expect(key.value, 20260820);
      expect((key.year, key.month, key.day), (2026, 8, 20));
    });

    test('round-trips through DateTime', () {
      final key = DateKey.fromParts(2026, 2, 28);
      expect(DateKey.fromDateTime(key.toDateTime()), key);
    });

    test('adds days across a month boundary', () {
      expect(DateKey.fromParts(2026, 1, 31).addDays(1), DateKey.fromParts(2026, 2, 1));
    });

    test('adds days across a leap day', () {
      expect(DateKey.fromParts(2024, 2, 28).addDays(1), DateKey.fromParts(2024, 2, 29));
      expect(DateKey.fromParts(2024, 2, 28).addDays(2), DateKey.fromParts(2024, 3, 1));
    });

    test('counts days between keys', () {
      expect(DateKey.fromParts(2026, 1, 1).daysUntil(DateKey.fromParts(2026, 1, 31)), 30);
    });

    test('sorts chronologically as integers', () {
      expect(DateKey.fromParts(2026, 1, 2).compareTo(DateKey.fromParts(2026, 1, 10)), lessThan(0));
    });
  });

  group('DateRange', () {
    test('contains its endpoints', () {
      final range = DateRange(DateKey.fromParts(2026, 8, 1), DateKey.fromParts(2026, 8, 31));
      expect(range.contains(DateKey.fromParts(2026, 8, 1)), isTrue);
      expect(range.contains(DateKey.fromParts(2026, 8, 31)), isTrue);
      expect(range.contains(DateKey.fromParts(2026, 9, 1)), isFalse);
      expect(range.dayCount, 31);
    });
  });

  group('GregorianCalendar', () {
    const cal = GregorianCalendar();

    test('month lengths include February in a leap year', () {
      expect(cal.monthLength(2026, 2), 28);
      expect(cal.monthLength(2024, 2), 29);
      expect(cal.monthLength(2026, 8), 31);
    });

    test('month period spans the whole month', () {
      final range = cal.periodContaining(DateKey.fromParts(2026, 8, 20), PeriodType.month);
      expect(range.startInclusive, DateKey.fromParts(2026, 8, 1));
      expect(range.endInclusive, DateKey.fromParts(2026, 8, 31));
    });

    test('week period respects the configured first day', () {
      // 2026-08-20 is a Thursday. With Monday(1) as first day the week is 17..23.
      final monday = cal.periodContaining(
        DateKey.fromParts(2026, 8, 20),
        PeriodType.week,
        firstDayOfWeek: DateTime.monday,
      );
      expect(monday.startInclusive, DateKey.fromParts(2026, 8, 17));
      expect(monday.endInclusive, DateKey.fromParts(2026, 8, 23));

      // With Saturday(6) as first day the week is 15..21.
      final saturday = cal.periodContaining(
        DateKey.fromParts(2026, 8, 20),
        PeriodType.week,
        firstDayOfWeek: DateTime.saturday,
      );
      expect(saturday.startInclusive, DateKey.fromParts(2026, 8, 15));
      expect(saturday.endInclusive, DateKey.fromParts(2026, 8, 21));
    });

    test('quarter and year periods', () {
      final q = cal.periodContaining(DateKey.fromParts(2026, 8, 20), PeriodType.quarter);
      expect(q.startInclusive, DateKey.fromParts(2026, 7, 1));
      expect(q.endInclusive, DateKey.fromParts(2026, 9, 30));

      final y = cal.periodContaining(DateKey.fromParts(2026, 8, 20), PeriodType.year);
      expect(y.startInclusive, DateKey.fromParts(2026, 1, 1));
      expect(y.endInclusive, DateKey.fromParts(2026, 12, 31));
    });

    test('shifts a month period backwards across a year boundary', () {
      final jan = cal.periodContaining(DateKey.fromParts(2026, 1, 15), PeriodType.month);
      final dec = cal.shiftPeriod(jan, PeriodType.month, -1);
      expect(dec.startInclusive, DateKey.fromParts(2025, 12, 1));
      expect(dec.endInclusive, DateKey.fromParts(2025, 12, 31));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/calendar/date_key_test.dart`
Expected: FAIL — `DateKey` is undefined.

- [ ] **Step 3: Implement DateKey, DateRange, and the calendar contract**

`lib/src/calendar/date_key.dart`:

```dart
import 'package:meta/meta.dart';

/// A local calendar date encoded as `yyyymmdd`.
///
/// Stored on every transaction so period queries are an indexed integer range
/// scan. Because Jalali and Gregorian dates are in bijection, one Gregorian
/// key serves both calendars: period boundaries are computed in the active
/// calendar and then converted to keys.
@immutable
final class DateKey implements Comparable<DateKey> {
  const DateKey(this.value);

  factory DateKey.fromParts(int year, int month, int day) =>
      DateKey(year * 10000 + month * 100 + day);

  factory DateKey.fromDateTime(DateTime local) =>
      DateKey.fromParts(local.year, local.month, local.day);

  final int value;

  int get year => value ~/ 10000;
  int get month => (value ~/ 100) % 100;
  int get day => value % 100;

  DateTime toDateTime() => DateTime(year, month, day);

  DateKey addDays(int days) {
    final shifted = DateTime(year, month, day + days);
    return DateKey.fromDateTime(shifted);
  }

  int daysUntil(DateKey other) =>
      other.toDateTime().difference(toDateTime()).inDays;

  @override
  int compareTo(DateKey other) => value.compareTo(other.value);

  bool operator <(DateKey other) => value < other.value;
  bool operator <=(DateKey other) => value <= other.value;
  bool operator >(DateKey other) => value > other.value;
  bool operator >=(DateKey other) => value >= other.value;

  @override
  bool operator ==(Object other) => other is DateKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DateKey($value)';
}

/// An inclusive span of dates.
@immutable
final class DateRange {
  const DateRange(this.startInclusive, this.endInclusive);

  final DateKey startInclusive;
  final DateKey endInclusive;

  bool contains(DateKey key) => key >= startInclusive && key <= endInclusive;

  int get dayCount => startInclusive.daysUntil(endInclusive) + 1;

  @override
  bool operator ==(Object other) =>
      other is DateRange &&
      other.startInclusive == startInclusive &&
      other.endInclusive == endInclusive;

  @override
  int get hashCode => Object.hash(startInclusive, endInclusive);

  @override
  String toString() => 'DateRange($startInclusive..$endInclusive)';
}
```

`lib/src/calendar/calendar.dart`:

```dart
import 'date_key.dart';

enum CalendarKind { gregorian, jalali }

enum PeriodType { day, week, month, quarter, year }

/// Year/month/day in a specific calendar system.
typedef CalendarParts = ({int year, int month, int day});

/// Every period calculation in the app goes through this interface.
///
/// "This month" is a different range in Jalali than in Gregorian, so goals,
/// budgets, and chart buckets must all be computed in the user's active
/// calendar rather than converted after the fact.
abstract interface class AppCalendar {
  CalendarKind get kind;

  /// Decomposes a Gregorian [DateKey] into this calendar's parts.
  CalendarParts partsOf(DateKey key);

  /// Builds a Gregorian [DateKey] from this calendar's parts.
  DateKey keyOf(int year, int month, int day);

  int monthLength(int year, int month);

  int monthsPerYear();

  DateRange periodContaining(
    DateKey key,
    PeriodType type, {
    int firstDayOfWeek,
  });

  DateRange shiftPeriod(DateRange range, PeriodType type, int delta);
}
```

`lib/src/calendar/gregorian_calendar.dart`:

```dart
import 'calendar.dart';
import 'date_key.dart';

final class GregorianCalendar implements AppCalendar {
  const GregorianCalendar();

  @override
  CalendarKind get kind => CalendarKind.gregorian;

  @override
  CalendarParts partsOf(DateKey key) =>
      (year: key.year, month: key.month, day: key.day);

  @override
  DateKey keyOf(int year, int month, int day) =>
      DateKey.fromParts(year, month, day);

  @override
  int monthsPerYear() => 12;

  @override
  int monthLength(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  @override
  DateRange periodContaining(
    DateKey key,
    PeriodType type, {
    int firstDayOfWeek = DateTime.monday,
  }) {
    switch (type) {
      case PeriodType.day:
        return DateRange(key, key);
      case PeriodType.week:
        final weekday = key.toDateTime().weekday; // Mon=1 .. Sun=7
        final offset = (weekday - firstDayOfWeek + 7) % 7;
        final start = key.addDays(-offset);
        return DateRange(start, start.addDays(6));
      case PeriodType.month:
        return DateRange(
          DateKey.fromParts(key.year, key.month, 1),
          DateKey.fromParts(key.year, key.month, monthLength(key.year, key.month)),
        );
      case PeriodType.quarter:
        final firstMonth = ((key.month - 1) ~/ 3) * 3 + 1;
        final lastMonth = firstMonth + 2;
        return DateRange(
          DateKey.fromParts(key.year, firstMonth, 1),
          DateKey.fromParts(key.year, lastMonth, monthLength(key.year, lastMonth)),
        );
      case PeriodType.year:
        return DateRange(
          DateKey.fromParts(key.year, 1, 1),
          DateKey.fromParts(key.year, 12, 31),
        );
    }
  }

  @override
  DateRange shiftPeriod(DateRange range, PeriodType type, int delta) {
    final start = range.startInclusive;
    switch (type) {
      case PeriodType.day:
        final moved = start.addDays(delta);
        return periodContaining(moved, type);
      case PeriodType.week:
        final moved = start.addDays(7 * delta);
        return periodContaining(moved, type, firstDayOfWeek: start.toDateTime().weekday);
      case PeriodType.month:
        return _shiftByMonths(start, delta, 1, PeriodType.month);
      case PeriodType.quarter:
        return _shiftByMonths(start, delta, 3, PeriodType.quarter);
      case PeriodType.year:
        return periodContaining(
          DateKey.fromParts(start.year + delta, start.month, 1),
          PeriodType.year,
        );
    }
  }

  DateRange _shiftByMonths(DateKey start, int delta, int step, PeriodType type) {
    final totalMonths = (start.year * 12 + (start.month - 1)) + delta * step;
    final year = totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    return periodContaining(DateKey.fromParts(year, month, 1), type);
  }
}
```

Export all three from `lib/nimbus_domain.dart`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart test test/calendar/date_key_test.dart`
Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add packages/nimbus_domain
git commit -m "feat: DateKey, DateRange, and the Gregorian calendar

Dates are stored as an indexed yyyymmdd integer so period queries are a range
scan. Period boundaries go through a calendar interface because 'this month'
differs between Jalali and Gregorian and must not be computed ad hoc."
```

---

### Task 6: Jalali calendar

**Files:**
- Create: `packages/nimbus_domain/lib/src/calendar/jalali_calendar.dart`
- Test: `packages/nimbus_domain/test/calendar/jalali_calendar_test.dart`

**Interfaces:**
- Consumes: `AppCalendar`, `DateKey`, `DateRange`, `PeriodType` from Task 5
- Produces: `JalaliCalendar()` implementing `AppCalendar` with `CalendarKind.jalali`.

Implementation note: depend only on `shamsi_date`'s core surface — the `Jalali(y, m, d)` constructor, `Jalali.fromDateTime(DateTime)`, `.toDateTime()`, and `.year/.month/.day`. Derive month length by differencing consecutive month starts rather than relying on a helper whose exact name is unverified, and derive weekday from `DateTime.weekday`, which is certain. Step 1 pins the library's behavior before anything is built on it.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:test/test.dart';

void main() {
  const cal = JalaliCalendar();

  group('library behaviour pins', () {
    test('Nowruz 1403 is 2024-03-20', () {
      final g = Jalali(1403, 1, 1).toDateTime();
      expect((g.year, g.month, g.day), (2024, 3, 20));
    });

    test('conversion round-trips for a decade of dates', () {
      var d = DateTime(2020, 1, 1);
      final end = DateTime(2030, 1, 1);
      while (d.isBefore(end)) {
        final j = Jalali.fromDateTime(d);
        final back = j.toDateTime();
        expect((back.year, back.month, back.day), (d.year, d.month, d.day));
        d = DateTime(d.year, d.month, d.day + 1);
      }
    });
  });

  group('JalaliCalendar', () {
    test('reports the Jalali parts of a Gregorian key', () {
      final parts = cal.partsOf(DateKey.fromParts(2024, 3, 20));
      expect(parts, (year: 1403, month: 1, day: 1));
    });

    test('builds a key from Jalali parts', () {
      expect(cal.keyOf(1403, 1, 1), DateKey.fromParts(2024, 3, 20));
    });

    test('first six months are 31 days, next five are 30', () {
      for (var m = 1; m <= 6; m++) {
        expect(cal.monthLength(1403, m), 31, reason: 'month $m');
      }
      for (var m = 7; m <= 11; m++) {
        expect(cal.monthLength(1403, m), 30, reason: 'month $m');
      }
    });

    test('Esfand is 29 or 30 days depending on the leap year', () {
      expect(cal.monthLength(1403, 12), anyOf(29, 30));
      final lengths = {
        for (var y = 1400; y <= 1410; y++) y: cal.monthLength(y, 12),
      };
      expect(lengths.values.toSet(), containsAll(<int>[29, 30]));
    });

    test('month period spans a whole Jalali month, not a Gregorian one', () {
      final range = cal.periodContaining(cal.keyOf(1403, 1, 15), PeriodType.month);
      expect(range.startInclusive, cal.keyOf(1403, 1, 1));
      expect(range.endInclusive, cal.keyOf(1403, 1, 31));
      expect(range.dayCount, 31);
    });

    test('year period spans the whole Jalali year', () {
      final range = cal.periodContaining(cal.keyOf(1403, 6, 10), PeriodType.year);
      expect(range.startInclusive, cal.keyOf(1403, 1, 1));
      expect(cal.partsOf(range.endInclusive).year, 1403);
      expect(cal.partsOf(range.endInclusive).month, 12);
      expect(range.dayCount, anyOf(365, 366));
    });

    test('week defaults to starting Saturday', () {
      final range = cal.periodContaining(
        DateKey.fromParts(2026, 8, 20),
        PeriodType.week,
        firstDayOfWeek: DateTime.saturday,
      );
      expect(range.startInclusive, DateKey.fromParts(2026, 8, 15));
      expect(range.dayCount, 7);
    });

    test('shifts a month period across the Jalali year boundary', () {
      final farvardin = cal.periodContaining(cal.keyOf(1403, 1, 10), PeriodType.month);
      final esfand = cal.shiftPeriod(farvardin, PeriodType.month, -1);
      expect(cal.partsOf(esfand.startInclusive), (year: 1402, month: 12, day: 1));
    });

    test('quarters group three Jalali months', () {
      final range = cal.periodContaining(cal.keyOf(1403, 5, 2), PeriodType.quarter);
      expect(cal.partsOf(range.startInclusive).month, 4);
      expect(cal.partsOf(range.endInclusive).month, 6);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/calendar/jalali_calendar_test.dart`
Expected: FAIL — `JalaliCalendar` is undefined. The two "library behaviour pins" tests should PASS; if either fails, stop and reconcile against the installed `shamsi_date` version before implementing anything.

- [ ] **Step 3: Implement JalaliCalendar**

```dart
import 'package:shamsi_date/shamsi_date.dart';

import 'calendar.dart';
import 'date_key.dart';

final class JalaliCalendar implements AppCalendar {
  const JalaliCalendar();

  @override
  CalendarKind get kind => CalendarKind.jalali;

  @override
  CalendarParts partsOf(DateKey key) {
    final j = Jalali.fromDateTime(key.toDateTime());
    return (year: j.year, month: j.month, day: j.day);
  }

  @override
  DateKey keyOf(int year, int month, int day) =>
      DateKey.fromDateTime(Jalali(year, month, day).toDateTime());

  @override
  int monthsPerYear() => 12;

  @override
  int monthLength(int year, int month) {
    // Difference consecutive month starts rather than trusting a helper:
    // this is correct for every leap rule the library implements.
    final start = keyOf(year, month, 1);
    final nextStart = month == 12 ? keyOf(year + 1, 1, 1) : keyOf(year, month + 1, 1);
    return start.daysUntil(nextStart);
  }

  @override
  DateRange periodContaining(
    DateKey key,
    PeriodType type, {
    int firstDayOfWeek = DateTime.saturday,
  }) {
    final parts = partsOf(key);
    switch (type) {
      case PeriodType.day:
        return DateRange(key, key);
      case PeriodType.week:
        final weekday = key.toDateTime().weekday; // Mon=1 .. Sun=7
        final offset = (weekday - firstDayOfWeek + 7) % 7;
        final start = key.addDays(-offset);
        return DateRange(start, start.addDays(6));
      case PeriodType.month:
        return _monthRange(parts.year, parts.month);
      case PeriodType.quarter:
        final firstMonth = ((parts.month - 1) ~/ 3) * 3 + 1;
        final lastMonth = firstMonth + 2;
        return DateRange(
          keyOf(parts.year, firstMonth, 1),
          _monthRange(parts.year, lastMonth).endInclusive,
        );
      case PeriodType.year:
        return DateRange(
          keyOf(parts.year, 1, 1),
          _monthRange(parts.year, 12).endInclusive,
        );
    }
  }

  @override
  DateRange shiftPeriod(DateRange range, PeriodType type, int delta) {
    final start = range.startInclusive;
    switch (type) {
      case PeriodType.day:
        return periodContaining(start.addDays(delta), type);
      case PeriodType.week:
        return periodContaining(
          start.addDays(7 * delta),
          type,
          firstDayOfWeek: start.toDateTime().weekday,
        );
      case PeriodType.month:
        return _shiftByMonths(start, delta, 1, PeriodType.month);
      case PeriodType.quarter:
        return _shiftByMonths(start, delta, 3, PeriodType.quarter);
      case PeriodType.year:
        final parts = partsOf(start);
        return periodContaining(keyOf(parts.year + delta, 1, 1), PeriodType.year);
    }
  }

  DateRange _monthRange(int year, int month) => DateRange(
        keyOf(year, month, 1),
        keyOf(year, month, monthLength(year, month)),
      );

  DateRange _shiftByMonths(DateKey start, int delta, int step, PeriodType type) {
    final parts = partsOf(start);
    final totalMonths = (parts.year * 12 + (parts.month - 1)) + delta * step;
    final year = totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    return periodContaining(keyOf(year, month, 1), type);
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart test test/calendar/`
Expected: PASS — both calendar suites green.

- [ ] **Step 5: Commit**

```bash
git add packages/nimbus_domain
git commit -m "feat: Jalali calendar behind the AppCalendar interface

Month lengths are derived by differencing consecutive month starts, which is
correct under whatever leap rule the library implements rather than
duplicating that rule here. Weekday comes from DateTime, which is unambiguous."
```

---

### Task 7: Entitlements

Everything ships unlocked. The machinery exists now so that switching gates on later is configuration, not surgery — and so founding users can be grandfathered rather than having features taken away.

**Files:**
- Create: `packages/nimbus_domain/lib/src/entitlements/feature.dart`, `packages/nimbus_domain/lib/src/entitlements/entitlements.dart`
- Test: `packages/nimbus_domain/test/entitlements/entitlements_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `enum Feature { unlimitedTemplates, advancedAnalytics, cloudBackup }`; `abstract interface class EntitlementSource { Set<Feature> get granted; }`; `AlwaysUnlockedSource`; `GrantedSetSource(Set<Feature>)`; `Entitlements({required EntitlementSource source, required bool isFoundingUser})` with `has(Feature)` and `isFoundingUser`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  test('everything is unlocked under the current source', () {
    final e = Entitlements(source: const AlwaysUnlockedSource(), isFoundingUser: false);
    for (final f in Feature.values) {
      expect(e.has(f), isTrue, reason: '$f should be unlocked');
    }
  });

  test('a founding user keeps every feature even under a restrictive source', () {
    final e = Entitlements(
      source: const GrantedSetSource(<Feature>{}),
      isFoundingUser: true,
    );
    for (final f in Feature.values) {
      expect(e.has(f), isTrue, reason: 'founding users are grandfathered');
    }
  });

  test('a non-founding user only gets what the source grants', () {
    final e = Entitlements(
      source: const GrantedSetSource(<Feature>{Feature.cloudBackup}),
      isFoundingUser: false,
    );
    expect(e.has(Feature.cloudBackup), isTrue);
    expect(e.has(Feature.advancedAnalytics), isFalse);
    expect(e.has(Feature.unlimitedTemplates), isFalse);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/entitlements/entitlements_test.dart`
Expected: FAIL — `Feature` is undefined.

- [ ] **Step 3: Implement entitlements**

`lib/src/entitlements/feature.dart`:

```dart
/// Features that may sit behind a paywall in a future release.
///
/// All are currently granted. They are enumerated now so that gate checks
/// live in one place from the start rather than being retrofitted across the
/// UI later.
enum Feature { unlimitedTemplates, advancedAnalytics, cloudBackup }
```

`lib/src/entitlements/entitlements.dart`:

```dart
import 'feature.dart';

abstract interface class EntitlementSource {
  Set<Feature> get granted;
}

/// The source used while the app is free. Swapped for a Play Billing backed
/// source when gates are switched on.
final class AlwaysUnlockedSource implements EntitlementSource {
  const AlwaysUnlockedSource();

  @override
  Set<Feature> get granted => Feature.values.toSet();
}

final class GrantedSetSource implements EntitlementSource {
  const GrantedSetSource(this.granted);

  @override
  final Set<Feature> granted;
}

final class Entitlements {
  const Entitlements({required this.source, required this.isFoundingUser});

  final EntitlementSource source;

  /// Set at first run before the early-access cutoff. Founding users retain
  /// full access permanently — a paywall that removes features people already
  /// use is a betrayal; one that grandfathers them is a gift.
  final bool isFoundingUser;

  bool has(Feature feature) =>
      isFoundingUser || source.granted.contains(feature);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart test`
Expected: PASS — the whole domain suite green.

- [ ] **Step 5: Commit**

```bash
git add packages/nimbus_domain
git commit -m "feat: entitlement layer with founding-user grandfathering

Gates are defined now and granted to everyone, so enabling them later is a
config change. Founding users keep full access permanently."
```

---

### Task 8: Database foundation, settings, and migration tooling

**Files:**
- Create: `packages/nimbus_data/lib/src/database/columns.dart`, `packages/nimbus_data/lib/src/database/converters.dart`, `packages/nimbus_data/lib/src/tables/settings_table.dart`, `packages/nimbus_data/lib/src/database/app_database.dart`
- Create: `packages/nimbus_data/test/database_test.dart`, `packages/nimbus_data/test/support/test_database.dart`

**Interfaces:**
- Consumes: `Money`, `DateKey` from the domain package
- Produces: `AppDatabase(QueryExecutor)` with `schemaVersion == 1`; `openTestDatabase()` returning an in-memory `AppDatabase`; `BaseColumns` mixin supplying `id`, `createdAt`, `updatedAt`, `deletedAt`; `DateKeyConverter`, `MoneyConverter`.

- [ ] **Step 1: Write the failing test**

`test/support/test_database.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:nimbus_data/nimbus_data.dart';

AppDatabase openTestDatabase() => AppDatabase(NativeDatabase.memory());
```

`test/database_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  test('opens at schema version 1', () async {
    expect(db.schemaVersion, 1);
    await db.customSelect('SELECT 1').get();
  });

  test('settings round-trip a value', () async {
    await db.settingsDao.put('currency', 'IRT');
    expect(await db.settingsDao.get('currency'), 'IRT');
  });

  test('settings return null for an unknown key rather than throwing', () async {
    expect(await db.settingsDao.get('nope'), isNull);
  });

  test('putting a key twice overwrites rather than duplicating', () async {
    await db.settingsDao.put('calendar', 'jalali');
    await db.settingsDao.put('calendar', 'gregorian');
    expect(await db.settingsDao.get('calendar'), 'gregorian');
    final rows = await db.customSelect(
      "SELECT COUNT(*) AS c FROM settings WHERE key = 'calendar'",
    ).getSingle();
    expect(rows.data['c'], 1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/nimbus_data && dart test`
Expected: FAIL — `AppDatabase` is undefined.

- [ ] **Step 3: Implement the base columns, converters, settings table, and database**

`lib/src/database/columns.dart`:

```dart
import 'package:drift/drift.dart';

/// Columns every table carries. UUIDv7 ids are time-ordered, so they index
/// well and remain stable if data ever has to merge across devices.
mixin BaseColumns on Table {
  TextColumn get id => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

`lib/src/database/converters.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

class DateKeyConverter extends TypeConverter<DateKey, int> {
  const DateKeyConverter();

  @override
  DateKey fromSql(int fromDb) => DateKey(fromDb);

  @override
  int toSql(DateKey value) => value.value;
}

class MoneyConverter extends TypeConverter<Money, int> {
  const MoneyConverter();

  @override
  Money fromSql(int fromDb) => Money(fromDb);

  @override
  int toSql(Money value) => value.minorUnits;
}
```

`lib/src/tables/settings_table.dart`:

```dart
import 'package:drift/drift.dart';

/// Key/value application settings. Deliberately not using BaseColumns —
/// settings are singleton values, not user records.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
```

`lib/src/database/app_database.dart`:

```dart
import 'package:drift/drift.dart';

import '../tables/settings_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  SettingsDao get settingsDao => SettingsDao(this);
}

class SettingsDao {
  SettingsDao(this._db);

  final AppDatabase _db;

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> put(String key, String value) =>
      _db.into(_db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(key: key, value: value),
          );
}
```

Run code generation:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Export `AppDatabase` and the DAO from `lib/nimbus_data.dart`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart test`
Expected: PASS, 4 tests.

- [ ] **Step 5: Set up migration snapshot tooling**

Confirm the CLI surface first rather than assuming it:

```bash
dart run drift_dev schema --help
```

Then export the version-1 snapshot:

```bash
dart run drift_dev schema dump lib/src/database/app_database.dart drift_schemas/
```

Expected: `drift_schemas/drift_schema_v1.json` exists. This snapshot is what later phases diff against when they add tables — without it, migration tests cannot verify that an upgrade produces the same schema as a fresh install.

- [ ] **Step 6: Commit**

```bash
git add packages/nimbus_data
git commit -m "feat: drift database foundation with settings and schema snapshot

Schema v1 is snapshotted so later phases can assert that migrating an old
database yields exactly the schema a fresh install creates."
```

---

### Task 9: Categories and tags with materialized-path hierarchy

Both are trees, and both need subtree rollup on every analytics query. A materialized path makes rollup an indexed prefix scan instead of a recursive query per aggregation.

**Files:**
- Create: `packages/nimbus_data/lib/src/tables/categories_table.dart`, `packages/nimbus_data/lib/src/tables/tags_table.dart`, `packages/nimbus_data/lib/src/tree/materialized_path.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart`
- Test: `packages/nimbus_data/test/tree/materialized_path_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `BaseColumns`
- Produces: `CategoriesDao` with `insertNode({id, name, parentId, ...})`, `subtreeOf(String id)`, `move(String id, String? newParentId)`, `descendantIdsViaCte(String id)`; identical shape for `TagsDao`. Path format is `/rootId/childId/` with leading and trailing slashes.

- [ ] **Step 1: Write the failing test**

The critical test verifies the fast path against a recursive CTE oracle — if the materialized path ever disagrees with the authoritative recursive query, every analytics number built on it is wrong.

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  Future<void> seedTree() async {
    await db.categoriesDao.insertNode(id: 'food', name: 'Food', parentId: null);
    await db.categoriesDao.insertNode(id: 'dining', name: 'Dining out', parentId: 'food');
    await db.categoriesDao.insertNode(id: 'fast', name: 'Fast food', parentId: 'dining');
    await db.categoriesDao.insertNode(id: 'grocery', name: 'Groceries', parentId: 'food');
    await db.categoriesDao.insertNode(id: 'transport', name: 'Transport', parentId: null);
  }

  test('builds paths with leading and trailing slashes', () async {
    await seedTree();
    final fast = await db.categoriesDao.byId('fast');
    expect(fast!.path, '/food/dining/fast/');
    expect(fast.depth, 2);

    final root = await db.categoriesDao.byId('food');
    expect(root!.path, '/food/');
    expect(root.depth, 0);
  });

  test('subtree includes the node and all descendants', () async {
    await seedTree();
    final ids = (await db.categoriesDao.subtreeOf('food')).map((c) => c.id).toSet();
    expect(ids, {'food', 'dining', 'fast', 'grocery'});
  });

  test('subtree of a leaf is just the leaf', () async {
    await seedTree();
    final ids = (await db.categoriesDao.subtreeOf('fast')).map((c) => c.id).toSet();
    expect(ids, {'fast'});
  });

  test('materialized path agrees with a recursive CTE oracle', () async {
    await seedTree();
    for (final id in ['food', 'dining', 'fast', 'grocery', 'transport']) {
      final viaPath = (await db.categoriesDao.subtreeOf(id)).map((c) => c.id).toSet();
      final viaCte = (await db.categoriesDao.descendantIdsViaCte(id)).toSet();
      expect(viaPath, viaCte, reason: 'subtree mismatch for $id');
    }
  });

  test('moving a node rewrites the paths of its whole subtree', () async {
    await seedTree();
    await db.categoriesDao.move('dining', 'transport');

    final dining = await db.categoriesDao.byId('dining');
    expect(dining!.path, '/transport/dining/');
    expect(dining.depth, 1);

    final fast = await db.categoriesDao.byId('fast');
    expect(fast!.path, '/transport/dining/fast/');
    expect(fast.depth, 2);

    final foodSubtree = (await db.categoriesDao.subtreeOf('food')).map((c) => c.id).toSet();
    expect(foodSubtree, {'food', 'grocery'});
  });

  test('moving a node to the root works', () async {
    await seedTree();
    await db.categoriesDao.move('dining', null);
    final dining = await db.categoriesDao.byId('dining');
    expect(dining!.path, '/dining/');
    expect(dining.depth, 0);
  });

  test('a node cannot be moved beneath its own descendant', () async {
    await seedTree();
    expect(
      () => db.categoriesDao.move('food', 'fast'),
      throwsArgumentError,
    );
  });

  test('tags support the same nesting', () async {
    await db.tagsDao.insertNode(id: 'travel', name: 'travel', parentId: null);
    await db.tagsDao.insertNode(id: 'turkey', name: 'turkey-2026', parentId: 'travel');
    final ids = (await db.tagsDao.subtreeOf('travel')).map((t) => t.id).toSet();
    expect(ids, {'travel', 'turkey'});
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/tree/materialized_path_test.dart`
Expected: FAIL — `categoriesDao` is undefined.

- [ ] **Step 3: Implement the tables and the path service**

`lib/src/tables/categories_table.dart`:

```dart
import 'package:drift/drift.dart';

import '../database/columns.dart';

class Categories extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get iconKey => text().withDefault(const Constant('tag'))();
  IntColumn get color => integer().withDefault(const Constant(0xFF9E9E9E))();
  TextColumn get parentId => text().nullable().references(Categories, #id)();

  /// Materialized path, e.g. `/food/dining/fast/`. Subtree rollup is then
  /// `WHERE path LIKE '/food/%'` on an index rather than a recursive query.
  TextColumn get path => text()();
  IntColumn get depth => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get kind => text().withDefault(const Constant('expense'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}
```

`lib/src/tables/tags_table.dart` is identical in shape, without `kind`, plus:

```dart
  IntColumn get usageCount => integer().withDefault(const Constant(0))();
```

`lib/src/tree/materialized_path.dart`:

```dart
/// Path helpers shared by the category and tag trees.
abstract final class MaterializedPath {
  static String childPath(String? parentPath, String id) =>
      '${parentPath ?? '/'}$id/';

  static int depthOf(String path) =>
      path.split('/').where((s) => s.isNotEmpty).length - 1;

  static bool isDescendant({required String path, required String ancestorPath}) =>
      path.startsWith(ancestorPath) && path != ancestorPath;

  /// Rewrites [path] so the segment rooted at [oldAncestorPath] now sits under
  /// [newAncestorPath].
  static String reparent({
    required String path,
    required String oldAncestorPath,
    required String newAncestorPath,
  }) =>
      newAncestorPath + path.substring(oldAncestorPath.length);
}
```

Add both tables to `@DriftDatabase(tables: [...])`, bump nothing (still schema version 1 — no release has shipped), regenerate, then implement `CategoriesDao`:

```dart
class CategoriesDao {
  CategoriesDao(this._db);
  final AppDatabase _db;

  Future<Category?> byId(String id) =>
      (_db.select(_db.categories)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertNode({
    required String id,
    required String name,
    required String? parentId,
    String iconKey = 'tag',
    int color = 0xFF9E9E9E,
  }) async {
    String path;
    if (parentId == null) {
      path = MaterializedPath.childPath(null, id);
    } else {
      final parent = await byId(parentId);
      if (parent == null) {
        throw ArgumentError.value(parentId, 'parentId', 'No such category');
      }
      path = MaterializedPath.childPath(parent.path, id);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            id: id,
            name: name,
            parentId: Value(parentId),
            path: path,
            depth: MaterializedPath.depthOf(path),
            iconKey: Value(iconKey),
            color: Value(color),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<List<Category>> subtreeOf(String id) async {
    final node = await byId(id);
    if (node == null) return const [];
    return (_db.select(_db.categories)
          ..where((t) => t.path.like('${node.path}%'))
          ..where((t) => t.deletedAt.isNull()))
        .get();
  }

  /// Authoritative but slower. Used as the oracle in tests to prove the
  /// materialized path stays correct.
  Future<List<String>> descendantIdsViaCte(String id) async {
    final rows = await _db.customSelect(
      '''
      WITH RECURSIVE tree(id) AS (
        SELECT id FROM categories WHERE id = ?1
        UNION ALL
        SELECT c.id FROM categories c JOIN tree t ON c.parent_id = t.id
      )
      SELECT id FROM tree
      ''',
      variables: [Variable<String>(id)],
    ).get();
    return rows.map((r) => r.read<String>('id')).toList();
  }

  Future<void> move(String id, String? newParentId) async {
    final node = await byId(id);
    if (node == null) throw ArgumentError.value(id, 'id', 'No such category');

    String newParentPath;
    if (newParentId == null) {
      newParentPath = '/';
    } else {
      final parent = await byId(newParentId);
      if (parent == null) {
        throw ArgumentError.value(newParentId, 'newParentId', 'No such category');
      }
      if (MaterializedPath.isDescendant(
            path: parent.path,
            ancestorPath: node.path,
          ) ||
          parent.id == node.id) {
        throw ArgumentError.value(
          newParentId,
          'newParentId',
          'Cannot move a node beneath its own descendant',
        );
      }
      newParentPath = parent.path;
    }

    final oldPath = node.path;
    final newPath = MaterializedPath.childPath(newParentPath, id);

    await _db.transaction(() async {
      final affected = await (_db.select(_db.categories)
            ..where((t) => t.path.like('$oldPath%')))
          .get();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in affected) {
        final rewritten = MaterializedPath.reparent(
          path: row.path,
          oldAncestorPath: oldPath,
          newAncestorPath: newPath,
        );
        await (_db.update(_db.categories)..where((t) => t.id.equals(row.id))).write(
          CategoriesCompanion(
            path: Value(rewritten),
            depth: Value(MaterializedPath.depthOf(rewritten)),
            parentId: row.id == id ? Value(newParentId) : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }
}
```

`TagsDao` mirrors this against the `tags` table.

Add indexes in `MigrationStrategy.onCreate`:

```dart
await customStatement('CREATE INDEX idx_categories_path ON categories(path)');
await customStatement('CREATE INDEX idx_tags_path ON tags(path)');
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart test`
Expected: PASS, 12 tests.

- [ ] **Step 5: Commit**

```bash
git add packages/nimbus_data
git commit -m "feat: category and tag trees with materialized paths

Subtree rollup is an indexed prefix scan rather than a recursive query per
aggregation. A test asserts the fast path agrees with a recursive CTE oracle,
because a silent disagreement would corrupt every analytics number."
```

---

### Task 10: Transactions, payment methods, and the tag join

**Files:**
- Create: `packages/nimbus_data/lib/src/tables/payment_methods_table.dart`, `packages/nimbus_data/lib/src/tables/transactions_table.dart`, `packages/nimbus_data/lib/src/tables/transaction_tags_table.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart`
- Test: `packages/nimbus_data/test/transactions_test.dart`

**Interfaces:**
- Consumes: `Money`, `DateKey`, converters, `CategoriesDao`
- Produces: `TransactionsDao` with `insertTransaction(...)`, `byId(String)`, `inRange(DateRange, {bool confirmedOnly})`, `setTags(String txId, List<String> tagIds)`, `tagsOf(String txId)`, `totalInRange(DateRange)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await db.categoriesDao.insertNode(id: 'food', name: 'Food', parentId: null);
    await db.categoriesDao.insertNode(id: 'uncat', name: 'Uncategorized', parentId: null);
    await db.tagsDao.insertNode(id: 'travel', name: 'travel', parentId: null);
    await db.tagsDao.insertNode(id: 'work', name: 'work', parentId: null);
  });
  tearDown(() => db.close());

  Future<String> addExpense({
    required int amount,
    required DateKey on,
    String category = 'food',
    bool confirmed = true,
  }) async {
    final id = 'tx-${on.value}-$amount';
    await db.transactionsDao.insertTransaction(
      id: id,
      direction: TxDirection.expense,
      amount: Money(amount),
      currencyCode: 'IRT',
      occurredAtUtc: on.toDateTime().millisecondsSinceEpoch,
      localDateKey: on,
      categoryId: category,
      source: TxSource.manual,
      isConfirmed: confirmed,
    );
    return id;
  }

  test('stores and reads back an exact amount', () async {
    final id = await addExpense(amount: 450000, on: DateKey.fromParts(2026, 8, 20));
    final tx = await db.transactionsDao.byId(id);
    expect(tx!.amount, const Money(450000));
    expect(tx.localDateKey, DateKey.fromParts(2026, 8, 20));
    expect(tx.isConfirmed, isTrue);
  });

  test('queries by date range inclusively', () async {
    await addExpense(amount: 100, on: DateKey.fromParts(2026, 8, 1));
    await addExpense(amount: 200, on: DateKey.fromParts(2026, 8, 31));
    await addExpense(amount: 300, on: DateKey.fromParts(2026, 9, 1));

    final august = DateRange(DateKey.fromParts(2026, 8, 1), DateKey.fromParts(2026, 8, 31));
    final rows = await db.transactionsDao.inRange(august);
    expect(rows.map((t) => t.amount.minorUnits).toSet(), {100, 200});
    expect(await db.transactionsDao.totalInRange(august), const Money(300));
  });

  test('can exclude unconfirmed captures', () async {
    final range = DateRange(DateKey.fromParts(2026, 8, 1), DateKey.fromParts(2026, 8, 31));
    await addExpense(amount: 100, on: DateKey.fromParts(2026, 8, 5));
    await addExpense(amount: 900, on: DateKey.fromParts(2026, 8, 6), confirmed: false);

    expect((await db.transactionsDao.inRange(range)).length, 2);
    expect((await db.transactionsDao.inRange(range, confirmedOnly: true)).length, 1);
  });

  test('assigns and replaces tags', () async {
    final id = await addExpense(amount: 500, on: DateKey.fromParts(2026, 8, 20));
    await db.transactionsDao.setTags(id, ['travel', 'work']);
    expect((await db.transactionsDao.tagsOf(id)).toSet(), {'travel', 'work'});

    await db.transactionsDao.setTags(id, ['travel']);
    expect((await db.transactionsDao.tagsOf(id)).toSet(), {'travel'});
  });

  test('the same tag cannot be attached twice', () async {
    final id = await addExpense(amount: 500, on: DateKey.fromParts(2026, 8, 20));
    await db.transactionsDao.setTags(id, ['travel', 'travel']);
    expect((await db.transactionsDao.tagsOf(id)).length, 1);
  });

  test('deleting a transaction removes its tag links', () async {
    final id = await addExpense(amount: 500, on: DateKey.fromParts(2026, 8, 20));
    await db.transactionsDao.setTags(id, ['travel']);
    await db.transactionsDao.deleteTransaction(id);
    expect(await db.transactionsDao.tagsOf(id), isEmpty);
  });

  test('rejects a transaction with a category that does not exist', () async {
    expect(
      () => addExpense(amount: 1, on: DateKey.fromParts(2026, 8, 20), category: 'ghost'),
      throwsA(anything),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/transactions_test.dart`
Expected: FAIL — `transactionsDao` is undefined.

- [ ] **Step 3: Implement the tables and DAO**

`lib/src/tables/transactions_table.dart`:

```dart
import 'package:drift/drift.dart';

import '../database/columns.dart';
import '../database/converters.dart';
import 'categories_table.dart';
import 'payment_methods_table.dart';

enum TxDirection { expense, income }

enum TxSource { manual, sms, notification, widget }

enum Necessity { needed, optional, avoidable }

enum Satisfaction { glad, neutral, regret }

class Transactions extends Table with BaseColumns {
  TextColumn get direction => textEnum<TxDirection>()();
  IntColumn get amount => integer().map(const MoneyConverter())();
  TextColumn get currencyCode => text().withLength(min: 3, max: 8)();

  IntColumn get occurredAtUtc => integer()();

  /// Local Gregorian yyyymmdd. Indexed; every period query is a range scan
  /// against this column in both calendars.
  IntColumn get localDateKey => integer().map(const DateKeyConverter())();
  IntColumn get tzOffsetMinutes => integer().withDefault(const Constant(0))();

  /// Required. A system "Uncategorized" row is used for captures awaiting
  /// review, so no chart ever has a hole in it.
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get paymentMethodId =>
      text().nullable().references(PaymentMethods, #id)();

  TextColumn get merchant => text().nullable()();
  TextColumn get note => text().nullable()();

  TextColumn get necessity => textEnum<Necessity>().nullable()();
  TextColumn get satisfaction => textEnum<Satisfaction>().nullable()();

  TextColumn get source => textEnum<TxSource>()();
  BoolColumn get isConfirmed => boolean().withDefault(const Constant(true))();
  TextColumn get captureId => text().nullable()();
}
```

`lib/src/tables/transaction_tags_table.dart`:

```dart
import 'package:drift/drift.dart';

import 'tags_table.dart';
import 'transactions_table.dart';

class TransactionTags extends Table {
  TextColumn get transactionId => text().references(Transactions, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column<Object>> get primaryKey => {transactionId, tagId};
}
```

`lib/src/tables/payment_methods_table.dart` uses `BaseColumns` plus `name`, `kind` (text enum `cash|card|bank|other`), `last4` (nullable text), `color`, `iconKey`, `archived`.

Add the indexes in `onCreate`:

```dart
await customStatement('CREATE INDEX idx_tx_date ON transactions(local_date_key)');
await customStatement('CREATE INDEX idx_tx_category ON transactions(category_id)');
await customStatement(
    'CREATE INDEX idx_tx_unconfirmed ON transactions(is_confirmed, local_date_key)');
await customStatement('CREATE INDEX idx_tx_merchant ON transactions(merchant)');
await customStatement('CREATE INDEX idx_txtags_tag ON transaction_tags(tag_id)');
```

`TransactionsDao`:

```dart
class TransactionsDao {
  TransactionsDao(this._db);
  final AppDatabase _db;

  Future<void> insertTransaction({
    required String id,
    required TxDirection direction,
    required Money amount,
    required String currencyCode,
    required int occurredAtUtc,
    required DateKey localDateKey,
    required String categoryId,
    required TxSource source,
    bool isConfirmed = true,
    String? paymentMethodId,
    String? merchant,
    String? note,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            direction: direction,
            amount: amount,
            currencyCode: currencyCode,
            occurredAtUtc: occurredAtUtc,
            localDateKey: localDateKey,
            categoryId: categoryId,
            source: source,
            isConfirmed: Value(isConfirmed),
            paymentMethodId: Value(paymentMethodId),
            merchant: Value(merchant),
            note: Value(note),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<Transaction?> byId(String id) =>
      (_db.select(_db.transactions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<List<Transaction>> inRange(DateRange range,
      {bool confirmedOnly = false}) {
    final query = _db.select(_db.transactions)
      ..where((t) => t.localDateKey.isBetweenValues(
            range.startInclusive.value,
            range.endInclusive.value,
          ))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.localDateKey)]);
    if (confirmedOnly) {
      query.where((t) => t.isConfirmed.equals(true));
    }
    return query.get();
  }

  Future<Money> totalInRange(DateRange range) async {
    final rows = await inRange(range);
    return Money.sum(rows.map((t) => t.amount));
  }

  Future<void> setTags(String transactionId, List<String> tagIds) async {
    await _db.transaction(() async {
      await (_db.delete(_db.transactionTags)
            ..where((t) => t.transactionId.equals(transactionId)))
          .go();
      for (final tagId in tagIds.toSet()) {
        await _db.into(_db.transactionTags).insert(
              TransactionTagsCompanion.insert(
                transactionId: transactionId,
                tagId: tagId,
              ),
            );
      }
    });
  }

  Future<List<String>> tagsOf(String transactionId) async {
    final rows = await (_db.select(_db.transactionTags)
          ..where((t) => t.transactionId.equals(transactionId)))
        .get();
    return rows.map((r) => r.tagId).toList();
  }

  Future<void> deleteTransaction(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.transactionTags)
            ..where((t) => t.transactionId.equals(id)))
          .go();
      await (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
    });
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `dart test`
Expected: PASS — full data suite green, 19 tests.

- [ ] **Step 5: Re-dump the schema snapshot**

```bash
dart run drift_dev schema dump lib/src/database/app_database.dart drift_schemas/
```

- [ ] **Step 6: Commit**

```bash
git add packages/nimbus_data
git commit -m "feat: transactions, payment methods, and tag links

Category is required and defaults to a system Uncategorized row so captured
expenses awaiting review still appear in every chart rather than vanishing."
```

---

### Task 11: Localization, RTL, and design tokens

**Files:**
- Create: `app/l10n.yaml`, `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_fa.arb`, `packages/nimbus_design/lib/src/tokens.dart`, `packages/nimbus_design/lib/src/theme.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/localization_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `AppLocalizations` generated for `en` and `fa`; `NimbusTokens` (spacing, radii, colors, type ramp); `NimbusTheme.light()`, `NimbusTheme.dark()`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

void main() {
  Widget harness(Locale locale) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Text(AppLocalizations.of(context)!.appTitle),
        ),
      );

  testWidgets('renders English left-to-right', (tester) async {
    await tester.pumpWidget(harness(const Locale('en')));
    expect(Directionality.of(tester.element(find.byType(Text))), TextDirection.ltr);
    expect(find.text('NimbuStats'), findsOneWidget);
  });

  testWidgets('renders Persian right-to-left', (tester) async {
    await tester.pumpWidget(harness(const Locale('fa')));
    expect(Directionality.of(tester.element(find.byType(Text))), TextDirection.rtl);
  });

  test('both locales define the same keys', () {
    // Guards against a string being added to one ARB and forgotten in the other.
    expect(AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
        {'en', 'fa'});
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && flutter test test/localization_test.dart`
Expected: FAIL — `app_localizations.dart` does not exist.

- [ ] **Step 3: Add localization configuration and ARB files**

`app/l10n.yaml`:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
```

`app/lib/l10n/app_en.arb`:

```json
{
  "@@locale": "en",
  "appTitle": "NimbuStats",
  "addExpense": "Add expense",
  "amount": "Amount",
  "category": "Category",
  "uncategorized": "Uncategorized",
  "currency_toman": "Toman",
  "currency_usd": "USD",
  "currency_eur": "EUR",
  "currency_try": "TRY"
}
```

`app/lib/l10n/app_fa.arb`:

```json
{
  "@@locale": "fa",
  "appTitle": "NimbuStats",
  "addExpense": "افزودن هزینه",
  "amount": "مبلغ",
  "category": "دسته‌بندی",
  "uncategorized": "دسته‌بندی‌نشده",
  "currency_toman": "تومان",
  "currency_usd": "دلار",
  "currency_eur": "یورو",
  "currency_try": "لیر"
}
```

- [ ] **Step 4: Implement design tokens and theme**

`packages/nimbus_design/lib/src/tokens.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Single source of truth for spacing, radii, and colour.
///
/// These are placeholders until the Claude Design token sheet lands; the point
/// of naming them now is that every screen references tokens rather than
/// literals, so swapping in the real values is one file.
abstract final class NimbusTokens {
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space6 = 24.0;
  static const space8 = 32.0;

  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 20.0;

  static const seed = Color(0xFF2E7D64);

  /// Minimum tap target. Primary actions sit in the bottom third of the screen
  /// so they stay within one-handed reach.
  static const minTapTarget = 48.0;
}
```

`packages/nimbus_design/lib/src/theme.dart`:

```dart
import 'package:flutter/material.dart';

import 'tokens.dart';

abstract final class NimbusTheme {
  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: NimbusTokens.seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
    );
  }
}
```

`app/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nimbus_design/nimbus_design.dart';

import 'l10n/app_localizations.dart';

void main() => runApp(const NimbuStatsApp());

class NimbuStatsApp extends StatelessWidget {
  const NimbuStatsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: NimbusTheme.light(),
        darkTheme: NimbusTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fa'),
        home: const Scaffold(body: Center(child: Text('NimbuStats'))),
      );
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test`
Expected: PASS, 3 tests. Flutter generates `app_localizations.dart` during `flutter pub get` / build because `generate: true` is set in `app/pubspec.yaml`.

- [ ] **Step 6: Commit**

```bash
git add app packages/nimbus_design
git commit -m "feat: fa/en localization with RTL and design token scaffold

Persian is the default locale so RTL is the path exercised by default rather
than an afterthought that breaks when it is finally switched on."
```

---

### Task 12: Screen contract

This is the deliverable that unblocks design work. It is a document, not code, and it must be written before any screen exists — designing without knowing each screen's states produces screens that cannot be built.

**Files:**
- Create: `docs/superpowers/screen-contract.md`

**Interfaces:**
- Consumes: everything above (the contract references real types — `Money`, `DateRange`, `Category`, `Transaction`)
- Produces: a document consumed by Claude Design and by every later UI phase.

- [ ] **Step 1: Write the contract**

For **each** screen in the inventory below, document exactly five things:

1. **Purpose** — one sentence.
2. **Data in** — the concrete types the screen reads (e.g. `List<Transaction>`, `DateRange`, `MoneyFormatter`).
3. **States** — `empty`, `loading`, `error`, `populated`, and every degenerate case worth designing: a nine-digit Toman amount, a forty-character merchant name, twenty tags on one expense, a category tree six levels deep, a failed SMS parse.
4. **Actions out** — the events the screen emits (e.g. `onAmountSubmitted(Money)`, `onCategorySelected(String id)`).
5. **UX budget** — the tap count and latency target from Global Constraints that applies.

Screens: onboarding · dashboard · add/edit transaction · transaction list · review inbox · teach-template · category manager · tag manager · analytics breakdown · analytics trends · analytics cross-tab · analytics patterns · regret matrix · saved-view builder · trackers · tracker detail · goals · goal editor · settings.

Mark each screen with the phase that builds it, so design effort can be sequenced to match the build.

- [ ] **Step 2: Add the RTL and numeral rules**

Document explicitly, because these are the constraints most often missed and most expensive to retrofit:

- Every layout is authored RTL first; LTR is derived.
- Numerals render as Persian digits in `fa` and Latin in `en`.
- Amounts use `formatCompact` on chart axes and in dense lists, `format` in detail views.
- Tag breakdown charts **must** carry a note that percentages do not sum to 100, because an expense with several tags counts in several buckets.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/screen-contract.md
git commit -m "docs: screen contract for design work

Written before any UI exists so design has a stable target: every screen's
states, data, actions, and UX budget are fixed up front."
```

- [ ] **Step 4: Verify Phase 0 end to end**

```bash
dart analyze --fatal-infos
dart test test/architecture_test.dart
cd packages/nimbus_domain && dart test && cd ../..
cd packages/nimbus_data && dart test && cd ../..
cd app && flutter test && cd ..
```

Expected: analyzer clean, all suites green. Phase 0 is complete when this sequence passes and `docs/superpowers/screen-contract.md` exists.

- [ ] **Step 5: Tag the phase**

```bash
git tag phase-0-complete   # gate tag: later phases verify this exists
git tag pre-phase-1        # rollback target for Phase 1
```

---

## Self-Review

**Spec coverage.** Phase 0 in the design doc lists: package scaffold with enforced boundaries (Task 2), drift schema + migrations (Tasks 8–10), CI (Task 2), pure-domain money and calendar with full unit tests (Tasks 3–6), RTL + fa/en localization (Task 11), entitlement layer (Task 7), and the screen contract (Task 12). Toolchain installation (Task 1) is additional — it was discovered during planning that nothing is installed on this machine.

**Deferred deliberately.** The capture, analytics, goal, tracker, and saved-view tables are *not* created here. Drift migrations are routine, and untested unused tables are a liability; each later phase adds its own tables and exercises the migration path in the process. This does not weaken the design's "get the model right on day one" premise, which is about the labeling model — category tree, nestable tags, necessity/satisfaction — all of which exist in Task 9 and Task 10.

**Known uncertainty, flagged rather than hidden.** Task 1 Step 5 empirically verifies that native SQLite loads for host tests, since `sqlite3_flutter_libs` is EOL and the replacement mechanism could not be confirmed without an installed toolchain. Task 6 Step 2 pins `shamsi_date`'s behavior before anything is built on it. Task 8 Step 5 confirms the `drift_dev schema` CLI surface rather than assuming it. If any of the three disagrees with what is written here, stop and reconcile before continuing.

**Type consistency.** `DateKey`, `DateRange`, `Money`, `Currency`, `PeriodType`, `AppCalendar`, `Feature`, `TxDirection`, `TxSource`, `Necessity`, and `Satisfaction` are defined once and referenced with identical names throughout. DAO accessors are `categoriesDao`, `tagsDao`, `transactionsDao`, `settingsDao` everywhere.
