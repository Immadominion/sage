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
