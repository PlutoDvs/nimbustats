import 'package:flutter/material.dart';

import '../tokens.dart';

/// The `empty` state every screen is required to implement.
///
/// Takes strings rather than localization keys: `nimbus_design` has no ARB
/// bundle and must not gain one, so callers resolve their own copy.
///
/// [message] is not decoration. The screen contract requires an empty state to
/// say what to do next rather than announcing that there is no data, which is
/// why the action is offered right here instead of leaving the user to find a
/// button elsewhere on the screen.
class NimbusEmptyState extends StatelessWidget {
  const NimbusEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = actionLabel;
    final action = onAction;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NimbusTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Decorative: the title and message carry the meaning, so
            // announcing the icon as well would just make a screen reader
            // repeat itself.
            ExcludeSemantics(
              child: Icon(icon, size: 48, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: NimbusTokens.space4),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              // Centre rather than start/end: direction-neutral, and therefore
              // correct in both locales without a mirrored variant.
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NimbusTokens.space2),
            Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (label != null && action != null) ...[
              const SizedBox(height: NimbusTokens.space6),
              FilledButton(onPressed: action, child: Text(label)),
            ],
          ],
        ),
      ),
    );
  }
}
