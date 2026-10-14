import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';
import 'goal_kind.dart';
import 'goal_providers.dart';

/// What the editor starts from: the goal being edited and its tracker, or
/// nothing for a new goal. A deleted tracker arrives as null, and the form
/// then asks for another.
typedef GoalEditorSeed = ({Goal? goal, Tracker? tracker});

/// Why the draft cannot be saved yet (spec §5.3). [targetMissing] blocks the
/// save without an inline message: an empty field says enough.
enum GoalEditorError {
  nameBlank,
  targetMissing,
  targetInvalid,
  targetNotWhole,
  targetZero,
  endBeforeStart,
  trackerMissing,
}

const _keep = Object();

/// Everything the editor has collected.
///
/// The target is held as text, as the add-expense screen holds its amount.
/// Parsing happens when the draft is read, so `1.` is something the user is
/// typing rather than a value to represent.
///
/// Filters the editor does not show ([baseFilters]: payment methods,
/// necessity, …) and a tag filter it did not touch ([tags]) are carried over
/// unchanged. An edit then cannot quietly widen a goal.
@immutable
final class GoalEditorState {
  const GoalEditorState({
    required this.id,
    required this.kind,
    required this.name,
    required this.nameEdited,
    required this.targetText,
    required this.categoryPaths,
    required this.tags,
    required this.baseFilters,
    required this.tracker,
    required this.period,
    required this.since,
    required this.start,
    required this.end,
    required this.calendar,
    required this.weekStart,
    required this.alertPercents,
    required this.active,
  });

  final String id;

  /// Null until a new goal's kind is chosen.
  final GoalKind? kind;
  final String name;

  /// False while [name] is the editor's suggestion, which then follows the
  /// scope: the category's name, the tracker's.
  final bool nameEdited;
  final String targetText;

  /// Empty for all expenses. Written as the picked category's current path.
  final List<String> categoryPaths;
  final TagFilter? tags;
  final QueryFilters baseFilters;
  final Tracker? tracker;
  final PeriodType period;

  /// A recurring goal's history starts with the period containing it: today
  /// for a new goal, kept for an edited one.
  final DateKey since;
  final DateKey start;
  final DateKey end;
  final CalendarKind calendar;
  final int weekStart;
  final List<int> alertPercents;
  final bool active;

  GoalEditorState copyWith({
    GoalKind? kind,
    String? name,
    bool? nameEdited,
    String? targetText,
    List<String>? categoryPaths,
    Object? tags = _keep,
    QueryFilters? baseFilters,
    Tracker? tracker,
    PeriodType? period,
    DateKey? start,
    DateKey? end,
    CalendarKind? calendar,
    List<int>? alertPercents,
  }) => GoalEditorState(
    id: id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    nameEdited: nameEdited ?? this.nameEdited,
    targetText: targetText ?? this.targetText,
    categoryPaths: categoryPaths ?? this.categoryPaths,
    // A sentinel, because null means "no tag filter" here.
    tags: identical(tags, _keep) ? this.tags : tags as TagFilter?,
    baseFilters: baseFilters ?? this.baseFilters,
    tracker: tracker ?? this.tracker,
    period: period ?? this.period,
    since: since,
    start: start ?? this.start,
    end: end ?? this.end,
    calendar: calendar ?? this.calendar,
    weekStart: weekStart,
    alertPercents: alertPercents ?? this.alertPercents,
    active: active,
  );
}

/// Every reason [state] cannot be saved. Empty means [goalDraft] builds.
///
/// These are the checks `Goal`'s constructor makes that a user can trip
/// (spec §5.3), so a draft that passes here never throws there. Zero is
/// refused only for an at-least goal: a limit of zero is legitimate.
Set<GoalEditorError> goalEditorErrors(
  GoalEditorState state,
  MoneyFormatter money,
) {
  final kind = state.kind;
  if (kind == null) return const {};
  final target = _targetOf(state, money);
  return {
    if (state.name.trim().isEmpty) GoalEditorError.nameBlank,
    if (state.targetText.trim().isEmpty)
      GoalEditorError.targetMissing
    else if (_fractionOfWholeCount(state))
      GoalEditorError.targetNotWhole
    else if (target == null)
      GoalEditorError.targetInvalid
    else if (kind.direction == GoalDirection.atLeast && target.isZero)
      GoalEditorError.targetZero,
    if (kind.isHabit && state.tracker == null) GoalEditorError.trackerMissing,
    if (kind == GoalKind.savingsTarget && state.end < state.start)
      GoalEditorError.endBeforeStart,
  };
}

