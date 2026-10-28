import 'package:boorusphere/presentation/theme/app_typography.dart';
import 'package:boorusphere/presentation/theme/design_tokens.dart';
import 'package:boorusphere/presentation/widgets/notice_card.dart';
import 'package:flutter/material.dart';

/// A page with nothing to show yet: one notice block, centred, and scrollable
/// so a large font scale or a short window never cuts its action off.
///
/// The title is the only primary line, the body explains the state in the
/// supporting role, and the action — when there is one — is the way out. An
/// empty state without one is a page that only says no.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final Widget icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final roles = AppTextRoles.of(context);
    final body = this.body;
    final action = this.action;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              child: NoticeCard(
                icon: icon,
                children: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: roles.rowTitle,
                    ),
                    if (body != null) ...[
                      const SizedBox(height: DesignTokens.spacingSm),
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: roles.rowSupporting,
                      ),
                    ],
                    if (action != null) ...[
                      const SizedBox(height: DesignTokens.spacingLg),
                      action,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
