import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:sage/core/config/env_config.dart';
import 'package:sage/core/repositories/wallet_repository.dart';
import 'package:sage/core/services/auth_service.dart';
import 'package:sage/core/services/mwa_wallet_service.dart';
import 'package:sage/core/theme/app_colors.dart';
import 'package:sage/shared/widgets/sage_bottom_sheet.dart';

/// Deposit SOL into a bot's wallet from the user's connected wallet.
///
/// The backend builds a system transfer TX (user → bot wallet address),
/// which the user signs via MWA. No server-side key access needed.
///
/// ```dart
/// SageBottomSheet.show<bool>(
///   context: context,
///   title: 'Fund Wallet',
///   builder: (c, text) => DepositSheet(
///     botId: bot.botId,
///     recommendedSol: 5.0,
///     minSol: 1.0,
///     c: c,
///     text: text,
///   ),
/// );
/// ```
class DepositSheet extends ConsumerStatefulWidget {
  /// The bot whose wallet will receive the deposit.
  final String botId;

  /// Recommended deposit amount (e.g. positionSize * maxPositions).
  final double recommendedSol;

  /// Minimum allowed deposit.
  final double minSol;

  /// Maximum allowed deposit (defaults to recommended * 3).
  final double? maxSol;

  final SageColors c;
  final TextTheme text;

  const DepositSheet({
    super.key,
    required this.botId,
    this.recommendedSol = 1.0,
    this.minSol = 0.1,
    this.maxSol,
    required this.c,
    required this.text,
  });

  @override
  ConsumerState<DepositSheet> createState() => _DepositSheetState();
}

enum _DepositState { input, loading, success, error }

class _DepositSheetState extends ConsumerState<DepositSheet> {
  var _state = _DepositState.input;
  String? _errorMessage;
  late double _amount;
  double? _depositedSol;

  @override
  void initState() {
    super.initState();
    _amount = widget.recommendedSol;
  }

  double get _max => widget.maxSol ?? widget.recommendedSol * 3;

