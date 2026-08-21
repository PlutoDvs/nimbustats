import 'package:flutter/material.dart';

import '../colors.dart';
import '../tokens.dart';

/// The `loading` state for any list.
///
/// A static skeleton rather than a spinner, because the screen contract
/// forbids a blocking spinner for a read: a skeleton shows the shape of what is
/// arriving, and costs nothing to render. It is also deliberately unanimated --
/// a shimmer on a screen that is already waiting on I/O is the wrong place to
/// spend frame budget.
class NimbusLoadingList extends StatelessWidget {
  const NimbusLoadingList({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final skeleton = NimbusSemanticColors.of(context).skeleton;

    return Semantics(
      // One announcement for the whole placeholder. Six identical "loading"
      // nodes would be noise.
      label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      excludeSemantics: true,
      child: ListView.separated(
        padding: const EdgeInsets.all(NimbusTokens.space4),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: NimbusTokens.space2),
        itemBuilder: (context, index) => Container(
          key: const Key('nimbus-skeleton-row'),
          height: NimbusTokens.minTapTarget,
          decoration: BoxDecoration(
            color: skeleton,
            borderRadius: NimbusTokens.borderRadiusSm,
          ),
        ),
      ),
    );
  }
}
