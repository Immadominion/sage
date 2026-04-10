# Sage Backend — System Design

> **Author**: Sage Engineering  
> **Date**: February 26, 2026  
> **Status**: Design Document — Pre-Implementation  
> **Target**: MONOLITH Hackathon (March 9, 2026)

---

## 1. Executive Summary

### What We Have Today

The current `seal/backend/` is a **thin API layer** — 13 REST endpoints that prepare unsigned Seal wallet transactions and read on-chain account state. It does NOT handle:

- User sessions / authentication
- Bot lifecycle (create, configure, start, stop, monitor)
- Rule-based strategy storage
- ML inference (Sage AI)
- Real-time market data streaming
- Trade execution on Meteora DLMM
- Position tracking and PnL reporting

### What We Need

A **full backend platform** that:

1. Authenticates users via wallet signature (Sign-In With Solana)
2. Manages bot instances per user — each with their own config
3. Executes trades on Meteora DLMM on behalf of users (via Seal session keys)
4. Serves ML predictions from the trained XGBoost model
5. Streams real-time updates to the mobile app
6. Persists user strategies, trade history, and performance data

### Design Principles

| Principle | Rationale |
|-----------|-----------|
| **Non-custodial execution** | Users fund their Seal wallet, backend uses session keys — never holds user private keys |
| **Modular engine** | lp-bot's TradingEngine is already proven — wrap it, don't rewrite it |
| **Event-driven architecture** | Bot events (open/close/error) push to clients via WebSockets |
| **Database-backed state** | User configs, strategies, trade logs stored in PostgreSQL (not JSON files like lp-bot) |
| **Horizontal scaling** | Each user's bot runs as an isolated worker — independent crash domains |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        SAGE MOBILE APP                          │
│                    (Flutter / MWA Signing)                       │
│                                                                  │
│   Signs: wallet creation, agent registration, fund transfers     │
│   Views: positions, PnL, strategy status, model confidence       │
│   Controls: start/stop bots, adjust parameters, kill switch      │
└──────────────────────────┬──────────────────────────────────────┘
                           │
               REST API + WebSocket (wss://)
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│                     SAGE API GATEWAY                             │
│                  (Hono on Node.js / Bun)                         │
│                                                                  │
│   Auth:    SIWS (Sign-In With Solana) → JWT                     │
│   Routes:  /auth, /user, /wallet, /bot, /strategy, /ml, /ws     │
│   Guards:  Rate limiting, JWT validation, input validation (Zod) │
└──────────┬────────────┬────────────┬───────────────────────────┘
           │            │            │
     ┌─────▼────┐ ┌─────▼─────┐ ┌───▼──────────┐
     │ Seal │ │ Bot       │ │ ML Service   │
     │ Service  │ │ Orchestr. │ │ (Inference)  │
     │          │ │           │ │              │
     │ Wallet   │ │ Per-user  │ │ XGBoost      │
     │ Agent    │ │ engines   │ │ predictions  │
     │ Session  │ │ lifecycle │ │ + confidence │
     └─────┬────┘ └─────┬─────┘ └───┬──────────┘
           │            │            │
     ┌─────▼────────────▼────────────▼──────────────┐
     │              DATA LAYER                        │
     │                                                │
     │   PostgreSQL: users, strategies, trades, bots  │
     │   Redis: session cache, rate limits, pub/sub   │
     │   Solana RPC: on-chain reads                   │
     │   Helius: webhooks, enhanced txs               │
     └────────────────────────────────────────────────┘
```

---

## 3. Why Not Express? Technology Decision

The current seal backend uses Express 5. For the full Sage backend, we should evaluate:

| Factor | Express 5 | Hono | Fastify |
|--------|-----------|------|---------|
| TypeScript DX | Good (manual types) | **Excellent** (built-in, RPC mode) | Good |
| Performance | Moderate | **Fast** (Web Standards) | Fast |
| Bundle size | 572KB | **14KB** | ~200KB |
| Middleware | Massive ecosystem | Built-in + compatible | Plugin system |
| WebSocket | Via ws package | Built-in helpers | Via plugin |
| Runtime | Node.js only | **Node, Bun, Deno, CF Workers** | Node.js |
| Zod integration | Manual | **First-class** (`@hono/zod-validator`) | Via plugin |
| Maturity | Very mature | Growing fast (Cloudflare, Unkey use it) | Very mature |

**Decision**: Use **Hono** on Node.js (or Bun if stable enough). Reasons:

- First-class TypeScript with RPC mode (type-safe client generation for Flutter)
- Web Standards compatible (future-proof for edge deployment)
- Built-in Zod validation
- Ultrafast routing
- If Bun runtime works, we get 4x faster startup

**Fallback**: If Hono causes friction, Express 5 is already proven in our codebase. The business logic is framework-agnostic.

---

## 4. Authentication — Sign-In With Solana (SIWS)

### Flow

```
Mobile App                    Backend                         Solana
    │                            │                              │
    │─── GET /auth/nonce ───────>│                              │
    │<── { nonce, domain } ──────│                              │
    │                            │                              │
    │── Sign message via MWA ──> │ (Phantom/Solflare)           │
    │<── signature ──────────────│                              │
    │                            │                              │
    │── POST /auth/verify ──────>│                              │
    │   { pubkey, signature,     │── Verify Ed25519 sig ──────> │
    │     message }              │<── Valid ────────────────── │
    │<── { jwt, refreshToken } ──│                              │
    │                            │── Upsert user in DB          │
```

### Implementation

```typescript
// Message format (SIWS standard)
const message = [
  `sage.scrolls.fun wants you to sign in with your Solana account:`,
  publicKey.toBase58(),
  ``,
  `Sign in to Sage`,
  ``,
  `URI: https://sage.scrolls.fun`,
  `Version: 1`,
  `Chain ID: mainnet`,
  `Nonce: ${nonce}`,
  `Issued At: ${new Date().toISOString()}`,
].join('\n');
```

- **No password, no email** — wallet IS the identity
- JWT expires in 24h, refresh token in 30d
- Nonce stored in Redis with 5-minute TTL to prevent replay

---

## 5. User Flow — First-Time Setup

This is the critical UX question. The user has just connected their wallet. What happens next?

### Design: Single Setup Sheet (NOT Separate Screens)

Instead of 5 sequential screens, we use a **single scrollable setup sheet** with progressive sections. The user can complete it in under 60 seconds or skip entirely.

```
┌──────────────────────────────────────┐
│  Welcome to Sage                     │
│  Let's set up your trading agent.    │
│                                      │
│  ┌─ STEP 1: Choose Your Mode ──────┐│
│  │                                  ││
│  │  ◉ Rule-Based Bot               ││
│  │    "I define the rules"          ││
│  │                                  ││
│  │  ○ Sage AI                       ││
│  │    "ML-powered, I set risk"      ││
│  │                                  ││
│  │  ○ Both                          ││
│  │    "Custom rules + AI together"  ││
│  └──────────────────────────────────┘│
│                                      │
│  ┌─ STEP 2: Fund Your Agent ───────┐│
│  │                                  ││
│  │  Agent Wallet Balance: 0 SOL     ││
│  │  [Deposit 1 SOL] [5] [10] [__]  ││
│  │                                  ││
│  │  Per-trade size: [0.5 SOL ▼]     ││
│  │  Max concurrent: [3 ▼]           ││
│  │  Daily limit:    [5 SOL ▼]       ││
│  └──────────────────────────────────┘│
│                                      │
│  ┌─ STEP 3: Risk Profile ──────────┐│
│  │                                  ││
│  │  ○ Conservative                  ││
│  │    5% profit / 8% stop / 4h max  ││
│  │                                  ││
│  │  ◉ Balanced                      ││
│  │    8% profit / 12% stop / 4h max ││
│  │                                  ││
│  │  ○ Aggressive                    ││
│  │    15% profit / 20% stop / 8h max││
│  └──────────────────────────────────┘│
│                                      │
│  [Skip for Now]      [Start Trading] │
└──────────────────────────────────────┘
```

### What "Start Trading" Does (Backend)

1. Creates Seal smart wallet (if not exists) → user signs via MWA
2. Registers backend as an agent on the wallet → user signs via MWA
3. Creates session key for the backend agent → user signs via MWA
4. Saves strategy config to database
5. Spawns a bot worker for this user
6. Redirects to Home (Mode 1 or 3 depending on choice)

### What "Skip for Now" Does

1. Creates Seal wallet only (one MWA signature)
2. Shows the app in "explore" mode — all data is mock/demo
3. Setup sheet accessible anytime from Settings

---

## 6. Bot Orchestrator — The Core Engine

### How lp-bot Becomes a Multi-Tenant Service

The existing `lp-bot` has exactly the right architecture. It already has:

- `TradingEngine` — CRON scanning, position entry/exit, scoring
- `BotManager` — multi-instance management with independent configs
- `ITradingExecutor` — pluggable execution (sim vs live)
- `IMarketDataProvider` — real Meteora API data with caching
- `LiveExecutorV2` — real transaction execution with safety layers

**The key insight**: We don't rewrite lp-bot. We wrap it.

```
┌─ Bot Orchestrator ──────────────────────────────────┐
│                                                      │
│  ┌── User A ──────────────────────┐                  │
│  │  TradingEngine (config A)      │                  │
│  │  ├─ LiveExecutorV2 (session A) │  ← Seal      │
│  │  ├─ MarketDataProvider (shared)│  ← Shared cache  │
│  │  └─ StatePersistence (DB)      │  ← PostgreSQL    │
│  └────────────────────────────────┘                  │
│                                                      │
│  ┌── User B ──────────────────────┐                  │
│  │  TradingEngine (config B)      │                  │
│  │  ├─ LiveExecutorV2 (session B) │                  │
│  │  ├─ MarketDataProvider (shared)│                  │
│  │  └─ StatePersistence (DB)      │                  │
│  └────────────────────────────────┘                  │
│                                                      │
│  Shared Resources:                                   │
│  ├─ SharedAPICache (Meteora pair/all, 30s TTL)       │
│  ├─ ConnectionPool (Helius RPC)                      │
│  └─ EventBus (Redis pub/sub → WebSocket)             │
└──────────────────────────────────────────────────────┘
```

### Per-User Bot Lifecycle

```typescript
interface BotInstance {
  userId: string;
  botId: string;
  status: 'starting' | 'running' | 'paused' | 'stopped' | 'error';
  mode: 'rule-based' | 'sage-ai' | 'hybrid';
  config: UserBotConfig;
  engine: TradingEngine;
  executor: LiveExecutorV2;
  sessionKey: PublicKey; // Seal session key for this bot
  startedAt: Date;
  lastActivity: Date;
}
```

### Seal Integration for Execution

Traditional bot: bot holds the wallet private key.
Sage: bot uses a **Seal session key** with on-chain spending limits.

```
User's Seal Wallet (PDA on-chain)
  └─ Backend Agent (registered with allowlists)
       └─ Session Key (time-bounded, amount-capped)
            └─ Bot executes via session → CPI to Meteora DLMM
```

**This is our competitive advantage.** The user never gives us their private key. The session key enforces limits on-chain. If our server is compromised, the attacker can only spend up to the session's remaining limit, and the user can revoke instantly from a different device.

---

## 7. Rule-Based Bot — Strategy Configuration

### What Rules Can Users Configure?

Based on lp-bot's proven `BotConfig`, users can set:

| Category | Parameters | UI Control |
|----------|------------|------------|
| **Entry** | Market score threshold (50-300) | Slider |
| | Min 24h volume ($) | Number input |
| | Min/Max liquidity ($) | Range slider |
| | SOL pairs only toggle | Toggle |
| | Token blacklist | Multi-select |
| **Position Sizing** | Size mode (% of balance / fixed) | Toggle |
| | Position size (% or SOL) | Slider |
| | Max concurrent positions (1-10) | Stepper |
| **Exit Rules** | Profit target % (1-50%) | Slider |
| | Stop loss % (1-50%) | Slider |
| | Max hold time (15m-24h) | Dropdown |
| | Trailing stop toggle + % | Toggle + slider |
| | Cooldown after exit (10-240m) | Slider |
| **Safety** | Max daily loss (SOL) | Number input |
| | Emergency stop toggle | Big red button |

### Preset Strategies (Templates)

| Template | Description | Key Settings |
|----------|-------------|-------------|
| **FreesolGames** | Proven 77% win rate pattern | 150 threshold, 79m cooldown, 1 SOL size |
| **Conservative** | Low risk, lower returns | 200 threshold, 5% profit, 8% stop, 120m cooldown |
| **Heart Attack** | Tight range, fast trades | 100 threshold, 15% profit, 20% stop, 30m max hold |
| **Slow & Steady** | Wide range, overnight holds | 180 threshold, 10% profit, 12% stop, 4h max hold |
| **Custom** | User defines everything | All fields editable |

### Is This Novel?

**Yes.** Existing Solana trading bots (BullX, Trojan, Bonkbot, Photon) are:

- **Swap bots** — buy/sell tokens on DEXs. Manual trigger or copy-trade.
- **Sniper bots** — detect new token launches, buy early.
- **Telegram-based** — text interface, not mobile-native.

**Nobody** offers:

- Configurable **LP strategy** bots on Meteora DLMM
- Non-custodial execution via session keys
- ML-augmented entry timing
- Mobile-native with real-time status

This is genuinely new. LP automation exists only as scripts (our lp-bot) and centralized vaults (Hawksight, Kamino). A user-configurable, non-custodial LP bot on mobile doesn't exist.

---

## 8. Sage AI Mode — ML Integration

### Current State

- XGBoost model trained on 200K+ data points from Meteora DLMM
- Predicts: "Is this pool profitable to enter right now?" → probability 0-1
- Features: volume, volatility, fee rate, bin activity, momentum

### Integration

```
Mobile App → "Activate Sage AI"
    │
    ▼
Backend creates bot with mode='sage-ai'
    │
    ▼
TradingEngine.scanMarkets()
    │
    ├─ Normal pool scoring (market data)
    │
    ├─ ML prediction request
    │   └─ POST /ml/predict { pool_features }
    │       └─ Returns { probability: 0.82, confidence: 'high' }
    │
    └─ Combined score = market_score * ml_weight + ml_probability * (1 - ml_weight)
```

### Can the Model Learn From Its Own Trades?

**Short answer: Partially, with caveats.**

- **What works**: Logging every trade (entry features, outcome PnL, hold time) and periodically retraining. This is standard online learning.
- **What doesn't**: The model can't learn from a single user's trades — too few data points. It needs aggregate data across all users (with consent).
- **The risk**: Feedback loops. If the model avoids pools because it lost there, it might miss regime changes. Mitigation: always include fresh Meteora API data, not just historical.
- **For MONOLITH**: We DON'T implement online learning. We ship with the pre-trained model. Trade logging is stored for future retraining offline.

### User Config for Sage AI

| Setting | Options | Default |
|---------|---------|---------|
| Risk level | Conservative / Balanced / Aggressive | Balanced |
| Capital allocated | 1-100 SOL | 5 SOL |
| Min model confidence | 50-90% | 70% |
| Auto-reinvest profits | Yes / No | Yes |
| Trading hours | 24/7 / Custom schedule | 24/7 |

---

## 9. Database Schema

```sql
-- Users (wallet = identity)
CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_pubkey VARCHAR(50) UNIQUE NOT NULL,
  seal_wallet VARCHAR(50),  -- Seal PDA address
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  last_login    TIMESTAMPTZ,
  settings      JSONB DEFAULT '{}'
);

