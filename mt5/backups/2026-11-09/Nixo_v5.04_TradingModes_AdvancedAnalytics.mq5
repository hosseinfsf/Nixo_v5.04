//+------------------------------------------------------------------+
//|                                                        Nixo.mq5  |
//|                        Professional Auto Trading Expert Advisor  |
//|                     Copyright 2026, Hossein FSF                  |
//|                                   Email: hosseinfsf@gmail.com    |
//+------------------------------------------------------------------+
#property copyright "Nixo | Hossein FSF | hosseinfsf@gmail.com"
#property link      "mailto:hosseinfsf@gmail.com"
#property version   "5.04"
#property description "Nixo v5.04 – Trading Modes, persistent per-position management and advanced analytics"
#property description "Manual / External / Strategy routing, non-destructive mode switching, shared risk gate and report export"
#property description "Author: Hossein FSF  |  Email: hosseinfsf@gmail.com"

#include <Trade/Trade.mqh>
CTrade trade;

//==================================================================
//  ENUMS
//==================================================================
enum ENUM_NIXO_TRADING_MODE
{
   NIXO_MODE_MANUAL   = 0, // Manual entries only
   NIXO_MODE_EXTERNAL = 1, // External normalized signal sources only
   NIXO_MODE_STRATEGY = 2  // Internal Nixo strategies only
};

enum ENUM_STRATEGY
{
   STRAT_RTM_LFT      = 0,  // 1. RTM + LFT (preserved)
   STRAT_DREAMS       = 1,  // 2. Dreams Liquidity Sweep (preserved)
   STRAT_SAFE_BREAK   = 2,  // 3. Six-filter breakout scalper
   STRAT_EMA_ADX_MTF  = 3,  // 4. EMA + RSI + ADX + HTF scalp
   STRAT_VWAP_RETEST  = 4,  // 5. VWAP retest + EMA9 + candle confirmation
   STRAT_SUPERTREND = 5,  // 6. Supertrend trend/retest scalper
   STRAT_ATR_MOMENTUM = 6,  // 7. ATR momentum continuation scalper
   STRAT_RTM_SCALP    = 7,  // 8. RTM Scalp (fast Quasimodo zone, M1-M5)
   STRAT_LIQ_SCALP    = 8,  // 9. Liquidity Scalp (micro stop-run reversal)
   STRAT_MICRO_PB     = 9,  // 10. Micro Pullback super-scalp (EMA9/21/50)
   STRAT_SQUEEZE      = 10, // 11. Squeeze Breakout super-scalp
   STRAT_DIP_RSI3     = 11, // 12. RSI-3 Dip super-scalp
   STRAT_EMA_PULLBACK    = 12, // 13. EMA trend pullback scalper
   STRAT_ENSEMBLE     = 13, // 14. Ensemble (all models vote)
   STRAT_TICK_TURBO   = 14, // 15. Tick-by-tick micro momentum Turbo
   STRAT_ULTRA_HFT    = 15, // 16. Tick-level five-engine confluence scalper (UltraHFT-inspired)
   STRAT_NYAO_STRADDLE= 16, // 17. OCO stop-straddle breakout scalper (Nyao-inspired)
   STRAT_ULTRA_NYAO_HYBRID = 17, // 18. UltraHFT tick entries + Nyao OCO straddle
   STRAT_TG_PUBLIC    = 18, // 19. Public Telegram channel bridge mode
   STRAT_COPY_SITE    = 19  // 20. Copy-trade station bridge mode
};

enum ENUM_ROULETTE
{
   ROULETTE_OFF      = 0,
   ROULETTE_ON       = 1,
   ROULETTE_STOPPED  = 2
};

enum ENUM_SIGNAL_MODEL
{
   SIGNAL_MODEL_A_BASE = 0,       // one order, base size
   SIGNAL_MODEL_B_ORDER = 1,      // Order Roulette only
   SIGNAL_MODEL_C_VOLUME = 2,     // Volume Roulette only
   SIGNAL_MODEL_D_COMBINED = 3    // both roulettes
};

enum ENUM_SIGNAL_SIZE_MODE
{
   SIGNAL_SIZE_FIXED_LOT = 0,
   SIGNAL_SIZE_RISK_PERCENT = 1,
   SIGNAL_SIZE_FIXED_CASH = 2
};

enum ENUM_NIXO_SIZE_MODE
{
   NIXO_SIZE_RISK_PERCENT = 0, // Size so SL loss equals selected % of equity/balance
   NIXO_SIZE_FIXED_MONEY  = 1, // Size so SL loss equals fixed account-currency amount
   NIXO_SIZE_FIXED_LOT    = 2  // Fixed lot; display calculated loss at SL
};

enum ENUM_NIXO_RISK_BASE
{
   NIXO_BASE_BALANCE = 0,
   NIXO_BASE_EQUITY = 1,
   NIXO_BASE_FREE_MARGIN = 2
};

//==================================================================
//  INPUTS
//==================================================================
input group "══════════ NIXO CORE ══════════"
input ENUM_STRATEGY InpStrategy       = STRAT_ULTRA_NYAO_HYBRID; // Active Strategy (Hybrid = UltraHFT market + Nyao OCO)
input ENUM_NIXO_TRADING_MODE InpStartupTradingMode = NIXO_MODE_STRATEGY; // Startup mode when no saved mode exists
input long          InpMagic          = 20261102;        // Magic Number
input bool          InpOneTradeOnly   = false;           // true = max 1 open trade; false = up to InpMaxOpenPositions
input bool          InpOneBatchAtATime = true;           // Prevent repeated same-direction strategy batches while positions remain open
input int           InpMaxTradesDay   = 0;               // RTM/Dreams max trades per day (0=unlimited)
input int           InpScalpMaxTradesDay = 0;             // Scalp models max trades per day (0=unlimited)
input int           InpMaxSpread      = 0;               // Max spread (points; 0=off)
input int           InpSlippage       = 30;              // Slippage

input group "══════════ MULTI-ORDER / TURBO ══════════"
input bool          InpMultiOrderMode  = false;           // Default multi-order state (panel toggle)
input int           InpInitialOrders  = 1;               // Starting orders per signal
input int           InpMaxOrderCount  = 8;               // Max next-batch orders (8 default safety cap)
input bool          InpOrderRoulette  = false;            // Default OFF: each win adds one order; each loss subtracts one (floor 1)
input bool          InpSplitRiskAcrossOrders = true;     // Keep total batch risk near one trade's risk
input bool          InpTurboMode      = false;           // Turbo execution mode (panel toggle; staged TP remains active)

input group "══════════ RISK LADDER (ROULETTE) ══════════"
input double        InpBaseRisk       = 0.25;            // Base Risk % (Step 1) – lower risk for many tight-stop trades
input int           InpMaxStep        = 50;              // Max Risk Step
input double        InpMaxRiskPct     = 0.50;            // Maximum risk % per trade after risk roulette
input double        InpRouletteTrigger= 4.00;            // Activate risk roulette after +4% cumulative equity gain (0 = always on)
input double        InpHardStopPct    = 5.0;             // Stop all trading at -5% from start
input bool          InpRiskRouletteEnabled = true;      // Arm risk roulette by default; it activates after the equity trigger
input ENUM_NIXO_RISK_BASE InpRiskBaseMode = NIXO_BASE_EQUITY; // Balance / Equity / Free Margin
input double        InpMaxLotGold     = 0.00;            // Max lot (Gold; 0=broker max)
input double        InpMaxLotOther    = 0.00;            // Max lot (other symbols; 0=broker max)
input ENUM_NIXO_SIZE_MODE InpPositionSizeMode = NIXO_SIZE_RISK_PERCENT; // Percent risk / fixed money / fixed lot
input double        InpFixedRiskMoney = 25.0;           // Fixed loss budget at SL, in account currency
input double        InpFixedLot       = 0.20;           // Optional fixed volume per entry/order; roulette requires % or cash risk

input group "══════════ THREE-STAGE R TP + RUNNER ══════════"
input bool          InpUseMultiTP          = false;      // Manage TP1/TP2/TP3 partial exits and runner
input double        InpTPAnchorR           = 3.00;       // TP3 distance in R; panel can adjust this value
input double        InpTP1_R               = 1.00;       // TP1 trigger at 1R; close 50% of initial volume
input double        InpTP2_R               = 2.00;       // TP2 trigger at 2R; close 50% of remaining volume
input double        InpRunnerTrailATR      = 1.20;       // After TP3, trail the 12.5% runner by ATR; stop never loosens
input double        InpCommissionPerLotRT  = 14.6;       // Round-turn commission/lot in account currency; adjust to broker
input int           InpRiskSlippagePoints = 10;         // Extra adverse points included in risk sizing

input group "══════════ DAILY PROFIT PROTECTION ══════════"
input bool          InpUseDailyProtection = true;        // Daily equity guard
input double        InpDailyMaxLossPct    = 1.00;       // Stop for day at this loss from day-start equity (0=off)
input double        InpDailyProfitArmPct  = 0.50;       // Arm profit lock after this daily peak gain (0=off)
input double        InpDailyGivebackPct   = 40.0;       // After +0.50% peak, allow 40% retrace; retain 60% of peak gain

input group "══════════ STOP LOSS / TAKE PROFIT ══════════"
input int           InpATR_Period     = 14;              // ATR Period
input double        InpATR_Mult       = 2.5;             // SL = ATR × Mult
input int           InpMinSL_Points   = 300;             // Minimum SL distance (points) ★
input double        InpTP_RR          = 2.0;             // Default Take Profit Risk:Reward (1:2)
input bool          InpUseBE          = false;           // Break-even enabled
input double        InpBE_R           = 1.0;             // Break-even trigger (× risk)
input bool          InpAutoProfile    = false;           // Apply strategy-specific SL/RR profile when switching strategy

input group "══════════ SCALP MODELS ══════════"
input int           InpEMA_Fast       = 50;              // Core fast trend EMA
input int           InpEMA_Slow       = 200;             // Core slow trend EMA
input int           InpRSI_Period     = 14;
input double        InpRSI_BuyMin     = 52.0;            // Safe Breakout: healthy bullish RSI range
input double        InpRSI_BuyMax     = 72.0;
input double        InpRSI_SellMin    = 28.0;            // Safe Breakout: healthy bearish RSI range
input double        InpRSI_SellMax    = 48.0;
input int           InpSafeBreakoutBars = 10;            // Previous bars for breakout level
input double        InpSafeADXMin    = 18.0;             // Breakout trend strength
input double        InpSafeBufferATR = 0.08;             // Breakout buffer in ATR
input ENUM_TIMEFRAMES InpScalpHigherTF = PERIOD_H1;      // Higher-timeframe confirmation
input int           InpMTF_FastEMA  = 20;
input int           InpMTF_SlowEMA  = 50;
input double        InpMTF_ADXMin   = 18.0;
input int           InpSweepBars    = 20;                // Dreams liquidity sweep lookback
input bool          InpTrendFilter  = true;             // Dreams: trade only with EMA200 trend
input int           InpADX_Period   = 14;
input int           InpVWAPRetestBars = 4;
input double        InpVWAPBufferATR = 0.20;
input int           InpVWAPSessionStartH = 0;            // Broker time
input int           InpVWAPSessionEndH   = 0;           // Broker time
input double        InpMomentumMinBodyATR = 0.25;
input double        InpMomentumADXMin = 20.0;
input int           InpMomentumBreakoutBars = 3;
input double        InpMomentumMinMoveATR = 0.10;
input double        InpMaxSignalCandleATR = 1.80;
input int           InpSupertrendATRPeriod = 10;           // Supertrend ATR period
input double        InpSupertrendMultiplier = 2.40;         // Supertrend ATR multiplier
input int           InpSupertrendLookback   = 120;          // Supertrend calculation history
input double        InpPullbackTouchATR     = 0.22;         // EMA pullback tolerance in ATR
input double        InpPullbackADXMin       = 16.0;         // EMA pullback minimum ADX
input int           InpPullbackSlopeBars    = 5;            // Slow EMA slope lookback
input double        InpTickTurboMoveATR     = 0.08;         // Tick Turbo minimum move in ATR
input int           InpTickTurboCooldownSec = 0;          // Minimum seconds between Tick Turbo entries (0=unlimited)
input int           InpMaxTradesPerMinute = 6;            // Entry-rate cap per minute (0=unlimited)

input group "══════════ HIGH-FREQUENCY ENGINES ══════════"
input int           InpUltraMinScore = 4;                  // UltraHFT: minimum directional confluence score (2..9)
input double        InpUltraBandTouchATR = 0.10;           // Bollinger proximity tolerance (ATR)
input double        InpNyaoEntryDistanceATR = 0.12;        // Straddle stop distance from live Ask/Bid in ATR
input double        InpNyaoMinVolatilityRatio = 0.0;       // Optional ATR/current-vs-average filter (0=off)
input int           InpNyaoATRBaseBars = 100;              // ATR baseline bars for optional volatility filter
input int           InpNyaoPendingExpiryMinutes = 5;     // Cancel/re-arm stale NYAO pending orders after N minutes

input group "══════════ TIGHT-STOP SCALPING CONTROLS (v3.7) ══════════"
input int           InpScalpMinSL_Points = 100;          // Min SL for scalp models (points; gold 100 = $1.00 — lower it on FX M1)
input double        InpMaxSpreadPctOfSL  = 0.0;          // Skip entry if (spread+commission) > this % of the stop (0=off)
input int           InpMaxOpenPositions  = 5;            // Max simultaneous Nixo positions (0=unlimited by EA)
input double        InpMaxOpenRiskPct    = 1.5;          // Total open risk cap across all orders, % equity (0=off)
input bool          InpAllowHedge        = false;        // Allow simultaneous BUY and SELL positions (hedging accounts)
input int           InpTimeStopBars      = 0;            // Close a trade that has not reached TimeStopMinR after N bars (0=off)
input double        InpTimeStopMinR      = 0.25;         // ...minimum favourable move in R
input int           InpMaxConsecLosses   = 0;            // Pause after N consecutive full losses (0=off)
input int           InpCooldownMinutes   = 0;            // ...for this many minutes (0=off)
input bool          InpAutoResumeNextDay = true;         // Resume automatically after a daily-guard stop

input group "══════════ RTM / LIQUIDITY / SCALP MODELS ══════════"
input double        InpRTMScalpTolATR    = 0.30;         // RTM Scalp: zone tolerance in ATR
input int           InpRTMScalpMaxAge    = 14;           // RTM Scalp: max bars since the structure break
input int           InpLiqBars           = 8;            // Liquidity Scalp: sweep lookback bars
input double        InpLiqWickATR        = 0.35;         // Liquidity Scalp: minimum rejection wick (ATR)
input double        InpMicroADXMin       = 15.0;         // Micro Pullback: minimum ADX
input double        InpSqueezeBoxATR     = 0.90;         // Squeeze: max 3-bar box height (ATR)
input double        InpDipRSI            = 25.0;         // RSI-3 Dip: oversold level (overbought = 100-x)
input int           InpEnsembleMinVotes  = 1;            // Ensemble: minimum agreeing models

input group "══════════ SESSION ══════════"
input int           InpSessionStartH  = 7;               // Session start hour (broker)
input int           InpSessionEndH    = 20;              // Session end hour
input bool          InpUseSession     = false;           // Force session filter
input int           InpAsiaStartH     = 0;               // Session display only: broker-time Asia start
input int           InpAsiaEndH       = 8;               // Session display only: broker-time Asia end
input int           InpLondonStartH   = 8;               // Session display only: broker-time London start
input int           InpLondonEndH     = 17;              // Session display only: broker-time London end
input int           InpNewYorkStartH  = 13;              // Session display only: broker-time New York start
input int           InpNewYorkEndH    = 22;              // Session display only: broker-time New York end

input group "══════════ AI ADVISORY BRIDGE (SEPARATE FROM SIGNAL COPY) ══════════"
input bool          InpAIAdvisoryEnabled = true;       // Publish market snapshots to the optional external AI bridge
input int           InpAIRefreshSeconds  = 30;         // Minimum interval between AI market snapshots
input int           InpAIMaxStatusAgeSec  = 120;        // Mark AI offline if its heartbeat is older than this

input group "══════════ TELEGRAM / COPIER BRIDGE ══════════"
input bool          InpPublicTelegramBridge = true;            // Accept public-channel text events from a local bridge script
input string        InpTelegramBridgeFolder = "NixoBridge\\inbox\\"; // Folder used by the Telegram bridge
input string        InpTelegramSourceName = "TG_PUBLIC";          // Channel/source label shown in logs
input string        InpCopySiteStrategyA = "TREND_BREAKOUT";     // Example copy-site model A
input string        InpCopySiteStrategyB = "ATR_PULLBACK";      // Example copy-site model B
input string        InpCopyTraderFeedLabel = "COPIER_FEED";     // Feed label for generic copier service
input int           InpBridgeMaxAgeSeconds = 180;                // Ignore stale bridge messages older than this

input group "══════════ SIGNAL COPY / SIGNAL LAB ══════════"
input bool          InpSignalLabEnabled          = true;       // Consume bridge events and run four virtual models
input string        InpSignalInboxFolder         = "NixoBridge\\inbox\\"; // MT5 Common\\Files subfolder
input string        InpSignalReportFolder        = "NixoBridge\\reports\\";
input long          InpSignalMagic               = 20261999;   // Separate magic for optional signal copying
input bool          InpSignalLiveAllowed         = false;      // Safety gate: must be enabled in Inputs before panel can copy live
input ENUM_SIGNAL_MODEL InpSignalLiveModel       = SIGNAL_MODEL_D_COMBINED; // Combined Order + Volume Roulette for live copying
input bool          InpSignalAllowHedge          = false;      // Allow opposite signal positions in a Hedging account
input ENUM_SIGNAL_SIZE_MODE InpSignalSizeMode    = SIGNAL_SIZE_FIXED_LOT;
input double        InpSignalBaseLot             = 0.01;       // Base lot for fixed-lot mode and paper comparison
input double        InpSignalBaseRiskPct         = 0.10;       // Base order risk % before roulette multipliers
input double        InpSignalBaseRiskCash        = 10.0;       // Base order cash risk before roulette multipliers
input double        InpSignalCommissionRTPerLot  = 14.60;      // Round-turn commission estimate per lot
input bool          InpSignalSplitRiskAcrossOrders = false;    // YES keeps basket exposure steady; NO multiplies exposure with order count
input int           InpSignalInitialOrderCount   = 1;         // Initial Order Roulette count per source
input int           InpSignalMaxOrderCount        = 8;         // Signal Lab/live order count cap
input int           InpSignalMaxVolumeStep        = 5;         // Volume Roulette multiplier cap
input double        InpSignalVolumeStepFactor     = 1.0;       // Each Volume Roulette step multiplies base size by this factor
input int           InpSignalMaxLivePositions     = 8;         // Live signal position cap
input double        InpSignalMaxLiveRiskPct       = 0.50;      // Aggregate live signal risk cap (% equity; 0=off)
input int           InpSignalPendingExpiryMinutes = 5;         // Cancel stale signal pending orders after N minutes
input int           InpSignalMaxAgeSeconds        = 120;       // Ignore new scalp signals older than N seconds (0=off)
input int           InpSignalPaperSlippagePoints  = 10;        // Conservative virtual execution slippage
input double        InpSignalTP1ClosePct          = 50.0;      // Close % of CURRENT remaining basket at TP1
input double        InpSignalTP2ClosePct          = 50.0;      // Close % of CURRENT remaining basket at TP2
input double        InpSignalTP3ClosePct          = 50.0;      // Close % of CURRENT remaining basket at TP3; 12.5% remains when all are 50%
input bool          InpSignalRunnerEnabled        = true;      // Keep the final 12.5% runner when broker volume steps allow it
input double        InpSignalRunnerTrailATR       = 1.20;      // Signal-copy runner ATR trailing multiplier

input group "══════════ PANEL ══════════"
input int           InpPanelX         = 15;
input int           InpPanelY         = 25;
input string        InpFont           = "Segoe UI";      // Panel font
input int           InpPanelScale     = 100;             // Panel size % (60-220)
input bool          InpStartCompact   = true;           // Start with a compact panel; advanced settings hidden
input bool          InpDebug          = true;            // Print debug info

//==================================================================
//  GLOBALS
//==================================================================
double   g_StartEquity   = 0;
double   g_CycleStartEq  = 0;
datetime g_DayStamp     = 0;
double   g_DayStartEquity= 0;
double   g_DayPeakEquity = 0;
bool     g_DailyStopped  = false;
string   g_DailyStopReason = "";
double   g_CommissionCache = 0.0;
datetime g_CommissionCacheTime = 0;
int      g_Step          = 1;
ENUM_ROULETTE g_Roulette = ROULETTE_OFF;
bool     g_Running       = false;
ENUM_NIXO_TRADING_MODE g_TradingMode = NIXO_MODE_STRATEGY;
bool     g_EntriesPaused = false; // independent master lock for all NEW entries
bool     g_Stopped       = false;
int      g_TradesToday   = 0;
datetime g_LastDay       = 0;
datetime g_LastBarTime   = 0;
int      g_OrderCount    = 1;
datetime g_LastTurboOpen = 0;
datetime g_StatsFrom     = 0;
int      g_ConsecLosses  = 0;
datetime g_CooldownUntil = 0;
bool     g_ResumeAfterDaily = false;
bool     g_RiskRouletteEnabled = false;
bool     g_OrderRouletteEnabled = false;
bool     g_MultiOrderEnabled = false;
bool     g_TurboEnabled = false;
bool     g_PortfolioMode = false;
bool     g_HedgeEnabled = false;
bool     g_ManualMode = false;
bool     g_SignalLiveEnabled = false;
bool     g_ManualDeskOpen = false;
int      g_ManualDeskX = -1;
int      g_ManualDeskY = -1;
ENUM_NIXO_SIZE_MODE g_ManualSizeMode = NIXO_SIZE_RISK_PERCENT;
double   g_ManualSizeValue = 0.25;
double   g_ManualSLATR = 2.5;
double   g_ManualTP3R = 3.0;
string   g_AIState = "OFFLINE";
string   g_AIBias = "WAIT";
string   g_AIRisk = "—";
string   g_AISummary = "AI bridge not started";
datetime g_LastAIRequest = 0;
long     g_TelegramOffset = 0;
datetime g_LastTelegramRefresh = 0;

// TradingView-style manual Risk:Reward planner (chart objects)
bool     g_RRPlaceArmed = false;
bool     g_RRActive = false;
int      g_RRDirection = 1;          // +1 LONG, -1 SHORT
bool     g_RRUpdating = false;
double   g_RREntry = 0.0;
double   g_RRSL = 0.0;
double   g_RRTP = 0.0;
double   g_RRLastEntry = 0.0;
double   g_RRLastSL = 0.0;
double   g_RRLastTP = 0.0;
datetime g_RRAnchorTime = 0;

double   g_ManualPrice = 0.0;
int      g_PendingArmType = 0; // +1 Buy Limit, -1 Sell Limit, 0 disarmed
double   g_NetProfit = 0.0;
double   g_TickPrices[8];
int      g_TickPriceCount = 0;
int      g_TickPriceHead = 0;
datetime g_LastTurboEntry = 0;
long     g_ActiveBatchId = 0;
int      g_ActiveBatchOrders = 0; // actual executable orders for current batch after broker-volume feasibility check
ulong    g_EntryTimesMs[2048];
int      g_EntryTimesHead = 0;
int      g_EntryTimesCount = 0;
double   g_MaxSpreadPct  = 0.0;
double   g_S             = 1.0;

// Forward declarations for cross-referenced trade-management helpers.
void   ProcessOrderRoulette(double profit);
void   ProcessRiskRoulette(double profit, double riskMoney);
void   ProcessClosedTrade(double profit, double closedRiskMoney);
bool   GetFullyClosedPositionNet(ulong positionId, double &netProfit);
void   ClearMultiTPState(ulong positionId);
void   CancelNyaoPendingOrders();
bool   MultiTPPlanValid(double lot);
bool   TradeRequestSucceeded(bool sent);
double ActualRiskMoney(ENUM_ORDER_TYPE type, double lot, double price, double sl);
double EstimateRoundTurnCommissionPerLot();
int    MaxOpenAllowed();
bool   HasOppositePosition(ENUM_ORDER_TYPE type);
bool   HasSameDirectionPosition(ENUM_ORDER_TYPE type);
bool   DailyTradeLimitReached();
double CalcLot(ENUM_ORDER_TYPE type, double riskPct, double slDist, double price, double cashRiskOverride=-1.0, int sizingModeOverride=-1, double fixedLotOverride=-1.0);
double ComputeSLDist();
double GetCurrentRiskPct();
bool ReadPositionRealizedNet(ulong positionId, double &realizedNet);
bool ShouldLogSLWait(ulong ticket);
void ExpireStaleNyaoPendingOrders();
void ProcessSignalInbox();
void SetTradingMode(ENUM_NIXO_TRADING_MODE mode);
bool TradingModeAllowsEntry(string reason);
string TradingModeName(ENUM_NIXO_TRADING_MODE mode);
double OpenRiskMoney();
void ReportSnapshotPendingOrder(ulong orderTicket,int mode,int strategyId,double plannedRR);
void ReportCaptureEntryDeal(ulong deal,ulong orderTicket);
void ReportRegisterSource(long sourceHash,string sourceId);
bool ExportAdvancedReport();
string ReportMetaKey(ulong positionId,string field);
void UpdateSignalPaperTrades();
void ManageSignalLivePositions();
void FinalizeSignalLiveBatches();
void   CancelSignalPendingOrders();
void   UpdateRRToolbar();
void   ClearRRDrawing();
void   DeleteRRToolbar();
void   CreateRRPlan(datetime anchorTime,double entryPrice);
bool   HandleRRObjectDrag(const string objectName);
bool   RegisterRRPlan();

// Runtime-editable settings (changed from the panel, persisted)
int      g_Strategy      = 2;
double   g_BaseRisk      = 0.25;
double   g_ATRMult       = 2.5;
double   g_TPRR          = 1.6;
double   g_TP1R          = 1.0;
double   g_TP2R          = 2.0;
double   g_TPAnchorR     = 3.0;
double   g_RunnerTrailATR = 1.2;
int      g_ExitProfile   = 0;
double   g_MaxLot        = 0.0;
int      g_MaxStep       = 50;
int      g_MaxTradesDay  = 0;
int      g_ScalpMaxTradesDay = 0;
bool     g_UseBE         = false;

// Last trade info + stats
double   g_LastLot       = 0;
double   g_LastRiskMoney = 0;
double   g_LastRiskPct   = 0;
double   g_LastQMZone    = 0;
int      g_Trades        = 0;
int      g_Wins          = 0;
double   g_GrossP        = 0;
double   g_GrossL        = 0;

struct CommissionAgg
{
   ulong  id;
   double inVol;
   double outVol;
   double costs;
};

// Indicator handles (created once)
int h_ATR   = INVALID_HANDLE;
int h_STATR = INVALID_HANDLE;
int h_EMA21 = INVALID_HANDLE;
int h_EMAF  = INVALID_HANDLE;
int h_EMAS  = INVALID_HANDLE;
int h_RSI   = INVALID_HANDLE;
int h_ADX   = INVALID_HANDLE;
int h_EMA9  = INVALID_HANDLE;
int h_HTFFast = INVALID_HANDLE;
int h_HTFSlow = INVALID_HANDLE;
int h_RSI3  = INVALID_HANDLE;
int h_EMA3  = INVALID_HANDLE;
int h_EMA8  = INVALID_HANDLE;
int h_MACD  = INVALID_HANDLE;
int h_BANDS = INVALID_HANDLE;
int h_STOCH = INVALID_HANDLE;

//==================================================================
//  PANEL GLOBALS
//==================================================================
struct HitRect { int x1; int y1; int x2; int y2; int act; };

const string UI_OBJ = "NIXO_UI";
const string UI_RES = "::NIXO_UI_IMG";
const string MANUAL_PRICE_OBJ = "NIXO_MANUAL_PRICE";
const string MANUAL_LINE_OBJ = "NIXO_MANUAL_ENTRY_LINE";
const string MD_BG = "NIXO_MD_BG";
const string MD_PREFIX = "NIXO_MD_";
const string MD_ENTRY = "NIXO_MD_ENTRY";
const string MD_SIZE_VALUE = "NIXO_MD_SIZE_VALUE";
const string MD_SL_ATR = "NIXO_MD_SL_ATR";
const string MD_TP3_R = "NIXO_MD_TP3_R";
const string RR_PREFIX       = "NIXO_RR_";
const string RR_BAR          = "NIXO_RR_BAR";
const string RR_TITLE        = "NIXO_RR_TITLE";
const string RR_STATUS       = "NIXO_RR_STATUS";
const string RR_STATUS2      = "NIXO_RR_STATUS2";
const string RR_LONG_BUTTON  = "NIXO_RR_LONG";
const string RR_SHORT_BUTTON = "NIXO_RR_SHORT";
const string RR_REGISTER_BTN = "NIXO_RR_REGISTER";
const string RR_CANCEL_BTN   = "NIXO_RR_CANCEL";
const string RR_ENTRY_LINE   = "NIXO_RR_ENTRY_LINE";
const string RR_SL_LINE      = "NIXO_RR_SL_LINE";
const string RR_TP_LINE      = "NIXO_RR_TP_LINE";
const string RR_RISK_ZONE    = "NIXO_RR_RISK_ZONE";
const string RR_REWARD_ZONE  = "NIXO_RR_REWARD_ZONE";
const string RR_ENTRY_TEXT   = "NIXO_RR_ENTRY_TEXT";
const string RR_SL_TEXT      = "NIXO_RR_SL_TEXT";
const string RR_TP_TEXT      = "NIXO_RR_TP_TEXT";
int g_ManualEditX=22, g_ManualEditY=0, g_ManualEditW=122, g_ManualEditH=22;
const int    UI_W   = 520;

uint     g_px[];
int      g_W = UI_W, g_H = 600, g_LogicalH = 600;
HitRect  g_Hits[];
int      g_HitN        = 0;
bool     g_ShowSettings= true;
int      g_SettingsTab=1;
string   g_LastSig     = "";
int      g_MouseX = 0, g_MouseY = 0;
ulong    g_LastClickMs = 0;
ulong    g_CloseAllConfirmUntilMs = 0;

// Actions
#define ACT_STARTSTOP  1
#define ACT_RESET      2
#define ACT_BUY        3
#define ACT_SELL       4
#define ACT_TOGGLESET  5
#define ACT_RISK_ROULETTE 6
#define ACT_ORDER_ROULETTE 7
#define ACT_MULTI_ORDER 8
#define ACT_TURBO 9
#define ACT_PORTFOLIO 10
#define ACT_STRATEGY_PREV 11
#define ACT_STRATEGY_NEXT 12
#define ACT_HEDGE 13
#define ACT_MANUAL_MODE 14
#define ACT_BUY_LIMIT 15
#define ACT_SELL_LIMIT 16
#define ACT_CLOSE_ALL  17
#define ACT_ORDER_MINUS 18
#define ACT_ORDER_PLUS  19
#define ACT_SIGNAL_LIVE 20
#define ACT_MANUAL_DESK 21
#define ACT_SETTINGS_RISK 22
#define ACT_SETTINGS_EXITS 23
#define ACT_MODE_MANUAL   24
#define ACT_MODE_EXTERNAL 25
#define ACT_MODE_STRATEGY 26
#define ACT_REPORT_EXPORT 27
#define ACT_EXIT_PROFILE_BASE 30
#define ACT_SET_BASE   100   // +row*2 (minus) / +row*2+1 (plus)

// Session label is an approximate display based on broker server time.
// Adjust the six session-hour inputs above if the broker uses another server offset.
bool HourInWindow(int hour, int startHour, int endHour)
{
   if(startHour < 0) startHour = 0;
   if(startHour > 23) startHour = 23;
   if(endHour < 0) endHour = 0;
   if(endHour > 24) endHour = 24;
   if(startHour == endHour) return false;
   if(startHour < endHour) return (hour >= startHour && hour < endHour);
   return (hour >= startHour || hour < endHour);
}

string CurrentSessionLabel()
{
   MqlDateTime tm; TimeToStruct(TimeCurrent(), tm);
   bool asia = HourInWindow(tm.hour, InpAsiaStartH, InpAsiaEndH);
   bool lon  = HourInWindow(tm.hour, InpLondonStartH, InpLondonEndH);
   bool ny   = HourInWindow(tm.hour, InpNewYorkStartH, InpNewYorkEndH);
   if(lon && ny) return "LONDON/NY";
   if(asia && lon) return "ASIA/LONDON";
   if(asia && ny) return "ASIA/NY";
   if(lon) return "LONDON";
   if(ny) return "NEW YORK";
   if(asia) return "ASIA";
   return "OFF SESSION";
}

//==================================================================
//  STRATEGY NAMES / PROFILES
//==================================================================
string StratShort(int s)
{
   switch(s)
   {
      case 0:  return "RTM+LFT";
      case 1:  return "DREAMS";
      case 2:  return "SAFE BRK";
      case 3:  return "EMA-ADX";
      case 4:  return "VWAP RT";
      case 5:  return "SUPERTREND";
      case 6:  return "ATR MOM";
      case 7:  return "RTM SCALP";
      case 8:  return "LIQ SCALP";
      case 9:  return "MICRO PB";
      case 10: return "SQUEEZE";
      case 11: return "DIP RSI3";
      case 12: return "EMA PULLBACK";
      case 13: return "ENSEMBLE";
      case 14: return "TICK TURBO";
      case 15: return "ULTRA HFT";
      case 16: return "NYAO STRAD";
      case 17: return "ULTRA+NYAO";
      case 18: return "TG PUBLIC";
      case 19: return "COPIER FEED";
   }
   return "?";
}

// Starting-point SL/RR per strategy (validate in Strategy Tester!)
void ApplyProfile(int s)
{
   switch(s)
   {
      case 0:  g_ATRMult = 2.0;  g_TPRR = 2.0; break;   // RTM classic
      case 1:  g_ATRMult = 2.0;  g_TPRR = 1.5; break;   // Dreams classic
      case 2:  g_ATRMult = 1.6;  g_TPRR = 1.6; break;
      case 3:  g_ATRMult = 1.5;  g_TPRR = 1.4; break;
      case 4:  g_ATRMult = 1.4;  g_TPRR = 1.3; break;
      case 5:  g_ATRMult = 1.4;  g_TPRR = 1.7; break;
      case 6:  g_ATRMult = 1.4;  g_TPRR = 1.5; break;
      case 7:  g_ATRMult = 1.3;  g_TPRR = 1.5; break;   // RTM scalp: tight structure stop
      case 8:  g_ATRMult = 1.2;  g_TPRR = 1.4; break;   // liquidity scalp
      case 9:  g_ATRMult = 1.0;  g_TPRR = 1.2; break;   // micro pullback
      case 10: g_ATRMult = 1.1;  g_TPRR = 1.5; break;   // squeeze breakout
      case 11: g_ATRMult = 1.2;  g_TPRR = 0.9; break;   // dip scalp: higher win rate, small target
      case 12: g_ATRMult = 1.25; g_TPRR = 1.6; break;   // EMA pullback scalper
      case 13: g_ATRMult = 1.2;  g_TPRR = 1.3; break;   // ensemble
      case 14: g_ATRMult = 0.9;  g_TPRR = 3.0; break;   // tick turbo tight stop
      case 15: g_ATRMult = 0.85; g_TPRR = 3.0; break;   // UltraHFT tick-confluence
      case 16: g_ATRMult = 1.00; g_TPRR = 3.0; break;   // Nyao-style stop straddle
      case 17: g_ATRMult = 0.90; g_TPRR = 3.0; break;   // UltraHFT market entries + Nyao OCO pending entries
      case 18: g_ATRMult = 1.15; g_TPRR = 2.0; break;   // public Telegram feed bridge: moderate risk, patient exits
      case 19: g_ATRMult = 1.10; g_TPRR = 1.8; break;   // copy-trade provider bridge: conservative but responsive
   }
}

bool IsGoldSymbol()
{
   return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0);
}

void InitSettingsFromInputs()
{
   g_Strategy     = (int)InpStrategy;
   g_ExitProfile  = -1;
   g_BaseRisk     = InpBaseRisk;
   g_ATRMult      = InpATR_Mult;
   g_TPRR         = InpTP_RR;
   g_TP1R         = InpTP1_R;
   g_TP2R         = InpTP2_R;
   g_TPAnchorR    = InpTPAnchorR;
   g_RunnerTrailATR = InpRunnerTrailATR;
   g_MaxLot       = IsGoldSymbol() ? InpMaxLotGold : InpMaxLotOther;
   g_MaxStep      = InpMaxStep;
   g_MaxTradesDay = InpMaxTradesDay;
   g_ScalpMaxTradesDay = InpScalpMaxTradesDay;
   g_UseBE        = InpUseBE;
   g_MaxSpreadPct = InpMaxSpreadPctOfSL;
   g_MultiOrderEnabled = InpMultiOrderMode;
   g_OrderRouletteEnabled = InpOrderRoulette;
   g_TurboEnabled = InpTurboMode;
   g_RiskRouletteEnabled = InpRiskRouletteEnabled;
   g_PortfolioMode = false;
   g_HedgeEnabled = InpAllowHedge;
   g_TradingMode = InpStartupTradingMode;
   g_EntriesPaused = false;
   g_ManualMode = (g_TradingMode==NIXO_MODE_MANUAL);
   if(InpAutoProfile) ApplyProfile(g_Strategy); // apply the selected strategy's SL/RR defaults on a fresh install
   g_ManualSizeMode = InpPositionSizeMode;
   if(g_ManualSizeMode==NIXO_SIZE_FIXED_MONEY) g_ManualSizeValue=InpFixedRiskMoney;
   else if(g_ManualSizeMode==NIXO_SIZE_FIXED_LOT) g_ManualSizeValue=InpFixedLot;
   else g_ManualSizeValue=InpBaseRisk;
   g_ManualSLATR = g_ATRMult;
   g_ManualTP3R = g_TPAnchorR;
}

//==================================================================
//  STATE PERSISTENCE
//==================================================================
string GVKey(string n)
{
   return StringFormat("NIXO500_%I64d_%I64d_%s", AccountInfoInteger(ACCOUNT_LOGIN), InpMagic, n);
}

int OrderCountCap()
{
   // 0 means no user-imposed cap. INT_MAX is only the MQL5 integer boundary.
   return (InpMaxOrderCount > 0 ? InpMaxOrderCount : 2147483647);
}

long NextBatchId()
{
   string k = GVKey("BSEQ");
   long id = GlobalVariableCheck(k) ? (long)GlobalVariableGet(k) : 0;
   id++;
   if(id <= 0 || id > 9007199254740000) id = 1; // exact integer range for a double Global Variable
   GlobalVariableSet(k, (double)id);
   return id;
}

string BatchKey(long batchId, string field)
{
   return GVKey("B" + (string)batchId + "_" + field);
}

bool EntryRateLimitReached()
{
   if(InpMaxTradesPerMinute <= 0) return false;
   ulong now = GetTickCount64();
   int recent = 0;
   for(int i=0; i<g_EntryTimesCount; i++)
   {
      int idx = (g_EntryTimesHead - 1 - i + 2048) % 2048;
      ulong stamp = g_EntryTimesMs[idx];
      if(now >= stamp && now - stamp < 60000) recent++;
   }
   return (recent >= InpMaxTradesPerMinute);
}

void RecordEntryTimestamp()
{
   g_EntryTimesMs[g_EntryTimesHead] = GetTickCount64();
   g_EntryTimesHead = (g_EntryTimesHead + 1) % 2048;
   if(g_EntryTimesCount < 2048) g_EntryTimesCount++;
}

void RegisterBatchPosition(long batchId, ulong positionId)
{
   if(batchId <= 0 || positionId == 0) return;
   GlobalVariableSet(GVKey("BPOS_" + (string)positionId), (double)batchId);
   string nkey = BatchKey(batchId, "N");
   double n = GlobalVariableCheck(nkey) ? GlobalVariableGet(nkey) : 0.0;
   GlobalVariableSet(nkey, n + 1.0);
}

void ProcessBatchRoulette(ulong positionId, double netProfit, double closedRiskMoney)
{
   string posKey = GVKey("BPOS_" + (string)positionId);
   if(!GlobalVariableCheck(posKey))
   {
      // Pending-straddle fills without a registered multi-order batch are a one-position batch.
      ProcessOrderRoulette(netProfit);
      ProcessRiskRoulette(netProfit, closedRiskMoney);
      return;
   }
   long batchId = (long)GlobalVariableGet(posKey);
   GlobalVariableDel(posKey);
   string nkey = BatchKey(batchId, "N");
   string ckey = BatchKey(batchId, "C");
   string pkey = BatchKey(batchId, "P");
   string rkey = BatchKey(batchId, "R");
   double expected = GlobalVariableCheck(nkey) ? GlobalVariableGet(nkey) : 1.0;
   double closed = GlobalVariableCheck(ckey) ? GlobalVariableGet(ckey) : 0.0;
   double total = GlobalVariableCheck(pkey) ? GlobalVariableGet(pkey) : 0.0;
   double totalRisk = GlobalVariableCheck(rkey) ? GlobalVariableGet(rkey) : 0.0;
   closed += 1.0;
   total += netProfit;
   totalRisk += MathMax(0.0, closedRiskMoney);
   GlobalVariableSet(ckey, closed);
   GlobalVariableSet(pkey, total);
   GlobalVariableSet(rkey, totalRisk);
   if(closed + 1e-8 >= expected)
   {
      // Both experiments advance once per completed signal batch, not once per child position.
      ProcessOrderRoulette(total);
      ProcessRiskRoulette(total, totalRisk);
      GlobalVariableDel(nkey);
      GlobalVariableDel(ckey);
      GlobalVariableDel(pkey);
      GlobalVariableDel(rkey);
   }
}

void SaveState()
{
   if(MQLInfoInteger(MQL_TESTER)) return;
   GlobalVariableSet(GVKey("SE"),     g_StartEquity);
   GlobalVariableSet(GVKey("CE"),     g_CycleStartEq);
   GlobalVariableSet(GVKey("STEP"),   (double)g_Step);
   GlobalVariableSet(GVKey("RL"),     (double)g_Roulette);
   GlobalVariableSet(GVKey("STOP"),   g_Stopped ? 1.0 : 0.0);
   GlobalVariableSet(GVKey("SFROM"),  (double)g_StatsFrom);
   GlobalVariableSet(GVKey("S_STRAT"),(double)g_Strategy);
   GlobalVariableSet(GVKey("S_BASE"), g_BaseRisk);
   GlobalVariableSet(GVKey("S_SL"),   g_ATRMult);
   GlobalVariableSet(GVKey("S_RR"),   g_TPRR);
   GlobalVariableSet(GVKey("S_TPA"),  g_TPAnchorR);
   GlobalVariableSet(GVKey("S_TP1"),  g_TP1R);
   GlobalVariableSet(GVKey("S_TP2"),  g_TP2R);
   GlobalVariableSet(GVKey("S_RUNATR"), g_RunnerTrailATR);
   GlobalVariableSet(GVKey("S_EPROF"), (double)g_ExitProfile);
   GlobalVariableSet(GVKey("S_MSTEP"),(double)g_MaxStep);
   GlobalVariableSet(GVKey("S_TPD"),  (double)g_MaxTradesDay);
   GlobalVariableSet(GVKey("S_STPD"), (double)g_ScalpMaxTradesDay);
   GlobalVariableSet(GVKey("S_BE"),   g_UseBE ? 1.0 : 0.0);
   GlobalVariableSet(GVKey("S_MLOT"), g_MaxLot);
   GlobalVariableSet(GVKey("S_SPRPCT"), g_MaxSpreadPct);
   GlobalVariableSet(GVKey("S_ORDERS"), (double)g_OrderCount);
   GlobalVariableSet(GVKey("S_RROUL"), g_RiskRouletteEnabled ? 1.0 : 0.0);
   GlobalVariableSet(GVKey("S_OROUL"), g_OrderRouletteEnabled ? 1.0 : 0.0);
   GlobalVariableSet(GVKey("S_MORD"),  g_MultiOrderEnabled ? 1.0 : 0.0);
   GlobalVariableSet(GVKey("S_TURBO"), g_TurboEnabled ? 1.0 : 0.0);
   GlobalVariableSet(GVKey("S_PORT"),  g_PortfolioMode ? 1.0 : 0.0);
   GlobalVariableSet(GVKey("S_HEDGE"), g_HedgeEnabled ? 1.0 : 0.0);
   GlobalVariableSet(GVKey("DAYSTAMP"), (double)g_DayStamp);
   GlobalVariableSet(GVKey("DAYSTART"), g_DayStartEquity);
   GlobalVariableSet(GVKey("DAYPEAK"),  g_DayPeakEquity);
   GlobalVariableSet(GVKey("DAYSTOP"),  g_DailyStopped ? 1.0 : 0.0);
   GlobalVariableSet(GVKey("TRADING_MODE"),(double)g_TradingMode);
   GlobalVariableSet(GVKey("ENTRIES_PAUSED"),g_EntriesPaused?1.0:0.0);
}

void LoadState()
{
   if(MQLInfoInteger(MQL_TESTER)) return;
   if(!GlobalVariableCheck(GVKey("SE"))) return;

   double se = GlobalVariableGet(GVKey("SE"));
   if(se <= 0) return;

   g_StartEquity  = se;
   g_CycleStartEq = GlobalVariableGet(GVKey("CE"));
   g_Step         = (int)GlobalVariableGet(GVKey("STEP"));
   if(g_Step < 1) g_Step = 1;
   g_Roulette     = (ENUM_ROULETTE)(int)GlobalVariableGet(GVKey("RL"));
   g_Stopped      = (GlobalVariableGet(GVKey("STOP")) > 0.5);
   if(GlobalVariableCheck(GVKey("TRADING_MODE")))
   {
      int savedMode=(int)GlobalVariableGet(GVKey("TRADING_MODE"));
      if(savedMode>=NIXO_MODE_MANUAL && savedMode<=NIXO_MODE_STRATEGY) g_TradingMode=(ENUM_NIXO_TRADING_MODE)savedMode;
   }
   if(GlobalVariableCheck(GVKey("ENTRIES_PAUSED"))) g_EntriesPaused=(GlobalVariableGet(GVKey("ENTRIES_PAUSED"))>0.5);
   g_ManualMode=(g_TradingMode==NIXO_MODE_MANUAL);
   g_StatsFrom    = (datetime)(long)GlobalVariableGet(GVKey("SFROM"));
   if(GlobalVariableCheck(GVKey("DAYSTAMP"))) g_DayStamp = (datetime)(long)GlobalVariableGet(GVKey("DAYSTAMP"));
   if(GlobalVariableCheck(GVKey("DAYSTART"))) g_DayStartEquity = GlobalVariableGet(GVKey("DAYSTART"));
   if(GlobalVariableCheck(GVKey("DAYPEAK")))  g_DayPeakEquity = GlobalVariableGet(GVKey("DAYPEAK"));
   if(GlobalVariableCheck(GVKey("DAYSTOP")))  g_DailyStopped = (GlobalVariableGet(GVKey("DAYSTOP")) > 0.5);

   if(GlobalVariableCheck(GVKey("S_STRAT")))
   {
      int s = (int)GlobalVariableGet(GVKey("S_STRAT"));
      if(s >= 0 && s <= 19) g_Strategy = s;
      g_BaseRisk     = GlobalVariableGet(GVKey("S_BASE"));
      g_ATRMult      = GlobalVariableGet(GVKey("S_SL"));
      g_TPRR         = GlobalVariableGet(GVKey("S_RR"));
      if(GlobalVariableCheck(GVKey("S_TPA"))) g_TPAnchorR=GlobalVariableGet(GVKey("S_TPA"));
      if(GlobalVariableCheck(GVKey("S_TP1"))) g_TP1R=GlobalVariableGet(GVKey("S_TP1"));
      if(GlobalVariableCheck(GVKey("S_TP2"))) g_TP2R=GlobalVariableGet(GVKey("S_TP2"));
      if(GlobalVariableCheck(GVKey("S_RUNATR"))) g_RunnerTrailATR=GlobalVariableGet(GVKey("S_RUNATR"));
      if(GlobalVariableCheck(GVKey("S_EPROF"))) g_ExitProfile=(int)GlobalVariableGet(GVKey("S_EPROF"));
      g_MaxStep      = (int)GlobalVariableGet(GVKey("S_MSTEP"));
      g_MaxTradesDay = (int)GlobalVariableGet(GVKey("S_TPD"));
      if(GlobalVariableCheck(GVKey("S_STPD")))
         g_ScalpMaxTradesDay = (int)GlobalVariableGet(GVKey("S_STPD"));
      g_UseBE        = (GlobalVariableGet(GVKey("S_BE")) > 0.5);
      g_MaxLot       = GlobalVariableGet(GVKey("S_MLOT"));
      if(GlobalVariableCheck(GVKey("S_ORDERS"))) g_OrderCount = (int)GlobalVariableGet(GVKey("S_ORDERS"));
      if(GlobalVariableCheck(GVKey("S_RROUL"))) g_RiskRouletteEnabled = (GlobalVariableGet(GVKey("S_RROUL")) > 0.5);
      if(GlobalVariableCheck(GVKey("S_OROUL"))) g_OrderRouletteEnabled = (GlobalVariableGet(GVKey("S_OROUL")) > 0.5);
      if(GlobalVariableCheck(GVKey("S_MORD")))  g_MultiOrderEnabled = (GlobalVariableGet(GVKey("S_MORD")) > 0.5);
      if(GlobalVariableCheck(GVKey("S_TURBO"))) g_TurboEnabled = (GlobalVariableGet(GVKey("S_TURBO")) > 0.5);
      if(GlobalVariableCheck(GVKey("S_PORT")))  g_PortfolioMode = (GlobalVariableGet(GVKey("S_PORT")) > 0.5);
      if(GlobalVariableCheck(GVKey("S_HEDGE"))) g_HedgeEnabled = (GlobalVariableGet(GVKey("S_HEDGE")) > 0.5);
      if(GlobalVariableCheck(GVKey("S_SPRPCT"))) g_MaxSpreadPct = GlobalVariableGet(GVKey("S_SPRPCT"));
      if(g_BaseRisk <= 0)  g_BaseRisk = InpBaseRisk;
      if(g_ATRMult  <= 0)  g_ATRMult  = InpATR_Mult;
      if(g_TPRR     <= 0)  g_TPRR     = InpTP_RR;
      if(g_TPAnchorR<=0) g_TPAnchorR=InpTPAnchorR;
      if(g_TP1R<=0) g_TP1R=InpTP1_R;
      if(g_TP2R<=g_TP1R) g_TP2R=MathMax(g_TP1R+0.25,InpTP2_R);
      if(g_RunnerTrailATR<=0) g_RunnerTrailATR=InpRunnerTrailATR;
      if(g_MaxStep  <  1)  g_MaxStep  = 1;
   }
   PrintFormat("State restored | StartEq=%.2f | Step=%d | Roulette=%d | Stopped=%s | Strategy=%s | Mode=%s | EntriesPaused=%s",
               g_StartEquity, g_Step, (int)g_Roulette, g_Stopped ? "YES" : "NO", StratShort(g_Strategy),
               TradingModeName(g_TradingMode),g_EntriesPaused?"YES":"NO");
}

string TradingModeName(ENUM_NIXO_TRADING_MODE mode)
{
   if(mode==NIXO_MODE_MANUAL) return "MANUAL";
   if(mode==NIXO_MODE_EXTERNAL) return "EXTERNAL SIGNALS";
   return "STRATEGY";
}

void SetTradingMode(ENUM_NIXO_TRADING_MODE mode)
{
   if(mode<NIXO_MODE_MANUAL || mode>NIXO_MODE_STRATEGY) return;
   if(g_TradingMode==mode && !g_EntriesPaused) return;
   ENUM_NIXO_TRADING_MODE oldMode=g_TradingMode;
   g_TradingMode=mode;
   g_ManualMode=(mode==NIXO_MODE_MANUAL);
   g_Running=false; // Strategy engine always needs an explicit START
   g_EntriesPaused=false; // explicit mode selection re-arms the selected route
   if(mode!=NIXO_MODE_EXTERNAL) g_SignalLiveEnabled=false; // disarm NEW external execution when leaving External mode
   g_PendingArmType=0; // clear only unsubmitted chart-click entry intent
   g_RRPlaceArmed=false;
   ObjectDelete(0,MANUAL_LINE_OBJ);
   SaveState();
   PrintFormat("TRADING MODE | %s -> %s | NEW entries routed to selected mode only | ALL existing positions, pending orders, SL and TP left untouched",
               TradingModeName(oldMode),TradingModeName(mode));
   Alert("Nixo Mode: ",TradingModeName(mode),". Existing positions, pending orders, SL and TP are unchanged.");
}

bool TradingModeAllowsEntry(string reason)
{
   if(g_EntriesPaused) return false;
   if(reason=="MANUAL") return (g_TradingMode==NIXO_MODE_MANUAL);
   return (g_TradingMode==NIXO_MODE_STRATEGY);
}

//==================================================================
//  v5.00 DAILY GUARD + COMMISSION ESTIMATION + RUNNER TP STATE
//==================================================================
int VolumeDigits(double step);

bool TurboActive()
{
   return g_TurboEnabled;
}

bool UseStagedTP()
{
   return (InpUseMultiTP || TurboActive());
}

datetime BrokerDayStart()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

void ResetDailyProtection(datetime dayStamp)
{
   g_DayStamp       = dayStamp;
   g_DayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_DayPeakEquity  = g_DayStartEquity;
   g_DailyStopped   = false;
   g_DailyStopReason= "";
   if(g_ResumeAfterDaily && InpAutoResumeNextDay && !g_Stopped && g_TradingMode==NIXO_MODE_STRATEGY && !g_EntriesPaused)
   {
      g_Running = true;
      Print(">>> NIXO AUTO-RESUMED for the new broker day");
   }
   g_ResumeAfterDaily = false;
   SaveState();
   PrintFormat("DAILY GUARD RESET | start equity=%.2f | broker day=%s",
               g_DayStartEquity, TimeToString(g_DayStamp, TIME_DATE));
}

void CloseAllNixoPositions(string reason)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), "Nixo500|") != 0) continue;
      bool sent = trade.PositionClose(ticket, InpSlippage);
      uint rc = trade.ResultRetcode();
      if(!sent || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_DONE_PARTIAL))
         PrintFormat("PROTECTION CLOSE FAILED | ticket=%I64u | reason=%s | retcode=%u %s",
                     ticket, reason, rc, trade.ResultRetcodeDescription());
   }
}

void CloseAllNixoPositionsOnly()
{
   // Explicit user command: close Nixo positions only. Pending orders and their SL/TP are untouched.
   g_Running=false;
   g_SignalLiveEnabled=false;
   g_EntriesPaused=true;
   g_PendingArmType=0;
   g_RRPlaceArmed=false;
   ObjectDelete(0,MANUAL_LINE_OBJ);
   SaveState();

   int matched=0,closed=0,failed=0,pendingLeft=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ot=OrderGetTicket(i); if(ot==0) continue;
      long magic=OrderGetInteger(ORDER_MAGIC);
      string c=OrderGetString(ORDER_COMMENT);
      bool mainNixo=(magic==InpMagic && StringFind(c,"Nixo500|")==0);
      bool signalNixo=(magic==InpSignalMagic && StringFind(c,"NX503|")==0);
      if(mainNixo || signalNixo) pendingLeft++;
   }

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      long magic=PositionGetInteger(POSITION_MAGIC);
      string comment=PositionGetString(POSITION_COMMENT);
      bool mainNixo=(magic==InpMagic && StringFind(comment,"Nixo500|")==0);
      bool signalNixo=(magic==InpSignalMagic && StringFind(comment,"NX503|")==0);
      if(!mainNixo && !signalNixo) continue;
      matched++;
      string sym=PositionGetString(POSITION_SYMBOL);
      trade.SetTypeFillingBySymbol(sym);
      bool sent=trade.PositionClose(ticket,InpSlippage);
      uint rc=trade.ResultRetcode();
      if(sent && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL)) closed++;
      else
      {
         failed++;
         PrintFormat("CLOSE NIXO POSITION FAILED | ticket=%I64u | symbol=%s | retcode=%u %s",ticket,sym,rc,trade.ResultRetcodeDescription());
      }
   }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   PrintFormat("CLOSE NIXO POSITIONS ONLY | matched=%d | accepted=%d | failed=%d | pending orders preserved=%d | new entries PAUSED",
      matched,closed,failed,pendingLeft);
   Alert("Nixo position close: ",closed," close requests accepted; ",failed," failed. Pending orders left untouched: ",pendingLeft,
         ". IMPORTANT: a preserved pending order can still fill later. New automatic entries are paused.");
}

void TriggerDailyStop(string reason, double equity, double threshold)
{
   if(g_DailyStopped) return;
   g_DailyStopped = true;
   g_DailyStopReason = reason;
   g_ResumeAfterDaily = (InpAutoResumeNextDay && g_Running);
   g_Running = false;
   SaveState();
   PrintFormat("DAILY PROTECTION TRIGGERED | %s | equity=%.2f | threshold=%.2f",
               reason, equity, threshold);
   Alert("Nixo daily protection: ", reason, ". Trading paused until next broker day.");
   CloseAllNixoPositions(reason);
}

void CheckDailyProtection()
{
   if(!InpUseDailyProtection)
   {
      g_DailyStopped = false;
      g_DailyStopReason = "";
      return;
   }
   if(g_DailyStopped || g_DayStartEquity <= 0.0) return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double updateStep = MathMax(1.0, g_DayStartEquity * 0.0001); // persist peak at 0.01% increments
   if(equity > g_DayPeakEquity + updateStep)
   {
      g_DayPeakEquity = equity;
      GlobalVariableSet(GVKey("DAYPEAK"), g_DayPeakEquity);
   }

   if(InpDailyMaxLossPct > 0.0)
   {
      double lossFloor = g_DayStartEquity * (1.0 - InpDailyMaxLossPct / 100.0);
      if(equity <= lossFloor)
      {
         TriggerDailyStop("daily loss limit", equity, lossFloor);
         return;
      }
   }

   if(InpDailyProfitArmPct > 0.0 && InpDailyGivebackPct >= 0.0 && InpDailyGivebackPct < 100.0)
   {
      double peakProfit = g_DayPeakEquity - g_DayStartEquity;
      double armMoney  = g_DayStartEquity * InpDailyProfitArmPct / 100.0;
      if(peakProfit >= armMoney)
      {
         double lockMoney = peakProfit * (1.0 - InpDailyGivebackPct / 100.0);
         double lockFloor = g_DayStartEquity + lockMoney;
         if(equity <= lockFloor)
         {
            TriggerDailyStop("daily profit protection", equity, lockFloor);
            return;
         }
      }
   }
}

string PositionStateKey(ulong positionId, string field)
{
   return GVKey("P" + (string)positionId + "_" + field);
}

void ClearMultiTPState(ulong positionId)
{
   GlobalVariableDel(PositionStateKey(positionId, "R"));
   GlobalVariableDel(PositionStateKey(positionId, "V"));
   for(int st=1; st<=6; st++)
   {
      GlobalVariableDel(PositionStateKey(positionId, (string)st));
      GlobalVariableDel(PositionStateKey(positionId, "T" + (string)st)); // fixed target close volume for this stage
      GlobalVariableDel(PositionStateKey(positionId, "X" + (string)st)); // actual volume already closed in this stage
   }
   GlobalVariableDel(PositionStateKey(positionId, "SP"));
   GlobalVariableDel(PositionStateKey(positionId, "A"));
   GlobalVariableDel(PositionStateKey(positionId, "MSL")); // last SL written by Nixo; manual edits can be detected
   GlobalVariableDel(PositionStateKey(positionId, "F")); // broker TP fallback flag
   GlobalVariableDel(PositionStateKey(positionId, "NR")); // cached realized net for statistics
   ObjectDelete(0,"NIXO500_TP3_"+(string)positionId);
}

bool IsVolumeStepValid(double volume)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0 || volume < minLot - 1e-9 || volume > maxLot + 1e-9) return false;
   double units = volume / step;
   return (MathAbs(units - MathRound(units)) < 1e-6);
}

double NormalizeVolumeDown(double volume)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) return 0.0;
   int vd = VolumeDigits(step);
   return NormalizeDouble(MathFloor(volume / step + 1e-9) * step, vd);
}

double NormalizeVolumeNearest(double volume)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) return 0.0;
   int vd = VolumeDigits(step);
   return NormalizeDouble(MathRound(volume / step) * step, vd);
}

double TPStageTriggerDistanceR(int stage, double anchorR)
{
   if(stage == 1) return g_TP1R;
   if(stage == 2) return g_TP2R;
   if(stage == 3) return anchorR;
   return anchorR;
}

// Cumulative net P/L for this position, including already-realized partial exits,
// current floating P/L, accrued swap, posted commission/fees, and estimated remaining exit costs.
// POSITION_PROFIT is based on the executable Bid (BUY close) / Ask (SELL close), so spread
// is already reflected and is deliberately not subtracted a second time.
double PositionNetProfitEstimateForTP(ulong ticket, ulong positionId)
{
   if(!PositionSelectByTicket(ticket) || positionId == 0) return -1.0e100;

   long ptype = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);
   double floating = PositionGetDouble(POSITION_PROFIT);
   double positionSwap = PositionGetDouble(POSITION_SWAP);
   double realisedNet = 0.0;
   string realizedKey=PositionStateKey(positionId,"NR");
   if(GlobalVariableCheck(realizedKey))
      realisedNet=GlobalVariableGet(realizedKey);
   else
   {
      if(!ReadPositionRealizedNet(positionId,realisedNet)) return -1.0e100;
      GlobalVariableSet(realizedKey,realisedNet);
   }

   // The configured value is round-turn commission; entry-side charges already posted
   // are included above, so estimate only the remaining close-side half for current volume.
   double closeCommission = MathMax(0.0, EstimateRoundTurnCommissionPerLot()) * 0.5 * volume;

   // Estimate adverse close slippage in account currency.
   double slippageCost = 0.0;
   int slipPoints = MathMax(0, InpRiskSlippagePoints);
   if(slipPoints > 0 && volume > 0.0)
   {
      double exitQuote = (ptype == POSITION_TYPE_BUY)
                         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double adverseQuote = (ptype == POSITION_TYPE_BUY)
                            ? exitQuote - slipPoints * _Point
                            : exitQuote + slipPoints * _Point;
      double slipProfit = 0.0;
      ENUM_ORDER_TYPE orderType = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcProfit(orderType, _Symbol, volume, exitQuote, adverseQuote, slipProfit))
         slippageCost = MathAbs(slipProfit);
   }

   return realisedNet + floating + positionSwap - closeCommission - slippageCost;
}

double TPStageClosePct(int stage)
{
   // All three stages close half of the volume currently open at that target.
   return (stage >= 1 && stage <= 3) ? 50.0 : 0.0;
}

bool MultiTPPlanValid(double lot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double remain = NormalizeVolumeDown(lot);
   if(minLot <= 0.0 || remain < minLot - 1e-9) return false;

   // Simulate three executable 50% partial closes, rounding each to broker volume step.
   for(int stage=1; stage<=3; stage++)
   {
      double closeVol = NormalizeVolumeNearest(remain * 0.5);
      closeVol = MathMin(closeVol, NormalizeVolumeDown(remain - minLot));
      closeVol = NormalizeVolumeDown(closeVol);
      if(closeVol < minLot - 1e-9 || remain - closeVol < minLot - 1e-9)
         return false;
      remain = NormalizeVolumeDown(remain - closeVol);
   }
   return (remain >= minLot - 1e-9);
}

// Estimate full open+close commission per lot from this EA's closed positions.
// Explicit input overrides the historical estimate.
double EstimateRoundTurnCommissionPerLot()
{
   if(InpCommissionPerLotRT > 0.0) return InpCommissionPerLotRT;
   datetime now = TimeCurrent();
   if(g_CommissionCacheTime > 0 && now - g_CommissionCacheTime < 300)
      return g_CommissionCache;

   g_CommissionCache = 0.0;
   g_CommissionCacheTime = now;
   if(!HistorySelect(now - 90 * 86400, now)) return 0.0;

   CommissionAgg aggs[];
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      ulong pid = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(pid == 0) continue;
      int idx = -1;
      int cntA = ArraySize(aggs);
      int loA = MathMax(0, cntA - 200);
      for(int k = cntA - 1; k >= loA; k--)
         if(aggs[k].id == pid) { idx = k; break; }
      if(idx < 0)
      {
         idx = ArraySize(aggs);
         ArrayResize(aggs, idx + 1, 512);
         aggs[idx].id = pid; aggs[idx].inVol = 0.0; aggs[idx].outVol = 0.0; aggs[idx].costs = 0.0;
      }
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      double vol = HistoryDealGetDouble(deal, DEAL_VOLUME);
      if(entry == DEAL_ENTRY_IN) aggs[idx].inVol += vol;
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT) aggs[idx].outVol += vol;
      aggs[idx].costs += MathAbs(HistoryDealGetDouble(deal, DEAL_COMMISSION));
      aggs[idx].costs += MathAbs(HistoryDealGetDouble(deal, DEAL_FEE));
   }
   double allCosts = 0.0, allEntryVolume = 0.0;
   for(int j = 0; j < ArraySize(aggs); j++)
   {
      if(aggs[j].inVol > 0.0 && aggs[j].outVol + 1e-8 >= aggs[j].inVol)
      { allCosts += aggs[j].costs; allEntryVolume += aggs[j].inVol; }
   }
   if(allEntryVolume > 0.0) g_CommissionCache = allCosts / allEntryVolume;
   return g_CommissionCache;
}

bool EnsureMultiTPState(ulong ticket, ulong &positionId, double &initialR, double &initialVolume, double &anchorR,
                        bool &tp1Done, bool &tp2Done, bool &tp3Done, bool &tp4Done, bool &tp5Done, bool &tp6Done)
{
   if(!PositionSelectByTicket(ticket)) return false;
   positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(positionId == 0) return false;
   string fallbackKey = PositionStateKey(positionId, "F");
   if(GlobalVariableCheck(fallbackKey) && GlobalVariableGet(fallbackKey) > 0.5) return false;

   string keyR = PositionStateKey(positionId, "R");
   string keyV = PositionStateKey(positionId, "V");
   if(!GlobalVariableCheck(keyR) || !GlobalVariableCheck(keyV))
   {
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(sl <= 0.0 || vol <= 0.0) return false;
      initialR = MathAbs(open - sl);
      initialVolume = vol;
      GlobalVariableSet(keyR, initialR);
      GlobalVariableSet(keyV, initialVolume);
      for(int st=1; st<=6; st++) GlobalVariableSet(PositionStateKey(positionId, (string)st), 0.0);
   }
   string keySP=PositionStateKey(positionId,"SP");
   if(!GlobalVariableCheck(keySP))
      GlobalVariableSet(keySP,MathMax(0.0,SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID)));
   string keyA=PositionStateKey(positionId,"A");
   if(!GlobalVariableCheck(keyA)) GlobalVariableSet(keyA,g_TPAnchorR);
   if(!GlobalVariableCheck(PositionStateKey(positionId,"TP1"))) GlobalVariableSet(PositionStateKey(positionId,"TP1"),g_TP1R);
   if(!GlobalVariableCheck(PositionStateKey(positionId,"TP2"))) GlobalVariableSet(PositionStateKey(positionId,"TP2"),g_TP2R);
   if(!GlobalVariableCheck(PositionStateKey(positionId,"RATR"))) GlobalVariableSet(PositionStateKey(positionId,"RATR"),g_RunnerTrailATR);
   if(!GlobalVariableCheck(PositionStateKey(positionId,"BE"))) GlobalVariableSet(PositionStateKey(positionId,"BE"),g_UseBE?1.0:0.0);
   if(!GlobalVariableCheck(PositionStateKey(positionId,"BER"))) GlobalVariableSet(PositionStateKey(positionId,"BER"),InpBE_R);
   if(!GlobalVariableCheck(PositionStateKey(positionId,"MULTI"))) GlobalVariableSet(PositionStateKey(positionId,"MULTI"),UseStagedTP()?1.0:0.0);
   if(!GlobalVariableCheck(PositionStateKey(positionId,"TIME"))) GlobalVariableSet(PositionStateKey(positionId,"TIME"),(double)InpTimeStopBars);
   if(!GlobalVariableCheck(PositionStateKey(positionId,"TIMEMIN"))) GlobalVariableSet(PositionStateKey(positionId,"TIMEMIN"),InpTimeStopMinR);
   string keyMSL=PositionStateKey(positionId,"MSL");
   if(!GlobalVariableCheck(keyMSL)) GlobalVariableSet(keyMSL,PositionGetDouble(POSITION_SL));
   anchorR=GlobalVariableGet(keyA);
   initialR = GlobalVariableGet(keyR);
   initialVolume = GlobalVariableGet(keyV);
   tp1Done = GlobalVariableCheck(PositionStateKey(positionId, "1")) && GlobalVariableGet(PositionStateKey(positionId, "1")) > 0.5;
   tp2Done = GlobalVariableCheck(PositionStateKey(positionId, "2")) && GlobalVariableGet(PositionStateKey(positionId, "2")) > 0.5;
   tp3Done = GlobalVariableCheck(PositionStateKey(positionId, "3")) && GlobalVariableGet(PositionStateKey(positionId, "3")) > 0.5;
   tp4Done = GlobalVariableCheck(PositionStateKey(positionId, "4")) && GlobalVariableGet(PositionStateKey(positionId, "4")) > 0.5;
   tp5Done = GlobalVariableCheck(PositionStateKey(positionId, "5")) && GlobalVariableGet(PositionStateKey(positionId, "5")) > 0.5;
   tp6Done = GlobalVariableCheck(PositionStateKey(positionId, "6")) && GlobalVariableGet(PositionStateKey(positionId, "6")) > 0.5;
   return (initialR > 0.0 && initialVolume > 0.0);
}

bool TradeRequestSucceeded(bool sent)
{
   uint rc = trade.ResultRetcode();
   return (sent && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL));
}

bool PendingOrderRequestSucceeded(bool sent)
{
   uint rc = trade.ResultRetcode();
   return (sent && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED));
}

void MovePositionSL(ulong ticket, long ptype, double desiredSL, double tp)
{
   if(!PositionSelectByTicket(ticket)) return;
   double currentSL = PositionGetDouble(POSITION_SL);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   double minModifyDistance = MathMax(stopsLevel, freezeLevel) + _Point;
   desiredSL = NormalizeDouble(desiredSL, _Digits);
   if(ptype == POSITION_TYPE_BUY)
   {
      if(currentSL > 0.0 && desiredSL <= currentSL + _Point * 0.5) return;
      if(bid - desiredSL <= minModifyDistance)
      {
         if(InpDebug && ShouldLogSLWait(ticket)) PrintFormat("SL MOVE WAIT | ticket=%I64u | BUY SL %.5f too close to Bid %.5f (stops/freeze %.5f); will retry", ticket, desiredSL, bid, minModifyDistance);
         return;
      }
   }
   else
   {
      if(currentSL > 0.0 && desiredSL >= currentSL - _Point * 0.5) return;
      if(desiredSL - ask <= minModifyDistance)
      {
         if(InpDebug && ShouldLogSLWait(ticket)) PrintFormat("SL MOVE WAIT | ticket=%I64u | SELL SL %.5f too close to Ask %.5f (stops/freeze %.5f); will retry", ticket, desiredSL, ask, minModifyDistance);
         return;
      }
   }
   bool sent = trade.PositionModify(ticket, desiredSL, tp);
   if(!TradeRequestSucceeded(sent))
      PrintFormat("STAGED-TP SL MODIFY FAILED | ticket=%I64u | retcode=%u %s", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
}

double BreakEvenPlusCostsPrice(long ptype, double open, double volume)
{
   double commissionRT = MathMax(0.0, EstimateRoundTurnCommissionPerLot());
   double accruedSwap = PositionGetDouble(POSITION_SWAP); // negative swap adds cost; positive swap offsets it
   double costMoney = MathMax(0.0, commissionRT * volume - accruedSwap);
   double onePointProfit = 0.0;
   double probe = (ptype == POSITION_TYPE_BUY) ? open + _Point : open - _Point;
   ENUM_ORDER_TYPE type = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type, _Symbol, volume, open, probe, onePointProfit) || MathAbs(onePointProfit) <= 0.0)
      return open;
   double points = (costMoney / MathAbs(onePointProfit)) + MathMax(0, InpRiskSlippagePoints);
   double offset = MathCeil(points) * _Point;
   // Spread is reflected in the executable close quote (Bid for BUY / Ask for SELL); do not add it twice.
   return (ptype == POSITION_TYPE_BUY) ? open + offset : open - offset;
}

bool ClosePartialStage(ulong ticket, ulong pid, int stage, double targetVolume, bool closeRemainder)
{
   if(!PositionSelectByTicket(ticket)) return false;
   double beforeVolume = PositionGetDouble(POSITION_VOLUME);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minLot <= 0.0 || step <= 0.0) return false;

   string stageKey = PositionStateKey(pid, (string)stage);
   string targetKey = PositionStateKey(pid, "T" + (string)stage);
   string progressKey = PositionStateKey(pid, "X" + (string)stage);
   double closeVol = beforeVolume;
   double stageTarget = 0.0;
   double progress = 0.0;

   if(!closeRemainder)
   {
      // Freeze the requested amount on the first attempt. If the broker partially fills
      // the close request, subsequent ticks close only the still-unfilled part.
      if(GlobalVariableCheck(targetKey)) stageTarget = GlobalVariableGet(targetKey);
      else
      {
         stageTarget = NormalizeVolumeNearest(targetVolume);
         GlobalVariableSet(targetKey, stageTarget);
      }
      if(GlobalVariableCheck(progressKey)) progress = GlobalVariableGet(progressKey);
      double leftToClose = stageTarget - progress;
      double tolerance = step * 0.25;
      if(leftToClose <= tolerance)
      {
         GlobalVariableSet(stageKey, 1.0);
         return true;
      }
      closeVol = NormalizeVolumeNearest(leftToClose);
      closeVol = MathMin(closeVol, NormalizeVolumeDown(beforeVolume - minLot));
      closeVol = NormalizeVolumeDown(closeVol);
      if(closeVol < minLot - 1e-9 || beforeVolume - closeVol < minLot - 1e-9)
      {
         string warnKey = PositionStateKey(pid, "W" + (string)stage);
         if(!GlobalVariableCheck(warnKey))
         {
            GlobalVariableSet(warnKey, 1.0);
            PrintFormat("TP%d PAUSED | broker min/step prevents the remaining partial close; volume=%.4f, stage target=%.4f, already closed=%.4f, min=%.4f, step=%.4f. Stage is NOT marked complete.",
                        stage, beforeVolume, stageTarget, progress, minLot, step);
         }
         return false;
      }
   }
   else
   {
      closeVol = NormalizeVolumeDown(beforeVolume);
      if(closeVol < minLot - 1e-9) return false;
   }

   bool sent = closeRemainder ? trade.PositionClose(ticket, InpSlippage)
                              : trade.PositionClosePartial(ticket, closeVol, InpSlippage);
   uint rc = trade.ResultRetcode();

   // Measure the real position-volume delta rather than trusting the requested amount.
   double afterVolume = 0.0;
   bool stillOpen = PositionSelectByTicket(ticket);
   if(stillOpen) afterVolume = PositionGetDouble(POSITION_VOLUME);
   double actuallyClosed = stillOpen ? MathMax(0.0, beforeVolume - afterVolume) : beforeVolume;

   if(closeRemainder)
   {
      if(!stillOpen && TradeRequestSucceeded(sent))
      {
         GlobalVariableSet(stageKey, 1.0);
         return true;
      }
   }
   else if(actuallyClosed > 0.0)
   {
      progress += actuallyClosed;
      GlobalVariableSet(progressKey, progress);
      if(stageTarget - progress <= step * 0.25)
      {
         GlobalVariableSet(stageKey, 1.0);
         PrintFormat("TP%d EXECUTED | ticket=%I64u | stage closed=%.4f/%.4f lots | remaining=%.4f lots",
                     stage, ticket, progress, stageTarget, afterVolume);
         return true;
      }
      PrintFormat("TP%d PARTIAL FILL | ticket=%I64u | stage progress=%.4f/%.4f lots | still to close=%.4f lots; will retry without over-closing",
                  stage, ticket, progress, stageTarget, MathMax(0.0, stageTarget-progress));
      return false;
   }

   PrintFormat("TP%d CLOSE FAILED | ticket=%I64u | sent=%s | retcode=%u %s",
               stage, ticket, sent ? "true" : "false", rc, trade.ResultRetcodeDescription());
   return false;
}

string TP3LineName(ulong positionId)
{
   return "NIXO500_TP3_"+(string)positionId;
}

void EnsureTP3GuideLine(ulong positionId,long ptype,double open,double initialR,double anchorR)
{
   if(positionId==0 || initialR<=0.0 || anchorR<=g_TP2R) return;
   string name=TP3LineName(positionId);
   double level=(ptype==POSITION_TYPE_BUY)?open+initialR*anchorR:open-initialR*anchorR;
   level=NormalizeDouble(level,_Digits);
   if(ObjectFind(0,name)<0)
   {
      if(!ObjectCreate(0,name,OBJ_HLINE,0,0,level)) return;
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrGold);
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
      ObjectSetString(0,name,OBJPROP_TEXT,"NIXO TP3 — drag to adjust");
   }
   else if(!ObjectGetInteger(0,name,OBJPROP_SELECTED))
      ObjectSetDouble(0,name,OBJPROP_PRICE,level);
}

void ManageMultiTPPosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   ulong pid=0;
   double initialR=0.0, initialVolume=0.0, anchorR=g_TPAnchorR;
   bool done[6];
   for(int k=0;k<6;k++) done[k]=false;
   if(!EnsureMultiTPState(ticket,pid,initialR,initialVolume,anchorR,done[0],done[1],done[2],done[3],done[4],done[5])) return;
   if(!PositionSelectByTicket(ticket)) return;
   double positionTP1R=GlobalVariableCheck(PositionStateKey(pid,"TP1"))?GlobalVariableGet(PositionStateKey(pid,"TP1")):g_TP1R;
   double positionTP2R=GlobalVariableCheck(PositionStateKey(pid,"TP2"))?GlobalVariableGet(PositionStateKey(pid,"TP2")):g_TP2R;
   double positionRunnerATR=GlobalVariableCheck(PositionStateKey(pid,"RATR"))?GlobalVariableGet(PositionStateKey(pid,"RATR")):g_RunnerTrailATR;
   bool positionUseBE=GlobalVariableCheck(PositionStateKey(pid,"BE"))?(GlobalVariableGet(PositionStateKey(pid,"BE"))>0.5):g_UseBE;
   double positionBER=GlobalVariableCheck(PositionStateKey(pid,"BER"))?GlobalVariableGet(PositionStateKey(pid,"BER")):InpBE_R;
   long ptype=PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN);
   double currentVolume=PositionGetDouble(POSITION_VOLUME);
   double currentSL=PositionGetDouble(POSITION_SL);
   double currentTP=PositionGetDouble(POSITION_TP);
   if(currentSL<=0.0)
   {
      if(InpDebug) PrintFormat("RUNNER MANAGER PAUSED | ticket=%I64u has no server-side SL. Restore SL before management continues.",ticket);
      return;
   }
   string managedSLKey=PositionStateKey(pid,"MSL");
   double lastManagedSL=GlobalVariableCheck(managedSLKey)?GlobalVariableGet(managedSLKey):currentSL;
   if(MathAbs(currentSL-lastManagedSL)>_Point*0.5)
   {
      double userRiskDistance=MathAbs(open-currentSL);
      if(userRiskDistance>_Point)
      {
         initialR=userRiskDistance;
         GlobalVariableSet(PositionStateKey(pid,"R"),initialR);
         GlobalVariableSet(managedSLKey,currentSL);
         PrintFormat("MANUAL SL CHANGE DETECTED | ticket=%I64u | new R distance=%.5f | TP1/TP2/TP3 recalculated from the adjusted SL distance.",ticket,initialR);
      }
   }
   EnsureTP3GuideLine(pid,ptype,open,initialR,anchorR);

   // A broker TP on the whole position would close the runner as well.
   // Clear any TP and keep the protective SL server-side; TP targets are EA-managed.
   if(currentTP>0.0)
   {
      bool cleared=trade.PositionModify(ticket,currentSL,0.0);
      if(!TradeRequestSucceeded(cleared))
      {
         if(InpDebug) PrintFormat("RUNNER SAFETY WAIT | cannot remove whole-position TP | ticket=%I64u | %u %s",
                                  ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
         return;
      }
      if(!PositionSelectByTicket(ticket)) return;
   }

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double marketExit=(ptype==POSITION_TYPE_BUY)?bid:ask;
   int stages=3;

   // Run all reached stages in order. TP1 closes 50% of initial volume;
   // TP2 and TP3 each close 50% of the then-current remainder.
   for(int st=1; st<=stages; st++)
   {
      if(done[st-1]) continue;
      if(st>1 && !done[st-2]) break;
      double triggerR=(st==1?positionTP1R:(st==2?positionTP2R:anchorR));
      double triggerDistance=initialR*triggerR;
      bool hit=(ptype==POSITION_TYPE_BUY)
               ? marketExit >= open+triggerDistance
               : marketExit <= open-triggerDistance;
      if(!hit) break;

      if(!PositionSelectByTicket(ticket)) return;
      currentVolume=PositionGetDouble(POSITION_VOLUME);
      double requestedClose=(st==1)?initialVolume*0.50:currentVolume*0.50;
      bool closed=ClosePartialStage(ticket,pid,st,requestedClose,false);
      if(!closed) return;
      done[st-1]=true;
      if(st==3) ObjectDelete(0,TP3LineName(pid));
      if(!PositionSelectByTicket(ticket)) return;
      currentVolume=PositionGetDouble(POSITION_VOLUME);
   }

   if(!PositionSelectByTicket(ticket)) return;
   currentSL=PositionGetDouble(POSITION_SL);
   currentTP=PositionGetDouble(POSITION_TP);
   bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   marketExit=(ptype==POSITION_TYPE_BUY)?bid:ask;

   double desiredSL=0.0;
   bool protectSL=false;
   if(done[2])
   {
      // Runner starts with at least the TP2 profit protected; ATR trail can only tighten it.
      double locked=(ptype==POSITION_TYPE_BUY)?open+initialR*positionTP2R:open-initialR*positionTP2R;
      double atrT=GetATR(1);
      desiredSL=locked;
      if(positionRunnerATR>0.0 && atrT>0.0)
      {
         double trailSL=(ptype==POSITION_TYPE_BUY)?marketExit-positionRunnerATR*atrT
                                                  :marketExit+positionRunnerATR*atrT;
         desiredSL=(ptype==POSITION_TYPE_BUY)?MathMax(locked,trailSL):MathMin(locked,trailSL);
      }
      protectSL=true;
   }
   else if(done[1])
   {
      desiredSL=BreakEvenPlusCostsPrice(ptype,open,currentVolume);
      protectSL=true;
   }
   else if(done[0])
   {
      desiredSL=(ptype==POSITION_TYPE_BUY)?open-initialR*0.50:open+initialR*0.50;
      protectSL=true;
   }

   if(positionUseBE && positionBER>0.0)
   {
      double favorableMove=(ptype==POSITION_TYPE_BUY)?(bid-open):(open-ask);
      if(favorableMove>=positionBER*initialR)
      {
         double beSL=BreakEvenPlusCostsPrice(ptype,open,currentVolume);
         if(!protectSL) { desiredSL=beSL; protectSL=true; }
         else desiredSL=(ptype==POSITION_TYPE_BUY)?MathMax(desiredSL,beSL):MathMin(desiredSL,beSL);
      }
   }
   if(protectSL)
   {
      MovePositionSL(ticket,ptype,desiredSL,0.0);
      if(PositionSelectByTicket(ticket))
         GlobalVariableSet(managedSLKey,PositionGetDouble(POSITION_SL));
   }
}

bool HasLegacyNixoPositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "Nixo500|") != 0) return true;
   }
   return false;
}

//==================================================================
//  INIT / DEINIT
//==================================================================
bool ValidTPInputs()
{
   if(g_TP1R<=0.0 || g_TP2R<=g_TP1R || g_TPAnchorR<=g_TP2R) return false;
   if(g_RunnerTrailATR<=0.0) return false;
   if(InpPositionSizeMode==NIXO_SIZE_FIXED_MONEY && InpFixedRiskMoney<=0.0) return false;
   if(InpPositionSizeMode==NIXO_SIZE_FIXED_LOT && InpFixedLot<=0.0) return false;
   return true;
}

//==================================================================
//  SIGNAL COPY ENGINE + FOUR-MODE PAPER LAB
//  Bridge format: NIXO_SIG_V1|event_uid|signal_id|source_id|action|symbol|side|kind|entry|sl|tp1|tp2|tp3|unix_time
//==================================================================
struct SignalPaperTrade
{
   string signalId;
   string sourceId;
   int    model;       // A=0, B=1, C=2, D=3
   int    side;        // BUY=1, SELL=-1
   int    kind;        // MARKET=0, LIMIT=1, STOP=2
   double entry;
   double sl;
   double tp1;
   double tp2;
   double tp3;
   double totalLots;
   double remainingLots;
   double realized;
   int    orders;
   int    orderStep;
   int    volumeStep;
   int    stage;
   int    state;       // 0=pending, 1=open, 2=closed
   datetime openedAt;
};
SignalPaperTrade g_SignalPaperTrades[];
long g_SignalLiveHashes[];

string SignalGlobalKey(long signalHash,string suffix)
{
   return StringFormat("NXS503_%I64d_%I64d_%I64d_%s",AccountInfoInteger(ACCOUNT_LOGIN),InpSignalMagic,signalHash,suffix);
}

long SignalHash(string value)
{
   long h=17;
   for(int i=0;i<StringLen(value);i++)
      h=(h*131+(long)StringGetCharacter(value,i))%2000000000;
   if(h<1) h=1;
   return h;
}

long SignalHashFromComment(string comment)
{
   int at=StringFind(comment,"NX503|");
   if(at<0) return 0;
   return (long)StringToInteger(StringSubstr(comment,at+6));
}

int SignalStateStep(long sourceHash,string suffix,int initial,int cap)
{
   string key=SignalGlobalKey(sourceHash,suffix);
   int value=GlobalVariableCheck(key)?(int)GlobalVariableGet(key):initial;
   return (int)Clampd(value,1,MathMax(1,cap));
}

void SignalSetStateStep(long sourceHash,string suffix,int value,int cap)
{
   GlobalVariableSet(SignalGlobalKey(sourceHash,suffix),(double)(int)Clampd(value,1,MathMax(1,cap)));
}

string SignalOrderStateSuffix(int model,bool live)
{
   return StringFormat("%s%dO",live?"L":"P",model);
}

string SignalVolumeStateSuffix(int model,bool live)
{
   return StringFormat("%s%dV",live?"L":"P",model);
}

int SignalModelOrderStep(long sourceHash,int model,bool live=false)
{
   if(model!=1 && model!=3) return 1;
   return SignalStateStep(sourceHash,SignalOrderStateSuffix(model,live),MathMax(1,InpSignalInitialOrderCount),MathMax(1,InpSignalMaxOrderCount));
}

int SignalModelVolumeStep(long sourceHash,int model,bool live=false)
{
   if(model!=2 && model!=3) return 1;
   return SignalStateStep(sourceHash,SignalVolumeStateSuffix(model,live),1,MathMax(1,InpSignalMaxVolumeStep));
}

string SignalModelName(int model)
{
   if(model==0) return "A_BASE";
   if(model==1) return "B_ORDER";
   if(model==2) return "C_VOLUME";
   return "D_COMBINED";
}

bool SignalSymbolMatches(string signalSymbol)
{
   string s=signalSymbol; StringToUpper(s);
   string chart=_Symbol; StringToUpper(chart);
   if(s=="XAUUSD" || s=="GOLD" || s=="XAU") return IsGoldSymbol();
   if(StringFind(chart,s)>=0 || StringFind(s,chart)>=0) return true;
   return false;
}

double NormalizeSignalPrice(double price)
{
   if(price<=0.0) return price;
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0.0) tickSize=_Point;
   return NormalizeDouble(MathRound(price/tickSize)*tickSize,_Digits);
}

bool SignalRunnerVolumeEligible(double initialVolume)
{
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(step<=0.0) step=minLot;
   if(step<=0.0) return false;
   // 50% -> 50% -> 50% requires at least eight volume-step units,
   // and an exact multiple of eight to leave an exact 12.5% runner.
   double units=MathRound(initialVolume/step);
   if(units<8.0) return false;
   if(minLot>0.0 && initialVolume/8.0<minLot-step*0.25) return false;
   if(MathAbs(initialVolume-units*step)>step*0.05) return false;
   return (((long)MathRound(units))%8)==0;
}

bool SignalOrderSucceeded(bool sent)
{
   if(!sent) return false;
   uint rc=trade.ResultRetcode();
   return (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED);
}

double SignalBaseLot(int side,double entry,double sl)
{
   double lot=InpSignalBaseLot;
   if(InpSignalSizeMode!=SIGNAL_SIZE_FIXED_LOT)
   {
      ENUM_ORDER_TYPE ot=(side>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
      double loss=0.0;
      if(!OrderCalcProfit(ot,_Symbol,1.0,entry,sl,loss)) return 0.0;
      double lossPerLot=MathAbs(loss)+InpSignalCommissionRTPerLot;
      if(lossPerLot<=0.0) return 0.0;
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      double riskMoney=(InpSignalSizeMode==SIGNAL_SIZE_RISK_PERCENT)
                       ? equity*MathMax(0.0,InpSignalBaseRiskPct)/100.0
                       : MathMax(0.0,InpSignalBaseRiskCash);
      lot=riskMoney/lossPerLot;
   }
   lot=NormalizeVolumeDown(lot);
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(maxLot>0.0) lot=MathMin(lot,maxLot);
   if(lot<=0.0 || (minLot>0.0 && lot<minLot-1e-9))
   {
      Print("SIGNAL SIZE rejected: selected budget computes below the broker's minimum tradable volume; no minimum-lot override is applied.");
      return 0.0;
   }
   return lot;
}

int SignalModelOrderCount(long sourceHash,int model,bool live=false)
{
   return (model==1 || model==3) ? SignalModelOrderStep(sourceHash,model,live) : 1;
}

double SignalModelTotalLots(long sourceHash,int model,double baseLot,bool live=false)
{
   int volumeStep=SignalModelVolumeStep(sourceHash,model,live);
   int count=SignalModelOrderCount(sourceHash,model,live);
   double total=baseLot*(1.0+MathMax(0.0,InpSignalVolumeStepFactor)*MathMax(0,volumeStep-1));
   if(!InpSignalSplitRiskAcrossOrders) total*=count;
   return total;
}

void SignalAppendLabRow(SignalPaperTrade &t,double exitPrice,string status)
{
   string path=InpSignalReportFolder+"signal_lab.csv";
   int h=FileOpen(path,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE)
   {
      Print("SIGNAL LAB report open failed | err=",GetLastError());
      return;
   }
   if(FileSize(h)==0)
      FileWrite(h,"utc_time","signal_id","source_id","model","side","entry","sl","tp1","tp2","tp3","orders","total_lots","exit_price","net_pnl","status","order_step","volume_step");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),t.signalId,t.sourceId,SignalModelName(t.model),
             t.side>0?"BUY":"SELL",DoubleToString(t.entry,_Digits),DoubleToString(t.sl,_Digits),
             DoubleToString(t.tp1,_Digits),DoubleToString(t.tp2,_Digits),DoubleToString(t.tp3,_Digits),
             t.orders,DoubleToString(t.totalLots,4),DoubleToString(exitPrice,_Digits),
             DoubleToString(t.realized,2),status,t.orderStep,t.volumeStep);
   FileClose(h);
}

void SignalUpdatePaperRoulette(SignalPaperTrade &t)
{
   long sh=SignalHash(t.sourceId);
   if(t.model==1 || t.model==3)
   {
      int before=SignalModelOrderStep(sh,t.model,false);
      int next=before;
      if(t.realized>0.0) next=(before>InpSignalMaxOrderCount/2?InpSignalMaxOrderCount:before*2);
      else if(t.realized<0.0) next=MathMax(1,before-1);
      SignalSetStateStep(sh,SignalOrderStateSuffix(t.model,false),next,InpSignalMaxOrderCount);
   }
   if(t.model==2 || t.model==3)
   {
      int before=SignalModelVolumeStep(sh,t.model,false);
      int next=before;
      if(t.realized>0.0) next=MathMin(InpSignalMaxVolumeStep,before+1);
      else if(t.realized<0.0) next=MathMax(1,before-1);
      SignalSetStateStep(sh,SignalVolumeStateSuffix(t.model,false),next,InpSignalMaxVolumeStep);
   }
}

void SignalFinishPaper(int index,double exitPrice,string status,bool updateRoulette=true)
{
   if(index<0 || index>=ArraySize(g_SignalPaperTrades)) return;
   if(g_SignalPaperTrades[index].state==2) return;
   SignalPaperTrade t=g_SignalPaperTrades[index];
   if(t.remainingLots>0.0 && status!="CANCEL")
   {
      ENUM_ORDER_TYPE ot=(t.side>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
      double pl=0.0;
      if(OrderCalcProfit(ot,_Symbol,t.remainingLots,t.entry,exitPrice,pl))
         t.realized+=pl-InpSignalCommissionRTPerLot*t.remainingLots;
      t.remainingLots=0.0;
   }
   t.state=2;
   g_SignalPaperTrades[index]=t;
   SignalAppendLabRow(g_SignalPaperTrades[index],exitPrice,status);
   if(updateRoulette && status!="CANCEL") SignalUpdatePaperRoulette(g_SignalPaperTrades[index]);
   PrintFormat("SIGNAL LAB CLOSED | %s | %s | net=%.2f | %s",SignalModelName(t.model),t.signalId,t.realized,status);
}

void SignalPaperClosePart(int index,double volume,double exitPrice)
{
   if(index<0 || index>=ArraySize(g_SignalPaperTrades)) return;
   if(volume<=0.0) return;
   double closeVol=MathMin(volume,g_SignalPaperTrades[index].remainingLots);
   if(closeVol<=0.0) return;
   ENUM_ORDER_TYPE ot=(g_SignalPaperTrades[index].side>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   double pl=0.0;
   if(OrderCalcProfit(ot,_Symbol,closeVol,g_SignalPaperTrades[index].entry,exitPrice,pl))
      g_SignalPaperTrades[index].realized+=pl-InpSignalCommissionRTPerLot*closeVol;
   g_SignalPaperTrades[index].remainingLots=MathMax(0.0,g_SignalPaperTrades[index].remainingLots-closeVol);
}

bool SignalPaperExists(string signalId,int model)
{
   for(int i=0;i<ArraySize(g_SignalPaperTrades);i++)
      if(g_SignalPaperTrades[i].signalId==signalId && g_SignalPaperTrades[i].model==model) return true;
   return false;
}

void SignalAddPaperTrades(string signalId,string sourceId,int side,int kind,double entry,double sl,double tp1,double tp2,double tp3)
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   if(kind==0) entry=(side>0?tick.ask:tick.bid);
   if(entry<=0.0 || sl<=0.0 || (tp1<=0.0 && tp2<=0.0 && tp3<=0.0)) return;
   entry=NormalizeSignalPrice(entry); sl=NormalizeSignalPrice(sl);
   if(tp1>0.0) tp1=NormalizeSignalPrice(tp1);
   if(tp2>0.0) tp2=NormalizeSignalPrice(tp2);
   if(tp3>0.0) tp3=NormalizeSignalPrice(tp3);
   double baseLot=SignalBaseLot(side,entry,sl);
   if(baseLot<=0.0)
   { Print("SIGNAL LAB rejected: base lot/risk computes below tradable size."); return; }
   long sh=SignalHash(sourceId);
   for(int model=0;model<4;model++)
   {
      if(SignalPaperExists(signalId,model)) continue;
      int orders=SignalModelOrderCount(sh,model,false);
      int vstep=SignalModelVolumeStep(sh,model,false);
      double total=SignalModelTotalLots(sh,model,baseLot,false);
      if(InpSignalSplitRiskAcrossOrders)
      {
         double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
         if(minLot>0.0) orders=MathMin(orders,MathMax(1,(int)MathFloor(total/minLot+1e-8)));
      }
      int n=ArraySize(g_SignalPaperTrades);
      ArrayResize(g_SignalPaperTrades,n+1);
      g_SignalPaperTrades[n].signalId=signalId;
      g_SignalPaperTrades[n].sourceId=sourceId;
      g_SignalPaperTrades[n].model=model;
      g_SignalPaperTrades[n].side=side;
      g_SignalPaperTrades[n].kind=kind;
      g_SignalPaperTrades[n].entry=entry;
      g_SignalPaperTrades[n].sl=sl;
      g_SignalPaperTrades[n].tp1=tp1;
      g_SignalPaperTrades[n].tp2=tp2;
      g_SignalPaperTrades[n].tp3=tp3;
      g_SignalPaperTrades[n].totalLots=total;
      g_SignalPaperTrades[n].remainingLots=total;
      g_SignalPaperTrades[n].realized=0.0;
      g_SignalPaperTrades[n].orders=orders;
      g_SignalPaperTrades[n].orderStep=orders;
      g_SignalPaperTrades[n].volumeStep=vstep;
      g_SignalPaperTrades[n].stage=0;
      g_SignalPaperTrades[n].state=(kind==0?1:0);
      g_SignalPaperTrades[n].openedAt=(kind==0?TimeCurrent():0);
      PrintFormat("SIGNAL LAB NEW | %s | %s | %s %s | orders=%d | total-lot=%.4f | SL=%.*f TP1=%.*f TP2=%.*f TP3=%.*f",
                  SignalModelName(model),signalId,Symbol(),side>0?"BUY":"SELL",orders,total,_Digits,sl,_Digits,tp1,_Digits,tp2,_Digits,tp3);
   }
}

void SignalUpdatePaperById(string signalId,string action,double sl,double tp1,double tp2,double tp3)
{
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   for(int i=0;i<ArraySize(g_SignalPaperTrades);i++)
   {
      if(g_SignalPaperTrades[i].signalId!=signalId || g_SignalPaperTrades[i].state==2) continue;
      if(action=="EDIT")
      {
         if(sl>0.0) g_SignalPaperTrades[i].sl=sl;
         if(tp1>0.0) g_SignalPaperTrades[i].tp1=tp1;
         g_SignalPaperTrades[i].tp2=tp2; g_SignalPaperTrades[i].tp3=tp3;
      }
      else if(action=="BE")
      {
         g_SignalPaperTrades[i].sl=g_SignalPaperTrades[i].entry;
      }
      else if(action=="CLOSE")
      {
         double px=(g_SignalPaperTrades[i].side>0?tick.bid:tick.ask);
         SignalFinishPaper(i,px,"SOURCE_CLOSE",true);
      }
      else if(action=="CANCEL" && g_SignalPaperTrades[i].state==0)
      {
         g_SignalPaperTrades[i].remainingLots=0.0;
         SignalFinishPaper(i,0.0,"CANCEL",false);
      }
   }
}

void SignalAddLiveHash(long hash)
{
   for(int i=0;i<ArraySize(g_SignalLiveHashes);i++) if(g_SignalLiveHashes[i]==hash) return;
   int n=ArraySize(g_SignalLiveHashes); ArrayResize(g_SignalLiveHashes,n+1); g_SignalLiveHashes[n]=hash;
}

int CountSignalLivePositions(long hash=0)
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpSignalMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(hash>0 && SignalHashFromComment(PositionGetString(POSITION_COMMENT))!=hash) continue;
      count++;
   }
   return count;
}

int CountSignalLiveOrders(long hash=0)
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)!=InpSignalMagic || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if(hash>0 && SignalHashFromComment(OrderGetString(ORDER_COMMENT))!=hash) continue;
      count++;
   }
   return count;
}

double SignalLiveOpenRiskMoney()
{
   double risk=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      long magic=PositionGetInteger(POSITION_MAGIC);
      if((magic!=InpSignalMagic && magic!=InpMagic) || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      double sl=PositionGetDouble(POSITION_SL); if(sl<=0.0) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE ot=(type==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
      risk+=ActualRiskMoney(ot,PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),sl);
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0) continue;
      long magic=OrderGetInteger(ORDER_MAGIC);
      if((magic!=InpSignalMagic && magic!=InpMagic) || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      double sl=OrderGetDouble(ORDER_SL); if(sl<=0.0) continue;
      ENUM_ORDER_TYPE pending=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      ENUM_ORDER_TYPE sideType=(pending==ORDER_TYPE_BUY_LIMIT || pending==ORDER_TYPE_BUY_STOP || pending==ORDER_TYPE_BUY_STOP_LIMIT)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      risk+=ActualRiskMoney(sideType,OrderGetDouble(ORDER_VOLUME_CURRENT),OrderGetDouble(ORDER_PRICE_OPEN),sl);
   }
   return risk;
}

void SignalStoreTargets(long hash,double tp1,double tp2,double tp3)
{
   GlobalVariableSet(SignalGlobalKey(hash,"T1"),tp1);
   GlobalVariableSet(SignalGlobalKey(hash,"T2"),tp2);
   GlobalVariableSet(SignalGlobalKey(hash,"T3"),tp3);
}

void SignalPendingExpirySettings(ENUM_ORDER_TYPE_TIME &timeType,datetime &expiration)
{
   timeType=ORDER_TIME_GTC; expiration=0;
   if(InpSignalPendingExpiryMinutes<=0) return;
   long modes=SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE);
   if((modes & SYMBOL_EXPIRATION_SPECIFIED)==SYMBOL_EXPIRATION_SPECIFIED)
   { timeType=ORDER_TIME_SPECIFIED; expiration=TimeCurrent()+InpSignalPendingExpiryMinutes*60; }
   else if((modes & SYMBOL_EXPIRATION_DAY)==SYMBOL_EXPIRATION_DAY)
   { timeType=ORDER_TIME_DAY; }
   else
      Print("SIGNAL NOTE: broker has no specified/day pending expiration; local expiry requires MT5/VPS to remain running.");
}

void SignalExecuteLive(string signalId,string sourceId,int side,int kind,double entry,double sl,double tp1,double tp2,double tp3)
{
   if(g_TradingMode!=NIXO_MODE_EXTERNAL || g_EntriesPaused || !g_SignalLiveEnabled || !InpSignalLiveAllowed) return;
   if(g_Stopped || g_DailyStopped || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   { Print("SIGNAL LIVE blocked: terminal/account protection or trading permission."); return; }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   { Print("SIGNAL LIVE blocked: Signal Copy requires a Hedging account for independent signal positions and partial exits."); return; }
   if(!SignalSymbolMatches(_Symbol) || sl<=0.0 || (tp1<=0.0 && tp2<=0.0 && tp3<=0.0)) return;
   entry=NormalizeSignalPrice(entry); sl=NormalizeSignalPrice(sl);
   if(tp1>0.0) tp1=NormalizeSignalPrice(tp1);
   if(tp2>0.0) tp2=NormalizeSignalPrice(tp2);
   if(tp3>0.0) tp3=NormalizeSignalPrice(tp3);
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double marketPrice=(side>0?tick.ask:tick.bid);
   double openPrice=(kind==0?marketPrice:entry);
   if(openPrice<=0.0) return;
   if((side>0 && sl>=openPrice) || (side<0 && sl<=openPrice))
   { Print("SIGNAL LIVE rejected: stop-loss is on the wrong side of entry."); return; }
   if(side>0 && ((tp1>0.0 && tp1<=openPrice) || (tp2>0.0 && tp2<=openPrice) || (tp3>0.0 && tp3<=openPrice) ||
                 (tp1>0.0 && tp2>0.0 && tp2<=tp1) || (tp2>0.0 && tp3>0.0 && tp3<=tp2)))
   { Print("SIGNAL LIVE rejected: BUY targets have invalid order/direction."); return; }
   if(side<0 && ((tp1>0.0 && tp1>=openPrice) || (tp2>0.0 && tp2>=openPrice) || (tp3>0.0 && tp3>=openPrice) ||
                 (tp1>0.0 && tp2>0.0 && tp2>=tp1) || (tp2>0.0 && tp3>0.0 && tp3>=tp2)))
   { Print("SIGNAL LIVE rejected: SELL targets have invalid order/direction."); return; }
   if(!InpSignalAllowHedge)
   {
      ENUM_ORDER_TYPE ot=(side>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ptk=PositionGetTicket(i); if(ptk==0) continue;
         long magic=PositionGetInteger(POSITION_MAGIC);
         if((magic!=InpSignalMagic && magic!=InpMagic) || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         long pt=PositionGetInteger(POSITION_TYPE);
         if((ot==ORDER_TYPE_BUY && pt==POSITION_TYPE_SELL) || (ot==ORDER_TYPE_SELL && pt==POSITION_TYPE_BUY))
         { Print("SIGNAL LIVE blocked: opposite Nixo/signal position exists; enable InpSignalAllowHedge only on a Hedging account to allow both directions."); return; }
      }
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         ulong otk=OrderGetTicket(i); if(otk==0) continue;
         long magic=OrderGetInteger(ORDER_MAGIC);
         if((magic!=InpSignalMagic && magic!=InpMagic) || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
         ENUM_ORDER_TYPE pending=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         bool oppositePending=(side>0 && (pending==ORDER_TYPE_SELL_LIMIT || pending==ORDER_TYPE_SELL_STOP || pending==ORDER_TYPE_SELL_STOP_LIMIT)) ||
                              (side<0 && (pending==ORDER_TYPE_BUY_LIMIT || pending==ORDER_TYPE_BUY_STOP || pending==ORDER_TYPE_BUY_STOP_LIMIT));
         if(oppositePending) { Print("SIGNAL LIVE blocked: opposite Nixo/signal pending order exists."); return; }
      }
   }

   long sourceHash=SignalHash(sourceId);
   ReportRegisterSource(sourceHash,sourceId);
   int model=(int)InpSignalLiveModel;
   int count=SignalModelOrderCount(sourceHash,model,true);
   int volumeStep=SignalModelVolumeStep(sourceHash,model,true);
   double baseLot=SignalBaseLot(side,openPrice,sl);
   if(baseLot<=0.0) return;
   double volumeMultiplier=1.0+MathMax(0.0,InpSignalVolumeStepFactor)*MathMax(0,volumeStep-1);
   double totalLot=NormalizeVolumeDown(baseLot*volumeMultiplier);
   double brokerMinLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double brokerMaxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(brokerMaxLot>0.0) totalLot=MathMin(totalLot,brokerMaxLot);
   if(totalLot<=0.0 || totalLot<brokerMinLot-1e-9)
   { Print("SIGNAL LIVE blocked: volume roulette result is outside broker volume limits."); return; }
   if(InpSignalMaxOrderCount>0) count=MathMin(count,InpSignalMaxOrderCount);
   int occupied=CountSignalLivePositions()+CountSignalLiveOrders();
   if(InpSignalMaxLivePositions>0)
   {
      int slots=InpSignalMaxLivePositions-occupied;
      if(slots<=0) { Print("SIGNAL LIVE blocked: max open signal positions/orders reached."); return; }
      count=MathMin(count,slots);
   }
   if(InpSignalSplitRiskAcrossOrders)
   {
      double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      int feasible=(int)MathFloor(totalLot/minLot+1e-8);
      count=MathMin(count,MathMax(1,feasible));
   }
   if(count<1) return;
   double perOrder=NormalizeVolumeDown(InpSignalSplitRiskAcrossOrders?totalLot/count:totalLot);
   if(brokerMaxLot>0.0) perOrder=MathMin(perOrder,brokerMaxLot);
   if(perOrder<brokerMinLot-1e-9)
   { Print("SIGNAL LIVE blocked: calculated per-order volume is below broker minimum lot."); return; }
   if(InpMaxOpenRiskPct>0.0)
   {
      double unifiedOpen=OpenRiskMoney();
      double unifiedNew=ActualRiskMoney(side>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,perOrder*count,openPrice,sl);
      double unifiedCap=SelectedRiskBase()*InpMaxOpenRiskPct/100.0;
      if(unifiedOpen+unifiedNew>unifiedCap+1e-8)
      { PrintFormat("UNIFIED RISK BLOCK | open=%.2f + external new=%.2f > cap=%.2f",unifiedOpen,unifiedNew,unifiedCap); return; }
   }
   if(InpSignalMaxLiveRiskPct>0.0)
   {
      double totalRisk=SignalLiveOpenRiskMoney();
      double newRisk=ActualRiskMoney(side>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,perOrder*count,openPrice,sl);
      double cap=AccountInfoDouble(ACCOUNT_EQUITY)*InpSignalMaxLiveRiskPct/100.0;
      if(totalRisk+newRisk>cap+1e-8)
      { PrintFormat("SIGNAL LIVE risk cap: open %.2f + new %.2f > %.2f",totalRisk,newRisk,cap); return; }
   }

   long signalHash=SignalHash(signalId);
   // TP levels are managed by Nixo. A broker TP on the full basket would close
   // all child orders at TP3 and prevent the final runner from being trailed.
   double brokerTP=0.0;
   SignalStoreTargets(signalHash,tp1,tp2,tp3);
   GlobalVariableSet(SignalGlobalKey(signalHash,"SL0"),sl);
   GlobalVariableSet(SignalGlobalKey(signalHash,"LSTAGE"),0.0);
   GlobalVariableSet(SignalGlobalKey(signalHash,"LINIT"),0.0);
   GlobalVariableSet(SignalGlobalKey(signalHash,"NET"),0.0);
   GlobalVariableSet(SignalGlobalKey(signalHash,"ACTIVE"),1.0);
   GlobalVariableSet(SignalGlobalKey(signalHash,"SOURCE"),(double)sourceHash);
   GlobalVariableSet(SignalGlobalKey(signalHash,"MODEL"),(double)model);
   SignalAddLiveHash(signalHash);

   trade.SetExpertMagicNumber(InpSignalMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   string comment=StringFormat("NX503|%I64d",signalHash);
   int sentCount=0;
   ENUM_ORDER_TYPE_TIME pendingTime=ORDER_TIME_GTC;
   datetime pendingExpiration=0;
   SignalPendingExpirySettings(pendingTime,pendingExpiration);
   for(int n=0;n<count;n++)
   {
      bool sent=false;
      if(kind==0)
         sent=(side>0?trade.Buy(perOrder,_Symbol,0.0,sl,brokerTP,comment):trade.Sell(perOrder,_Symbol,0.0,sl,brokerTP,comment));
      else if(kind==1)
      {
         if(side>0 && entry<tick.ask) sent=trade.BuyLimit(perOrder,entry,_Symbol,sl,brokerTP,pendingTime,pendingExpiration,comment);
         else if(side<0 && entry>tick.bid) sent=trade.SellLimit(perOrder,entry,_Symbol,sl,brokerTP,pendingTime,pendingExpiration,comment);
      }
      else
      {
         if(side>0 && entry>tick.ask) sent=trade.BuyStop(perOrder,entry,_Symbol,sl,brokerTP,pendingTime,pendingExpiration,comment);
         else if(side<0 && entry<tick.bid) sent=trade.SellStop(perOrder,entry,_Symbol,sl,brokerTP,pendingTime,pendingExpiration,comment);
      }
      if(SignalOrderSucceeded(sent)) sentCount++;
      else PrintFormat("SIGNAL LIVE order %d/%d failed | retcode=%u %s",n+1,count,trade.ResultRetcode(),trade.ResultRetcodeDescription());
   }
   trade.SetExpertMagicNumber(InpMagic);
   if(sentCount<=0) GlobalVariableSet(SignalGlobalKey(signalHash,"ACTIVE"),0.0);
   PrintFormat("SIGNAL LIVE | %s | %s %s | model=%s | orders=%d/%d | lots/order=%.4f | total=%.4f | order-step=%d volume-step=%d | SL=%.*f TP1=%.*f TP2=%.*f TP3=%.*f",
               signalId,Symbol(),side>0?"BUY":"SELL",SignalModelName(model),sentCount,count,perOrder,perOrder*sentCount,
               SignalModelOrderStep(sourceHash,model,true),volumeStep,_Digits,sl,_Digits,tp1,_Digits,tp2,_Digits,tp3);
}

void SignalModifyLiveByHash(long hash,double sl,double tp1,double tp2,double tp3)
{
   SignalStoreTargets(hash,tp1,tp2,tp3);
   if(sl>0.0) GlobalVariableSet(SignalGlobalKey(hash,"SL0"),sl);
   trade.SetExpertMagicNumber(InpSignalMagic);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpSignalMagic || SignalHashFromComment(PositionGetString(POSITION_COMMENT))!=hash) continue;
      double oldSL=PositionGetDouble(POSITION_SL);
      // Keep the protective SL server-side; keep staged targets virtual in Nixo.
      trade.PositionModify(ticket,sl>0.0?sl:oldSL,0.0);
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)!=InpSignalMagic || SignalHashFromComment(OrderGetString(ORDER_COMMENT))!=hash) continue;
      double oldSL=OrderGetDouble(ORDER_SL),price=OrderGetDouble(ORDER_PRICE_OPEN);
      ENUM_ORDER_TYPE_TIME tt=(ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
      datetime expiry=(datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      trade.OrderModify(ticket,price,sl>0.0?sl:oldSL,0.0,tt,expiry,0.0);
   }
   trade.SetExpertMagicNumber(InpMagic);
}

void SignalMoveLiveToBE(long hash)
{
   trade.SetExpertMagicNumber(InpSignalMagic);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpSignalMagic || SignalHashFromComment(PositionGetString(POSITION_COMMENT))!=hash) continue;
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      trade.PositionModify(ticket,openPrice,PositionGetDouble(POSITION_TP));
   }
   trade.SetExpertMagicNumber(InpMagic);
}

void SignalCloseLiveByHash(long hash,bool closePositions)
{
   trade.SetExpertMagicNumber(InpSignalMagic);
   if(closePositions)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
         if(PositionGetInteger(POSITION_MAGIC)==InpSignalMagic && SignalHashFromComment(PositionGetString(POSITION_COMMENT))==hash)
            trade.PositionClose(ticket,InpSlippage);
      }
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)==InpSignalMagic && SignalHashFromComment(OrderGetString(ORDER_COMMENT))==hash)
         trade.OrderDelete(ticket);
   }
   trade.SetExpertMagicNumber(InpMagic);
}

void CancelSignalPendingOrders()
{
   trade.SetExpertMagicNumber(InpSignalMagic);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)==InpSignalMagic && OrderGetString(ORDER_SYMBOL)==_Symbol) trade.OrderDelete(ticket);
   }
   trade.SetExpertMagicNumber(InpMagic);
}

void SignalApplyEvent(string signalId,string sourceId,string action,int side,int kind,double entry,double sl,double tp1,double tp2,double tp3)
{
   long hash=SignalHash(signalId);
   if(action=="NEW")
   {
      SignalAddPaperTrades(signalId,sourceId,side,kind,entry,sl,tp1,tp2,tp3);
      SignalExecuteLive(signalId,sourceId,side,kind,entry,sl,tp1,tp2,tp3);
   }
   else if(action=="EDIT")
   {
      SignalUpdatePaperById(signalId,"EDIT",sl,tp1,tp2,tp3);
      SignalModifyLiveByHash(hash,sl,tp1,tp2,tp3);
   }
   else if(action=="BE")
   {
      SignalUpdatePaperById(signalId,"BE",sl,tp1,tp2,tp3);
      SignalMoveLiveToBE(hash);
   }
   else if(action=="CLOSE")
   {
      SignalUpdatePaperById(signalId,"CLOSE",sl,tp1,tp2,tp3);
      SignalCloseLiveByHash(hash,true);
   }
   else if(action=="CANCEL")
   {
      SignalUpdatePaperById(signalId,"CANCEL",sl,tp1,tp2,tp3);
      SignalCloseLiveByHash(hash,false);
   }
}

bool ParseBridgeSignalLine(string line, string &signalId, string &sourceId, string &action, string &symbol,
                     string &sideText, string &kindText, double &entry, double &sl, double &tp1, double &tp2, double &tp3,
                     long &signalUnix)
{
   if(StringLen(line) < 10) return false;
   string f[]; ushort sep=StringGetCharacter("|",0);
   int n=StringSplit(line,sep,f);
   if(n >= 14 && f[0] == "NIXO_SIG_V1")
   {
      signalId = f[2]; sourceId = f[3]; action = f[4]; symbol = f[5]; sideText = f[6]; kindText = f[7];
      entry = StringToDouble(f[8]); sl = StringToDouble(f[9]); tp1 = StringToDouble(f[10]); tp2 = StringToDouble(f[11]); tp3 = StringToDouble(f[12]);
      signalUnix = (long)StringToInteger(f[13]);
      return true;
   }
   string compact=line;
   StringReplace(compact, "\r", "");
   StringReplace(compact, "\n", "");
   StringReplace(compact, ",", " ");
   StringReplace(compact, "[", " ");
   StringReplace(compact, "]", " ");
   StringReplace(compact, "(", " ");
   StringReplace(compact, ")", " ");
   StringReplace(compact, "_", " ");
   StringReplace(compact, "  ", " ");
   while(StringFind(compact, "  ") >= 0) StringReplace(compact, "  ", " ");
   string parts[]; ushort sp = StringGetCharacter(" ",0);
   int count = StringSplit(compact, sp, parts);
   if(count < 7) return false;
   if(parts[0] == "BUY" || parts[0] == "SELL")
   {
      sideText = parts[0]; action = "NEW";
      sourceId = (StringLen(InpTelegramSourceName)>0 ? InpTelegramSourceName : "TG_PUBLIC");
      symbol = parts[1];
      int idx = 2;
      entry = StringToDouble(parts[idx++]);
      sl = StringToDouble(parts[idx++]);
      tp1 = (idx < count ? StringToDouble(parts[idx++]) : 0.0);
      tp2 = (idx < count ? StringToDouble(parts[idx++]) : 0.0);
      tp3 = (idx < count ? StringToDouble(parts[idx++]) : 0.0);
      signalId = StringFormat("TG_%s_%d", symbol, (int)TimeCurrent());
      signalUnix = (long)TimeGMT();
      kindText = "MARKET";
      return true;
   }
   return false;
}

void ProcessOneSignalFile(string fileName)
{
   string path=InpSignalInboxFolder+fileName;
   int h=FileOpen(path,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE) return;
   string line=FileReadString(h); FileClose(h);
   FileDelete(path,FILE_COMMON);
   if(StringLen(line)<10) return;
   string signalId="", sourceId="", action="", symbol="", sideText="", kindText="";
   double entry=0.0, sl=0.0, tp1=0.0, tp2=0.0, tp3=0.0;
   long signalUnix=0;
   if(!ParseBridgeSignalLine(line, signalId, sourceId, action, symbol, sideText, kindText, entry, sl, tp1, tp2, tp3, signalUnix))
   {
      string f[]; ushort sep=StringGetCharacter("|",0);
      int n=StringSplit(line,sep,f);
      if(n<14 || f[0]!="NIXO_SIG_V1")
      { Print("SIGNAL BRIDGE rejected malformed event file: ",fileName); return; }
   }
   if(signalId == "")
   {
      string f[]; ushort sep=StringGetCharacter("|",0);
      int n=StringSplit(line,sep,f);
      if(n<14 || f[0]!="NIXO_SIG_V1") { Print("SIGNAL BRIDGE rejected malformed event file: ",fileName); return; }
      signalId = f[2]; sourceId = f[3]; action = f[4]; symbol = f[5]; sideText = f[6]; kindText = f[7];
      entry = StringToDouble(f[8]); sl = StringToDouble(f[9]); tp1 = StringToDouble(f[10]); tp2 = StringToDouble(f[11]); tp3 = StringToDouble(f[12]);
      signalUnix = (long)StringToInteger(f[13]);
   }
   long eventHash=SignalHash(signalId + StringFormat("_%d", (int)TimeCurrent()));
   string seenKey=SignalGlobalKey(eventHash,"SEEN");
   if(GlobalVariableCheck(seenKey)) return;
   GlobalVariableSet(seenKey,(double)TimeCurrent());
   if(!SignalSymbolMatches(symbol))
   { PrintFormat("SIGNAL BRIDGE ignored symbol=%s on chart=%s",symbol,_Symbol); return; }
   int side=(sideText=="BUY"?1:(sideText=="SELL"?-1:0));
   int kind=(kindText=="LIMIT"?1:(kindText=="STOP"?2:0));
   if(action=="NEW" && InpBridgeMaxAgeSeconds>0 && signalUnix>0 && (long)TimeGMT()-signalUnix>InpBridgeMaxAgeSeconds)
   { PrintFormat("SIGNAL BRIDGE ignored stale feed signal | id=%s | age=%I64d sec",signalId,(long)TimeGMT()-signalUnix); return; }
   if(side==0 || (action!="BE" && (sl<=0.0 || (tp1<=0.0 && tp2<=0.0 && tp3<=0.0))))
   { PrintFormat("SIGNAL BRIDGE rejected incomplete signal | %s",signalId); return; }
   string newKey=SignalGlobalKey(SignalHash(signalId),"NEW");
   if(action=="NEW" && GlobalVariableCheck(newKey)) return;
   if(action=="NEW") GlobalVariableSet(newKey,(double)TimeCurrent());
   PrintFormat("SIGNAL EVENT | %s | source=%s | %s %s | entry=%.*f SL=%.*f TP1=%.*f TP2=%.*f TP3=%.*f",
               action,sourceId,symbol,sideText,_Digits,entry,_Digits,sl,_Digits,tp1,_Digits,tp2,_Digits,tp3);
   SignalApplyEvent(signalId,sourceId,action,side,kind,entry,sl,tp1,tp2,tp3);
}

void ProcessSignalInbox()
{
   if(!InpSignalLabEnabled) return;
   string fileName="";
   long handle=FileFindFirst(InpSignalInboxFolder+"*.sig",fileName,FILE_COMMON);
   if(handle==INVALID_HANDLE) return;
   int processed=0;
   do
   {
      ProcessOneSignalFile(fileName);
      processed++;
      if(processed>=50) break;
   } while(FileFindNext(handle,fileName));
   FileFindClose(handle);
}
void UpdateSignalPaperTrades()
{
   if(ArraySize(g_SignalPaperTrades)<=0) return;
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double slip=MathMax(0,InpSignalPaperSlippagePoints)*_Point;
   for(int i=0;i<ArraySize(g_SignalPaperTrades);i++)
   {
      if(g_SignalPaperTrades[i].state==2) continue;
      SignalPaperTrade t=g_SignalPaperTrades[i];
      double trigger=(t.side>0?tick.ask:tick.bid);
      if(t.state==0)
      {
         bool filled=false;
         if(t.kind==1) filled=(t.side>0?trigger<=t.entry:trigger>=t.entry);
         else if(t.kind==2) filled=(t.side>0?trigger>=t.entry:trigger<=t.entry);
         if(!filled) continue;
         g_SignalPaperTrades[i].state=1;
         g_SignalPaperTrades[i].openedAt=TimeCurrent();
         PrintFormat("SIGNAL LAB PENDING FILLED | %s | %s at %.*f",SignalModelName(t.model),t.signalId,_Digits,t.entry);
         t=g_SignalPaperTrades[i];
      }
      double exitPx=(t.side>0?tick.bid:tick.ask);
      bool slHit=(t.side>0?exitPx<=t.sl:exitPx>=t.sl);
      if(slHit)
      {
         double stopExit=(t.side>0?t.sl-slip:t.sl+slip);
         SignalFinishPaper(i,stopExit,"SL",true);
         continue;
      }

      double targets[3]={0.0,0.0,0.0};
      int targetCount=0;
      if(t.tp1>0.0) targets[targetCount++]=t.tp1;
      if(t.tp2>0.0) targets[targetCount++]=t.tp2;
      if(t.tp3>0.0) targets[targetCount++]=t.tp3;

      if(t.stage>=3)
      {
         double atr=GetATR(1);
         if(atr>0.0 && InpSignalRunnerEnabled && t.remainingLots>0.0 && targetCount>=3)
         {
            double trail=(t.side>0?exitPx-InpSignalRunnerTrailATR*atr:exitPx+InpSignalRunnerTrailATR*atr);
            double lock=targets[1];
            if(t.side>0) t.sl=MathMax(t.sl,MathMax(lock,trail));
            else t.sl=MathMin(t.sl,MathMin(lock,trail));
            g_SignalPaperTrades[i].sl=t.sl;
         }
         continue;
      }
      if(targetCount<=0 || t.stage>=targetCount) continue;

      double target=targets[t.stage];
      double closePct=100.0;
      if(targetCount>=2 && t.stage==0) closePct=InpSignalTP1ClosePct;
      else if(targetCount>=3 && t.stage==1) closePct=InpSignalTP2ClosePct;
      else if(targetCount>=3 && t.stage==2)
         closePct=(InpSignalRunnerEnabled && SignalRunnerVolumeEligible(t.totalLots)?InpSignalTP3ClosePct:100.0);

      bool tpHit=(t.side>0?exitPx>=target:exitPx<=target);
      if(!tpHit) continue;
      double closeVol=(closePct>=99.99?t.remainingLots:NormalizeVolumeDown(t.remainingLots*closePct/100.0));
      if(closeVol>t.remainingLots) closeVol=t.remainingLots;
      double tpExit=(t.side>0?target-slip:target+slip);
      if(closePct>=99.99)
         SignalPaperClosePart(i,t.remainingLots,tpExit);
      else if(closeVol>=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)-1e-9 &&
              t.remainingLots-closeVol>=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)-1e-9)
         SignalPaperClosePart(i,closeVol,tpExit);
      else if(t.stage>=2)
      {
         // At TP3, if broker volume limits cannot leave a runner, close the remainder.
         SignalPaperClosePart(i,t.remainingLots,tpExit);
         closePct=100.0;
      }
      else
      {
         // At TP1/TP2 retain the position, advance protection, and try at the next target.
         PrintFormat("SIGNAL LAB TP%d partial skipped: below broker volume constraints; remainder retained.",t.stage+1);
         closeVol=0.0;
      }
      g_SignalPaperTrades[i].stage++;
      bool runnerStarted=(g_SignalPaperTrades[i].stage>=3 && closePct<99.99 && g_SignalPaperTrades[i].remainingLots>1e-8 && targetCount>=3);
      if(runnerStarted)
      {
         g_SignalPaperTrades[i].sl=targets[1];
         PrintFormat("SIGNAL LAB RUNNER | %s | %s | remainder=%.4f",SignalModelName(t.model),t.signalId,g_SignalPaperTrades[i].remainingLots);
      }
      else if(g_SignalPaperTrades[i].remainingLots<=1e-8 || g_SignalPaperTrades[i].stage>=targetCount)
      {
         SignalFinishPaper(i,tpExit,"TP",true);
      }
   }
}

double SignalCloseBasketVolume(long hash,double desiredVolume,bool closeAll)
{
   double closed=0.0;
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) step=minLot;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpSignalMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long positionHash=SignalHashFromComment(PositionGetString(POSITION_COMMENT));
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(positionHash<=0 && GlobalVariableCheck(SignalGlobalKey((long)pid,"HASH")))
         positionHash=(long)GlobalVariableGet(SignalGlobalKey((long)pid,"HASH"));
      if(positionHash!=hash) continue;
      double current=PositionGetDouble(POSITION_VOLUME);
      double left=MathMax(0.0,desiredVolume-closed);
      if(!closeAll && left<minLot-step*0.25) break;
      double closeVol=closeAll?current:MathMin(current,NormalizeVolumeDown(left));
      bool full=(closeVol>=current-step*0.25);
      if(!full && (closeVol<minLot-step*0.25 || current-closeVol<minLot-step*0.25))
      {
         if(closeAll || current<=left+step*0.25) { closeVol=current; full=true; }
         else continue;
      }
      bool ok=(full?trade.PositionClose(ticket,InpSlippage):trade.PositionClosePartial(ticket,closeVol,InpSlippage));
      if(SignalOrderSucceeded(ok))
      {
         double actual=trade.ResultVolume();
         if(actual<=0.0) actual=closeVol;
         closed+=actual;
         PrintFormat("SIGNAL BASKET PARTIAL | hash=%I64d | ticket=%I64u | requested=%.4f | filled=%.4f | full=%s",hash,ticket,closeVol,actual,full?"YES":"NO");
      }
      else
      {
         PrintFormat("SIGNAL BASKET PARTIAL FAILED | ticket=%I64u | volume=%.4f | ret=%u %s",ticket,closeVol,trade.ResultRetcode(),trade.ResultRetcodeDescription());
         return -1.0;
      }
      if(!closeAll && closed>=desiredVolume-step*0.25) break;
   }
   return closed;
}

void SignalProtectLiveBasket(long hash,int completedStage,double originalSL)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpSignalMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long ph=SignalHashFromComment(PositionGetString(POSITION_COMMENT));
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(ph<=0 && GlobalVariableCheck(SignalGlobalKey((long)pid,"HASH"))) ph=(long)GlobalVariableGet(SignalGlobalKey((long)pid,"HASH"));
      if(ph!=hash) continue;
      long ptype=PositionGetInteger(POSITION_TYPE);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL=PositionGetDouble(POSITION_SL);
      double desired=currentSL;
      if(completedStage==1 && originalSL>0.0)
         desired=(ptype==POSITION_TYPE_BUY ? open-(open-originalSL)*0.50 : open+(originalSL-open)*0.50);
      else if(completedStage==2)
         desired=open;
      if(desired>0.0) MovePositionSL(ticket,ptype,desired,0.0);
   }
}

void SignalTrailRunner(long hash,double lockPrice)
{
   double atr=GetATR(1);
   if(atr<=0.0 || InpSignalRunnerTrailATR<=0.0) return;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpSignalMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long ph=SignalHashFromComment(PositionGetString(POSITION_COMMENT));
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(ph<=0 && GlobalVariableCheck(SignalGlobalKey((long)pid,"HASH"))) ph=(long)GlobalVariableGet(SignalGlobalKey((long)pid,"HASH"));
      if(ph!=hash) continue;
      long ptype=PositionGetInteger(POSITION_TYPE);
      double currentSL=PositionGetDouble(POSITION_SL);
      double desired=0.0;
      if(ptype==POSITION_TYPE_BUY)
      {
         double trail=bid-InpSignalRunnerTrailATR*atr;
         desired=(lockPrice>0.0?MathMax(lockPrice,trail):trail);
         if(currentSL>0.0) desired=MathMax(currentSL,desired);
      }
      else
      {
         double trail=ask+InpSignalRunnerTrailATR*atr;
         desired=(lockPrice>0.0?MathMin(lockPrice,trail):trail);
         if(currentSL>0.0) desired=MathMin(currentSL,desired);
      }
      if(desired>0.0) MovePositionSL(ticket,ptype,desired,0.0);
   }
}
void ManageOneSignalLiveBasket(long hash)
{
   double tp1=GlobalVariableCheck(SignalGlobalKey(hash,"T1"))?GlobalVariableGet(SignalGlobalKey(hash,"T1")):0.0;
   double tp2=GlobalVariableCheck(SignalGlobalKey(hash,"T2"))?GlobalVariableGet(SignalGlobalKey(hash,"T2")):0.0;
   double tp3=GlobalVariableCheck(SignalGlobalKey(hash,"T3"))?GlobalVariableGet(SignalGlobalKey(hash,"T3")):0.0;
   string stageKey=SignalGlobalKey(hash,"LSTAGE");
   int stage=GlobalVariableCheck(stageKey)?(int)GlobalVariableGet(stageKey):0;
   double initial=GlobalVariableCheck(SignalGlobalKey(hash,"LINIT"))?GlobalVariableGet(SignalGlobalKey(hash,"LINIT")):0.0;
   double originalSL=GlobalVariableCheck(SignalGlobalKey(hash,"SL0"))?GlobalVariableGet(SignalGlobalKey(hash,"SL0")):0.0;
   double remaining=0.0;
   bool buy=false,found=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpSignalMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long ph=SignalHashFromComment(PositionGetString(POSITION_COMMENT));
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(ph<=0 && GlobalVariableCheck(SignalGlobalKey((long)pid,"HASH"))) ph=(long)GlobalVariableGet(SignalGlobalKey((long)pid,"HASH"));
      if(ph!=hash) continue;
      double positionTP=PositionGetDouble(POSITION_TP);
      if(positionTP>0.0)
      {
         trade.SetExpertMagicNumber(InpSignalMagic);
         if(!trade.PositionModify(ticket,PositionGetDouble(POSITION_SL),0.0))
            PrintFormat("SIGNAL TP SAFETY: failed to clear legacy full-position TP | ticket=%I64u | %u %s",ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      }
      remaining+=PositionGetDouble(POSITION_VOLUME);
      buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      found=true;
   }
   if(!found || remaining<=0.0) return;
   if(initial<=0.0) { initial=remaining; GlobalVariableSet(SignalGlobalKey(hash,"LINIT"),initial); }

   // If part of a multi-order pending basket is still waiting, do not advance its TP stages yet.
   // This prevents early fills being partially closed before the remaining sibling orders fill/expire.
   if(CountSignalLiveOrders(hash)>0) return;

   double targets[3]={0.0,0.0,0.0};
   int targetCount=0;
   if(tp1>0.0) targets[targetCount++]=tp1;
   if(tp2>0.0) targets[targetCount++]=tp2;
   if(tp3>0.0) targets[targetCount++]=tp3;
   if(targetCount<=0) return;

   // Runner phase: the third target has been reached and half of remaining volume was closed.
   if(stage>=3)
   {
      if(targetCount>=3 && InpSignalRunnerEnabled)
         SignalTrailRunner(hash,targets[1]);
      return;
   }
   if(stage>=targetCount) return;

   double target=targets[stage];
   double closePct=100.0;
   if(targetCount>=2 && stage==0) closePct=InpSignalTP1ClosePct;
   else if(targetCount>=3 && stage==1) closePct=InpSignalTP2ClosePct;
   else if(targetCount>=3 && stage==2)
   {
      bool runnerCanBeExact=(InpSignalRunnerEnabled && SignalRunnerVolumeEligible(initial));
      closePct=(runnerCanBeExact?InpSignalTP3ClosePct:100.0);
      if(InpSignalRunnerEnabled && !runnerCanBeExact)
         PrintFormat("SIGNAL RUNNER NOT AVAILABLE | hash=%I64d | initial volume %.4f cannot be split into exact eighths for this broker; TP3 will close the remainder.",hash,initial);
   }

   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double exitPx=(buy?tick.bid:tick.ask);
   bool hit=(buy?exitPx>=target:exitPx<=target);
   if(!hit) return;

   trade.SetExpertMagicNumber(InpSignalMagic);
   double closed=0.0;
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double volStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(volStep<=0.0) volStep=minLot;
   bool partialStage=(closePct<99.99);
   if(!partialStage)
   {
      closed=SignalCloseBasketVolume(hash,remaining,true);
      if(closed<0.0 || CountSignalLivePositions(hash)>0) return;
   }
   else
   {
      // Persist the requested quantity so an incomplete broker fill is resumed, not recalculated.
      string reqStageKey=SignalGlobalKey(hash,"LREQST");
      string reqKey=SignalGlobalKey(hash,"LREQ");
      string doneKey=SignalGlobalKey(hash,"LDONE");
      double wanted=0.0;
      if(!GlobalVariableCheck(reqStageKey) || (int)GlobalVariableGet(reqStageKey)!=stage)
      {
         wanted=NormalizeVolumeDown(remaining*closePct/100.0);
         if(wanted<minLot-volStep*0.25 || remaining-wanted<minLot-volStep*0.25)
         {
            if(stage>=2)
            {
               // At TP3, close all remaining rather than leave a sub-minimum runner.
               closed=SignalCloseBasketVolume(hash,remaining,true);
               if(closed<0.0 || CountSignalLivePositions(hash)>0) return;
               closePct=100.0;
               partialStage=false;
            }
            else
            {
               PrintFormat("SIGNAL TP%d partial skipped: broker volume constraints prevent an exact partial; keeping remainder for the next target.",stage+1);
               GlobalVariableSet(stageKey,(double)(stage+1));
               SignalProtectLiveBasket(hash,stage+1,originalSL);
               trade.SetExpertMagicNumber(InpMagic);
               return;
            }
         }
         else
         {
            GlobalVariableSet(reqStageKey,(double)stage);
            GlobalVariableSet(reqKey,wanted);
            GlobalVariableSet(doneKey,0.0);
         }
      }
      if(partialStage)
      {
         wanted=GlobalVariableGet(reqKey);
         double already=GlobalVariableGet(doneKey);
         double left=MathMax(0.0,wanted-already);
         if(left>volStep*0.25)
         {
            closed=SignalCloseBasketVolume(hash,left,false);
            if(closed<0.0) return;
            already+=closed;
            GlobalVariableSet(doneKey,already);
         }
         if(already+volStep*0.25<wanted)
         {
            PrintFormat("SIGNAL TP%d partial close pending | target=%.4f completed=%.4f; retrying remaining volume.",stage+1,wanted,already);
            return;
         }
         GlobalVariableDel(reqStageKey);
         GlobalVariableDel(reqKey);
         GlobalVariableDel(doneKey);
      }
   }

   GlobalVariableSet(stageKey,(double)(stage+1));
   if(stage+1==1 || stage+1==2) SignalProtectLiveBasket(hash,stage+1,originalSL);
   if(stage+1>=3 && partialStage)
      PrintFormat("SIGNAL TP3 RUNNER ACTIVE | hash=%I64d | remaining-volume~%.4f | trail=%.2f ATR",hash,MathMax(0.0,remaining-closed),InpSignalRunnerTrailATR);
   else
      PrintFormat("SIGNAL TP%d BASKET EXECUTED | hash=%I64d | closed=%.4f | remaining-before=%.4f",stage+1,hash,closed,remaining);
   trade.SetExpertMagicNumber(InpMagic);
}

void ManageSignalLivePositions()
{
   trade.SetExpertMagicNumber(InpSignalMagic);
   long hashes[];
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpSignalMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long hash=SignalHashFromComment(PositionGetString(POSITION_COMMENT));
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(hash<=0 && GlobalVariableCheck(SignalGlobalKey((long)pid,"HASH"))) hash=(long)GlobalVariableGet(SignalGlobalKey((long)pid,"HASH"));
      if(hash<=0) continue;
      SignalAddLiveHash(hash); // restore roulette batch tracking after terminal restart
      bool seen=false; for(int j=0;j<ArraySize(hashes);j++) if(hashes[j]==hash) { seen=true; break; }
      if(!seen) { int n=ArraySize(hashes); ArrayResize(hashes,n+1); hashes[n]=hash; }
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)!=InpSignalMagic || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      long hash=SignalHashFromComment(OrderGetString(ORDER_COMMENT));
      if(hash<=0) continue;
      SignalAddLiveHash(hash);
      double oldTP=OrderGetDouble(ORDER_TP);
      if(oldTP>0.0)
      {
         double price=OrderGetDouble(ORDER_PRICE_OPEN),oldSL=OrderGetDouble(ORDER_SL);
         ENUM_ORDER_TYPE_TIME tt=(ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
         datetime expiry=(datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
         trade.SetExpertMagicNumber(InpSignalMagic);
         trade.OrderModify(ticket,price,oldSL,0.0,tt,expiry,0.0);
      }
   }
   for(int i=0;i<ArraySize(hashes);i++) ManageOneSignalLiveBasket(hashes[i]);
   trade.SetExpertMagicNumber(InpMagic);
}

void FinalizeSignalLiveBatches()
{
   for(int i=ArraySize(g_SignalLiveHashes)-1;i>=0;i--)
   {
      long hash=g_SignalLiveHashes[i];
      if(CountSignalLivePositions(hash)>0 || CountSignalLiveOrders(hash)>0) continue;
      string activeKey=SignalGlobalKey(hash,"ACTIVE");
      if(GlobalVariableCheck(activeKey) && GlobalVariableGet(activeKey)>0.5)
      {
         double net=GlobalVariableCheck(SignalGlobalKey(hash,"NET"))?GlobalVariableGet(SignalGlobalKey(hash,"NET")):0.0;
         long sourceHash=(long)(GlobalVariableCheck(SignalGlobalKey(hash,"SOURCE"))?GlobalVariableGet(SignalGlobalKey(hash,"SOURCE")):0);
         int model=(int)(GlobalVariableCheck(SignalGlobalKey(hash,"MODEL"))?GlobalVariableGet(SignalGlobalKey(hash,"MODEL")):InpSignalLiveModel);
         if(model==1 || model==3)
         {
            int step=SignalModelOrderStep(sourceHash,model,true);
            int next=step;
            if(net>0.0) next=(step>InpSignalMaxOrderCount/2?InpSignalMaxOrderCount:step*2);
            else if(net<0.0) next=MathMax(1,step-1);
            SignalSetStateStep(sourceHash,SignalOrderStateSuffix(model,true),next,InpSignalMaxOrderCount);
         }
         if(model==2 || model==3)
         {
            int step=SignalModelVolumeStep(sourceHash,model,true);
            int next=step;
            if(net>0.0) next=MathMin(InpSignalMaxVolumeStep,step+1);
            else if(net<0.0) next=MathMax(1,step-1);
            SignalSetStateStep(sourceHash,SignalVolumeStateSuffix(model,true),next,InpSignalMaxVolumeStep);
         }
         PrintFormat("SIGNAL LIVE ROULETTE | hash=%I64d | net=%.2f | model=%s",hash,net,SignalModelName(model));
         GlobalVariableSet(activeKey,0.0);
      }
      ArrayRemove(g_SignalLiveHashes,i,1);
   }
}

void ExpireSignalPendingOrders()
{
   if(InpSignalPendingExpiryMinutes<=0) return;
   trade.SetExpertMagicNumber(InpSignalMagic);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)!=InpSignalMagic || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      datetime setup=(datetime)OrderGetInteger(ORDER_TIME_SETUP);
      if(setup>0 && TimeCurrent()-setup>=InpSignalPendingExpiryMinutes*60)
      {
         PrintFormat("SIGNAL PENDING EXPIRED | order=%I64u",ticket);
         trade.OrderDelete(ticket);
      }
   }
   trade.SetExpertMagicNumber(InpMagic);
}

void SignalAddRealizedDeal(const MqlTradeTransaction &trans)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0 || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpSignalMagic || HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   ulong pid=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   string c=HistoryDealGetString(trans.deal,DEAL_COMMENT);
   long hash=SignalHashFromComment(c);
   if(hash<=0 && pid>0 && GlobalVariableCheck(SignalGlobalKey((long)pid,"HASH")))
      hash=(long)GlobalVariableGet(SignalGlobalKey((long)pid,"HASH"));
   if(hash<=0) return;
   if(entry==DEAL_ENTRY_IN)
   {
      GlobalVariableSet(SignalGlobalKey((long)pid,"HASH"),(double)hash);
      double dealVol=HistoryDealGetDouble(trans.deal,DEAL_VOLUME);
      double prior=GlobalVariableCheck(SignalGlobalKey(hash,"LINIT"))?GlobalVariableGet(SignalGlobalKey(hash,"LINIT")):0.0;
      GlobalVariableSet(SignalGlobalKey(hash,"LINIT"),prior+dealVol);
      double valuePrior=GlobalVariableCheck(SignalGlobalKey(hash,"ENTRYVAL"))?GlobalVariableGet(SignalGlobalKey(hash,"ENTRYVAL")):0.0;
      GlobalVariableSet(SignalGlobalKey(hash,"ENTRYVAL"),valuePrior+dealVol*HistoryDealGetDouble(trans.deal,DEAL_PRICE));
      SignalAddLiveHash(hash);
   }
   double net=HistoryDealGetDouble(trans.deal,DEAL_COMMISSION)+HistoryDealGetDouble(trans.deal,DEAL_FEE);
   if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
      net+=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+HistoryDealGetDouble(trans.deal,DEAL_SWAP);
   string netKey=SignalGlobalKey(hash,"NET");
   double old=GlobalVariableCheck(netKey)?GlobalVariableGet(netKey):0.0;
   GlobalVariableSet(netKey,old+net);
}


//==================================================================
// v5.04 TRADE REGISTRY + ADVANCED REPORT EXPORT
//==================================================================
string ReportMetaKey(ulong positionId,string field)
{
   return StringFormat("NXR_%I64d_%I64d_%I64u_%s",AccountInfoInteger(ACCOUNT_LOGIN),InpMagic,positionId,field);
}

string ReportPendingKey(ulong orderTicket,string field)
{
   return GVKey("RPT_PEND_"+(string)orderTicket+"_"+field);
}

void ReportSnapshotPendingOrder(ulong orderTicket,int mode,int strategyId,double plannedRR)
{
   if(orderTicket==0) return;
   GlobalVariableSet(ReportPendingKey(orderTicket,"MODE"),(double)mode);
   GlobalVariableSet(ReportPendingKey(orderTicket,"STRAT"),(double)strategyId);
   GlobalVariableSet(ReportPendingKey(orderTicket,"TP1"),g_TP1R);
   GlobalVariableSet(ReportPendingKey(orderTicket,"TP2"),g_TP2R);
   GlobalVariableSet(ReportPendingKey(orderTicket,"ANCHOR"),plannedRR);
   GlobalVariableSet(ReportPendingKey(orderTicket,"RATR"),g_RunnerTrailATR);
   GlobalVariableSet(ReportPendingKey(orderTicket,"BE"),g_UseBE?1.0:0.0);
   GlobalVariableSet(ReportPendingKey(orderTicket,"BER"),InpBE_R);
   GlobalVariableSet(ReportPendingKey(orderTicket,"MULTI"),UseStagedTP()?1.0:0.0);
   GlobalVariableSet(ReportPendingKey(orderTicket,"TIME"),(double)InpTimeStopBars);
   GlobalVariableSet(ReportPendingKey(orderTicket,"TIMEMIN"),InpTimeStopMinR);
}

void ReportRegisterSource(long sourceHash,string sourceId)
{
   if(sourceHash<=0 || StringLen(sourceId)==0) return;
   FolderCreate("NixoReports",FILE_COMMON);
   int h=FileOpen("NixoReports\\source_registry.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) { PrintFormat("REPORT SOURCE REGISTRY OPEN FAILED | error=%d",GetLastError()); return; }
   FileSeek(h,0,SEEK_END);
   FileWrite(h,(string)sourceHash,sourceId);
   FileClose(h);
}

int ReportStrategyFromComment(string comment)
{
   int p=StringFind(comment,"|S");
   if(p<0) return -1;
   int e=StringFind(comment,"|",p+1);
   if(e<0) return -1;
   string v=StringSubstr(comment,p+2,e-(p+2));
   return (int)StringToInteger(v);
}

void ReportCaptureEntryDeal(ulong deal,ulong orderTicket)
{
   if(deal==0 || !HistoryDealSelect(deal)) return;
   long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
   if(magic!=InpMagic && magic!=InpSignalMagic) return;
   long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT) return;
   ulong pid=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   if(pid==0) return;
   string comment=HistoryDealGetString(deal,DEAL_COMMENT);
   int mode=(magic==InpSignalMagic?NIXO_MODE_EXTERNAL:NIXO_MODE_STRATEGY);
   int strat=(magic==InpSignalMagic?-1:g_Strategy);
   long sourceHash=0;
   long signalHash=(magic==InpSignalMagic?SignalHashFromComment(comment):0);
   double initialSL=0.0, plannedRR=(magic==InpSignalMagic?0.0:g_TPAnchorR);
   if(magic==InpMagic && (StringFind(comment,"|M|")>=0 || StringFind(comment,"MANUAL")>=0))
   { mode=NIXO_MODE_MANUAL; strat=ReportStrategyFromComment(comment); }
   else if(magic==InpMagic) strat=ReportStrategyFromComment(comment)>=0?ReportStrategyFromComment(comment):g_Strategy;
   if(magic==InpSignalMagic && signalHash>0)
   {
      if(GlobalVariableCheck(SignalGlobalKey(signalHash,"SOURCE"))) sourceHash=(long)GlobalVariableGet(SignalGlobalKey(signalHash,"SOURCE"));
      if(GlobalVariableCheck(SignalGlobalKey(signalHash,"SL0"))) initialSL=GlobalVariableGet(SignalGlobalKey(signalHash,"SL0"));
      double t3=GlobalVariableCheck(SignalGlobalKey(signalHash,"T3"))?GlobalVariableGet(SignalGlobalKey(signalHash,"T3")):0.0;
      double ep=HistoryDealGetDouble(deal,DEAL_PRICE);
      if(initialSL>0.0 && t3>0.0) plannedRR=MathAbs(t3-ep)/MathAbs(ep-initialSL);
   }
   // Pending orders carry a full settings snapshot from submission time.
   if(orderTicket>0 && GlobalVariableCheck(ReportPendingKey(orderTicket,"MODE")))
   {
      mode=(int)GlobalVariableGet(ReportPendingKey(orderTicket,"MODE"));
      strat=(int)GlobalVariableGet(ReportPendingKey(orderTicket,"STRAT"));
      plannedRR=GlobalVariableGet(ReportPendingKey(orderTicket,"ANCHOR"));
      string fields[9]={"TP1","TP2","RATR","BE","BER","MULTI","ANCHOR","TIME","TIMEMIN"};
      string dest[9]={"TP1","TP2","RATR","BE","BER","MULTI","A","TIME","TIMEMIN"};
      for(int i=0;i<9;i++)
      {
         string sk=ReportPendingKey(orderTicket,fields[i]);
         if(GlobalVariableCheck(sk)) GlobalVariableSet(PositionStateKey(pid,dest[i]),GlobalVariableGet(sk));
      }
   }
   // Restore exact entry snapshot written by the order path before estimating fallbacks.
   if(magic==InpMagic)
   {
      if(GlobalVariableCheck(PositionStateKey(pid,"SL0"))) initialSL=GlobalVariableGet(PositionStateKey(pid,"SL0"));
      if(GlobalVariableCheck(PositionStateKey(pid,"RR0"))) plannedRR=GlobalVariableGet(PositionStateKey(pid,"RR0"));
   }
   // Capture the currently active server SL when the position is available.
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER)!=pid) continue;
      if(initialSL<=0.0) initialSL=PositionGetDouble(POSITION_SL);
      break;
   }
   double price=HistoryDealGetDouble(deal,DEAL_PRICE);
   double vol=HistoryDealGetDouble(deal,DEAL_VOLUME);
   long dtype=HistoryDealGetInteger(deal,DEAL_TYPE);
   ENUM_ORDER_TYPE ot=(dtype==DEAL_TYPE_SELL?ORDER_TYPE_SELL:ORDER_TYPE_BUY);
   double risk=0.0;
   string sym=HistoryDealGetString(deal,DEAL_SYMBOL);
   if(initialSL>0.0) { double pl=0.0; if(OrderCalcProfit(ot,sym,vol,price,initialSL,pl)) risk=MathAbs(pl)+EstimateRoundTurnCommissionPerLot()*vol; }
   if(magic==InpMagic && GlobalVariableCheck(PositionStateKey(pid,"RISK0"))) risk=GlobalVariableGet(PositionStateKey(pid,"RISK0"));
   GlobalVariableSet(ReportMetaKey(pid,"MODE"),(double)mode);
   GlobalVariableSet(ReportMetaKey(pid,"STRAT"),(double)strat);
   GlobalVariableSet(ReportMetaKey(pid,"SOURCE"),(double)sourceHash);
   GlobalVariableSet(ReportMetaKey(pid,"SIGNAL"),(double)signalHash);
   GlobalVariableSet(ReportMetaKey(pid,"SL0"),initialSL);
   GlobalVariableSet(ReportMetaKey(pid,"RISK"),risk);
   GlobalVariableSet(ReportMetaKey(pid,"RR"),plannedRR);
   if(magic==InpMagic)
   {
      if(!GlobalVariableCheck(PositionStateKey(pid,"TP1"))) GlobalVariableSet(PositionStateKey(pid,"TP1"),g_TP1R);
      if(!GlobalVariableCheck(PositionStateKey(pid,"TP2"))) GlobalVariableSet(PositionStateKey(pid,"TP2"),g_TP2R);
      if(!GlobalVariableCheck(PositionStateKey(pid,"RATR"))) GlobalVariableSet(PositionStateKey(pid,"RATR"),g_RunnerTrailATR);
      if(!GlobalVariableCheck(PositionStateKey(pid,"BE"))) GlobalVariableSet(PositionStateKey(pid,"BE"),g_UseBE?1.0:0.0);
      if(!GlobalVariableCheck(PositionStateKey(pid,"BER"))) GlobalVariableSet(PositionStateKey(pid,"BER"),InpBE_R);
      if(!GlobalVariableCheck(PositionStateKey(pid,"MULTI"))) GlobalVariableSet(PositionStateKey(pid,"MULTI"),UseStagedTP()?1.0:0.0);
      if(!GlobalVariableCheck(PositionStateKey(pid,"TIME"))) GlobalVariableSet(PositionStateKey(pid,"TIME"),(double)InpTimeStopBars);
      if(!GlobalVariableCheck(PositionStateKey(pid,"TIMEMIN"))) GlobalVariableSet(PositionStateKey(pid,"TIMEMIN"),InpTimeStopMinR);
      if(!GlobalVariableCheck(PositionStateKey(pid,"A"))) GlobalVariableSet(PositionStateKey(pid,"A"),plannedRR);
   }
}

bool ExportAdvancedReport()
{
   FolderCreate("NixoReports",FILE_COMMON);
   datetime now=TimeCurrent();
   if(!HistorySelect(0,now)) { PrintFormat("REPORT HISTORY SELECT FAILED | error=%d",GetLastError()); return false; }
   string stamp=TimeToString(now,TIME_DATE|TIME_MINUTES);
   StringReplace(stamp,".","-"); StringReplace(stamp,":","-"); StringReplace(stamp," ","_");
   string filename=StringFormat("NixoReports\\Nixo_Deals_%I64d_%s.csv",AccountInfoInteger(ACCOUNT_LOGIN),stamp);
   int h=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) { PrintFormat("REPORT FILE OPEN FAILED | %s | error=%d",filename,GetLastError()); return false; }
   FileWrite(h,"record_type","deal_ticket","position_id","magic","symbol","entry","deal_type","time","volume","price","profit","commission","swap","fee","comment","mode","strategy_id","source_hash","initial_sl","risk_money","planned_rr");
   int total=HistoryDealsTotal(), exported=0;
   for(int i=0;i<total;i++)
   {
      ulong d=HistoryDealGetTicket(i); if(d==0) continue;
      long magic=HistoryDealGetInteger(d,DEAL_MAGIC);
      if(magic!=InpMagic && magic!=InpSignalMagic) continue;
      string c=HistoryDealGetString(d,DEAL_COMMENT);
      if(magic==InpMagic && StringFind(c,"Nixo500|")!=0) continue;
      if(magic==InpSignalMagic && StringFind(c,"NX503|")!=0) continue;
      ulong pid=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);
      string entry=EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY));
      string dtype=EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(d,DEAL_TYPE));
      int mode=(int)(GlobalVariableCheck(ReportMetaKey(pid,"MODE"))?GlobalVariableGet(ReportMetaKey(pid,"MODE")):(magic==InpSignalMagic?NIXO_MODE_EXTERNAL:((StringFind(c,"|M|")>=0 || StringFind(c,"MANUAL")>=0)?NIXO_MODE_MANUAL:NIXO_MODE_STRATEGY)));
      int strat=(int)(GlobalVariableCheck(ReportMetaKey(pid,"STRAT"))?GlobalVariableGet(ReportMetaKey(pid,"STRAT")):ReportStrategyFromComment(c));
      long source=(long)(GlobalVariableCheck(ReportMetaKey(pid,"SOURCE"))?GlobalVariableGet(ReportMetaKey(pid,"SOURCE")):0);
      double sl=GlobalVariableCheck(ReportMetaKey(pid,"SL0"))?GlobalVariableGet(ReportMetaKey(pid,"SL0")):0.0;
      double risk=GlobalVariableCheck(ReportMetaKey(pid,"RISK"))?GlobalVariableGet(ReportMetaKey(pid,"RISK")):0.0;
      double rr=GlobalVariableCheck(ReportMetaKey(pid,"RR"))?GlobalVariableGet(ReportMetaKey(pid,"RR")):0.0;
      FileWrite(h,"DEAL",(string)d,(string)pid,(string)magic,HistoryDealGetString(d,DEAL_SYMBOL),entry,dtype,
         TimeToString((datetime)HistoryDealGetInteger(d,DEAL_TIME),TIME_DATE|TIME_SECONDS),
         DoubleToString(HistoryDealGetDouble(d,DEAL_VOLUME),8),DoubleToString(HistoryDealGetDouble(d,DEAL_PRICE),10),
         DoubleToString(HistoryDealGetDouble(d,DEAL_PROFIT),2),DoubleToString(HistoryDealGetDouble(d,DEAL_COMMISSION),2),
         DoubleToString(HistoryDealGetDouble(d,DEAL_SWAP),2),DoubleToString(HistoryDealGetDouble(d,DEAL_FEE),2),c,
         TradingModeName((ENUM_NIXO_TRADING_MODE)mode),(string)strat,(string)source,DoubleToString(sl,10),DoubleToString(risk,2),DoubleToString(rr,3));
      exported++;
   }
   // Live Nixo positions are included separately and excluded from closed-trade performance math.
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      long magic=PositionGetInteger(POSITION_MAGIC); if(magic!=InpMagic && magic!=InpSignalMagic) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if((magic==InpMagic && StringFind(c,"Nixo500|")!=0) || (magic==InpSignalMagic && StringFind(c,"NX503|")!=0)) continue;
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      int mode=(int)(GlobalVariableCheck(ReportMetaKey(pid,"MODE"))?GlobalVariableGet(ReportMetaKey(pid,"MODE")):(magic==InpSignalMagic?NIXO_MODE_EXTERNAL:NIXO_MODE_STRATEGY));
      int strat=(int)(GlobalVariableCheck(ReportMetaKey(pid,"STRAT"))?GlobalVariableGet(ReportMetaKey(pid,"STRAT")):ReportStrategyFromComment(c));
      long source=(long)(GlobalVariableCheck(ReportMetaKey(pid,"SOURCE"))?GlobalVariableGet(ReportMetaKey(pid,"SOURCE")):0);
      double sl=GlobalVariableCheck(ReportMetaKey(pid,"SL0"))?GlobalVariableGet(ReportMetaKey(pid,"SL0")):PositionGetDouble(POSITION_SL);
      double risk=GlobalVariableCheck(ReportMetaKey(pid,"RISK"))?GlobalVariableGet(ReportMetaKey(pid,"RISK")):0.0;
      double rr=GlobalVariableCheck(ReportMetaKey(pid,"RR"))?GlobalVariableGet(ReportMetaKey(pid,"RR")):0.0;
      long pt=PositionGetInteger(POSITION_TYPE);
      FileWrite(h,"OPEN","",(string)pid,(string)magic,PositionGetString(POSITION_SYMBOL),"OPEN",pt==POSITION_TYPE_BUY?"BUY":"SELL",
         TimeToString((datetime)PositionGetInteger(POSITION_TIME),TIME_DATE|TIME_SECONDS),
         DoubleToString(PositionGetDouble(POSITION_VOLUME),8),DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN),10),
         DoubleToString(PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP),2),"0","0","0",c,
         TradingModeName((ENUM_NIXO_TRADING_MODE)mode),(string)strat,(string)source,DoubleToString(sl,10),DoubleToString(risk,2),DoubleToString(rr,3));
      exported++;
   }
   FileClose(h);
   PrintFormat("ADVANCED REPORT EXPORTED | file=%s | rows=%d",filename,exported);
   return true;
}

int OnInit()
{
   if(InpSignalMagic==InpMagic || InpSignalTP1ClosePct<=0.0 || InpSignalTP1ClosePct>100.0 ||
      InpSignalTP2ClosePct<=0.0 || InpSignalTP2ClosePct>100.0 ||
      InpSignalTP3ClosePct<=0.0 || InpSignalTP3ClosePct>100.0 ||
      InpSignalRunnerTrailATR<=0.0 || InpSignalMaxOrderCount<1 || InpSignalMaxVolumeStep<1 ||
      InpSignalBaseLot<=0.0 || InpSignalVolumeStepFactor<0.0 || InpSignalMaxLiveRiskPct<0.0)
   { Print("INIT FAILED: invalid signal magic, risk/roulette caps, runner ATR or signal partial-close percentages."); return INIT_PARAMETERS_INCORRECT; }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   h_ATR   = iATR (_Symbol, PERIOD_CURRENT, InpATR_Period);
   h_STATR = iATR (_Symbol, PERIOD_CURRENT, InpSupertrendATRPeriod);
   h_EMA21 = iMA  (_Symbol, PERIOD_CURRENT, 21, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA9  = iMA  (_Symbol, PERIOD_CURRENT, 9, 0, MODE_EMA, PRICE_CLOSE);
   h_EMAF  = iMA  (_Symbol, PERIOD_CURRENT, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   h_EMAS  = iMA  (_Symbol, PERIOD_CURRENT, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   h_RSI   = iRSI (_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   h_ADX   = iADX (_Symbol, PERIOD_CURRENT, InpADX_Period);
   h_HTFFast = iMA(_Symbol, InpScalpHigherTF, InpMTF_FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   h_HTFSlow = iMA(_Symbol, InpScalpHigherTF, InpMTF_SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   h_RSI3  = iRSI (_Symbol, PERIOD_CURRENT, 3, PRICE_CLOSE);
   h_EMA3  = iMA(_Symbol, PERIOD_CURRENT, 3, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA8  = iMA(_Symbol, PERIOD_CURRENT, 8, 0, MODE_EMA, PRICE_CLOSE);
   h_MACD  = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   h_BANDS = iBands(_Symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   h_STOCH = iStochastic(_Symbol, PERIOD_CURRENT, 5, 3, 3, MODE_SMA, STO_LOWHIGH);

   if(h_ATR==INVALID_HANDLE || h_STATR==INVALID_HANDLE || h_EMA21==INVALID_HANDLE || h_EMA9==INVALID_HANDLE ||
      h_EMAF==INVALID_HANDLE || h_EMAS==INVALID_HANDLE || h_RSI==INVALID_HANDLE || h_ADX==INVALID_HANDLE ||
      h_HTFFast==INVALID_HANDLE || h_HTFSlow==INVALID_HANDLE || h_RSI3==INVALID_HANDLE ||
      h_EMA3==INVALID_HANDLE || h_EMA8==INVALID_HANDLE || h_MACD==INVALID_HANDLE ||
      h_BANDS==INVALID_HANDLE || h_STOCH==INVALID_HANDLE)
   {
      Print("OnInit: failed to create indicator handles, error ", GetLastError());
      return INIT_FAILED;
   }

   InitSettingsFromInputs();
   if(HasLegacyNixoPositions())
      Print("WARNING: positions with this Magic/Symbol were not opened by this engine. They are counted but left to their broker SL/TP.");
   if(MQLInfoInteger(MQL_TESTER))
   {
      GlobalVariablesDeleteAll(GVKey("P"));       // stale TP-stage flags
      GlobalVariablesDeleteAll(GVKey("C_"));      // stale "position already processed" markers
      GlobalVariablesDeleteAll(GVKey("RISK_"));   // stale per-position risk snapshots
      GlobalVariablesDeleteAll(GVKey("ENTRY_"));  // stale Nyao entry counters
      GlobalVariablesDeleteAll(GVKey("BPOS_"));   // stale batch-to-position links
      GlobalVariablesDeleteAll(GVKey("B"));       // stale batch aggregates / sequence
   }
   if(PeriodSeconds(InpScalpHigherTF) <= PeriodSeconds(PERIOD_CURRENT))
      Print("WARNING: InpScalpHigherTF is not higher than the chart timeframe – EMA-ADX MTF confirmation is meaningless.");
   if((InpUseMultiTP || g_TurboEnabled) && !ValidTPInputs())
   {
      Print("INIT FAILED: require TP1_R < TP2_R < TP3_R, positive runner ATR, and valid selected sizing inputs.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if((g_MultiOrderEnabled || g_OrderRouletteEnabled || g_TurboEnabled || InpUseMultiTP) &&
      AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Alert("Nixo Multi-Order / Roulette / Turbo / Multi-TP requires a HEDGING account.");
      Print("INIT FAILED: partial close and multi-order features require ACCOUNT_MARGIN_MODE_RETAIL_HEDGING.");
      return INIT_FAILED;
   }
   g_StartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_CycleStartEq = g_StartEquity;
   g_Step         = 1;
   g_Roulette     = ROULETTE_OFF;
   g_Running      = false;       // never auto-resume: press START
   g_Stopped      = false;
   g_TradesToday  = 0;
   g_LastDay      = 0;
   g_DayStamp     = 0;
   g_DayStartEquity = 0.0;
   g_DayPeakEquity = 0.0;
   g_DailyStopped = false;
   g_DailyStopReason = "";
   g_LastBarTime  = 0;
   g_StatsFrom    = 0;
   g_ConsecLosses = 0;
   g_CooldownUntil= 0;
   g_ResumeAfterDaily = false;
   g_OrderCount   = (int)Clampd(InpInitialOrders, 1, OrderCountCap());

   LoadState();
   g_Running=false;
   g_SignalLiveEnabled=false;
   g_ManualMode=(g_TradingMode==NIXO_MODE_MANUAL);
   if(InpPositionSizeMode==NIXO_SIZE_FIXED_LOT && (g_RiskRouletteEnabled || g_OrderRouletteEnabled))
   {
      g_RiskRouletteEnabled=false;
      g_OrderRouletteEnabled=false;
      g_Roulette=ROULETTE_OFF;
      g_Step=1;
      Print("ROULETTE DISABLED | Fixed Lot sizing is selected. Choose % risk or fixed cash risk to use either roulette.");
   }
   if(g_HedgeEnabled && AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      g_HedgeEnabled=false;
      Print("HEDGE MODE disabled: current account is not a Hedging account.");
   }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING &&
      (g_MultiOrderEnabled || g_OrderRouletteEnabled || g_TurboEnabled))
   {
      g_MultiOrderEnabled=false;
      g_OrderRouletteEnabled=false;
      g_TurboEnabled=false;
      Print("HEDGING-ONLY MODES DISABLED | this account is Netting/Exchange; single-order execution remains available.");
   }
   if(g_DayStamp == 0 || g_DayStartEquity <= 0.0 || g_DayStamp != BrokerDayStart())
      ResetDailyProtection(BrokerDayStart());
   g_LastDay = g_DayStamp;
   g_OrderCount = (int)Clampd(g_OrderCount, 1, OrderCountCap());
   if(g_Step > g_MaxStep) g_Step = g_MaxStep;
   UpdateRouletteState();
   SaveState();
   RefreshStats();

   g_S = Clampd(InpPanelScale / 100.0, 0.6, 1.6);
   g_ShowSettings = !InpStartCompact;
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   g_SignalLiveEnabled=false;
   FolderCreate("NixoBridge",FILE_COMMON);
   FolderCreate("NixoBridge\\inbox",FILE_COMMON);
   FolderCreate("NixoBridge\\reports",FILE_COMMON);
   FolderCreate("NixoBridge\\ai",FILE_COMMON);
   FolderCreate("NixoBridge\\copy",FILE_COMMON);
   ArrayResize(g_SignalLiveHashes,0);
   for(int si=PositionsTotal()-1;si>=0;si--)
   {
      ulong st=PositionGetTicket(si); if(st==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpSignalMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long sh=SignalHashFromComment(PositionGetString(POSITION_COMMENT));
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(sh<=0 && GlobalVariableCheck(SignalGlobalKey((long)pid,"HASH"))) sh=(long)GlobalVariableGet(SignalGlobalKey((long)pid,"HASH"));
      if(sh>0) SignalAddLiveHash(sh);
   }
   for(int si=OrdersTotal()-1;si>=0;si--)
   {
      ulong st=OrderGetTicket(si); if(st==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)!=InpSignalMagic || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      long sh=SignalHashFromComment(OrderGetString(ORDER_COMMENT));
      if(sh>0) SignalAddLiveHash(sh);
   }
   EventSetTimer(1);
   g_LastSig = "";
   Render();

   Print("══════════════════════════════════════");
   Print("  NIXO v5.03  |  Compact AI Dashboard + TradingView RR Planner + Manual Desk + Three-stage Runner + Telegram/RSS Signal Copy | Hossein FSF");
   PrintFormat("  Risk base=%.2f%% | size mode=%d | MultiTP=%s | TP=%.2fR / %.2fR / %.2fR | runner trail=%.2f ATR | daily protection=%s",
               g_BaseRisk,(int)InpPositionSizeMode,UseStagedTP()?"ON":"OFF",g_TP1R,g_TP2R,g_TPAnchorR,g_RunnerTrailATR,InpUseDailyProtection?"ON":"OFF");
   if(InpPositionSizeMode==NIXO_SIZE_FIXED_MONEY)
      PrintFormat("  Fixed loss budget at SL: %.2f %s per signal/order allocation.",InpFixedRiskMoney,AccountInfoString(ACCOUNT_CURRENCY));
   if(InpPositionSizeMode==NIXO_SIZE_FIXED_LOT)
      PrintFormat("  Fixed lot mode: %.2f lots per entry; monetary loss at SL will vary with stop distance.",InpFixedLot);
   if(TurboActive()) Print("TURBO ENABLED | three-stage R TP with ATR runner is shared with normal strategies.");
   Print("  Symbol: ", _Symbol, "  TF: ", EnumToString(_Period));
   Print("  Strategy: ", StratShort(g_Strategy), "  Start Equity: ", DoubleToString(g_StartEquity, 2));
   PrintFormat("  SAFETY DEFAULTS | Ultra score=%d | max positions=%d | open risk cap=%.2f%% | trades/min=%d | max order count=%d | daily guard=%s | hard stop=%.2f%% | NYAO expiry=%d min",
               InpUltraMinScore,InpMaxOpenPositions,InpMaxOpenRiskPct,InpMaxTradesPerMinute,InpMaxOrderCount,
               InpUseDailyProtection?"ON":"OFF",InpHardStopPct,InpNyaoPendingExpiryMinutes);
   PrintFormat("  Roulette controls | ORDER +1=%s (next count=%d) | VOLUME=%s (armed=%s, step=%d, risk=%.3f%%) | HEDGE=%s",
               g_OrderRouletteEnabled?"ON":"OFF",g_OrderCount,
               g_RiskRouletteEnabled?"ON":"OFF",g_Roulette==ROULETTE_ON?"YES":"NO",g_Step,GetCurrentRiskPct(),
               g_HedgeEnabled?"ON":"OFF");
   PrintFormat("  Entry caps: daily=%s, per-minute=%s, open-pos=%s, order-count=%s, spread=%s, cooldown=%s",
               InpMaxTradesDay<=0 && InpScalpMaxTradesDay<=0 ? "OFF" : "ON",
               InpMaxTradesPerMinute<=0 ? "OFF" : "ON",
               InpMaxOpenPositions<=0 ? "OFF" : "ON",
               InpMaxOrderCount<=0 ? "OFF" : "ON",
               InpMaxSpread<=0 ? "OFF" : "ON",
               InpMaxConsecLosses<=0 || InpCooldownMinutes<=0 ? "OFF" : "ON");
   PrintFormat("  SIGNAL LAB=%s | LIVE ALLOW INPUT=%s | live model=%s | signal magic=%I64d | base lot=%.3f | split=%s | max-age=%d sec",InpSignalLabEnabled?"ON":"OFF",InpSignalLiveAllowed?"ON":"OFF",SignalModelName((int)InpSignalLiveModel),InpSignalMagic,InpSignalBaseLot,InpSignalSplitRiskAcrossOrders?"YES":"NO",InpSignalMaxAgeSeconds);
   Print("══════════════════════════════════════");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(reason==REASON_REMOVE || reason==REASON_CHARTCLOSE)
   {
      Print("NIXO DEINIT: removing EA/chart; canceling owned NYAO pending orders.");
      CancelNyaoPendingOrders();
      CancelSignalPendingOrders();
   }
   EventKillTimer();
   ObjectDelete(0, UI_OBJ);
   ObjectDelete(0, MANUAL_PRICE_OBJ);
   ObjectDelete(0, MANUAL_LINE_OBJ);
   DeleteManualDesk();
   ClearRRDrawing();
   DeleteRRToolbar();
   ResourceFree(UI_RES);
   Comment("");

   int hs[] = { h_ATR, h_STATR, h_EMA21, h_EMA9, h_EMAF, h_EMAS, h_RSI, h_ADX, h_HTFFast, h_HTFSlow, h_RSI3, h_EMA3, h_EMA8, h_MACD, h_BANDS, h_STOCH };
   for(int i = 0; i < ArraySize(hs); i++)
      if(hs[i] != INVALID_HANDLE) IndicatorRelease(hs[i]);
}

//==================================================================
//  EVENTS
//==================================================================
void OnTimer()
{
   ReadAIStatus();
   WriteAIMarketSnapshot();
   ProcessSignalInbox();
   UpdateSignalPaperTrades();
   ManageSignalLivePositions();
   ExpireSignalPendingOrders();
   FinalizeSignalLiveBatches();
   Render();
   if(g_ManualDeskOpen) UpdateManualDesk();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_ENDEDIT && (sparam==MD_ENTRY || sparam==MD_SIZE_VALUE || sparam==MD_SL_ATR || sparam==MD_TP3_R))
   { HandleManualDeskEdit(sparam); return; }
   if(id==CHARTEVENT_OBJECT_CLICK && StringFind(sparam,MD_PREFIX)==0)
   {
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      if(sparam==MD_PREFIX+"CLOSE") { g_ManualDeskOpen=false; DeleteManualDesk(); }
      else if(sparam==MD_PREFIX+"MODE")
      {
         g_ManualSizeMode=(ENUM_NIXO_SIZE_MODE)(((int)g_ManualSizeMode+1)%3);
         if(g_ManualSizeMode==NIXO_SIZE_RISK_PERCENT) g_ManualSizeValue=MathMax(0.05,InpBaseRisk);
         else if(g_ManualSizeMode==NIXO_SIZE_FIXED_MONEY) g_ManualSizeValue=MathMax(1.0,InpFixedRiskMoney);
         else g_ManualSizeValue=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),InpFixedLot);
         if(ObjectFind(0,MD_SIZE_VALUE)>=0) ObjectSetString(0,MD_SIZE_VALUE,OBJPROP_TEXT,DoubleToString(g_ManualSizeValue,2));
         UpdateManualDesk();
      }
      else if(sparam==MD_PREFIX+"TOGGLE") DoAction(ACT_MANUAL_MODE);
      else if(sparam==MD_PREFIX+"BUY") DoAction(ACT_BUY);
      else if(sparam==MD_PREFIX+"SELL") DoAction(ACT_SELL);
      else if(sparam==MD_PREFIX+"BUYLIMIT") DoAction(ACT_BUY_LIMIT);
      else if(sparam==MD_PREFIX+"SELLLIMIT") DoAction(ACT_SELL_LIMIT);
      g_LastSig=""; Render();
      if(g_ManualDeskOpen) UpdateManualDesk();
      return;
   }
   if(id==CHARTEVENT_OBJECT_CLICK &&
      (sparam==RR_LONG_BUTTON || sparam==RR_SHORT_BUTTON || sparam==RR_REGISTER_BTN || sparam==RR_CANCEL_BTN))
   {
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      if(sparam==RR_LONG_BUTTON || sparam==RR_SHORT_BUTTON)
      {
         if(!g_ManualMode)
            Alert("Enable MANUAL MODE in the yellow MANUAL DESK first. Auto entries remain paused in manual mode.");
         else
         {
            ClearRRDrawing();
            g_RRDirection=(sparam==RR_LONG_BUTTON?1:-1);
            g_RRPlaceArmed=true;
            UpdateRRToolbar();
            Print("RR PLANNER ARMED | ",g_RRDirection>0?"LONG":"SHORT"," | click the chart once to place Entry; then drag Entry / SL / TP lines.");
         }
      }
      else if(sparam==RR_REGISTER_BTN)
      {
         if(RegisterRRPlan())
         {
            ClearRRDrawing();
            g_RRPlaceArmed=false;
         }
      }
      else if(sparam==RR_CANCEL_BTN)
      {
         ClearRRDrawing();
         g_RRPlaceArmed=false;
         Print("RR PLANNER: setup cleared.");
      }
      g_LastSig="";
      UpdateRRToolbar();
      Render();
      return;
   }

   if(id==CHARTEVENT_OBJECT_DRAG && HandleRRObjectDrag(sparam)) return;

   string tp3Prefix="NIXO500_TP3_";
   if(id==CHARTEVENT_OBJECT_DRAG && StringFind(sparam,tp3Prefix)==0)
   {
      ulong pid=(ulong)StringToInteger(StringSubstr(sparam,StringLen(tp3Prefix)));
      double requestedTP=ObjectGetDouble(0,sparam,OBJPROP_PRICE);
      bool matched=false;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong tk=PositionGetTicket(i); if(tk==0) continue;
         if((ulong)PositionGetInteger(POSITION_IDENTIFIER)!=pid) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=InpMagic || PositionGetString(POSITION_SYMBOL)!=_Symbol) break;
         long pt=PositionGetInteger(POSITION_TYPE);
         double op=PositionGetDouble(POSITION_PRICE_OPEN);
         double r=GlobalVariableCheck(PositionStateKey(pid,"R"))?GlobalVariableGet(PositionStateKey(pid,"R")):0.0;
         double newR=(r>0.0)?((pt==POSITION_TYPE_BUY)?(requestedTP-op)/r:(op-requestedTP)/r):0.0;
         if(newR<=g_TP2R || newR>20.0)
         {
            double oldR=GlobalVariableCheck(PositionStateKey(pid,"A"))?GlobalVariableGet(PositionStateKey(pid,"A")):g_TPAnchorR;
            double oldPrice=(pt==POSITION_TYPE_BUY)?op+r*oldR:op-r*oldR;
            ObjectSetDouble(0,sparam,OBJPROP_PRICE,NormalizeDouble(oldPrice,_Digits));
            Alert("TP3 must remain beyond TP2 and no farther than 20R.");
         }
         else
         {
            GlobalVariableSet(PositionStateKey(pid,"A"),newR);
            PrintFormat("MANUAL TP3 CHANGE | position=%I64u | TP3 updated to %.2fR at %.*f",pid,newR,_Digits,requestedTP);
         }
         ObjectSetInteger(0,sparam,OBJPROP_SELECTED,false);
         matched=true;
         break;
      }
      if(!matched) ObjectDelete(0,sparam);
      return;
   }
   if(id==CHARTEVENT_OBJECT_DRAG && sparam==MD_BG)
   {
      g_ManualDeskX=(int)ObjectGetInteger(0,MD_BG,OBJPROP_XDISTANCE);
      g_ManualDeskY=(int)ObjectGetInteger(0,MD_BG,OBJPROP_YDISTANCE);
      if(g_ManualDeskOpen) UpdateManualDesk();
      return;
   }
   if(id==CHARTEVENT_MOUSE_MOVE)
   {
      g_MouseX=(int)lparam; g_MouseY=(int)dparam;
      if(g_PendingArmType!=0 && g_ManualMode)
      {
         int sub=0; datetime tm=0; double px=0.0;
         if(ChartXYToTimePrice(0,g_MouseX,g_MouseY,sub,tm,px) && px>0.0 && ObjectFind(0,MANUAL_LINE_OBJ)>=0)
            ObjectSetDouble(0,MANUAL_LINE_OBJ,OBJPROP_PRICE,px);
      }
      return;
   }
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==UI_OBJ)
   {
      PanelClick(g_MouseX-InpPanelX,g_MouseY-InpPanelY); return;
   }
   if(id==CHARTEVENT_CLICK)
   {
      int cx=(int)lparam, cy=(int)dparam;
      bool inside=(cx>=InpPanelX && cx<=InpPanelX+g_W && cy>=InpPanelY && cy<=InpPanelY+g_H);
      if(inside) { PanelClick(cx-InpPanelX,cy-InpPanelY); return; }
      if(g_RRPlaceArmed && g_ManualMode)
      {
         int rrSub=0; datetime rrTime=0; double rrPrice=0.0;
         if(ChartXYToTimePrice(0,cx,cy,rrSub,rrTime,rrPrice) && rrPrice>0.0)
            CreateRRPlan(rrTime,rrPrice);
         return;
      }
      if(g_PendingArmType!=0 && g_ManualMode)
      {
         int sub=0; datetime tm=0; double price=0.0;
         if(ChartXYToTimePrice(0,cx,cy,sub,tm,price) && price>0.0)
         {
            bool placed=PlaceManualLimit(g_PendingArmType>0?ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_SELL_LIMIT,price);
            if(placed) { g_PendingArmType=0; ObjectDelete(0,MANUAL_LINE_OBJ); }
            g_LastSig=""; Render();
         }
      }
   }
}

void PanelClick(int x, int y)
{
   ulong now = GetTickCount64();
   if(now - g_LastClickMs < 300) return;            // de-bounce (object click + chart click)

   for(int i = g_HitN - 1; i >= 0; i--)
   {
      if(x >= g_Hits[i].x1 && x <= g_Hits[i].x2 && y >= g_Hits[i].y1 && y <= g_Hits[i].y2)
      {
         g_LastClickMs = now;
         DoAction(g_Hits[i].act);
         return;
      }
   }
}

double Clampd(double v, double lo, double hi)
{
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
}

void ChangeSetting(int row, int dir)
{
   switch(row)
   {
      case 0: // Base risk
         g_BaseRisk = NormalizeDouble(Clampd(g_BaseRisk + dir * 0.05, 0.05, MathMax(0.05, InpMaxRiskPct)), 2); break;
      case 1: // SL ATR
         g_ATRMult = NormalizeDouble(Clampd(g_ATRMult + dir * 0.25, 0.5, 6.0), 2); break;
      case 2: // Final TP3 anchor R for the staged manager
         g_TPAnchorR = NormalizeDouble(Clampd(g_TPAnchorR + dir * 0.25, g_TP2R + 0.25, 10.0), 2);
         g_TPRR = g_TPAnchorR; break;
      case 3: // Max lot; zero means OFF
      {
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double step = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), 0.01);
         double v = (g_MaxLot <= 0.0) ? (dir > 0 ? minLot : 0.0) : g_MaxLot + dir * step;
         if(v < minLot - 1e-9) v = 0.0;
         g_MaxLot = (v <= 0.0) ? 0.0 : NormalizeDouble(MathMin(v, 100.0), VolumeDigits(step));
         break;
      }
      case 4: // Max cost/SL
         g_MaxSpreadPct = NormalizeDouble(Clampd(g_MaxSpreadPct + dir * 2.5, 0.0, 50.0), 1); break;
      case 5: // Break-even toggle
         g_UseBE = !g_UseBE; break;
      case 6: // TP1 R
         g_TP1R = NormalizeDouble(Clampd(g_TP1R + dir * 0.25, 0.25, g_TP2R - 0.25), 2); break;
      case 7: // TP2 R
         g_TP2R = NormalizeDouble(Clampd(g_TP2R + dir * 0.25, g_TP1R + 0.25, g_TPAnchorR - 0.25), 2); break;
      case 8: // Runner trail ATR
         g_RunnerTrailATR = NormalizeDouble(Clampd(g_RunnerTrailATR + dir * 0.1, 0.2, 5.0), 2); break;
      case 9: // Single-target R when staged TP is disabled
         g_TPRR = NormalizeDouble(Clampd(g_TPRR + dir * 0.25, 0.25, 20.0), 2); break;
      case 10: // Maximum roulette step
         g_MaxStep = (int)Clampd(g_MaxStep + dir, 1, 100);
         if(g_Step > g_MaxStep) g_Step = g_MaxStep;
         break;
   }
   if(row==1 || row==2 || row==6 || row==7 || row==8 || row==9)
   {
      g_ExitProfile = -1;
      g_ManualSLATR = g_ATRMult;
      g_ManualTP3R = g_TPAnchorR;
   }
   SaveState();
}

void ApplyExitPreset(int profile)
{
   g_ExitProfile = (int)Clampd(profile, 0, 2);
   if(g_ExitProfile == 0)
   {
      g_ATRMult = 1.25; g_TP1R = 0.75; g_TP2R = 1.50; g_TPAnchorR = 2.25; g_RunnerTrailATR = 0.90;
   }
   else if(g_ExitProfile == 1)
   {
      g_ATRMult = 2.00; g_TP1R = 1.00; g_TP2R = 2.00; g_TPAnchorR = 3.00; g_RunnerTrailATR = 1.20;
   }
   else
   {
      g_ATRMult = 2.50; g_TP1R = 1.50; g_TP2R = 3.00; g_TPAnchorR = 4.50; g_RunnerTrailATR = 1.50;
   }
   g_TPRR = g_TPAnchorR;
   g_ManualSLATR = g_ATRMult;
   g_ManualTP3R = g_TPAnchorR;
}

void DoAction(int act)
{
   if(act == ACT_STARTSTOP)
   {
      if(g_TradingMode!=NIXO_MODE_STRATEGY)
      {
         Alert("START controls internal strategies only. Select STRATEGY mode first.");
      }
      else if(g_Stopped)
      {
         Alert("Nixo is hard-stopped. Press RESET first.");
      }
      else if(g_DailyStopped)
      {
         Alert("Nixo daily protection is active. Trading can resume on the next broker day or after RESET.");
      }
      else if(!g_Running && (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
              !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
              SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE)==SYMBOL_TRADE_MODE_DISABLED))
      {
         Alert("Nixo cannot start trading: enable AutoTrading, EA trading permission, account trading, and symbol trading first.");
         Print("START BLOCKED | trading permission unavailable for terminal, EA, account, or symbol.");
      }
      else
      {
         g_Running = !g_Running;
         if(g_Running) g_EntriesPaused=false;
         SaveState();
         Print(g_Running ? ">>> NIXO STARTED – Auto trading ON" : ">>> NIXO STOPPED – Auto trading OFF");
      }
   }
   else if(act == ACT_RESET)
   {
      g_StartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
      g_CycleStartEq = g_StartEquity;
      g_Step         = 1;
      g_Roulette     = ROULETTE_OFF;
      g_OrderCount   = (int)Clampd(InpInitialOrders, 1, OrderCountCap());
      g_Running      = false;
      g_Stopped      = false;
      g_TradesToday  = 0;
      g_StatsFrom    = TimeCurrent();
      g_ConsecLosses = 0;
      g_CooldownUntil= 0;
      g_ResumeAfterDaily = false;
      ResetDailyProtection(BrokerDayStart());
      UpdateRouletteState();
      SaveState();
      RefreshStats();
      Print(">>> NIXO RESET – equity baseline + statistics reset");
   }
   else if(act == ACT_BUY || act == ACT_SELL)
   {
      if(g_TradingMode!=NIXO_MODE_MANUAL || g_EntriesPaused) Alert("Select MANUAL mode and resume entries first.");
      else if(g_Stopped) Alert("Nixo is hard-stopped. Press RESET first.");
      else if(g_DailyStopped) Alert("Nixo daily protection is active. Trading paused.");
      else TryOpen(act == ACT_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, "MANUAL");
   }
   else if(act == ACT_HEDGE)
   {
      if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
         Alert("Hedge mode requires a Hedging account. Current account is not Hedging.");
      else
      {
         g_HedgeEnabled=!g_HedgeEnabled;
         if(!g_HedgeEnabled) CancelNyaoPendingOrders();
         PrintFormat("HEDGE MODE %s | account=HEDGING | NYAO pending orders %s",
                     g_HedgeEnabled?"ON (BUY + SELL allowed)":"OFF (opposite positions blocked)",
                     g_HedgeEnabled?"may use OCO pair":"cancelled; one direction only");
         SaveState();
      }
   }
   else if(act == ACT_MANUAL_MODE)
   {
      SetTradingMode(g_TradingMode==NIXO_MODE_MANUAL?NIXO_MODE_STRATEGY:NIXO_MODE_MANUAL);
   }
   else if(act == ACT_MODE_MANUAL) SetTradingMode(NIXO_MODE_MANUAL);
   else if(act == ACT_MODE_EXTERNAL) SetTradingMode(NIXO_MODE_EXTERNAL);
   else if(act == ACT_MODE_STRATEGY) SetTradingMode(NIXO_MODE_STRATEGY);
   else if(act == ACT_REPORT_EXPORT)
   {
      if(ExportAdvancedReport()) Alert("Nixo advanced report exported to MT5 Common Files\NixoReports.");
      else Alert("Nixo report export failed. Check Experts log and Common Files permissions.");
   }
   else if(act == ACT_ORDER_MINUS || act == ACT_ORDER_PLUS)
   {
      int before = g_OrderCount;
      int cap = OrderCountCap();
      if(act == ACT_ORDER_MINUS) g_OrderCount = MathMax(1, g_OrderCount - 1);
      else if(g_OrderCount < cap) g_OrderCount++;
      if(g_OrderCount != before)
      {
         PrintFormat("ORDER COUNT MANUAL | %d -> %d | auto order roulette=%s",
                     before, g_OrderCount, g_OrderRouletteEnabled ? "ON (win x2 / loss -1)" : "OFF");
         SaveState();
      }
   }
   else if(act == ACT_CLOSE_ALL)
   {
      if(g_CloseAllConfirmUntilMs > GetTickCount64())
      {
         g_CloseAllConfirmUntilMs=0;
         CloseAllNixoPositionsOnly();
      }
      else
      {
         g_CloseAllConfirmUntilMs=GetTickCount64()+8000;
         Alert("Confirm CLOSE NIXO POSITIONS within 8 seconds. Only Nixo positions will close; pending orders and their SL/TP will remain active and may still fill.");
      }
      g_LastSig="";
   }
   else if(act == ACT_BUY_LIMIT || act == ACT_SELL_LIMIT)
   {
      if(g_TradingMode!=NIXO_MODE_MANUAL || g_EntriesPaused) Alert("Select MANUAL mode and resume entries first.");
      else if(g_ManualPrice>0.0) PlaceManualLimit(act==ACT_BUY_LIMIT?ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_SELL_LIMIT,g_ManualPrice);
      else
      {
         g_PendingArmType=(act==ACT_BUY_LIMIT?1:-1);
         double seed=(g_PendingArmType>0?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK));
         if(ObjectFind(0,MANUAL_LINE_OBJ)<0) ObjectCreate(0,MANUAL_LINE_OBJ,OBJ_HLINE,0,0,seed);
         ObjectSetDouble(0,MANUAL_LINE_OBJ,OBJPROP_PRICE,seed);
         ObjectSetInteger(0,MANUAL_LINE_OBJ,OBJPROP_COLOR,g_PendingArmType>0?clrLimeGreen:clrTomato);
         ObjectSetInteger(0,MANUAL_LINE_OBJ,OBJPROP_STYLE,STYLE_DASH);
         ObjectSetInteger(0,MANUAL_LINE_OBJ,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,MANUAL_LINE_OBJ,OBJPROP_SELECTABLE,false);
         ObjectSetString(0,MANUAL_LINE_OBJ,OBJPROP_TEXT,g_PendingArmType>0?"NIXO BUY LIMIT — click to place":"NIXO SELL LIMIT — click to place");
         Print("MANUAL LIMIT ARMED — move the cursor over the chart and click at the desired price.");
      }
   }
   else if(act == ACT_MANUAL_DESK)
   {
      g_ManualDeskOpen=!g_ManualDeskOpen;
      if(g_ManualDeskOpen) UpdateManualDesk();
      else DeleteManualDesk();
   }
   else if(act == ACT_TOGGLESET)
   {
      g_ShowSettings = !g_ShowSettings;
   }
   else if(act == ACT_SETTINGS_RISK)
   {
      g_SettingsTab = 0;
   }
   else if(act == ACT_SETTINGS_EXITS)
   {
      g_SettingsTab = 1;
   }
   else if(act >= ACT_EXIT_PROFILE_BASE && act < ACT_EXIT_PROFILE_BASE + 4)
   {
   int profile=act-ACT_EXIT_PROFILE_BASE;
   if(profile<3) ApplyExitPreset(profile);
   else g_ExitProfile=-1;
      SaveState();
   }
   else if(act == ACT_RISK_ROULETTE)
   {
      if(!g_RiskRouletteEnabled && InpPositionSizeMode==NIXO_SIZE_FIXED_LOT)
      {
         Alert("Volume Roulette cannot be enabled with Fixed Lot sizing. Select % risk or fixed cash risk.");
         return;
      }
      g_RiskRouletteEnabled = !g_RiskRouletteEnabled;
      if(!g_RiskRouletteEnabled) { g_Roulette = ROULETTE_OFF; g_Step = 1; }
      else UpdateRouletteState();
      PrintFormat("VOLUME ROULETTE %s | trigger=+%.2f%% equity | current step=%d | current risk=%.3f%%",
                  g_RiskRouletteEnabled?"ENABLED":"DISABLED",InpRouletteTrigger,g_Step,GetCurrentRiskPct());
      SaveState();
   }
   else if(act == ACT_ORDER_ROULETTE)
   {
      if(!g_OrderRouletteEnabled && InpPositionSizeMode==NIXO_SIZE_FIXED_LOT)
      {
         Alert("Order Roulette cannot be enabled with Fixed Lot sizing. Select % risk or fixed cash risk.");
         return;
      }
      if(!g_OrderRouletteEnabled && AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         Alert("Order Roulette needs a Hedging account so each batch order remains independently managed.");
         return;
      }
      g_OrderRouletteEnabled = !g_OrderRouletteEnabled;
      PrintFormat("ORDER ROULETTE %s | current batch count=%d | win=plus one / loss=minus one",
                  g_OrderRouletteEnabled?"ENABLED":"DISABLED",g_OrderCount);
      SaveState();
   }
   else if(act == ACT_SIGNAL_LIVE)
   {
      if(g_TradingMode!=NIXO_MODE_EXTERNAL)
      {
         Alert("Select EXTERNAL SIGNALS mode before arming live external signals.");
      }
      else if(!InpSignalLiveAllowed)
      {
         Alert("Signal Lab is paper-only. To permit live copying, enable InpSignalLiveAllowed in Inputs, restart, then press SIGNAL LIVE.");
      }
      else
      {
         if(!g_SignalLiveEnabled && (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)))
            Alert("Live signal copy cannot start: trading permissions are disabled.");
         else
         {
            g_SignalLiveEnabled=!g_SignalLiveEnabled;
            if(g_SignalLiveEnabled) g_EntriesPaused=false;
            SaveState();
            Print("SIGNAL LIVE ",g_SignalLiveEnabled?"ARMED":"DISABLED"," | selected model=",SignalModelName((int)InpSignalLiveModel));
         }
      }
   }
   else if(act == ACT_MULTI_ORDER)
   {
      if(!g_MultiOrderEnabled && AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         Alert("Multi-order mode needs a Hedging account for independent position and batch management.");
         return;
      }
      g_MultiOrderEnabled = !g_MultiOrderEnabled;
      Print("MULTI-ORDER ", g_MultiOrderEnabled ? "ENABLED" : "DISABLED"); SaveState();
   }
   else if(act == ACT_TURBO)
   {
      if(!g_TurboEnabled && AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         Alert("Turbo mode uses staged partial exits and requires a Hedging account.");
         return;
      }
      g_TurboEnabled = !g_TurboEnabled;
      Print("TURBO ", g_TurboEnabled ? "ENABLED" : "DISABLED", " | three-stage R TP + runner stays active"); SaveState();
   }
   else if(act == ACT_PORTFOLIO)
   {
      g_PortfolioMode = !g_PortfolioMode;
      Print("PORTFOLIO ", g_PortfolioMode ? "ENABLED" : "DISABLED"); SaveState();
   }
   else if(act == ACT_STRATEGY_PREV || act == ACT_STRATEGY_NEXT)
   {
      int dir = (act == ACT_STRATEGY_NEXT) ? 1 : -1;
      g_Strategy = (g_Strategy + dir + 20) % 20;
      g_PortfolioMode = false;
      if(g_Strategy == STRAT_TICK_TURBO) g_TurboEnabled = true; // selecting Tick Turbo arms its execution mode
      if(InpAutoProfile) ApplyProfile(g_Strategy);
      SaveState();
   }
   else if(act >= ACT_SET_BASE)
   {
      int k   = act - ACT_SET_BASE;
      int row = k / 2;
      int dir = (k % 2 == 0) ? -1 : 1;
      ChangeSetting(row, dir);
   }
   g_LastSig = "";      // force redraw
   Render();
}

//==================================================================
//  MAIN TICK
//==================================================================
void OnTick()
{
   // Keep a rolling real-time Bid buffer for tick engines.
   double tickBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(tickBid > 0.0)
   {
      g_TickPrices[g_TickPriceHead] = tickBid;
      g_TickPriceHead = (g_TickPriceHead + 1) % 8;
      if(g_TickPriceCount < 8) g_TickPriceCount++;
   }

   datetime today = BrokerDayStart();
   if(today != g_LastDay)
   {
      g_LastDay = today;
      g_TradesToday = 0;
      ResetDailyProtection(today);
   }

   CheckDailyProtection();
   CheckHardStop();
   UpdateRouletteState();
   ManagePosition();
   UpdateSignalPaperTrades();
   ManageSignalLivePositions();
   ExpireSignalPendingOrders();
   FinalizeSignalLiveBatches();

   // v5.04: submitted pending orders are NOT cancelled when Trading Mode or strategy run-state changes.
   // Their own broker expiry / configured Nyao TTL and OCO lifecycle remain independent.
   ExpireStaleNyaoPendingOrders();

   datetime observedBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(g_TradingMode!=NIXO_MODE_STRATEGY || g_EntriesPaused || !g_Running || g_Stopped || g_DailyStopped || (g_CooldownUntil > 0 && TimeCurrent() < g_CooldownUntil))
   {
      if(observedBar > 0) g_LastBarTime = observedBar;
      return;
   }
   if(DailyTradeLimitReached()) return;
   if(EntryRateLimitReached()) return;
   if(IsSpreadTooHigh()) return;
   if(InpUseSession && !IsInSession()) return;

   // Nyao-style straddle uses two server-side stop orders with OCO cancellation.
   bool hybridUltraNyao = (g_Strategy == STRAT_ULTRA_NYAO_HYBRID);
   if(g_Strategy == STRAT_NYAO_STRADDLE || hybridUltraNyao)
   {
      MaintainNyaoStraddle();
      if(!hybridUltraNyao) return; // pure Nyao is pending-order driven; hybrid continues into UltraHFT below
   }

   bool isTickEngine = (g_Strategy == STRAT_TICK_TURBO || g_Strategy == STRAT_ULTRA_HFT || hybridUltraNyao);
   int barsNeeded = isTickEngine
                    ? 60 // EMA21, Bollinger/Stochastic and prior-candle tick-confluence warm-up
                    : (int)MathMax(InpEMA_Slow + 10, InpSafeBreakoutBars + 20);
   if(Bars(_Symbol, PERIOD_CURRENT) < barsNeeded) return;

   if(g_Strategy == STRAT_TICK_TURBO && !g_TurboEnabled) return;
   if(!isTickEngine)
   {
      datetime barTime = observedBar;
      if(barTime <= 0 || barTime == g_LastBarTime) return;
      g_LastBarTime = barTime;
   }

   int signal = 0;
   int signalStrategy = g_Strategy;
   if(g_Strategy == STRAT_TICK_TURBO)
      signal = Signal_TickTurbo();
   else if(g_Strategy == STRAT_ULTRA_HFT || hybridUltraNyao)
      signal = Signal_UltraHFT();
   else if(g_PortfolioMode)
   {
      int buys = 0, sells = 0, firstBuy = -1, firstSell = -1;
      for(int st = STRAT_SAFE_BREAK; st <= STRAT_EMA_PULLBACK; st++)
      {
         int sg = RunStrategy(st);
         if(sg > 0) { buys++; if(firstBuy < 0) firstBuy = st; }
         if(sg < 0) { sells++; if(firstSell < 0) firstSell = st; }
      }
      int needed = (int)Clampd(InpEnsembleMinVotes, 1, 6);
      if(buys >= needed && sells == 0) { signal = 1; signalStrategy = firstBuy; }
      else if(sells >= needed && buys == 0) { signal = -1; signalStrategy = firstSell; }
      else if(buys > 0 && sells > 0 && InpDebug) PrintFormat("PORTFOLIO SKIP: conflicting signals (buy=%d sell=%d)", buys, sells);
   }
   else
      signal = RunStrategy(g_Strategy);

   if(signal == 0) return;
   int savedStrategy = g_Strategy;
   g_Strategy = signalStrategy;

   bool batchMode = (g_MultiOrderEnabled || g_OrderRouletteEnabled || TurboActive());
   int maxAllowed = MaxOpenAllowed();
   if(InpMaxOrderCount > 0) maxAllowed = MathMin(maxAllowed, InpMaxOrderCount);
   int openNow = CountMyPositions();
   int targetOrders = batchMode ? g_OrderCount : 1;
   int slots = maxAllowed - openNow;
   if(slots <= 0 || targetOrders <= 0)
   {
      g_Strategy = savedStrategy;
      return;
   }
   if(targetOrders > slots) targetOrders = slots;

   ENUM_ORDER_TYPE type = (signal > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(InpOneBatchAtATime && g_ActiveBatchId<=0 && HasSameDirectionPosition(type))
   {
      if(InpDebug) PrintFormat("ENTRY GATE | same-direction Nixo position remains open; next %s batch waits for it to close.",type==ORDER_TYPE_BUY?"BUY":"SELL");
      g_Strategy = savedStrategy;
      return;
   }
   // No fixed EA order ceiling by default. Adapt only when broker min-volume/step
   // makes the requested split impossible; keep the intended total batch risk.
   if(batchMode && InpSplitRiskAcrossOrders && targetOrders > 1)
   {
      MqlTick capTick;
      if(SymbolInfoTick(_Symbol, capTick))
      {
         double capPrice = (type == ORDER_TYPE_BUY ? capTick.ask : capTick.bid);
         double aggregateLot = NormalizeVolumeDown(CalcLot(type, GetCurrentRiskPct(), ComputeSLDist(), capPrice));
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(minLot > 0.0)
         {
            int feasible = (int)MathFloor(aggregateLot / minLot + 1e-8);
            if(feasible < targetOrders)
            {
               PrintFormat("ROULETTE BATCH ADAPTED | desired=%d executable=%d | broker min lot=%.4f | total risk lot=%.4f",
                           targetOrders, feasible, minLot, aggregateLot);
               targetOrders = feasible;
            }
         }
      }
   }
   if(targetOrders <= 0)
   {
      Print("BATCH SKIP: current risk budget is below broker minimum volume. Roulette target is retained; no order sent.");
      g_Strategy = savedStrategy;
      return;
   }
   g_ActiveBatchOrders = targetOrders;
   if(InpDebug)
      PrintFormat("AUTO SIGNAL -> %s | strategy=%s | batch=%d | open=%d | cap=%s | turbo=%s portfolio=%s",
                  signal > 0 ? "BUY" : "SELL", StratShort(g_Strategy), targetOrders, openNow,
                  (InpMaxOpenPositions<=0 && InpMaxOrderCount<=0 ? "OFF" : IntegerToString(maxAllowed)),
                  TurboActive() ? "ON" : "OFF", g_PortfolioMode ? "ON" : "OFF");

   g_ActiveBatchId = NextBatchId();
   for(int n = 0; n < targetOrders; n++)
   {
      if(DailyTradeLimitReached() || EntryRateLimitReached()) break;
      if(!TryOpen(type, TurboActive() ? "TURBO" : "AUTO")) break;
   }
   g_ActiveBatchId = 0;
   g_ActiveBatchOrders = 0;
   g_Strategy = savedStrategy;
}

//==================================================================
//  CLOSED-TRADE DETECTION → RISK LADDER
//==================================================================
bool GetFullyClosedPositionNet(ulong positionId, double &netProfit)
{
   netProfit = 0.0;
   if(positionId == 0 || !HistorySelectByPosition(positionId)) return false;

   double inVol = 0.0, outVol = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      double vol = HistoryDealGetDouble(deal, DEAL_VOLUME);
      netProfit += HistoryDealGetDouble(deal, DEAL_COMMISSION)
                 + HistoryDealGetDouble(deal, DEAL_FEE);
      if(entry == DEAL_ENTRY_IN) inVol += vol;
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
      {
         outVol += vol;
         netProfit += HistoryDealGetDouble(deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(deal, DEAL_SWAP);
      }
   }
   return (inVol > 0.0 && outVol + 1e-8 >= inVol);
}

void ProcessOrderRoulette(double profit)
{
   if(!g_OrderRouletteEnabled) return;
   if(InpPositionSizeMode == NIXO_SIZE_FIXED_LOT)
   {
      Alert("Roulette order mode is not allowed with Fixed Lot sizing. Use % risk or fixed cash risk.");
      g_OrderRouletteEnabled = false;
      SaveState();
      return;
   }
   int cap = OrderCountCap();
   int before = g_OrderCount;
   if(profit > 0.0)
      g_OrderCount = MathMin(cap, g_OrderCount + 1);
   else if(profit < 0.0)
      g_OrderCount = MathMax(1, g_OrderCount - 1);
   PrintFormat("ORDER ROULETTE | batch net=%.2f | next batch=%d (previous %d; user cap=%s)",
               profit, g_OrderCount, before, InpMaxOrderCount > 0 ? IntegerToString(InpMaxOrderCount) : "OFF");
   SaveState();
}

bool CanUseRouletteWithCurrentSizing()
{
   if(InpPositionSizeMode == NIXO_SIZE_FIXED_LOT)
   {
      Print("ROULETTE BLOCKED | Fixed Lot sizing is not allowed for risk/order roulette. Use % risk or fixed cash risk.");
      return false;
   }
   return true;
}

void ProcessRiskRoulette(double profit, double riskMoney)
{
   if(!g_RiskRouletteEnabled) return;
   if(!CanUseRouletteWithCurrentSizing())
   {
      g_RiskRouletteEnabled = false;
      g_Roulette = ROULETTE_OFF;
      g_Step = 1;
      SaveState();
      return;
   }
   if(g_Roulette != ROULETTE_ON)
   {
      PrintFormat("VOLUME ROULETTE WAIT | enabled=ON | equity trigger=+%.2f%% | step=%d | base risk=%.3f%%",
                  InpRouletteTrigger, g_Step, g_BaseRisk);
      SaveState();
      return;
   }

   bool flat = (riskMoney > 0.0) ? (MathAbs(profit) < 0.15 * riskMoney)
                                : (MathAbs(profit) < 0.01);
   int before = g_Step;
   if(!flat && profit > 0.0)
      g_Step = MathMin(g_MaxStep, g_Step + 1);
   else if(!flat && profit < 0.0)
      g_Step = MathMax(1, g_Step - 1);

   double effectiveRisk = GetCurrentRiskPct();
   PrintFormat("VOLUME ROULETTE | batch net=%.2f | batch risk=%.2f | %s | step %d -> %d | risk now=%.3f%% (cap %.3f%%)",
               profit, riskMoney, flat ? "FLAT" : (profit > 0.0 ? "WIN" : "LOSS"),
               before, g_Step, effectiveRisk, InpMaxRiskPct);
   SaveState();
}


bool IsCurrentNixoPosition(ulong positionId)
{
   if(positionId == 0 || !HistorySelectByPosition(positionId)) return false;
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      long e=HistoryDealGetInteger(d,DEAL_ENTRY);
      if(e!=DEAL_ENTRY_IN) continue;
      string c=HistoryDealGetString(d,DEAL_COMMENT);
      if(StringFind(c,"Nixo500|")==0) return true;
   }
   return false;
}


bool ReadPositionRealizedNet(ulong positionId, double &realizedNet)
{
   realizedNet=0.0;
   if(positionId==0 || !HistorySelectByPosition(positionId)) return false;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      realizedNet += HistoryDealGetDouble(deal,DEAL_COMMISSION)
                   + HistoryDealGetDouble(deal,DEAL_FEE);
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
         realizedNet += HistoryDealGetDouble(deal,DEAL_PROFIT)
                      + HistoryDealGetDouble(deal,DEAL_SWAP);
   }
   return true;
}

bool ShouldLogSLWait(ulong ticket)
{
   string key=GVKey("SLWAIT_"+(string)ticket);
   datetime now=TimeCurrent();
   if(GlobalVariableCheck(key))
   {
      datetime last=(datetime)(long)GlobalVariableGet(key);
      if(last>0 && now-last<10) return false;
   }
   GlobalVariableSet(key,(double)now);
   return true;
}

long BatchIdFromComment(string comment)
{
   int at = StringFind(comment, "|B");
   if(at < 0) return 0;
   int start = at + 2;
   int end = StringFind(comment, "|", start);
   string value = (end < 0) ? StringSubstr(comment, start) : StringSubstr(comment, start, end-start);
   return (long)StringToInteger(value);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)==InpSignalMagic)
   {
      if(HistoryDealGetInteger(trans.deal,DEAL_ENTRY)==DEAL_ENTRY_IN || HistoryDealGetInteger(trans.deal,DEAL_ENTRY)==DEAL_ENTRY_INOUT)
         ReportCaptureEntryDeal(trans.deal,trans.order);
      SignalAddRealizedDeal(trans);
      return;
   }
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   // Snapshot deal properties before HistorySelectByPosition changes the selected history list.
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long dealTypeSnapshot = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   ulong positionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   string dealComment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   bool belongsToThisEngine=(StringFind(dealComment,"Nixo500|")==0);
   if(!belongsToThisEngine && (entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT))
      belongsToThisEngine=IsCurrentNixoPosition(positionId);
   if(belongsToThisEngine && positionId>0)
   {
      double realizedNetCache=0.0;
      if(ReadPositionRealizedNet(positionId,realizedNetCache))
         GlobalVariableSet(PositionStateKey(positionId,"NR"),realizedNetCache);
   }

   if(entry == DEAL_ENTRY_IN)
   {
      ReportCaptureEntryDeal(trans.deal,trans.order);
      // Final safety gate: pending orders can fill without passing through TryOpen().
      // With Hedge OFF, immediately close a newly filled opposite Nixo position.
      if(StringFind(dealComment,"Nixo500|")==0 && !g_HedgeEnabled && (dealTypeSnapshot==DEAL_TYPE_BUY || dealTypeSnapshot==DEAL_TYPE_SELL))
      {
         ENUM_ORDER_TYPE filledType = (dealTypeSnapshot==DEAL_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
         if(HasOppositePosition(filledType))
         {
            for(int pi=PositionsTotal()-1; pi>=0; pi--)
            {
               ulong ptk=PositionGetTicket(pi);
               if(ptk==0) continue;
               if((ulong)PositionGetInteger(POSITION_IDENTIFIER)!=positionId) continue;
               bool closeSent=trade.PositionClose(ptk);
               if(closeSent && (trade.ResultRetcode()==TRADE_RETCODE_DONE || trade.ResultRetcode()==TRADE_RETCODE_DONE_PARTIAL))
                  PrintFormat("HEDGE GUARD CLOSE | filled %s position=%I64u | opposite position existed while HEDGE=OFF",
                              filledType==ORDER_TYPE_BUY?"BUY":"SELL", positionId);
               else
                  PrintFormat("HEDGE GUARD CLOSE FAILED | position=%I64u | retcode=%u %s",
                              positionId,trade.ResultRetcode(),trade.ResultRetcodeDescription());
               break;
            }
            if(StringFind(dealComment,"Nixo500|NYAO|")==0) CancelNyaoPendingOrders();
            return;
         }
      }

      // Normal market entries are counted in TryOpen(). Pending-straddle fills are counted here once per position.
      if(StringFind(dealComment, "Nixo500|") == 0)
      {
         bool isNyao=(StringFind(dealComment,"Nixo500|NYAO|")==0);
         bool isManualPending=(StringFind(dealComment,"Nixo500|MANUAL_LIMIT|")==0);
         bool isRRPending=(StringFind(dealComment,"Nixo500|RR_PENDING|M|")==0);
         string entrySeenKey=GVKey("ENTRY_"+(string)positionId);
         bool firstFill=(positionId>0 && !GlobalVariableCheck(entrySeenKey));
         // TryOpen/RR market entries are counted at submission. Server-side pending fills are counted here.
         if(firstFill && (isNyao || isManualPending || isRRPending))
         {
            GlobalVariableSet(entrySeenKey,(double)TimeCurrent());
            RecordEntryTimestamp();
            g_TradesToday++;
         }
         if(isNyao) CancelNyaoPendingOrders();
         long batch=BatchIdFromComment(dealComment);
         if(positionId>0 && batch>0 && !GlobalVariableCheck(GVKey("BPOS_"+(string)positionId))) RegisterBatchPosition(batch,positionId);
         if(positionId>0 && !GlobalVariableCheck(PositionStateKey(positionId,"SP")))
            GlobalVariableSet(PositionStateKey(positionId,"SP"),MathMax(0.0,SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID)));
         if(positionId>0 && !GlobalVariableCheck(PositionStateKey(positionId,"A")))
         {
            string pendingAnchorKey=GVKey("PEND_A_"+(string)trans.order);
            double pendingAnchor=GlobalVariableCheck(pendingAnchorKey)?GlobalVariableGet(pendingAnchorKey):g_TPAnchorR;
            GlobalVariableSet(PositionStateKey(positionId,"A"),pendingAnchor);
            if(GlobalVariableCheck(pendingAnchorKey)) GlobalVariableDel(pendingAnchorKey);
         }
         if(positionId>0 && !GlobalVariableCheck(GVKey("RISK_"+(string)positionId)))
         {
            for(int i=PositionsTotal()-1;i>=0;i--)
            {
               ulong tk=PositionGetTicket(i); if(tk==0) continue;
               if((ulong)PositionGetInteger(POSITION_IDENTIFIER)!=positionId) continue;
               long pt=PositionGetInteger(POSITION_TYPE);
               ENUM_ORDER_TYPE ot=(pt==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
               double vol=PositionGetDouble(POSITION_VOLUME),op=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL);
               if(sl>0.0) GlobalVariableSet(GVKey("RISK_"+(string)positionId),ActualRiskMoney(ot,vol,op,sl));
               if(UseStagedTP())
               {
                  if(!MultiTPPlanValid(vol))
                  {
                     // Unexpected partial fill: preserve safety with a broker-side TP3 that closes the whole undersized position.
                     GlobalVariableSet(PositionStateKey(positionId,"F"),1.0);
                     double fallbackTP=(pt==POSITION_TYPE_BUY)?op+MathAbs(op-sl)*g_TPAnchorR:op-MathAbs(op-sl)*g_TPAnchorR;
                     fallbackTP=NormalizeDouble(fallbackTP,_Digits);
                     trade.PositionModify(tk,sl,fallbackTP);
                     PrintFormat("RUNNER FALLBACK | position=%I64u | actual lot=%.4f cannot support 3 partial closes; broker TP3 will close full remainder.",positionId,vol);
                  }
                  else
                     PrintFormat("3-STAGE TP ARMED | position=%I64u | lot=%.4f | TP1=%.2fR close 50%% initial | TP2=%.2fR close 50%% remaining | TP3=%.2fR close 50%% remaining | Runner=12.5%% with %.2f ATR trail",
                                 positionId,vol,g_TP1R,g_TP2R,g_TPAnchorR,g_RunnerTrailATR);
               }
               break;
            }
         }
      }
      return;
   }

   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT) return;
   if(!IsCurrentNixoPosition(positionId)) return; // do not alter v4.8/v4.9/manual positions
   string closedKey = GVKey("C_" + (string)positionId);
   if(GlobalVariableCheck(closedKey)) return;
   double netProfit = 0.0;
   if(!GetFullyClosedPositionNet(positionId, netProfit)) return;

   double closedRiskMoney = 0.0;
   string riskKey = GVKey("RISK_" + (string)positionId);
   if(GlobalVariableCheck(riskKey))
   {
      closedRiskMoney = GlobalVariableGet(riskKey);
      GlobalVariableDel(riskKey);
   }
   GlobalVariableSet(closedKey, (double)TimeCurrent());
   GlobalVariableDel(GVKey("ENTRY_" + (string)positionId));
   ClearMultiTPState(positionId);
   ProcessClosedTrade(netProfit, closedRiskMoney);
   ProcessBatchRoulette(positionId, netProfit, closedRiskMoney);
   RefreshStats();
}

//==================================================================
//  RISK LADDER / ROULETTE
//   • Roulette ON : risk = BaseRisk × Step  (capped by MaxRiskPct)
//   • Every WIN   : +1 step
//   • Every STOP  : −1 step (minimum step 1)
//==================================================================
double GetCurrentRiskPct()
{
   if(!g_RiskRouletteEnabled || g_Roulette != ROULETTE_ON)
      return g_BaseRisk;

   // STEP scaling: base value × step (example: 0.25% => 0.50% => 0.75% => 1.00% ...)
   double risk = g_BaseRisk * g_Step;
   if(risk > InpMaxRiskPct) risk = InpMaxRiskPct;
   return risk;
}

void UpdateRouletteState()
{
   if(!g_RiskRouletteEnabled)
   {
      g_Roulette = ROULETTE_OFF;
      g_Step = 1;
      return;
   }
   if(g_Stopped || g_StartEquity <= 0) return;
   if(g_Roulette != ROULETTE_OFF) return;

   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double profitPct = (equity - g_StartEquity) / g_StartEquity * 100.0;

   if(InpRouletteTrigger <= 0.0 || profitPct >= InpRouletteTrigger)
   {
      g_Roulette     = ROULETTE_ON;
      g_CycleStartEq = equity;
      g_Step         = 1;
      Print("★ ROULETTE ACTIVATED at ", DoubleToString(profitPct, 2), "%");
      SaveState();
   }
}

void ProcessClosedTrade(double profit, double closedRiskMoney)
{
   if(g_Stopped) return;

   bool flat = (closedRiskMoney > 0.0)
               ? (MathAbs(profit) < 0.15 * closedRiskMoney)
               : (MathAbs(profit) < 0.01); // fallback for positions not opened by this engine

   // ---- loss-streak cooldown (full positions only)
   if(!flat)
   {
      if(profit > 0.0) g_ConsecLosses = 0;
      else
      {
         g_ConsecLosses++;
         if(InpMaxConsecLosses > 0 && InpCooldownMinutes > 0 &&
            g_ConsecLosses >= InpMaxConsecLosses)
         {
            g_CooldownUntil = TimeCurrent() + (datetime)(InpCooldownMinutes * 60);
            g_ConsecLosses = 0;
            PrintFormat("OPTIONAL COOLDOWN | %d consecutive losses → no new entries until %s",
                        InpMaxConsecLosses, TimeToString(g_CooldownUntil, TIME_DATE | TIME_MINUTES));
         }
      }
   }

   // Risk-volume roulette is advanced once per completed signal batch in ProcessBatchRoulette().
   // This avoids a 30-order batch increasing/decreasing the volume ladder 30 times.
   UpdateRouletteState();
   SaveState();
}

void CheckHardStop()
{
   if(g_Stopped || g_StartEquity <= 0) return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct  = (g_StartEquity - equity) / g_StartEquity * 100.0;

   if(InpHardStopPct > 0.0 && ddPct >= InpHardStopPct)
   {
      g_Stopped = true;
      g_Running = false;
      SaveState();

      for(int i = PositionsTotal()-1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagic)
            trade.PositionClose(ticket);
      }
      Print("!!! HARD STOP triggered at -", DoubleToString(ddPct, 2), "%");
      Alert("Nixo HARD STOP – trading halted");
   }
}

//==================================================================
//  LOT CALCULATION  (selected % risk / fixed cash / fixed volume)
//==================================================================
int VolumeDigits(double step)
{
   int d = 0;
   double s = step;
   while(d < 8 && MathAbs(s - MathRound(s)) > 1e-9) { s *= 10.0; d++; }
   return d;
}

double SelectedRiskBase()
{
   if(InpRiskBaseMode==NIXO_BASE_BALANCE) return AccountInfoDouble(ACCOUNT_BALANCE);
   if(InpRiskBaseMode==NIXO_BASE_FREE_MARGIN) return AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   return AccountInfoDouble(ACCOUNT_EQUITY);
}

double CalcLot(ENUM_ORDER_TYPE type, double riskPct, double slDist, double price, double cashRiskOverride, int sizingModeOverride, double fixedLotOverride)
{
   if(slDist <= 0) return 0;

   double equity = SelectedRiskBase();
   int sizingMode = (sizingModeOverride>=0 ? sizingModeOverride : (int)InpPositionSizeMode);
   double riskMoney = equity * riskPct / 100.0;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0 || minLot <= 0)
   {
      Print("CalcLot: invalid volume properties");
      return 0;
   }

   // Estimate adverse SL execution including configurable slippage and round-turn commission.
   double riskDistance = slDist + MathMax(0, InpRiskSlippagePoints) * _Point;
   double slPrice = (type == ORDER_TYPE_BUY) ? price - riskDistance : price + riskDistance;
   double pl = 0, lossPerLot = 0;
   if(OrderCalcProfit(type, _Symbol, 1.0, price, slPrice, pl) && pl < 0)
      lossPerLot = -pl;
   else
   {
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickValue <= 0) tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue > 0 && tickSize > 0)
         lossPerLot = (riskDistance / tickSize) * tickValue;
   }
   double commissionRT = EstimateRoundTurnCommissionPerLot();
   lossPerLot += commissionRT;
   if(lossPerLot <= 0)
   {
      Print("CalcLot: lossPerLot invalid");
      return 0;
   }

   double rawLot = 0.0;
   if(sizingMode==NIXO_SIZE_RISK_PERCENT)
   {
      riskMoney = equity * riskPct / 100.0;
      rawLot = riskMoney / lossPerLot;
   }
   else if(sizingMode==NIXO_SIZE_FIXED_MONEY)
   {
      riskMoney = (cashRiskOverride>0.0 ? cashRiskOverride : InpFixedRiskMoney);
      rawLot = riskMoney / lossPerLot;
   }
   else
   {
      rawLot = (fixedLotOverride>0.0 ? fixedLotOverride : InpFixedLot);
      riskMoney = rawLot * lossPerLot;
   }
   if(rawLot<=0.0) return 0.0;
   double lot = rawLot;

   if(g_MaxLot > 0.0 && lot > g_MaxLot) lot = g_MaxLot; // optional user max-lot cap (0=off)
   if(lot > maxLot)   lot = maxLot;

   int vd = VolumeDigits(step);
   lot = NormalizeDouble(MathFloor(lot / step + 1e-9) * step, vd);

   if(lot < minLot)
   {
      PrintFormat("CalcLot: lot below broker minimum (%s < %s) – trade skipped",
                  DoubleToString(lot, vd), DoubleToString(minLot, vd));
      return 0;
   }

   // margin check
   double margin = 0;
   if(OrderCalcMargin(type, _Symbol, lot, price, margin) && margin > 0)
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin * 0.65)
      {
         lot = lot * (freeMargin * 0.65 / margin);
         lot = NormalizeDouble(MathFloor(lot / step + 1e-9) * step, vd);
         if(lot < minLot)
         {
            Print("CalcLot: not enough free margin");
            return 0;
         }
      }
   }

   string capNote = (g_MaxLot > 0.0 && rawLot > g_MaxLot + 1e-9) ? "  [CAPPED by Max lot]" : "";
   PrintFormat(">>> LOT CALC | Mode=%d | RiskBase=%.2f | Risk=%.2f%% | RiskMoney=%.2f %s | SL dist=%.5f | SlipPts=%d | CommRT/lot=%.2f | Loss/lot=%.2f | RawLot=%s | FinalLot=%s%s",
               sizingMode,equity, riskPct, riskMoney, AccountInfoString(ACCOUNT_CURRENCY),slDist, InpRiskSlippagePoints, commissionRT, lossPerLot,
               DoubleToString(rawLot, 3), DoubleToString(lot, vd), capNote);
   if(commissionRT <= 0.0)
      Print("WARNING: round-turn commission estimate unavailable. Set InpCommissionPerLotRT manually for conservative sizing.");

   return lot;
}

double ActualRiskMoney(ENUM_ORDER_TYPE type, double lot, double price, double sl)
{
   double adverseSL = (type == ORDER_TYPE_BUY) ? sl - MathMax(0, InpRiskSlippagePoints) * _Point
                                                : sl + MathMax(0, InpRiskSlippagePoints) * _Point;
   double pl = 0;
   if(!OrderCalcProfit(type, _Symbol, lot, price, adverseSL, pl)) return 0.0;
   return MathAbs(pl) + EstimateRoundTurnCommissionPerLot() * lot;
}

bool TryOpen(ENUM_ORDER_TYPE type, string reason)
{
   if(!TradingModeAllowsEntry(reason))
   {
      if(InpDebug) PrintFormat("ENTRY ROUTER BLOCK | reason=%s | mode=%s | entriesPaused=%s",
         reason,TradingModeName(g_TradingMode),g_EntriesPaused?"YES":"NO");
      return false;
   }
   bool batchMode = (g_MultiOrderEnabled || g_OrderRouletteEnabled || TurboActive());
   if(g_DailyStopped || g_Stopped) return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      Alert("Trading not allowed – check AutoTrading and account permissions");
      return false;
   }

   if(EntryRateLimitReached())
   {
      if(InpDebug) Print("TryOpen blocked – optional max trades/minute reached");
      return false;
   }
   int maxPositions = MaxOpenAllowed();
   if(InpMaxOrderCount > 0) maxPositions = MathMin(maxPositions, InpMaxOrderCount);
   if(CountMyPositions() >= maxPositions)
   {
      if(InpDebug) PrintFormat("TryOpen blocked – optional max open positions reached (%d)", maxPositions);
      return false;
   }
   if(!g_HedgeEnabled && HasOppositePosition(type))
   {
      if(InpDebug) PrintFormat("HEDGE GUARD BLOCK | requested=%s | HEDGE=OFF | opposite Nixo position already open", type==ORDER_TYPE_BUY?"BUY":"SELL");
      return false;
   }
   if(InpMaxOrderCount > 0 && batchMode && CountMyPositions() >= InpMaxOrderCount) return false;
   if(DailyTradeLimitReached()) return false;

   double slDist = (reason=="MANUAL" ? ComputeSLDistWithMultiplier(g_ManualSLATR) : ComputeSLDist());

   MqlTick liveTick;
   if(!SymbolInfoTick(_Symbol, liveTick)) return false;
   double price = (type == ORDER_TYPE_BUY) ? liveTick.ask : liveTick.bid;
   if(price <= 0) return false;

   // cost filter: tight stops are only worth taking when spread+commission is a small slice of the stop
   if(reason != "MANUAL" && g_MaxSpreadPct > 0.0)
   {
      double costPct = CostDistance() / slDist * 100.0;
      if(costPct > g_MaxSpreadPct)
      {
         if(InpDebug)
            PrintFormat("COST FILTER skip | cost=%.1f%% of stop (limit %.1f%%) | SL dist=%.5f", costPct, g_MaxSpreadPct, slDist);
         return false;
      }
   }

   double riskPct = (reason=="MANUAL" && g_ManualSizeMode==NIXO_SIZE_RISK_PERCENT) ? g_ManualSizeValue : GetCurrentRiskPct();
   if(batchMode && InpSplitRiskAcrossOrders && reason != "MANUAL")
   {
      int splitCount = (g_ActiveBatchOrders > 0 ? g_ActiveBatchOrders : g_OrderCount);
      riskPct /= (double)MathMax(1, splitCount);
   }
   double cashRiskBudget = (reason=="MANUAL" && g_ManualSizeMode==NIXO_SIZE_FIXED_MONEY) ? g_ManualSizeValue : InpFixedRiskMoney;
   if(InpPositionSizeMode==NIXO_SIZE_FIXED_MONEY && batchMode && InpSplitRiskAcrossOrders && reason!="MANUAL")
   {
      int splitCount=(g_ActiveBatchOrders>0?g_ActiveBatchOrders:g_OrderCount);
      cashRiskBudget/=MathMax(1,splitCount);
   }
   int sizingOverride=(reason=="MANUAL"?(int)g_ManualSizeMode:-1);
   double fixedLotOverride=(reason=="MANUAL" && g_ManualSizeMode==NIXO_SIZE_FIXED_LOT)?g_ManualSizeValue:-1.0;
   double lot = CalcLot(type, riskPct, slDist, price,
                        ((reason=="MANUAL" && g_ManualSizeMode==NIXO_SIZE_FIXED_MONEY) || InpPositionSizeMode==NIXO_SIZE_FIXED_MONEY)?cashRiskBudget:-1.0,
                        sizingOverride,fixedLotOverride);
   if(lot <= 0)
   {
      Print("TryOpen aborted – lot = 0");
      return false;
   }
   bool multiPlanOK = (!UseStagedTP() || MultiTPPlanValid(lot));
   if(UseStagedTP() && !multiPlanOK)
   {
      PrintFormat("TryOpen skipped: lot %.4f cannot execute three half-volume closes and leave a valid 12.5%% runner at this broker's min/step.", lot);
      return false;
   }

   double sl, tp;
   if(type == ORDER_TYPE_BUY)
   {
      sl = NormalizeDouble(price - slDist, _Digits);
      tp = UseStagedTP() ? 0.0
                         : (TurboActive() ? 0.0 : NormalizeDouble(price + slDist * g_TPRR, _Digits));
   }
   else
   {
      sl = NormalizeDouble(price + slDist, _Digits);
      tp = UseStagedTP() ? 0.0
                         : (TurboActive() ? 0.0 : NormalizeDouble(price - slDist * g_TPRR, _Digits));
   }

   // Aggregate risk cap is enforced for single, multi-order, roulette and Turbo entries.
   if(InpMaxOpenRiskPct > 0.0)
   {
      double baseEq   = SelectedRiskBase();
      double newRisk  = ActualRiskMoney(type, lot, price, sl);
      double openRisk = OpenRiskMoney(); // includes Manual + Strategy + External + pending risk
      double capMoney = baseEq * InpMaxOpenRiskPct / 100.0;
      if(openRisk + newRisk > capMoney + 1e-9)
      {
         if(InpDebug)
            PrintFormat("OPEN-RISK CAP skip | open=%.2f + new=%.2f > cap=%.2f (%.2f%%)", openRisk, newRisk, capMoney, InpMaxOpenRiskPct);
         return false;
      }
   }

   bool ownBatch = (g_ActiveBatchId <= 0);
   long batchId = ownBatch ? NextBatchId() : g_ActiveBatchId;
   string reasonCode = (reason == "MANUAL" ? "M" : (reason == "TURBO" ? "T" : "A"));
   string comment = StringFormat("Nixo500|S%d|%s|B%I64d", g_Strategy, reasonCode, batchId);

   bool ok = (type == ORDER_TYPE_BUY) ? trade.Buy (lot, _Symbol, 0.0, sl, tp, comment)
                                      : trade.Sell(lot, _Symbol, 0.0, sl, tp, comment);

   if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_DONE_PARTIAL || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
   {
      g_TradesToday++;
      RecordEntryTimestamp();
      double base      = SelectedRiskBase();
      int reportSizeMode=(reason=="MANUAL"?(int)g_ManualSizeMode:(int)InpPositionSizeMode);
      double planned   = (reportSizeMode==NIXO_SIZE_RISK_PERCENT) ? base*riskPct/100.0
                         : (reportSizeMode==NIXO_SIZE_FIXED_MONEY ? cashRiskBudget : ActualRiskMoney(type,lot,price,sl));
      double fillPrice = (trade.ResultPrice() > 0) ? trade.ResultPrice() : price;
      double actual    = ActualRiskMoney(type, lot, fillPrice, sl);

      g_LastLot       = lot;
      g_LastRiskMoney = actual;
      g_LastRiskPct   = (base > 0) ? actual / base * 100.0 : 0;

      ulong openingDeal = trade.ResultDeal();
      if(openingDeal > 0 && HistoryDealSelect(openingDeal))
      {
         ulong positionId = (ulong)HistoryDealGetInteger(openingDeal, DEAL_POSITION_ID);
         if(positionId > 0)
         {
            GlobalVariableSet(GVKey("RISK_" + (string)positionId), actual);
            GlobalVariableSet(PositionStateKey(positionId,"SP"),MathMax(0.0,liveTick.ask-liveTick.bid));
            GlobalVariableSet(PositionStateKey(positionId,"A"),(reason=="MANUAL"?g_ManualTP3R:g_TPAnchorR));
            GlobalVariableSet(PositionStateKey(positionId,"TP1"),g_TP1R);
            GlobalVariableSet(PositionStateKey(positionId,"TP2"),g_TP2R);
            GlobalVariableSet(PositionStateKey(positionId,"RATR"),g_RunnerTrailATR);
            GlobalVariableSet(PositionStateKey(positionId,"BE"),g_UseBE?1.0:0.0);
            GlobalVariableSet(PositionStateKey(positionId,"BER"),InpBE_R);
            GlobalVariableSet(PositionStateKey(positionId,"MULTI"),UseStagedTP()?1.0:0.0);
            GlobalVariableSet(PositionStateKey(positionId,"TIME"),(double)InpTimeStopBars);
            GlobalVariableSet(PositionStateKey(positionId,"TIMEMIN"),InpTimeStopMinR);
            GlobalVariableSet(PositionStateKey(positionId,"MODE"),(double)g_TradingMode);
            GlobalVariableSet(PositionStateKey(positionId,"STRAT"),(double)g_Strategy);
            GlobalVariableSet(PositionStateKey(positionId,"SL0"),sl);
            GlobalVariableSet(PositionStateKey(positionId,"RISK0"),actual);
            GlobalVariableSet(PositionStateKey(positionId,"RR0"),(reason=="MANUAL"?g_ManualTP3R:g_TPAnchorR));
            RegisterBatchPosition(batchId, positionId);
            if(openingDeal>0) ReportCaptureEntryDeal(openingDeal,trade.ResultOrder());

         }
      }
      else if(InpDebug)
         Print("WARNING: opening deal unavailable; per-position risk/batch snapshots could not be saved.");

      if(ownBatch) g_ActiveBatchId = 0;
      PrintFormat("OPENED %s | Lot=%s | SL=%.5f | TP=%.5f | Step=%d | Batch=%I64d",
                  (type==ORDER_TYPE_BUY?"BUY":"SELL"), DoubleToString(lot, VolumeDigits(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))), sl, tp, g_Step, batchId);
      PrintFormat("RISK CHECK | planned=%.2f%% (%.2f) | actual loss at SL=%.2f (%.2f%% of equity)",
                  riskPct, planned, actual, g_LastRiskPct);
      return true;
   }

   if(ownBatch) g_ActiveBatchId = 0;
   Print("Order failed: ", trade.ResultRetcode(), " – ", trade.ResultRetcodeDescription());
   return false;
}

bool PlaceManualLimit(ENUM_ORDER_TYPE type,double entryPrice)
{
   if(g_TradingMode!=NIXO_MODE_MANUAL || g_EntriesPaused) { Alert("Manual entry is blocked by current Trading Mode / entry pause."); return false; }
   if(g_Stopped || g_DailyStopped) { Alert("Trading is locked by Nixo protection."); return false; }
   if(type!=ORDER_TYPE_BUY_LIMIT && type!=ORDER_TYPE_SELL_LIMIT) return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   { Alert("Trading permissions are disabled."); return false; }
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return false;
   entryPrice=NormalizeDouble(entryPrice,_Digits);
   double minDist=MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   if(type==ORDER_TYPE_BUY_LIMIT && entryPrice>=tick.ask-minDist)
   { Alert("Buy Limit price must be below Ask by the broker's minimum distance."); return false; }
   if(type==ORDER_TYPE_SELL_LIMIT && entryPrice<=tick.bid+minDist)
   { Alert("Sell Limit price must be above Bid by the broker's minimum distance."); return false; }
   double slDist=ComputeSLDistWithMultiplier(g_ManualSLATR);
   double sl=(type==ORDER_TYPE_BUY_LIMIT)?entryPrice-slDist:entryPrice+slDist;
   double tp=UseStagedTP()?0.0:((type==ORDER_TYPE_BUY_LIMIT)?entryPrice+slDist*g_TPRR:entryPrice-slDist*g_TPRR);
   sl=NormalizeDouble(sl,_Digits); if(tp>0.0) tp=NormalizeDouble(tp,_Digits);
   ENUM_ORDER_TYPE marketType=(type==ORDER_TYPE_BUY_LIMIT)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!g_HedgeEnabled && HasOppositePosition(marketType))
   { Alert("Hedge mode is OFF: an opposite Nixo position is already open."); return false; }
   double manualRiskPct=(g_ManualSizeMode==NIXO_SIZE_RISK_PERCENT)?g_ManualSizeValue:GetCurrentRiskPct();
   double manualCash=(g_ManualSizeMode==NIXO_SIZE_FIXED_MONEY)?g_ManualSizeValue:-1.0;
   double manualFixedLot=(g_ManualSizeMode==NIXO_SIZE_FIXED_LOT)?g_ManualSizeValue:-1.0;
   double lot=CalcLot(marketType,manualRiskPct,slDist,entryPrice,manualCash,(int)g_ManualSizeMode,manualFixedLot);
   if(lot<=0.0) return false;
   if(InpMaxOpenRiskPct>0.0)
   {
      double openRisk=OpenRiskMoney();
      double newRisk=ActualRiskMoney(marketType,lot,entryPrice,sl);
      double capMoney=SelectedRiskBase()*InpMaxOpenRiskPct/100.0;
      if(openRisk+newRisk>capMoney+1e-9)
      { Alert("Unified Nixo risk cap: manual pending order would exceed total open risk."); return false; }
   }
   if(UseStagedTP() && !MultiTPPlanValid(lot))
   { Alert("Lot is too small to execute TP1/TP2/TP3 partial closes and leave the 12.5% runner. Increase lot size or change broker/symbol."); return false; }
   string comment=StringFormat("Nixo500|MANUAL_LIMIT|%s",type==ORDER_TYPE_BUY_LIMIT?"BUY":"SELL");
   bool sent=(type==ORDER_TYPE_BUY_LIMIT)
      ? trade.BuyLimit(lot,entryPrice,_Symbol,sl,tp,ORDER_TIME_GTC,0,comment)
      : trade.SellLimit(lot,entryPrice,_Symbol,sl,tp,ORDER_TIME_GTC,0,comment);
   if(PendingOrderRequestSucceeded(sent))
   {
      g_LastLot=lot; g_ManualPrice=0.0; g_PendingArmType=0;
      ObjectDelete(0,MANUAL_LINE_OBJ);
      if(ObjectFind(0,MANUAL_PRICE_OBJ)>=0) ObjectSetString(0,MANUAL_PRICE_OBJ,OBJPROP_TEXT,"0 = chart click");
      double tp3Display=(type==ORDER_TYPE_BUY_LIMIT)?entryPrice+slDist*g_ManualTP3R:entryPrice-slDist*g_ManualTP3R;
      GlobalVariableSet(GVKey("PEND_A_"+(string)trade.ResultOrder()),g_ManualTP3R);
      ReportSnapshotPendingOrder(trade.ResultOrder(),NIXO_MODE_MANUAL,-1,g_ManualTP3R);
      PrintFormat("MANUAL LIMIT PLACED | %s | entry=%.*f | lot=%.2f | SL=%.*f | virtual TP3=%.*f | three-stage R TP + runner manager on fill",
         type==ORDER_TYPE_BUY_LIMIT?"BUY LIMIT":"SELL LIMIT",_Digits,entryPrice,lot,_Digits,sl,_Digits,tp3Display);
      return true;
   }
   PrintFormat("MANUAL LIMIT FAILED | retcode=%u %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
   return false;
}

//==================================================================
//  POSITION MANAGEMENT (break-even + staged TP + Turbo)
//==================================================================
void ManagePosition()
{
   if(CountMyPositions() == 0) return;

   double stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      bool posStaged=(GlobalVariableCheck(PositionStateKey(pid,"MULTI")) ? GlobalVariableGet(PositionStateKey(pid,"MULTI"))>0.5 : UseStagedTP());
      bool posBE=(GlobalVariableCheck(PositionStateKey(pid,"BE")) ? GlobalVariableGet(PositionStateKey(pid,"BE"))>0.5 : g_UseBE);
      double posBER=(GlobalVariableCheck(PositionStateKey(pid,"BER")) ? GlobalVariableGet(PositionStateKey(pid,"BER")) : InpBE_R);
      int posTimeStopBars=(int)(GlobalVariableCheck(PositionStateKey(pid,"TIME")) ? GlobalVariableGet(PositionStateKey(pid,"TIME")) : InpTimeStopBars);
      double posTimeStopMinR=(GlobalVariableCheck(PositionStateKey(pid,"TIMEMIN")) ? GlobalVariableGet(PositionStateKey(pid,"TIMEMIN")) : InpTimeStopMinR);
      if(posStaged && StringFind(PositionGetString(POSITION_COMMENT), "Nixo500|") != 0) continue;
      long   ptype = PositionGetInteger(POSITION_TYPE);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);

      if(posTimeStopBars > 0 && TimeStopTriggered(tk, ptype, open, sl, posTimeStopBars, posTimeStopMinR, posStaged)) continue;

      if(posStaged)
      {
         ManageMultiTPPosition(tk);
         continue;
      }

      if(!posBE || sl <= 0) continue;

      if(ptype == POSITION_TYPE_BUY && sl < open)
      {
         double R    = open - sl;
         double trig = posBER * R;
         if(tp > 0) trig = MathMin(trig, 0.7 * (tp - open));
         if(bid - open >= trig)
         {
            double nsl = NormalizeDouble(open + 0.1 * R, _Digits);
            if(bid - nsl > stopsLvl + _Point) trade.PositionModify(tk, nsl, tp);
         }
      }
      else if(ptype == POSITION_TYPE_SELL && sl > open)
      {
         double R    = sl - open;
         double trig = posBER * R;
         if(tp > 0) trig = MathMin(trig, 0.7 * (open - tp));
         if(open - ask >= trig)
         {
            double nsl = NormalizeDouble(open - 0.1 * R, _Digits);
            if(nsl - ask > stopsLvl + _Point) trade.PositionModify(tk, nsl, tp);
         }
      }
   }
}

int CountMyPositions()
{
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         cnt++;
   }
   return cnt;
}

double FloatingPL()
{
   double sum = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         sum += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return sum;
}

struct PosAgg { ulong id; double net; double inVol; double outVol; };

// Win rate / PF are computed per FULL position (partial TP deals are merged), same basis as the roulette.
void RefreshStats()
{
   g_Trades = 0; g_Wins = 0; g_GrossP = 0; g_GrossL = 0; g_NetProfit = 0.0;
   if(!HistorySelect(g_StatsFrom, TimeCurrent() + 86400)) return;

   PosAgg a[];
   int n = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString (t, DEAL_SYMBOL) != _Symbol) continue;

      long e = HistoryDealGetInteger(t, DEAL_ENTRY);
      if(e != DEAL_ENTRY_IN && e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY && e != DEAL_ENTRY_INOUT) continue;

      ulong pid = (ulong)HistoryDealGetInteger(t, DEAL_POSITION_ID);
      if(pid == 0) continue;

      int idx = -1;
      int lo = MathMax(0, n - 200);
      for(int k = n - 1; k >= lo; k--)
         if(a[k].id == pid) { idx = k; break; }
      if(idx < 0)
      {
         if(n >= ArraySize(a)) ArrayResize(a, n + 256);
         idx = n;
         a[idx].id = pid; a[idx].net = 0.0; a[idx].inVol = 0.0; a[idx].outVol = 0.0;
         n++;
      }

      double vol = HistoryDealGetDouble(t, DEAL_VOLUME);
      a[idx].net += HistoryDealGetDouble(t, DEAL_COMMISSION) + HistoryDealGetDouble(t, DEAL_FEE);
      if(e == DEAL_ENTRY_IN) a[idx].inVol += vol;
      else
      {
         a[idx].outVol += vol;
         a[idx].net += HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP);
      }
   }

   for(int j = 0; j < n; j++)
   {
      if(a[j].inVol <= 0.0 || a[j].outVol + 1e-8 < a[j].inVol) continue;   // still open / partially closed
      g_Trades++;
      g_NetProfit += a[j].net;
      if(a[j].net > 0.0)      { g_Wins++; g_GrossP += a[j].net; }
      else if(a[j].net < 0.0) { g_GrossL += -a[j].net; }
   }
   double netPF=(g_GrossL>0.0?g_GrossP/g_GrossL:(g_GrossP>0.0?99.0:0.0));
   PrintFormat("NIXO REALIZED SUMMARY | closed positions=%d | wins=%d | net P/L=%.2f | net PF=%.2f | WinRate=%.1f%%",
      g_Trades,g_Wins,g_NetProfit,netPF,g_Trades>0?100.0*g_Wins/g_Trades:0.0);
}

bool IsSpreadTooHigh()
{
   if(InpMaxSpread <= 0) return false;
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread > InpMaxSpread);
}

bool IsInSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpSessionStartH <= InpSessionEndH)
      return (dt.hour >= InpSessionStartH && dt.hour < InpSessionEndH);
   return (dt.hour >= InpSessionStartH || dt.hour < InpSessionEndH);
}

int EffectiveDailyTradeLimit()
{
   return (g_PortfolioMode || g_Strategy >= STRAT_SAFE_BREAK) ? g_ScalpMaxTradesDay : g_MaxTradesDay;
}

bool DailyTradeLimitReached()
{
   int lim = EffectiveDailyTradeLimit();
   return (lim > 0 && g_TradesToday >= lim);
}

//==================================================================
//  INDICATOR HELPERS
//==================================================================
// index 0 = newest value, index 1 = last CLOSED bar
bool GetBuf(int handle, int bufIdx, int shift, int count, double &arr[])
{
   ArraySetAsSeries(arr, true);
   return (CopyBuffer(handle, bufIdx, shift, count, arr) == count);
}

double GetATR(int shift = 1)
{
   double buf[];
   if(!GetBuf(h_ATR, 0, shift, 1, buf)) return 0;
   return buf[0];
}

struct SwingPt { int shift; double price; };

// Fractal swings on closed bars only. Output arrays are ordered newest → oldest.
bool FindSwings(int strength, int lookback, int maxPts, SwingPt &H[], SwingPt &L[])
{
   double hi[], lo[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   int need = lookback + strength + 2;
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, need, hi) != need) return false;
   if(CopyLow (_Symbol, PERIOD_CURRENT, 0, need, lo) != need) return false;

   ArrayResize(H, 0);
   ArrayResize(L, 0);

   for(int s = strength + 1; s <= lookback; s++)
   {
      bool isH = true, isL = true;
      for(int k = 1; k <= strength; k++)
      {
         if(!(hi[s] >  hi[s-k]) || !(hi[s] >= hi[s+k])) isH = false;
         if(!(lo[s] <  lo[s-k]) || !(lo[s] <= lo[s+k])) isL = false;
      }
      if(isH && ArraySize(H) < maxPts)
      {
         int n = ArraySize(H);
         ArrayResize(H, n + 1);
         H[n].shift = s; H[n].price = hi[s];
      }
      if(isL && ArraySize(L) < maxPts)
      {
         int n = ArraySize(L);
         ArrayResize(L, n + 1);
         L[n].shift = s; L[n].price = lo[s];
      }
   }
   return true;
}

//==================================================================
//  STRATEGY 1 – RTM + LFT
//  Quasimodo (change-of-character) zone with liquidity grab:
//   SELL: LS-high → low A → HEAD (higher high = liquidity grab) →
//         break below A → price returns to LS-high zone and rejects.
//   BUY : mirror image.
//==================================================================
int Signal_RTM_LFT()
{
   SwingPt H[], L[];
   if(!FindSwings(2, 70, 4, H, L)) return 0;
   if(ArraySize(H) < 2 || ArraySize(L) < 2) return 0;

   double atr = GetATR(1);
   if(atr <= 0) return 0;

   double o1 = iOpen (_Symbol, PERIOD_CURRENT, 1);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow  (_Symbol, PERIOD_CURRENT, 1);
   double tol = 0.25 * atr;

   // ---- bearish QM:  H[1] > L[1] > H[0] > L[0]  (shift: bigger = older)
   if(H[1].shift > L[1].shift && L[1].shift > H[0].shift && H[0].shift > L[0].shift &&
      H[0].price > H[1].price && L[0].price < L[1].price && L[0].shift <= 30)
   {
      double zone = H[1].price;
      if(MathAbs(zone - g_LastQMZone) > 0.1 * atr &&
         h1 >= zone - tol && c1 < zone && c1 < o1 && c1 < H[0].price)
      {
         g_LastQMZone = zone;
         return -1;
      }
   }

   // ---- bullish QM:  L[1] > H[1] > L[0] > H[0]
   if(L[1].shift > H[1].shift && H[1].shift > L[0].shift && L[0].shift > H[0].shift &&
      L[0].price < L[1].price && H[0].price > H[1].price && H[0].shift <= 30)
   {
      double zone = L[1].price;
      if(MathAbs(zone - g_LastQMZone) > 0.1 * atr &&
         l1 <= zone + tol && c1 > zone && c1 > o1 && c1 > L[0].price)
      {
         g_LastQMZone = zone;
         return 1;
      }
   }
   return 0;
}

//==================================================================
//  STRATEGY 2 – Dreams Liquidity Sweep
//  Sweep of the N-bar high/low, strong rejection wick, close back
//  inside; optionally only in the direction of EMA200.
//==================================================================
int Signal_Dreams()
{
   double atr = GetATR(1);
   if(atr <= 0) return 0;

   double o1 = iOpen (_Symbol, PERIOD_CURRENT, 1);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow  (_Symbol, PERIOD_CURRENT, 1);

   double rng = h1 - l1;
   if(rng <= 0 || rng > 3.0 * atr) return 0;       // skip news spikes

   double hiN = 0, loN = DBL_MAX;
   for(int i = 2; i <= InpSweepBars + 1; i++)
   {
      hiN = MathMax(hiN, iHigh(_Symbol, PERIOD_CURRENT, i));
      loN = MathMin(loN, iLow (_Symbol, PERIOD_CURRENT, i));
   }

   double lowWick = MathMin(o1, c1) - l1;
   double upWick  = h1 - MathMax(o1, c1);

   bool sweepLow  = (l1 < loN && c1 > loN && lowWick >= 0.5 * atr && (c1 - l1) / rng >= 0.6);
   bool sweepHigh = (h1 > hiN && c1 < hiN && upWick  >= 0.5 * atr && (h1 - c1) / rng >= 0.6);

   if(InpTrendFilter)
   {
      double e200[];
      if(!GetBuf(h_EMAS, 0, 0, 3, e200)) return 0;
      if(sweepLow  && c1 < e200[1]) sweepLow  = false;
      if(sweepHigh && c1 > e200[1]) sweepHigh = false;
   }

   if(sweepLow)  return 1;
   if(sweepHigh) return -1;
   return 0;
}

//==================================================================
//  STRATEGY 3 – SAFE BREAKOUT SCALPER
//  Inspired by the public ExMachina SafeScalping six-filter model:
//  EMA alignment, ATR trend-strength, price location, N-bar breakout,
//  healthy RSI and candle momentum. Original Nixo implementation.
//==================================================================
int Signal_SafeBreakout()
{
   double e21[], e50[], e200[], rsi[], adx[], pdi[], mdi[];
   if(!GetBuf(h_EMA21, 0, 0, 3, e21))   return 0;
   if(!GetBuf(h_EMAF,  0, 0, 3, e50))   return 0;
   if(!GetBuf(h_EMAS,  0, 0, 3, e200))  return 0;
   if(!GetBuf(h_RSI,   0, 0, 3, rsi))   return 0;
   if(!GetBuf(h_ADX,   0, 0, 3, adx))   return 0;
   if(!GetBuf(h_ADX,   1, 0, 3, pdi))   return 0;
   if(!GetBuf(h_ADX,   2, 0, 3, mdi))   return 0;

   double atr = GetATR(1);
   if(atr <= 0.0 || adx[1] < InpSafeADXMin) return 0;

   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double c2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double o1 = iOpen (_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow  (_Symbol, PERIOD_CURRENT, 1);
   double body = MathAbs(c1-o1);
   double buffer = MathMax(0.0, InpSafeBufferATR) * atr;
   double maxHigh = -DBL_MAX, minLow = DBL_MAX;
   int lookback = (int)Clampd(InpSafeBreakoutBars, 3, 50);
   for(int i=2; i<=lookback+1; i++)
   {
      maxHigh = MathMax(maxHigh, iHigh(_Symbol, PERIOD_CURRENT, i));
      minLow  = MathMin(minLow,  iLow (_Symbol, PERIOD_CURRENT, i));
   }

   bool bullTrend = e21[1] > e50[1] && e50[1] > e200[1] && pdi[1] > mdi[1];
   bool bearTrend = e21[1] < e50[1] && e50[1] < e200[1] && mdi[1] > pdi[1];
   bool bullStrength = (e21[1]-e200[1]) >= 0.20*atr;
   bool bearStrength = (e200[1]-e21[1]) >= 0.20*atr;
   bool bullBreak = c1 > maxHigh + buffer && c2 <= maxHigh;
   bool bearBreak = c1 < minLow - buffer && c2 >= minLow;
   bool candleOK = body >= MathMax(0.05, InpMomentumMinBodyATR)*atr &&
                   (h1-l1) <= MathMax(0.8, InpMaxSignalCandleATR)*atr;

   if(bullTrend && bullStrength && c1>e21[1] && c1>e50[1] && c1>e200[1] &&
      bullBreak && rsi[1]>=InpRSI_BuyMin && rsi[1]<=InpRSI_BuyMax && c1>c2 && candleOK)
      return 1;
   if(bearTrend && bearStrength && c1<e21[1] && c1<e50[1] && c1<e200[1] &&
      bearBreak && rsi[1]>=InpRSI_SellMin && rsi[1]<=InpRSI_SellMax && c1<c2 && candleOK)
      return -1;
   return 0;
}

//==================================================================
//  STRATEGY 4 – EMA + RSI + ADX + HIGHER-TF SCALPER
//  Trend pullback entry with higher-timeframe agreement. The public
//  reference reports only 19 trades, so its statistics are not treated
//  as conclusive; this is a fresh, independently coded Nixo variant.
//==================================================================
int Signal_EMA_ADX_MTF()
{
   double e21[], e50[], htfF[], htfS[], adx[], pdi[], mdi[], rsi[];
   if(!GetBuf(h_EMA21, 0, 0, 5, e21))     return 0;
   if(!GetBuf(h_EMAF,  0, 0, 5, e50))     return 0;
   if(!GetBuf(h_HTFFast,0, 0, 3, htfF))   return 0;
   if(!GetBuf(h_HTFSlow,0, 0, 3, htfS))   return 0;
   if(!GetBuf(h_ADX,   0, 0, 3, adx))     return 0;
   if(!GetBuf(h_ADX,   1, 0, 3, pdi))     return 0;
   if(!GetBuf(h_ADX,   2, 0, 3, mdi))     return 0;
   if(!GetBuf(h_RSI,   0, 0, 3, rsi))     return 0;
   double atr = GetATR(1);
   if(atr <= 0.0 || adx[1] < InpMTF_ADXMin) return 0;

   double c1=iClose(_Symbol,PERIOD_CURRENT,1), o1=iOpen(_Symbol,PERIOD_CURRENT,1);
   double h2=iHigh(_Symbol,PERIOD_CURRENT,2), l2=iLow(_Symbol,PERIOD_CURRENT,2);
   bool up = e21[1]>e50[1] && htfF[1]>htfS[1] && pdi[1]>mdi[1];
   bool dn = e21[1]<e50[1] && htfF[1]<htfS[1] && mdi[1]>pdi[1];
   bool pullbackBuy=false, pullbackSell=false;
   for(int i=1;i<=3;i++)
   {
      if(iLow(_Symbol,PERIOD_CURRENT,i) <= e21[i] + 0.18*atr) pullbackBuy=true;
      if(iHigh(_Symbol,PERIOD_CURRENT,i)>= e21[i] - 0.18*atr) pullbackSell=true;
   }
   bool bodyOK = MathAbs(c1-o1) >= 0.15*atr && MathAbs(c1-o1) <= InpMaxSignalCandleATR*atr;
   if(up && pullbackBuy && c1>e21[1] && c1>o1 && c1>h2 && rsi[1]>=48 && rsi[1]<=68 && bodyOK)
      return 1;
   if(dn && pullbackSell && c1<e21[1] && c1<o1 && c1<l2 && rsi[1]>=32 && rsi[1]<=52 && bodyOK)
      return -1;
   return 0;
}

//==================================================================
//  VWAP helper: broker-day anchored VWAP from CLOSED-bar tick volume.
//  On spot FX this is a tick-volume VWAP proxy, not centralized volume.
//==================================================================
bool GetSessionVWAP(double &vwap)
{
   vwap = 0.0;
   datetime dayStart = BrokerDayStart();
   datetime lastClosed = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(lastClosed <= dayStart) return false;

   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_CURRENT, dayStart, lastClosed, rates);
   if(copied < 2) return false;

   double pv=0.0, volSum=0.0;
   for(int i=0; i<copied; i++)
   {
      double v=(rates[i].tick_volume > 0) ? (double)rates[i].tick_volume : 1.0;
      double typical=(rates[i].high + rates[i].low + rates[i].close)/3.0;
      pv += typical*v;
      volSum += v;
   }
   if(volSum<=0.0) return false;
   vwap=pv/volSum;
   return (vwap>0.0);
}

//==================================================================
//  STRATEGY 5 – VWAP RETEST + EMA9 + PRICE-ACTION SCALPER
//  Adapted from an open-source TradingView intraday momentum setup.
//  FX/CFD VWAP uses broker tick volume and broker-day anchoring.
//==================================================================
int Signal_VWAPRetest()
{
   MqlDateTime tm; TimeToStruct(TimeCurrent(),tm);
   if(InpVWAPSessionStartH != InpVWAPSessionEndH)
   {
      if(InpVWAPSessionStartH < InpVWAPSessionEndH)
      {
         if(tm.hour<InpVWAPSessionStartH || tm.hour>=InpVWAPSessionEndH) return 0;
      }
      else if(tm.hour>=InpVWAPSessionEndH && tm.hour<InpVWAPSessionStartH) return 0;
   }

   double vwap, ema9[];
   if(!GetSessionVWAP(vwap)) return 0;
   if(!GetBuf(h_EMA9,0,0,5,ema9)) return 0;
   double atr=GetATR(1);
   if(atr<=0.0) return 0;
   double o1=iOpen(_Symbol,PERIOD_CURRENT,1), c1=iClose(_Symbol,PERIOD_CURRENT,1);
   double h1=iHigh(_Symbol,PERIOD_CURRENT,1), l1=iLow(_Symbol,PERIOD_CURRENT,1);
   double body=MathAbs(c1-o1);
   double lowerWick=MathMin(o1,c1)-l1;
   double upperWick=h1-MathMax(o1,c1);
   double buf=MathMax(0.03,InpVWAPBufferATR)*atr;
   int n=(int)Clampd(InpVWAPRetestBars,1,8);
   bool retestBuy=false, retestSell=false;
   for(int i=1;i<=n;i++)
   {
      if(iLow(_Symbol,PERIOD_CURRENT,i)<=vwap+buf) retestBuy=true;
      if(iHigh(_Symbol,PERIOD_CURRENT,i)>=vwap-buf) retestSell=true;
   }
   bool bullCandle=(c1>o1 && (lowerWick>=0.7*body || body>=InpMomentumMinBodyATR*atr));
   bool bearCandle=(c1<o1 && (upperWick>=0.7*body || body>=InpMomentumMinBodyATR*atr));
   if(c1>vwap && ema9[1]>vwap && ema9[1]>ema9[2] && retestBuy && bullCandle && c1>ema9[1]) return 1;
   if(c1<vwap && ema9[1]<vwap && ema9[1]<ema9[2] && retestSell && bearCandle && c1<ema9[1]) return -1;
   return 0;
}

//==================================================================
//  STRATEGY 6 – SUPERTREND + ADX/DMI SCALPER
//  Rebuilt as an in-file Supertrend calculation (no external iCustom).
//  Entry: confirmed Supertrend direction on closed bars, EMA21 alignment,
//  DI agreement, ADX strength and a fresh pullback/reclaim near EMA9.
//==================================================================
int SupertrendDirection(int shift, double &lineOut)
{
   lineOut = 0.0;
   int n = (int)Clampd(InpSupertrendLookback, 40, 250);
   MqlRates rates[]; double atr[];
   ArraySetAsSeries(rates, true); ArraySetAsSeries(atr, true);
   int gotR = CopyRates(_Symbol, PERIOD_CURRENT, shift, n, rates);
   int gotA = CopyBuffer(h_STATR, 0, shift, n, atr);
   if(gotR < 20 || gotA != gotR) return 0;
   int oldest = gotR - 1;
   double prevUpper = (rates[oldest].high + rates[oldest].low) * 0.5 + InpSupertrendMultiplier * atr[oldest];
   double prevLower = (rates[oldest].high + rates[oldest].low) * 0.5 - InpSupertrendMultiplier * atr[oldest];
   int trend = 1;
   double st = prevLower;
   for(int i = oldest - 1; i >= 0; i--)
   {
      double mid = (rates[i].high + rates[i].low) * 0.5;
      double basicUpper = mid + InpSupertrendMultiplier * atr[i];
      double basicLower = mid - InpSupertrendMultiplier * atr[i];
      double finalUpper = (basicUpper < prevUpper || rates[i+1].close > prevUpper) ? basicUpper : prevUpper;
      double finalLower = (basicLower > prevLower || rates[i+1].close < prevLower) ? basicLower : prevLower;
      if(trend < 0 && rates[i].close > finalUpper) trend = 1;
      else if(trend > 0 && rates[i].close < finalLower) trend = -1;
      st = (trend > 0) ? finalLower : finalUpper;
      prevUpper = finalUpper; prevLower = finalLower;
   }
   lineOut = st;
   return trend;
}

int Signal_SupertrendScalp()
{
   double stLine = 0.0, e9[], e21[], adx[], pdi[], mdi[], rsi[];
   int stNow = SupertrendDirection(1, stLine);
   if(stNow == 0) return 0;
   if(!GetBuf(h_EMA9,0,0,4,e9) || !GetBuf(h_EMA21,0,0,4,e21) ||
      !GetBuf(h_ADX,0,0,3,adx) || !GetBuf(h_ADX,1,0,3,pdi) ||
      !GetBuf(h_ADX,2,0,3,mdi) || !GetBuf(h_RSI,0,0,3,rsi)) return 0;
   double atr = GetATR(1);
   if(atr <= 0.0 || adx[1] < InpMomentumADXMin) return 0;
   double o1=iOpen(_Symbol,PERIOD_CURRENT,1), c1=iClose(_Symbol,PERIOD_CURRENT,1);
   double h1=iHigh(_Symbol,PERIOD_CURRENT,1), l1=iLow(_Symbol,PERIOD_CURRENT,1);
   if(h1-l1 > InpMaxSignalCandleATR * atr) return 0;
   bool upTrend = stNow > 0 && e21[1] > e21[2] && pdi[1] > mdi[1];
   bool dnTrend = stNow < 0 && e21[1] < e21[2] && mdi[1] > pdi[1];
   bool pullBuy = l1 <= e9[1] + 0.18*atr && c1 > e9[1] && c1 > o1 && rsi[1] >= 48 && rsi[1] <= 70;
   bool pullSell= h1 >= e9[1] - 0.18*atr && c1 < e9[1] && c1 < o1 && rsi[1] <= 52 && rsi[1] >= 30;
   if(upTrend && pullBuy && c1 > stLine) return 1;
   if(dnTrend && pullSell && c1 < stLine) return -1;
   return 0;
}

//==================================================================
//  STRATEGY 7 – ATR MOMENTUM CONTINUATION SCALPER
//  ATR volatility gate + EMA9/EMA21 direction + ADX/DI + RSI momentum
//  + short micro-range break. Bar-close only: not a tick-fire entry loop.
//==================================================================
int Signal_ATRMomentum()
{
   double e9[],e21[],adx[],pdi[],mdi[],rsi[];
   if(!GetBuf(h_EMA9,0,0,3,e9)) return 0;
   if(!GetBuf(h_EMA21,0,0,3,e21)) return 0;
   if(!GetBuf(h_ADX,0,0,3,adx)) return 0;
   if(!GetBuf(h_ADX,1,0,3,pdi)) return 0;
   if(!GetBuf(h_ADX,2,0,3,mdi)) return 0;
   if(!GetBuf(h_RSI,0,0,3,rsi)) return 0;
   double atr=GetATR(1);
   if(atr<=0.0 || adx[1]<InpMomentumADXMin) return 0;

   double c1=iClose(_Symbol,PERIOD_CURRENT,1), c2=iClose(_Symbol,PERIOD_CURRENT,2);
   double o1=iOpen(_Symbol,PERIOD_CURRENT,1), h1=iHigh(_Symbol,PERIOD_CURRENT,1), l1=iLow(_Symbol,PERIOD_CURRENT,1);
   double body=MathAbs(c1-o1);
   double range=h1-l1;
   if(range<=0.0 || range>InpMaxSignalCandleATR*atr || body<InpMomentumMinBodyATR*atr) return 0;

   int lb=(int)Clampd(InpMomentumBreakoutBars,2,8);
   double priorHigh=-DBL_MAX, priorLow=DBL_MAX;
   for(int i=2;i<=lb+1;i++)
   {
      priorHigh=MathMax(priorHigh,iHigh(_Symbol,PERIOD_CURRENT,i));
      priorLow=MathMin(priorLow,iLow(_Symbol,PERIOD_CURRENT,i));
   }
   bool volatilityOK=range>=MathMax(0.05,InpMomentumMinMoveATR)*atr;
   bool buy=e9[1]>e21[1] && c1>e9[1] && c1>priorHigh && c1>c2 &&
            pdi[1]>mdi[1] && rsi[1]>=52.0 && rsi[1]<=78.0;
   bool sell=e9[1]<e21[1] && c1<e9[1] && c1<priorLow && c1<c2 &&
             mdi[1]>pdi[1] && rsi[1]<=48.0 && rsi[1]>=22.0;
   if(volatilityOK && buy) return 1;
   if(volatilityOK && sell) return -1;
   return 0;
}

//==================================================================
//  v4.8 HELPERS  (open-position limits, cost model, time-stop)
//==================================================================
int MaxOpenAllowed()
{
   if(InpOneTradeOnly) return 1;
   return (InpMaxOpenPositions > 0 ? InpMaxOpenPositions : 2147483647);
}

bool HasOppositePosition(ENUM_ORDER_TYPE type)
{
   long want = (type == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE) != want) return true;
   }
   return false;
}

bool HasSameDirectionPosition(ENUM_ORDER_TYPE type)
{
   long want=(type==ORDER_TYPE_BUY?POSITION_TYPE_BUY:POSITION_TYPE_SELL);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE)==want) return true;
   }
   return false;
}

// Shared money-at-risk snapshot across all Nixo modes, symbols, positions and submitted pending entries.
double OpenRiskMoney()
{
   double total=0.0;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      long magic=PositionGetInteger(POSITION_MAGIC);
      if(magic!=InpMagic && magic!=InpSignalMagic) continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      double sl=PositionGetDouble(POSITION_SL);
      double vol=PositionGetDouble(POSITION_VOLUME);
      if(sl<=0.0) return equity; // unmanaged Nixo exposure blocks additional entries
      long pt=PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE ot=(pt==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double point=SymbolInfoDouble(sym,SYMBOL_POINT);
      double adverse=(pt==POSITION_TYPE_BUY)?sl-MathMax(0,InpRiskSlippagePoints)*point:sl+MathMax(0,InpRiskSlippagePoints)*point;
      double pl=0.0;
      if(!OrderCalcProfit(ot,sym,vol,open,adverse,pl)) return equity;
      total+=MathMax(0.0,-pl)+EstimateRoundTurnCommissionPerLot()*vol;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong tk=OrderGetTicket(i); if(tk==0) continue;
      long magic=OrderGetInteger(ORDER_MAGIC);
      if(magic!=InpMagic && magic!=InpSignalMagic) continue;
      ENUM_ORDER_TYPE raw=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      ENUM_ORDER_TYPE ot;
      if(raw==ORDER_TYPE_BUY || raw==ORDER_TYPE_BUY_LIMIT || raw==ORDER_TYPE_BUY_STOP || raw==ORDER_TYPE_BUY_STOP_LIMIT) ot=ORDER_TYPE_BUY;
      else if(raw==ORDER_TYPE_SELL || raw==ORDER_TYPE_SELL_LIMIT || raw==ORDER_TYPE_SELL_STOP || raw==ORDER_TYPE_SELL_STOP_LIMIT) ot=ORDER_TYPE_SELL;
      else continue;
      string sym=OrderGetString(ORDER_SYMBOL);
      double sl=OrderGetDouble(ORDER_SL), price=OrderGetDouble(ORDER_PRICE_OPEN), vol=OrderGetDouble(ORDER_VOLUME_CURRENT);
      if(vol<=0.0) vol=OrderGetDouble(ORDER_VOLUME_INITIAL);
      if(sl<=0.0) return equity;
      double pl=0.0;
      if(!OrderCalcProfit(ot,sym,vol,price,sl,pl)) return equity;
      total+=MathMax(0.0,-pl)+EstimateRoundTurnCommissionPerLot()*vol;
   }
   return total;
}

double MoneyPerPointPerLot()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pl = 0.0;
   if(bid > 0.0 && OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, bid, bid + _Point, pl) && pl > 0.0)
      return pl;
   return 0.0;
}

// round-trip trading cost expressed as a PRICE distance: spread + commission
double CostDistance()
{
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(spread < 0.0) spread = 0.0;
   double comm = 0.0;
   double crt = EstimateRoundTurnCommissionPerLot();
   double mpp = MoneyPerPointPerLot();
   if(crt > 0.0 && mpp > 0.0) comm = (crt / mpp) * _Point;
   return spread + comm;
}

double ComputeSLDistWithMultiplier(double atrMultiplier)
{
   double atr = GetATR(1);
   bool scalp = (g_Strategy >= STRAT_SAFE_BREAK);
   double minSL = (scalp ? InpScalpMinSL_Points : InpMinSL_Points) * _Point;
   double slDist = (atr > 0.0) ? atr * MathMax(0.1,atrMultiplier) : minSL;
   if(slDist < minSL) slDist = minSL;
   double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(slDist < stopsLevel + 5 * _Point) slDist = stopsLevel + 10 * _Point;
   return slDist;
}

double ComputeSLDist()
{
   return ComputeSLDistWithMultiplier(g_ATRMult);
}

// closes a stale trade that never moved in our favour (position already selected)
bool TimeStopTriggered(ulong tk, long ptype, double open, double sl, int timeStopBars, double minR, bool stagedMode)
{
   if(timeStopBars <= 0) return false;
   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
   long held = (long)(TimeCurrent() - opened);
   if(held < (long)timeStopBars * (long)PeriodSeconds(PERIOD_CURRENT)) return false;

   double initR = (sl > 0.0) ? MathAbs(open - sl) : 0.0;
   if(stagedMode)
   {
      ulong pid = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      string kR = PositionStateKey(pid, "R");
      if(GlobalVariableCheck(kR)) initR = GlobalVariableGet(kR);
      string k1 = PositionStateKey(pid, "1");
      if(GlobalVariableCheck(k1) && GlobalVariableGet(k1) > 0.5) return false;   // TP1 reached → let it run
   }
   if(initR <= 0.0) return false;

   double fav = (ptype == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) - open
                                             : open - SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(fav >= minR * initR) return false;

   bool sent = trade.PositionClose(tk, InpSlippage);
   if(TradeRequestSucceeded(sent))
   {
      PrintFormat("TIME STOP | ticket=%I64u | held %I64d s without reaching %.2fR", tk, held, minR);
      return true;
   }
   return false;
}

//==================================================================
//  STRATEGY 8 – RTM SCALP  (fast Quasimodo zone, M1–M5)
//  Same structure as RTM+LFT but with 1-bar fractals, a recent break
//  (≤ N bars) and a wider zone tolerance → many more setups per hour.
//==================================================================
int Signal_RTM_Scalp()
{
   SwingPt H[], L[];
   if(!FindSwings(1, 45, 4, H, L)) return 0;
   if(ArraySize(H) < 2 || ArraySize(L) < 2) return 0;

   double atr = GetATR(1);
   if(atr <= 0.0) return 0;

   double o1 = iOpen (_Symbol, PERIOD_CURRENT, 1);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow  (_Symbol, PERIOD_CURRENT, 1);
   if((h1 - l1) > InpMaxSignalCandleATR * atr) return 0;
   double tol = MathMax(0.05, InpRTMScalpTolATR) * atr;
   int maxAge = (int)Clampd(InpRTMScalpMaxAge, 4, 40);

   // bearish QM: H[1] > L[1] > H[0] > L[0]  (bigger shift = older)
   if(H[1].shift > L[1].shift && L[1].shift > H[0].shift && H[0].shift > L[0].shift &&
      H[0].price > H[1].price && L[0].price < L[1].price && L[0].shift <= maxAge)
   {
      double zone = H[1].price;
      if(MathAbs(zone - g_LastQMZone) > 0.1 * atr &&
         h1 >= zone - tol && h1 <= H[0].price + 0.1 * atr && c1 < zone && c1 < o1)
      {
         g_LastQMZone = zone;
         return -1;
      }
   }

   // bullish QM: L[1] > H[1] > L[0] > H[0]
   if(L[1].shift > H[1].shift && H[1].shift > L[0].shift && L[0].shift > H[0].shift &&
      L[0].price < L[1].price && H[0].price > H[1].price && H[0].shift <= maxAge)
   {
      double zone = L[1].price;
      if(MathAbs(zone - g_LastQMZone) > 0.1 * atr &&
         l1 <= zone + tol && l1 >= L[0].price - 0.1 * atr && c1 > zone && c1 > o1)
      {
         g_LastQMZone = zone;
         return 1;
      }
   }
   return 0;
}

//==================================================================
//  STRATEGY 9 – LIQUIDITY SCALP  (micro stop-run reversal)
//  Sweep of the last N bars' extreme, rejection wick, close back
//  inside the range, soft EMA bias.  Fires often on M1/M5.
//==================================================================
int Signal_LiqScalp()
{
   double e21[], e50[];
   if(!GetBuf(h_EMA21, 0, 0, 4, e21)) return 0;
   if(!GetBuf(h_EMAF,  0, 0, 3, e50)) return 0;
   double atr = GetATR(1);
   if(atr <= 0.0) return 0;

   double o1 = iOpen (_Symbol, PERIOD_CURRENT, 1);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow  (_Symbol, PERIOD_CURRENT, 1);
   double rng = h1 - l1;
   if(rng <= 0.0 || rng > InpMaxSignalCandleATR * 1.2 * atr) return 0;

   int n = (int)Clampd(InpLiqBars, 4, 30);
   double hiN = -DBL_MAX, loN = DBL_MAX;
   for(int i = 2; i <= n + 1; i++)
   {
      hiN = MathMax(hiN, iHigh(_Symbol, PERIOD_CURRENT, i));
      loN = MathMin(loN, iLow (_Symbol, PERIOD_CURRENT, i));
   }

   double lowWick = MathMin(o1, c1) - l1;
   double upWick  = h1 - MathMax(o1, c1);
   double wickMin = MathMax(0.10, InpLiqWickATR) * atr;

   bool sweepLow  = (l1 < loN - 0.02 * atr && c1 > loN && lowWick >= wickMin && (c1 - l1) / rng >= 0.55);
   bool sweepHigh = (h1 > hiN + 0.02 * atr && c1 < hiN && upWick  >= wickMin && (h1 - c1) / rng >= 0.55);

   bool bullBias = (c1 > e50[1] || e21[1] > e21[2]);
   bool bearBias = (c1 < e50[1] || e21[1] < e21[2]);

   if(sweepLow  && bullBias) return 1;
   if(sweepHigh && bearBias) return -1;
   return 0;
}

//==================================================================
//  STRATEGY 10 – MICRO PULLBACK SUPER-SCALP (EMA9 / EMA21 / EMA50)
//==================================================================
int Signal_MicroPullback()
{
   double e9[], e21[], e50[], adx[], rsi[];
   if(!GetBuf(h_EMA9,  0, 0, 5, e9))  return 0;
   if(!GetBuf(h_EMA21, 0, 0, 5, e21)) return 0;
   if(!GetBuf(h_EMAF,  0, 0, 5, e50)) return 0;
   if(!GetBuf(h_ADX,   0, 0, 3, adx)) return 0;
   if(!GetBuf(h_RSI,   0, 0, 3, rsi)) return 0;

   double atr = GetATR(1);
   if(atr <= 0.0 || adx[1] < InpMicroADXMin) return 0;

   double o1 = iOpen (_Symbol, PERIOD_CURRENT, 1);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow  (_Symbol, PERIOD_CURRENT, 1);
   double h2 = iHigh (_Symbol, PERIOD_CURRENT, 2);
   double l2 = iLow  (_Symbol, PERIOD_CURRENT, 2);
   double body = MathAbs(c1 - o1);
   if(body < 0.12 * atr || (h1 - l1) > InpMaxSignalCandleATR * atr) return 0;

   bool up = (e9[1] > e21[1] && e21[1] > e50[1] && e21[1] > e21[3]);
   bool dn = (e9[1] < e21[1] && e21[1] < e50[1] && e21[1] < e21[3]);
   bool touchUp = (l1 <= e9[1] + 0.10 * atr) || (l2 <= e9[2] + 0.10 * atr);
   bool touchDn = (h1 >= e9[1] - 0.10 * atr) || (h2 >= e9[2] - 0.10 * atr);

   if(up && touchUp && c1 > e9[1] && c1 > o1 && c1 > h2 && rsi[1] >= 45.0 && rsi[1] <= 68.0) return 1;
   if(dn && touchDn && c1 < e9[1] && c1 < o1 && c1 < l2 && rsi[1] <= 55.0 && rsi[1] >= 32.0) return -1;
   return 0;
}

//==================================================================
//  STRATEGY 11 – SQUEEZE BREAKOUT SUPER-SCALP
//  3 compressed bars (box < X·ATR) followed by a strong breakout
//  candle in the EMA direction.
//==================================================================
int Signal_Squeeze()
{
   double e21[], e50[];
   if(!GetBuf(h_EMA21, 0, 0, 4, e21)) return 0;
   if(!GetBuf(h_EMAF,  0, 0, 3, e50)) return 0;
   double atr = GetATR(1);
   if(atr <= 0.0) return 0;

   double o1 = iOpen (_Symbol, PERIOD_CURRENT, 1);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow  (_Symbol, PERIOD_CURRENT, 1);
   double rng = h1 - l1;
   double body = MathAbs(c1 - o1);
   if(rng <= 0.0 || rng > InpMaxSignalCandleATR * atr || body < 0.30 * atr) return 0;

   double hh = -DBL_MAX, ll = DBL_MAX;
   for(int i = 2; i <= 4; i++)
   {
      hh = MathMax(hh, iHigh(_Symbol, PERIOD_CURRENT, i));
      ll = MathMin(ll, iLow (_Symbol, PERIOD_CURRENT, i));
   }
   if((hh - ll) > MathMax(0.3, InpSqueezeBoxATR) * atr) return 0;

   double buf = 0.03 * atr;
   if(c1 > hh + buf && c1 > o1 && (c1 - l1) / rng >= 0.70 && e21[1] >= e21[2] && c1 > e50[1]) return 1;
   if(c1 < ll - buf && c1 < o1 && (h1 - c1) / rng >= 0.70 && e21[1] <= e21[2] && c1 < e50[1]) return -1;
   return 0;
}

//==================================================================
//  STRATEGY 12 – RSI-3 DIP SUPER-SCALP (buy dips in uptrend)
//==================================================================
int Signal_DipRSI3()
{
   double r3[], e21[], e50[], adx[];
   if(!GetBuf(h_RSI3,  0, 0, 4, r3))  return 0;
   if(!GetBuf(h_EMA21, 0, 0, 3, e21)) return 0;
   if(!GetBuf(h_EMAF,  0, 0, 3, e50)) return 0;
   if(!GetBuf(h_ADX,   0, 0, 3, adx)) return 0;

   double atr = GetATR(1);
   if(atr <= 0.0 || adx[1] < 14.0) return 0;

   double o1 = iOpen (_Symbol, PERIOD_CURRENT, 1);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow  (_Symbol, PERIOD_CURRENT, 1);
   if((h1 - l1) > InpMaxSignalCandleATR * atr) return 0;

   bool up = (e21[1] > e50[1] && c1 > e50[1]);
   bool dn = (e21[1] < e50[1] && c1 < e50[1]);
   double lo = Clampd(InpDipRSI, 5.0, 40.0);

   if(up && r3[2] <= lo        && r3[1] > r3[2] && c1 > o1) return 1;
   if(dn && r3[2] >= 100.0 - lo && r3[1] < r3[2] && c1 < o1) return -1;
   return 0;
}

//==================================================================
//  STRATEGY 13 – VOLUME-BURST MOMENTUM SUPER-SCALP
//  Tick-volume spike + full-body candle closing near its extreme,
//  not already stretched away from EMA21.
//==================================================================
//==================================================================
//  STRATEGY 13 – EMA TREND PULLBACK SCALPER
//  Inspired by public MT5 EMA-pullback designs: fast/slow EMA trend,
//  slope filter, retracement to EMA21, ADX/DI + RSI confirmation.
//  Original Nixo implementation; no external indicators required.
//==================================================================
int Signal_EMAPullback()
{
   double e9[], e21[], e50[], adx[], pdi[], mdi[], rsi[];
   int sb = (int)Clampd(InpPullbackSlopeBars, 2, 10);
   if(!GetBuf(h_EMA9,0,0,6,e9) || !GetBuf(h_EMA21,0,0,6,e21) ||
      !GetBuf(h_EMAF,0,0,sb+2,e50) || !GetBuf(h_ADX,0,0,3,adx) ||
      !GetBuf(h_ADX,1,0,3,pdi) || !GetBuf(h_ADX,2,0,3,mdi) ||
      !GetBuf(h_RSI,0,0,3,rsi)) return 0;
   double atr = GetATR(1);
   if(atr <= 0.0 || adx[1] < InpPullbackADXMin) return 0;
   double c1=iClose(_Symbol,PERIOD_CURRENT,1), o1=iOpen(_Symbol,PERIOD_CURRENT,1);
   double h1=iHigh(_Symbol,PERIOD_CURRENT,1), l1=iLow(_Symbol,PERIOD_CURRENT,1);
   bool up = e9[1] > e21[1] && e21[1] > e50[1] && e50[1] > e50[1+sb] && pdi[1] > mdi[1];
   bool dn = e9[1] < e21[1] && e21[1] < e50[1] && e50[1] < e50[1+sb] && mdi[1] > pdi[1];
   bool touchedBuy=false, touchedSell=false;
   for(int i=1;i<=3;i++)
   {
      if(iLow(_Symbol,PERIOD_CURRENT,i) <= e21[i] + InpPullbackTouchATR*atr) touchedBuy=true;
      if(iHigh(_Symbol,PERIOD_CURRENT,i) >= e21[i] - InpPullbackTouchATR*atr) touchedSell=true;
   }
   bool candleOK = (h1-l1) <= InpMaxSignalCandleATR*atr && MathAbs(c1-o1) >= 0.10*atr;
   if(up && touchedBuy && candleOK && c1>o1 && c1>e9[1] && rsi[1]>=50 && rsi[1]<=70) return 1;
   if(dn && touchedSell && candleOK && c1<o1 && c1<e9[1] && rsi[1]<=50 && rsi[1]>=30) return -1;
   return 0;
}

//==================================================================
//  STRATEGY 14 – ENSEMBLE  (every model votes, conflicts are skipped)
//==================================================================
int Signal_Ensemble()
{
   int buys = 0, sells = 0;
   for(int s = 0; s < STRAT_ENSEMBLE; s++)
   {
      int sg = RunStrategy(s);
      if(sg > 0) buys++;
      else if(sg < 0) sells++;
   }
   int need = (int)Clampd(InpEnsembleMinVotes, 1, 6);
   if(buys >= need && sells == 0) return 1;
   if(sells >= need && buys == 0) return -1;
   return 0;
}

int Signal_TickTurbo()
{
   if(g_TickPriceCount < 6) return 0;
   datetime now = TimeCurrent();
   if(InpTickTurboCooldownSec > 0 && g_LastTurboEntry > 0 &&
      now - g_LastTurboEntry < InpTickTurboCooldownSec) return 0;
   double atr=GetATR(1), e9[], e21[];
   if(atr<=0.0 || !GetBuf(h_EMA9,0,0,2,e9) || !GetBuf(h_EMA21,0,0,2,e21)) return 0;
   int oldIdx=(g_TickPriceHead + 8 - 6) % 8;
   double oldPrice=g_TickPrices[oldIdx];
   double nowPrice=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(oldPrice<=0.0 || nowPrice<=0.0) return 0;
   double move=nowPrice-oldPrice;
   double threshold=MathMax(InpTickTurboMoveATR*atr, 2.0*CostDistance());
   if(move>=threshold && nowPrice>e9[0] && e9[0]>e21[0]) { g_LastTurboEntry=now; return 1; }
   if(move<=-threshold && nowPrice<e9[0] && e9[0]<e21[0]) { g_LastTurboEntry=now; return -1; }
   return 0;
}

int TickPressureScore()
{
   if(g_TickPriceCount < 4) return 0;
   int up=0, dn=0;
   int start=(g_TickPriceHead - g_TickPriceCount + 8) % 8;
   for(int j=1; j<g_TickPriceCount; j++)
   {
      double prev=g_TickPrices[(start+j-1)%8];
      double curr=g_TickPrices[(start+j)%8];
      if(curr>prev) up++;
      else if(curr<prev) dn++;
   }
   if(up>=dn+2) return 1;
   if(dn>=up+2) return -1;
   return 0;
}

// Original Nixo implementation inspired by the public UltraHFT concept:
// five independent signal layers scored on every tick; no internal cooldown by default.
int Signal_UltraHFT()
{
   double e3[], e8[], e21[], rsi[], adx[], pdi[], mdi[], macd[], macdSig[], upper[], lower[], stoch[];
   int buyScore=0, sellScore=0;
   if(!GetBuf(h_EMA3,0,0,2,e3) || !GetBuf(h_EMA8,0,0,2,e8) || !GetBuf(h_EMA21,0,0,2,e21)) return 0;
   double atr=GetATR(1);
   if(atr<=0.0) return 0;

   // Layer 1: fast EMA stack (EMA 3/8/21).
   if(e3[0]>e8[0] && e8[0]>e21[0]) buyScore+=2;
   if(e3[0]<e8[0] && e8[0]<e21[0]) sellScore+=2;

   // Layer 2: RSI + MACD + ADX/DI momentum.
   if(GetBuf(h_RSI,0,0,2,rsi) && GetBuf(h_ADX,0,0,2,adx) &&
      GetBuf(h_ADX,1,0,2,pdi) && GetBuf(h_ADX,2,0,2,mdi) &&
      GetBuf(h_MACD,0,0,2,macd) && GetBuf(h_MACD,1,0,2,macdSig))
   {
      if(adx[0]>=12.0 && rsi[0]>=51.0 && macd[0]>macdSig[0] && pdi[0]>mdi[0]) buyScore+=2;
      if(adx[0]>=12.0 && rsi[0]<=49.0 && macd[0]<macdSig[0] && mdi[0]>pdi[0]) sellScore+=2;
   }

   // Layer 3: Bollinger + Stochastic mean-reversion contribution.
   if(GetBuf(h_BANDS,1,0,2,upper) && GetBuf(h_BANDS,2,0,2,lower) && GetBuf(h_STOCH,0,0,2,stoch))
   {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double tol=InpUltraBandTouchATR*atr;
      if(bid<=lower[0]+tol && stoch[0]<=25.0) buyScore+=2;
      if(ask>=upper[0]-tol && stoch[0]>=75.0) sellScore+=2;
   }

   // Layer 4: live tick pressure proxy (tick direction, not exchange order-book data).
   int pressure=TickPressureScore();
   if(pressure>0) buyScore++;
   if(pressure<0) sellScore++;

   // Layer 5: current price breaks the last completed candle's extreme.
   double priorHigh=iHigh(_Symbol,PERIOD_CURRENT,1);
   double priorLow=iLow(_Symbol,PERIOD_CURRENT,1);
   double liveBid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double buffer=0.02*atr;
   if(liveBid>priorHigh+buffer) buyScore+=2;
   if(liveBid<priorLow-buffer) sellScore+=2;

   int required=(int)Clampd(InpUltraMinScore,2,9);
   if(buyScore>=required && buyScore>sellScore)
   {
      if(InpDebug) PrintFormat("ULTRA HFT BUY | score=%d:%d",buyScore,sellScore);
      return 1;
   }
   if(sellScore>=required && sellScore>buyScore)
   {
      if(InpDebug) PrintFormat("ULTRA HFT SELL | score=%d:%d",sellScore,buyScore);
      return -1;
   }
   return 0;
}

int CountNyaoPositions()
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT),"Nixo500|NYAO|")==0) count++;
   }
   return count;
}

long ExistingNyaoPendingBatchId()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol || OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      string c=OrderGetString(ORDER_COMMENT);
      if(StringFind(c,"Nixo500|NYAO|")!=0) continue;
      long batch=BatchIdFromComment(c);
      if(batch>0) return batch;
   }
   return 0;
}

int CountNyaoPending(bool &hasBuy, bool &hasSell)
{
   int count=0; hasBuy=false; hasSell=false;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol || OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      if(StringFind(OrderGetString(ORDER_COMMENT),"Nixo500|NYAO|")!=0) continue;
      ENUM_ORDER_TYPE t=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(t==ORDER_TYPE_BUY_STOP || t==ORDER_TYPE_BUY_STOP_LIMIT) hasBuy=true;
      if(t==ORDER_TYPE_SELL_STOP || t==ORDER_TYPE_SELL_STOP_LIMIT) hasSell=true;
      count++;
   }
   return count;
}

void CancelNyaoPendingOrders()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol || OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      if(StringFind(OrderGetString(ORDER_COMMENT),"Nixo500|NYAO|")!=0) continue;
      bool sent=trade.OrderDelete(ticket);
      if(!TradeRequestSucceeded(sent))
         PrintFormat("NYAO OCO DELETE FAILED | order=%I64u | retcode=%u %s",ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
   }
}


ENUM_ORDER_TYPE_TIME NyaoPendingTimeType(datetime &expiration)
{
   int modes=(int)SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE);
   int minutes=(int)Clampd(InpNyaoPendingExpiryMinutes,1,1440);
   if((modes & SYMBOL_EXPIRATION_SPECIFIED)==SYMBOL_EXPIRATION_SPECIFIED)
   {
      expiration=TimeCurrent()+minutes*60;
      return ORDER_TIME_SPECIFIED;
   }
   if((modes & SYMBOL_EXPIRATION_DAY)==SYMBOL_EXPIRATION_DAY)
   {
      expiration=0;
      return ORDER_TIME_DAY;
   }
   expiration=0;
   return ORDER_TIME_GTC;
}

void ExpireStaleNyaoPendingOrders()
{
   int maxAge=(int)Clampd(InpNyaoPendingExpiryMinutes,1,1440)*60;
   datetime now=TimeCurrent();
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i); if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol || OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      if(StringFind(OrderGetString(ORDER_COMMENT),"Nixo500|NYAO|")!=0) continue;
      datetime setup=(datetime)OrderGetInteger(ORDER_TIME_SETUP);
      if(setup<=0 || now-setup<maxAge) continue;
      bool sent=trade.OrderDelete(ticket);
      if(TradeRequestSucceeded(sent))
         PrintFormat("NYAO STALE PENDING EXPIRED | order=%I64u | age=%d sec",ticket,(int)(now-setup));
      else
         PrintFormat("NYAO STALE PENDING DELETE FAILED | order=%I64u | retcode=%u %s",ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
   }
}

bool NyaoVolatilityOK(double atr)
{
   if(InpNyaoMinVolatilityRatio<=0.0) return true;
   int bars=(int)Clampd(InpNyaoATRBaseBars,10,1000);
   double a[];
   if(!GetBuf(h_ATR,0,1,bars,a)) return false;
   double avg=0.0;
   for(int i=0;i<bars;i++) avg+=a[i];
   avg/=bars;
   return (avg>0.0 && atr/avg>=InpNyaoMinVolatilityRatio);
}

// Nyao-inspired OCO straddle. One BuyStop + one SellStop; first fill cancels the other.
// The logic is written independently for Nixo; no repository source is copied.
void MaintainNyaoStraddle()
{
   if(!g_Running || g_Stopped || g_DailyStopped) { CancelNyaoPendingOrders(); return; }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return;
   if(DailyTradeLimitReached() || EntryRateLimitReached() || IsSpreadTooHigh()) return;
   if(InpUseSession && !IsInSession()) return;
   if(CountNyaoPositions()>0) { CancelNyaoPendingOrders(); return; }

   int hedgeOffDirection=0;
   if(!g_HedgeEnabled)
   {
      // A two-sided OCO straddle can race-fill both legs. In Hedge OFF mode,
      // require a one-sided UltraHFT bias and disarm all pending legs if any Nixo position exists.
      if(CountMyPositions()>0) { CancelNyaoPendingOrders(); return; }
      hedgeOffDirection=Signal_UltraHFT();
      if(hedgeOffDirection==0) { CancelNyaoPendingOrders(); return; }
   }

   bool hasBuy=false, hasSell=false;
   CountNyaoPending(hasBuy,hasSell);
   if(!g_HedgeEnabled && ((hedgeOffDirection>0 && hasSell) || (hedgeOffDirection<0 && hasBuy)))
   {
      CancelNyaoPendingOrders();
      hasBuy=false; hasSell=false;
   }
   if(hasBuy && hasSell) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.ask<=0.0 || tick.bid<=0.0) return;
   double atr=GetATR(1);
   if(atr<=0.0 || !NyaoVolatilityOK(atr)) return;

   double spread=tick.ask-tick.bid;
   double stops=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   double freeze=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*_Point;
   double distance=MathMax(atr*MathMax(0.01,InpNyaoEntryDistanceATR),stops+freeze+spread+3.0*_Point);
   double slDist=ComputeSLDist();
   double riskLeg=GetCurrentRiskPct()*(g_HedgeEnabled?0.5:1.0); // halve only when both OCO legs are active
   long nyaoBatchId = ExistingNyaoPendingBatchId();
   if(nyaoBatchId <= 0) nyaoBatchId = NextBatchId();
   double buyPrice=NormalizeDouble(tick.ask+distance,_Digits);
   double sellPrice=NormalizeDouble(tick.bid-distance,_Digits);

   datetime pendingExpiry=0;
   ENUM_ORDER_TYPE_TIME pendingTimeType=NyaoPendingTimeType(pendingExpiry);
   if(!hasBuy && (g_HedgeEnabled || hedgeOffDirection>0))
   {
      double lotBuy=CalcLot(ORDER_TYPE_BUY,riskLeg,slDist,buyPrice,InpPositionSizeMode==NIXO_SIZE_FIXED_MONEY?InpFixedRiskMoney*(g_HedgeEnabled?0.5:1.0):-1.0);
      if(lotBuy>0.0)
      {
         if(UseStagedTP() && !MultiTPPlanValid(lotBuy))
         { PrintFormat("NYAO BUY skipped: %.4f lots cannot leave a valid runner after three half closes.",lotBuy); return; }
         double sl=NormalizeDouble(buyPrice-slDist,_Digits);
         double tp=UseStagedTP()?0.0:NormalizeDouble(buyPrice+slDist*3.0,_Digits);
         if(InpMaxOpenRiskPct>0.0)
         {
            double reserved=OpenRiskMoney(), proposed=ActualRiskMoney(ORDER_TYPE_BUY,lotBuy,buyPrice,sl);
            double cap=SelectedRiskBase()*InpMaxOpenRiskPct/100.0;
            if(reserved+proposed>cap+1e-8)
            { PrintFormat("NYAO BUY blocked by unified risk cap | open=%.2f new=%.2f cap=%.2f",reserved,proposed,cap); return; }
         }
         string c=StringFormat("Nixo500|NYAO|B%I64d",nyaoBatchId);
         bool sent=trade.BuyStop(lotBuy,buyPrice,_Symbol,sl,tp,pendingTimeType,pendingExpiry,c);
         if(!PendingOrderRequestSucceeded(sent))
            PrintFormat("NYAO BUYSTOP FAILED | price=%.5f lot=%.3f | retcode=%u %s",buyPrice,lotBuy,trade.ResultRetcode(),trade.ResultRetcodeDescription());
         else
         {
            ReportSnapshotPendingOrder(trade.ResultOrder(),NIXO_MODE_STRATEGY,g_Strategy,g_TPAnchorR);
            if(InpDebug) PrintFormat("NYAO BUYSTOP PLACED | %.5f | %.3f lot",buyPrice,lotBuy);
         }
      }
   }

   if(!hasSell && (g_HedgeEnabled || hedgeOffDirection<0))
   {
      double lotSell=CalcLot(ORDER_TYPE_SELL,riskLeg,slDist,sellPrice,InpPositionSizeMode==NIXO_SIZE_FIXED_MONEY?InpFixedRiskMoney*(g_HedgeEnabled?0.5:1.0):-1.0);
      if(lotSell>0.0)
      {
         if(UseStagedTP() && !MultiTPPlanValid(lotSell))
         { PrintFormat("NYAO SELL skipped: %.4f lots cannot leave a valid runner after three half closes.",lotSell); return; }
         double sl=NormalizeDouble(sellPrice+slDist,_Digits);
         double tp=UseStagedTP()?0.0:NormalizeDouble(sellPrice-slDist*3.0,_Digits);
         if(InpMaxOpenRiskPct>0.0)
         {
            double reserved=OpenRiskMoney(), proposed=ActualRiskMoney(ORDER_TYPE_SELL,lotSell,sellPrice,sl);
            double cap=SelectedRiskBase()*InpMaxOpenRiskPct/100.0;
            if(reserved+proposed>cap+1e-8)
            { PrintFormat("NYAO SELL blocked by unified risk cap | open=%.2f new=%.2f cap=%.2f",reserved,proposed,cap); return; }
         }
         string c=StringFormat("Nixo500|NYAO|B%I64d",nyaoBatchId);
         bool sent=trade.SellStop(lotSell,sellPrice,_Symbol,sl,tp,pendingTimeType,pendingExpiry,c);
         if(!PendingOrderRequestSucceeded(sent))
            PrintFormat("NYAO SELLSTOP FAILED | price=%.5f lot=%.3f | retcode=%u %s",sellPrice,lotSell,trade.ResultRetcode(),trade.ResultRetcodeDescription());
         else
         {
            ReportSnapshotPendingOrder(trade.ResultOrder(),NIXO_MODE_STRATEGY,g_Strategy,g_TPAnchorR);
            if(InpDebug) PrintFormat("NYAO SELLSTOP PLACED | %.5f | %.3f lot",sellPrice,lotSell);
         }
      }
   }
}

int RunStrategy(int s)
{
   switch(s)
   {
      case STRAT_RTM_LFT:      return Signal_RTM_LFT();
      case STRAT_DREAMS:       return Signal_Dreams();
      case STRAT_SAFE_BREAK:   return Signal_SafeBreakout();
      case STRAT_EMA_ADX_MTF:  return Signal_EMA_ADX_MTF();
      case STRAT_VWAP_RETEST:  return Signal_VWAPRetest();
      case STRAT_SUPERTREND: return Signal_SupertrendScalp();
      case STRAT_ATR_MOMENTUM: return Signal_ATRMomentum();
      case STRAT_RTM_SCALP:    return Signal_RTM_Scalp();
      case STRAT_LIQ_SCALP:    return Signal_LiqScalp();
      case STRAT_MICRO_PB:     return Signal_MicroPullback();
      case STRAT_SQUEEZE:      return Signal_Squeeze();
      case STRAT_DIP_RSI3:     return Signal_DipRSI3();
      case STRAT_EMA_PULLBACK:    return Signal_EMAPullback();
      case STRAT_ENSEMBLE:     return Signal_Ensemble();
      case STRAT_TICK_TURBO:   return Signal_TickTurbo();
      case STRAT_ULTRA_HFT:    return Signal_UltraHFT();
      case STRAT_NYAO_STRADDLE:return 0; // managed by server-side OCO pending-order engine
      case STRAT_ULTRA_NYAO_HYBRID:return Signal_UltraHFT();
   }
   return 0;
}

//==================================================================
// AI ADVISORY BRIDGE + LOCAL/GREGORIAN/PERSIAN DATE DISPLAY
// AI output is read-only/advisory; it cannot place or alter orders.
//==================================================================
void GregorianToJalali(int gy,int gm,int gd,int &jy,int &jm,int &jd)
{
   int gdm[12]={0,31,59,90,120,151,181,212,243,273,304,334};
   int gy2=(gm>2)?gy+1:gy;
   long days=355666L+365L*gy+(gy2+3)/4-(gy2+99)/100+(gy2+399)/400+gdm[gm-1]+gd;
   jy=-1595+(int)(33*(days/12053)); days%=12053;
   jy+=4*(int)(days/1461); days%=1461;
   if(days>365) { jy+=(int)((days-1)/365); days=(days-1)%365; }
   if(days<186) { jm=1+(int)(days/31); jd=1+(int)(days%31); }
   else { jm=7+(int)((days-186)/30); jd=1+(int)((days-186)%30); }
}

string CurrentDatePair()
{
   MqlDateTime dt; TimeToStruct(TimeLocal(),dt);
   int jy=0,jm=0,jd=0; GregorianToJalali(dt.year,dt.mon,dt.day,jy,jm,jd);
   return StringFormat("GREGORIAN %04d/%02d/%02d   ·   SHAMSI %04d/%02d/%02d",dt.year,dt.mon,dt.day,jy,jm,jd);
}

void WriteAIMarketSnapshot()
{
   if(!InpAIAdvisoryEnabled) return;
   datetime now=TimeGMT();
   if(g_LastAIRequest>0 && (now-g_LastAIRequest)<MathMax(10,InpAIRefreshSeconds)) return;
   g_LastAIRequest=now;
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double rsi=0.0,adx=0.0;
   double b1[],b2[];
   if(CopyBuffer(h_RSI,0,1,1,b1)>0) rsi=b1[0];
   if(CopyBuffer(h_ADX,0,1,1,b2)>0) adx=b2[0];
   double atr=GetATR(1);
   int h=FileOpen("NixoBridge\\ai_market_snapshot.csv",FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE) { if(InpDebug) Print("AI bridge snapshot write failed: ",GetLastError()); return; }
   string row=StringFormat("%I64d|%s|%s|%.10f|%.10f|%.2f|%.10f|%.3f|%.3f|%s|%d|%d",
      (long)now,_Symbol,EnumToString(_Period),tick.bid,tick.ask,(tick.ask-tick.bid)/_Point,atr,rsi,adx,
      StratShort(g_Strategy),(int)g_Running,(int)g_ManualMode);
   FileWriteString(h,row+"\r\n"); FileClose(h);
}

void ReadAIStatus()
{
   if(!InpAIAdvisoryEnabled) { g_AIState="DISABLED"; g_AIBias="WAIT"; g_AIRisk="—"; g_AISummary="AI advisory disabled"; return; }
   int h=FileOpen("NixoBridge\\ai_status.txt",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE) { g_AIState="OFFLINE"; g_AIBias="WAIT"; g_AIRisk="—"; g_AISummary="Start Nixo AI bridge"; return; }
   string line=FileReadString(h); FileClose(h);
   string p[]; int n=StringSplit(line,'|',p);
   if(n<5) { g_AIState="OFFLINE"; g_AISummary="AI status file incomplete"; return; }
   long stamp=(long)StringToInteger(p[1]);
   if(stamp<=0 || (long)TimeGMT()-stamp>MathMax(30,InpAIMaxStatusAgeSec))
   { g_AIState="OFFLINE"; g_AIBias="WAIT"; g_AIRisk="—"; g_AISummary="AI heartbeat expired"; return; }
   g_AIState=p[0]; g_AIBias=p[2]; g_AIRisk=p[3]; g_AISummary=p[4];
   if(g_AIState!="ONLINE" && g_AIState!="ERROR") g_AIState="OFFLINE";
}

string ManualSizeModeText()
{
   if(g_ManualSizeMode==NIXO_SIZE_FIXED_MONEY) return "FIXED CASH";
   if(g_ManualSizeMode==NIXO_SIZE_FIXED_LOT) return "FIXED LOT";
   return "RISK %";
}

void MDCreateRect(string name,int x,int y,int w,int h,color bg,color edge)
{
   bool created=(ObjectFind(0,name)<0);
   if(created) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w); ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg); ObjectSetInteger(0,name,OBJPROP_COLOR,edge);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_BACK,false); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,(name==MD_BG));
   if(created) ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true); ObjectSetInteger(0,name,OBJPROP_ZORDER,240);
}

void MDCreateLabel(string name,int x,int y,string caption,color clr,int size=9,bool bold=false)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr); ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,name,OBJPROP_FONT,bold?"Segoe UI Semibold":"Segoe UI");
   ObjectSetString(0,name,OBJPROP_TEXT,caption);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,245);
}

void MDCreateButton(string name,int x,int y,int w,int h,string caption,color bg,color fg)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w); ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg); ObjectSetInteger(0,name,OBJPROP_COLOR,fg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'74,90,112');
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9); ObjectSetString(0,name,OBJPROP_FONT,"Segoe UI Semibold");
   ObjectSetString(0,name,OBJPROP_TEXT,caption); ObjectSetInteger(0,name,OBJPROP_STATE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,250);
}

void MDCreateEdit(string name,int x,int y,int w,int h,string value)
{
   if(ObjectFind(0,name)<0)
   {
      ObjectCreate(0,name,OBJ_EDIT,0,0,0);
      ObjectSetString(0,name,OBJPROP_TEXT,value);
   }
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w); ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite); ObjectSetInteger(0,name,OBJPROP_BGCOLOR,C'25,37,55');
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'78,102,132'); ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
   ObjectSetInteger(0,name,OBJPROP_ALIGN,ALIGN_CENTER); ObjectSetInteger(0,name,OBJPROP_READONLY,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,260);
}

//==================================================================
//  TRADINGVIEW-STYLE RISK:REWARD PLANNER
//  LONG/SHORT tool -> click chart for Entry -> drag Entry/SL/TP -> REGISTER.
//  The planner is manual-only and uses the same money-management engine as
//  the Manual Desk. Target becomes the staged TP3 anchor when staged TP is on.
//==================================================================
void DeleteRRToolbar()
{
   string names[]={RR_BAR,RR_TITLE,RR_STATUS,RR_STATUS2,RR_LONG_BUTTON,RR_SHORT_BUTTON,RR_REGISTER_BTN,RR_CANCEL_BTN};
   for(int i=0;i<ArraySize(names);i++) ObjectDelete(0,names[i]);
}

void ClearRRDrawing()
{
   string names[]={RR_ENTRY_LINE,RR_SL_LINE,RR_TP_LINE,RR_RISK_ZONE,RR_REWARD_ZONE,
                   RR_ENTRY_TEXT,RR_SL_TEXT,RR_TP_TEXT};
   for(int i=0;i<ArraySize(names);i++) ObjectDelete(0,names[i]);
   g_RRActive=false;
   g_RREntry=0.0; g_RRSL=0.0; g_RRTP=0.0;
   g_RRLastEntry=0.0; g_RRLastSL=0.0; g_RRLastTP=0.0;
   g_RRAnchorTime=0;
   ChartRedraw();
}

void UpdateRRToolbar()
{
   int chartW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int chartH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   int x=InpPanelX+g_W+10;
   int y=InpPanelY+82;
   if(x+136>chartW-6)
   {
      x=InpPanelX;
      y=InpPanelY+g_H+8; // narrow chart: stack below the original panel, preserving its layout
      if(y+168>chartH-6) { x=MathMax(6,chartW-136); y=8; }
   }
   if(y+168>chartH-6) y=MathMax(6,chartH-174);

   MDCreateRect(RR_BAR,x,y,128,164,C'14,27,45',C'75,139,155');
   MDCreateLabel(RR_TITLE,x+10,y+8,"RISK : REWARD",9,C'255,211,132',true);
   MDCreateButton(RR_LONG_BUTTON,x+8,y+31,53,25,"LONG",C'34,112,87',clrWhite);
   MDCreateButton(RR_SHORT_BUTTON,x+67,y+31,53,25,"SHORT",C'145,62,72',clrWhite);
   color regBg=g_RRActive?C'232,177,54':C'105,91,59';
   color regFg=g_RRActive?C'25,31,39':C'211,211,205';
   string regCaption=g_RRActive?"REGISTER":"REGISTER";
   MDCreateButton(RR_REGISTER_BTN,x+8,y+64,112,29,regCaption,regBg,regFg);
   MDCreateButton(RR_CANCEL_BTN,x+8,y+98,112,23,"CLEAR / CANCEL",C'43,57,75',C'207,219,232');

   string status="Manual mode required";
   string status2="Enable from Manual Desk";
   color statusCol=C'255,180,104';
   if(g_RRPlaceArmed)
   {
      status=(g_RRDirection>0?"Click chart: LONG":"Click chart: SHORT");
      status2="Place the Entry level";
      statusCol=C'120,215,238';
   }
   else if(g_RRActive)
   {
      double risk=MathAbs(g_RREntry-g_RRSL);
      double reward=MathAbs(g_RRTP-g_RREntry);
      double rr=(risk>0.0?reward/risk:0.0);
      status=StringFormat("R:R  1 : %.2f",rr);
      status2=StringFormat("SL %.0f pt | TP %.0f pt",risk/_Point,reward/_Point);
      statusCol=C'149,233,197';
   }
   else if(g_ManualMode)
   {
      status="Choose LONG / SHORT";
      status2="Then click chart";
      statusCol=C'177,198,219';
   }
   MDCreateLabel(RR_STATUS,x+8,y+128,status,statusCol,8,true);
   MDCreateLabel(RR_STATUS2,x+8,y+143,status2,C'180,196,214',7,false);
   ChartRedraw();
}

void RRCreateHLine(const string name,double price,color lineColor,int width,ENUM_LINE_STYLE style,const string tip)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,NormalizeDouble(price,_Digits));
   ObjectSetInteger(0,name,OBJPROP_COLOR,lineColor);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,180);
}

void RRCreateZone(const string name,datetime t1,datetime t2,double p1,double p2,color zoneColor)
{
   double top=MathMax(p1,p2), bottom=MathMin(p1,p2);
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,top,t2,bottom);
   else
   {
      ObjectMove(0,name,0,t1,top);
      ObjectMove(0,name,1,t2,bottom);
   }
   ObjectSetInteger(0,name,OBJPROP_COLOR,zoneColor);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void RRCreatePriceText(const string name,datetime t,double price,const string caption,color textColor)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   else ObjectMove(0,name,0,t,price);
   ObjectSetString(0,name,OBJPROP_TEXT,caption);
   ObjectSetInteger(0,name,OBJPROP_COLOR,textColor);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetString(0,name,OBJPROP_FONT,"Segoe UI Semibold");
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void UpdateRRDrawing()
{
   if(!g_RRActive || g_RRUpdating) return;
   g_RRUpdating=true;
   g_RREntry=NormalizeDouble(g_RREntry,_Digits);
   g_RRSL=NormalizeDouble(g_RRSL,_Digits);
   g_RRTP=NormalizeDouble(g_RRTP,_Digits);

   RRCreateHLine(RR_ENTRY_LINE,g_RREntry,C'255,202,91',2,STYLE_SOLID,"NIXO RR ENTRY — drag to move entry; SL and TP move with it");
   RRCreateHLine(RR_SL_LINE,g_RRSL,C'237,93,102',2,STYLE_DASH,"NIXO RR STOP LOSS — drag to adjust risk");
   RRCreateHLine(RR_TP_LINE,g_RRTP,C'56,202,144',2,STYLE_DASH,"NIXO RR TAKE PROFIT / TP3 — drag to adjust reward");

   datetime t1=g_RRAnchorTime;
   if(t1<=0) t1=TimeCurrent()-PeriodSeconds(_Period)*5;
   int ps=MathMax(60,PeriodSeconds(_Period));
   datetime t2=TimeCurrent()+ps*2;
   if(t2<=t1) t1=t2-ps*20;
   RRCreateZone(RR_REWARD_ZONE,t1,t2,g_RREntry,g_RRTP,C'22,91,68');
   RRCreateZone(RR_RISK_ZONE,t1,t2,g_RREntry,g_RRSL,C'105,44,55');

   double risk=MathAbs(g_RREntry-g_RRSL);
   double reward=MathAbs(g_RRTP-g_RREntry);
   double rr=(risk>0.0?reward/risk:0.0);
   RRCreatePriceText(RR_ENTRY_TEXT,t2,g_RREntry,StringFormat("ENTRY  %s",DoubleToString(g_RREntry,_Digits)),C'255,218,144');
   RRCreatePriceText(RR_SL_TEXT,t2,g_RRSL,StringFormat("SL  %s  |  %.0f pt",DoubleToString(g_RRSL,_Digits),risk/_Point),C'255,151,157');
   RRCreatePriceText(RR_TP_TEXT,t2,g_RRTP,StringFormat("TP3  %s  |  %.0f pt  |  R:R 1:%.2f",DoubleToString(g_RRTP,_Digits),reward/_Point,rr),C'119,235,185');

   g_RRLastEntry=g_RREntry; g_RRLastSL=g_RRSL; g_RRLastTP=g_RRTP;
   g_RRUpdating=false;
   UpdateRRToolbar();
   ChartRedraw();
}

void CreateRRPlan(datetime anchorTime,double entryPrice)
{
   if(!g_ManualMode)
   {
      Alert("RR Planner is manual-only. Enable MANUAL MODE in Manual Desk first.");
      g_RRPlaceArmed=false;
      UpdateRRToolbar();
      return;
   }
   double riskDist=ComputeSLDistWithMultiplier(g_ManualSLATR);
   if(riskDist<=0.0 || entryPrice<=0.0) return;
   g_RREntry=NormalizeDouble(entryPrice,_Digits);
   if(g_RRDirection>0)
   {
      g_RRSL=NormalizeDouble(g_RREntry-riskDist,_Digits);
      g_RRTP=NormalizeDouble(g_RREntry+riskDist*g_ManualTP3R,_Digits);
   }
   else
   {
      g_RRSL=NormalizeDouble(g_RREntry+riskDist,_Digits);
      g_RRTP=NormalizeDouble(g_RREntry-riskDist*g_ManualTP3R,_Digits);
   }
   g_RRAnchorTime=(anchorTime>0?anchorTime:TimeCurrent());
   g_RRActive=true;
   g_RRPlaceArmed=false;
   UpdateRRDrawing();
   PrintFormat("RR PLAN CREATED | %s | Entry=%.*f | SL=%.*f | TP3=%.*f | R:R=1:%.2f | drag any line then press REGISTER",
      g_RRDirection>0?"LONG":"SHORT",_Digits,g_RREntry,_Digits,g_RRSL,_Digits,g_RRTP,
      MathAbs(g_RRTP-g_RREntry)/MathAbs(g_RREntry-g_RRSL));
}

bool HandleRRObjectDrag(const string objectName)
{
   if(!g_RRActive || g_RRUpdating) return false;
   if(objectName!=RR_ENTRY_LINE && objectName!=RR_SL_LINE && objectName!=RR_TP_LINE) return false;
   double moved=ObjectGetDouble(0,objectName,OBJPROP_PRICE);
   if(moved<=0.0) return true;
   moved=NormalizeDouble(moved,_Digits);
   if(objectName==RR_ENTRY_LINE)
   {
      double delta=moved-g_RREntry;
      g_RREntry=moved;
      g_RRSL=NormalizeDouble(g_RRSL+delta,_Digits);
      g_RRTP=NormalizeDouble(g_RRTP+delta,_Digits);
   }
   else if(objectName==RR_SL_LINE) g_RRSL=moved;
   else g_RRTP=moved;

   bool valid=(g_RRDirection>0)?(g_RRSL<g_RREntry && g_RRTP>g_RREntry)
                              :(g_RRSL>g_RREntry && g_RRTP<g_RREntry);
   if(!valid)
   {
      g_RREntry=g_RRLastEntry; g_RRSL=g_RRLastSL; g_RRTP=g_RRLastTP;
      Alert("Invalid RR layout: for LONG, SL must be below Entry and TP above; for SHORT, the reverse.");
   }
   UpdateRRDrawing();
   return true;
}

bool RegisterRRPlan()
{
   if(!g_RRActive)
   {
      Alert("First choose LONG or SHORT, then click the chart to draw a Risk:Reward plan.");
      return false;
   }
   if(!g_ManualMode)
   {
      Alert("Enable MANUAL MODE in Manual Desk before registering an RR setup.");
      return false;
   }
   if(g_Stopped || g_DailyStopped || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      Alert("Nixo trading is locked or trading permissions are disabled.");
      return false;
   }
   if(DailyTradeLimitReached()) { Alert("Nixo daily trade limit reached."); return false; }
   if(EntryRateLimitReached()) { Alert("Nixo per-minute entry rate limit reached."); return false; }
   int rrMaxOpen=MaxOpenAllowed();
   if(InpMaxOrderCount>0) rrMaxOpen=MathMin(rrMaxOpen,InpMaxOrderCount);
   int rrPendingCount=0;
   double rrPendingRiskMoney=0.0;
   for(int oi=OrdersTotal()-1;oi>=0;oi--)
   {
      ulong otk=OrderGetTicket(oi); if(otk==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)!=InpMagic || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      rrPendingCount++;
      ENUM_ORDER_TYPE pendingRiskType=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool pendingBuy=(pendingRiskType==ORDER_TYPE_BUY_LIMIT || pendingRiskType==ORDER_TYPE_BUY_STOP || pendingRiskType==ORDER_TYPE_BUY_STOP_LIMIT);
      bool pendingSell=(pendingRiskType==ORDER_TYPE_SELL_LIMIT || pendingRiskType==ORDER_TYPE_SELL_STOP || pendingRiskType==ORDER_TYPE_SELL_STOP_LIMIT);
      if(!pendingBuy && !pendingSell) continue;
      double pendingSL=OrderGetDouble(ORDER_SL);
      double pendingVol=OrderGetDouble(ORDER_VOLUME_CURRENT);
      double pendingPrice=OrderGetDouble(ORDER_PRICE_OPEN);
      if(pendingSL<=0.0)
      {
         rrPendingRiskMoney+=SelectedRiskBase(); // conservative: an unprotected Nixo pending order blocks new risk
         continue;
      }
      ENUM_ORDER_TYPE calcPendingType=pendingBuy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      double adversePendingSL=(pendingBuy?pendingSL-MathMax(0,InpRiskSlippagePoints)*_Point
                                         :pendingSL+MathMax(0,InpRiskSlippagePoints)*_Point);
      double pendingPL=0.0;
      if(!OrderCalcProfit(calcPendingType,_Symbol,pendingVol,pendingPrice,adversePendingSL,pendingPL))
         rrPendingRiskMoney+=SelectedRiskBase();
      else
         rrPendingRiskMoney+=MathMax(0.0,-pendingPL)+EstimateRoundTurnCommissionPerLot()*pendingVol;
   }
   if(CountMyPositions()+rrPendingCount>=rrMaxOpen)
   { Alert("Nixo position/order limit reached."); return false; }

   bool longSide=(g_RRDirection>0);
   ENUM_ORDER_TYPE marketType=longSide?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!g_HedgeEnabled && HasOppositePosition(marketType))
   {
      Alert("Hedge mode is OFF: an opposite Nixo position is already open.");
      return false;
   }

   double entry=NormalizeDouble(g_RREntry,_Digits);
   double sl=NormalizeDouble(g_RRSL,_Digits);
   double tp3=NormalizeDouble(g_RRTP,_Digits);
   double riskDist=MathAbs(entry-sl);
   double rewardDist=MathAbs(tp3-entry);
   if(riskDist<_Point || rewardDist<_Point ||
      (longSide && !(sl<entry && tp3>entry)) || (!longSide && !(sl>entry && tp3<entry)))
   {
      Alert("Invalid RR levels. Check Entry, Stop Loss and Take Profit positions.");
      return false;
   }
   double tp3R=rewardDist/riskDist;
   if(UseStagedTP() && (tp3R<=g_TP2R || tp3R>20.0))
   {
      Alert(StringFormat("With staged TP enabled, TP3 must be beyond TP2 (%.2fR) and no farther than 20R. Current: %.2fR.",g_TP2R,tp3R));
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.ask<=0.0 || tick.bid<=0.0) return false;
   double minDist=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                  SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point+_Point;
   double spread=MathMax(0.0,tick.ask-tick.bid);
   double nearTol=MathMax(3.0*_Point,spread*1.5);
   ENUM_ORDER_TYPE pendingType=marketType;
   bool isPending=false;
   double orderEntry=entry;

   if(longSide)
   {
      if(MathAbs(entry-tick.ask)<=nearTol)
      {
         orderEntry=tick.ask;
         double offsetSL=g_RRSL-g_RREntry, offsetTP=g_RRTP-g_RREntry;
         sl=NormalizeDouble(orderEntry+offsetSL,_Digits);
         tp3=NormalizeDouble(orderEntry+offsetTP,_Digits);
      }
      else if(entry<tick.ask-minDist) { pendingType=ORDER_TYPE_BUY_LIMIT; isPending=true; }
      else if(entry>tick.ask+minDist) { pendingType=ORDER_TYPE_BUY_STOP; isPending=true; }
      else { Alert("Entry is inside the broker's minimum pending-order distance. Move Entry farther away or closer to market."); return false; }
   }
   else
   {
      if(MathAbs(entry-tick.bid)<=nearTol)
      {
         orderEntry=tick.bid;
         double offsetSL=g_RRSL-g_RREntry, offsetTP=g_RRTP-g_RREntry;
         sl=NormalizeDouble(orderEntry+offsetSL,_Digits);
         tp3=NormalizeDouble(orderEntry+offsetTP,_Digits);
      }
      else if(entry>tick.bid+minDist) { pendingType=ORDER_TYPE_SELL_LIMIT; isPending=true; }
      else if(entry<tick.bid-minDist) { pendingType=ORDER_TYPE_SELL_STOP; isPending=true; }
      else { Alert("Entry is inside the broker's minimum pending-order distance. Move Entry farther away or closer to market."); return false; }
   }

   double finalRiskDist=MathAbs(orderEntry-sl);
   double finalRewardDist=MathAbs(tp3-orderEntry);
   if(g_MaxSpreadPct>0.0 && finalRiskDist>0.0 && (CostDistance()/finalRiskDist*100.0)>g_MaxSpreadPct)
   { Alert("Current spread/commission cost exceeds the configured Cost / SL limit."); return false; }
   if(InpMaxSpread>0 && (tick.ask-tick.bid)/_Point>InpMaxSpread)
   { Alert("Current spread exceeds the configured maximum spread."); return false; }
   if(finalRiskDist<minDist || (longSide && !(sl<orderEntry && tp3>orderEntry)) ||
      (!longSide && !(sl>orderEntry && tp3<orderEntry)))
   {
      Alert("SL is too close to Entry for this broker or the recalculated levels are invalid.");
      return false;
   }
   if(!isPending)
   {
      double executable=(longSide?tick.bid:tick.ask);
      if((longSide && executable-sl<minDist) || (!longSide && sl-executable<minDist))
      { Alert("Stop Loss is inside the broker's minimum stop/freeze distance from the market."); return false; }
   }

   tp3R=finalRewardDist/finalRiskDist;
   if(UseStagedTP() && (tp3R<=g_TP2R || tp3R>20.0))
   { Alert("Adjusted TP3 is outside the valid staged TP range."); return false; }

   double riskPct=(g_ManualSizeMode==NIXO_SIZE_RISK_PERCENT)?g_ManualSizeValue:GetCurrentRiskPct();
   double cashRisk=(g_ManualSizeMode==NIXO_SIZE_FIXED_MONEY)?g_ManualSizeValue:-1.0;
   double fixedLot=(g_ManualSizeMode==NIXO_SIZE_FIXED_LOT)?g_ManualSizeValue:-1.0;
   double lot=CalcLot(marketType,riskPct,finalRiskDist,orderEntry,cashRisk,(int)g_ManualSizeMode,fixedLot);
   if(lot<=0.0) return false;
   if(UseStagedTP() && !MultiTPPlanValid(lot))
   {
      Alert("This lot is too small for TP1/TP2/TP3 partial closes and a valid 12.5% runner at this broker.");
      return false;
   }
   if(InpMaxOpenRiskPct>0.0)
   {
      double cap=SelectedRiskBase()*InpMaxOpenRiskPct/100.0;
      double total=OpenRiskMoney()+rrPendingRiskMoney+ActualRiskMoney(marketType,lot,orderEntry,sl);
      if(total>cap+1e-8)
      {
         Alert(StringFormat("Open-risk cap prevents this entry: %.2f > %.2f %s.",total,cap,AccountInfoString(ACCOUNT_CURRENCY)));
         return false;
      }
   }

   double brokerTP=UseStagedTP()?0.0:tp3;
   sl=NormalizeDouble(sl,_Digits);
   if(brokerTP>0.0) brokerTP=NormalizeDouble(brokerTP,_Digits);
   bool ownBatch=(g_ActiveBatchId<=0);
   long batchId=ownBatch?NextBatchId():g_ActiveBatchId;
   string comment=StringFormat("Nixo500|%s|M|B%I64d",isPending?"RR_PENDING":"RR_MARKET",batchId);
   bool sent=false;
   if(!isPending)
   {
      sent=longSide?trade.Buy(lot,_Symbol,0.0,sl,brokerTP,comment)
                    :trade.Sell(lot,_Symbol,0.0,sl,brokerTP,comment);
   }
   else if(pendingType==ORDER_TYPE_BUY_LIMIT)
      sent=trade.BuyLimit(lot,orderEntry,_Symbol,sl,brokerTP,ORDER_TIME_GTC,0,comment);
   else if(pendingType==ORDER_TYPE_SELL_LIMIT)
      sent=trade.SellLimit(lot,orderEntry,_Symbol,sl,brokerTP,ORDER_TIME_GTC,0,comment);
   else if(pendingType==ORDER_TYPE_BUY_STOP)
      sent=trade.BuyStop(lot,orderEntry,_Symbol,sl,brokerTP,ORDER_TIME_GTC,0,comment);
   else if(pendingType==ORDER_TYPE_SELL_STOP)
      sent=trade.SellStop(lot,orderEntry,_Symbol,sl,brokerTP,ORDER_TIME_GTC,0,comment);

   bool accepted=isPending?PendingOrderRequestSucceeded(sent):TradeRequestSucceeded(sent);
   if(!accepted)
   {
      if(ownBatch) g_ActiveBatchId=0;
      PrintFormat("RR REGISTER FAILED | retcode=%u | %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
      Alert(StringFormat("RR order failed: %s",trade.ResultRetcodeDescription()));
      return false;
   }

   double actualRisk=ActualRiskMoney(marketType,lot,orderEntry,sl);
   double base=SelectedRiskBase();
   g_LastLot=lot; g_LastRiskMoney=actualRisk; g_LastRiskPct=(base>0.0?actualRisk/base*100.0:0.0);
   if(isPending)
   {
      ulong orderTicket=trade.ResultOrder();
      if(orderTicket>0) GlobalVariableSet(GVKey("PEND_A_"+(string)orderTicket),tp3R);
      PrintFormat("RR PENDING REGISTERED | %s | Entry=%.*f | SL=%.*f | TP3=%.*f | R:R=1:%.2f | lot=%.3f | risk~%.2f %s",
         EnumToString(pendingType),_Digits,orderEntry,_Digits,sl,_Digits,tp3, tp3R,lot,actualRisk,AccountInfoString(ACCOUNT_CURRENCY));
   }
   else
   {
      g_TradesToday++;
      RecordEntryTimestamp();
      ulong openingDeal=trade.ResultDeal();
      if(openingDeal>0 && HistoryDealSelect(openingDeal))
      {
         ulong positionId=(ulong)HistoryDealGetInteger(openingDeal,DEAL_POSITION_ID);
         if(positionId>0)
         {
            double fill=trade.ResultPrice()>0.0?trade.ResultPrice():orderEntry;
            double riskAtFill=ActualRiskMoney(marketType,lot,fill,sl);
            GlobalVariableSet(GVKey("RISK_"+(string)positionId),riskAtFill);
            GlobalVariableSet(PositionStateKey(positionId,"SP"),MathMax(0.0,tick.ask-tick.bid));
            GlobalVariableSet(PositionStateKey(positionId,"A"),tp3R);
            RegisterBatchPosition(batchId,positionId);
            g_LastRiskMoney=riskAtFill;
            g_LastRiskPct=(base>0.0?riskAtFill/base*100.0:0.0);
         }
      }
      PrintFormat("RR MARKET REGISTERED | %s | planned Entry=%.*f | SL=%.*f | TP3=%.*f | R:R=1:%.2f | lot=%.3f | risk~%.2f %s",
         longSide?"BUY":"SELL",_Digits,orderEntry,_Digits,sl,_Digits,tp3,tp3R,lot,actualRisk,AccountInfoString(ACCOUNT_CURRENCY));
   }
   if(ownBatch) g_ActiveBatchId=0;
   g_LastSig="";
   Render();
   return true;
}

void DeleteManualDesk()
{
   string names[]={MD_BG,MD_PREFIX+"TITLE",MD_PREFIX+"CLOSE",MD_PREFIX+"MODE",MD_PREFIX+"MODE_LBL",
      MD_PREFIX+"VALUE_LBL",MD_PREFIX+"SL_LBL",MD_PREFIX+"TP_LBL",MD_PREFIX+"INFO",MD_PREFIX+"INFO2",MD_PREFIX+"INFO3",MD_PREFIX+"ENTRY_LBL",MD_PREFIX+"STATE",
      MD_PREFIX+"BUY",MD_PREFIX+"SELL",MD_PREFIX+"BUYLIMIT",MD_PREFIX+"SELLLIMIT",MD_PREFIX+"TOGGLE",
      MD_ENTRY,MD_SIZE_VALUE,MD_SL_ATR,MD_TP3_R};
   for(int i=0;i<ArraySize(names);i++) ObjectDelete(0,names[i]);
}

void UpdateManualDesk()
{
   if(!g_ManualDeskOpen) return;
   int chartW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int chartH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   int w=300,h=352;
   int x=(g_ManualDeskX>=0?g_ManualDeskX:InpPanelX+g_W+14);
   if(x+w>chartW-8) x=MathMax(8,chartW-w-12);
   int y=(g_ManualDeskY>=0?g_ManualDeskY:InpPanelY+28);
   y=MathMax(8,MathMin(y,chartH-h-8));
   g_ManualDeskX=x; g_ManualDeskY=y;
   MDCreateRect(MD_BG,x,y,w,h,C'13,22,38',C'217,154,91');
   MDCreateLabel(MD_PREFIX+"TITLE",x+14,y+11,"NIXO  |  MANUAL DESK",C'255,215,145',11,true);
   MDCreateButton(MD_PREFIX+"CLOSE",x+w-30,y+7,22,22,"×",C'104,48,57',clrWhite);
   MDCreateLabel(MD_PREFIX+"STATE",x+14,y+39,g_ManualMode?"MANUAL MODE  •  ON":"MANUAL MODE  •  OFF",g_ManualMode?C'72,222,161':C'255,180,104',9,true);
   MDCreateButton(MD_PREFIX+"TOGGLE",x+181,y+33,104,25,g_ManualMode?"PAUSE MANUAL":"ENABLE MANUAL",g_ManualMode?C'48,108,88':C'87,66,39',clrWhite);
   MDCreateLabel(MD_PREFIX+"MODE_LBL",x+14,y+76,"POSITION SIZING",C'164,181,205',8,true);
   MDCreateButton(MD_PREFIX+"MODE",x+14,y+91,124,27,ManualSizeModeText(),C'45,58,80',clrWhite);
   MDCreateLabel(MD_PREFIX+"VALUE_LBL",x+151,y+76,"VALUE",C'164,181,205',8,true);
   MDCreateEdit(MD_SIZE_VALUE,x+151,y+91,134,27,DoubleToString(g_ManualSizeValue,2));
   MDCreateLabel(MD_PREFIX+"SL_LBL",x+14,y+130,"STOP DISTANCE  |  ATR MULTIPLIER",C'164,181,205',8,true);
   MDCreateEdit(MD_SL_ATR,x+14,y+145,124,27,DoubleToString(g_ManualSLATR,2));
   MDCreateLabel(MD_PREFIX+"TP_LBL",x+151,y+130,"TP3 TARGET  |  R",C'164,181,205',8,true);
   MDCreateEdit(MD_TP3_R,x+151,y+145,134,27,DoubleToString(g_ManualTP3R,2));
   MDCreateLabel(MD_PREFIX+"INFO",x+14,y+180,"TP1 1R  •  TP2 2R  •  TP3 custom R",C'227,232,241',8,false);
   MDCreateLabel(MD_PREFIX+"INFO2",x+14,y+197,"50% / 50% remainder / 50% remainder",C'154,171,193',8,false);
   MDCreateLabel(MD_PREFIX+"INFO3",x+14,y+214,"Runner: 12.5%  |  ATR trail",C'255,210,130',8,true);
   MDCreateLabel(MD_PREFIX+"ENTRY_LBL",x+14,y+239,"LIMIT ENTRY PRICE  (0 = click chart)",C'164,181,205',8,true);
   MDCreateEdit(MD_ENTRY,x+14,y+254,271,27,g_ManualPrice>0.0?DoubleToString(g_ManualPrice,_Digits):"0");
   MDCreateButton(MD_PREFIX+"BUY",x+14,y+292,130,27,"BUY MARKET",C'29,125,90',clrWhite);
   MDCreateButton(MD_PREFIX+"SELL",x+155,y+292,130,27,"SELL MARKET",C'161,65,75',clrWhite);
   MDCreateButton(MD_PREFIX+"BUYLIMIT",x+14,y+323,130,24,"BUY LIMIT",C'37,91,82',clrWhite);
   MDCreateButton(MD_PREFIX+"SELLLIMIT",x+155,y+323,130,24,"SELL LIMIT",C'103,54,65',clrWhite);
   ChartRedraw();
}

void HandleManualDeskEdit(string objectName)
{
   if(objectName==MD_ENTRY)
   {
      string v=ObjectGetString(0,MD_ENTRY,OBJPROP_TEXT); StringReplace(v,",",".");
      g_ManualPrice=StringToDouble(v);
   }
   else if(objectName==MD_SIZE_VALUE)
   {
      string v=ObjectGetString(0,MD_SIZE_VALUE,OBJPROP_TEXT); StringReplace(v,",",".");
      double x=StringToDouble(v); if(x>0.0) g_ManualSizeValue=x;
   }
   else if(objectName==MD_SL_ATR)
   {
      string v=ObjectGetString(0,MD_SL_ATR,OBJPROP_TEXT); StringReplace(v,",",".");
      double x=StringToDouble(v); if(x>=0.5 && x<=10.0) g_ManualSLATR=x;
   }
   else if(objectName==MD_TP3_R)
   {
      string v=ObjectGetString(0,MD_TP3_R,OBJPROP_TEXT); StringReplace(v,",",".");
      double x=StringToDouble(v); if(x>g_TP2R && x<=20.0) g_ManualTP3R=x;
   }
   g_LastSig=""; UpdateManualDesk(); Render();
}

//==================================================================
//  ░░  PANEL  ░░   iPod-touch style (true-scale bitmap renderer)
//  All coordinates below are LOGICAL units; every primitive multiplies
//  them by g_S (InpPanelScale) so shapes stay round and text stays sharp.
//==================================================================
#define SCR_Y1 24
#define SCR_Y2 379

uint     g_bg[];
string   g_BgKey = "";

uint WithAlpha(uint col, int a)
{
   return ((uint)a << 24) | (col & 0x00FFFFFF);
}

uint C(int rgb, int a = 255)
{
   return ((uint)a << 24) | ((uint)rgb & 0xFFFFFF);
}

uint LerpC(uint a, uint b, double t)
{
   double aa = (double)((a >> 24) & 0xFF), ar = (double)((a >> 16) & 0xFF), ag = (double)((a >> 8) & 0xFF), ab = (double)(a & 0xFF);
   double ba = (double)((b >> 24) & 0xFF), br = (double)((b >> 16) & 0xFF), bg = (double)((b >> 8) & 0xFF), bb = (double)(b & 0xFF);
   uint ra = (uint)(aa + (ba - aa) * t + 0.5);
   uint rr = (uint)(ar + (br - ar) * t + 0.5);
   uint rg = (uint)(ag + (bg - ag) * t + 0.5);
   uint rb = (uint)(ab + (bb - ab) * t + 0.5);
   return (ra << 24) | (rr << 16) | (rg << 8) | rb;
}

// physical-pixel alpha blend (straight alpha "over")
void BlendPx(int x, int y, uint src, double cov)
{
   if(x < 0 || y < 0 || x >= g_W || y >= g_H) return;
   double sa = ((double)((src >> 24) & 0xFF) / 255.0) * cov;
   if(sa <= 0.0) return;

   int idx = y * g_W + x;
   uint d = g_px[idx];
   double da = (double)((d >> 24) & 0xFF) / 255.0;
   double oa = sa + da * (1.0 - sa);
   if(oa <= 0.0) { g_px[idx] = 0; return; }

   double sr = (double)((src >> 16) & 0xFF), sg = (double)((src >> 8) & 0xFF), sb = (double)(src & 0xFF);
   double dr = (double)((d   >> 16) & 0xFF), dg = (double)((d   >> 8) & 0xFF), db = (double)(d   & 0xFF);

   double r = (sr * sa + dr * da * (1.0 - sa)) / oa;
   double g = (sg * sa + dg * da * (1.0 - sa)) / oa;
   double b = (sb * sa + db * da * (1.0 - sa)) / oa;

   uint ua = (uint)Clampd(oa * 255.0 + 0.5, 0, 255);
   uint ur = (uint)Clampd(r + 0.5, 0, 255);
   uint ug = (uint)Clampd(g + 0.5, 0, 255);
   uint ub = (uint)Clampd(b + 0.5, 0, 255);
   g_px[idx] = (ua << 24) | (ur << 16) | (ug << 8) | ub;
}

double SdRR(double px, double py, double cx, double cy, double hw, double hh, double r)
{
   double qx = MathAbs(px - cx) - hw + r;
   double qy = MathAbs(py - cy) - hh + r;
   double ox = MathMax(qx, 0.0), oy = MathMax(qy, 0.0);
   return MathSqrt(ox * ox + oy * oy) + MathMin(MathMax(qx, qy), 0.0) - r;
}

double SMin(double a, double b, double k)
{
   double h = MathMax(k - MathAbs(a - b), 0.0) / k;
   return MathMin(a, b) - h * h * k * 0.25;
}

// rounded rectangle, vertical gradient (c1 top → c2 bottom). LOGICAL coords.
void FillRR(double x1, double y1, double x2, double y2, double r, uint c1, uint c2)
{
   x1 *= g_S; y1 *= g_S; x2 *= g_S; y2 *= g_S; r *= g_S;
   double cx = (x1 + x2) * 0.5, cy = (y1 + y2) * 0.5;
   double hw = (x2 - x1) * 0.5, hh = (y2 - y1) * 0.5;
   if(hw <= 0 || hh <= 0) return;
   if(r > MathMin(hw, hh)) r = MathMin(hw, hh);

   int ix1 = (int)MathFloor(x1) - 1, ix2 = (int)MathCeil(x2) + 1;
   int iy1 = (int)MathFloor(y1) - 1, iy2 = (int)MathCeil(y2) + 1;

   for(int y = iy1; y <= iy2; y++)
   {
      double t = Clampd((y + 0.5 - y1) / (y2 - y1), 0.0, 1.0);
      uint col = (c1 == c2) ? c1 : LerpC(c1, c2, t);
      for(int x = ix1; x <= ix2; x++)
      {
         double d   = SdRR(x + 0.5, y + 0.5, cx, cy, hw, hh, r);
         double cov = Clampd(0.5 - d, 0.0, 1.0);
         if(cov > 0.0) BlendPx(x, y, col, cov);
      }
   }
}

void StrokeRR(double x1, double y1, double x2, double y2, double r, double w, uint col)
{
   x1 *= g_S; y1 *= g_S; x2 *= g_S; y2 *= g_S; r *= g_S; w *= g_S;
   double cx = (x1 + x2) * 0.5, cy = (y1 + y2) * 0.5;
   double hw = (x2 - x1) * 0.5, hh = (y2 - y1) * 0.5;
   if(hw <= 0 || hh <= 0) return;
   if(r > MathMin(hw, hh)) r = MathMin(hw, hh);

   int ix1 = (int)MathFloor(x1) - 1, ix2 = (int)MathCeil(x2) + 1;
   int iy1 = (int)MathFloor(y1) - 1, iy2 = (int)MathCeil(y2) + 1;

   for(int y = iy1; y <= iy2; y++)
      for(int x = ix1; x <= ix2; x++)
      {
         double d   = SdRR(x + 0.5, y + 0.5, cx, cy, hw, hh, r);
         double cov = Clampd(0.5 - (MathAbs(d + w * 0.5) - w * 0.5), 0.0, 1.0);
         if(cov > 0.0) BlendPx(x, y, col, cov);
      }
}

void FillCircle(double cx, double cy, double r, uint c1, uint c2)
{
   FillRR(cx - r, cy - r, cx + r, cy + r, r, c1, c2);
}

void StrokeCircle(double cx, double cy, double r, double w, uint col)
{
   StrokeRR(cx - r, cy - r, cx + r, cy + r, r, w, col);
}

void FillGlow(double cx, double cy, double r, double spread, int rgb, int maxA)
{
   cx *= g_S; cy *= g_S; r *= g_S; spread *= g_S;
   int ix1 = (int)(cx - r - spread) - 1, ix2 = (int)(cx + r + spread) + 1;
   int iy1 = (int)(cy - r - spread) - 1, iy2 = (int)(cy + r + spread) + 1;
   for(int y = iy1; y <= iy2; y++)
      for(int x = ix1; x <= ix2; x++)
      {
         double dx = x + 0.5 - cx, dy = y + 0.5 - cy;
         double d  = MathSqrt(dx * dx + dy * dy) - r;
         if(d <= 0.0 || d >= spread) continue;
         double f = 1.0 - d / spread;
         int a = (int)(maxA * f * f);
         if(a > 0) BlendPx(x, y, C(rgb, a), 1.0);
      }
}

// power glyph: ring with a gap at the top + vertical bar
void DrawPower(double cx, double cy, double r, double w, uint col)
{
   double sx = cx * g_S, sy = cy * g_S, sr = r * g_S, sw = w * g_S;
   int ix1 = (int)(sx - sr - sw) - 1, ix2 = (int)(sx + sr + sw) + 1;
   int iy1 = (int)(sy - sr - sw) - 1, iy2 = (int)(sy + sr + sw) + 1;
   for(int y = iy1; y <= iy2; y++)
      for(int x = ix1; x <= ix2; x++)
      {
         double dx = x + 0.5 - sx, dy = y + 0.5 - sy;
         double d  = MathSqrt(dx * dx + dy * dy);
         double cov = Clampd(0.5 - (MathAbs(d - sr) - sw * 0.5), 0.0, 1.0);
         if(cov <= 0.0) continue;
         double ang = MathArctan2(dx, -dy);           // 0 = straight up
         if(MathAbs(ang) < 0.55) continue;
         BlendPx(x, y, col, cov);
      }
   FillRR(cx - w * 0.5, cy - r - 2.0, cx + w * 0.5, cy - 1.0, w * 0.5, col, col);
}

int FontPx(int px)
{
   return (int)MathMax(8, MathRound(px * g_S));
}

// logical width of a string
int TxtW(string s, int px, bool bold)
{
   TextSetFont(InpFont, FontPx(px), bold ? FW_BOLD : FW_NORMAL, 0);
   uint w = 0, h = 0;
   TextGetSize(s, w, h);
   return (int)MathCeil((double)w / g_S);
}

void Txt(int x, int y, string s, int px, uint col, bool bold, uint anchor)
{
   TextSetFont(InpFont, FontPx(px), bold ? FW_BOLD : FW_NORMAL, 0);
   TextOut(s, (int)MathRound(x * g_S), (int)MathRound(y * g_S), anchor,
           g_px, (uint)g_W, (uint)g_H, col, COLOR_FORMAT_ARGB_NORMALIZE);
}

void AddHit(int x1, int y1, int x2, int y2, int act)
{
   if(g_HitN >= ArraySize(g_Hits)) ArrayResize(g_Hits, g_HitN + 16);
   g_Hits[g_HitN].x1 = (int)MathFloor(x1 * g_S);
   g_Hits[g_HitN].y1 = (int)MathFloor(y1 * g_S);
   g_Hits[g_HitN].x2 = (int)MathCeil (x2 * g_S);
   g_Hits[g_HitN].y2 = (int)MathCeil (y2 * g_S);
   g_Hits[g_HitN].act = act;
   g_HitN++;
}

string FmtMoney(double v, int digits = 2)
{
   string s  = DoubleToString(MathAbs(v), digits);
   int dot   = StringFind(s, ".");
   string ip = (dot >= 0) ? StringSubstr(s, 0, dot) : s;
   string fp = (dot >= 0) ? StringSubstr(s, dot) : "";
   string out = "";
   int cnt = 0;
   for(int i = StringLen(ip) - 1; i >= 0; i--)
   {
      out = StringSubstr(ip, i, 1) + out;
      cnt++;
      if(cnt % 3 == 0 && i > 0) out = "," + out;
   }
   return (v < 0 ? "-" : "") + out + fp;
}

string SettingText(int row)
{
   switch(row)
   {
      case 0: return DoubleToString(g_BaseRisk,2)+"%";
      case 1: return DoubleToString(g_ATRMult,2)+" ATR";
      case 2: return "1:"+DoubleToString(g_TPAnchorR,1);
      case 3: return (g_MaxLot<=0.0) ? "OFF" : DoubleToString(g_MaxLot,2);
      case 4: return (g_MaxSpreadPct<=0.0) ? "OFF" : DoubleToString(g_MaxSpreadPct,1)+"%";
      case 5: return g_UseBE ? "ON" : "OFF";
      case 6: return DoubleToString(g_TP1R,2)+"R";
      case 7: return DoubleToString(g_TP2R,2)+"R";
      case 8: return DoubleToString(g_RunnerTrailATR,2)+" ATR";
      case 9: return DoubleToString(g_TPRR,2)+"R";
      case 10: return IntegerToString(g_MaxStep);
   }
   return "";
}

void UpdatePanel() { Render(); }

void DrawStatic(int B, double R)
{
   double S=g_S, cx=g_W/2.0, cy=(B*S)/2.0;
   double hw=g_W/2.0-1.0*S, hh=(B*S)/2.0-0.5*S;
   double rad=30.0*S, Rr=R*S, kk=12.0*S;
   for(int y=0;y<g_H;y++)
   {
      double t=Clampd((double)y/(B*S),0.0,1.0);
      uint body=LerpC(C(0x343945),C(0x141925),t);
      for(int x=0;x<g_W;x++)
      {
         double px=x+0.5, py=y+0.5;
         double d1=SdRR(px,py,cx,cy,hw,hh,rad);
         double dx=px-cx, dy=py-B*S;
         double d2=MathSqrt(dx*dx+dy*dy)-Rr;
         double d=SMin(d1,d2,kk);
         double cov=Clampd(0.5-d,0.0,1.0);
         if(cov<=0.0) continue;
         BlendPx(x,y,body,cov);
         double edge=Clampd(0.5-(MathAbs(d+0.8*S)-0.8*S),0.0,1.0);
         if(edge>0.0) BlendPx(x,y,C(0xD69A5B,125),edge);
      }
   }
   FillRR(14,20,UI_W-14,B-8,18,C(0x121A2B),C(0x080D18));
   StrokeRR(13,19,UI_W-13,B-7,19,3.0,C(0xD18B4E,55));
   StrokeRR(14,20,UI_W-14,B-8,18,1.8,C(0xD79A5B,135));
   StrokeRR(14,20,UI_W-14,B-8,18,0.8,C(0xE8B47B,190));
}

void Render()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double plPct=(g_StartEquity>0.0)?(equity-g_StartEquity)/g_StartEquity*100.0:0.0;
   double dayPL=(g_DayStartEquity>0.0)?(equity-g_DayStartEquity)/g_DayStartEquity*100.0:0.0;
   double flt=FloatingPL(), wr=(g_Trades>0)?100.0*g_Wins/g_Trades:0.0;
   double pf=(g_GrossL>0.0)?g_GrossP/g_GrossL:(g_GrossP>0.0?99.0:0.0);
   bool cooldown=(TimeCurrent()<g_CooldownUntil);
   string sessionTime=CurrentSessionLabel()+" "+TimeToString(TimeCurrent(),TIME_MINUTES);
   string datePair=CurrentDatePair();

   string sig=DoubleToString(equity,2)+"|"+DoubleToString(balance,2)+"|"+DoubleToString(flt,2)+"|"+
      IntegerToString(g_Strategy)+"|"+IntegerToString((int)g_Running)+"|"+IntegerToString((int)g_Stopped)+"|"+
      IntegerToString((int)g_DailyStopped)+"|"+IntegerToString((int)g_RiskRouletteEnabled)+"|"+
      IntegerToString((int)g_OrderRouletteEnabled)+"|"+IntegerToString((int)g_MultiOrderEnabled)+"|"+
      IntegerToString((int)g_TurboEnabled)+"|"+IntegerToString((int)g_PortfolioMode)+"|"+
      IntegerToString((int)g_HedgeEnabled)+"|"+IntegerToString((int)g_TradingMode)+"|"+IntegerToString((int)g_EntriesPaused)+"|"+IntegerToString((int)g_SignalLiveEnabled)+"|"+
      DoubleToString(g_NetProfit,2)+"|"+DoubleToString(g_TPAnchorR,2)+"|"+
      DoubleToString(g_ManualPrice,_Digits)+"|"+IntegerToString(g_OrderCount)+"|"+
      IntegerToString(g_Step)+"|"+IntegerToString((int)g_Roulette)+"|"+
      DoubleToString(GetCurrentRiskPct(),3)+"|"+DoubleToString(g_LastLot,2)+"|"+
      DoubleToString(g_LastRiskPct,2)+"|"+IntegerToString(g_Trades)+"|"+
      IntegerToString(g_Wins)+"|"+DoubleToString(g_GrossP,2)+"|"+
      DoubleToString(g_GrossL,2)+"|"+DoubleToString(dayPL,2)+"|"+
      DoubleToString(plPct,2)+"|"+IntegerToString((int)g_ShowSettings)+"|"+
      IntegerToString((int)(g_CloseAllConfirmUntilMs>GetTickCount64()))+"|"+sessionTime+"|"+datePair+"|"+
      g_AIState+"|"+g_AIBias+"|"+g_AIRisk+"|"+g_AISummary+"|"+IntegerToString((int)g_ManualDeskOpen)+"|"+IntegerToString(g_ManualDeskX)+"|"+IntegerToString(g_ManualDeskY)+"|"+
      IntegerToString((int)g_RRPlaceArmed)+"|"+IntegerToString((int)g_RRActive)+"|"+IntegerToString(g_RRDirection);
   if(sig==g_LastSig && ObjectFind(0,UI_OBJ)>=0) { UpdateRRToolbar(); return; }
   g_LastSig=sig;

   const int W=UI_W;
   const int rowH=27;
   const int settingsHeaderY=375;
   const int settingsTop=392;
   int settingsBottom=g_ShowSettings ? settingsTop+124 : settingsHeaderY+4;
   int manualDeskY=settingsBottom+9;
   int closeY=manualDeskY+36;
   int B=closeY+75;
   const double R=36.0;
   int logicalH=B+(int)R+21;
   g_S=Clampd(InpPanelScale/100.0,0.6,1.6);
   g_W=(int)MathCeil(W*g_S); g_H=(int)MathCeil(logicalH*g_S); g_LogicalH=logicalH;
   g_HitN=0; ArrayResize(g_px,g_W*g_H);
   string bgKey=IntegerToString(g_W)+"x"+IntegerToString(g_H);
   if(bgKey!=g_BgKey || ArraySize(g_bg)!=g_W*g_H)
   {
      ArrayInitialize(g_px,0); DrawStatic(B,R); ArrayResize(g_bg,g_W*g_H); ArrayCopy(g_bg,g_px); g_BgKey=bgKey;
   }
   else ArrayCopy(g_px,g_bg);

   uint tx=C(0xF5F7FC), tx2=C(0xC8D1E2), dim=C(0xA1AEC2);
   uint grn=C(0x42DEA0), red=C(0xFF706A), org=C(0xF1A966);
   uint sky=C(0x78D5FF), gold=C(0xFFD47A), teal=C(0x65E5D5), pur=C(0xC9A0FF);

   // New cool petrol / midnight header with a subdued amber inner rim.
   FillRR(18,18,W-18,211,30,C(0x16435A),C(0x111A31));
   StrokeRR(18,18,W-18,211,30,1.1,C(0x71D4D0,155));
   StrokeRR(21,21,W-21,208,27,0.7,C(0xF2C28E,80));
   FillRR(W/2-48,25,W/2+48,32,4,C(0x070B12),C(0x070B12));

   Txt(34,46,"NIXO 5.04",17,tx,true,TA_LEFT|TA_VCENTER);
   Txt(153,46,_Symbol+"  "+StringSubstr(EnumToString(_Period),7),11,sky,true,TA_LEFT|TA_VCENTER);
   string status=g_Stopped?"HALT":(g_DailyStopped?"DAY LOCK":(g_EntriesPaused?"ENTRY PAUSED":(cooldown?"COOLDOWN":(g_TradingMode==NIXO_MODE_MANUAL?"MANUAL":(g_TradingMode==NIXO_MODE_EXTERNAL?"EXTERNAL":(g_Running?"RUNNING":"PAUSED"))))));
   uint statusCol=(g_Stopped||g_DailyStopped)?red:(g_EntriesPaused?red:(g_TradingMode==NIXO_MODE_MANUAL?teal:(g_TradingMode==NIXO_MODE_EXTERNAL?sky:(cooldown?org:(g_Running?grn:gold)))));
   FillRR(W-137,34,W-31,58,12,WithAlpha(statusCol,48),WithAlpha(statusCol,48));
   StrokeRR(W-137,34,W-31,58,12,0.8,WithAlpha(statusCol,130));
   FillCircle(W-123,46,3.5,statusCol,statusCol);
   Txt(W-82,46,status,10,statusCol,true,TA_CENTER|TA_VCENTER);

   Txt(34,70,"ACCOUNT EQUITY",9,C(0x9BE7EE),true,TA_LEFT|TA_VCENTER);
   Txt(32,102,FmtMoney(equity,2),29,tx,true,TA_LEFT|TA_VCENTER);
   string eqPct=(plPct>=0?"+":"")+DoubleToString(plPct,2)+"%";
   FillRR(W-151,70,W-31,106,15,WithAlpha(plPct>=0?grn:red,48),WithAlpha(plPct>=0?grn:red,48));
   StrokeRR(W-151,70,W-31,106,15,0.8,WithAlpha(plPct>=0?grn:red,145));
   Txt(W-91,88,eqPct,15,plPct>=0?grn:red,true,TA_CENTER|TA_VCENTER);

   string aiCell=(g_AIState=="ONLINE"?g_AIBias+" / "+g_AIRisk:(g_AIState=="ERROR"?"AI ERROR":"OFFLINE"));
   string infoLabs[4]={"BALANCE","FLOATING P/L","AI ADVISORY","SESSION / SERVER"};
   string infoVals[4]={FmtMoney(balance,2),(flt>=0?"+":"")+FmtMoney(flt,2),aiCell,sessionTime};
   uint infoCols[4]={tx2,flt>=0?grn:red,(g_AIState=="ONLINE"?grn:(g_AIState=="ERROR"?red:org)),teal};
   for(int i=0;i<4;i++)
   {
      int x1=28+i*117, x2=x1+110;
      FillRR(x1,117,x2,145,7,C(0x102A3C),C(0x111D32));
      Txt(x1+7,125,infoLabs[i],7,dim,true,TA_LEFT|TA_VCENTER);
      Txt(x1+7,137,infoVals[i],9,infoCols[i],true,TA_LEFT|TA_VCENTER);
   }

   string labs[4]={"WIN RATE","PROFIT FACTOR","REALIZED NET P/L","OPEN POSITIONS"};
   string vals[4]={g_Trades>0?DoubleToString(wr,1)+"%":"—",
      g_Trades>0?(pf>=99.0?"∞":DoubleToString(pf,2)):"—",
      (g_NetProfit>=0?"+":"")+FmtMoney(g_NetProfit,2),IntegerToString(CountMyPositions())};
   uint cols[4]={grn,gold,g_NetProfit>=0?grn:red,sky};
   for(int i=0;i<4;i++)
   {
      int x1=28+i*117, x2=x1+110;
      FillRR(x1,151,x2,181,8,C(0x102A3C),C(0x111D32));
      StrokeRR(x1,151,x2,181,8,0.7,C(0x387184));
      Txt(x1+7,160,labs[i],7,dim,true,TA_LEFT|TA_VCENTER);
      Txt(x1+7,173,vals[i],11,cols[i],true,TA_LEFT|TA_VCENTER);
   }
   string aiDetail=(g_AIState=="ONLINE"?g_AISummary:(g_AIState=="ERROR"?g_AISummary:"AI advisory bridge: start local helper"));
   if(StringLen(aiDetail)>66) aiDetail=StringSubstr(aiDetail,0,63)+"...";
   Txt(30,191,aiDetail,7,(g_AIState=="ONLINE"?C(0xA9E8D5):C(0xB9C6D6)),false,TA_LEFT|TA_VCENTER);
   Txt(W/2,204,datePair,7,C(0xD3E5ED),true,TA_CENTER|TA_VCENTER);

   // Strategy line.
   Txt(29,226,"STRATEGY",9,gold,true,TA_LEFT|TA_VCENTER);
   FillRR(112,212,143,240,8,C(0x35415B),C(0x263249)); Txt(127,226,"‹",16,tx,true,TA_CENTER|TA_VCENTER);
   AddHit(110,210,145,242,ACT_STRATEGY_PREV);
   string stratLabel=g_PortfolioMode?"PORTFOLIO · SCALP MODELS":StratShort(g_Strategy);
   Txt(155,226,stratLabel,11,g_PortfolioMode?teal:tx,true,TA_LEFT|TA_VCENTER);
   FillRR(W-65,212,W-22,240,8,g_PortfolioMode?WithAlpha(teal,65):C(0x35415B),C(0x263249));
   Txt(W-44,226,"›",16,tx,true,TA_CENTER|TA_VCENTER);
   AddHit(W-67,210,W-20,242,ACT_STRATEGY_NEXT);
   AddHit(149,210,W-70,242,ACT_PORTFOLIO);

   // v5.04 Trading Mode selector: one exclusive entry route at a time.
   FillRR(22,249,W-22,283,10,C(0x17243A),C(0x111A2A));
   string modeLabels[3]={"MANUAL","EXTERNAL SIGNALS","STRATEGY"};
   int modeActs[3]={ACT_MODE_MANUAL,ACT_MODE_EXTERNAL,ACT_MODE_STRATEGY};
   for(int m=0;m<3;m++)
   {
      int x1=27+m*157, x2=x1+151;
      bool selected=((m==0 && g_TradingMode==NIXO_MODE_MANUAL) || (m==1 && g_TradingMode==NIXO_MODE_EXTERNAL) || (m==2 && g_TradingMode==NIXO_MODE_STRATEGY));
      uint mc=(m==0?teal:(m==1?sky:pur));
      FillRR(x1,255,x2,278,7,selected?WithAlpha(mc,85):C(0x263247),selected?WithAlpha(mc,85):C(0x263247));
      StrokeRR(x1,255,x2,278,7,0.7,selected?mc:C(0x3C4B62));
      Txt((x1+x2)/2,267,modeLabels[m],8,selected?C(0xFFFFFF):tx2,true,TA_CENTER|TA_VCENTER);
      AddHit(x1,252,x2,281,modeActs[m]);
   }

   // Independent feature switches; MANUAL is a mode, not a duplicate switch.
   FillRR(22,287,W-22,323,10,C(0x17243A),C(0x111A2A));
   string names[4]={"VOL","ORDER","HEDGE","SIGNAL LIVE"};
   bool on[4]={g_RiskRouletteEnabled,g_OrderRouletteEnabled,g_HedgeEnabled,g_SignalLiveEnabled};
   int acts[4]={ACT_RISK_ROULETTE,ACT_ORDER_ROULETTE,ACT_HEDGE,ACT_SIGNAL_LIVE};
   for(int i=0;i<4;i++)
   {
      int x1=27+i*118, x2=x1+112;
      uint led=on[i]?grn:C(0x66758B);
      FillRR(x1,292,x2,317,7,on[i]?C(0x1E3E42):C(0x263247),on[i]?C(0x1E3E42):C(0x263247));
      FillCircle(x1+10,304,2.8,led,led);
      Txt(x1+61,304,names[i],8,on[i]?C(0xE7FFF3):tx2,true,TA_CENTER|TA_VCENTER);
      AddHit(x1,289,x2,320,acts[i]);
   }

   // Action bar: Manual Desk, order sizing, and independent report export.
   FillRR(22,329,184,363,9,C(0xE8B43E),C(0xC78A23));
   StrokeRR(22,329,184,363,9,0.8,C(0xFFE08A));
   Txt(103,346,g_ManualDeskOpen?"MANUAL DESK · CLOSE":"MANUAL DESK · OPEN",8,C(0x1C2432),true,TA_CENTER|TA_VCENTER);
   AddHit(22,327,184,365,ACT_MANUAL_DESK);

   FillRR(191,329,344,363,9,C(0x172A40),C(0x101A2B));
   Txt(199,346,"ORDERS",7,dim,true,TA_LEFT|TA_VCENTER);
   FillRR(243,334,263,357,6,C(0x30394B),C(0x263249)); Txt(253,346,"−",12,tx,true,TA_CENTER|TA_VCENTER); AddHit(241,332,265,359,ACT_ORDER_MINUS);
   Txt(284,346,IntegerToString(g_OrderCount),10,gold,true,TA_CENTER|TA_VCENTER);
   FillRR(304,334,324,357,6,C(0x23504E),C(0x263249)); Txt(314,346,"+",12,tx,true,TA_CENTER|TA_VCENTER); AddHit(302,332,326,359,ACT_ORDER_PLUS);

   FillRR(351,329,W-22,363,9,C(0x273B57),C(0x17263B));
   StrokeRR(351,329,W-22,363,9,0.7,C(0x52769A));
   Txt((351+W-22)/2,346,"ADVANCED REPORT",8,sky,true,TA_CENTER|TA_VCENTER);
   AddHit(351,327,W-22,365,ACT_REPORT_EXPORT);

   Txt(28,settingsHeaderY,"QUICK SETTINGS",10,gold,true,TA_LEFT|TA_VCENTER);
   int resetX=W-166, hideX=W-88;
   FillRR(resetX,settingsHeaderY-11,resetX+68,settingsHeaderY+11,8,WithAlpha(red,45),WithAlpha(red,45));
   Txt(resetX+34,settingsHeaderY,"RESET",8,red,true,TA_CENTER|TA_VCENTER);
   AddHit(resetX-2,settingsHeaderY-13,resetX+70,settingsHeaderY+13,ACT_RESET);
   FillRR(hideX,settingsHeaderY-11,W-22,settingsHeaderY+11,8,C(0x30394B),C(0x30394B));
   Txt((hideX+W-22)/2,settingsHeaderY,g_ShowSettings?"HIDE":"SHOW",8,tx,true,TA_CENTER|TA_VCENTER);
   AddHit(hideX,settingsHeaderY-13,W-20,settingsHeaderY+13,ACT_TOGGLESET);
   if(g_ShowSettings)
   {
      int tabY=settingsTop;
      uint riskTab=g_SettingsTab==0?C(0x1C645F):C(0x18263A);
      uint exitTab=g_SettingsTab==1?C(0x8B6330):C(0x18263A);
      FillRR(22,tabY,W/2-3,tabY+24,7,riskTab,riskTab);
      FillRR(W/2+3,tabY,W-22,tabY+24,7,exitTab,exitTab);
      Txt(W/4+5,tabY+12,"RISK & SIZE",8,g_SettingsTab==0?C(0xA8FFF0):tx2,true,TA_CENTER|TA_VCENTER);
      Txt(W*3/4-5,tabY+12,"STOP LOSS & TAKE PROFIT",8,g_SettingsTab==1?C(0xFFE0A0):tx2,true,TA_CENTER|TA_VCENTER);
      AddHit(22,tabY,W/2-3,tabY+24,ACT_SETTINGS_RISK);
      AddHit(W/2+3,tabY,W-22,tabY+24,ACT_SETTINGS_EXITS);

      if(g_SettingsTab==0)
      {
         int rows[6]={0,1,3,4,10,5};
         string labels[6]={"BASE RISK","STOP DISTANCE","MAX LOT","COST / SL","MAX RISK STEP","BREAK EVEN"};
         uint valueColors[6]={sky,org,pur,teal,grn,gold};
         for(int i=0;i<6;i++)
         {
            int col=i%3, row=i/3;
            int x1=22+col*160, x2=x1+152, y1=settingsTop+31+row*34, cy=y1+14;
            int setting=rows[i];
            FillRR(x1,y1,x2,y1+29,6,C(0x17263B),C(0x101A2B));
            StrokeRR(x1,y1,x2,y1+29,6,0.6,C(0x36536A));
            Txt(x1+7,cy,labels[i],7,dim,true,TA_LEFT|TA_VCENTER);
            if(setting==5)
            {
               Txt(x2-9,cy,SettingText(setting),9,g_UseBE?grn:dim,true,TA_RIGHT|TA_VCENTER);
               AddHit(x1,y1,x2,y1+29,ACT_SET_BASE+setting*2+1);
            }
            else
            {
               Txt(x2-47,cy,SettingText(setting),9,valueColors[i],true,TA_RIGHT|TA_VCENTER);
               FillRR(x2-42,y1+5,x2-27,y1+24,5,C(0x2A394D),C(0x2A394D));
               Txt((int)MathRound(x2-34.5),cy,"-",9,tx,true,TA_CENTER|TA_VCENTER);
               FillRR(x2-23,y1+5,x2-8,y1+24,5,C(0x23504E),C(0x23504E));
               Txt((int)MathRound(x2-15.5),cy,"+",9,teal,true,TA_CENTER|TA_VCENTER);
               AddHit(x2-44,y1+3,x2-25,y1+26,ACT_SET_BASE+setting*2);
               AddHit(x2-25,y1+3,x2-6,y1+26,ACT_SET_BASE+setting*2+1);
            }
         }
      }
      else
      {
         string profileNames[4]={"SCALP","BALANCED","RUNNER","CUSTOM"};
         uint profileColors[4]={C(0x22705D),C(0x8B6330),C(0x4C5C88),C(0x1B655E)};
         for(int i=0;i<4;i++)
         {
            int x1=22+i*120, x2=x1+112, y1=settingsTop+30;
            bool selected=(i<3?g_ExitProfile==i:g_ExitProfile<0);
            uint fill=selected?profileColors[i]:C(0x1A293D);
            FillRR(x1,y1,x2,y1+25,6,fill,fill);
            StrokeRR(x1,y1,x2,y1+25,6,0.7,selected?C(0xF5D38C):C(0x38536A));
            Txt((x1+x2)/2,y1+13,profileNames[i],8,selected?C(0xFFF4D6):tx2,true,TA_CENTER|TA_VCENTER);
            AddHit(x1,y1,x2,y1+25,ACT_EXIT_PROFILE_BASE+i);
         }
         int rows[6]={1,6,7,2,8,5};
         string labels[6]={"SL · ATR","TP1 · R","TP2 · R","TP3 · R","RUNNER · ATR","BREAK EVEN"};
         uint valueColors[6]={org,sky,teal,grn,pur,gold};
         for(int i=0;i<6;i++)
         {
            int col=i%3, row=i/3;
            int x1=22+col*160, x2=x1+152, y1=settingsTop+60+row*31, cy=y1+13;
            int setting=rows[i];
            FillRR(x1,y1,x2,y1+27,6,C(0x17263B),C(0x101A2B));
            StrokeRR(x1,y1,x2,y1+27,6,0.6,C(0x36536A));
            Txt(x1+7,cy,labels[i],7,dim,true,TA_LEFT|TA_VCENTER);
            if(setting==5)
            {
               Txt(x2-9,cy,SettingText(setting),9,g_UseBE?grn:dim,true,TA_RIGHT|TA_VCENTER);
               AddHit(x1,y1,x2,y1+27,ACT_SET_BASE+setting*2+1);
               continue;
            }
            Txt(x2-47,cy,SettingText(setting),9,valueColors[i],true,TA_RIGHT|TA_VCENTER);
            FillRR(x2-42,y1+4,x2-27,y1+23,5,C(0x2A394D),C(0x2A394D));
            Txt((int)MathRound(x2-34.5),cy,"-",9,tx,true,TA_CENTER|TA_VCENTER);
            FillRR(x2-23,y1+4,x2-8,y1+23,5,C(0x23504E),C(0x23504E));
            Txt((int)MathRound(x2-15.5),cy,"+",9,teal,true,TA_CENTER|TA_VCENTER);
            AddHit(x2-44,y1+2,x2-25,y1+25,ACT_SET_BASE+setting*2);
            AddHit(x2-25,y1+2,x2-6,y1+25,ACT_SET_BASE+setting*2+1);
         }
      }
   }

   int closeY2=manualDeskY; // keep the close action directly below the main compact controls
   bool closeArmed=(g_CloseAllConfirmUntilMs>GetTickCount64());
   uint closeFill=closeArmed?C(0xC43F48):C(0x713D49);
   FillRR(22,closeY,W-22,closeY+31,9,closeFill,closeFill);
   StrokeRR(22,closeY,W-22,closeY+31,9,0.8,closeArmed?C(0xFFAAA9):C(0xB96A78));
   Txt(W/2,closeY+15,closeArmed?"CONFIRM CLOSE POSITIONS":"CLOSE NIXO POSITIONS ONLY",9,C(0xFFFFFF),true,TA_CENTER|TA_VCENTER);
   AddHit(22,closeY,W-22,closeY+31,ACT_CLOSE_ALL);

   uint startA=g_Stopped||g_DailyStopped?C(0xCE7A17):(g_Running?C(0xB63C4B):C(0x168F68));
   uint startB=g_Stopped||g_DailyStopped?C(0xA95A13):(g_Running?C(0x862D3C):C(0x0B6C50));
   FillGlow(W/2,B,29,9,g_Running?0xFF453A:0x30D158,75);
   FillCircle(W/2,B,33,C(0x101722),C(0x101722)); FillCircle(W/2,B-1,29,C(0xFFFFFF,80),C(0xFFFFFF,10));
   FillCircle(W/2,B-1,27,startA,startB);
   string runLabel=g_Stopped?"HALT":(g_DailyStopped?"LOCK":(g_Running?"STOP":"START"));
   Txt(W/2,B-2,runLabel,11,C(0xFFFFFF),true,TA_CENTER|TA_VCENTER);
   AddHit(W/2-31,B-32,W/2+31,B+30,ACT_STARTSTOP);
   Txt(24,B+31,"Nixo 5.04 · Trading Modes / Position Registry / Advanced Analytics",7,C(0x77839B),false,TA_LEFT|TA_VCENTER);
   Present();
   UpdateRRToolbar();
}

void Present()
{
   if(!ResourceCreate(UI_RES, g_px, g_W, g_H, 0, 0, g_W, COLOR_FORMAT_ARGB_NORMALIZE))
   {
      Print("Panel: ResourceCreate failed, error ", GetLastError());
      return;
   }

   if(ObjectFind(0, UI_OBJ) < 0)
   {
      ObjectCreate(0, UI_OBJ, OBJ_BITMAP_LABEL, 0, 0, 0);
      ObjectSetInteger(0, UI_OBJ, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, UI_OBJ, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, UI_OBJ, OBJPROP_XDISTANCE, InpPanelX);
      ObjectSetInteger(0, UI_OBJ, OBJPROP_YDISTANCE, InpPanelY);
      ObjectSetInteger(0, UI_OBJ, OBJPROP_BACK, false);
      ObjectSetInteger(0, UI_OBJ, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, UI_OBJ, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, UI_OBJ, OBJPROP_ZORDER, 100);
      ObjectSetString (0, UI_OBJ, OBJPROP_BMPFILE, UI_RES);
   }
   ChartRedraw();
}
//+------------------------------------------------------------------+
