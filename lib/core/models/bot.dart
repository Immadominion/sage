// Bot model — maps to backend `bots` table.
// Covers config, stats, and live engine state.

enum BotMode { simulation, live }

enum BotStatus { stopped, starting, running, stopping, error }

enum StrategyMode { ruleBased, sageAi, both }

class Bot {
  final int id;
  final String botId;
  final int userId;
  final String name;
  final BotMode mode;
  final BotStatus status;
  final StrategyMode strategyMode;

  // Strategy config
  final double entryScoreThreshold;
  final double? mlThreshold;
  final double minVolume24h;
  final double minLiquidity;
  final double maxLiquidity;
  final double positionSizeSOL;
  final int maxConcurrentPositions;
  final int defaultBinRange;
  final double profitTargetPercent;
  final double stopLossPercent;
  final int maxHoldTimeMinutes;
  final double maxDailyLossSOL;
  final int cooldownMinutes;
  final int cronIntervalSeconds;
  final double simulationBalanceSOL;

  // Stats (persisted in DB)
  final int totalTrades;
  final int winningTrades;
  final int totalPnlLamports;
  final String? lastError;
  final DateTime? lastActivityAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Authoritative current simulation balance in SOL.
  /// Computed by backend from: live executor → persisted DB → config fallback.
  /// Always accurate whether the bot is running, stopped, or never started.
  final double currentBalanceSol;

  // Live engine data (only when running)
  final int activePositionCount;
  final bool engineRunning;
  final EngineStats? engineStats;
  final PerformanceSummary? performanceSummary;
  final List<LivePosition> livePositions;

  const Bot({
    required this.id,
    required this.botId,
    required this.userId,
    required this.name,
    required this.mode,
    required this.status,
    required this.strategyMode,
    required this.entryScoreThreshold,
    this.mlThreshold,
    required this.minVolume24h,
    required this.minLiquidity,
    required this.maxLiquidity,
    required this.positionSizeSOL,
    required this.maxConcurrentPositions,
    required this.defaultBinRange,
    required this.profitTargetPercent,
    required this.stopLossPercent,
    required this.maxHoldTimeMinutes,
    required this.maxDailyLossSOL,
    required this.cooldownMinutes,
    required this.cronIntervalSeconds,
    required this.simulationBalanceSOL,
    required this.totalTrades,
    required this.winningTrades,
    required this.totalPnlLamports,
    required this.currentBalanceSol,
    this.lastError,
    this.lastActivityAt,
    required this.createdAt,
    required this.updatedAt,
    this.activePositionCount = 0,
    this.engineRunning = false,
    this.engineStats,
    this.performanceSummary,
    this.livePositions = const [],
  });

  double get winRate =>
      totalTrades > 0 ? (winningTrades / totalTrades * 100) : 0;

  double get totalPnlSOL => totalPnlLamports / 1e9;

