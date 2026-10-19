import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../categories/application/category_providers.dart';
import '../../categories/data/category_tree.dart';
import '../../notifications/application/outside_errors.dart';
import '../../notifications/application/permission_request.dart';
import '../../notifications/data/outside_channel.dart';
import '../../settings/application/settings_providers.dart';
import '../../tags/application/tag_providers.dart';
import '../../tags/presentation/widgets/tag_chip_row.dart';
import '../../tags/presentation/widgets/tag_picker_sheet.dart';
import '../../trackers/application/tracker_providers.dart';
import '../../transactions/presentation/widgets/amount_field.dart';
import '../application/goal_editor_controller.dart';
import '../application/goal_format.dart';
import '../application/goal_kind.dart';
import '../application/goal_providers.dart';
import '../routes.dart';
import 'widgets/goal_kind_tiles.dart';
import 'widgets/goal_preview.dart';
import 'widgets/goal_write.dart';

/// Writes a goal (screen contract §7.2): for a new goal the kind first,
/// then one form for that kind, with a live preview against recent history.
class GoalEditorScreen extends ConsumerStatefulWidget {
  const GoalEditorScreen({super.key, this.id});

  /// The goal being edited, or null for a new one.
  final String? id;

  @override
  ConsumerState<GoalEditorScreen> createState() => _GoalEditorScreenState();
}

