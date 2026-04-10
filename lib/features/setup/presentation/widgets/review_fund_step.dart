import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:sage/core/config/simulation_defaults.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/features/setup/models/risk_profile.dart';
import 'package:sage/features/setup/presentation/widgets/step_indicator.dart';
import 'package:sage/shared/widgets/sage_bottom_sheet.dart';
import 'package:sage/shared/widgets/sage_button.dart';

/// Step 3 — Review configuration, fund wallet (live), accept disclaimers,
/// and activate.
///
/// Flat layout with no heavy containers — uses subtle dividers and inline
/// text to stay consistent with the rest of the setup wizard.
class ReviewFundStep extends StatefulWidget {
  final SetupPath path;
  final ExecutionMode mode;
  final double positionSizeSOL;
  final double simulationBalanceSOL;
  final ValueChanged<double>? onSimulationBalanceChanged;
  final int maxConcurrentPositions;
  final double profitTargetPercent;
  final double stopLossPercent;
  final double maxDailyLossSOL;

  final VoidCallback onBack;
  final VoidCallback? onSkip;

  /// Called when user confirms — for live mode includes the deposit amount.
  final Future<void> Function(double? depositSol) onActivate;

  final bool isActivating;

  /// Status message shown below the deploy button during activation.
  final String? statusMessage;

  /// Whether to show the funding/deposit section (initial setup only).
  /// When false (e.g. creating an additional bot), the wallet already
  /// exists and we skip the deposit slider.
  final bool showFunding;

  /// Override the activate button label.
  final String? activateLabel;

  final SageColors c;
  final TextTheme text;

  const ReviewFundStep({
    super.key,
    required this.path,
    required this.mode,
    required this.positionSizeSOL,
    required this.simulationBalanceSOL,
    this.onSimulationBalanceChanged,
    required this.maxConcurrentPositions,
    required this.profitTargetPercent,
    required this.stopLossPercent,
    required this.maxDailyLossSOL,
    required this.onBack,
    this.onSkip,
    required this.onActivate,
    required this.isActivating,
    this.statusMessage,
    this.showFunding = true,
    this.activateLabel,
    required this.c,
    required this.text,
  });

  @override
  State<ReviewFundStep> createState() => _ReviewFundStepState();
}

class _ReviewFundStepState extends State<ReviewFundStep> {
  late double _depositAmount;
  late double _simulationBalanceAmount;
  bool _disclaimerAccepted = false;

  double get _recommended =>
      widget.positionSizeSOL * widget.maxConcurrentPositions;
  double get _simulationRecommended => recommendedSimulationBalanceSOL(
    positionSizeSOL: widget.positionSizeSOL,
    maxConcurrentPositions: widget.maxConcurrentPositions,
  );
  double get _simulationMinimum =>
      minimumSimulationBalanceSOL(widget.positionSizeSOL);
  // Minimum = position size + 0.075 SOL overhead (rent + fees + finalization),
  // rounded up to nearest 0.05 SOL
  double get _minimum =>
      ((widget.positionSizeSOL + 0.075) * 20).ceilToDouble() / 20;
  double get _profitPerTrade =>
      widget.positionSizeSOL * (widget.profitTargetPercent / 100);
  double get _lossPerTrade =>
      widget.positionSizeSOL * (widget.stopLossPercent / 100);
  bool get _isLive => widget.mode == ExecutionMode.live;

  @override
  void initState() {
    super.initState();
    _depositAmount = math.max(_recommended, _minimum);
    _simulationBalanceAmount = clampSimulationBalanceSOL(
      requested: widget.simulationBalanceSOL,
      positionSizeSOL: widget.positionSizeSOL,
    );
  }

