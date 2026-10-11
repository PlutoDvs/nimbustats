import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';

/// A static placeholder where a goal's numbers will be. Never a spinner
/// (screen contract §1.1).
class GoalInlineSkeleton extends StatelessWidget {
  const GoalInlineSkeleton({super.key, this.height = NimbusTokens.minTapTarget});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: NimbusSemanticColors.of(context).skeleton,
          borderRadius: NimbusTokens.borderRadiusSm,
        ),
      );
}

/// The Retry of every inline failure, so the three screens' errors agree.
class GoalRetryButton extends StatelessWidget {
  const GoalRetryButton({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onRetry,
        child: Text(AppLocalizations.of(context).commonRetry),
      );
}

/// A failed load, said in place with a Retry, so one failure does not cost
/// the rest of the screen.
class GoalInlineError extends StatelessWidget {
  const GoalInlineError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(message)),
          GoalRetryButton(onRetry: onRetry),
        ],
      );
}
