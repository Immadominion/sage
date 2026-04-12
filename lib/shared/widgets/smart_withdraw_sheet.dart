import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:rive/rive.dart';

import 'package:sage/core/models/wallet.dart';
import 'package:sage/core/repositories/wallet_repository.dart';
import 'package:sage/core/theme/app_colors.dart';

/// Smart multi-wallet withdraw sheet.
///
/// Loads aggregate balances from all live bot wallets, lets the user
/// select which wallets to withdraw from, then batch-withdraws SOL
/// back to their connected Phantom wallet.
///
/// Designed for use inside [SageBottomSheet.show()].
class SmartWithdrawSheet extends ConsumerStatefulWidget {
  final SageColors c;
  final TextTheme text;

  const SmartWithdrawSheet({
    super.key,
    required this.c,
    required this.text,
  });

  @override
  ConsumerState<SmartWithdrawSheet> createState() =>
      _SmartWithdrawSheetState();
}

enum _SheetState { loading, select, withdrawing, success, error }

class _SmartWithdrawSheetState extends ConsumerState<SmartWithdrawSheet> {
  var _state = _SheetState.loading;
  AggregateBalances? _balances;
  final Set<String> _selectedBotIds = {};
  String? _errorMessage;
  SmartWithdrawResult? _result;

  @override
  void initState() {
    super.initState();
    _loadBalances();
  }

  Future<void> _loadBalances() async {
    setState(() => _state = _SheetState.loading);
    try {
      final repo = ref.read(walletRepositoryProvider);
      final balances = await repo.getAggregateBalances();
      if (!mounted) return;
      // Auto-select wallets with meaningful balance (> 0.003 SOL)
      final autoSelect = balances.wallets
          .where((w) => w.balanceSOL > 0.003)
          .map((w) => w.botId)
          .toSet();
      setState(() {
        _balances = balances;
        _selectedBotIds.addAll(autoSelect);
        _state = _SheetState.select;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _SheetState.error;
        _errorMessage = 'Failed to load wallet balances.';
      });
    }
  }

  double get _selectedTotal {
    if (_balances == null) return 0;
    return _balances!.wallets
        .where((w) => _selectedBotIds.contains(w.botId))
        .fold(0.0, (sum, w) => sum + w.balanceSOL);
  }

  bool get _hasSelection => _selectedBotIds.isNotEmpty && _selectedTotal > 0;

  void _toggleSelectAll() {
    if (_balances == null) return;
    final withdrawable =
        _balances!.wallets.where((w) => w.balanceSOL > 0.003).toList();
    if (_selectedBotIds.length == withdrawable.length) {
      setState(() => _selectedBotIds.clear());
    } else {
      setState(() {
        _selectedBotIds.clear();
        _selectedBotIds.addAll(withdrawable.map((w) => w.botId));
      });
    }
  }

