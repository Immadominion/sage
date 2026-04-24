/// Per-bot wallet info from GET /wallet/address/:botId.
class BotWalletInfo {
  final String botId;
  final String walletAddress;
  final String? ownerWallet;

  const BotWalletInfo({
    required this.botId,
    required this.walletAddress,
    this.ownerWallet,
  });

  factory BotWalletInfo.fromJson(Map<String, dynamic> json) => BotWalletInfo(
    botId: json['botId'] as String,
    walletAddress: json['walletAddress'] as String,
    ownerWallet: json['ownerWallet'] as String?,
  );
}

/// Balance response from GET /wallet/balance/:botId.
class WalletBalance {
  final double balanceSOL;
  final int balanceLamports;
  final String? botId;
  final String? walletAddress;

  const WalletBalance({
    required this.balanceSOL,
    required this.balanceLamports,
    this.botId,
    this.walletAddress,
  });

  factory WalletBalance.fromJson(Map<String, dynamic> json) => WalletBalance(
    balanceSOL: (json['balanceSOL'] as num?)?.toDouble() ?? 0,
    balanceLamports: json['balanceLamports'] as int? ?? 0,
    botId: json['botId'] as String?,
    walletAddress: json['walletAddress'] as String?,
  );
}

/// Withdrawal result from POST /wallet/withdraw/:botId.
class WithdrawalResult {
  final bool success;
  final String? signature;
  final String? error;

  const WithdrawalResult({required this.success, this.signature, this.error});

  factory WithdrawalResult.fromJson(Map<String, dynamic> json) =>
      WithdrawalResult(
        success: json['success'] as bool? ?? false,
        signature: json['signature'] as String?,
        error: json['error'] as String?,
      );
}

// ═══════════════════════════════════════════════════════════
// Aggregate wallet models (GET /wallet/balances)
// ═══════════════════════════════════════════════════════════

class TokenBalance {
  final String mint;
  final double amount;
  final int decimals;

  const TokenBalance({
    required this.mint,
    required this.amount,
    required this.decimals,
  });

  factory TokenBalance.fromJson(Map<String, dynamic> json) => TokenBalance(
    mint: json['mint'] as String,
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    decimals: json['decimals'] as int? ?? 0,
  );
}

class BotWalletBalances {
  final String botId;
  final String botName;
  final String walletAddress;
  final double balanceSOL;
  final List<TokenBalance> tokens;

  const BotWalletBalances({
    required this.botId,
    required this.botName,
    required this.walletAddress,
    required this.balanceSOL,
    required this.tokens,
  });

