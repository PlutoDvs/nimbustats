import 'package:flutter/material.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';

/// One tag, rendered as a compact chip.
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = Color(tag.color);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NimbusTokens.space2,
        vertical: NimbusTokens.space1,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: NimbusTokens.borderRadiusSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Icon(nimbusIconFor(tag.iconKey), size: 14)),
          const SizedBox(width: NimbusTokens.space1),
          // Flexible so a long tag name ellipsizes rather than pushing the row
          // past the edge of a narrow screen.
          Flexible(
            child: Text(
              tag.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// A bounded row of tag chips with a remainder count.
///
/// Screen contract D3: twenty tags on one expense must not push anything off
/// the row or wrap it into a paragraph. At most [maxVisible] chips render and
/// the rest collapse into a `+N`, so the row's height is the same whether a
/// transaction carries one tag or fifty.
class TagChipRow extends StatelessWidget {
  const TagChipRow({
    super.key,
    required this.tags,
    this.maxVisible = 4,
    this.moreKey,
  });

  final List<Tag> tags;
  final int maxVisible;

  /// Key for the `+N` affordance, so a screen can pin it by its own name.
  final Key? moreKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final visible = tags.take(maxVisible).toList();
    final remainder = tags.length - visible.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tag in visible)
          Flexible(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                  end: NimbusTokens.space1),
              child: TagChip(tag: tag),
            ),
          ),
        if (remainder > 0)
          Text(
            l10n.tagMoreCount(remainder),
            key: moreKey,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
