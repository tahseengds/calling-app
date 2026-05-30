import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/lumio_icons.dart';

/// A single block within a legal document. Either a [heading] (numbered
/// section title) or a body [paragraph], or a [bullet] list item.
class LegalBlock {
  final String? heading;
  final String? paragraph;
  final List<String>? bullets;

  const LegalBlock.heading(this.heading)
      : paragraph = null,
        bullets = null;
  const LegalBlock.paragraph(this.paragraph)
      : heading = null,
        bullets = null;
  const LegalBlock.bullets(this.bullets)
      : heading = null,
        paragraph = null;
}

/// Renders a legal document (Privacy Policy / Terms) entirely in-app — no
/// external browser. Content is passed as a list of [LegalBlock]s so the two
/// documents share one consistent, readable layout.
class LegalDocumentScreen extends StatelessWidget {
  final String title;
  final String effectiveDate;
  final String intro;
  final List<LegalBlock> blocks;

  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.effectiveDate,
    required this.intro,
    required this.blocks,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final isDark = context.isDarkMode;

    // Number the headings (1, 2, 3 …) so the document reads like a real policy.
    var sectionNumber = 0;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LumioIcons.back, color: colors.fg1),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text(title, style: AppTextStyles.h1(color: colors.fg1)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space5,
            AppSpacing.space2,
            AppSpacing.space5,
            AppSpacing.space10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Effective-date chip.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space3,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurface
                      : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: colors.hairline),
                ),
                child: Text(
                  'Effective $effectiveDate',
                  style: AppTextStyles.caption(color: colors.fg2),
                ),
              ),
              const SizedBox(height: AppSpacing.space5),
              Text(
                intro,
                style: AppTextStyles.body(color: colors.fg2)
                    .copyWith(height: 1.5),
              ),
              const SizedBox(height: AppSpacing.space6),
              for (final block in blocks) ...[
                if (block.heading != null)
                  _Heading(
                    number: ++sectionNumber,
                    text: block.heading!,
                    colors: colors,
                  ),
                if (block.paragraph != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space4),
                    child: Text(
                      block.paragraph!,
                      style: AppTextStyles.body(color: colors.fg2)
                          .copyWith(height: 1.5),
                    ),
                  ),
                if (block.bullets != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final b in block.bullets!)
                          _Bullet(text: b, colors: colors),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final int number;
  final String text;
  final LumioColors colors;

  const _Heading({
    required this.number,
    required this.text,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              '$number',
              style: AppTextStyles.captionSemibold(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.h2(color: colors.fg1)
                  .copyWith(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  final LumioColors colors;

  const _Bullet({required this.text, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: AppSpacing.space3),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body(color: colors.fg2)
                  .copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
