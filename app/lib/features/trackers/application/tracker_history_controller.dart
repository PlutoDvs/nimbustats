import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../data/tracker_entry_page.dart';
import 'tracker_providers.dart';

final class TrackerHistoryState {
  const TrackerHistoryState({
    required this.entries,
    required this.cursor,
    this.isLoadingMore = false,
  });

  final List<TrackerEntry> entries;
  final TrackerEntryCursor? cursor;
  final bool isLoadingMore;

  bool get hasMore => cursor != null;
}

/// One tracker's history, a page at a time, newest first.
class TrackerHistoryController extends AsyncNotifier<TrackerHistoryState> {
  TrackerHistoryController(this.trackerId);

  final String trackerId;

  static const pageSize = 40;

  @override
  Future<TrackerHistoryState> build() async {
    final repository = ref.watch(trackerRepositoryProvider);
    // Any entry write reloads what is shown. An edit, a delete, an undo or a
    // quick log then appears at once, without each caller having to remember
    // to refresh.
    final changes =
        repository.entryChanges().listen((_) => unawaited(_reload()));
    ref.onDispose(changes.cancel);
    final page = await repository.entriesPage(trackerId, limit: pageSize);
    return TrackerHistoryState(entries: page.items, cursor: page.cursor);
  }

  /// Appends the next page.
  ///
  /// Guarded by [TrackerHistoryState.isLoadingMore]: a fling fires scroll
  /// notifications far faster than a page resolves.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;
    final loading = TrackerHistoryState(
        entries: current.entries, cursor: current.cursor, isLoadingMore: true);
    state = AsyncData(loading);

    final TrackerEntryPage page;
    try {
      page = await ref
          .read(trackerRepositoryProvider)
          .entriesPage(trackerId, after: current.cursor, limit: pageSize);
    } on Object {
      // Not stuck "loading" forever: the next scroll may try again.
      if (ref.mounted && identical(state.value, loading)) {
        state = AsyncData(current);
      }
      rethrow;
    }
    // If a reload replaced the list while this page was on its way, its cursor
    // belongs to a list no longer shown, so the page is dropped.
    if (!ref.mounted || !identical(state.value, loading)) return;
    state = AsyncData(TrackerHistoryState(
      entries: [...current.entries, ...page.items],
      cursor: page.cursor,
    ));
  }

  /// Reloads from the top, as deep as the user has scrolled, so a write does
  /// not snap the list back to its first page.
  Future<void> _reload() async {
    final depth = math.max(pageSize, state.value?.entries.length ?? 0);
    final next = await AsyncValue.guard(() async {
      final page = await ref
          .read(trackerRepositoryProvider)
          .entriesPage(trackerId, limit: depth);
      return TrackerHistoryState(entries: page.items, cursor: page.cursor);
    });
    if (ref.mounted) state = next;
  }
}

final trackerHistoryProvider = AsyncNotifierProvider.autoDispose
    .family<TrackerHistoryController, TrackerHistoryState, String>(
        TrackerHistoryController.new);