-- Bot configurations (one per user per strategy)
CREATE TABLE bots (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID REFERENCES users(id) ON DELETE CASCADE,
  name          VARCHAR(100) NOT NULL,
  mode          VARCHAR(20) NOT NULL CHECK (mode IN ('rule-based', 'sage-ai', 'hybrid')),
  status        VARCHAR(20) DEFAULT 'stopped',
  config        JSONB NOT NULL,  -- Full BotConfig serialized
  session_key   VARCHAR(50),     -- Seal session key address
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW(),
  started_at    TIMESTAMPTZ,
  stopped_at    TIMESTAMPTZ
);

-- Active and historical positions
CREATE TABLE positions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bot_id        UUID REFERENCES bots(id) ON DELETE CASCADE,
  user_id       UUID REFERENCES users(id),
  pool_address  VARCHAR(50) NOT NULL,
  pool_name     VARCHAR(100),
  status        VARCHAR(20) DEFAULT 'open',
  entry_price   NUMERIC,
  exit_price    NUMERIC,
  amount_sol    NUMERIC NOT NULL,
  pnl_sol       NUMERIC,
  fees_earned   NUMERIC,
  entry_score   NUMERIC,
  ml_probability NUMERIC,
  exit_reason   VARCHAR(100),
  entry_tx      VARCHAR(100),
  exit_tx       VARCHAR(100),
  opened_at     TIMESTAMPTZ DEFAULT NOW(),
  closed_at     TIMESTAMPTZ,
  metadata      JSONB DEFAULT '{}'
);

