import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/saved_views_repository.dart';

final savedViewsRepositoryProvider = Provider<SavedViewsRepository>(
  (ref) => SavedViewsRepository(ref.watch(appDatabaseProvider).savedViewsDao),
);
