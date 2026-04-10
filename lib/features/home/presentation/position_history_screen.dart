import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:sage/core/repositories/position_repository.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/core/theme/app_theme.dart';

/// Position History — Layer 4: Forensics.
///
/// Shows closed positions with PnL, exit reason, and hold duration.
/// Redesigned to match Sage dark canvas design language.
class PositionHistoryScreen extends ConsumerWidget {
  const PositionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sage;
    final text = context.sageText;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final historyAsync = ref.watch(positionHistoryProvider);

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          // ── Top bar — circular back icon matching strategy detail ──
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, topPad + 12.h, 20.w, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
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
                const Spacer(),
                Text(
                  'TRADE HISTORY',
                  style: text.titleSmall?.copyWith(
                    color: c.textTertiary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.sp,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                SizedBox(width: 36.w),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms),

          SizedBox(height: 20.h),

          Expanded(
            child: historyAsync.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: c.accent)),
              error: (err, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIconsBold.warningCircle,
                      size: 40.sp,
                      color: c.loss,
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      'Failed to load history',
                      style: text.titleMedium?.copyWith(color: c.textPrimary),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '$err',
                      style: text.bodySmall?.copyWith(color: c.textTertiary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              data: (page) {
                if (page.positions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          PhosphorIconsBold.chartLine,
                          size: 48.sp,
                          color: c.textTertiary,
                        ),
                        SizedBox(height: 12.h),
                        Text(
                          'No closed positions yet',
                          style: text.titleMedium?.copyWith(
                            color: c.textTertiary,
                          ),
                        ),
                        SizedBox(height: 6.h),
                        Text(
                          'Positions will appear here after they close',
                          style: text.bodySmall?.copyWith(
                            color: c.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Summary stats
                final total = page.positions.length;
                final wins = page.positions
                    .where((p) => p.pnlPercent > 0)
                    .length;
                final losses = total - wins;
                final totalPnl = page.positions.fold<double>(
                  0,
                  (sum, p) => sum + (p.pnlSol ?? 0),
                );
                final winRate = total > 0
                    ? (wins / total * 100).toStringAsFixed(0)
                    : '0';

                return ListView(
                  padding: EdgeInsets.fromLTRB(28.w, 0, 28.w, bottomPad + 24.h),
                  children: [
                    // ── Overview — inline metrics on dark canvas ──
                    Text(
                      'OVERVIEW',
                      style: text.titleSmall?.copyWith(
                        fontSize: 10.sp,
                        letterSpacing: 1.5,
                        color: c.textTertiary,
                      ),
                    ).animate().fadeIn(duration: 400.ms),

                    SizedBox(height: 14.h),

                    // P&L headline — same pattern as strategy detail NET P&L
                    Text(
                      '${totalPnl >= 0 ? '+' : ''}${totalPnl.toStringAsFixed(4)} SOL',
                      style: text.displayMedium?.copyWith(
                        letterSpacing: -0.5,
                        color: totalPnl >= 0 ? c.profit : c.loss,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ).animate().fadeIn(duration: 400.ms, delay: 50.ms),

                    SizedBox(height: 6.h),

                    Text(
                      '$total trades · $winRate% win rate',
                      style: text.bodySmall?.copyWith(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                        color: c.textSecondary,
                      ),
                    ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

                    SizedBox(height: 20.h),

                    // Stat chips row — left-aligned, separated by spacing
                    Row(
                          children: [
                            _StatChip(
                              label: 'Total',
                              value: '$total',
                              c: c,
                              text: text,
                            ),
                            SizedBox(width: 24.w),
                            _StatChip(
                              label: 'Wins',
                              value: '$wins',
                              valueColor: c.profit,
                              c: c,
                              text: text,
                            ),
                            SizedBox(width: 24.w),
                            _StatChip(
                              label: 'Losses',
                              value: '$losses',
                              valueColor: c.loss,
                              c: c,
                              text: text,
                            ),
                          ],
                        )
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 150.ms)
                        .slideY(begin: 0.03, end: 0),

                    SizedBox(height: 28.h),

                    // ── Positions list ──
                    Text(
                      'POSITIONS',
                      style: text.titleSmall?.copyWith(
                        fontSize: 10.sp,
                        letterSpacing: 1.5,
                        color: c.textTertiary,
                      ),
                    ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

                    SizedBox(height: 14.h),

                    // Position rows — divider-separated, no heavy containers
                    ...page.positions.asMap().entries.map((entry) {
                      final i = entry.key;
                      final pos = entry.value;
                      final isProfitable = pos.isProfitable;
                      final pnlColor = isProfitable ? c.profit : c.loss;
                      final pnlSol = pos.pnlSol ?? 0;

                      return GestureDetector(
                            onTap: () =>
                                context.push('/position/${pos.positionId}'),
                            child: Container(
                              margin: EdgeInsets.only(bottom: 2.h),
                              padding: EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: 14.h,
                              ),
                              decoration: BoxDecoration(
                                border: i < total - 1
                                    ? Border(
                                        bottom: BorderSide(
                                          color: c.borderSubtle,
                                          width: 0.5,
                                        ),
                                      )
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  // Win/loss indicator bar
                                  Container(
                                    width: 3.w,
                                    height: 40.h,
                                    decoration: BoxDecoration(
                                      color: pnlColor.withValues(alpha: 0.8),
                                      borderRadius: BorderRadius.circular(
                                        1.5.r,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 14.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pos.poolName ??
                                              pos.poolAddress.substring(0, 8),
                                          style: text.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: c.textPrimary,
                                          ),
                                        ),
                                        SizedBox(height: 3.h),
                                        Text(
                                          '${pos.exitReason ?? 'Closed'} · ${pos.holdDurationFormatted}',
                                          style: text.labelSmall?.copyWith(
                                            color: c.textTertiary,
                                            fontSize: 10.sp,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        pos.displayPnl,
                                        style: text.titleMedium?.copyWith(
                                          color: pnlColor,
                                          fontWeight: FontWeight.w700,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        '${pnlSol >= 0 ? '+' : ''}${pnlSol.toStringAsFixed(3)} SOL',
                                        style: text.labelSmall?.copyWith(
                                          color: c.textTertiary,
                                          fontSize: 10.sp,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )
                          .animate()
                          .fadeIn(
                            duration: 300.ms,
                            delay: Duration(milliseconds: 220 + 40 * i),
                          )
                          .slideY(begin: 0.02, end: 0);
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Stat chip — inline label + value, matching strategy detail screen pattern.
class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final SageColors c;
  final TextTheme text;

  const _StatChip({
    required this.label,
    required this.value,
    this.valueColor,
    required this.c,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.labelSmall?.copyWith(
            color: c.textTertiary,
            fontSize: 10.sp,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          value,
          style: text.titleMedium?.copyWith(
            color: valueColor ?? c.textPrimary,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