  Future<void> _executeDeposit() async {
    setState(() => _state = _DepositState.loading);
    HapticFeedback.mediumImpact();

    try {
      final walletRepo = ref.read(walletRepositoryProvider);
      final mwa = ref.read(mwaWalletServiceProvider);
      final feePayer = ref.read(connectedWalletAddressProvider);

      if (feePayer == null || feePayer.isEmpty) {
        throw Exception('Wallet not connected. Please reconnect your wallet.');
      }

      // Step 1: Backend builds a system transfer TX (user → bot wallet).
      final txData = await walletRepo.prepareDeposit(
        botId: widget.botId,
        amountSOL: _amount,
        feePayer: feePayer,
      );
      final network = txData['network'] as String? ?? EnvConfig.solanaNetwork;
      final txBytes = Uint8List.fromList(
        base64Decode(txData['transaction'] as String),
      );

      // Step 2: Sign and send via MWA.
      final signatures = await mwa.signAndSendTransactions([
        txBytes,
      ], cluster: network);
      if (signatures.isEmpty) {
        throw Exception('Transaction was rejected by wallet');
      }

      _depositedSol = _amount;
      ref.invalidate(walletBalanceProvider(widget.botId));

      if (mounted) {
        setState(() => _state = _DepositState.success);
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _DepositState.error;
          _errorMessage = _parseError(e);
        });
        HapticFeedback.heavyImpact();
      }
    }
  }

  String _parseError(Object e) {
    final msg = e.toString();
    if (msg.contains('cancelled') || msg.contains('cancel')) {
      return 'You cancelled the transaction. No funds were moved.';
    }
    if (msg.contains('insufficient') || msg.contains('Insufficient')) {
      return 'Insufficient balance in your connected wallet.';
    }
    if (msg.contains('Wallet not found') || msg.contains('Bot not found')) {
      return 'Bot wallet not found. The bot may have been deleted.';
    }
    if (msg.contains('Only live-mode') || msg.contains('not initialized')) {
      return 'This bot does not have a wallet yet.';
    }
    if (msg.contains('rejected')) {
      return 'Transaction was rejected by your wallet.';
    }
    if (msg.contains('simulation') || msg.contains('Simulation')) {
      return 'Transaction simulation failed. Check your wallet balance.';
    }
    final match = RegExp(r'message:\s*(.+)').firstMatch(msg);
    return match?.group(1) ?? 'Deposit failed. Please try again.';
  }

  void _openAmountEditor() {
    SageBottomSheet.show<double>(
      context: context,
      title: 'Deposit Amount',
      builder: (c, text) => _AmountEditorContent(
        current: _amount,
        min: widget.minSol,
        max: _max,
        c: c,
        text: text,
      ),
    ).then((value) {
      if (value != null && mounted) setState(() => _amount = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final text = widget.text;

    return switch (_state) {
      _DepositState.input => _buildInput(c, text),
      _DepositState.loading => _buildLoading(c, text),
      _DepositState.success => _buildSuccess(c, text),
      _DepositState.error => _buildError(c, text),
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // Input state — amount selection
  // ═══════════════════════════════════════════════════════════════

  Widget _buildInput(SageColors c, TextTheme text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add SOL to your bot wallet for live trading.',
          style: text.bodyMedium?.copyWith(color: c.textSecondary),
        ),

        SizedBox(height: 24.h),

        // Tappable amount row
        GestureDetector(
          onTap: _openAmountEditor,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            child: Row(
              children: [
                Text(
                  'Deposit Amount',
                  style: text.titleMedium?.copyWith(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_amount.toStringAsFixed(1)} SOL',
                  style: text.titleMedium?.copyWith(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: c.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                SizedBox(width: 6.w),
                Icon(
                  PhosphorIconsBold.pencilSimple,
                  size: 12.sp,
                  color: c.textTertiary.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),

        Divider(height: 1, color: c.borderSubtle),

        // Recommendation hint
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          child: Text(
            'Recommended: ${widget.recommendedSol.toStringAsFixed(1)} SOL',
            style: text.bodySmall?.copyWith(
              color: c.textTertiary,
              fontSize: 11.sp,
            ),
          ),
        ),

        SizedBox(height: 20.h),

        // Fund button
        GestureDetector(
          onTap: _executeDeposit,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 16.h),
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Center(
              child: Text(
                'Fund ${_amount.toStringAsFixed(1)} SOL',
                style: text.titleMedium?.copyWith(
                  color: c.buttonPrimaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),

        SizedBox(height: 8.h),

        // Cancel
        GestureDetector(
          onTap: () => Navigator.pop(context, false),
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

        SizedBox(height: 8.h),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Loading state
  // ═══════════════════════════════════════════════════════════════

  Widget _buildLoading(SageColors c, TextTheme text) {
    return SizedBox(
      height: 200.h,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32.w,
              height: 32.w,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(c.accent),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Depositing…',
              style: text.titleMedium?.copyWith(
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Sending ${_amount.toStringAsFixed(1)} SOL to your bot wallet',
              style: text.bodySmall?.copyWith(color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Success state
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSuccess(SageColors c, TextTheme text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 16.h),

        // Checkmark
        Container(
          width: 64.w,
          height: 64.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.profit.withValues(alpha: 0.12),
          ),
          child: Icon(
            PhosphorIconsBold.checkCircle,
            size: 36.sp,
            color: c.profit,
          ),
        ),

        SizedBox(height: 20.h),

        Text(
          'Deposit Complete',
          style: text.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),

        SizedBox(height: 8.h),

        Text(
          '${(_depositedSol ?? _amount).toStringAsFixed(1)} SOL added to your bot wallet',
          style: text.bodyMedium?.copyWith(color: c.textSecondary),
        ),

        SizedBox(height: 28.h),

        // Done
        GestureDetector(
          onTap: () => Navigator.pop(context, true),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 16.h),
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Center(
              child: Text(
                'Done',
                style: text.titleMedium?.copyWith(
                  color: c.buttonPrimaryText,
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

  // ═══════════════════════════════════════════════════════════════
  // Error state
  // ═══════════════════════════════════════════════════════════════

  Widget _buildError(SageColors c, TextTheme text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 16.h),

        Container(
          width: 64.w,
          height: 64.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.loss.withValues(alpha: 0.12),
          ),
          child: Icon(
            PhosphorIconsBold.warningCircle,
            size: 36.sp,
            color: c.loss,
          ),
        ),

        SizedBox(height: 20.h),

        Text(
          'Deposit Failed',
          style: text.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),

        SizedBox(height: 8.h),

        Text(
          _errorMessage ?? 'Something went wrong.',
          style: text.bodyMedium?.copyWith(color: c.textSecondary),
          textAlign: TextAlign.center,
        ),

        SizedBox(height: 28.h),

        // Retry
        GestureDetector(
          onTap: () => setState(() => _state = _DepositState.input),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 16.h),
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Center(
              child: Text(
                'Try Again',
                style: text.titleMedium?.copyWith(
                  color: c.buttonPrimaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),

        SizedBox(height: 8.h),

        // Cancel
        GestureDetector(
          onTap: () => Navigator.pop(context, false),
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

        SizedBox(height: 8.h),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Amount Editor — slider inside SageBottomSheet
// ═══════════════════════════════════════════════════════════════

class _AmountEditorContent extends StatefulWidget {
  final double current;
  final double min;
  final double max;
  final SageColors c;
  final TextTheme text;

  const _AmountEditorContent({
    required this.current,
    required this.min,
    required this.max,
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

        // Range labels
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
              Text(
                '${widget.max.toStringAsFixed(1)} SOL',
                style: text.labelSmall?.copyWith(
                  color: c.textTertiary,
                  fontSize: 10.sp,
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
                'Set Amount',
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
