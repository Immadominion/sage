import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:sage/core/repositories/position_repository.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/core/theme/app_theme.dart';

/// Active positions section — fetched from /position/active endpoint.
class PositionsSection extends ConsumerWidget {
  const PositionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sage;
    final text = context.sageText;

    final posAsync = ref.watch(activePositionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACTIVE POSITIONS',
          style: text.titleSmall?.copyWith(color: c.panelTextSecondary),
        ),
        SizedBox(height: 8.h),
        posAsync.when(
          skipLoadingOnReload: true,
          loading: () => Padding(
            padding: EdgeInsets.symmetric(vertical: 20.h),
            child: Center(
              child: SizedBox(
                width: 20.w,
                height: 20.w,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.panelTextSecondary,
                ),
              ),
            ),
          ),
          error: (err, _) => Padding(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            child: Text(
              'Failed to load positions',
              style: text.bodySmall?.copyWith(color: c.panelTextSecondary),
            ),
          ),
          data: (positions) {
            if (positions.isEmpty) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 20.h),
                child: Column(
                  children: [
                    Icon(
                      PhosphorIconsDuotone.receiptX,
                      size: 32.w,
                      color: c.panelTextSecondary,
                    ),
                    Center(
                      child: Text(
                        'Nothing Here',
                        style: text.bodySmall?.copyWith(
                          color: c.panelTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: positions.take(2).map((pos) {
                final pnlColor = pos.isProfitable ? c.profit : c.loss;
                return GestureDetector(
                  onTap: () => context.push('/position/${pos.positionId}'),
                  child: Container(
                    margin: EdgeInsets.only(bottom: 10.h),
                    padding: EdgeInsets.all(14.w),
                    decoration: BoxDecoration(
                      color: c.panelBorder.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pos.poolName ?? pos.poolAddress.substring(0, 8),
                                style: text.titleMedium?.copyWith(
                                  color: c.panelText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 3.h),
                              Text(
                                '${pos.entryAmountYSol.toStringAsFixed(1)} SOL \u00b7 ${pos.holdDurationFormatted}',
                                style: text.labelMedium?.copyWith(
                                  color: c.panelTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          pos.displayPnl,
                          style: text.titleMedium?.copyWith(
                            color: pnlColor,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
