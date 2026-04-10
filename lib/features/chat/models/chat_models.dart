/// Chat message model for Sage AI conversations.
class ChatMessage {
  final String role; // "user" or "assistant"
  final String content;
  final DateTime timestamp;

  /// Strategy parameters attached to this message (if AI generated them).
  /// This makes params survive dismissal — they live on the message, not just
  /// in ephemeral state.
  final StrategyParams? strategyParams;

  const ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.strategyParams,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  /// Whether this message carries strategy parameters.
  bool get hasStrategy => strategyParams != null && !strategyParams!.isEmpty;

  /// Return a copy with updated strategy params.
  ChatMessage withStrategyParams(StrategyParams? params) => ChatMessage(
    role: role,
    content: content,
    timestamp: timestamp,
    strategyParams: params,
  );

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      strategyParams: json['strategyParams'] != null
          ? StrategyParams.fromJson(
              json['strategyParams'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    if (strategyParams != null) 'strategyParams': strategyParams!.toJson(),
  };
}

/// Strategy parameters extracted by Claude from conversation.
class StrategyParams {
  final double? entryScoreThreshold;
  final double? minVolume24h;
  final double? minLiquidity;
  final double? maxLiquidity;
  final double? positionSizeSOL;
  final double? simulationBalanceSOL;
  final int? maxConcurrentPositions;
  final int? defaultBinRange;
  final double? profitTargetPercent;
  final double? stopLossPercent;
  final int? maxHoldTimeMinutes;
  final double? maxDailyLossSOL;
  final int? cooldownMinutes;

  const StrategyParams({
    this.entryScoreThreshold,
    this.minVolume24h,
    this.minLiquidity,
    this.maxLiquidity,
    this.positionSizeSOL,
    this.simulationBalanceSOL,
    this.maxConcurrentPositions,
    this.defaultBinRange,
    this.profitTargetPercent,
    this.stopLossPercent,
    this.maxHoldTimeMinutes,
    this.maxDailyLossSOL,
    this.cooldownMinutes,
  });

  bool get isEmpty =>
      entryScoreThreshold == null &&
      minVolume24h == null &&
      minLiquidity == null &&
      maxLiquidity == null &&
      positionSizeSOL == null &&
      simulationBalanceSOL == null &&
      maxConcurrentPositions == null &&
      defaultBinRange == null &&
      profitTargetPercent == null &&
      stopLossPercent == null &&
      maxHoldTimeMinutes == null &&
      maxDailyLossSOL == null &&
      cooldownMinutes == null;

  factory StrategyParams.fromJson(Map<String, dynamic> json) {
    return StrategyParams(
      entryScoreThreshold: (json['entryScoreThreshold'] as num?)?.toDouble(),
      minVolume24h: (json['minVolume24h'] as num?)?.toDouble(),
      minLiquidity: (json['minLiquidity'] as num?)?.toDouble(),
      maxLiquidity: (json['maxLiquidity'] as num?)?.toDouble(),
      positionSizeSOL: (json['positionSizeSOL'] as num?)?.toDouble(),
      simulationBalanceSOL: (json['simulationBalanceSOL'] as num?)?.toDouble(),
      maxConcurrentPositions: json['maxConcurrentPositions'] as int?,
      defaultBinRange: json['defaultBinRange'] as int?,
      profitTargetPercent: (json['profitTargetPercent'] as num?)?.toDouble(),
      stopLossPercent: (json['stopLossPercent'] as num?)?.toDouble(),
      maxHoldTimeMinutes: json['maxHoldTimeMinutes'] as int?,
      maxDailyLossSOL: (json['maxDailyLossSOL'] as num?)?.toDouble(),
      cooldownMinutes: json['cooldownMinutes'] as int?,
    );
  }

