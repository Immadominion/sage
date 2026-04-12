import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:rive/rive.dart';

import 'package:sage/core/repositories/wallet_repository.dart';
import 'package:sage/core/services/auth_service.dart';
import 'package:sage/core/services/domain_resolver.dart';
import 'package:sage/core/theme/app_colors.dart';

/// Withdraw SOL from Sage bot wallets back to user's wallet.
///
/// The backend decrypts the bot's server-side keypair and signs
/// the transfer — no MWA signature required from the user.
///
/// Designed for use inside [SageBottomSheet.show()].
/// Handles its own loading/success/error state.
///
/// ```dart
/// SageBottomSheet.show<bool>(
///   context: context,
///   title: 'Withdraw',
///   builder: (c, text) => WithdrawSheet(
///     botId: bot.botId,
///     availableBalanceSol: balance,
///     c: c,
///     text: text,
///   ),
/// );
/// ```
class WithdrawSheet extends ConsumerStatefulWidget {
  final String botId;
  final double availableBalanceSol;
  final SageColors c;
  final TextTheme text;

  const WithdrawSheet({
    super.key,
    required this.botId,
    required this.availableBalanceSol,
    required this.c,
    required this.text,
  });

  @override
  ConsumerState<WithdrawSheet> createState() => _WithdrawSheetState();
}

enum _SheetState { input, loading, success, error }

class _WithdrawSheetState extends ConsumerState<WithdrawSheet> {
  var _state = _SheetState.input;
  String? _errorMessage;
  String? _signature;
  double? _withdrawnSol;

  // Destination wallet — defaults to connected wallet, can be customized.
  late final TextEditingController _destController;
  bool _useCustomDest = false;
  String? _resolvedAddress; // set when domain resolves to an address
  bool _isResolving = false;
  String? _resolveError;

  String get _connectedWallet => ref.read(connectedWalletAddressProvider) ?? '';

  /// The actual destination: resolved domain address > custom input > connected wallet.
  String get _effectiveDestination {
    if (!_useCustomDest) return _connectedWallet;
    if (_resolvedAddress != null) return _resolvedAddress!;
    return _destController.text.trim();
  }

  @override
  void initState() {
    super.initState();
    _destController = TextEditingController();
  }

  @override
  void dispose() {
    _destController.dispose();
    super.dispose();
  }

  /// Resolve domain input (debounce happens naturally — user taps withdraw).
  Future<void> _resolveDestination() async {
    final input = _destController.text.trim();
    if (input.isEmpty) return;

    // Already a valid base58 address — nothing to resolve
    if (DomainResolver.isValidAddress(input)) {
      setState(() {
        _resolvedAddress = input;
        _resolveError = null;
      });
      return;
    }

    // Looks like a domain — resolve it
    if (DomainResolver.isDomain(input)) {
      setState(() {
        _isResolving = true;
        _resolveError = null;
      });

      final resolver = ref.read(domainResolverProvider);
      final address = await resolver.resolveAddress(input);

      if (!mounted) return;
      setState(() {
        _isResolving = false;
        if (address != null) {
          _resolvedAddress = address;
          _resolveError = null;
        } else {
          _resolvedAddress = null;
          _resolveError = 'Domain not found';
        }
      });
      return;
    }

    // Neither valid address nor domain
    setState(() {
      _resolvedAddress = null;
      _resolveError = 'Invalid address or domain';
    });
  }

