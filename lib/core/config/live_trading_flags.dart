/// Master switch for live trading.
///
/// When `true`, users can create and start live-mode bots that trade real SOL
/// via server-side encrypted keypairs (AES-256-GCM). The backend still enforces
/// `SOLANA_NETWORK=mainnet-beta` as a second guard.
///
/// Set to `false` only if there is a known security issue or the backend is
/// not yet deployed to mainnet.
const bool kLiveTradingEnabled = true;

/// Shown when live trading is disabled — update this if you flip the flag.
const String kLiveTradingDisabledReason =
    'Live trading is temporarily unavailable. '
    'Please check back soon.';
