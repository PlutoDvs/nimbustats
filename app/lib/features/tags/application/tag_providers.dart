import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/tag_repository.dart';
import '../data/tag_tree.dart';

final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepository(ref.watch(appDatabaseProvider).tagsDao),
);

/// The nested tag tree, re-emitted on every write.
final tagTreeProvider = StreamProvider<List<TagNode>>((ref) {
  ref.keepAlive();
  return ref.watch(tagRepositoryProvider).watchTree();
});

/// Tags to offer on the add screen, best first.
///
/// A stream rather than a one-shot read: creating a tag inline while adding an
/// expense has to change what the next expense is offered, without anyone
/// remembering to invalidate anything.
final tagSuggestionsProvider = StreamProvider<List<Tag>>((ref) {
  ref.keepAlive();
  return ref.watch(tagRepositoryProvider).watchSuggestions();
});

/// Every live tag, ranked the same way, for the picker.
///
/// Unbounded on purpose: the picker has a search field, and a truncated list
/// would hide the very tag someone is typing the name of.
final tagPickerOptionsProvider = StreamProvider<List<Tag>>((ref) {
  ref.keepAlive();
  return ref.watch(tagRepositoryProvider).watchSuggestions(limit: null);
});
