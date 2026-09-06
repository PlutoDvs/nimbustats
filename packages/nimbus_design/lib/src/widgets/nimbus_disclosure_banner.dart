import 'package:flutter/material.dart';

import '../tokens.dart';

/// States a caveat about the numbers beside it.
///
/// Built for the one Phase 3 must never omit: a transaction tagged `#travel`
/// and `#food` lands in both buckets, so tag slices sum to more than the true
/// total. A pie chart that renders those slices without saying so is not a
/// rough edge, it is a quiet lie -- which is why this is a shared widget with
/// its own tests rather than a `Text` somewhere in a chart screen.
class NimbusDisclosureBanner extends StatelessWidget {
  const NimbusDisclosureBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: message,
      container: true,
      // The row's own nodes are dropped in favour of the label above. Left in,
      // a screen reader announces the sentence twice -- once for the container
      // and once for the Text inside it.
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: NimbusTokens.space4,
          vertical: NimbusTokens.space3,
        ),
        decoration: BoxDecoration(
          // secondaryContainer rather than an alarm colour: this explains a
          // number, it does not report a failure, and dressing it as an error
          // teaches people to dismiss it without reading.
          color: scheme.secondaryContainer,
          borderRadius: NimbusTokens.borderRadiusMd,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: NimbusTokens.space3),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