  /// Withdraw SOL from bot wallet to the destination wallet.
  /// Backend decrypts the bot keypair and signs the transfer server-side.
  Future<void> _executeWithdraw() async {
    // If custom destination, resolve domain first
    if (_useCustomDest && _destController.text.trim().isNotEmpty) {
      await _resolveDestination();
      if (_resolveError != null || (_resolvedAddress == null && _useCustomDest)) {
        setState(() {
          _state = _SheetState.error;
          _errorMessage = _resolveError ?? 'Could not resolve destination address.';
        });
        return;
      }
    }

    final dest = _useCustomDest ? _effectiveDestination : _connectedWallet;
    if (dest.isEmpty) {
      setState(() {
        _state = _SheetState.error;
        _errorMessage = 'Wallet not connected. Please reconnect your wallet.';
      });
      return;
    }

    setState(() => _state = _SheetState.loading);
    HapticFeedback.mediumImpact();

    try {
      final walletRepo = ref.read(walletRepositoryProvider);

      // Backend clamps to max withdrawable (balance - fee reserve).
      // Pass custom destination if different from owner wallet.
      final result = await walletRepo.withdraw(
        widget.botId,
        widget.availableBalanceSol,
        destination: _useCustomDest ? dest : null,
      );

      if (!result.success) {
        throw Exception(result.error ?? 'Withdrawal failed');
      }

      _signature = result.signature;
      _withdrawnSol = widget.availableBalanceSol;

      // Refresh the bot's wallet balance.
      ref.invalidate(walletBalanceProvider(widget.botId));

      if (mounted) {
        setState(() => _state = _SheetState.success);
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _SheetState.error;
          _errorMessage = _parseError(e);
        });
        HapticFeedback.heavyImpact();
      }
    }
  }

  String _parseError(Object e) {
    final msg = e.toString();
    if (msg.contains('No funds available') ||
        msg.contains('No session signer funds')) {
      return 'No funds available to withdraw.';
    }
    if (msg.contains('Insufficient balance') ||
        msg.contains('InsufficientFunds')) {
      return 'Insufficient balance for withdrawal + transaction fees.';
    }
    if (msg.contains('Bot not found') || msg.contains('404')) {
      return 'Bot wallet not found. It may have been deleted.';
    }
    if (msg.contains('Only live-mode') || msg.contains('not initialized')) {
      return 'This bot does not have a wallet yet.';
    }
    if (msg.contains('Wallet not found')) {
      return 'No on-chain wallet found. It may already be closed.';
    }
    if (msg.contains('signing was cancelled')) {
      return 'You cancelled the transaction. No funds were moved.';
    }
    // Generic
    final match = RegExp(r'message:\s*(.+)').firstMatch(msg);
    return match?.group(1) ?? 'Withdrawal failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final text = widget.text;

    return switch (_state) {
      _SheetState.input => _buildInput(c, text),
      _SheetState.loading => _buildLoading(c, text),
      _SheetState.success => _buildSuccess(c, text),
      _SheetState.error => _buildError(c, text),
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // Input state — withdrawal confirmation
  // ═══════════════════════════════════════════════════════════════

  Widget _buildInput(SageColors c, TextTheme text) {
    final hasEnough = widget.availableBalanceSol > 0;
    final shortWallet = _connectedWallet.length > 8
        ? '${_connectedWallet.substring(0, 6)}\u2026${_connectedWallet.substring(_connectedWallet.length - 4)}'
        : _connectedWallet;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Withdraw SOL from your bot wallet.',
          style: text.bodyMedium?.copyWith(color: c.textSecondary),
        ),

        SizedBox(height: 16.h),

        // Balance info
        _InfoRow(
          label: 'Available',
          value: '${widget.availableBalanceSol.toStringAsFixed(4)} SOL',
          c: c,
          text: text,
        ),

        Divider(height: 1, color: c.borderSubtle),

        // Destination row — default or custom toggle
        Padding(
          padding: EdgeInsets.symmetric(vertical: 10.h),
          child: Row(
            children: [
              Text(
                'Destination',
                style: text.titleMedium?.copyWith(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
              const Spacer(),
              if (!_useCustomDest)
                Text(
                  shortWallet.isNotEmpty ? shortWallet : 'Not connected',
                  style: text.titleMedium?.copyWith(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              SizedBox(width: 8.w),
              GestureDetector(
                onTap: () => setState(() {
                  _useCustomDest = !_useCustomDest;
                  if (!_useCustomDest) {
                    _destController.clear();
                    _resolvedAddress = null;
                    _resolveError = null;
                  }
                }),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: _useCustomDest ? c.accent.withValues(alpha: 0.15) : c.surfaceElevated,
                    borderRadius: BorderRadius.circular(6.r),
                    border: Border.all(
                      color: _useCustomDest ? c.accent : c.borderSubtle,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _useCustomDest ? 'Custom' : 'Edit',
                    style: text.bodySmall?.copyWith(
                      color: _useCustomDest ? c.accent : c.textTertiary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11.sp,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Custom destination input
        if (_useCustomDest) ...[
          Container(
            decoration: BoxDecoration(
              color: c.surfaceElevated,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(
                color: _resolveError != null ? c.loss : c.borderSubtle,
              ),
            ),
            child: TextField(
              controller: _destController,
              style: text.bodyMedium?.copyWith(
                color: c.textPrimary,
                fontFamily: 'monospace',
                fontSize: 13.sp,
              ),
              decoration: InputDecoration(
                hintText: 'Address or domain (e.g. miester.abc)',
                hintStyle: text.bodyMedium?.copyWith(
                  color: c.textTertiary,
                  fontSize: 13.sp,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12.w,
                  vertical: 12.h,
                ),
                border: InputBorder.none,
                suffixIcon: _isResolving
                    ? Padding(
                        padding: EdgeInsets.all(12.w),
                        child: SizedBox(
                          width: 16.w,
                          height: 16.w,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                          ),
                        ),
                      )
                    : _resolvedAddress != null
                        ? Icon(PhosphorIconsBold.checkCircle,
                            color: c.profit, size: 18.sp)
                        : null,
              ),
              onChanged: (_) {
                // Clear old resolved state on new input
                if (_resolvedAddress != null || _resolveError != null) {
                  setState(() {
                    _resolvedAddress = null;
                    _resolveError = null;
                  });
                }
              },
            ),
          ),
          if (_resolveError != null)
            Padding(
              padding: EdgeInsets.only(top: 4.h, left: 4.w),
              child: Text(
                _resolveError!,
                style: text.bodySmall?.copyWith(color: c.loss, fontSize: 11.sp),
              ),
            ),
          if (_resolvedAddress != null &&
              _resolvedAddress != _destController.text.trim())
            Padding(
              padding: EdgeInsets.only(top: 4.h, left: 4.w),
              child: Text(
                'Resolves to ${_resolvedAddress!.substring(0, 6)}\u2026${_resolvedAddress!.substring(_resolvedAddress!.length - 4)}',
                style: text.bodySmall?.copyWith(
                  color: c.profit,
                  fontSize: 11.sp,
                ),
              ),
            ),
          SizedBox(height: 4.h),
          Padding(
            padding: EdgeInsets.only(left: 4.w),
            child: Text(
              'Supports .abc, .bonk, .skr, .poor and other AllDomains TLDs',
              style: text.bodySmall?.copyWith(
                color: c.textTertiary,
                fontSize: 10.sp,
              ),
            ),
          ),
          SizedBox(height: 8.h),
        ],

        Divider(height: 1, color: c.borderSubtle),

        // Big amount display
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24.h),
          child: Center(
            child: Text(
              '${widget.availableBalanceSol.toStringAsFixed(4)} SOL',
              style: text.displayMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),

        if (!hasEnough)
          Padding(
            padding: EdgeInsets.only(bottom: 16.h),
            child: Text(
              'No balance to withdraw.',
              style: text.bodySmall?.copyWith(color: c.loss),
            ),
          ),

        // Withdraw button
        GestureDetector(
          onTap: hasEnough ? _executeWithdraw : null,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 16.h),
            decoration: BoxDecoration(
              color: hasEnough ? c.accent : c.buttonDisabled,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Center(
              child: Text(
                'Withdraw All SOL',
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
              'Withdrawing…',
              style: text.titleMedium?.copyWith(
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Sending SOL to ${_useCustomDest ? "custom wallet" : "your wallet"}',
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

        // Success animation
        SizedBox(
          width: 80.w,
          height: 80.w,
          child: const _RiveAsset(asset: 'assets/animation/rive/success.riv'),
        ),

        SizedBox(height: 20.h),

        Text(
          'Withdrawal Complete',
          style: text.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),

        SizedBox(height: 8.h),

        Text(
          '${(_withdrawnSol ?? widget.availableBalanceSol).toStringAsFixed(4)} SOL withdrawn',
          style: text.bodyMedium?.copyWith(color: c.textSecondary),
        ),

        if (_signature != null) ...[
          SizedBox(height: 12.h),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _signature!));
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Signature copied')));
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIconsBold.copy,
                  size: 12.sp,
                  color: c.textTertiary,
                ),
                SizedBox(width: 4.w),
                Text(
                  'TX: ${_signature!.substring(0, 8)}…${_signature!.substring(_signature!.length - 4)}',
                  style: text.bodySmall?.copyWith(
                    color: c.textTertiary,
                    fontFamily: 'monospace',
                    fontSize: 11.sp,
                  ),
                ),
              ],
            ),
          ),
        ],

        SizedBox(height: 28.h),

        // Done button
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

        SizedBox(height: 16.h),
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

        // Failure animation
        SizedBox(
          width: 80.w,
          height: 80.w,
          child: const _RiveAsset(asset: 'assets/animation/rive/failure.riv'),
        ),

        SizedBox(height: 20.h),

        Text(
          'Withdrawal Failed',
          style: text.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),

        SizedBox(height: 8.h),

        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Text(
            _errorMessage ?? 'An unknown error occurred.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
        ),

        SizedBox(height: 28.h),

        // Retry button
        GestureDetector(
          onTap: () => setState(() => _state = _SheetState.input),
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
// Shared info row (label: value)
// ═══════════════════════════════════════════════════════════════

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final SageColors c;
  final TextTheme text;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.c,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        children: [
          Text(
            label,
            style: text.titleMedium?.copyWith(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
          const Spacer(),
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

// ═══════════════════════════════════════════════════════════════
// One-shot Rive animation from asset
// ═══════════════════════════════════════════════════════════════

class _RiveAsset extends StatefulWidget {
  final String asset;
  const _RiveAsset({required this.asset});

  @override
  State<_RiveAsset> createState() => _RiveAssetState();
}

class _RiveAssetState extends State<_RiveAsset> {
  late final FileLoader _loader;

  @override
  void initState() {
    super.initState();
    _loader = FileLoader.fromAsset(widget.asset, riveFactory: Factory.rive);
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RiveWidgetBuilder(
      fileLoader: _loader,
      builder: (context, state) => switch (state) {
        RiveLoading() => const SizedBox.expand(),
        RiveFailed() => const SizedBox.expand(),
        RiveLoaded() => RiveWidget(
          controller: state.controller,
          fit: Fit.contain,
        ),
      },
    );
  }
}
