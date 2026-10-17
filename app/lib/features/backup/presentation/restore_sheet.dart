import 'package:flutter/widgets.dart';

import '../application/backup_controller.dart';

/// Restore, in one sheet (spec §5.3). Completed in Task 12.
class RestoreSheet extends StatelessWidget {
  const RestoreSheet({super.key, required this.picked});

  final PickedBackup picked;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
