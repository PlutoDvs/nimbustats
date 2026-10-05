import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../database/columns.dart';

/// Something the user counts that is not money: cigarettes, water, gym days,
/// sleep.
///
/// The row class is named explicitly: drift would otherwise generate one
/// called `Tracker`, which is the domain value type the DAO returns.
///
/// `idx_trackers_live` is partial because every reader asks only for live
/// trackers, archived or not, in the user's order.
@DataClassName('TrackerRow')
@TableIndex.sql('CREATE INDEX idx_trackers_live ON trackers '
    '(archived, sort_order) WHERE deleted_at IS NULL')
class Trackers extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get iconKey => text()();
  IntColumn get color => integer()();
  TextColumn get type => textEnum<TrackerType>()();

  /// Free text, quantity trackers only: `L`, `pages`, `لیتر`.
  TextColumn get unit => text().nullable()();

  /// What one tap logs on a quantity tracker, and required for one. Null for
  /// every other type, whose taps log 1 or start a timer.
  RealColumn get perTapValue => real().nullable()();

  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Epoch ms of the running timer's start; duration trackers only, null when
  /// no timer runs.
  ///
  /// A column rather than a table or an open entry row: it holds at most one
  /// start per tracker by construction -- the brief's "one running timer per
  /// tracker", enforced by the schema instead of the UI. It is written the
  /// moment the timer starts, so the timer survives the process being killed;
  /// elapsed time is always now minus this, never a value held in memory.
  IntColumn get timerStartedAtUtc => integer().nullable()();
}