class _GoalEditorScreenState extends ConsumerState<GoalEditorScreen> {
  /// Frozen the first time the goal, and its tracker, are known. A later
  /// emission, such as the tracker's timer starting, must not reset a form
  /// half written.
  GoalEditorSeed? _seed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final id = widget.id;
    var seed = _seed;
    if (seed == null && id == null) seed = _seed = (goal: null, tracker: null);
    if (seed == null) {
      final goals = ref.watch(goalsProvider);
      if (goals.hasError) {
        return _ErrorScaffold(onRetry: () => ref.invalidate(goalsProvider));
      }
      if (!goals.hasValue) return const _LoadingScaffold();
      final goal = [
        for (final read in goals.requireValue)
          if (read case GoalReadable(:final goal) when goal.id == id) goal,
      ].firstOrNull;
      if (goal == null) {
        return Scaffold(
          appBar: AppBar(),
          body: NimbusEmptyState(
            icon: Icons.search_off,
            title: l10n.goalsNotFoundTitle,
            message: l10n.goalsNotFoundBody,
            actionLabel: l10n.navGoals,
            onAction: () => context.go(goalsRoute),
          ),
        );
      }
      Tracker? tracker;
      if (goal.scope case TrackerScope(:final trackerId)) {
        final found = ref.watch(trackerByIdProvider(trackerId));
        if (found.hasError) {
          return _ErrorScaffold(
            onRetry: () => ref.invalidate(trackerByIdProvider(trackerId)),
          );
        }
        if (!found.hasValue) return const _LoadingScaffold();
        tracker = found.requireValue;
      }
      seed = _seed = (goal: goal, tracker: tracker);
    }
    return _GoalForm(seed: seed);
  }
}

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm({required this.seed});

  final GoalEditorSeed seed;

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  late final _provider = goalEditorProvider(widget.seed);
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _targetFocus = FocusNode();

  /// The preview's debounce. It lives in widget state, so it ends with the
  /// screen.
  Timer? _debounce;

  /// The draft as it stood ~300 ms after the last change (spec §5.3).
  Goal? _previewed;

  @override
  void initState() {
    super.initState();
    ref.listenManual(_provider, (_, next) {
      // The editor changes these itself: a suggested name, or a target
      // cleared for a new kind. Typing leaves them equal, so the caret stays
      // where it is.
      if (_name.text != next.name) _name.text = next.name;
      if (_target.text != next.targetText) _target.text = next.targetText;
      _schedulePreview();
    }, fireImmediately: true);
  }

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(
        () => _previewed = goalDraft(
          ref.read(_provider),
          ref.read(moneyFormatterProvider),
        ),
      );
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _target.dispose();
    _targetFocus.dispose();
    super.dispose();
  }

  GoalEditorController get _controller => ref.read(_provider.notifier);

  Future<void> _save() async {
    final goal = goalDraft(
      ref.read(_provider),
      ref.read(moneyFormatterProvider),
    );
    if (goal == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final service = ref.read(goalServiceProvider);
    final outside = ref.read(outsideChannelProvider);
    final isNew = widget.seed.goal == null;
    // Awaited before leaving, as the add-expense screen does. If the write
    // fails, the user is still holding the form. No spinner: a local write
    // is sub-millisecond (screen contract §1.3).
    await reportingGoalFailure(
      messenger: messenger,
      l10n: l10n,
      write: () => service.save(goal),
    );
    // Not awaited: Android's dialog shows over the list the editor returns
    // to, and the save is already done.
    if (isNew) unawaited(_askIfFirstGoal(service, outside));
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(goalsRoute);
    }
  }

  /// The first goal is when notifications start to matter (Phase 6 spec
  /// §4.2). Counted after the write, so this goal is the one and a failed
  /// read can never abort the save; that failure is reported, and no ask.
  static Future<void> _askIfFirstGoal(
      GoalService service, OutsideChannel outside) async {
    final goals = await reportingFailure('alert router',
        'while counting goals for the notification ask', service.goals);
    if (goals?.length == 1) {
      await askForNotifications(outside, library: 'alert router');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(_provider);
    final money = ref.watch(moneyFormatterProvider);
    final title = Text(
      widget.seed.goal == null ? l10n.goalsNew : l10n.goalsEditTitle,
    );

    final kind = state.kind;
    if (kind == null) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: GoalKindTiles(
          onChosen: (kind) => _controller.chooseKind(
            kind,
            suggestedName: switch (kind) {
              GoalKind.spendingCap => l10n.goalsAllExpenses,
              GoalKind.savingsTarget => l10n.goalsKindSavingsTarget,
              // A habit is named after its tracker, once one is chosen.
              GoalKind.habitLimit || GoalKind.habitGoal => '',
            },
          ),
        ),
      );
    }

    final errors = goalEditorErrors(state, money);
    final canSave = goalDraft(state, money) != null;
    return Scaffold(
      appBar: AppBar(title: title),
      // A short form, so every field is built and findable; a lazy list
      // would leave the ones below the fold out.
      body: SingleChildScrollView(
        key: const Key('goal-editor'),
        padding: const EdgeInsets.all(NimbusTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('goal-name'),
              textCapitalization: TextCapitalization.sentences,
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.goalsFieldName,
                border: const OutlineInputBorder(),
                errorText: errors.contains(GoalEditorError.nameBlank)
                    ? l10n.goalsErrorName
                    : null,
              ),
              onChanged: _controller.setName,
            ),
            const SizedBox(height: NimbusTokens.space2),
            ...switch (kind) {
              GoalKind.spendingCap => _capFields(l10n, state, errors, money),
              GoalKind.habitLimit ||
              GoalKind.habitGoal => _habitFields(l10n, theme, state, errors),
              GoalKind.savingsTarget => _savingsFields(
                l10n,
                state,
                errors,
                money,
              ),
            },
            const SizedBox(height: NimbusTokens.space4),
            _AlertChips(
              selected: state.alertPercents,
              onToggled: _controller.toggleAlert,
            ),
            const SizedBox(height: NimbusTokens.space4),
            GoalPreviewPanel(goal: _previewed, tracker: state.tracker),
          ],
        ),
      ),
      // As on the add-expense screen: Save rides above the keyboard, in the
      // bottom third (screen contract §1.3).
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(NimbusTokens.space4),
            child: SizedBox(
              height: NimbusTokens.minTapTarget,
              child: FilledButton(
                key: const Key('goal-save'),
                // Disabled until every inline error clears (spec §5.3).
                onPressed: canSave ? () => unawaited(_save()) : null,
                child: Text(
                  l10n.commonSave,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _capFields(
    AppLocalizations l10n,
    GoalEditorState state,
    Set<GoalEditorError> errors,
    MoneyFormatter money,
  ) {
    final categories =
        ref.watch(categoryNodesByIdProvider).value ??
        const <String, CategoryNode>{};
    final tagNodes = ref.watch(tagNodesByIdProvider).value ?? const {};
    final path = state.categoryPaths.firstOrNull;
    final tags = [
      for (final tagPath in state.tags?.subtreePaths ?? const <String>[])
        if (tagNodes[_leafOf(tagPath)] case final node?) node.value,
    ];
    return [
      ListTile(
        key: const Key('goal-category'),
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.goalsFieldCategory),
        // Named by the category's own id, the path's last segment, which
        // survives a move to another parent (Review Focus 1).
        subtitle: Text(
          path == null
              ? l10n.goalsAllExpenses
              : categories[_leafOf(path)]?.category.name ?? l10n.goalsScopeGone,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(_pickCategory()),
      ),
      ListTile(
        key: const Key('goal-tags'),
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.goalsFieldTags),
        // D3: a bounded row with a +N, however many tags the filter names.
        subtitle: tags.isEmpty
            ? Text(l10n.goalsTagsNone)
            : TagChipRow(tags: tags),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(_pickTags()),
      ),
      const SizedBox(height: NimbusTokens.space2),
      AmountField(
        controller: _target,
        focusNode: _targetFocus,
        formatter: money,
        label: l10n.amount,
        errorText: _targetError(l10n, errors),
        onChanged: _controller.setTarget,
      ),
      const SizedBox(height: NimbusTokens.space4),
      _PeriodChips(selected: state.period, onSelected: _controller.setPeriod),
      const SizedBox(height: NimbusTokens.space4),
      _CalendarChoice(
        selected: state.calendar,
        onChanged: _controller.setCalendar,
      ),
    ];
  }

  List<Widget> _habitFields(
    AppLocalizations l10n,
    ThemeData theme,
    GoalEditorState state,
    Set<GoalEditorError> errors,
  ) {
    // Loaded now, so the picker opens on a list rather than on nothing.
    ref.watch(trackersProvider);
    final tracker = state.tracker;
    return [
      ListTile(
        key: const Key('goal-tracker'),
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.goalsFieldTracker),
        subtitle: Text(
          tracker?.name ?? l10n.goalsChooseTracker,
          style: tracker == null
              ? TextStyle(color: theme.colorScheme.error)
              : null,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(_pickTracker()),
      ),
      const SizedBox(height: NimbusTokens.space2),
      TextField(
        key: const Key('goal-target'),
        controller: _target,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: switch (tracker) {
            null => l10n.goalsFieldTarget,
            Tracker(type: TrackerType.counter) => l10n.goalsTargetTimes,
            Tracker(type: TrackerType.boolean) => l10n.goalsTargetDays,
            Tracker(type: TrackerType.quantity, :final unit) =>
              unit ?? l10n.trackerAmountLabel,
            Tracker(type: TrackerType.duration) => l10n.goalsTargetMinutes,
          },
          border: const OutlineInputBorder(),
          errorText: _targetError(l10n, errors),
        ),
        onChanged: _controller.setTarget,
      ),
      const SizedBox(height: NimbusTokens.space4),
      _PeriodChips(selected: state.period, onSelected: _controller.setPeriod),
    ];
  }

  List<Widget> _savingsFields(
    AppLocalizations l10n,
    GoalEditorState state,
    Set<GoalEditorError> errors,
    MoneyFormatter money,
  ) => [
    AmountField(
      controller: _target,
      focusNode: _targetFocus,
      formatter: money,
      label: l10n.amount,
      errorText: _targetError(l10n, errors),
      onChanged: _controller.setTarget,
    ),
    const SizedBox(height: NimbusTokens.space2),
    _DateTile(
      key: const Key('goal-start'),
      label: l10n.goalsFieldStart,
      day: state.start,
      calendar: state.calendar,
      onPicked: _controller.setStart,
    ),
    _DateTile(
      key: const Key('goal-end'),
      label: l10n.goalsFieldEnd,
      day: state.end,
      calendar: state.calendar,
      error: errors.contains(GoalEditorError.endBeforeStart)
          ? l10n.goalsErrorEndBeforeStart
          : null,
      onPicked: _controller.setEnd,
    ),
    const SizedBox(height: NimbusTokens.space4),
    _CalendarChoice(
      selected: state.calendar,
      onChanged: _controller.setCalendar,
    ),
  ];

  static String? _targetError(
    AppLocalizations l10n,
    Set<GoalEditorError> errors,
  ) => errors.contains(GoalEditorError.targetInvalid)
      ? l10n.goalsErrorTargetInvalid
      : errors.contains(GoalEditorError.targetNotWhole)
      ? l10n.goalsErrorTargetWhole
      : errors.contains(GoalEditorError.targetZero)
      ? l10n.goalsErrorTargetZero
      : null;

  /// A path's last segment: the category's or tag's own id.
  static String _leafOf(String path) =>
      path.split('/').where((segment) => segment.isNotEmpty).last;

  Future<void> _pickCategory() async {
    final l10n = AppLocalizations.of(context);
    final tree = ref.read(categoryTreeProvider).value ?? const <CategoryNode>[];
    // Expense categories a user can still choose: not archived, and not the
    // Uncategorized fallback, as the add screen's picker offers.
    final nodes = [
      for (final node in CategoryTree.flatten(tree))
        if (!node.category.archived &&
            node.category.kind == 'expense' &&
            !SystemCategoryIds.isSystem(node.category.id))
          node,
    ];
    final picked = await showModalBottomSheet<({String? path, String name})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              key: const Key('goal-category-all'),
              leading: const ExcludeSemantics(child: Icon(Icons.all_inclusive)),
              title: Text(l10n.goalsAllExpenses),
              onTap: () =>
                  Navigator.of(context)
                      .pop((path: null, name: l10n.goalsAllExpenses)),
            ),
            for (final node in nodes)
              ListTile(
                key: Key('goal-category-${node.category.id}'),
                // D4: the indent stops growing at the token's depth.
                contentPadding: EdgeInsetsDirectional.only(
                  start:
                      NimbusTokens.space4 +
                      math.min(node.depth, NimbusTokens.maxTreeIndentDepth) *
                          NimbusTokens.indentPerLevel,
                  end: NimbusTokens.space4,
                ),
                leading: ExcludeSemantics(
                  child: Icon(
                    nimbusIconFor(node.category.iconKey),
                    color: Color(node.category.color),
                  ),
                ),
                title: Text(node.category.name),
                onTap: () => Navigator.of(context)
                    .pop((path: node.category.path, name: node.category.name)),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _controller.setCategory(picked.path, suggestedName: picked.name);
  }

  Future<void> _pickTags() async {
    // The filter's own paths, by tag id: the last answer for a tag the other
    // two reads no longer return, such as an archived one.
    final stored = {
      for (final path
          in ref.read(_provider).tags?.subtreePaths ?? const <String>[])
        _leafOf(path): path,
    };
    final picked = await showTagPickerSheet(
      context,
      selected: stored.keys.toSet(),
    );
    if (picked == null || !mounted) return;
    // The tag tree stream may not have caught up with a tag the sheet just
    // created, so ask the repository for the live tags now. The tree map
    // answers for an archived tag, and the stored path for one neither knows.
    final fresh = {
      for (final tag
          in await ref.read(tagRepositoryProvider).suggestions(limit: null))
        tag.id: tag.path,
    };
    if (!mounted) return;
    final nodes = ref.read(tagNodesByIdProvider).value ?? const {};
    final paths = [
      for (final id in picked)
        fresh[id] ??
            nodes[id]?.value.path ??
            stored[id] ??
            (throw StateError('Picked tag $id has no path')),
    ];
    _controller.setTags(paths.isEmpty ? null : TagsAny(paths));
  }

  Future<void> _pickTracker() async {
    final l10n = AppLocalizations.of(context);
    final trackers = ref.read(trackersProvider).value ?? const <Tracker>[];
    final picked = await showModalBottomSheet<Tracker>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (trackers.isEmpty) ListTile(title: Text(l10n.goalsNoTrackers)),
            for (final tracker in trackers)
              ListTile(
                key: Key('goal-tracker-option-${tracker.id}'),
                leading: ExcludeSemantics(
                  child: Icon(
                    nimbusIconFor(tracker.iconKey),
                    color: Color(tracker.color),
                  ),
                ),
                title: Text(tracker.name),
                onTap: () => Navigator.of(context).pop(tracker),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _controller.setTracker(picked);
  }
}

class _PeriodChips extends StatelessWidget {
  const _PeriodChips({required this.selected, required this.onSelected});

  final PeriodType selected;
  final ValueChanged<PeriodType> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.goalsFieldPeriod,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: NimbusTokens.space2),
        // A Wrap, so five chips at twice the font size take two lines.
        Wrap(
          spacing: NimbusTokens.space2,
          runSpacing: NimbusTokens.space2,
          children: [
            for (final period in PeriodType.values)
              ChoiceChip(
                key: Key('goal-period-${period.name}'),
                label: Text(switch (period) {
                  PeriodType.day => l10n.goalsPeriodDay,
                  PeriodType.week => l10n.goalsPeriodWeek,
                  PeriodType.month => l10n.goalsPeriodMonth,
                  PeriodType.quarter => l10n.goalsPeriodQuarter,
                  PeriodType.year => l10n.goalsPeriodYear,
                }),
                selected: period == selected,
                onSelected: (_) => onSelected(period),
              ),
          ],
        ),
      ],
    );
  }
}