  @override
  void didUpdateWidget(covariant ReviewFundStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionSizeSOL != widget.positionSizeSOL ||
        oldWidget.simulationBalanceSOL != widget.simulationBalanceSOL) {
      _simulationBalanceAmount = clampSimulationBalanceSOL(
        requested: widget.simulationBalanceSOL,
        positionSizeSOL: widget.positionSizeSOL,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: 28.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 16.h),

          // ── Back ──
          GestureDetector(
            onTap: widget.onBack,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIconsBold.caretLeft,
                    size: 16.sp,
                    color: widget.c.accent,
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    'Back',
                    style: widget.text.titleMedium?.copyWith(
                      color: widget.c.accent,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          StepIndicator(current: 2, total: 3, c: widget.c),

          SizedBox(height: 28.h),

          // ── Headline ──
          Text(
                _isLive ? 'Review &\nFund' : 'Review &\nActivate',
                style: widget.text.headlineLarge,
              )
              .animate()
              .fadeIn(duration: 600.ms)
              .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),

          SizedBox(height: 8.h),

          Text(
            'Confirm your setup before launching.',
            style: widget.text.bodyMedium?.copyWith(
              color: widget.c.textSecondary,
            ),
          ).animate().fadeIn(duration: 500.ms, delay: 100.ms),

          SizedBox(height: 28.h),

          // ───────────── CONFIGURATION ─────────────
          _sectionLabel(
            'CONFIGURATION',
          ).animate().fadeIn(duration: 400.ms, delay: 150.ms),

          SizedBox(height: 14.h),

          // Path + Mode (inline)
          Row(
            children: [
              Icon(
                widget.path == SetupPath.sageAi
                    ? PhosphorIconsBold.sparkle
                    : PhosphorIconsBold.folderSimpleUser,
                size: 14.sp,
                color: widget.c.accent,
              ),
              SizedBox(width: 6.w),
              Text(
                widget.path == SetupPath.sageAi ? 'Sage AI' : 'Custom Strategy',
                style: widget.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: widget.c.textPrimary,
                ),
              ),
              SizedBox(width: 8.w),
              _modePill(),
            ],
          ).animate().fadeIn(duration: 400.ms, delay: 170.ms),

          SizedBox(height: 16.h),

          _kvRow('Position Size', '${widget.positionSizeSOL} SOL'),
          SizedBox(height: 10.h),
          _kvRow('Max Positions', '${widget.maxConcurrentPositions}'),
          SizedBox(height: 10.h),
          _kvRow('Daily Loss Limit', '${widget.maxDailyLossSOL} SOL'),

          SizedBox(height: 24.h),

          // ───────────── PER TRADE ─────────────
          _sectionLabel(
            'PER TRADE',
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

          SizedBox(height: 14.h),

          _kvRow(
            'Profit Target',
            '+${widget.profitTargetPercent.toStringAsFixed(0)}%',
            trailing: '+${_profitPerTrade.toStringAsFixed(3)} SOL',
            trailingColor: widget.c.profit,
          ),
          SizedBox(height: 10.h),
          _kvRow(
            'Stop Loss',
            '-${widget.stopLossPercent.toStringAsFixed(0)}%',
            trailing: '-${_lossPerTrade.toStringAsFixed(3)} SOL',
            trailingColor: widget.c.loss,
          ),

          SizedBox(height: 24.h),

          // ───────────── FUND WALLET / SIM INFO ─────────────
          if (widget.showFunding && _isLive) ...[
            _sectionLabel(
              'FUND WALLET',
            ).animate().fadeIn(duration: 400.ms, delay: 250.ms),
            SizedBox(height: 10.h),

            // Tappable deposit amount row — opens slider editor sheet
            GestureDetector(
              onTap: _openDepositEditor,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Row(
                  children: [
                    Text(
                      'Deposit Amount',
                      style: widget.text.titleMedium?.copyWith(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: widget.c.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_depositAmount.toStringAsFixed(1)} SOL',
                      style: widget.text.titleMedium?.copyWith(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: widget.c.accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(width: 6.w),
                    Icon(
                      PhosphorIconsBold.pencilSimple,
                      size: 12.sp,
                      color: widget.c.textTertiary.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 260.ms),

            // Recommendation hint
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Text(
                'Recommended: ${_recommended.toStringAsFixed(1)} SOL '
                '(${widget.positionSizeSOL.toStringAsFixed(1)} × ${widget.maxConcurrentPositions} positions)',
                style: widget.text.bodySmall?.copyWith(
                  color: widget.c.textTertiary,
                  fontSize: 11.sp,
                ),
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 265.ms),

            SizedBox(height: 14.h),

            Text(
              'This is your bot\'s trading capital. '
              'One wallet approval covers everything. '
              'You can deposit more or withdraw anytime.',
              style: widget.text.bodySmall?.copyWith(
                color: widget.c.textSecondary,
                fontSize: 12.sp,
                height: 1.5,
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 270.ms),
          ] else if (!_isLive) ...[
            _sectionLabel(
              'SIMULATION CAPITAL',
            ).animate().fadeIn(duration: 400.ms, delay: 250.ms),
            SizedBox(height: 10.h),
            GestureDetector(
              onTap: _openSimulationBalanceEditor,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Row(
                  children: [
                    Text(
                      'Virtual Capital',
                      style: widget.text.titleMedium?.copyWith(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: widget.c.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_simulationBalanceAmount.toStringAsFixed(1)} SOL',
                      style: widget.text.titleMedium?.copyWith(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: widget.c.accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(width: 6.w),
                    Icon(
                      PhosphorIconsBold.pencilSimple,
                      size: 12.sp,
                      color: widget.c.textTertiary.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 260.ms),
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Text(
                'Minimum viable balance: ${_simulationMinimum.toStringAsFixed(1)} SOL. '
                'Recommended: ${_simulationRecommended.toStringAsFixed(1)} SOL.',
                style: widget.text.bodySmall?.copyWith(
                  color: widget.c.textTertiary,
                  fontSize: 11.sp,
                ),
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 265.ms),
            SizedBox(height: 14.h),
            Text(
              'No wallet needed — you\'re trading with virtual SOL '
              'using real market data. This only affects the simulation bankroll.',
              style: widget.text.bodySmall?.copyWith(
                color: widget.c.textTertiary,
                fontSize: 12.sp,
                height: 1.5,
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 250.ms),
          ],

          SizedBox(height: 28.h),

          // ───────────── DISCLAIMERS ─────────────
          _buildDisclaimerSection().animate().fadeIn(
            duration: 400.ms,
            delay: 300.ms,
          ),

          SizedBox(height: 28.h),

          // ── Activate ──
          SageButton(
            label:
                widget.activateLabel ??
                (_isLive ? 'Deploy & Fund Bot' : 'Activate'),
            onPressed: () => widget.onActivate(
              widget.showFunding && _isLive ? _depositAmount : null,
            ),
            isLoading: widget.isActivating,
            enabled: _disclaimerAccepted && !widget.isActivating,
          ).animate().fadeIn(duration: 400.ms, delay: 350.ms),

          // ── Deploy status message ──
          if (widget.isActivating &&
              widget.statusMessage != null &&
              widget.statusMessage!.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 12.h),
              child: Center(
                child: Text(
                  widget.statusMessage!,
                  style: widget.text.bodySmall?.copyWith(
                    color: widget.c.textSecondary,
                    fontSize: 12.sp,
                  ),
                ),
              ),
            ),

          SizedBox(height: 12.h),

          // ── Skip ──
          if (widget.onSkip != null)
            Center(
              child: GestureDetector(
                onTap: widget.onSkip,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                  child: Text(
                    'I\'ll explore first',
                    style: widget.text.titleMedium?.copyWith(
                      color: widget.c.textTertiary,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 400.ms),

          SizedBox(height: 28.h),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // Section label — matches _SectionDivider from CustomStrategyStep
  // ────────────────────────────────────────────────────────────

  Widget _sectionLabel(String title) {
    return Row(
      children: [
        Text(
          title,
          style: widget.text.labelSmall?.copyWith(
            color: widget.c.textTertiary,
            fontWeight: FontWeight.w700,
            fontSize: 11.sp,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(child: Container(height: 1, color: widget.c.borderSubtle)),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────
  // Key-value row — flat, no container
  // ────────────────────────────────────────────────────────────

  Widget _kvRow(
    String label,
    String value, {
    String? trailing,
    Color? trailingColor,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: widget.text.bodySmall?.copyWith(
            color: widget.c.textSecondary,
            fontSize: 13.sp,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: widget.text.bodyMedium?.copyWith(
            color: widget.c.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13.sp,
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: 6.w),
          Text(
            trailing,
            style: widget.text.bodySmall?.copyWith(
              color: trailingColor ?? widget.c.textTertiary,
              fontWeight: FontWeight.w500,
              fontSize: 12.sp,
            ),
          ),
        ],
      ],
    );
  }

  // ────────────────────────────────────────────────────────────
  // Mode pill — small inline pill matching PathStep style
  // ────────────────────────────────────────────────────────────

  Widget _modePill() {
    final label = _isLive ? 'Live' : 'Simulation';
    final bg = _isLive ? const Color(0xFFF5E6FF) : const Color(0xFFE5F0FF);
    final border = _isLive ? const Color(0xFFD4BFEB) : const Color(0xFFB4C8F0);
    final fg = _isLive ? const Color(0xFF4A1E7B) : const Color(0xFF1E3A5F);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100.r),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: widget.text.bodySmall?.copyWith(
          fontSize: 11.sp,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // Deposit amount editor — opens SageBottomSheet with slider
  // ────────────────────────────────────────────────────────────

  void _openDepositEditor() {
    HapticFeedback.selectionClick();

    SageBottomSheet.show<double>(
      context: context,
      title: 'Deposit Amount',
      builder: (c, text) => _AmountEditorContent(
        current: _depositAmount,
        min: _minimum,
        max: _recommended * 2,
        recommended: _recommended,
        confirmLabel: 'Set Amount',
        recommendedLabel: 'Recommended',
        c: c,
        text: text,
      ),
    ).then((value) {
      if (value != null) setState(() => _depositAmount = value);
    });
  }

  void _openSimulationBalanceEditor() {
    HapticFeedback.selectionClick();

    SageBottomSheet.show<double>(
      context: context,
      title: 'Simulation Capital',
      builder: (c, text) => _AmountEditorContent(
        current: _simulationBalanceAmount,
        min: _simulationMinimum,
        max: kMaxSimulationBalanceSOL,
        recommended: _simulationRecommended,
        confirmLabel: 'Set Capital',
        recommendedLabel: 'Recommended',
        c: c,
        text: text,
      ),
    ).then((value) {
      if (value == null) return;
      final nextValue = clampSimulationBalanceSOL(
        requested: value,
        positionSizeSOL: widget.positionSizeSOL,
      );
      setState(() => _simulationBalanceAmount = nextValue);
      widget.onSimulationBalanceChanged?.call(nextValue);
    });
  }

  // ────────────────────────────────────────────────────────────
  // Disclaimers — collapsible on acceptance
  // ────────────────────────────────────────────────────────────

  Widget _buildDisclaimerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Checkbox row ──
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _disclaimerAccepted = !_disclaimerAccepted);
          },
          behavior: HitTestBehavior.opaque,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20.r,
                height: 20.r,
                decoration: BoxDecoration(
                  color: _disclaimerAccepted
                      ? widget.c.accent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6.r),
                  border: Border.all(
                    color: _disclaimerAccepted
                        ? widget.c.accent
                        : widget.c.textTertiary,
                    width: 1.5,
                  ),
                ),
                child: _disclaimerAccepted
                    ? Icon(
                        PhosphorIconsBold.check,
                        size: 12.sp,
                        color: widget.c.buttonPrimaryText,
                      )
                    : null,
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'I understand the risks of automated trading. '
                  'This is not financial advice.',
                  style: widget.text.bodySmall?.copyWith(
                    color: _disclaimerAccepted
                        ? widget.c.textPrimary
                        : widget.c.textSecondary,
                    fontWeight: _disclaimerAccepted
                        ? FontWeight.w500
                        : FontWeight.w400,
                    fontSize: 12.sp,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Collapsible disclaimer bullets ──
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: EdgeInsets.only(top: 14.h, left: 30.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bullet(
                  'Sage does not guarantee returns. '
                  'Software is provided as-is.',
                ),
                SizedBox(height: 6.h),
                _bullet(
                  'Crypto trading carries significant risk, '
                  'including total loss of investment.',
                ),
                SizedBox(height: 6.h),
                _bullet(
                  'Past performance is not indicative '
                  'of future results.',
                ),
                SizedBox(height: 6.h),
                _bullet(
                  'You are solely responsible for your '
                  'trading decisions.',
                ),
                if (_isLive) ...[
                  SizedBox(height: 6.h),
                  _bullet(
                    'SOL is deposited into a bot wallet '
                    'managed by the server on your behalf.',
                  ),
                ],
              ],
            ),
          ),
          crossFadeState: _disclaimerAccepted
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 300),
        ),
      ],
    );
  }

  Widget _bullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 5.h),
          child: Container(
            width: 3.r,
            height: 3.r,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.c.textTertiary,
            ),
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            text,
            style: widget.text.bodySmall?.copyWith(
              color: widget.c.textTertiary,
              fontSize: 11.sp,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Deposit Editor — slider inside SageBottomSheet (matches param editor)
// ═══════════════════════════════════════════════════════════════

class _AmountEditorContent extends StatefulWidget {
  final double current;
  final double min;
  final double max;
  final double recommended;
  final String confirmLabel;
  final String recommendedLabel;
  final SageColors c;
  final TextTheme text;

  const _AmountEditorContent({
    required this.current,
    required this.min,
    required this.max,
    required this.recommended,
    required this.confirmLabel,
    required this.recommendedLabel,
    required this.c,
    required this.text,
  });

  @override
  State<_AmountEditorContent> createState() => _AmountEditorContentState();
}

class _AmountEditorContentState extends State<_AmountEditorContent> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final text = widget.text;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 8.h),

        // Big value display
        Text(
          '${_value.toStringAsFixed(1)} SOL',
          style: text.displayMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),

        SizedBox(height: 28.h),

        // Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: c.accent,
            inactiveTrackColor: c.border,
            thumbColor: c.accent,
            overlayColor: c.accent.withValues(alpha: 0.12),
            trackHeight: 3,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8.r),
          ),
          child: Slider(
            value: _value,
            min: widget.min,
            max: widget.max,
            divisions: ((widget.max - widget.min) * 10).round().clamp(1, 200),
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _value = v);
            },
          ),
        ),

        // Range labels + recommended tap
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${widget.min.toStringAsFixed(1)} SOL',
                style: text.labelSmall?.copyWith(
                  color: c.textTertiary,
                  fontSize: 10.sp,
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _value = widget.recommended);
                },
                child: Text(
                  '${widget.recommendedLabel} ${widget.recommended.toStringAsFixed(1)}',
                  style: text.labelSmall?.copyWith(
                    color: c.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 10.sp,
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 28.h),

        // Confirm button
        GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            Navigator.pop(context, _value);
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 16.h),
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(16.r),
              boxShadow: [
                BoxShadow(
                  color: c.accent.withValues(alpha: 0.25),
                  blurRadius: 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                widget.confirmLabel,
                style: text.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),

        SizedBox(height: 8.h),
      ],
    );
  }
}