  StrategyParams copyWith({
    double? entryScoreThreshold,
    double? minVolume24h,
    double? minLiquidity,
    double? maxLiquidity,
    double? positionSizeSOL,
    double? simulationBalanceSOL,
    int? maxConcurrentPositions,
    int? defaultBinRange,
    double? profitTargetPercent,
    double? stopLossPercent,
    int? maxHoldTimeMinutes,
    double? maxDailyLossSOL,
    int? cooldownMinutes,
  }) {
    return StrategyParams(
      entryScoreThreshold: entryScoreThreshold ?? this.entryScoreThreshold,
      minVolume24h: minVolume24h ?? this.minVolume24h,
      minLiquidity: minLiquidity ?? this.minLiquidity,
      maxLiquidity: maxLiquidity ?? this.maxLiquidity,
      positionSizeSOL: positionSizeSOL ?? this.positionSizeSOL,
      simulationBalanceSOL: simulationBalanceSOL ?? this.simulationBalanceSOL,
      maxConcurrentPositions:
          maxConcurrentPositions ?? this.maxConcurrentPositions,
      defaultBinRange: defaultBinRange ?? this.defaultBinRange,
      profitTargetPercent: profitTargetPercent ?? this.profitTargetPercent,
      stopLossPercent: stopLossPercent ?? this.stopLossPercent,
      maxHoldTimeMinutes: maxHoldTimeMinutes ?? this.maxHoldTimeMinutes,
      maxDailyLossSOL: maxDailyLossSOL ?? this.maxDailyLossSOL,
      cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (entryScoreThreshold != null)
      map['entryScoreThreshold'] = entryScoreThreshold;
    if (minVolume24h != null) map['minVolume24h'] = minVolume24h;
    if (minLiquidity != null) map['minLiquidity'] = minLiquidity;
    if (maxLiquidity != null) map['maxLiquidity'] = maxLiquidity;
    if (positionSizeSOL != null) map['positionSizeSOL'] = positionSizeSOL;
    if (simulationBalanceSOL != null) {
      map['simulationBalanceSOL'] = simulationBalanceSOL;
    }
    if (maxConcurrentPositions != null)
      map['maxConcurrentPositions'] = maxConcurrentPositions;
    if (defaultBinRange != null) map['defaultBinRange'] = defaultBinRange;
    if (profitTargetPercent != null)
      map['profitTargetPercent'] = profitTargetPercent;
    if (stopLossPercent != null) map['stopLossPercent'] = stopLossPercent;
    if (maxHoldTimeMinutes != null)
      map['maxHoldTimeMinutes'] = maxHoldTimeMinutes;
    if (maxDailyLossSOL != null) map['maxDailyLossSOL'] = maxDailyLossSOL;
    if (cooldownMinutes != null) map['cooldownMinutes'] = cooldownMinutes;
    return map;
  }
}

/// Summary of a conversation (for list view).
class ConversationSummary {
  final String conversationId;
  final String type;
  final String? title;
  final int messageCount;
  final bool hasStrategyParams;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ConversationSummary({
    required this.conversationId,
    required this.type,
    this.title,
    required this.messageCount,
    required this.hasStrategyParams,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      conversationId: json['conversationId'] as String,
      type: json['type'] as String,
      title: json['title'] as String?,
      messageCount: json['messageCount'] as int? ?? 0,
      hasStrategyParams: json['hasStrategyParams'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// AI service status.
class AiStatus {
  final bool llm;
  final bool stt;

  const AiStatus({required this.llm, required this.stt});

  factory AiStatus.fromJson(Map<String, dynamic> json) {
    return AiStatus(
      llm: json['llm'] as bool? ?? false,
      stt: json['stt'] as bool? ?? false,
    );
  }
}

/// An action the AI wants to perform in the app.
class AppAction {
  final String type;
  final Map<String, dynamic> payload;

  const AppAction({required this.type, required this.payload});

  factory AppAction.fromJson(Map<String, dynamic> json) {
    return AppAction(
      type: json['type'] as String,
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }
}
