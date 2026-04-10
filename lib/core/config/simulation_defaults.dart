import 'dart:math' as math;

const double kDefaultSimulationBalanceSOL = 20.0;
const double kMinSimulationBalanceSOL = 0.2;
const double kMaxSimulationBalanceSOL = 100.0;
const double kSimulationReserveSOL = 0.07;
const double kSimulationBalanceStepSOL = 0.1;

double normalizeSimulationBalanceSOL(double value) {
  final clamped = value.clamp(
    kMinSimulationBalanceSOL,
    kMaxSimulationBalanceSOL,
  );
  return _roundToStep(clamped.toDouble());
}

double minimumSimulationBalanceSOL(double positionSizeSOL) {
  final minimum = math.max(
    kMinSimulationBalanceSOL,
    positionSizeSOL + kSimulationReserveSOL,
  );
  return _roundUpToStep(minimum);
}

double clampSimulationBalanceSOL({
  required double requested,
  required double positionSizeSOL,
}) {
  final normalized = normalizeSimulationBalanceSOL(requested);
  final minimum = minimumSimulationBalanceSOL(positionSizeSOL);
  return math.max(normalized, minimum);
}

double recommendedSimulationBalanceSOL({
  required double positionSizeSOL,
  required int maxConcurrentPositions,
}) {
  final recommended = math.max(
    kDefaultSimulationBalanceSOL,
    positionSizeSOL * math.max(1, maxConcurrentPositions),
  );
  return clampSimulationBalanceSOL(
    requested: recommended,
    positionSizeSOL: positionSizeSOL,
  );
}

double _roundToStep(double value) {
  return (value / kSimulationBalanceStepSOL).round() *
      kSimulationBalanceStepSOL;
}

double _roundUpToStep(double value) {
  return (value / kSimulationBalanceStepSOL).ceil() * kSimulationBalanceStepSOL;
}
