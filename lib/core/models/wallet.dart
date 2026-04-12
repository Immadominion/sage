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
        tokens: (json['tokens'] as List<dynamic>?)
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
        wallets: (json['wallets'] as List<dynamic>?)
                ?.map((e) =>
                    BotWalletBalances.fromJson(e as Map<String, dynamic>))
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
        totalWithdrawnSOL:
            (json['totalWithdrawnSOL'] as num?)?.toDouble() ?? 0,
        results: (json['results'] as List<dynamic>?)
                ?.map((e) =>
                    SmartWithdrawBotResult.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
