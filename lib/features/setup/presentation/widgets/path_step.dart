import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:sage/core/config/live_trading_flags.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/features/setup/models/risk_profile.dart';
import 'package:sage/features/setup/presentation/widgets/path_card.dart';
import 'package:sage/features/setup/presentation/widgets/step_indicator.dart';
import 'package:sage/shared/widgets/sage_button.dart';

/// Step 1 — Choose path (Sage AI / Custom) + execution mode radio.
class PathStep extends StatelessWidget {
  final SetupPath? selected;
  final ValueChanged<SetupPath> onSelect;
  final ExecutionMode mode;
  final ValueChanged<ExecutionMode> onModeChanged;
  final VoidCallback onNext;
  final VoidCallback? onSkip;
  final VoidCallback? onClose;
  final SageColors c;
  final TextTheme text;

  /// Optional name input — shown when creating a new strategy (not during
  /// initial setup).  When non-null a styled text field appears above the
  /// path cards so the user can name the bot before choosing a path.
  final TextEditingController? nameController;

  const PathStep({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.mode,
    required this.onModeChanged,
    required this.onNext,
    this.onSkip,
    this.onClose,
    this.nameController,
    required this.c,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = kLiveTradingEnabled && mode == ExecutionMode.live;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 28.w),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 16.h),

                  // ── Close button (when used outside setup wizard) ──
                  if (onClose != null) ...[
                    GestureDetector(
                      onTap: onClose,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 12.h),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIconsBold.caretLeft,
                              size: 16.sp,
                              color: c.accent,
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              'Cancel',
                              style: text.titleMedium?.copyWith(
                                color: c.accent,
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // ── Step indicator ──
                  StepIndicator(current: 0, total: 3, c: c),

                  SizedBox(height: 32.h),

                  // ── Headline ──
                  Text(
                        'How should Sage\nwork for you?',
                        style: text.headlineLarge,
                      )
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),

                  SizedBox(height: 12.h),

                  Text(
                    'Choose how you want to deploy capital.\n'
                    'You can always change this later.',
                    style: text.bodyMedium?.copyWith(color: c.textSecondary),
                  ).animate().fadeIn(duration: 500.ms, delay: 150.ms),

                  // ── Optional name input ──
                  if (nameController != null) ...[
                    SizedBox(height: 16.h),
                    TextField(
                      controller: nameController,
                      style: text.bodyMedium?.copyWith(color: c.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Strategy name (optional)',
                        hintStyle: text.bodyMedium?.copyWith(
                          color: c.textSecondary.withValues(alpha: 0.5),
                        ),
                        filled: true,
                        fillColor: c.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide(color: c.accent, width: 1),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 14.h,
                        ),
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(left: 12.w, right: 8.w),
                          child: Icon(
                            PhosphorIconsRegular.pencilSimpleLine,
                            size: 18.sp,
                            color: c.textSecondary,
                          ),
                        ),
                        prefixIconConstraints: BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                      ),
                    ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                  ],

                  SizedBox(height: 24.h),