/// The goal's own calendar, copied from the settings at creation. A goal
/// keeps it when the app's calendar changes (the brief's first trap).
class _CalendarChoice extends StatelessWidget {
  const _CalendarChoice({required this.selected, required this.onChanged});

  final CalendarKind selected;
  final ValueChanged<CalendarKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsCalendar,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: NimbusTokens.space2),
        SegmentedButton<CalendarKind>(
          key: const Key('goal-calendar'),
          segments: [
            ButtonSegment(
              value: CalendarKind.jalali,
              label: Text(l10n.settingsCalendarJalali),
            ),
            ButtonSegment(
              value: CalendarKind.gregorian,
              label: Text(l10n.settingsCalendarGregorian),
            ),
          ],
          selected: {selected},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}

class _AlertChips extends ConsumerWidget {
  const _AlertChips({required this.selected, required this.onToggled});

  final List<int> selected;
  final ValueChanged<int> onToggled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = ref.watch(goalFormatProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).goalsFieldAlerts,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: NimbusTokens.space2),
        Wrap(
          spacing: NimbusTokens.space2,
          runSpacing: NimbusTokens.space2,
          children: [
            for (final percent in GoalEditorController.alertChoices)
              FilterChip(
                key: Key('goal-alert-$percent'),
                label: Text(format.wholePercent(percent)),
                selected: selected.contains(percent),
                onSelected: (_) => onToggled(percent),
              ),
          ],
        ),
      ],
    );
  }
}

/// A date in the goal's calendar, picked with the platform's picker, as the
/// add-expense screen's date is.
class _DateTile extends ConsumerWidget {
  const _DateTile({
    super.key,
    required this.label,
    required this.day,
    required this.calendar,
    required this.onPicked,
    this.error,
  });

  final String label;
  final DateKey day;
  final CalendarKind calendar;
  final ValueChanged<DateKey> onPicked;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = this.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ref.watch(goalFormatProvider).date(calendar, day)),
          if (error != null)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      trailing: const Icon(Icons.calendar_today_outlined),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: day.toDateTime(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPicked(DateKey.fromDateTime(picked));
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(), body: const NimbusLoadingList());
}

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: NimbusErrorState(
        title: l10n.goalsErrorTitle,
        retryLabel: l10n.commonRetry,
        onRetry: onRetry,
      ),
    );
  }
}