/// The goal [state] describes, or null while anything blocks the save.
Goal? goalDraft(GoalEditorState state, MoneyFormatter money) {
  final kind = state.kind;
  if (kind == null || goalEditorErrors(state, money).isNotEmpty) return null;
  final base = state.baseFilters;
  return Goal(
    id: state.id,
    name: state.name.trim(),
    metric: switch (kind) {
      GoalKind.spendingCap => GoalMetric.moneySum,
      GoalKind.savingsTarget => GoalMetric.netSavings,
      GoalKind.habitLimit ||
      GoalKind.habitGoal => habitMetricFor(state.tracker!.type),
    },
    scope: switch (kind) {
      GoalKind.spendingCap => MoneyScope(
        QueryFilters(
          direction: base.direction,
          categorySubtreePaths: state.categoryPaths,
          tags: state.tags,
          paymentMethodIds: base.paymentMethodIds,
          necessity: base.necessity,
          satisfaction: base.satisfaction,
          amountRange: base.amountRange,
          confirmedOnly: base.confirmedOnly,
          searchText: base.searchText,
        ),
      ),
      // All transactions, both directions (spec §5.3).
      GoalKind.savingsTarget => MoneyScope(base),
      GoalKind.habitLimit ||
      GoalKind.habitGoal => TrackerScope(state.tracker!.id),
    },
    direction: kind.direction,
    target: _targetOf(state, money)!,
    period: kind == GoalKind.savingsTarget
        ? FixedRangePeriod(DateRange(state.start, state.end))
        : RecurringPeriod(state.period, state.since),
    calendar: state.calendar,
    weekStart: state.weekStart,
    alertPercents: state.alertPercents,
    active: state.active,
  );
}

GoalAmount? _targetOf(GoalEditorState state, MoneyFormatter money) {
  final kind = state.kind;
  if (kind == null) return null;
  if (!kind.isHabit) {
    final amount = money.parse(state.targetText);
    return amount == null || amount.isNegative ? null : MoneyAmount(amount);
  }
  // TrackerValues.parseAmount is written for entries and refuses zero. For a
  // limit, zero is a goal: "zero cigarettes".
  final value = double.tryParse(Digits.toLatin(state.targetText.trim())) == 0
      ? 0.0
      : TrackerValues.parseAmount(state.targetText);
  if (value == null || _fractionOfWholeCount(state)) return null;
  // A duration is typed in minutes and measured in seconds.
  return QuantityAmount(
    state.tracker?.type == TrackerType.duration ? value * 60 : value,
  );
}

/// A counter counts times and a boolean days, so a fraction is no target.
bool _fractionOfWholeCount(GoalEditorState state) {
  final type = state.tracker?.type;
  if (type != TrackerType.counter && type != TrackerType.boolean) return false;
  final value = TrackerValues.parseAmount(state.targetText);
  return value != null && value != value.roundToDouble();
}

/// Holds the editor's form. Auto-disposed, so a draft lives exactly as long
/// as its screen, as the add-expense form does.
class GoalEditorController extends Notifier<GoalEditorState> {
  GoalEditorController(this.seed);

  final GoalEditorSeed seed;

  /// The alert percents the chips offer.
  static const alertChoices = <int>[50, 80, 90, 100];

  @override
  GoalEditorState build() {
    // Read, not watched: a day or settings change must not reset a form
    // half written.
    // shortcut: an editor opened as the first screen, before the settings
    // load, captures the defaults; upgrade if a deep link to the editor is
    // ever added.
    final today = ref.read(goalTodayProvider);
    final money = ref.read(moneyFormatterProvider);
    final goal = seed.goal;
    if (goal == null) {
      return GoalEditorState(
        id: Ids.newId(),
        kind: null,
        name: '',
        nameEdited: false,
        targetText: '',
        categoryPaths: const [],
        tags: null,
        baseFilters: const QueryFilters(),
        tracker: null,
        period: PeriodType.month,
        since: today,
        start: today,
        end: today,
        // A new goal copies the settings at creation (spec §1).
        calendar: ref.read(calendarProvider).kind,
        weekStart: ref.read(firstDayOfWeekProvider),
        alertPercents: Goal.defaultAlertPercents,
        active: true,
      );
    }
    final filters = switch (goal.scope) {
      MoneyScope(:final filters) => filters,
      TrackerScope() => const QueryFilters(),
    };
    return GoalEditorState(
      id: goal.id,
      kind: kindOf(goal),
      name: goal.name,
      nameEdited: true,
      // A habit goal whose tracker is gone has no unit to show its number in
      // (a duration is stored in seconds, typed in minutes), so the form
      // asks for it again once another tracker is chosen.
      targetText: goal.metric.isTrackerMetric && seed.tracker == null
          ? ''
          : _textOf(goal.target, seed.tracker, money),
      categoryPaths: filters.categorySubtreePaths,
      tags: filters.tags,
      baseFilters: filters,
      tracker: seed.tracker,
      period: switch (goal.period) {
        RecurringPeriod(:final type) => type,
        FixedRangePeriod() => PeriodType.month,
      },
      since: goal.period.startDate,
      start: goal.period.startDate,
      end: goal.period.endDate ?? goal.period.startDate,
      calendar: goal.calendar,
      weekStart: goal.weekStart,
      alertPercents: goal.alertPercents,
      active: goal.active,
    );
  }

