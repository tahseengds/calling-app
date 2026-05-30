import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/lumio_icons.dart';

/// One package's worth of license text, aggregated across the (possibly many)
/// LicenseEntry rows that name it.
class _PackageLicense {
  final String name;
  final List<String> paragraphs;

  _PackageLicense(this.name, this.paragraphs);
}

/// Reads Flutter's [LicenseRegistry] and folds the flat stream of
/// [LicenseEntry] rows into one entry per package, sorted alphabetically.
Future<List<_PackageLicense>> _loadLicenses() async {
  // package name → ordered, de-duplicated license paragraphs.
  final byPackage = <String, List<String>>{};

  await for (final entry in LicenseRegistry.licenses) {
    final text =
        entry.paragraphs.map((p) => p.text.trim()).join('\n\n').trim();
    if (text.isEmpty) continue;
    for (final pkg in entry.packages) {
      final list = byPackage.putIfAbsent(pkg, () => <String>[]);
      if (!list.contains(text)) list.add(text);
    }
  }

  final result = byPackage.entries
      .map((e) => _PackageLicense(e.key, e.value))
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}

/// Redesigned Open Source Licenses screen — searchable, grouped per package,
/// styled with the app's design system instead of Flutter's stock
/// `showLicensePage` dialog.
class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  late final Future<List<_PackageLicense>> _future;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _loadLicenses();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final isDark = context.isDarkMode;

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
        title: Text('Open-source licenses',
            style: AppTextStyles.h1(color: colors.fg1)),
      ),
      body: SafeArea(
        child: FutureBuilder<List<_PackageLicense>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            if (snap.hasError) {
              return Center(
                child: Text('Could not load licenses.',
                    style: AppTextStyles.body(color: colors.fg2)),
              );
            }
            final all = snap.data ?? const [];
            final q = _query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? all
                : all
                    .where((p) => p.name.toLowerCase().contains(q))
                    .toList();

            return Column(
              children: [
                // ── Intro + count ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.space5,
                    AppSpacing.space2,
                    AppSpacing.space5,
                    AppSpacing.space3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lumio is built with the help of these open-source '
                        'packages. Thank you to their authors and maintainers.',
                        style: AppTextStyles.secondary(color: colors.fg2)
                            .copyWith(height: 1.4),
                      ),
                      const SizedBox(height: AppSpacing.space3),
                      Text(
                        '${all.length} packages',
                        style:
                            AppTextStyles.captionSemibold(color: colors.fg3),
                      ),
                    ],
                  ),
                ),
                // ── Search ─────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space5,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    style: AppTextStyles.body(color: colors.fg1),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search packages',
                      hintStyle: AppTextStyles.body(color: colors.fg3),
                      prefixIcon:
                          Icon(LumioIcons.search, color: colors.fg3, size: 20),
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkSurface
                          : AppColors.lightSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        borderSide: BorderSide(color: colors.hairline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        borderSide: BorderSide(color: colors.hairline),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space2),
                // ── List ───────────────────────────────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No packages match "$_query".',
                            style: AppTextStyles.body(color: colors.fg3),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.space5,
                            AppSpacing.space2,
                            AppSpacing.space5,
                            AppSpacing.space8,
                          ),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.space2),
                          itemBuilder: (_, i) =>
                              _LicenseCard(pkg: filtered[i], colors: colors),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Collapsible card: package name as the header, license text revealed on tap.
class _LicenseCard extends StatefulWidget {
  final _PackageLicense pkg;
  final LumioColors colors;

  const _LicenseCard({required this.pkg, required this.colors});

  @override
  State<_LicenseCard> createState() => _LicenseCardState();
}

class _LicenseCardState extends State<_LicenseCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final isDark = context.isDarkMode;
    final licenseCount = widget.pkg.paragraphs.length;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(LumioIcons.fileText,
                  color: AppColors.primary, size: 18),
            ),
            title: Text(
              widget.pkg.name,
              style: AppTextStyles.bodySemibold(color: colors.fg1),
            ),
            subtitle: Text(
              licenseCount == 1 ? '1 license' : '$licenseCount licenses',
              style: AppTextStyles.caption(color: colors.fg3),
            ),
            trailing: Icon(
              _expanded ? LumioIcons.arrowDown : LumioIcons.chevronRight,
              color: colors.fg3,
              size: 20,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                0,
                AppSpacing.space4,
                AppSpacing.space4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final text in widget.pkg.paragraphs) ...[
                    Divider(color: colors.hairline, height: AppSpacing.space5),
                    SelectableText(
                      text,
                      style: AppTextStyles.caption(color: colors.fg2)
                          .copyWith(height: 1.5, fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