  factory BotWalletBalances.fromJson(Map<String, dynamic> json) =>
      BotWalletBalances(
        botId: json['botId'] as String,
        botName: json['botName'] as String,
        walletAddress: json['walletAddress'] as String,
        balanceSOL: (json['balanceSOL'] as num?)?.toDouble() ?? 0,
        tokens:
            (json['tokens'] as List<dynamic>?)
                ?.map((e) => TokenBalance.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class AggregateBalances {
  final List<BotWalletBalances> wallets;
  final double totalSOL;

  const AggregateBalances({required this.wallets, required this.totalSOL});

  factory AggregateBalances.fromJson(Map<String, dynamic> json) =>
      AggregateBalances(
        wallets:
            (json['wallets'] as List<dynamic>?)
                ?.map(
                  (e) => BotWalletBalances.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            [],
        totalSOL: (json['totalSOL'] as num?)?.toDouble() ?? 0,
      );
}

// ═══════════════════════════════════════════════════════════
// Smart withdraw result (POST /wallet/smart-withdraw)
// ═══════════════════════════════════════════════════════════

class SmartWithdrawBotResult {
  final String botId;
  final bool success;
  final String? signature;
  final double? amountSOL;
  final String? error;

  const SmartWithdrawBotResult({
    required this.botId,
    required this.success,
    this.signature,
    this.amountSOL,
    this.error,
  });

  factory SmartWithdrawBotResult.fromJson(Map<String, dynamic> json) =>
      SmartWithdrawBotResult(
        botId: json['botId'] as String,
        success: json['success'] as bool? ?? false,
        signature: json['signature'] as String?,
        amountSOL: (json['amountSOL'] as num?)?.toDouble(),
        error: json['error'] as String?,
      );
}

class SmartWithdrawResult {
  final bool success;
  final double totalWithdrawnSOL;
  final List<SmartWithdrawBotResult> results;

  const SmartWithdrawResult({
    required this.success,
    required this.totalWithdrawnSOL,
    required this.results,
  });

  factory SmartWithdrawResult.fromJson(Map<String, dynamic> json) =>
      SmartWithdrawResult(
        success: json['success'] as bool? ?? false,
        totalWithdrawnSOL: (json['totalWithdrawnSOL'] as num?)?.toDouble() ?? 0,
        results:
            (json['results'] as List<dynamic>?)
                ?.map(
                  (e) => SmartWithdrawBotResult.fromJson(
                    e as Map<String, dynamic>,
                  ),
                )
                .toList() ??
            [],
      );
}

// ═══════════════════════════════════════════════════════════
// Smart Wallet portfolio (GET /wallet/portfolio/:botId)
// Powered by Jupiter Token API for symbols + USD price.
// ═══════════════════════════════════════════════════════════

class PortfolioToken {
  final String mint;
  final String symbol;
  final String name;
  final String? icon;
  final int decimals;
  final double amount;       // ui amount
  final String rawAmount;    // smallest unit
  final double? usdPrice;
  final double usdValue;
  final bool isVerified;
  /// True when /wallet/sweep would attempt to swap this to SOL via Jupiter.
  final bool swappable;

  const PortfolioToken({
    required this.mint,
    required this.symbol,
    required this.name,
    required this.icon,
    required this.decimals,
    required this.amount,
    required this.rawAmount,
    required this.usdPrice,
    required this.usdValue,
    required this.isVerified,
    required this.swappable,
  });

  factory PortfolioToken.fromJson(Map<String, dynamic> json) => PortfolioToken(
    mint: json['mint'] as String,
    symbol: (json['symbol'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    icon: json['icon'] as String?,
    decimals: (json['decimals'] as num?)?.toInt() ?? 0,
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    rawAmount: (json['rawAmount'] as String?) ?? '0',
    usdPrice: (json['usdPrice'] as num?)?.toDouble(),
    usdValue: (json['usdValue'] as num?)?.toDouble() ?? 0,
    isVerified: json['isVerified'] as bool? ?? false,
    swappable: json['swappable'] as bool? ?? false,
  );
}

class PortfolioSol {
  final double amount;
  final int rawLamports;
  final double? usdPrice;
  final double usdValue;

  const PortfolioSol({
    required this.amount,
    required this.rawLamports,
    required this.usdPrice,
    required this.usdValue,
  });

  factory PortfolioSol.fromJson(Map<String, dynamic> json) => PortfolioSol(
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    rawLamports: (json['rawLamports'] as num?)?.toInt() ?? 0,
    usdPrice: (json['usdPrice'] as num?)?.toDouble(),
    usdValue: (json['usdValue'] as num?)?.toDouble() ?? 0,
  );
}

class WalletPortfolio {
  final String botId;
  final String walletAddress;
  final String? ownerWallet;
  final PortfolioSol sol;
  final List<PortfolioToken> tokens;
  final double totalUsdValue;
  final bool jupiterEnabled;

  const WalletPortfolio({
    required this.botId,
    required this.walletAddress,
    required this.ownerWallet,
    required this.sol,
    required this.tokens,
    required this.totalUsdValue,
    required this.jupiterEnabled,
  });

  /// True when the bot wallet has SPL tokens that the sweep flow can convert
  /// to SOL — i.e. there is value beyond the native balance that the user
  /// would otherwise leave stranded on chain.
  bool get hasSweepableTokens => tokens.any((t) => t.swappable);

  /// Total USD value of swappable SPL holdings (excluding native SOL).
  double get sweepableUsdValue =>
      tokens.where((t) => t.swappable).fold(0.0, (s, t) => s + t.usdValue);

  factory WalletPortfolio.fromJson(Map<String, dynamic> json) =>
      WalletPortfolio(
        botId: json['botId'] as String,
        walletAddress: json['walletAddress'] as String,
        ownerWallet: json['ownerWallet'] as String?,
        sol: PortfolioSol.fromJson(
          (json['sol'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        tokens: (json['tokens'] as List<dynamic>?)
                ?.map((e) =>
                    PortfolioToken.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        totalUsdValue: (json['totalUsdValue'] as num?)?.toDouble() ?? 0,
        jupiterEnabled: json['jupiterEnabled'] as bool? ?? false,
      );
}

// ═══════════════════════════════════════════════════════════
// Sweep result (POST /wallet/sweep/:botId)
// ═══════════════════════════════════════════════════════════

class SweepOutcome {
  final String mint;
  final String symbol;
  final double uiAmount;
  final bool success;
  final String? signature;
  final double? receivedSOL;
  final String? router;
  final String? error;

  const SweepOutcome({
    required this.mint,
    required this.symbol,
    required this.uiAmount,
    required this.success,
    this.signature,
    this.receivedSOL,
    this.router,
    this.error,
  });

  factory SweepOutcome.fromJson(Map<String, dynamic> json) => SweepOutcome(
    mint: json['mint'] as String,
    symbol: (json['symbol'] as String?) ?? '',
    uiAmount: (json['uiAmount'] as num?)?.toDouble() ?? 0,
    success: json['success'] as bool? ?? false,
    signature: json['signature'] as String?,
    receivedSOL: (json['receivedSOL'] as num?)?.toDouble(),
    router: json['router'] as String?,
    error: json['error'] as String?,
  );
}

class SweepWithdrawSummary {
  final String? signature;
  final double amountSOL;
  final String? to;
  const SweepWithdrawSummary({this.signature, required this.amountSOL, this.to});
  factory SweepWithdrawSummary.fromJson(Map<String, dynamic> json) =>
      SweepWithdrawSummary(
        signature: json['signature'] as String?,
        amountSOL: (json['amountSOL'] as num?)?.toDouble() ?? 0,
        to: json['to'] as String?,
      );
}

class SweepResult {
  final bool success;
  final String botId;
  final int swappedTokenCount;
  final double totalSwappedSOL;
  final SweepWithdrawSummary? withdraw;
  final List<SweepOutcome> outcomes;

  const SweepResult({
    required this.success,
    required this.botId,
    required this.swappedTokenCount,
    required this.totalSwappedSOL,
    required this.withdraw,
    required this.outcomes,
  });

  factory SweepResult.fromJson(Map<String, dynamic> json) => SweepResult(
    success: json['success'] as bool? ?? false,
    botId: json['botId'] as String,
    swappedTokenCount: (json['swappedTokenCount'] as num?)?.toInt() ?? 0,
    totalSwappedSOL: (json['totalSwappedSOL'] as num?)?.toDouble() ?? 0,
    withdraw: json['withdraw'] is Map<String, dynamic>
        ? SweepWithdrawSummary.fromJson(json['withdraw'] as Map<String, dynamic>)
        : null,
    outcomes: (json['outcomes'] as List<dynamic>?)
            ?.map((e) => SweepOutcome.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}