  Future<void> _executeSmartWithdraw() async {
    if (!_hasSelection) return;
    setState(() => _state = _SheetState.withdrawing);
    HapticFeedback.mediumImpact();

    try {
      final repo = ref.read(walletRepositoryProvider);
      final result =
          await repo.smartWithdraw(_selectedBotIds.toList());

      if (!mounted) return;

      // Invalidate per-bot balance caches
      for (final botId in _selectedBotIds) {
        ref.invalidate(walletBalanceProvider(botId));
      }
      ref.invalidate(aggregateBalancesProvider);

      setState(() {
        _result = result;
        _state = _SheetState.success;
      });
      HapticFeedback.heavyImpact();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _SheetState.error;
        _errorMessage = _parseError(e);
      });
      HapticFeedback.heavyImpact();
    }
  }

  String _parseError(Object e) {
    final msg = e.toString();
    if (msg.contains('No funds available')) {
      return 'No funds available to withdraw.';
    }
    if (msg.contains('Insufficient balance')) {
      return 'Insufficient balance for withdrawal + transaction fees.';
    }
    final match = RegExp(r'message:\s*(.+)').firstMatch(msg);
    return match?.group(1) ?? 'Withdrawal failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final text = widget.text;

    return switch (_state) {
      _SheetState.loading => _buildLoading(c, text),
      _SheetState.select => _buildSelect(c, text),
      _SheetState.withdrawing => _buildWithdrawing(c, text),
      _SheetState.success => _buildSuccess(c, text),
      _SheetState.error => _buildError(c, text),
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // Loading
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
              'Loading wallets…',
              style: text.titleMedium?.copyWith(
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Select wallets (chumbucket-inspired grid)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSelect(SageColors c, TextTheme text) {
    final wallets = _balances!.wallets;

    if (wallets.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 32.h),
          Icon(PhosphorIconsBold.wallet, size: 48.sp, color: c.textTertiary),
          SizedBox(height: 16.h),
          Text(
            'No wallets found',
            style: text.titleMedium?.copyWith(color: c.textSecondary),
          ),
          SizedBox(height: 32.h),
        ],
      );
    }

    final withdrawable = wallets.where((w) => w.balanceSOL > 0.003).toList();
    final allSelected = _selectedBotIds.length == withdrawable.length &&
        withdrawable.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select wallets to withdraw from. All SOL will be sent to your connected wallet.',
          style: text.bodyMedium?.copyWith(color: c.textSecondary),
        ),

        SizedBox(height: 16.h),

        // Select All toggle
        GestureDetector(
          onTap: _toggleSelectAll,
          child: Row(
            children: [
              Icon(
                allSelected
                    ? PhosphorIconsFill.checkSquare
                    : PhosphorIconsBold.square,
                size: 20.sp,
                color: allSelected ? c.accent : c.textTertiary,
              ),
              SizedBox(width: 8.w),
              Text(
                'Select All',
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${_balances!.totalSOL.toStringAsFixed(4)} SOL total',
                style: text.bodySmall?.copyWith(
                  color: c.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 12.h),
        Divider(height: 1, color: c.borderSubtle),
        SizedBox(height: 8.h),

        // Wallet grid — 3 columns like chumbucket friends picker
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12.w,
            mainAxisSpacing: 12.h,
            childAspectRatio: 0.85,
          ),
          itemCount: wallets.length,
          itemBuilder: (context, index) =>
              _buildWalletItem(wallets[index], c, text),
        ),

        SizedBox(height: 16.h),

        // Selected total
        if (_hasSelection) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: c.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsBold.currencyDollar,
                    size: 18.sp, color: c.accent),
                SizedBox(width: 8.w),
                Text(
                  'Withdrawing',
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_selectedTotal.toStringAsFixed(4)} SOL',
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
        ],

        // Withdraw button
        GestureDetector(
          onTap: _hasSelection ? _executeSmartWithdraw : null,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 16.h),
            decoration: BoxDecoration(
              color: _hasSelection ? c.accent : c.buttonDisabled,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Center(
              child: Text(
                _hasSelection
                    ? 'Withdraw ${_selectedBotIds.length} Wallet${_selectedBotIds.length > 1 ? 's' : ''}'
                    : 'Select Wallets',
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

  Widget _buildWalletItem(
      BotWalletBalances wallet, SageColors c, TextTheme text) {
    final selected = _selectedBotIds.contains(wallet.botId);
    final hasBalance = wallet.balanceSOL > 0.003;

    return GestureDetector(
      onTap: hasBalance
          ? () {
              setState(() {
                if (selected) {
                  _selectedBotIds.remove(wallet.botId);
                } else {
                  _selectedBotIds.add(wallet.botId);
                }
              });
              HapticFeedback.selectionClick();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: selected
              ? c.accent.withValues(alpha: 0.1)
              : c.surface,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: selected
                ? c.accent
                : hasBalance
                    ? c.borderSubtle
                    : c.borderSubtle.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Wallet icon with check overlay
            Stack(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: (selected ? c.accent : c.textTertiary)
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      PhosphorIconsBold.wallet,
                      size: 20.sp,
                      color: selected
                          ? c.accent
                          : hasBalance
                              ? c.textSecondary
                              : c.textTertiary,
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16.w,
                      height: 16.w,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.surface, width: 2),
                      ),
                      child: Center(
                        child: Icon(PhosphorIconsBold.check,
                            size: 9.sp, color: c.buttonPrimaryText),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 6.h),
            // Bot name
            Text(
              wallet.botName,
              style: text.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: hasBalance ? c.textPrimary : c.textTertiary,
                fontSize: 11.sp,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 2.h),
            // Balance
            Text(
              hasBalance
                  ? '${wallet.balanceSOL.toStringAsFixed(3)} SOL'
                  : 'Empty',
              style: text.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: hasBalance ? c.accent : c.textTertiary,
                fontSize: 10.sp,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Withdrawing
  // ═══════════════════════════════════════════════════════════════

  Widget _buildWithdrawing(SageColors c, TextTheme text) {
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
              'Withdrawing from ${_selectedBotIds.length} wallet${_selectedBotIds.length > 1 ? 's' : ''}…',
              style: text.titleMedium?.copyWith(
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              '${_selectedTotal.toStringAsFixed(4)} SOL → your wallet',
              style: text.bodySmall?.copyWith(color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Success
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSuccess(SageColors c, TextTheme text) {
    final r = _result!;
    final succeeded = r.results.where((x) => x.success).toList();
    final failed = r.results.where((x) => !x.success).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 16.h),

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
          '${r.totalWithdrawnSOL.toStringAsFixed(4)} SOL sent to your wallet',
          style: text.bodyMedium?.copyWith(color: c.textSecondary),
        ),

        if (succeeded.isNotEmpty || failed.isNotEmpty) ...[
          SizedBox(height: 16.h),
          // Summary row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (succeeded.isNotEmpty)
                _statusChip(
                  '${succeeded.length} succeeded',
                  c.profit,
                  c,
                  text,
                ),
              if (succeeded.isNotEmpty && failed.isNotEmpty)
                SizedBox(width: 8.w),
              if (failed.isNotEmpty)
                _statusChip(
                  '${failed.length} failed',
                  c.loss,
                  c,
                  text,
                ),
            ],
          ),
        ],

        // Per-wallet results
        if (succeeded.length > 1) ...[
          SizedBox(height: 16.h),
          ...succeeded.map((x) => Padding(
                padding: EdgeInsets.symmetric(vertical: 2.h),
                child: Row(
                  children: [
                    Icon(PhosphorIconsBold.checkCircle,
                        size: 14.sp, color: c.profit),
                    SizedBox(width: 6.w),
                    Expanded(
                      child: Text(
                        x.botId,
                        style: text.bodySmall?.copyWith(
                          color: c.textTertiary,
                          fontFamily: 'monospace',
                          fontSize: 11.sp,
                        ),
                      ),
                    ),
                    Text(
                      '${(x.amountSOL ?? 0).toStringAsFixed(4)} SOL',
                      style: text.bodySmall?.copyWith(
                        color: c.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              )),
        ],

        SizedBox(height: 28.h),

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

  Widget _statusChip(
      String label, Color color, SageColors c, TextTheme text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        label,
        style: text.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11.sp,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Error
  // ═══════════════════════════════════════════════════════════════

  Widget _buildError(SageColors c, TextTheme text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 16.h),

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

        GestureDetector(
          onTap: _loadBalances,
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
