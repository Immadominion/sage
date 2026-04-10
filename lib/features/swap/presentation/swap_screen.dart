import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:sage/core/models/bot.dart';
import 'package:sage/core/repositories/bot_repository.dart';
import 'package:sage/core/repositories/ml_repository.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/core/theme/app_theme.dart';
import 'package:sage/shared/widgets/sage_components.dart';
import 'package:sage/features/swap/presentation/widgets/model_card.dart';
import 'package:sage/features/swap/presentation/widgets/metric_box.dart';
import 'package:sage/features/swap/presentation/widgets/fleet_info_row.dart';

/// Intelligence Mode — AI brain overview + ML model status.
///
/// Shows: Sage greeting, ML model health, model metrics,
/// aggregated bot performance, and strategy mode context.
class SwapScreen extends ConsumerWidget {
  const SwapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sage;
    final text = context.sageText;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final mlHealthAsync = ref.watch(mlHealthProvider);
    final botsAsync = ref.watch(botListProvider);

    return Scaffold(
      backgroundColor: c.background,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          28.w,
          topPad + 48.h,
          28.w,
          bottomPad + 80.h,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Label ──
            const SageLabel('Intelligence'),

            SizedBox(height: 20.h),

            // ── Greeting ──
            Text(
                  'Hello',
                  style: text.displayLarge?.copyWith(
                    fontSize: 48.sp,
                    letterSpacing: -2.0,
                    height: 1.1,
                  ),
                )
                .animate()
                .fadeIn(duration: 800.ms, delay: 200.ms)
                .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),

            SizedBox(height: 28.h),

            // ── ML Model Status ──
            mlHealthAsync
                .when(
                  skipLoadingOnReload: true,
                  loading: () => ModelCard(
                    status: 'Loading...',
                    statusColor: c.textTertiary,
                    icon: PhosphorIconsBold.circleNotch,
                    c: c,
                    text: text,
                    children: const [],
                  ),
                  error: (e, st) => ModelCard(
                    status: 'ML Offline',
                    statusColor: c.loss,
                    icon: PhosphorIconsBold.xCircle,
                    c: c,
                    text: text,
                    children: [
                      Text(
                        'The ML prediction server is not reachable. '
                        'Bots using Sage AI mode will pause scanning until the service recovers.',
                        style: text.bodySmall?.copyWith(
                          color: c.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      GestureDetector(
                        onTap: () => ref.invalidate(mlHealthProvider),
                        child: Text(
                          'Retry',
                          style: text.labelMedium?.copyWith(
                            color: c.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  data: (health) => ModelCard(
                    status: health.isHealthy
                        ? 'Model Active'
                        : 'Model Unhealthy',
                    statusColor: health.isHealthy ? c.profit : c.warning,
                    icon: health.isHealthy
                        ? PhosphorIconsBold.brain
                        : PhosphorIconsBold.warningCircle,
                    c: c,
                    text: text,
                    children: [
                      // Model version + features
                      Text(
                        'XGBoost ${health.modelVersion} · ${health.featureCount} features',
                        style: text.bodySmall?.copyWith(
                          color: c.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      SizedBox(height: 16.h),
                      // Metrics row
                      Row(
                        children: [
                          MetricBox(
                            label: 'ROC AUC',
                            value: health.rocAuc.toStringAsFixed(3),
                            c: c,
                            text: text,
                          ),
                          SizedBox(width: 8.w),
                          MetricBox(
                            label: 'PRECISION',
                            value:
                                '${(health.precision * 100).toStringAsFixed(1)}%',
                            c: c,
                            text: text,
                          ),
                          SizedBox(width: 8.w),
                          MetricBox(
                            label: 'THRESHOLD',
                            value: health.threshold.toStringAsFixed(4),
                            c: c,
                            text: text,
                          ),
                        ],
                      ),
                    ],
                  ),
                )
                .animate()
                .fadeIn(duration: 600.ms, delay: 600.ms)
                .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),

            SizedBox(height: 24.h),

            // ── Bot Performance Summary ──
            botsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e1, st1) => const SizedBox.shrink(),
              data: (bots) {
                if (bots.isEmpty) {
                  return Text(
                    'No bots deployed yet. Go to Control to create one.',
                    style: text.bodySmall?.copyWith(
                      color: c.textTertiary,
                      height: 1.5,
                    ),
                  ).animate().fadeIn(duration: 600.ms, delay: 1000.ms);
                }

                final running = bots.where((b) => b.engineRunning).length;
                final totalPnl = bots.fold<double>(
                  0,
                  (s, b) =>
                      s + (b.performanceSummary?.totalPnlSol ?? b.totalPnlSOL),
                );
                final totalTrades = bots.fold<int>(
                  0,
                  (s, b) =>
                      s + (b.engineStats?.positionsOpened ?? b.totalTrades),
                );
                final sageAiBots = bots
                    .where(
                      (b) =>
                          b.strategyMode == StrategyMode.sageAi ||
                          b.strategyMode == StrategyMode.both,
                    )
                    .length;

                final pnlColor = totalPnl >= 0 ? c.profit : c.loss;
                final pnlStr = totalPnl >= 0
                    ? '+${totalPnl.toStringAsFixed(4)} SOL'
                    : '${totalPnl.toStringAsFixed(4)} SOL';

                return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FLEET OVERVIEW',
                          style: text.titleSmall?.copyWith(
                            fontSize: 10.sp,
                            letterSpacing: 1.5,
                            color: c.textTertiary,
                          ),
                        ),
                        SizedBox(height: 14.h),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(20.w),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(16.r),
                            border: Border.all(color: c.borderSubtle),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pnlStr,
                                style: text.displaySmall?.copyWith(
                                  color: pnlColor,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                'Aggregate P&L across ${bots.length} bots',
                                style: text.bodySmall?.copyWith(
                                  color: c.textSecondary,
                                ),
                              ),
                              SizedBox(height: 16.h),
                              FleetInfoRow(
                                items: [
                                  FleetInfo('Running', '$running'),
                                  FleetInfo('Trades', '$totalTrades'),
                                  FleetInfo('AI-Powered', '$sageAiBots'),
                                ],
                                c: c,
                                text: text,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                    .animate()
                    .fadeIn(duration: 600.ms, delay: 1000.ms)
                    .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
              },
            ),

            SizedBox(height: 32.h),

            // ── Intelligence note ──
            Text(
              'LAST UPDATED',
              style: text.titleSmall?.copyWith(
                fontSize: 10.sp,
                fontWeight: FontWeight.w800,
                color: c.textTertiary,
              ),
            ).animate().fadeIn(duration: 600.ms, delay: 1400.ms),
            SizedBox(height: 4.h),
            Text(
              'Just now',
              style: text.bodySmall?.copyWith(color: c.textTertiary),
            ).animate().fadeIn(duration: 600.ms, delay: 1400.ms),
          ],
        ),
      ),
    );
  }
}
