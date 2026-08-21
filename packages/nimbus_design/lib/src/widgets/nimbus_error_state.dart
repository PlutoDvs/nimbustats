import 'package:flutter/material.dart';

import '../tokens.dart';

/// The `error` state every screen is required to implement.
///
/// [detail] is accepted but deliberately **not rendered**. The screen contract
/// forbids showing a bare exception string, and callers were otherwise dropping
/// the underlying error on the floor entirely -- taking it here means the value
/// is available to whichever phase adds a bug-report affordance, without any
/// screen having to remember to keep hold of it in the meantime.
class NimbusErrorState extends StatelessWidget {
  const NimbusErrorState({
    super.key,
    required this.title,
    required this.retryLabel,
    required this.onRetry,
    this.detail,
  });

  final String title;
  final String retryLabel;
  final VoidCallback onRetry;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NimbusTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.error_outline,
                  size: 48, color: theme.colorScheme.error),
            ),
            const SizedBox(height: NimbusTokens.space4),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NimbusTokens.space6),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