                  // ── Sage AI card ──
                  PathCard(
                        icon: PhosphorIconsBold.sparkle,
                        title: 'Sage AI',
                        subtitle: 'Delegate to intelligence',
                        description:
                            'ML-powered LP positions on Meteora. '
                            'Set your limits — Sage finds the opportunities.',
                        isSelected: selected == SetupPath.sageAi,
                        isRecommended: true,
                        onTap: () => onSelect(SetupPath.sageAi),
                        c: c,
                        text: text,
                      )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 200.ms)
                      .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),

                  SizedBox(height: 12.h),

                  // ── Custom Strategy card ──
                  PathCard(
                        icon: PhosphorIconsBold.folderSimpleUser,
                        title: 'Custom Strategy',
                        subtitle: 'Build your own rules',
                        description:
                            'Define entry conditions, triggers, and risk parameters. '
                            'Your strategy runs 24/7.',
                        isSelected: selected == SetupPath.custom,
                        isRecommended: false,
                        onTap: () => onSelect(SetupPath.custom),
                        c: c,
                        text: text,
                      )
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 300.ms)
                      .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),

                  const Spacer(),

                  // ── Mode radio ──
                  Row(
                    children: [
                      _StatusPill(
                        label: 'Simulation',
                        isSelected:
                            mode == ExecutionMode.simulation ||
                            !kLiveTradingEnabled,
                        activeBgColor: const Color(0xFFE5F0FF),
                        activeBorderColor: const Color(0xFFB4C8F0),
                        activeTextColor: const Color(0xFF1E3A5F),
                        icon: PhosphorIconsRegular.warningCircle,
                        onTap: () => onModeChanged(ExecutionMode.simulation),
                        c: c,
                        text: text,
                      ),
                      SizedBox(width: 10.w),
                      _StatusPill(
                        label: 'Live',
                        isSelected:
                            kLiveTradingEnabled && mode == ExecutionMode.live,
                        activeBgColor: const Color(0xFFF5E6FF),
                        activeBorderColor: const Color(0xFFD4BFEB),
                        activeTextColor: const Color(0xFF4A1E7B),
                        icon: PhosphorIconsRegular.spinnerGap,
                        onTap: () => onModeChanged(ExecutionMode.live),
                        enabled: kLiveTradingEnabled,
                        c: c,
                        text: text,
                      ),
                    ],
                  ).animate().fadeIn(duration: 400.ms, delay: 350.ms),

                  if (!kLiveTradingEnabled)
                    Padding(
                      padding: EdgeInsets.only(top: 8.h),
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIconsBold.info,
                            size: 13.sp,
                            color: c.textTertiary,
                          ),
                          SizedBox(width: 6.w),
                          Expanded(
                            child: Text(
                              kLiveTradingDisabledReason,
                              style: text.bodySmall?.copyWith(
                                color: c.textTertiary,
                                fontSize: 11.sp,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Live warning ──
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: EdgeInsets.only(top: 8.h),
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIconsBold.warningCircle,
                            size: 13.sp,
                            color: c.warning,
                          ),
                          SizedBox(width: 6.w),
                          Expanded(
                            child: Text(
                              'Real SOL from your wallet. Losses are permanent.',
                              style: text.bodySmall?.copyWith(
                                color: c.warning,
                                fontSize: 11.sp,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    crossFadeState: isLive
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),

                  SizedBox(height: 14.h),

                  // ── Continue ──
                  SageButton(
                    label: 'Continue',
                    onPressed: onNext,
                    enabled: selected != null,
                  ).animate().fadeIn(duration: 400.ms, delay: 400.ms),

                  SizedBox(height: 12.h),

                  // ── Skip ──
                  if (onSkip != null)
                    Center(
                      child: GestureDetector(
                        onTap: onSkip,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.h),
                          child: Text(
                            'I\'ll explore first',
                            style: text.titleMedium?.copyWith(
                              color: c.textTertiary,
                              fontSize: 14.sp,
                            ),
                          ),
                        ),
                      ),
                    ).animate().fadeIn(duration: 400.ms, delay: 500.ms),

                  SizedBox(height: 16.h),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Simple status pill ──────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color activeBgColor;
  final Color activeBorderColor;
  final Color activeTextColor;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final SageColors c;
  final TextTheme text;

  const _StatusPill({
    required this.label,
    required this.isSelected,
    required this.activeBgColor,
    required this.activeBorderColor,
    required this.activeTextColor,
    required this.icon,
    required this.onTap,
    this.enabled = true,
    required this.c,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected
              ? activeBgColor
              : enabled
              ? Colors.transparent
              : c.surface,
          borderRadius: BorderRadius.circular(100.r),
          border: Border.all(
            color: isSelected ? activeBorderColor : c.borderSubtle,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16.sp,
              color: isSelected
                  ? activeTextColor
                  : enabled
                  ? c.textTertiary
                  : c.textTertiary.withValues(alpha: 0.45),
            ),
            SizedBox(width: 6.w),
            Text(
              label,
              style: text.bodyMedium?.copyWith(
                color: isSelected
                    ? activeTextColor
                    : enabled
                    ? c.textSecondary
                    : c.textTertiary.withValues(alpha: 0.65),
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                fontSize: 14.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
