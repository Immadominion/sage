import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/core/theme/app_theme.dart';
import 'package:sage/features/fleet/data/fleet_repository.dart';
import 'package:sage/features/fleet/models/fleet_models.dart';
import 'package:sage/features/fleet/presentation/widgets/fleet_card.dart';
import 'package:sage/shared/widgets/sage_components.dart';
import 'package:sage/features/automate/presentation/widgets/stat_chip.dart';

/// Fleet — pushed over app shell from Automate CTA.
///
/// Platform-wide leaderboard of top-performing bots.
/// Consistent with Automate screen — SageLabel, SageMetric, bare stats.
class FleetScreen extends ConsumerStatefulWidget {
  const FleetScreen({super.key});

  @override
  ConsumerState<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends ConsumerState<FleetScreen> {
  String _sort = 'pnl';

  @override
  Widget build(BuildContext context) {
    final c = context.sage;
    final text = context.sageText;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final leaderboardAsync = ref.watch(fleetLeaderboardProvider(_sort));
    final statsAsync = ref.watch(fleetStatsProvider);

    return Scaffold(
      backgroundColor: c.background,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          28.w,
          topPad + 12.h,
          28.w,
          bottomPad + 80.h,
        ),
        children: [
          // ── Back button ──
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surface,
                  border: Border.all(color: c.borderSubtle, width: 1),
                ),
                child: Icon(
                  PhosphorIconsBold.arrowLeft,
                  size: 20.sp,
                  color: c.textSecondary,
                ),
              ),
            ),
          ),

          SizedBox(height: 16.h),

          // ── Label ──
          const SageLabel('Fleet'),

          SizedBox(height: 20.h),

          // ── Platform stats hero ──
          statsAsync.when(
            skipLoadingOnReload: true,
            loading: () => _buildStatsPlaceholder(c, text),
            error: (_, _) => _buildStatsPlaceholder(c, text),
            data: (stats) => _buildStatsHero(c, text, stats),
          ),

          SizedBox(height: 28.h),

          // ── Sort strip ──
          Row(
            children: [
              _SortChip(
                label: 'PnL',
                value: 'pnl',
                current: _sort,
                c: c,
                text: text,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _sort = 'pnl');
                },
              ),
              SizedBox(width: 14.w),
              _SortChip(
                label: 'Win Rate',
                value: 'winRate',
                current: _sort,
                c: c,
                text: text,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _sort = 'winRate');
                },
              ),
              SizedBox(width: 14.w),
              _SortChip(
                label: 'Trades',
                value: 'trades',
                current: _sort,
                c: c,
                text: text,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _sort = 'trades');
                },
              ),
            ],
          ),

          SizedBox(height: 28.h),

          // ── Section label ──
          Text(
            'LEADERBOARD',
            style: text.titleSmall?.copyWith(
              color: c.textTertiary,
              letterSpacing: 1.5,
            ),
          ),

          SizedBox(height: 16.h),

          // ── Leaderboard ──
          leaderboardAsync.when(
            skipLoadingOnReload: true,
            loading: () => Padding(
              padding: EdgeInsets.only(top: 40.h),
              child: Center(
                child: CircularProgressIndicator(
                  color: c.accent,
                  strokeWidth: 2,
                ),
              ),
            ),
            error: (err, _) => Padding(
              padding: EdgeInsets.only(top: 40.h),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      PhosphorIconsBold.wifiSlash,
                      size: 28.sp,
                      color: c.textTertiary,
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      'Could not load leaderboard',
                      style: text.bodySmall?.copyWith(color: c.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
            data: (entries) => entries.isEmpty
                ? _buildEmptyState(c, text)
                : Column(
                    children: entries.asMap().entries.map((mapEntry) {
                      final i = mapEntry.key;
                      final entry = mapEntry.value;
                      return Column(
                        children: [
                          if (i > 0)
                            Divider(
                              height: 1,
                              thickness: 0.5,
                              color: c.borderSubtle,
                            ),
                          FleetCard(entry: entry, c: c, text: text),
                        ],
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHero(SageColors c, TextTheme text, FleetStats stats) {
    final pnlAbs = stats.totalPnlSol.abs();
    final pnlWhole = pnlAbs.toStringAsFixed(2).split('.')[0];
    final pnlDecimal = '.${pnlAbs.toStringAsFixed(2).split('.')[1]} SOL';
    final pnlPrefix = stats.totalPnlSol >= 0 ? '+' : '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SageMetric(
          '$pnlPrefix$pnlWhole',
          decimal: pnlDecimal,
          color: stats.totalPnlSol >= 0 ? c.profit : c.loss,
        ),

        SizedBox(height: 12.h),

        Row(
          children: [
            Text(
              '${stats.runningBots} active · ${stats.totalTrades} trades',
              style: text.bodySmall?.copyWith(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: c.textSecondary,
              ),
            ),
          ],
        ),

        SizedBox(height: 20.h),

        // ── Quick stats — bare, no containers ──
        Row(
          children: [
            StatChip(
              label: 'Public Bots',
              value: '${stats.publicBots}',
              c: c,
              text: text,
            ),
            SizedBox(width: 24.w),
            StatChip(
              label: 'Avg Win Rate',
              value: '${stats.avgWinRatePercent}%',
              c: c,
              text: text,
            ),
            SizedBox(width: 24.w),
            StatChip(
              label: 'Trades',
              value: '${stats.totalTrades}',
              c: c,
              text: text,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsPlaceholder(SageColors c, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SageMetric('…', decimal: ' SOL'),
        SizedBox(height: 10.h),
        Text(
          'Loading fleet stats…',
          style: text.bodySmall?.copyWith(
            fontSize: 13.sp,
            color: c.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(SageColors c, TextTheme text) {
    return Padding(
      padding: EdgeInsets.only(top: 60.h),
      child: Center(
        child: Column(
          children: [
            Icon(
              PhosphorIconsBold.trophy,
              size: 36.sp,
              color: c.textTertiary.withValues(alpha: 0.5),
            ),
            SizedBox(height: 16.h),
            Text(
              'No bots on the leaderboard yet',
              style: text.bodyMedium?.copyWith(color: c.textTertiary),
            ),
            SizedBox(height: 6.h),
            Text(
              'Make your bot public from the Automate tab\nto appear here.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                color: c.textTertiary.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Sort chip — minimal, text-only active indicator
// ─────────────────────────────────────────────────────────

class _SortChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final SageColors c;
  final TextTheme text;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.value,
    required this.current,
    required this.c,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = value == current;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(
              color: isActive ? c.textPrimary : c.textTertiary,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12.sp,
            ),
          ),
          SizedBox(height: 4.h),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: isActive ? 16.w : 0,
            height: 2.h,
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(1.r),
            ),
          ),
        ],
      ),
    );
  }
}