  factory Bot.fromJson(Map<String, dynamic> json) {
    final botData = json['bot'] as Map<String, dynamic>? ?? json;

    return Bot(
      id: _parseInt(botData['id']) ?? 0,
      botId: botData['botId'] as String,
      userId: _parseInt(botData['userId']) ?? 0,
      name: botData['name'] as String,
      mode: BotMode.values.firstWhere(
        (e) => e.name == botData['mode'],
        orElse: () => BotMode.simulation,
      ),
      status: _parseStatus(botData['status'] as String),
      strategyMode: _parseStrategyMode(botData['strategyMode'] as String),
      entryScoreThreshold: _parseDouble(botData['entryScoreThreshold']),
      mlThreshold: _parseDoubleNullable(botData['mlThreshold']),
      minVolume24h: _parseDouble(botData['minVolume24h']),
      minLiquidity: _parseDouble(botData['minLiquidity']),
      maxLiquidity: _parseDouble(botData['maxLiquidity']),
      positionSizeSOL: _parseDouble(botData['positionSizeSOL']),
      maxConcurrentPositions: _parseInt(botData['maxConcurrentPositions']) ?? 5,
      defaultBinRange: _parseInt(botData['defaultBinRange']) ?? 10,
      profitTargetPercent: _parseDouble(botData['profitTargetPercent']),
      stopLossPercent: _parseDouble(botData['stopLossPercent']),
      maxHoldTimeMinutes: _parseInt(botData['maxHoldTimeMinutes']) ?? 60,
      maxDailyLossSOL: _parseDouble(botData['maxDailyLossSOL']),
      cooldownMinutes: _parseInt(botData['cooldownMinutes']) ?? 79,
      cronIntervalSeconds: _parseInt(botData['cronIntervalSeconds']) ?? 30,
      simulationBalanceSOL: _parseDouble(botData['simulationBalanceSOL']),
      totalTrades: _parseInt(botData['totalTrades']) ?? 0,
      winningTrades: _parseInt(botData['winningTrades']) ?? 0,
      totalPnlLamports: _parseInt(botData['totalPnlLamports']) ?? 0,
      // currentBalanceSol: Returned at top-level by GET /bot/:id,
      // or inlined into the bot object by GET /bot/list.
      // Fallback to simulationBalanceSOL if neither is present (old backend).
      currentBalanceSol:
          _parseDoubleNullable(json['currentBalanceSol']) ??
          _parseDoubleNullable(botData['currentBalanceSol']) ??
          _parseDouble(botData['simulationBalanceSOL']),
      lastError: botData['lastError'] as String?,
      lastActivityAt: botData['lastActivityAt'] != null
          ? DateTime.parse(botData['lastActivityAt'] as String)
          : null,
      createdAt: DateTime.parse(botData['createdAt'] as String),
      updatedAt: DateTime.parse(botData['updatedAt'] as String),
      activePositionCount:
          _parseInt(json['activePositionCount']) ??
          _parseInt(botData['activePositionCount']) ??
          0,
      engineRunning:
          (json['engineRunning'] as bool?) ??
          (botData['engineRunning'] as bool?) ??
          false,
      engineStats: json['engineStats'] != null
          ? EngineStats.fromJson(json['engineStats'] as Map<String, dynamic>)
          : botData['engineStats'] != null
          ? EngineStats.fromJson(botData['engineStats'] as Map<String, dynamic>)
          : null,
      performanceSummary: json['performanceSummary'] != null
          ? PerformanceSummary.fromJson(
              json['performanceSummary'] as Map<String, dynamic>,
            )
          : botData['performanceSummary'] != null
          ? PerformanceSummary.fromJson(
              botData['performanceSummary'] as Map<String, dynamic>,
            )
          : null,
      livePositions:
          ((json['livePositions'] as List<dynamic>?) ??
                  (botData['livePositions'] as List<dynamic>?))
              ?.map((e) => LivePosition.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  static BotStatus _parseStatus(String s) {
    switch (s) {
      case 'stopped':
        return BotStatus.stopped;
      case 'starting':
        return BotStatus.starting;
      case 'running':
        return BotStatus.running;
      case 'stopping':
        return BotStatus.stopping;
      case 'error':
        return BotStatus.error;
      default:
        return BotStatus.stopped;
    }
  }

  static StrategyMode _parseStrategyMode(String s) {
    switch (s) {
      case 'rule-based':
        return StrategyMode.ruleBased;
      case 'sage-ai':
        return StrategyMode.sageAi;
      case 'both':
        return StrategyMode.both;
      default:
        return StrategyMode.ruleBased;
    }
  }

  /// Safely parse a value that may be int, String, num, or null.
  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Safely parse a double from int, num, String, or null (returns 0.0 on null).
  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  /// Nullable variant of _parseDouble.
  static double? _parseDoubleNullable(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

/// Live engine statistics — only available when bot is running.
class EngineStats {
  final int totalScans;
  final int positionsOpened;
  final int positionsClosed;
  final int wins;
  final int losses;
  final double winRate;
  final double totalPnlSol;
  final String runtime;

  const EngineStats({
    required this.totalScans,
    required this.positionsOpened,
    required this.positionsClosed,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.totalPnlSol,
    required this.runtime,
  });

  factory EngineStats.fromJson(Map<String, dynamic> json) => EngineStats(
    totalScans: _safeInt(json['totalScans']),
    positionsOpened: _safeInt(json['positionsOpened']),
    positionsClosed: _safeInt(json['positionsClosed']),
    wins: _safeInt(json['wins']),
    losses: _safeInt(json['losses']),
    winRate: _safeDouble(json['winRate']),
    totalPnlSol: _safeDouble(json['totalPnlSol']),
    runtime: json['runtime'] as String? ?? '',
  );

  static int _safeInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double _safeDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}

/// Performance summary from simulation executor.
class PerformanceSummary {
  final int totalPositions;
  final int wins;
  final int losses;
  final double totalPnlSol;
  final double currentBalanceSol;
  final double winRate;

  const PerformanceSummary({
    required this.totalPositions,
    required this.wins,
    required this.losses,
    required this.totalPnlSol,
    required this.currentBalanceSol,
    required this.winRate,
  });

  factory PerformanceSummary.fromJson(Map<String, dynamic> json) =>
      PerformanceSummary(
        totalPositions: _safeInt(json['totalPositions']),
        wins: _safeInt(json['wins']),
        losses: _safeInt(json['losses']),
        totalPnlSol: _safeDouble(json['totalPnlSol']),
        currentBalanceSol: _safeDouble(json['currentBalanceSol']),
        winRate: _safeDouble(json['winRate']),
      );

  static int _safeInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double _safeDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}

/// A simplified position returned in the bot detail response.
class LivePosition {
  final String id;
  final String? poolName;
  final String poolAddress;
  final double entryPrice;
  final double currentPrice;
  final int entryTimestamp;
  final String status;

  const LivePosition({
    required this.id,
    this.poolName,
    required this.poolAddress,
    required this.entryPrice,
    required this.currentPrice,
    required this.entryTimestamp,
    required this.status,
  });

  double get pnlPercent =>
      entryPrice > 0 ? ((currentPrice - entryPrice) / entryPrice * 100) : 0;

  Duration get holdDuration => DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(entryTimestamp),
  );

  factory LivePosition.fromJson(Map<String, dynamic> json) => LivePosition(
    id: json['id']?.toString() ?? '',
    poolName: json['poolName'] as String?,
    poolAddress: json['poolAddress']?.toString() ?? '',
    entryPrice: _safeDouble(json['entryPrice']),
    currentPrice: _safeDouble(json['currentPrice']),
    entryTimestamp: _safeInt(json['entryTimestamp']),
    status: json['status']?.toString() ?? 'active',
  );

  static int _safeInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double _safeDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}

/// Config payload for creating/updating a bot.
class BotConfig {
  /// Optional — if omitted the backend auto-generates "Strategy N".
  final String? name;
  final String mode;
  final Map<String, dynamic> config;

  const BotConfig({
    this.name,
    this.mode = 'simulation',
    this.config = const {},
  });

  /// Flatten config fields to top level — backend Zod schema expects
  /// all fields (strategyMode, positionSizeSOL, etc.) at root, not
  /// nested under a "config" key.
  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    'mode': mode,
    ...config,
  };
}
