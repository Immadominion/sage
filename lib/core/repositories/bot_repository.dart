import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bot.dart';
import '../services/api_client.dart';

/// Repository for bot CRUD + lifecycle operations.
class BotRepository {
  final ApiClient _api;

  BotRepository(this._api);

  /// Create a new bot with the given config.
  Future<Bot> createBot(BotConfig config) async {
    final response = await _api.post('/bot/create', data: config.toJson());
    return Bot.fromJson(response.data as Map<String, dynamic>);
  }

  /// List all bots for the authenticated user.
  Future<List<Bot>> listBots() async {
    final response = await _api.get('/bot/list');
    final data = response.data as Map<String, dynamic>;
    final bots = data['bots'] as List<dynamic>;
    return bots
        .map((e) => Bot.fromJson({'bot': e as Map<String, dynamic>}))
        .toList();
  }

  /// Get bot detail with live engine stats.
  Future<Bot> getBot(String botId) async {
    final response = await _api.get('/bot/$botId');
    return Bot.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update bot config (only when stopped).
  Future<Bot> updateConfig(String botId, Map<String, dynamic> config) async {
    final response = await _api.put('/bot/$botId/config', data: config);
    return Bot.fromJson(response.data as Map<String, dynamic>);
  }

  /// Start the bot engine.
  Future<void> startBot(String botId) async {
    await _api.post('/bot/$botId/start');
  }

  /// Stop the bot gracefully.
  Future<void> stopBot(String botId) async {
    await _api.post('/bot/$botId/stop');
  }

  /// Emergency close all positions and stop.
  Future<void> emergencyStop(String botId) async {
    await _api.post('/bot/$botId/emergency');
  }

  /// Delete a stopped bot.
  Future<void> deleteBot(String botId) async {
    await _api.delete('/bot/$botId');
  }

  /// Rename a bot (allowed regardless of status).
  Future<Bot> renameBot(String botId, String name) async {
    final response = await _api.put('/bot/$botId/rename', data: {'name': name});
    return Bot.fromJson(response.data as Map<String, dynamic>);
  }

  /// Convert a simulation bot to live mode.
  /// Returns the updated bot with wallet address.
  Future<Bot> convertToLive(String botId) async {
    final response = await _api.post('/bot/$botId/convert-to-live');
    return Bot.fromJson(response.data as Map<String, dynamic>);
  }
}

/// BotRepository Riverpod provider.
final botRepositoryProvider = Provider<BotRepository>((ref) {
  return BotRepository(ref.read(apiClientProvider));
});

/// Provider for the list of bots (auto-refresh).
final botListProvider = AsyncNotifierProvider<BotListNotifier, List<Bot>>(() {
  return BotListNotifier();
});

class BotListNotifier extends AsyncNotifier<List<Bot>> {
  Future<void>? _refreshInFlight;

  @override
  Future<List<Bot>> build() async {
    final repo = ref.read(botRepositoryProvider);
    return repo.listBots();
  }

  Future<void> refresh({bool showLoading = false}) async {
    if (_refreshInFlight != null) {
      await _refreshInFlight;
      return;
    }

    if (showLoading || !state.hasValue) {
      state = const AsyncValue.loading();
    }

    final future =
        AsyncValue.guard(() => ref.read(botRepositoryProvider).listBots())
            .then((next) {
              state = next;
            })
            .whenComplete(() {
              _refreshInFlight = null;
            });

    _refreshInFlight = future;
    await future;
  }

  Future<Bot> createBot(BotConfig config) async {
    final repo = ref.read(botRepositoryProvider);
    final bot = await repo.createBot(config);
    await refresh();
    return bot;
  }

  /// Delete a stopped bot and refresh the list.
  Future<void> deleteBot(String botId) async {
    final repo = ref.read(botRepositoryProvider);
    await repo.deleteBot(botId);
    await refresh();
  }

  /// Update a bot's config (only when stopped) and refresh the list.
  Future<Bot> updateConfig(String botId, Map<String, dynamic> config) async {
    final repo = ref.read(botRepositoryProvider);
    final bot = await repo.updateConfig(botId, config);
    await refresh();
    return bot;
  }

  /// Rename a bot (allowed regardless of status) and refresh the list.
  Future<Bot> renameBot(String botId, String name) async {
    final repo = ref.read(botRepositoryProvider);
    final bot = await repo.renameBot(botId, name);
    await refresh();
    return bot;
  }
}

/// Provider for a single bot's detail (with live stats).
final botDetailProvider = FutureProvider.family<Bot, String>((
  ref,
  botId,
) async {
  final repo = ref.read(botRepositoryProvider);
  return repo.getBot(botId);
});
