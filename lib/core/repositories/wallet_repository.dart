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

  /// Withdraw SOL from a bot's wallet to the owner's connected wallet.
  /// The backend decrypts the keypair and signs server-side.
  Future<WithdrawalResult> withdraw(String botId, double amountSOL) async {
    final response = await _api.post(
      '/wallet/withdraw/$botId',
      data: {'amountSOL': amountSOL},
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
