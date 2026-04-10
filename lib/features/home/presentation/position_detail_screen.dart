import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:sage/core/models/position.dart';
import 'package:sage/core/repositories/position_repository.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/core/theme/app_theme.dart';

/// Position Detail — Layer 2 of Delegate (Home) mode.
///
/// Redesigned to match Sage dark canvas design language.
/// Flat layout: circular back button, inline metrics, divider-separated rows.
class PositionDetailScreen extends ConsumerWidget {
  final String positionId;

  const PositionDetailScreen({super.key, required this.positionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sage;
    final text = context.sageText;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final posAsync = ref.watch(positionDetailProvider(positionId));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: c.background,
        body: Column(
          children: [
            // ── Top bar — circular back button ──
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
                    'POSITION',
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

            Expanded(
              child: posAsync.when(
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
                        'Failed to load position',
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
                data: (pos) =>
                    _buildContent(context, ref, c, text, bottomPad, pos),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    SageColors c,
    TextTheme text,
    double bottomPad,
    Position pos,
  ) {
    final pnlColor = pos.isProfitable ? c.profit : c.loss;
    final statusColor = pos.isActive ? c.profit : c.textTertiary;
    final statusLabel = pos.isActive ? 'Active' : 'Closed';
    final pnlSol = pos.pnlSol ?? 0;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(28.w, 24.h, 28.w, bottomPad + 24.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status + mode badges — matching strategy detail pattern
          Row(
            children: [
              Container(
                width: 8.w,
                height: 8.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              SizedBox(width: 10.w),
              Text(
                statusLabel,
                style: text.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
              const Spacer(),
              if (pos.isLive)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.w,
                    vertical: 4.h,
                  ),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    'LIVE',
                    style: text.labelSmall?.copyWith(
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.sp,
                    ),
                  ),
                ),
            ],
          ),

          SizedBox(height: 12.h),

          // Pool name
          Text(
                pos.poolName ?? pos.poolAddress.substring(0, 8),
                style: text.displayMedium?.copyWith(letterSpacing: -0.8),
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 100.ms)
              .slideY(begin: 0.04, end: 0),

          SizedBox(height: 6.h),
          Text(
            'Meteora DLMM · ${pos.source == 'live' ? 'Real-time' : 'Database'}',
            style: text.titleMedium?.copyWith(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: c.textSecondary,
            ),
          ),

          SizedBox(height: 28.h),

          // ── P&L — inline metric on dark canvas ──
          Text(
            'P&L',
            style: text.titleSmall?.copyWith(
              fontSize: 10.sp,
              letterSpacing: 1.5,
              color: c.textTertiary,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            pos.displayPnl,
            style: text.displayMedium?.copyWith(
              letterSpacing: -0.5,
              color: pnlColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 150.ms),
          SizedBox(height: 6.h),
          Text(
            '${pnlSol >= 0 ? '+' : ''}${pnlSol.toStringAsFixed(4)} SOL',
            style: text.bodySmall?.copyWith(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: c.textSecondary,
            ),
          ),

          SizedBox(height: 20.h),

          // Stat chips — flat inline
          Row(
                children: [
                  _StatChip(
                    label: 'Deposited',
                    value: '${pos.entryAmountYSol.toStringAsFixed(2)} SOL',
                    c: c,
                    text: text,
                  ),
                  SizedBox(width: 24.w),
                  _StatChip(
                    label: 'Fees',
                    value: '+${(pos.feesEarnedYSol ?? 0).toStringAsFixed(4)}',
                    valueColor: c.profit,
                    c: c,
                    text: text,
                  ),
                  SizedBox(width: 24.w),
                  _StatChip(
                    label: 'Hold Time',
                    value: pos.holdDurationFormatted,
                    c: c,
                    text: text,
                  ),
                ],
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 200.ms)
              .slideY(begin: 0.03, end: 0),

          SizedBox(height: 28.h),

          // ── Details — divider-separated rows ──
          Text(
            'DETAILS',
            style: text.titleSmall?.copyWith(
              fontSize: 10.sp,
              letterSpacing: 1.5,
              color: c.textTertiary,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 250.ms),
          SizedBox(height: 14.h),

          _DetailRow(label: 'Entry Price', value: _formatPrice(pos.entryPrice)),
          Divider(height: 1, color: c.borderSubtle),
          _DetailRow(
            label: 'Current Price',
            value: _formatPrice(pos.currentPrice),
          ),
          Divider(height: 1, color: c.borderSubtle),
          if (pos.binStep != null) ...[
            _DetailRow(label: 'Bin Step', value: '${pos.binStep}'),
            Divider(height: 1, color: c.borderSubtle),
          ],
          if (pos.entryActiveBinId != null) ...[
            _DetailRow(label: 'Entry Bin ID', value: '${pos.entryActiveBinId}'),
            Divider(height: 1, color: c.borderSubtle),
          ],
          _DetailRow(
            label: 'Entry Score',
            value: pos.entryScore.toStringAsFixed(0),
          ),
          if (pos.exitReason != null) ...[
            Divider(height: 1, color: c.borderSubtle),
            _DetailRow(label: 'Exit Reason', value: pos.exitReason!),
          ],

          SizedBox(height: 28.h),

          // ── Model Assessment — flat section ──
          Text(
            'MODEL ASSESSMENT',
            style: text.titleSmall?.copyWith(
              fontSize: 10.sp,
              letterSpacing: 1.5,
              color: c.textTertiary,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 350.ms),
          SizedBox(height: 14.h),

          // ML confidence row
          _DetailRow(
            label: 'ML Confidence',
            value: pos.mlProbability != null
                ? '${(pos.mlProbability! * 100).toStringAsFixed(0)}%'
                : 'N/A',
          ),

          SizedBox(height: 8.h),

          // Confidence bar — thin, flat
          ClipRRect(
            borderRadius: BorderRadius.circular(2.r),
            child: LinearProgressIndicator(
              value: pos.mlProbability ?? 0,
              minHeight: 4.h,
              backgroundColor: c.borderSubtle,
              valueColor: AlwaysStoppedAnimation(c.accent),
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 400.ms),

          SizedBox(height: 12.h),

          Text(
            pos.mlProbability != null
                ? 'XGBoost V3 model prediction. '
                      'Entry score: ${pos.entryScore.toStringAsFixed(0)} · Source: ${pos.source}'
                : 'No ML prediction available. '
                      'This position was entered by rule-based scoring.',
            style: text.bodySmall?.copyWith(
              height: 1.5,
              color: c.textTertiary,
              fontSize: 12.sp,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 420.ms),

          SizedBox(height: 32.h),

          // Close button (active positions only)
          if (pos.isActive)
            GestureDetector(
              onTap: () => _confirmClose(context, ref, pos),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 16.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: c.loss.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(PhosphorIconsBold.x, size: 16.sp, color: c.loss),
                    SizedBox(width: 8.w),
                    Text(
                      'Close Position',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.loss,
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 500.ms),
        ],
      ),
    );
  }

  Future<void> _confirmClose(
    BuildContext context,
    WidgetRef ref,
    Position pos,
  ) async {
    HapticFeedback.mediumImpact();
    final c = context.sage;
    final text = context.sageText;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: c.surfaceElevated,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
          border: Border(top: BorderSide(color: c.border, width: 1)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24.w,
            12.h,
            24.w,
            MediaQuery.of(ctx).padding.bottom + 24.h,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: c.textTertiary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Close Position',
                  style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                'This will remove liquidity, claim fees, and swap '
                'leftover tokens back to SOL.',
                style: text.bodyMedium?.copyWith(
                  color: c.textSecondary,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 24.h),
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(true),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  decoration: BoxDecoration(
                    color: c.loss,
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Center(
                    child: Text(
                      'Confirm Close',
                      style: text.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(false),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    child: Text(
                      'Cancel',
                      style: text.bodyMedium?.copyWith(color: c.textTertiary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      final repo = ref.read(positionRepositoryProvider);
      final pnl = await repo.closePosition(positionId);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Position closed  ·  P&L: ${pnl >= 0 ? "+" : ""}${pnl.toStringAsFixed(4)} SOL',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to close: $e')));
    }
  }

  String _formatPrice(double price) {
    if (price == 0) return '\u2014';
    if (price < 0.0001) return price.toStringAsExponential(3);
    if (price < 1) return price.toStringAsFixed(6);
    return price.toStringAsFixed(4);
  }
}

/// Stat chip — inline label + value, matching strategy detail pattern.
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

/// Flat key-value row used in detail sections — matches ParamRow pattern.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.sage;
    final text = context.sageText;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: text.titleMedium?.copyWith(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
          Text(
            value,
            style: text.titleMedium?.copyWith(
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