-- Strategy presets (system + user-created)
CREATE TABLE strategy_presets (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID REFERENCES users(id),  -- NULL = system preset
  name          VARCHAR(100) NOT NULL,
  description   TEXT,
  config        JSONB NOT NULL,
  is_public     BOOLEAN DEFAULT false,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Trade log (every entry/exit for analytics + ML retraining)
CREATE TABLE trade_log (
  id            BIGSERIAL PRIMARY KEY,
  bot_id        UUID REFERENCES bots(id),
  user_id       UUID REFERENCES users(id),
  action        VARCHAR(10) NOT NULL,  -- 'open' or 'close'
  pool_address  VARCHAR(50) NOT NULL,
  pool_name     VARCHAR(100),
  amount_sol    NUMERIC NOT NULL,
  pnl_sol       NUMERIC,
  fees_earned   NUMERIC,
  entry_score   NUMERIC,
  ml_probability NUMERIC,
  exit_reason   VARCHAR(100),
  tx_signature  VARCHAR(100),
  -- ML features at time of trade (for retraining)
  features      JSONB,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_bots_user ON bots(user_id);
CREATE INDEX idx_positions_bot ON positions(bot_id);
CREATE INDEX idx_positions_user ON positions(user_id);
CREATE INDEX idx_positions_status ON positions(status);
CREATE INDEX idx_trade_log_bot ON trade_log(bot_id);
CREATE INDEX idx_trade_log_created ON trade_log(created_at);
```

### Database Choice for MONOLITH

**Pragmatic decision**: Use **Supabase** (hosted PostgreSQL + Auth + Realtime).

- Free tier: 500MB, 50K rows — more than enough for hackathon
- Built-in auth (but we use our own SIWS → JWT)
- Real-time subscriptions via WebSocket (positions table changes)
- REST + SQL access
- Scales to paid tier if product grows

**Alternative**: SQLite via Turso (serverless, edge-deployed). Simpler but less ecosystem.

---

## 10. API Design

### Route Groups

```
/auth
  POST /auth/nonce          → Generate nonce for SIWS
  POST /auth/verify         → Verify signature, return JWT
  POST /auth/refresh        → Refresh JWT

/user
  GET  /user/me             → Get current user profile
  PUT  /user/settings       → Update user settings

/wallet
  POST /wallet/create       → Prepare Seal wallet creation tx
  GET  /wallet/state        → Get user's Seal wallet state
  GET  /wallet/balance      → Get wallet SOL balance
  POST /wallet/fund         → Prepare SOL transfer to Seal wallet

/bot
  POST /bot/create          → Create bot with config
  GET  /bot/list            → List user's bots
  GET  /bot/:id             → Get bot status + stats
  PUT  /bot/:id/config      → Update bot config (must be stopped)
  POST /bot/:id/start       → Start bot
  POST /bot/:id/stop        → Stop bot
  POST /bot/:id/pause       → Pause bot (finish current trades)
  DELETE /bot/:id           → Delete bot (must be stopped)
  POST /bot/:id/emergency   → Emergency close all positions

/strategy
  GET  /strategy/presets     → List available strategy presets
  POST /strategy/create      → Save custom strategy
  GET  /strategy/:id         → Get strategy details

/position
  GET  /position/active      → All active positions across user's bots
  GET  /position/history     → Closed positions with PnL
  GET  /position/:id         → Single position detail

/ml
  GET  /ml/status            → Model status, last retrain date
  POST /ml/predict           → Get prediction for a pool (internal)
  GET  /ml/performance       → Model accuracy metrics

/market
  GET  /market/pools         → Top pools by score (cached, shared)
  GET  /market/pool/:address → Single pool detail with score

/ws (WebSocket)
  → Bot status changes
  → Position opens/closes
  → Real-time PnL updates
  → Market alerts
```

---

## 11. Real-Time Updates — WebSocket Protocol

### Connection

```
wss://api.sage.scrolls.fun/ws?token=<jwt>
```

### Message Types (Server → Client)

```typescript
type WSMessage =
  | { type: 'bot:status';    botId: string; status: BotStatus; }
  | { type: 'position:open'; position: PositionSummary; }
  | { type: 'position:close'; position: PositionSummary; pnl: number; }
  | { type: 'position:update'; positionId: string; currentPnl: number; }
  | { type: 'balance:update'; balance: number; }
  | { type: 'alert';         level: 'info'|'warn'|'error'; message: string; }
  | { type: 'stats:update';  stats: BotStats; }
```

### Message Types (Client → Server)

```typescript
type WSClientMessage =
  | { type: 'subscribe'; channels: string[]; }   // 'bot:*', 'position:*'
  | { type: 'ping'; }
```

---

## 12. Infrastructure for Helius

You paid for Helius ($49/mo Developer plan). Here's what we use it for:

| Feature | Use Case | Priority |
|---------|----------|----------|
| **RPC Node** | All Solana reads (getAccountInfo, getBalance) | P0 — replace public RPC |
| **Enhanced Transactions** | Parse tx details for position tracking | P1 |
| **Webhooks** | Watch Seal wallet for deposits/withdrawals | P2 |
| **DAS API** | Token metadata, ownership verification | P2 |
| **gRPC (Yellowstone)** | Real-time account changes (requires Business plan) | P3 — future |

### Immediate Use

Replace `https://api.devnet.solana.com` with Helius RPC in all services:

```
SOLANA_RPC_URL=https://devnet.helius-rpc.com/?api-key=<YOUR_KEY>
```

This alone fixes rate limiting issues that plagued lp-bot in production.

---

## 13. Security Considerations

| Concern | Mitigation |
|---------|------------|
| Backend compromise → user funds at risk | Seal session keys cap max exposure. Users can revoke from any device. |
| JWT theft | Short expiry (24h), refresh rotation, device binding (future) |
| Bot goes rogue (bug) | EmergencyStop + CircuitBreaker from lp-bot already handle this |
| Database leak | No private keys stored. Wallet pubkeys are public anyway. |
| RPC abuse | Helius rate limits + our own per-user rate limiting |
| DDoS | Cloudflare in front, rate limiting at API gateway |

---

## 14. Deployment Architecture (MONOLITH MVP)

For the hackathon, keep it simple:

```
┌─ Railway / Fly.io ──────────────────┐
│                                      │
│  ┌─ API Server ────────────┐        │
│  │  Hono + Node.js         │        │
│  │  Bot Orchestrator       │        │
│  │  WebSocket server       │        │
│  └─────────────────────────┘        │
│                                      │
│  ┌─ Worker (optional) ────┐        │
│  │  Background bot loops   │        │
│  │  ML inference server    │        │
│  └─────────────────────────┘        │
│                                      │
│  Supabase (external)                 │
│  ├─ PostgreSQL                       │
│  └─ Realtime subscriptions           │
│                                      │
│  Helius (external)                   │
│  └─ RPC + webhooks                   │
└──────────────────────────────────────┘
```

**Cost**: Railway free tier (500h/mo) + Supabase free tier + Helius ($49/mo) = **$49/mo total**.

---

## 15. What the Current seal/backend Becomes

The current `seal/backend/` (13 endpoints) gets **absorbed** into the new Sage backend as the `SealService` module. It's not thrown away — it's promoted to a service layer.

```
sage-backend/
├── src/
│   ├── index.ts                 # Hono app entry
│   ├── config.ts                # Env validation (Zod)
│   ├── db/                      # Database client + migrations
│   │   ├── client.ts
│   │   ├── schema.ts
│   │   └── migrations/
│   ├── auth/                    # SIWS + JWT
│   │   ├── siws.ts
│   │   ├── jwt.ts
│   │   └── middleware.ts
│   ├── routes/
│   │   ├── auth.ts
│   │   ├── user.ts
│   │   ├── wallet.ts            # ← Evolved from seal/backend
│   │   ├── bot.ts               # NEW — bot lifecycle
│   │   ├── strategy.ts          # NEW — strategy CRUD
│   │   ├── position.ts          # NEW — position tracking
│   │   ├── market.ts            # NEW — pool data
│   │   ├── ml.ts                # NEW — ML predictions
│   │   └── ws.ts                # NEW — WebSocket
│   ├── services/
│   │   ├── seal.ts          # ← Evolved from seal/backend
│   │   ├── bot-orchestrator.ts  # NEW — wraps lp-bot engine
│   │   ├── market-data.ts       # ← From lp-bot providers
│   │   ├── ml-service.ts        # NEW — XGBoost inference
│   │   └── ws-manager.ts        # NEW — WebSocket broadcast
│   ├── engine/                  # ← Adapted from lp-bot/src/engine
│   │   ├── trading-engine.ts
│   │   ├── bot-instance.ts
│   │   └── shared-cache.ts
│   ├── executors/               # ← Adapted from lp-bot/src/executors
│   │   ├── seal-executor.ts # NEW — executes via Seal session
│   │   └── simulation.ts       # ← From lp-bot (for demo mode)
│   └── middleware/
│       ├── auth-guard.ts
│       ├── rate-limit.ts
│       └── error.ts
├── package.json
├── tsconfig.json
├── .env.example
└── README.md
```

### The Key New Class: SealExecutor

This replaces `LiveExecutorV2`'s direct wallet signing with Seal session key execution:

```typescript
class SealExecutor implements ITradingExecutor {
  // Instead of wallet.signTransaction()
  // Uses ExecuteViaSession instruction → CPI to Meteora DLMM
  
  async openPosition(poolAddress, strategy, amountX, amountY) {
    // 1. Build Meteora DLMM instruction (addLiquidity)
    // 2. Wrap in ExecuteViaSession (CPI)
    // 3. Sign with session keypair (backend holds this ephemeral key)
    // 4. Send transaction
    // 5. Track position in DB
  }
}
```

---

## 16. Open Questions

| Question | Impact | Notes |
|----------|--------|-------|
| Does Meteora DLMM support CPI from Seal's ExecuteViaSession? | Blocking if not | Need to test. If CPI depth is too deep, may need direct signing with delegated authority. |
| Supabase free tier row limits for trade_log? | Scaling | 50K rows should last months for a few users |
| Can we ship Sage AI without a hosted ML model? | Scope | For MONOLITH, we can embed the model weights in the backend (XGBoost exports to JSON) |
| Should strategy presets be on-chain? | Decentralization | No — too expensive, no benefit for MVP |
| How do we handle the user closing the app while bot runs? | UX | Bot continues server-side. App reconnects to WebSocket on resume. |

---

## 17. MONOLITH Hackathon Scope (What We Actually Ship)

Given 11 days until deadline, here's the realistic MVP:

### Must Have (Demo-Ready)

- [ ] SIWS authentication (wallet connect → JWT)
- [ ] Bot creation with preset strategies (FreesolGames, Conservative, Aggressive)
- [ ] Bot start/stop/status via API
- [ ] Simulation mode (demo with real market data, no real trades)
- [ ] Position tracking with real-time PnL on WebSocket
- [ ] Sage AI mode with pre-trained model predictions
- [ ] Home screen showing live bot status + positions
- [ ] Setup flow in app (choose mode → configure → start)

### Nice to Have

- [ ] Live trading via Seal session keys
- [ ] Custom strategy builder (full parameter editing)
- [ ] Trade history with export
- [ ] Helius webhook integration for deposit notifications
- [ ] Multiple bots per user

### Not for MONOLITH

- Online ML retraining
- Social features / leaderboards
- iOS support
- Mainnet deployment
- Revenue model (fees)
