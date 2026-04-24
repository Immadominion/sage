import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/wallet.dart';
import '../services/api_client.dart';

/// Repository for per-bot wallet operations.
///
/// Each live-mode bot has its own server-side Solana keypair.
/// These methods map to the backend wallet routes:
///   GET  /wallet/balance/:botId
///   GET  /wallet/address/:botId
///   POST /wallet/withdraw/:botId
class WalletRepository {
  final ApiClient _api;

  WalletRepository(this._api);

  /// Get the SOL balance of a bot's wallet.
  Future<WalletBalance> getBalance(String botId) async {
    final response = await _api.get('/wallet/balance/$botId');
    return WalletBalance.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get the deposit address (public key) for a bot's wallet.
  Future<BotWalletInfo> getAddress(String botId) async {
    final response = await _api.get('/wallet/address/$botId');
    return BotWalletInfo.fromJson(response.data as Map<String, dynamic>);
  }

  /// Withdraw SOL from a bot's wallet to the owner's connected wallet
  /// or an optional custom destination address.
  /// The backend decrypts the keypair and signs server-side.
  Future<WithdrawalResult> withdraw(
    String botId,
    double amountSOL, {
    String? destination,
  }) async {
    final response = await _api.post(
      '/wallet/withdraw/$botId',
      data: {'amountSOL': amountSOL, 'destination': ?destination},
    );
    return WithdrawalResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// Prepare a deposit transaction (user → bot wallet).
  /// Returns a serialized TX that the user signs via MWA.
  Future<Map<String, dynamic>> prepareDeposit({
    required String botId,
    required double amountSOL,
    required String feePayer,
  }) async {
    final response = await _api.post(
      '/wallet/prepare-deposit/$botId',
      data: {'amountSOL': amountSOL, 'feePayer': feePayer},
    );
    return response.data as Map<String, dynamic>;
  }

  /// Get aggregate balances across all live bot wallets.
  Future<AggregateBalances> getAggregateBalances() async {
    final response = await _api.get('/wallet/balances');
    return AggregateBalances.fromJson(response.data as Map<String, dynamic>);
  }

  /// Batch withdraw SOL from multiple bot wallets.
  Future<SmartWithdrawResult> smartWithdraw(List<String> botIds) async {
    final response = await _api.post(
      '/wallet/smart-withdraw',
      data: {'botIds': botIds},
    );
    return SmartWithdrawResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// Smart Wallet portfolio — SOL + every SPL token with USD values
  /// (Jupiter Token API).
  Future<WalletPortfolio> getPortfolio(String botId) async {
    final response = await _api.get('/wallet/portfolio/$botId');
    return WalletPortfolio.fromJson(response.data as Map<String, dynamic>);
  }

  /// Sweep all swappable SPL tokens to SOL via Jupiter, then optionally
  /// drain the resulting SOL to the owner wallet.
  Future<SweepResult> sweepWallet(
    String botId, {
    bool withdrawAfter = true,
    int? slippageBps,
    List<String>? mints,
  }) async {
    final response = await _api.post(
      '/wallet/sweep/$botId',
      data: {
        'withdrawAfter': withdrawAfter,
        'slippageBps': ?slippageBps,
        'mints': ?mints,
      },
    );
    return SweepResult.fromJson(response.data as Map<String, dynamic>);
  }
}

/// WalletRepository Riverpod provider.
final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return WalletRepository(ref.read(apiClientProvider));
});

/// Per-bot wallet balance provider.
final walletBalanceProvider = FutureProvider.family<WalletBalance, String>((
  ref,
  botId,
) async {
  final repo = ref.read(walletRepositoryProvider);
  return repo.getBalance(botId);
});

/// Aggregate balances across all live bot wallets.
final aggregateBalancesProvider = FutureProvider<AggregateBalances>((ref) {
  final repo = ref.read(walletRepositoryProvider);
  return repo.getAggregateBalances();
});

/// Smart Wallet portfolio per bot — SOL + tokens + USD via Jupiter.
final walletPortfolioProvider =
    FutureProvider.family<WalletPortfolio, String>((ref, botId) async {
  final repo = ref.read(walletRepositoryProvider);
  return repo.getPortfolio(botId);
});