  /// Starts a new goal of [kind]: its direction and default period, and
  /// [suggestedName] until the user types one (spec §5.3).
  void chooseKind(GoalKind kind, {required String suggestedName}) {
    final today = ref.read(goalTodayProvider);
    final calendar = GoalPeriods.calendarFor(state.calendar);
    final month = calendar.periodContaining(today, PeriodType.month);
    state = state.copyWith(
      kind: kind,
      name: suggestedName,
      nameEdited: false,
      targetText: '',
      period: kind.defaultPeriod ?? state.period,
      start: today,
      // Six months, this one included: a horizon to change, not a rule.
      end: calendar.shiftPeriod(month, PeriodType.month, 5).endInclusive,
      baseFilters: kind == GoalKind.spendingCap
          ? const QueryFilters(direction: MoneyDirection.expense)
          : const QueryFilters(),
    );
  }

  void setName(String value) =>
      state = state.copyWith(name: value, nameEdited: true);

  void setTarget(String text) => state = state.copyWith(targetText: text);

  /// [path] null is all expenses. The name follows until the user types one.
  void setCategory(String? path, {required String suggestedName}) =>
      state = state.copyWith(
        categoryPaths: [if (path != null) path],
        name: state.nameEdited ? state.name : suggestedName,
      );

  void setTags(TagFilter? tags) => state = state.copyWith(tags: tags);

  /// A target is typed in the tracker's unit (times, days, litres, minutes).
  /// Swapping to a tracker of another type means the text is in another
  /// unit, so it is cleared and asked for again. Seconds read as minutes
  /// would save a target 60 times too large. With no tracker before, the text
  /// is what the user typed first, and it stays.
  void setTracker(Tracker tracker) {
    final previous = state.tracker;
    state = state.copyWith(
      tracker: tracker,
      name: state.nameEdited ? state.name : tracker.name,
      targetText: previous != null && previous.type != tracker.type
          ? ''
          : state.targetText,
    );
  }

  void setPeriod(PeriodType period) => state = state.copyWith(period: period);

  void setStart(DateKey day) => state = state.copyWith(start: day);

  void setEnd(DateKey day) => state = state.copyWith(end: day);

  void setCalendar(CalendarKind calendar) =>
      state = state.copyWith(calendar: calendar);

  /// Adds or removes one alert percent. The last one stays on, because a goal
  /// alerts at least once (`Goal` refuses an empty list).
  void toggleAlert(int percent) {
    final current = state.alertPercents;
    if (current.contains(percent)) {
      if (current.length == 1) return;
      state = state.copyWith(
        alertPercents: [
          for (final p in current)
            if (p != percent) p,
        ],
      );
    } else {
      state = state.copyWith(alertPercents: [...current, percent]..sort());
    }
  }

  static String _textOf(
    GoalAmount target,
    Tracker? tracker,
    MoneyFormatter formatter,
  ) {
    final text = switch (target) {
      MoneyAmount(:final money) => formatter.format(money),
      QuantityAmount(:final value) => _plain(
        tracker?.type == TrackerType.duration ? value / 60 : value,
      ),
    };
    return formatter.persianDigits ? Digits.toPersian(text) : text;
  }

  static String _plain(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';
}

final goalEditorProvider = NotifierProvider.autoDispose
    .family<GoalEditorController, GoalEditorState, GoalEditorSeed>(
      GoalEditorController.new,
    );
