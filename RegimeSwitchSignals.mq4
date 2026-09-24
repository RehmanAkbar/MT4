   //+------------------------------------------------------------------+
   //|                                    RegimeSwitchSignals_v2.mq4    |
   //|                    Regime-Switching Signal Indicator v2.1         |
   //|                                                                  |
   //|  v2.4 Fixes over v2.3:                                           |
   //|  - MR rejection: band/RSI extreme is read on the setup bar, the  |
   //|    reversal candle on the next bar. The same-bar check needed an |
   //|    opening gap (RSI only crosses up on an up-close), so MR       |
   //|    almost never fired. NOT comparable with v2.3 backtests.       |
   //|  - BO pullback: outer-band test moved to the break bar (on the   |
   //|    pullback bar it made the EMA9 retest impossible)              |
   //|  - MR EMA9 invalidator arms only after a close on the profitable |
   //|    side of EMA9; flat exits are counted apart from open trades   |
   //|  - Regime state indexed by absolute bar. MT4 doesn't shift plain |
   //|    arrays on a new bar, so v2.3 seeded every update from a stale |
   //|    bar, and bars that closed live could end up with another      |
   //|    regime (losing or gaining arrows) than after a reload. Each   |
   //|    closed bar is now evaluated once, so rejection counters no    |
   //|    longer grow on every tick                                     |
   //|  - SL/TP lines, strength labels and X marks: drawn only within   |
   //|    InpSLTP_MaxAge, cleaned whenever shown, wiped on full recalc  |
   //|  - Buy entries include the spread for the newest signal too      |
   //|  v2.3 Improvements over v2.2:                                    |
   //|  - MTF causality fix: HTF ADX/ER now read the last CLOSED HTF    |
   //|    bar. Before, history used the HTF bar CONTAINING the local    |
   //|    bar (look-ahead on recalc, repaint of last ~50 bars live).    |
   //|    History now matches live. NOT comparable with v2.2 backtests. |
   //|  - Input-change hash extended to v2.2 signal inputs              |
   //|    (RequireRejection, MinRR, MinCloseStrength, Div flags,        |
   //|    CooldownBars) so changing them forces a full recalc           |
   //|  - Outcome resolver + object cleanup throttled to once per bar   |
   //|  - NEW iCustom export buffers: 9 = signal strength (0-100),      |
   //|    10 = confirmed regime (+1 trend / -1 range / 0 none)          |
   //|  - NEW cost gate InpMinTP_SpreadMult (default 0=off): reject     |
   //|    signals whose TP distance < N x current spread                |
   //|  - Panel Vol Ratio shows the real ratio when filter is off       |
   //|  v2.1 Improvements over v2.0:                                    |
   //|  - EMA9 added (off by default): BO pullback gate, BO momentum    |
   //|    stack (EMA9>EMA20>EMA50), MR invalidator on EMA9 close-thru   |
   //|  - RSI divergence rewritten: two-pass scan, picks closest swing  |
   //|  - MTF regime: joint local+HTF decision (no stuck dead zones)    |
   //|  - SL/TP math extracted to CalcSignalSLTP() (single source)      |
   //|  - Same-bar SL+TP tie-break by relative distance from entry      |
   //|  - Strength/threshold input changes trigger automatic fullRecalc |
   //|  - MR BB penetration scoring floor lowered 0.90 -> 0.85          |
   //|  - BO emaDist score floor clamped (volatility regime stability)  |
   //|  - Volume filter default OFF; warns when ON for forex symbols    |
   //|  - Fast-path regime confirm on strong ER (>=0.85) or ADX (>=35)  |
   //|  - Rejected-signal counters surfaced in panel                    |
   //|  - g_emaTrend[] cache for EMA9-vs-EMA20 sign                     |
   //|  v2.0 Improvements over v1.36:                                   |
   //|  - Signal strength scoring (0-100) with confluence weighting     |
   //|  - Volume confirmation filter                                    |
   //|  - Efficiency Ratio for faster regime detection                  |
   //|  - RSI divergence filter for MR signals                          |
   //|  - Consolidation tightness filter for BO signals                 |
   //|  - Multi-timeframe regime confirmation                           |
   //|  - Win/loss tracking with panel display                          |
   //|  - Signal invalidation (grayed arrows on failed setups)          |
   //|  - Dead-zone decay counter                                       |
   //|  - Performance: cached panel values, smarter object cleanup      |
   //|  - Trailing TP option for BO, BB-mid target for MR              |
   //+------------------------------------------------------------------+
   #property copyright "RegimeSwitchSignals v2"
   #property version   "2.40"
   #property strict
   #property indicator_chart_window
   #property indicator_buffers 11

   //--- Arrow buffers
   #property indicator_label1  "MR Buy"
   #property indicator_type1   DRAW_ARROW
   #property indicator_color1  clrDodgerBlue
   #property indicator_width1  3

   #property indicator_label2  "MR Sell"
   #property indicator_type2   DRAW_ARROW
   #property indicator_color2  clrOrangeRed
   #property indicator_width2  3

   #property indicator_label3  "BO Buy"
   #property indicator_type3   DRAW_ARROW
   #property indicator_color3  clrLime
   #property indicator_width3  3

   #property indicator_label4  "BO Sell"
   #property indicator_type4   DRAW_ARROW
   #property indicator_color4  clrMagenta
   #property indicator_width4  3

   //--- Band buffers (visual context)
   #property indicator_label5  "BB Upper"
   #property indicator_type5   DRAW_LINE
   #property indicator_color5  clrGray
   #property indicator_style5  STYLE_DOT
   #property indicator_width5  1

   #property indicator_label6  "BB Lower"
   #property indicator_type6   DRAW_LINE
   #property indicator_color6  clrGray
   #property indicator_style6  STYLE_DOT
   #property indicator_width6  1

   #property indicator_label7  "EMA Fast"
   #property indicator_type7   DRAW_LINE
   #property indicator_color7  clrGold
   #property indicator_style7  STYLE_SOLID
   #property indicator_width7  1

   #property indicator_label8  "EMA Slow"
   #property indicator_type8   DRAW_LINE
   #property indicator_color8  clrSilver
   #property indicator_style8  STYLE_SOLID
   #property indicator_width8  1

   #property indicator_label9  "EMA9"
   #property indicator_type9   DRAW_LINE
   #property indicator_color9  clrAqua
   #property indicator_style9  STYLE_DOT
   #property indicator_width9  1

   //--- v2.3: hidden iCustom export buffers (EA/tester access, not drawn)
   #property indicator_label10 "Signal Strength"
   #property indicator_type10  DRAW_NONE
   #property indicator_label11 "Regime"
   #property indicator_type11  DRAW_NONE

   //--- Enums
   enum ENUM_REGIME { REGIME_NONE, REGIME_RANGE, REGIME_TREND };

   //+------------------------------------------------------------------+
   //| INPUT PARAMETERS                                                 |
   //+------------------------------------------------------------------+

   //--- Indicator periods
   input string   __indicators__     = "══════ Indicators ══════";
   input int      InpEMA_Fast        = 20;
   input int      InpEMA_Slow        = 50;
   input int      InpEMA9_Period     = 9;             // NEW v2.1: short-term EMA used by BO pullback / MR invalidator
input ENUM_MA_METHOD InpMA_Method       = MODE_EMA;   // MA method: SMA/EMA/SMMA/LWMA
   input int      InpATR_Period      = 14;
   input int      InpRSI_Period      = 14;
   input int      InpADX_Period      = 14;
   input int      InpBB_Period       = 20;
   input double   InpBB_Dev          = 2.0;

   //--- Regime filter
   input string   __regime__         = "══════ Regime Filter ══════";
   input double   InpADX_TrendThresh = 25.0;
   input double   InpADX_RangeThresh = 20.0;
   input double   InpBB_SqzRatio     = 0.6;
   input int      InpBW_Lookback     = 50;
   input int      InpRegimeConfirmBars = 3;

   //--- NEW: Efficiency Ratio for faster regime detection
   input string   __effRatio__       = "══════ Efficiency Ratio ══════";
   input int      InpER_Period       = 10;          // Efficiency Ratio lookback
   input double   InpER_TrendThresh  = 0.60;        // Above this = trending
   input double   InpER_RangeThresh  = 0.30;        // Below this = ranging
   input double   InpER_Weight       = 0.40;        // ER weight in blended regime (0-1, rest is ADX)
   input int      InpDeadZoneDecay   = 8;           // Max bars to persist dead-zone before forcing NONE

   //--- NEW: Multi-timeframe confirmation
   input string   __mtf__            = "══════ Multi-TF Confirm ══════";
   input bool     InpUseMTF          = true;         // Enable higher-TF regime confirmation
   input int      InpHTF_Period      = 0;            // Higher TF (0=auto: next standard TF)

   //--- Mean-reversion module
   input string   __mr__             = "══════ Mean-Reversion ══════";
   input double   InpMR_RSI_OB       = 70.0;
   input double   InpMR_RSI_OS       = 30.0;
   input double   InpMR_BB_Touch     = 0.95;
   input double   InpMR_SL_ATR       = 1.5;
   input double   InpMR_TP_ATR       = 1.5;
   input bool     InpMR_TP_BBMid     = true;         // NEW: Use BB midline as MR TP (overrides ATR TP)
   input bool     InpMR_RequireRejection = true;     // v2.2: require reversal candle at band extreme (avoid catching the knife)
   input double   InpMR_MinRR            = 0.0;      // v2.2: min reward:risk for MR (0=off; enable with a tighter SL)

   //--- NEW: RSI Divergence filter for MR
   input string   __divergence__     = "══════ RSI Divergence ══════";
   input bool     InpMR_RequireDiv   = false;        // Require RSI divergence for MR (strict mode)
   input bool     InpMR_DivBoost     = true;         // Boost signal strength when divergence present
   input int      InpDiv_Lookback    = 15;           // Bars to look back for divergence

   //--- Breakout module
   input string   __bo__             = "══════ Breakout ══════";
   input int      InpBO_LookbackBars = 20;
   input double   InpBO_Momentum_RSI = 55.0;
   input double   InpBO_SL_ATR       = 2.0;
   input double   InpBO_TP_ATR       = 3.0;
   input double   InpBO_BreakBuffer  = 0.2;
   input bool     InpBO_SL_Structure = true;
   input double   InpBO_StructPad    = 0.3;
   input double   InpBO_SL_MaxATR    = 4.0;

   //--- NEW: Consolidation tightness filter
   input double   InpBO_MaxRangeATR  = 3.0;         // Max consolidation range in ATR (skip sloppy breakouts)
   input double   InpBO_MinRangeATR  = 0.5;         // Min consolidation range in ATR (skip noise)
   input double   InpBO_MinCloseStrength = 0.55;     // v2.2: min close position in breakout bar range (anti-fakeout, 0=off)

   //--- NEW v2.1: EMA9-based gates
   input string   __ema9__               = "══════ EMA9 Gates ══════";
   input bool     InpBO_RequireEMA9Stack = false;   // Require EMA9>EMA20>EMA50 (inverse for sell) for BO entry
   input bool     InpBO_RequireEMA9Pullback = false;// Require pullback to EMA9 within N bars after range break
   input int      InpBO_PullbackMaxBars  = 3;       // Bars allowed between break and pullback fire
   input double   InpBO_PullbackTolATR   = 0.25;    // Distance to EMA9 (ATR units) considered "pulled back"
   input bool     InpMR_UseEMA9Invalidator = false; // Resolve MR as exit when price closes thru EMA9 first

   //--- NEW: Volume filter
   input string   __volume__         = "══════ Volume Filter ══════";
   input bool     InpUseVolumeFilter = false;        // Enable volume confirmation (off by default — tick-volume on forex is broker-dependent)
   input int      InpVol_AvgPeriod   = 20;           // Volume averaging period
   input double   InpVol_BO_MinRatio = 1.3;          // Min volume ratio for BO signals
   input double   InpVol_MR_MinRatio = 0.8;          // Min volume ratio for MR signals (lower OK)

   //--- NEW: Signal strength
   input string   __strength__       = "══════ Signal Strength ══════";
   input int      InpMinStrength     = 40;           // Minimum signal strength to fire (0-100)
   input bool     InpShowStrength    = true;         // Show strength value on chart

   //--- Signal quality
   input string   __quality__        = "══════ Signal Quality ══════";
   input int      InpCooldownBars    = 5;
   input bool     InpRequireRSICross = true;

   //--- NEW: Win/Loss tracking
   input string   __winloss__        = "══════ Win/Loss Tracker ══════";
   input bool     InpTrackWinLoss    = true;         // Track historical SL/TP outcomes
   input int      InpWL_MaxLookback  = 200;          // Max bars to look back for outcome resolution

   //--- Display
   input string   __display__        = "══════ Display ══════";
   input bool     InpShowBands       = true;
   input bool     InpShowEMAs        = true;
   input bool     InpShowEMA9        = false;        // NEW v2.1: plot EMA9 (off by default to keep chart clean)
   input bool     InpShowPanel       = true;
   input bool     InpShowRegimeBG    = true;
   input int      InpRegimeBG_MaxBars= 300;
   input bool     InpShowSLTP        = true;
   input int      InpSLTP_MaxAge     = 50;
   input double   InpArrowOffset_ATR = 0.5;
   input int      InpSignalCountBars = 500;
   input bool     InpEnableAlerts    = true;
   input bool     InpEnablePush      = true;
   input bool     InpAlertEMACross   = true;          // Alert on Fast/Slow EMA crossover
   input string   InpInstanceSuffix  = "";

   //--- NEW: Signal invalidation
   input bool     InpInvalidateSignals = true;       // Gray out arrows that hit SL
   input color    InpInvalidColor      = clrDarkGray; // Color for invalidated signals

   //--- Chart appearance
   input string   __chart__           = "══════ Chart Style ══════";
   input bool     InpApplyChartStyle  = true;
   input bool     InpRemoveGrid       = true;
   input color    InpBullCandleColor  = C'0,190,130';
   input color    InpBearCandleColor  = C'220,60,80';
   input color    InpBullWickColor    = C'0,190,130';
   input color    InpBearWickColor    = C'220,60,80';
   input color    InpChartBG          = C'18,22,30';
   input color    InpChartFG          = C'140,150,170';

   //--- Session filter
   input string   __session__        = "══════ Session Filter ══════";
   input bool     InpUseSessionFilter = false;
   input int      InpSessionStartHour = 7;
   input int      InpSessionEndHour   = 20;

   //--- v2.3: Cost-aware gate (kept LAST so positional iCustom callers stay valid)
   input string   __cost__            = "══════ Cost Gate ══════";
   input double   InpMinTP_SpreadMult = 0.0;         // Reject signals with TP distance < N x current spread (0=off). Note: uses the spread at calc time, so historical arrows are an approximation on live charts; exact in the tester (fixed spread).

   //+------------------------------------------------------------------+
   //| BUFFERS                                                          |
   //+------------------------------------------------------------------+
   double g_mrBuy[];
   double g_mrSell[];
   double g_boBuy[];
   double g_boSell[];
   double g_bbUpper[];
   double g_bbLower[];
   double g_emaFast[];
   double g_emaSlow[];
   double g_ema9[];                  // NEW v2.1: EMA9 plot buffer
   double g_strengthBuf[];           // v2.3: export — signal strength 0-100 (0 = none)
   double g_regimeBuf[];             // v2.3: export — +1 trend, -1 range, 0 none
   int    g_emaTrend[];              // NEW v2.1: per-bar sign of (EMA9 - EMA20): +1/-1/0

   //--- Rejected-signal counters (v2.1) — last full recalc only, panel-displayed
   int g_rejRegime  = 0;             // signal direction was 0 due to regime mismatch (implicit, never counted)
   int g_rejVolume  = 0;
   int g_rejDiv     = 0;
   int g_rejStrength= 0;
   int g_rejCooldown= 0;
   int g_rejPullback= 0;
   int g_rejStack   = 0;
   int g_rejCost    = 0;             // v2.3: TP distance below spread multiple

   //--- v2.3: per-bar maintenance throttle (resolver + object cleanup)
   datetime g_lastMaintBar = 0;

   //--- Panel object prefix
   string g_prefix = "RSSIG2_";

   //--- Panel dimensions
   int g_panelX      = 12;
   int g_panelY      = 22;
   int g_panelWidth  = 260;

   //--- Bandwidth cache
   double g_bwCache[];
   bool   g_bwCacheReady = false;

   //--- Regime persistence
   ENUM_REGIME g_lastRegime[];
   ENUM_REGIME g_rawRegime[];
   int         g_regimeStreak[];
   int         g_deadZoneCount[];      // NEW: dead-zone decay counter

   //--- Signal strength cache (per bar)
   double g_signalStrength[];

   //--- Win/Loss tracking
   int g_wins   = 0;
   int g_losses = 0;
   int g_pending = 0;
   int g_flat   = 0;                 // v2.4: MR trades closed flat by the EMA9 invalidator

   //--- Signal outcome tracking: +1=win, -1=loss, 0=pending/none
   int g_signalOutcome[];

   //--- Cached panel values (avoid redundant iXXX calls)
   double g_panelADX  = 0;
   double g_panelRSI  = 0;
   double g_panelATR  = 0;
   double g_panelBBUp = 0;
   double g_panelBBLo = 0;
   double g_panelBBMid= 0;
   double g_panelCls  = 0;
   double g_panelER   = 0;
   bool   g_panelCacheValid = false;

   //--- Panel throttle
   datetime g_lastPanelBar = 0;

   //--- Previous rates_total
   int g_prevRatesTotal = 0;

   //--- GlobalVariable prefix
   string g_gvPrefix = "";

   //--- Object creation time tracker for efficient cleanup
   datetime g_sltpTimes[];
   int      g_sltpCount = 0;

   //--- Higher timeframe
   int g_htfPeriod = 0;

   //--- v2.4: the per-bar state arrays above (g_bwCache, g_rawRegime, ...) are
   //    indexed by ABSOLUTE bar, 0 = oldest (see AbsIdx). MT4 shifts indicator
   //    buffers when a new bar opens but not plain arrays, so the old
   //    shift-indexed state went stale.
   int      g_absTotal    = 0;       // rates_total of the current OnCalculate call
   datetime g_absBaseTime = 0;       // open time of the oldest bar (absolute index 0)

   //+------------------------------------------------------------------+
   //| INIT                                                             |
   //+------------------------------------------------------------------+
   int OnInit()
   {
      string instID = IntegerToString(ChartID()) + "_" + Symbol() + "_" + IntegerToString(Period());
      if(InpInstanceSuffix != "")
         instID += "_" + InpInstanceSuffix;
      g_prefix   = "RSSIG2_" + instID + "_";
      g_gvPrefix = "RSSIG2_" + instID + "_";

      //--- Resolve higher timeframe
      g_htfPeriod = InpHTF_Period;
      if(g_htfPeriod <= 0)
         g_htfPeriod = GetNextHTF(Period());

      //--- Map buffers
      SetIndexBuffer(0, g_mrBuy);
      SetIndexBuffer(1, g_mrSell);
      SetIndexBuffer(2, g_boBuy);
      SetIndexBuffer(3, g_boSell);
      SetIndexBuffer(4, g_bbUpper);
      SetIndexBuffer(5, g_bbLower);
      SetIndexBuffer(6, g_emaFast);
      SetIndexBuffer(7, g_emaSlow);
      SetIndexBuffer(8, g_ema9);
      SetIndexBuffer(9, g_strengthBuf);   // v2.3: hidden exports
      SetIndexBuffer(10, g_regimeBuf);

      SetIndexArrow(0, 233);
      SetIndexArrow(1, 234);
      SetIndexArrow(2, 241);
      SetIndexArrow(3, 242);

      for(int i = 0; i < 9; i++)
         SetIndexEmptyValue(i, EMPTY_VALUE);

      //--- v2.3: export buffers use 0 as "empty" so iCustom reads are clean doubles
      SetIndexStyle(9,  DRAW_NONE);
      SetIndexStyle(10, DRAW_NONE);
      SetIndexEmptyValue(9,  0.0);
      SetIndexEmptyValue(10, 0.0);

      if(!InpShowBands)  { SetIndexStyle(4, DRAW_NONE); SetIndexStyle(5, DRAW_NONE); }
      if(!InpShowEMAs)   { SetIndexStyle(6, DRAW_NONE); SetIndexStyle(7, DRAW_NONE); }
      if(!InpShowEMA9)   { SetIndexStyle(8, DRAW_NONE); }

      //--- v2.1: warn if volume filter is on for likely forex symbols (tick-volume is unreliable)
      if(InpUseVolumeFilter)
      {
         string sym = Symbol();
         bool likelyForex = (StringLen(sym) >= 6 &&
                             StringFind(sym, "XAU") < 0 && StringFind(sym, "XAG") < 0 &&
                             StringFind(sym, "OIL") < 0 && StringFind(sym, "BTC") < 0 &&
                             StringFind(sym, "ETH") < 0 && StringFind(sym, "US30") < 0 &&
                             StringFind(sym, "NAS") < 0 && StringFind(sym, "SPX") < 0 &&
                             StringFind(sym, "GER") < 0 && StringFind(sym, "UK")  < 0);
         if(likelyForex)
            Print("[RegimeSwitch v2.1] WARNING: Volume filter is enabled on ", sym,
                  ". Tick-volume on forex is broker-dependent and may distort signal scoring. Consider InpUseVolumeFilter=false.");
      }

      if(InpApplyChartStyle)
      {
         SaveOriginalChartColors();
         ApplyChartStyle();
      }

      g_bwCacheReady   = false;
      g_prevRatesTotal = 0;
      g_panelCacheValid = false;
      g_wins   = 0;
      g_losses = 0;
      g_pending = 0;
      g_flat   = 0;
      g_sltpCount = 0;
      g_rejRegime = 0; g_rejVolume = 0; g_rejDiv = 0; g_rejStrength = 0;
      g_rejCooldown = 0; g_rejPullback = 0; g_rejStack = 0; g_rejCost = 0;
      g_lastMaintBar = 0;

      IndicatorShortName("RegimeSwitch Signals v2.4");
      return(INIT_SUCCEEDED);
   }

   //+------------------------------------------------------------------+
   //| GET NEXT STANDARD HIGHER TIMEFRAME                               |
   //+------------------------------------------------------------------+
   int GetNextHTF(int currentTF)
   {
      if(currentTF <= PERIOD_M1)  return PERIOD_M5;
      if(currentTF <= PERIOD_M5)  return PERIOD_M15;
      if(currentTF <= PERIOD_M15) return PERIOD_H1;
      if(currentTF <= PERIOD_M30) return PERIOD_H1;
      if(currentTF <= PERIOD_H1)  return PERIOD_H4;
      if(currentTF <= PERIOD_H4)  return PERIOD_D1;
      if(currentTF <= PERIOD_D1)  return PERIOD_W1;
      return PERIOD_MN1;
   }

   //+------------------------------------------------------------------+
   //| CHART COLOR MANAGEMENT (same as v1.36)                           |
   //+------------------------------------------------------------------+
   void SaveOriginalChartColors()
   {
      string base = g_gvPrefix + "orig_";
      if(GlobalVariableCheck(base + "saved")) return;
      GlobalVariableSet(base + "grid",       (double)ChartGetInteger(0, CHART_SHOW_GRID));
      GlobalVariableSet(base + "bull_candle",(double)ChartGetInteger(0, CHART_COLOR_CANDLE_BULL));
      GlobalVariableSet(base + "bear_candle",(double)ChartGetInteger(0, CHART_COLOR_CANDLE_BEAR));
      GlobalVariableSet(base + "chart_up",   (double)ChartGetInteger(0, CHART_COLOR_CHART_UP));
      GlobalVariableSet(base + "chart_down", (double)ChartGetInteger(0, CHART_COLOR_CHART_DOWN));
      GlobalVariableSet(base + "bg",         (double)ChartGetInteger(0, CHART_COLOR_BACKGROUND));
      GlobalVariableSet(base + "fg",         (double)ChartGetInteger(0, CHART_COLOR_FOREGROUND));
      GlobalVariableSet(base + "mode",       (double)ChartGetInteger(0, CHART_MODE));
      GlobalVariableSet(base + "saved",      1.0);
   }

   void RestoreOriginalChartColors()
   {
      string base = g_gvPrefix + "orig_";
      if(!GlobalVariableCheck(base + "saved")) return;
      ChartSetInteger(0, CHART_SHOW_GRID,         (long)GlobalVariableGet(base + "grid"));
      ChartSetInteger(0, CHART_COLOR_CANDLE_BULL,  (long)GlobalVariableGet(base + "bull_candle"));
      ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR,  (long)GlobalVariableGet(base + "bear_candle"));
      ChartSetInteger(0, CHART_COLOR_CHART_UP,     (long)GlobalVariableGet(base + "chart_up"));
      ChartSetInteger(0, CHART_COLOR_CHART_DOWN,   (long)GlobalVariableGet(base + "chart_down"));
      ChartSetInteger(0, CHART_COLOR_BACKGROUND,   (long)GlobalVariableGet(base + "bg"));
      ChartSetInteger(0, CHART_COLOR_FOREGROUND,   (long)GlobalVariableGet(base + "fg"));
      ChartSetInteger(0, CHART_MODE,               (long)GlobalVariableGet(base + "mode"));
      ChartRedraw(0);
   }

   void DeleteOriginalChartColorGVs()
   {
      string base = g_gvPrefix + "orig_";
      string keys[] = {"grid","bull_candle","bear_candle","chart_up","chart_down","bg","fg","mode","saved"};
      for(int i = 0; i < ArraySize(keys); i++)
         GlobalVariableDel(base + keys[i]);
   }

   void ApplyChartStyle()
   {
      if(InpRemoveGrid) ChartSetInteger(0, CHART_SHOW_GRID, false);
      ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, InpBullCandleColor);
      ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, InpBearCandleColor);
      ChartSetInteger(0, CHART_COLOR_CHART_UP,    InpBullWickColor);
      ChartSetInteger(0, CHART_COLOR_CHART_DOWN,  InpBearWickColor);
      ChartSetInteger(0, CHART_COLOR_BACKGROUND,  InpChartBG);
      ChartSetInteger(0, CHART_COLOR_FOREGROUND,  InpChartFG);
      ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
      ChartRedraw(0);
   }

   //+------------------------------------------------------------------+
   //| DEINIT                                                           |
   //+------------------------------------------------------------------+
   void OnDeinit(const int reason)
   {
      ObjectsDeleteAll(0, g_prefix);
      Comment("");

      if(InpApplyChartStyle)
         RestoreOriginalChartColors();

      if(reason != REASON_CHARTCHANGE && reason != REASON_PARAMETERS && reason != REASON_RECOMPILE)
      {
         DeleteOriginalChartColorGVs();
         GlobalVariableDel(g_gvPrefix + "lastAlert");
         GlobalVariableDel(g_gvPrefix + "lastEMACross");
      }
   }

   //+------------------------------------------------------------------+
   //| EFFICIENCY RATIO (Kaufman-style: direction / volatility)         |
   //| Returns 0.0 (choppy) to 1.0 (perfectly trending)                |
   //+------------------------------------------------------------------+
   double CalcEfficiencyRatio(int shift, int period)
   {
      if(shift + period >= Bars) return 0.5;

      double direction = MathAbs(iClose(Symbol(), 0, shift) - iClose(Symbol(), 0, shift + period));
      double volatility = 0;
      for(int j = shift; j < shift + period; j++)
         volatility += MathAbs(iClose(Symbol(), 0, j) - iClose(Symbol(), 0, j + 1));

      if(volatility < _Point) return 0.5;
      return direction / volatility;
   }

   //+------------------------------------------------------------------+
   //| HIGHER-TIMEFRAME EFFICIENCY RATIO                                |
   //+------------------------------------------------------------------+
   double CalcHTF_ER(int shift)
   {
      if(!InpUseMTF || g_htfPeriod <= Period()) return 0.5;

      datetime barTime = iTime(Symbol(), 0, shift);
      int htfShift = iBarShift(Symbol(), g_htfPeriod, barTime, false);
      if(htfShift < 0) return 0.5;
      //--- v2.3 causality: the HTF bar CONTAINING this local bar is still forming
      //    at this point in time — using it is look-ahead on recalc and repaints
      //    live. Read the last CLOSED HTF bar instead (history == live).
      htfShift += 1;
      if(htfShift + InpER_Period >= iBars(Symbol(), g_htfPeriod))
         return 0.5;

      double direction = MathAbs(iClose(Symbol(), g_htfPeriod, htfShift) -
                                 iClose(Symbol(), g_htfPeriod, htfShift + InpER_Period));
      double volatility = 0;
      for(int j = htfShift; j < htfShift + InpER_Period; j++)
         volatility += MathAbs(iClose(Symbol(), g_htfPeriod, j) - iClose(Symbol(), g_htfPeriod, j + 1));

      if(volatility < _Point) return 0.5;
      return direction / volatility;
   }

   //+------------------------------------------------------------------+
   //| HTF ADX (for MTF regime confirmation)                            |
   //+------------------------------------------------------------------+
   double CalcHTF_ADX(int shift)
   {
      if(!InpUseMTF || g_htfPeriod <= Period()) return 0;
      datetime barTime = iTime(Symbol(), 0, shift);
      int htfShift = iBarShift(Symbol(), g_htfPeriod, barTime, false);
      if(htfShift < 0) return 0;
      //--- v2.3 causality: last CLOSED HTF bar (see CalcHTF_ER)
      return iADX(Symbol(), g_htfPeriod, InpADX_Period, PRICE_CLOSE, MODE_MAIN, htfShift + 1);
   }

   //+------------------------------------------------------------------+
   //| VOLUME RATIO: current tick_volume vs N-bar average               |
   //+------------------------------------------------------------------+
   double GetVolumeRatio(int shift, bool ignoreFilter=false)
   {
      if(!InpUseVolumeFilter && !ignoreFilter) return 999.0;  // pass-through for signal gates
      if(shift + InpVol_AvgPeriod >= Bars) return 1.0;

      double current = (double)iVolume(Symbol(), 0, shift);
      double sum = 0;
      for(int j = shift + 1; j <= shift + InpVol_AvgPeriod; j++)
         sum += (double)iVolume(Symbol(), 0, j);

      double avg = sum / InpVol_AvgPeriod;
      if(avg < 1.0) return 1.0;
      return current / avg;
   }

   //+------------------------------------------------------------------+
   //| RSI DIVERGENCE DETECTION (v2.1: two-pass closest-swing scan)     |
   //| Returns: +1 bullish div, -1 bearish div, 0 none                  |
   //|                                                                  |
   //| Pass 1: collect all 3-bar pivot swings in the lookback window    |
   //|         (skipping the 2 nearest bars to avoid evaluating an      |
   //|          unconfirmed pivot at the signal bar).                   |
   //| Pass 2: pick the *closest* prior swing whose price extended      |
   //|         further than the current swing in the same direction —   |
   //|         that is the only valid divergence anchor.                |
   //+------------------------------------------------------------------+
   int DetectRSIDivergence(int shift, int lookback)
   {
      double priceLowCur  = iLow (Symbol(), 0, shift);
      double priceHighCur = iHigh(Symbol(), 0, shift);
      double rsiCur       = iRSI (Symbol(), 0, InpRSI_Period, PRICE_CLOSE, shift);

      int    bestBullIdx = -1; double bestBullLow  = 0; double bestBullRSI = 0;
      int    bestBearIdx = -1; double bestBearHigh = 0; double bestBearRSI = 0;

      int jStart = shift + 3;     // skip 2 nearest bars: pivot at j needs j-1 and j+1
      int jEnd   = shift + lookback;
      if(jEnd >= Bars - 1) jEnd = Bars - 2;

      for(int j = jStart; j <= jEnd; j++)
      {
         double lo = iLow (Symbol(), 0, j);
         double hi = iHigh(Symbol(), 0, j);

         bool isPivotLow  = (lo < iLow (Symbol(), 0, j - 1) && lo < iLow (Symbol(), 0, j + 1));
         bool isPivotHigh = (hi > iHigh(Symbol(), 0, j - 1) && hi > iHigh(Symbol(), 0, j + 1));

         if(!isPivotLow && !isPivotHigh) continue;

         double r = iRSI(Symbol(), 0, InpRSI_Period, PRICE_CLOSE, j);

         // Bullish anchor: the prior low must be ABOVE current low (current makes a lower low),
         // and the prior RSI must be BELOW current RSI (RSI makes a higher low).
         if(isPivotLow && bestBullIdx < 0 && lo > priceLowCur && r < rsiCur)
         {
            bestBullIdx = j; bestBullLow = lo; bestBullRSI = r;
         }

         // Bearish anchor: the prior high must be BELOW current high (current makes a higher high),
         // and the prior RSI must be ABOVE current RSI (RSI makes a lower high).
         if(isPivotHigh && bestBearIdx < 0 && hi < priceHighCur && r > rsiCur)
         {
            bestBearIdx = j; bestBearHigh = hi; bestBearRSI = r;
         }

         if(bestBullIdx >= 0 && bestBearIdx >= 0) break; // closest of each found
      }

      if(bestBullIdx >= 0) return +1;
      if(bestBearIdx >= 0) return -1;
      return 0;
   }

   //+------------------------------------------------------------------+
   //| CONSOLIDATION TIGHTNESS (range / ATR ratio)                      |
   //+------------------------------------------------------------------+
   double ConsolidationTightness(int shift, int lookback, double atr)
   {
      if(atr < _Point) return 999.0;
      int startBar = shift + 1;
      double hiHigh = iHigh(Symbol(), 0, iHighest(Symbol(), 0, MODE_HIGH, lookback, startBar));
      double loLow  = iLow(Symbol(), 0, iLowest(Symbol(), 0, MODE_LOW, lookback, startBar));
      return (hiHigh - loLow) / atr;
   }

   //+------------------------------------------------------------------+
   //| SIGNAL STRENGTH SCORING                                          |
   //| Returns 0-100 based on confluence count and quality              |
   //+------------------------------------------------------------------+
   double CalcMRStrength(double cls, double rsi, double bbUp, double bbLo,
                        double atr, double volRatio, int divSignal, double er)
   {
      double score = 0;
      double bbRange = bbUp - bbLo;
      if(bbRange <= 0) return 0;
      double bbPos = (cls - bbLo) / bbRange;

      // 1. BB penetration depth (0-25 pts)
      // v2.1: floor lowered 0.90 -> 0.85 so borderline-but-valid touches still score above zero.
      double bbExtreme = (bbPos >= 0.5) ? bbPos : (1.0 - bbPos);
      score += MathMax(0, MathMin(25, (bbExtreme - 0.85) / 0.15 * 25.0));

      // 2. RSI extremity (0-25 pts)
      double rsiExtreme = 0;
      if(rsi >= InpMR_RSI_OB) rsiExtreme = (rsi - InpMR_RSI_OB) / (100.0 - InpMR_RSI_OB);
      if(rsi <= InpMR_RSI_OS) rsiExtreme = (InpMR_RSI_OS - rsi) / InpMR_RSI_OS;
      score += MathMin(25, rsiExtreme * 25.0);

      // 3. Volume confirmation (0-15 pts)
      if(InpUseVolumeFilter && volRatio >= InpVol_MR_MinRatio)
         score += MathMin(15, (volRatio - 0.5) / 1.5 * 15.0);
      else if(!InpUseVolumeFilter)
         score += 10;  // neutral if disabled

      // 4. RSI divergence (0-20 pts)
      if(divSignal != 0 && InpMR_DivBoost)
         score += 20;

      // 5. Low ER = good for mean reversion (0-15 pts)
      score += MathMin(15, (1.0 - er) * 15.0);

      return MathMin(100, MathMax(0, score));
   }

   double CalcBOStrength(double cls, double rsi, double atr, double emaF, double emaS,
                        double diP, double diM, double adx, double volRatio,
                        double er, double tightness, double hiHigh, double loLow)
   {
      double score = 0;

      // 1. ADX strength (0-20 pts)
      score += MathMin(20, (adx - InpADX_RangeThresh) / (50.0 - InpADX_RangeThresh) * 20.0);

      // 2. EMA alignment (0-15 pts) — v2.1: ensure regime-transition entries don't get nuked
      //    when EMAs are momentarily tight. Floor at 0.5 ATR contribution so the score
      //    can't fall below ~7.5 here unless EMAs are flat-flat on absurdly low ATR.
      double emaDist = MathAbs(emaF - emaS) / atr;
      score += MathMin(15, MathMax(0.5, emaDist) * 15.0);

      // 3. DI spread (0-15 pts)
      double diSpread = MathAbs(diP - diM);
      score += MathMin(15, diSpread / 20.0 * 15.0);

      // 4. Volume surge (0-20 pts)
      if(InpUseVolumeFilter && volRatio >= InpVol_BO_MinRatio)
         score += MathMin(20, (volRatio - 1.0) / 2.0 * 20.0);
      else if(!InpUseVolumeFilter)
         score += 12;

      // 5. High ER = good for breakout (0-15 pts)
      score += MathMin(15, er * 15.0);

      // 6. Consolidation tightness bonus (0-15 pts)
      // Tighter consolidation = better breakout quality
      if(tightness >= InpBO_MinRangeATR && tightness <= InpBO_MaxRangeATR)
      {
         double optimal = (InpBO_MinRangeATR + InpBO_MaxRangeATR) / 2.0;
         double dist = MathAbs(tightness - optimal) / (InpBO_MaxRangeATR - InpBO_MinRangeATR);
         score += MathMin(15, (1.0 - dist) * 15.0);
      }

      return MathMin(100, MathMax(0, score));
   }

   //+------------------------------------------------------------------+
   //| v2.4: SHIFT -> ABSOLUTE BAR INDEX for the per-bar state arrays   |
   //|   0 = oldest bar. A bar keeps its index as new bars arrive; the  |
   //|   previous (older) bar of absolute index a is a - 1.             |
   //+------------------------------------------------------------------+
   int AbsIdx(int shift)
   {
      return g_absTotal - 1 - shift;
   }

   //--- v2.4: neutral regime state for a bar the regime logic skips, so the
   //    next bar sees the same state live as after a reload
   void ResetBarState(int a)
   {
      g_rawRegime[a]     = REGIME_NONE;
      g_lastRegime[a]    = REGIME_NONE;
      g_regimeStreak[a]  = 0;
      g_deadZoneCount[a] = 0;
   }

   //--- v2.4: SL/TP lines, strength labels and X marks are drawn only inside
   //    the window CleanupSLTP() keeps (InpSLTP_MaxAge <= 0 keeps everything)
   bool WithinObjAge(int shift)
   {
      return (InpSLTP_MaxAge <= 0 || shift <= InpSLTP_MaxAge);
   }

   //--- v2.4: drop every per-bar object; a full recalc redraws what still applies
   void DeletePerBarObjects()
   {
      ObjectsDeleteAll(0, g_prefix + "SL_");
      ObjectsDeleteAll(0, g_prefix + "TP_");
      ObjectsDeleteAll(0, g_prefix + "STR_");
      ObjectsDeleteAll(0, g_prefix + "INV_");
      ObjectsDeleteAll(0, g_prefix + "BG_");
   }

   //+------------------------------------------------------------------+
   //| CALCULATE                                                        |
   //+------------------------------------------------------------------+
   int OnCalculate(const int rates_total,
                  const int prev_calculated,
                  const datetime &time[],
                  const double &open[],
                  const double &high[],
                  const double &low[],
                  const double &close[],
                  const long &tick_volume[],
                  const long &volume[],
                  const int &spread[])
   {
      int prevCalc = prev_calculated;
      if(prevCalc > rates_total) prevCalc = 0;

      //--- v2.1: invalidate cache when scoring/threshold inputs have changed since last init.
      //    Force prevCalc=0 so the rest of the routine treats this as a fresh load.
      double inpHash = (double)InpMinStrength * 1.0
                     + InpMR_BB_Touch        * 100.0
                     + InpMR_RSI_OB          * 1000.0
                     + InpMR_RSI_OS          * 10000.0
                     + InpBO_Momentum_RSI    * 100000.0
                     + InpBO_BreakBuffer     * 1000000.0
                     + (InpRequireRSICross ? 1 : 0) * 10000000.0
                     + (InpUseVolumeFilter ? 1 : 0) * 100000000.0
                     + (InpBO_RequireEMA9Stack ? 1 : 0) * 200000000.0
                     + (InpBO_RequireEMA9Pullback ? 1 : 0) * 400000000.0
                     // v2.3: v2.2 signal inputs were missing from the hash, so changing
                     // them did not force a recalc and stale arrows survived.
                     + (InpMR_RequireRejection ? 1 : 0) * 800000000.0
                     + (InpMR_RequireDiv ? 1 : 0)       * 1600000000.0
                     + (InpMR_DivBoost ? 1 : 0)         * 3200000000.0
                     + InpMR_MinRR                      * 6400000000.0
                     + InpBO_MinCloseStrength           * 12800000000.0
                     + InpCooldownBars                  * 25600000000.0
                     + InpMinTP_SpreadMult              * 51200000000.0;
      string hashKey = g_gvPrefix + "inpHash";
      double prevHash = GlobalVariableCheck(hashKey) ? GlobalVariableGet(hashKey) : 0.0;
      if(MathAbs(prevHash - inpHash) > 1e-9)
      {
         prevCalc = 0;
         GlobalVariableSet(hashKey, inpHash);
      }

      //--- Warmup
      int maxIndPeriod = MathMax(InpEMA_Slow,
                        MathMax(InpATR_Period,
                        MathMax(InpRSI_Period + 1,
                        MathMax(InpADX_Period * 2,
                        MathMax(InpBB_Period,
                              InpER_Period + 1)))));
      int warmup = MathMax(maxIndPeriod,
                           MathMax(InpBO_LookbackBars + 1,
                           MathMax(InpBB_Period + InpBW_Lookback,
                                 InpDiv_Lookback + 2)))
                  + 1;
      if(rates_total < warmup) return(0);

      //--- v2.4: absolute indices stay valid only while bars are appended. If bars
      //    were prepended or trimmed at the old end, recalc everything.
      datetime oldestTime = iTime(Symbol(), 0, rates_total - 1);
      if(prevCalc > 0 && (oldestTime != g_absBaseTime || ArraySize(g_bwCache) > rates_total))
         prevCalc = 0;
      g_absBaseTime = oldestTime;
      g_absTotal    = rates_total;

      //--- v2.4: incremental calls evaluate only newly closed bars (0 on an intrabar
      //    tick). Re-evaluating bars 1..51 on every call existed to refresh the
      //    shift-indexed state; it also re-counted rejections on every tick.
      int limit;
      if(prevCalc == 0)
         limit = rates_total - warmup + 1;
      else
         limit = MathMin(rates_total - prevCalc, rates_total - warmup + 1);

      //--- Cache management
      bool fullRecalc = (prevCalc == 0);

      if(fullRecalc)
      {
         ArrayInitialize(g_mrBuy,   EMPTY_VALUE);
         ArrayInitialize(g_mrSell,  EMPTY_VALUE);
         ArrayInitialize(g_boBuy,   EMPTY_VALUE);
         ArrayInitialize(g_boSell,  EMPTY_VALUE);
         ArrayInitialize(g_bbUpper, EMPTY_VALUE);
         ArrayInitialize(g_bbLower, EMPTY_VALUE);
         ArrayInitialize(g_emaFast, EMPTY_VALUE);
         ArrayInitialize(g_emaSlow, EMPTY_VALUE);
         ArrayInitialize(g_ema9,    EMPTY_VALUE);
         ArrayInitialize(g_strengthBuf, 0.0);
         ArrayInitialize(g_regimeBuf,   0.0);

         ArrayResize(g_bwCache, rates_total);
         ArrayInitialize(g_bwCache, 0.0);
         g_bwCacheReady = false;

         ArrayResize(g_lastRegime, rates_total);
         ArrayResize(g_rawRegime, rates_total);
         ArrayResize(g_regimeStreak, rates_total);
         ArrayResize(g_deadZoneCount, rates_total);
         ArrayResize(g_signalStrength, rates_total);
         ArrayResize(g_signalOutcome, rates_total);
         ArrayResize(g_emaTrend, rates_total);
         for(int r = 0; r < rates_total; r++)
         {
            g_lastRegime[r]    = REGIME_NONE;
            g_rawRegime[r]     = REGIME_NONE;
            g_regimeStreak[r]  = 0;
            g_deadZoneCount[r] = 0;
            g_signalStrength[r]= 0;
            g_signalOutcome[r] = 0;
            g_emaTrend[r]      = 0;
         }

         DeletePerBarObjects();   // v2.4: nothing drawn before the recalc can linger

         g_wins = 0;
         g_losses = 0;
         g_pending = 0;
         g_flat = 0;
         g_rejRegime = 0; g_rejVolume = 0; g_rejDiv = 0; g_rejStrength = 0;
         g_rejCooldown = 0; g_rejPullback = 0; g_rejStack = 0; g_rejCost = 0;
      }
      else
      {
         int oldSize = ArraySize(g_bwCache);
         if(oldSize < rates_total)
         {
            //--- v2.4: new slots sit at the END (absolute index), i.e. the new bars
            ArrayResize(g_bwCache, rates_total);
            ArrayResize(g_lastRegime, rates_total);
            ArrayResize(g_rawRegime, rates_total);
            ArrayResize(g_regimeStreak, rates_total);
            ArrayResize(g_deadZoneCount, rates_total);
            ArrayResize(g_signalStrength, rates_total);
            ArrayResize(g_signalOutcome, rates_total);
            ArrayResize(g_emaTrend, rates_total);
            for(int n = oldSize; n < rates_total; n++)
            {
               g_bwCache[n]       = 0.0;
               g_lastRegime[n]    = REGIME_NONE;
               g_rawRegime[n]     = REGIME_NONE;
               g_regimeStreak[n]  = 0;
               g_deadZoneCount[n] = 0;
               g_signalStrength[n]= 0;
               g_signalOutcome[n] = 0;
               g_emaTrend[n]      = 0;
            }
         }
      }

      g_prevRatesTotal = rates_total;
      g_panelCacheValid = false;

      //--- Build bandwidth cache (v2.4: absolute-indexed, so each closed bar is
      //    computed once; the forming bar 0 is never read)
      int bwBuildFrom = fullRecalc ? MathMin(rates_total - 1, limit + InpBW_Lookback - 1) : limit;
      for(int b = bwBuildFrom; b >= 1; b--)
      {
         int    ab = AbsIdx(b);
         double m  = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_MAIN, b);
         if(m > 0)
         {
            double u = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_UPPER, b);
            double l = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_LOWER, b);
            g_bwCache[ab] = (u - l) / m;
         }
         else
            g_bwCache[ab] = 0;
      }
      g_bwCacheReady = true;

      //--- Cleanup + resolver throttle: object scans and the outcome walk are
      //    O(objects + signals*bars) — run once per bar, not on every tick.
      bool doMaint = fullRecalc;
      datetime maintBar = iTime(Symbol(), 0, 0);
      if(maintBar != g_lastMaintBar) { doMaint = true; g_lastMaintBar = maintBar; }

      if(doMaint)
      {
         //--- v2.4: SL/TP lines, strength labels and X marks share one age limit;
         //    clean whenever any of them is drawn (before: only with SL/TP lines
         //    on, so labels and X marks were never removed with SL/TP off)
         if((InpShowSLTP || InpShowStrength || InpInvalidateSignals) && InpSLTP_MaxAge > 0)
            CleanupSLTP();
         if(InpShowRegimeBG) CleanupRegimeBG();
      }

      //--- Main loop
      for(int i = limit; i >= 1; i--)
      {
         int a = AbsIdx(i);   // v2.4: index into the per-bar state arrays

         //=== STEP 1: Compute indicators ===
         double emaF    = iMA(Symbol(), 0, InpEMA_Fast,    0, InpMA_Method, PRICE_CLOSE, i);
         double emaS    = iMA(Symbol(), 0, InpEMA_Slow,    0, InpMA_Method, PRICE_CLOSE, i);
         double ema9v   = iMA(Symbol(), 0, InpEMA9_Period, 0, InpMA_Method, PRICE_CLOSE, i);
         double atr     = iATR(Symbol(), 0, InpATR_Period, i);
         double rsi     = iRSI(Symbol(), 0, InpRSI_Period, PRICE_CLOSE, i);
         double rsiPrev = iRSI(Symbol(), 0, InpRSI_Period, PRICE_CLOSE, i + 1);
         double adx     = iADX(Symbol(), 0, InpADX_Period, PRICE_CLOSE, MODE_MAIN, i);
         double diP     = iADX(Symbol(), 0, InpADX_Period, PRICE_CLOSE, MODE_PLUSDI, i);
         double diM     = iADX(Symbol(), 0, InpADX_Period, PRICE_CLOSE, MODE_MINUSDI, i);
         double bbUp    = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_UPPER, i);
         double bbLo    = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_LOWER, i);
         double bbMid   = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_MAIN, i);
         double cls     = iClose(Symbol(), 0, i);

         //--- NEW: Efficiency Ratio
         double er = CalcEfficiencyRatio(i, InpER_Period);

         //--- Cache bar-1 values for panel
         if(i == 1)
         {
            g_panelADX   = adx;
            g_panelRSI   = rsi;
            g_panelATR   = atr;
            g_panelBBUp  = bbUp;
            g_panelBBLo  = bbLo;
            g_panelBBMid = bbMid;
            g_panelCls   = cls;
            g_panelER    = er;
            g_panelCacheValid = true;
         }

         if(atr < _Point)
         {
            g_bbUpper[i] = EMPTY_VALUE; g_bbLower[i] = EMPTY_VALUE;
            g_emaFast[i] = EMPTY_VALUE; g_emaSlow[i] = EMPTY_VALUE;
            g_ema9[i]    = EMPTY_VALUE;
            g_mrBuy[i] = EMPTY_VALUE; g_mrSell[i] = EMPTY_VALUE;
            g_boBuy[i] = EMPTY_VALUE; g_boSell[i] = EMPTY_VALUE;
            g_strengthBuf[i] = 0.0; g_regimeBuf[i] = 0.0;
            g_emaTrend[a] = 0;
            g_signalStrength[a] = 0;
            ResetBarState(a);
            continue;
         }

         g_bbUpper[i] = bbUp;
         g_bbLower[i] = bbLo;
         g_emaFast[i] = emaF;
         g_emaSlow[i] = emaS;
         g_ema9[i]    = ema9v;

         //--- v2.1: cache EMA9-vs-EMA20 sign for downstream gates and the resolver.
         g_emaTrend[a] = (ema9v > emaF) ? +1 : (ema9v < emaF ? -1 : 0);

         g_mrBuy[i]  = EMPTY_VALUE;
         g_mrSell[i] = EMPTY_VALUE;
         g_boBuy[i]  = EMPTY_VALUE;
         g_boSell[i] = EMPTY_VALUE;
         g_signalStrength[a] = 0;
         g_strengthBuf[i] = 0.0;
         g_regimeBuf[i]   = 0.0;

         if(InpUseSessionFilter && !IsBarInSession(i))
         {
            //--- v2.4: a session gap resets the regime state, live exactly as on reload
            //    (before, the first in-session bar read leftovers from another bar live)
            ResetBarState(a);
            continue;
         }

         //=== STEP 2: Blended Regime Detection ===
         ENUM_REGIME rawRegime = DetectRegimeBlended(adx, bbUp, bbLo, bbMid, er, i);

         //--- Dead-zone persistence with decay
         if(rawRegime == REGIME_NONE)
         {
            if(a > 0 && g_rawRegime[a - 1] != REGIME_NONE)
            {
               if(g_deadZoneCount[a - 1] < InpDeadZoneDecay)
               {
                  rawRegime = g_rawRegime[a - 1];
                  g_deadZoneCount[a] = g_deadZoneCount[a - 1] + 1;
               }
               else
                  g_deadZoneCount[a] = 0;  // decayed — force NONE
            }
         }
         else
            g_deadZoneCount[a] = 0;  // reset when not in dead zone

         //--- v2.1: Apply MTF veto BEFORE hysteresis so a stale lastRegime can't
         //     be re-selected when local regime has reverted to NONE due to HTF
         //     disagreement. Joint local+HTF decision, not post-downgrade.
         if(InpUseMTF && rawRegime != REGIME_NONE)
         {
            double htfADX = CalcHTF_ADX(i);
            double htfER  = CalcHTF_ER(i);

            if(rawRegime == REGIME_TREND && htfADX < InpADX_RangeThresh && htfER < InpER_RangeThresh)
               rawRegime = REGIME_NONE;
            if(rawRegime == REGIME_RANGE && htfADX > InpADX_TrendThresh && htfER > InpER_TrendThresh)
               rawRegime = REGIME_NONE;
         }

         g_rawRegime[a] = rawRegime;

         //--- Hysteresis
         if(a > 0 && rawRegime == g_rawRegime[a - 1])
            g_regimeStreak[a] = g_regimeStreak[a - 1] + 1;
         else
            g_regimeStreak[a] = 1;

         //--- v2.1: fast-path confirmation — strong ER or ADX bypasses streak wait.
         double erFastPath  = er;
         double adxFastPath = adx;
         bool   fastConfirm = (rawRegime == REGIME_TREND &&
                               (erFastPath >= 0.85 || adxFastPath >= 35.0));

         ENUM_REGIME regime = REGIME_NONE;
         if(g_regimeStreak[a] >= InpRegimeConfirmBars || fastConfirm)
            regime = rawRegime;
         else if(a > 0 && rawRegime != REGIME_NONE && rawRegime == g_lastRegime[a - 1])
            regime = g_lastRegime[a - 1];   // v2.2: hold prior regime only when raw still agrees (else stand aside as NONE)

         g_lastRegime[a] = regime;

         //--- v2.3: export confirmed regime for iCustom callers
         g_regimeBuf[i] = (regime == REGIME_TREND) ? 1.0 : ((regime == REGIME_RANGE) ? -1.0 : 0.0);

         //=== STEP 3: Signal generation with strength + filters ===
         double offset  = InpArrowOffset_ATR * atr;
         double volRatio = GetVolumeRatio(i);

         if(regime == REGIME_RANGE)
         {
            //--- v2.4: with InpMR_RequireRejection the band/RSI extreme is read on the
            //    PREVIOUS bar (setup) and the reversal candle on THIS bar (trigger).
            //    The same-bar version could not pass: RSI only crosses up into OB on an
            //    up-close, so a bearish body on that bar needed an opening gap.
            int    setupBar     = InpMR_RequireRejection ? i + 1 : i;
            double setupCls     = cls, setupRsi = rsi, setupRsiPrev = rsiPrev;
            double setupBBUp    = bbUp, setupBBLo = bbLo;
            if(setupBar != i)
            {
               setupCls     = iClose(Symbol(), 0, setupBar);
               setupRsi     = rsiPrev;
               setupRsiPrev = iRSI(Symbol(), 0, InpRSI_Period, PRICE_CLOSE, setupBar + 1);
               setupBBUp    = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_UPPER, setupBar);
               setupBBLo    = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_LOWER, setupBar);
            }
            int sig = MeanReversionSignal(setupCls, setupRsi, setupRsiPrev, setupBBUp, setupBBLo,
                                          iOpen(Symbol(), 0, i), cls);
            if(sig != 0)
            {
               //--- Volume filter
               if(InpUseVolumeFilter && volRatio < InpVol_MR_MinRatio)
               {
                  sig = 0;
                  g_rejVolume++;
               }

               //--- RSI divergence check
               int div = 0;
               if(sig != 0 && (InpMR_RequireDiv || InpMR_DivBoost))
               {
                  div = DetectRSIDivergence(setupBar, InpDiv_Lookback);
                  if(InpMR_RequireDiv)
                  {
                     // For buy, need bullish div; for sell, need bearish div
                     if(sig > 0 && div != +1) { sig = 0; g_rejDiv++; }
                     if(sig < 0 && div != -1) { sig = 0; g_rejDiv++; }
                  }
               }

               //--- Signal strength
               if(sig != 0)
               {
                  double strength = CalcMRStrength(setupCls, setupRsi, setupBBUp, setupBBLo, atr, volRatio, div, er);
                  g_signalStrength[a] = strength;

                  if(strength < InpMinStrength)
                  {
                     sig = 0;  // too weak
                     g_rejStrength++;
                  }
               }
            }

            //--- v2.2: minimum reward:risk guard (off by default; reject poor-R:R MR setups when enabled)
            if(sig != 0 && InpMR_MinRR > 0.0)
            {
               double rrEntry, rrSL, rrTP;
               CalcSignalSLTP(1, i, sig, atr, 0, 0, bbMid, rrEntry, rrSL, rrTP);
               double rrRisk   = MathAbs(rrEntry - rrSL);
               double rrReward = (rrTP > 0) ? MathAbs(rrTP - rrEntry) : 0;
               if(rrRisk > 0 && rrReward / rrRisk < InpMR_MinRR) { sig = 0; g_rejStrength++; }
            }

            //--- v2.3: cost gate — a TP only a few spreads away can't pay for the trade
            if(sig != 0 && !PassesCostGate(1, i, sig, atr, 0, 0, bbMid))
            {
               sig = 0;
               g_rejCost++;
            }
            if(sig > 0)
            {
               if(!HasRecentSignal(g_mrBuy, i, InpCooldownBars, rates_total))
               {
                  g_mrBuy[i] = iLow(Symbol(), 0, i) - offset;
                  if(InpShowSLTP && WithinObjAge(i)) DrawSLTP(i, sig, atr, 1, 0, 0, bbMid);
                  if(InpShowStrength && WithinObjAge(i)) DrawStrengthLabel(i, g_signalStrength[a], true);
               }
               else
                  g_rejCooldown++;
            }
            else if(sig < 0)
            {
               if(!HasRecentSignal(g_mrSell, i, InpCooldownBars, rates_total))
               {
                  g_mrSell[i] = iHigh(Symbol(), 0, i) + offset;
                  if(InpShowSLTP && WithinObjAge(i)) DrawSLTP(i, sig, atr, 1, 0, 0, bbMid);
                  if(InpShowStrength && WithinObjAge(i)) DrawStrengthLabel(i, g_signalStrength[a], false);
               }
               else
                  g_rejCooldown++;
            }
         }
         else if(regime == REGIME_TREND)
         {
            //--- Consolidation tightness filter
            double tightness = ConsolidationTightness(i, InpBO_LookbackBars, atr);
            if(tightness > InpBO_MaxRangeATR || tightness < InpBO_MinRangeATR)
            {
               // Skip: consolidation too wide (sloppy) or too narrow (noise)
            }
            else
            {
               int boStart = i + 1;
               double boHiHigh = iHigh(Symbol(), 0, iHighest(Symbol(), 0, MODE_HIGH, InpBO_LookbackBars, boStart));
               double boLoLow  = iLow(Symbol(), 0, iLowest(Symbol(), 0, MODE_LOW, InpBO_LookbackBars, boStart));

               int sig;
               if(InpBO_RequireEMA9Pullback)
               {
                  //--- Pullback mode: don't fire on the break bar; fire on the EMA9 retest.
                  //    g_rejPullback is incremented only when the *would-have-been* entry
                  //    (raw BreakoutSignal would have fired) gets rejected by the pullback
                  //    condition, so the counter is meaningful instead of ticking each bar.
                  int rawSig = BreakoutSignal(cls, iHigh(Symbol(), 0, i), iLow(Symbol(), 0, i), rsi, atr, emaF, emaS, diP, diM, bbUp, bbLo,
                                              boHiHigh, boLoLow);
                  sig = BreakoutPullbackSignal(i, cls, rsi, atr, emaF, emaS, ema9v,
                                               diP, diM);
                  if(rawSig != 0 && sig == 0) g_rejPullback++;
               }
               else
               {
                  sig = BreakoutSignal(cls, iHigh(Symbol(), 0, i), iLow(Symbol(), 0, i), rsi, atr, emaF, emaS, diP, diM, bbUp, bbLo,
                                       boHiHigh, boLoLow);
               }

               //--- v2.1: EMA9>EMA20>EMA50 stack gate (inverse for sell)
               if(sig != 0 && InpBO_RequireEMA9Stack)
               {
                  bool stackOK = (sig > 0)
                                 ? (ema9v > emaF && emaF > emaS)
                                 : (ema9v < emaF && emaF < emaS);
                  if(!stackOK) { sig = 0; g_rejStack++; }
               }

               //--- Volume filter for breakouts
               if(sig != 0 && InpUseVolumeFilter && volRatio < InpVol_BO_MinRatio)
               {
                  sig = 0;
                  g_rejVolume++;
               }

               //--- Signal strength
               if(sig != 0)
               {
                  double strength = CalcBOStrength(cls, rsi, atr, emaF, emaS, diP, diM, adx,
                                                   volRatio, er, tightness, boHiHigh, boLoLow);
                  g_signalStrength[a] = strength;
                  if(strength < InpMinStrength)
                  {
                     sig = 0;
                     g_rejStrength++;
                  }
               }

               //--- v2.3: cost gate
               if(sig != 0 && !PassesCostGate(2, i, sig, atr, boHiHigh, boLoLow, 0))
               {
                  sig = 0;
                  g_rejCost++;
               }

               if(sig > 0)
               {
                  if(!HasRecentSignal(g_boBuy, i, InpCooldownBars, rates_total))
                  {
                     g_boBuy[i] = iLow(Symbol(), 0, i) - offset;
                     if(InpShowSLTP && WithinObjAge(i)) DrawSLTP(i, sig, atr, 2, boHiHigh, boLoLow, 0);
                     if(InpShowStrength && WithinObjAge(i)) DrawStrengthLabel(i, g_signalStrength[a], true);
                  }
                  else
                     g_rejCooldown++;
               }
               else if(sig < 0)
               {
                  if(!HasRecentSignal(g_boSell, i, InpCooldownBars, rates_total))
                  {
                     g_boSell[i] = iHigh(Symbol(), 0, i) + offset;
                     if(InpShowSLTP && WithinObjAge(i)) DrawSLTP(i, sig, atr, 2, boHiHigh, boLoLow, 0);
                     if(InpShowStrength && WithinObjAge(i)) DrawStrengthLabel(i, g_signalStrength[a], false);
                  }
                  else
                     g_rejCooldown++;
               }
            }
         }

         //--- v2.3: export candidate strength (kept even when the signal was
         //    rejected downstream, so an EA can study near-misses too)
         g_strengthBuf[i] = g_signalStrength[a];

         //--- Regime background
         if(InpShowRegimeBG && i >= 1 && i <= InpRegimeBG_MaxBars)
            DrawRegimeBackground(i, regime);
      }

      //--- Win/Loss resolution + signal invalidation (once per bar — intrabar
      //    SL/TP hits show up on the next bar open, which the panel can afford)
      if((InpTrackWinLoss || InpInvalidateSignals) && doMaint)
         ResolveSignalOutcomes(rates_total);

      //--- Alerts
      if(prevCalc > 0) CheckAlerts();

      //--- Panel
      if(InpShowPanel)
      {
         datetime currentBar = iTime(Symbol(), 0, 0);
         if(currentBar != g_lastPanelBar)
         {
            g_lastPanelBar = currentBar;
            DrawPanel();
         }
      }

      return(rates_total);
   }

   //+------------------------------------------------------------------+
   //| BLENDED REGIME DETECTION (ADX + ER)                              |
   //+------------------------------------------------------------------+
   ENUM_REGIME DetectRegimeBlended(double adx, double bbUp, double bbLo, double bbMid,
                                 double er, int shift)
   {
      double bandwidth = 0;
      if(bbMid > 0) bandwidth = (bbUp - bbLo) / bbMid;

      //--- Average bandwidth
      double avgBW = 0;
      int cnt = 0;
      if(g_bwCacheReady)
      {
         for(int j = shift; j < shift + InpBW_Lookback && j < g_absTotal; j++)
         {
            int aj = AbsIdx(j);   // v2.4: absolute-indexed cache
            if(g_bwCache[aj] > 0) { avgBW += g_bwCache[aj]; cnt++; }
         }
      }
      if(cnt > 0) avgBW /= cnt;

      bool isSqueeze = (avgBW > 0 && bandwidth / avgBW < InpBB_SqzRatio);

      //--- Normalize ADX to 0-1 scale for blending
      //    ADX at RangeThresh = 0, at TrendThresh = 1
      double adxNorm = 0.5;
      double adxRange = InpADX_TrendThresh - InpADX_RangeThresh;
      if(adxRange > 0)
         adxNorm = (adx - InpADX_RangeThresh) / adxRange;
      adxNorm = MathMax(0, MathMin(1, adxNorm));

      //--- Normalize ER: RangeThresh = 0, TrendThresh = 1
      double erNorm = 0.5;
      double erRange = InpER_TrendThresh - InpER_RangeThresh;
      if(erRange > 0)
         erNorm = (er - InpER_RangeThresh) / erRange;
      erNorm = MathMax(0, MathMin(1, erNorm));

      //--- Blend: weighted combination
      double blended = adxNorm * (1.0 - InpER_Weight) + erNorm * InpER_Weight;

      //--- Decision thresholds on blended score
      if(blended >= 0.70)                    return REGIME_TREND;
      if(blended <= 0.30 && !isSqueeze)      return REGIME_RANGE;
      if(isSqueeze && blended < 0.70)        return REGIME_TREND;  // squeeze = pre-breakout

      return REGIME_NONE;
   }

   //+------------------------------------------------------------------+
   //| MEAN-REVERSION SIGNAL                                            |
   //|   cls/rsi/rsiPrev/bbUp/bbLo: the setup bar (band + RSI extreme)  |
   //|   trigOpen/trigClose: the trigger bar, checked for the reversal  |
   //|   candle when InpMR_RequireRejection is on (v2.4: the bar after  |
   //|   the setup; without the option both are the same bar)           |
   //+------------------------------------------------------------------+
   int MeanReversionSignal(double cls, double rsi, double rsiPrev, double bbUp, double bbLo,
                           double trigOpen, double trigClose)
   {
      double bbRange = bbUp - bbLo;
      if(bbRange <= 0) return 0;
      double bbPos = (cls - bbLo) / bbRange;

      if(bbPos >= InpMR_BB_Touch && rsi >= InpMR_RSI_OB)
      {
         if(InpRequireRSICross && rsiPrev >= InpMR_RSI_OB) return 0;
         if(InpMR_RequireRejection && trigClose >= trigOpen) return 0;  // v2.2: need bearish rejection candle
         return -1;
      }
      if(bbPos <= (1.0 - InpMR_BB_Touch) && rsi <= InpMR_RSI_OS)
      {
         if(InpRequireRSICross && rsiPrev <= InpMR_RSI_OS) return 0;
         if(InpMR_RequireRejection && trigClose <= trigOpen) return 0;  // v2.2: need bullish rejection candle
         return +1;
      }
      return 0;
   }

   //+------------------------------------------------------------------+
   //| BREAKOUT SIGNAL (unchanged logic)                                |
   //+------------------------------------------------------------------+
   int BreakoutSignal(double cls, double hi, double lo, double rsi, double atr,
                     double emaF, double emaS,
                     double diP, double diM,
                     double bbUp, double bbLo,
                     double hiHigh, double loLow)
   {
      double buffer = InpBO_BreakBuffer * atr;

      if(cls > hiHigh + buffer && cls > bbUp && emaF > emaS
         && diP > diM && rsi > InpBO_Momentum_RSI
         && (InpBO_MinCloseStrength <= 0 || ((hi - lo) > 0 && (cls - lo) / (hi - lo) >= InpBO_MinCloseStrength)))
         return +1;

      if(cls < loLow - buffer && cls < bbLo && emaF < emaS
         && diM > diP && rsi < (100.0 - InpBO_Momentum_RSI)
         && (InpBO_MinCloseStrength <= 0 || ((hi - lo) > 0 && (hi - cls) / (hi - lo) >= InpBO_MinCloseStrength)))
         return -1;

      return 0;
   }

   //+------------------------------------------------------------------+
   //| v2.1: BREAKOUT PULLBACK SIGNAL                                   |
   //|   Fires on a retest of EMA9 within InpBO_PullbackMaxBars after   |
   //|   a confirmed range break. Returns +1/-1/0.                      |
   //|   Requires: a break bar in the recent past (closed beyond the    |
   //|   range and the outer band), current bar near EMA9 (within       |
   //|   tolerance), price still on the break side of the broken level, |
   //|   EMA stack still aligned, momentum RSI still on the right side, |
   //|   and DI alignment intact.                                       |
   //+------------------------------------------------------------------+
   int BreakoutPullbackSignal(int shift, double cls, double rsi, double atr,
                              double emaF, double emaS, double ema9v,
                              double diP, double diM)
   {
      if(atr < _Point) return 0;
      double tol = InpBO_PullbackTolATR * atr;
      if(MathAbs(cls - ema9v) > tol) return 0;       // not at EMA9 yet

      int maxScan = MathMin(InpBO_PullbackMaxBars, Bars - shift - 2);
      if(maxScan <= 0) return 0;

      for(int b = 1; b <= maxScan; b++)
      {
         int   br      = shift + b;
         double atrB   = iATR(Symbol(), 0, InpATR_Period, br);
         if(atrB < _Point) continue;
         double bufB   = InpBO_BreakBuffer * atrB;

         int    bStart = br + 1;
         if(bStart + InpBO_LookbackBars >= Bars) continue;

         double bHi = iHigh(Symbol(), 0,
                              iHighest(Symbol(), 0, MODE_HIGH, InpBO_LookbackBars, bStart));
         double bLo = iLow (Symbol(), 0,
                              iLowest (Symbol(), 0, MODE_LOW,  InpBO_LookbackBars, bStart));
         double clsB = iClose(Symbol(), 0, br);
         //--- v2.4: the outer-band test belongs to the BREAK bar. On the pullback bar it
         //    contradicted the EMA9 retest (a close within tolerance of EMA9 and beyond
         //    the outer band never coexist), so pullback mode could not fire.
         double bbUpB = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_UPPER, br);
         double bbLoB = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_LOWER, br);

         //--- Bullish pullback: prior bar broke up, price is still above the broken high
         //    (we're not back inside the range), EMA stack intact, momentum still bullish.
         if(clsB > bHi + bufB && clsB > bbUpB && cls > bHi && emaF > emaS
            && diP > diM && rsi > InpBO_Momentum_RSI)
            return +1;

         //--- Bearish pullback: mirror.
         if(clsB < bLo - bufB && clsB < bbLoB && cls < bLo && emaF < emaS
            && diM > diP && rsi < (100.0 - InpBO_Momentum_RSI))
            return -1;
      }
      return 0;
   }

   //+------------------------------------------------------------------+
   //| COOLDOWN CHECK                                                   |
   //+------------------------------------------------------------------+
   bool HasRecentSignal(const double &buf[], int shift, int cooldownBars, int totalBars)
   {
      int scanEnd = MathMin(shift + cooldownBars, totalBars - 1);
      for(int j = shift + 1; j <= scanEnd; j++)
         if(buf[j] != EMPTY_VALUE) return true;
      return false;
   }

   //+------------------------------------------------------------------+
   //| v2.1: SHARED SL/TP CALCULATOR                                    |
   //|   module: 1 = MR, 2 = BO                                         |
   //|   shift:  signal bar index                                       |
   //|   Single source of truth — used by DrawSLTP() and the resolver.  |
   //+------------------------------------------------------------------+
   void CalcSignalSLTP(int module, int shift, int direction, double atr,
                       double structHigh, double structLow, double bbMid,
                       double &entryOut, double &slOut, double &tpOut)
   {
      int execShift = MathMax(shift - 1, 0);
      double entry  = iOpen(Symbol(), 0, execShift);
      //--- v2.4: buys pay the spread for the newest signal too. Skipping it at
      //    execShift 0 made a live signal's SL/TP (and cost/R:R gates) differ from
      //    the same signal after a reload; it used to be redrawn a bar later.
      if(direction > 0)
         entry += MarketInfo(Symbol(), MODE_SPREAD) * _Point;

      double sl = 0, tp = 0;
      if(module == 1) // MR
      {
         sl = entry - direction * InpMR_SL_ATR * atr;
         double bbMidUse = bbMid;
         if(bbMidUse <= 0)
            bbMidUse = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_MAIN, shift);
         if(InpMR_TP_BBMid && bbMidUse > 0)
            tp = bbMidUse;
         else if(InpMR_TP_ATR > 0)
            tp = entry + direction * InpMR_TP_ATR * atr;
      }
      else            // BO
      {
         double atrSL    = entry - direction * InpBO_SL_ATR * atr;
         double structSL = atrSL;
         if(InpBO_SL_Structure && (structHigh > 0 || structLow > 0))
         {
            double pad = InpBO_StructPad * atr;
            if(direction > 0) structSL = structHigh - pad;
            else              structSL = structLow  + pad;
         }
         if(direction > 0)  sl = MathMin(atrSL, structSL);
         else               sl = MathMax(atrSL, structSL);

         if(InpBO_SL_MaxATR > 0)
         {
            double maxDist = InpBO_SL_MaxATR * atr;
            if(direction > 0 && (entry - sl) > maxDist) sl = entry - maxDist;
            else if(direction < 0 && (sl - entry) > maxDist) sl = entry + maxDist;
         }

         if(InpBO_TP_ATR > 0)
            tp = entry + direction * InpBO_TP_ATR * atr;
      }

      entryOut = entry;
      slOut    = sl;
      tpOut    = tp;
   }

   //+------------------------------------------------------------------+
   //| v2.3: COST GATE                                                  |
   //|   Rejects a signal whose TP distance is less than                |
   //|   InpMinTP_SpreadMult x the current spread. Uses the spread at   |
   //|   calc time (MT4 has no per-bar spread history), so historical   |
   //|   arrows are an approximation live; exact in the fixed-spread    |
   //|   tester where it matters for A/B runs.                          |
   //+------------------------------------------------------------------+
   bool PassesCostGate(int module, int shift, int direction, double atr,
                       double structHigh, double structLow, double bbMid)
   {
      if(InpMinTP_SpreadMult <= 0.0) return true;

      double entry = 0, sl = 0, tp = 0;
      CalcSignalSLTP(module, shift, direction, atr, structHigh, structLow, bbMid, entry, sl, tp);
      if(tp <= 0) return true;   // no TP defined — nothing to compare against

      double spreadDist = MarketInfo(Symbol(), MODE_SPREAD) * _Point;
      if(spreadDist <= 0) return true;

      return MathAbs(tp - entry) >= InpMinTP_SpreadMult * spreadDist;
   }

   //+------------------------------------------------------------------+
   //| WIN/LOSS RESOLUTION + SIGNAL INVALIDATION                        |
   //| Scans historical signals and checks if SL or TP was hit first    |
   //+------------------------------------------------------------------+
   void ResolveSignalOutcomes(int totalBars)
   {
      g_wins   = 0;
      g_losses = 0;
      g_pending = 0;
      g_flat   = 0;

      int lookback = MathMin(InpWL_MaxLookback, totalBars - 2);

      for(int i = lookback; i >= 1; i--)
      {
         bool hasSignal = false;
         int  direction = 0;
         int  module    = 0;

         if(g_mrBuy[i] != EMPTY_VALUE)       { hasSignal = true; direction = +1; module = 1; }
         else if(g_mrSell[i] != EMPTY_VALUE)  { hasSignal = true; direction = -1; module = 1; }
         else if(g_boBuy[i] != EMPTY_VALUE)   { hasSignal = true; direction = +1; module = 2; }
         else if(g_boSell[i] != EMPTY_VALUE)  { hasSignal = true; direction = -1; module = 2; }

         if(!hasSignal)
         {
            g_signalOutcome[AbsIdx(i)] = 0;
            continue;
         }

         //--- Reconstruct entry, SL, TP via shared helper
         double atr = iATR(Symbol(), 0, InpATR_Period, i);
         if(atr < _Point) { g_signalOutcome[AbsIdx(i)] = 0; continue; }

         //--- Reconstruct structural high/low for BO (matches main loop)
         double structHigh = 0, structLow = 0;
         if(module == 2)
         {
            int boStart = i + 1;
            if(boStart + InpBO_LookbackBars < totalBars)
            {
               structHigh = iHigh(Symbol(), 0,
                              iHighest(Symbol(), 0, MODE_HIGH, InpBO_LookbackBars, boStart));
               structLow  = iLow (Symbol(), 0,
                              iLowest (Symbol(), 0, MODE_LOW,  InpBO_LookbackBars, boStart));
            }
         }
         double bbMidI = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_MAIN, i);

         double entry = 0, sl = 0, tp = 0;
         CalcSignalSLTP(module, i, direction, atr, structHigh, structLow, bbMidI, entry, sl, tp);

         int execShift = MathMax(i - 1, 0);

         //--- Walk forward from entry bar to check outcome
         int  outcome   = 0;      // 0=pending
         bool flatExit  = false;  // v2.4: closed flat by the EMA9 invalidator
         bool ema9Armed = false;
         for(int j = execShift; j >= 1 && j >= i - InpWL_MaxLookback; j--)
         {
            double hi = iHigh(Symbol(), 0, j);
            double lo = iLow(Symbol(), 0, j);

            bool slHit = false, tpHit = false;

            if(direction > 0)
            {
               if(lo <= sl) slHit = true;
               if(tp > 0 && hi >= tp) tpHit = true;
            }
            else
            {
               if(hi >= sl) slHit = true;
               if(tp > 0 && lo <= tp) tpHit = true;
            }

            //--- v2.1: MR EMA9 invalidator — close on the wrong side of EMA9
            //          counts as exit BEFORE SL/TP if it happens first.
            //    v2.4: an MR entry starts on the far side of EMA9 by construction, so
            //          the old test fired on the entry bar ~99% of the time. Arm it only
            //          after a close on the profitable side of EMA9; a later close back
            //          through is the exit.
            if(module == 1 && InpMR_UseEMA9Invalidator)
            {
               double clsJ  = iClose(Symbol(), 0, j);
               double ema9J = iMA(Symbol(), 0, InpEMA9_Period, 0, InpMA_Method, PRICE_CLOSE, j);
               bool   favorable = (direction > 0 && clsJ > ema9J) ||
                                  (direction < 0 && clsJ < ema9J);
               if(favorable)
                  ema9Armed = true;
               else if(ema9Armed && !slHit && !tpHit)
               {
                  // Treat as breakeven exit — neither win nor loss.
                  outcome  = 0;
                  flatExit = true;
                  break;
               }
            }

            if(slHit && tpHit)
            {
               //--- v2.1: tie-break by relative distance from entry. The closer level
               //          is the more plausible same-bar fill. SL still wins on ties.
               double dSL = MathAbs(entry - sl);
               double dTP = (tp > 0) ? MathAbs(entry - tp) : 1e18;
               outcome = (dTP < dSL * 0.9) ? +1 : -1;
               break;
            }
            if(slHit) { outcome = -1; break; }
            if(tpHit) { outcome = +1; break; }
         }

         g_signalOutcome[AbsIdx(i)] = outcome;

         if(outcome > 0) g_wins++;
         else if(outcome < 0) g_losses++;
         else if(flatExit) g_flat++;
         else g_pending++;

         //--- Signal invalidation: gray out losing arrows
         //    v2.4: only inside the SL/TP age window (CleanupSLTP() deleted older X
         //    marks and this re-created them every bar), and an X is removed if the
         //    outcome is no longer a loss
         string invName = g_prefix + "INV_" + IntegerToString((int)iTime(Symbol(), 0, i));
         if(InpInvalidateSignals && outcome < 0 && WithinObjAge(i))
         {
            string objName = "";
            if(g_mrBuy[i]  != EMPTY_VALUE) objName = "MR Buy";
            if(g_mrSell[i] != EMPTY_VALUE) objName = "MR Sell";
            if(g_boBuy[i]  != EMPTY_VALUE) objName = "BO Buy";
            if(g_boSell[i] != EMPTY_VALUE) objName = "BO Sell";

            // Draw a gray "X" marker at the signal location to indicate invalidation
            double invY = (direction > 0) ? iLow(Symbol(), 0, i) - InpArrowOffset_ATR * atr * 1.5
                                          : iHigh(Symbol(), 0, i) + InpArrowOffset_ATR * atr * 1.5;
            if(ObjectFind(0, invName) < 0)
            {
               ObjectCreate(0, invName, OBJ_ARROW, 0, iTime(Symbol(), 0, i), invY);
               ObjectSetInteger(0, invName, OBJPROP_ARROWCODE, 251);  // "X" mark
               ObjectSetInteger(0, invName, OBJPROP_COLOR, InpInvalidColor);
               ObjectSetInteger(0, invName, OBJPROP_WIDTH, 2);
               ObjectSetInteger(0, invName, OBJPROP_SELECTABLE, false);
               ObjectSetInteger(0, invName, OBJPROP_HIDDEN, true);
               ObjectSetInteger(0, invName, OBJPROP_BACK, false);
            }
         }
         else if(ObjectFind(0, invName) >= 0)
            ObjectDelete(0, invName);
      }
   }

   //+------------------------------------------------------------------+
   //| DRAW SIGNAL STRENGTH LABEL                                       |
   //+------------------------------------------------------------------+
   void DrawStrengthLabel(int shift, double strength, bool isBuy)
   {
      string name = g_prefix + "STR_" + IntegerToString((int)iTime(Symbol(), 0, shift));
      double atr  = iATR(Symbol(), 0, InpATR_Period, shift);
      double y;

      if(isBuy)
         y = iLow(Symbol(), 0, shift) - InpArrowOffset_ATR * atr * 2.0;
      else
         y = iHigh(Symbol(), 0, shift) + InpArrowOffset_ATR * atr * 2.0;

      color clr = C'120,130,150';
      if(strength >= 80)      clr = C'0,220,130';
      else if(strength >= 60) clr = C'200,210,50';
      else                    clr = C'200,120,60';

      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_TEXT, 0, iTime(Symbol(), 0, shift), y);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      ObjectSetString(0, name, OBJPROP_TEXT, IntegerToString((int)strength));
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
      ObjectMove(0, name, 0, iTime(Symbol(), 0, shift), y);
   }

   //+------------------------------------------------------------------+
   //| REGIME BACKGROUND RECTANGLES                                     |
   //+------------------------------------------------------------------+
   void DrawRegimeBackground(int shift, ENUM_REGIME regime)
   {
      if(regime == REGIME_NONE) return;

      datetime barTime = iTime(Symbol(), 0, shift);
      string name = g_prefix + "BG_" + IntegerToString((int)barTime);

      color clr = clrNONE;
      if(regime == REGIME_RANGE) clr = C'30,60,90';
      if(regime == REGIME_TREND) clr = C'60,30,60';

      datetime t1 = iTime(Symbol(), 0, shift);
      datetime t2 = iTime(Symbol(), 0, MathMax(shift - 1, 0));
      double   hi = iHigh(Symbol(), 0, shift) + iATR(Symbol(), 0, InpATR_Period, shift) * 0.3;
      double   lo = iLow(Symbol(), 0, shift)  - iATR(Symbol(), 0, InpATR_Period, shift) * 0.3;

      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, hi, t2, lo);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_FILL, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, true);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      else
      {
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectMove(0, name, 0, t1, hi);
         ObjectMove(0, name, 1, t2, lo);
      }
   }

   void CleanupRegimeBG()
   {
      if(Bars <= InpRegimeBG_MaxBars) return;
      datetime cutoff = iTime(Symbol(), 0, MathMin(InpRegimeBG_MaxBars + 50, Bars - 1));
      string bgPrefix = g_prefix + "BG_";
      int totalObjects = ObjectsTotal(0, 0, -1);
      for(int k = totalObjects - 1; k >= 0; k--)
      {
         string objName = ObjectName(0, k);
         if(StringFind(objName, bgPrefix) == 0)
         {
            datetime objTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
            if(objTime < cutoff) ObjectDelete(0, objName);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| SL/TP LEVEL DRAWING (with BB-mid target for MR)                  |
   //| v2.1: thin wrapper around CalcSignalSLTP() — single source.      |
   //+------------------------------------------------------------------+
   void DrawSLTP(int shift, int signal, double atr, int module,
               double structHigh, double structLow, double bbMid)
   {
      double entry = 0, sl = 0, tp = 0;
      CalcSignalSLTP(module, shift, signal, atr, structHigh, structLow, bbMid, entry, sl, tp);

      datetime t1 = iTime(Symbol(), 0, shift);
      //--- v2.4: lines span 3 bars. A new signal has no bars to its right yet, so
      //    extend into the future instead of clamping to bar 0 (each bar is drawn
      //    once now; the old per-bar redraw used to stretch the line later)
      datetime t2 = (shift >= 3) ? iTime(Symbol(), 0, shift - 3) : (datetime)(t1 + 3 * PeriodSeconds());
      string timeKey = IntegerToString((int)t1);

      //--- SL line
      string slName = g_prefix + "SL_" + timeKey;
      if(ObjectFind(0, slName) < 0)
         ObjectCreate(0, slName, OBJ_TREND, 0, t1, sl, t2, sl);
      ObjectSetInteger(0, slName, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, slName, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, slName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, slName, OBJPROP_RAY, false);
      ObjectSetInteger(0, slName, OBJPROP_BACK, false);
      ObjectSetInteger(0, slName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, slName, OBJPROP_HIDDEN, true);
      ObjectMove(0, slName, 0, t1, sl);
      ObjectMove(0, slName, 1, t2, sl);

      //--- TP line
      if(tp != 0)
      {
         string tpName = g_prefix + "TP_" + timeKey;
         if(ObjectFind(0, tpName) < 0)
            ObjectCreate(0, tpName, OBJ_TREND, 0, t1, tp, t2, tp);
         ObjectSetInteger(0, tpName, OBJPROP_COLOR, clrLime);
         ObjectSetInteger(0, tpName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, tpName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, tpName, OBJPROP_RAY, false);
         ObjectSetInteger(0, tpName, OBJPROP_BACK, false);
         ObjectSetInteger(0, tpName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, tpName, OBJPROP_HIDDEN, true);
         ObjectMove(0, tpName, 0, t1, tp);
         ObjectMove(0, tpName, 1, t2, tp);
      }
   }

   void CleanupSLTP()
   {
      datetime cutoff = iTime(Symbol(), 0, MathMin(InpSLTP_MaxAge, Bars - 1));
      int totalObjects = ObjectsTotal(0, 0, -1);
      for(int k = totalObjects - 1; k >= 0; k--)
      {
         string objName = ObjectName(0, k);
         if(StringFind(objName, g_prefix + "SL_") == 0 ||
            StringFind(objName, g_prefix + "TP_") == 0 ||
            StringFind(objName, g_prefix + "STR_") == 0 ||
            StringFind(objName, g_prefix + "INV_") == 0)
         {
            datetime objTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
            if(objTime < cutoff) ObjectDelete(0, objName);
         }
      }
   }

   //+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| ALERT CHECK (with signal strength in message)                    |
//+------------------------------------------------------------------+
void FireAlertMessage(string text)
{
   string fullMsg = "[RegimeSwitch v2] " + text;
   Print(fullMsg);

   if(InpEnableAlerts)
      Alert("[RegimeSwitch v2] ", text);

   if(InpEnablePush)
   {
      ResetLastError();
      if(!SendNotification(fullMsg))
         Print("RegimeSwitch v2 push notification failed. Error=", GetLastError());
   }
}

void CheckAlerts()
{
   if(!InpEnableAlerts && !InpEnablePush) return;

   datetime signalBarTime = iTime(Symbol(), 0, 1);
   string signalGVKey = g_gvPrefix + "lastAlert";
   datetime lastSignalAlertBarTime = 0;
   if(GlobalVariableCheck(signalGVKey))
      lastSignalAlertBarTime = (datetime)(long)GlobalVariableGet(signalGVKey);

   string msgs[];
   int msgCount = 0;

   if(signalBarTime > lastSignalAlertBarTime)
   {
      if(g_mrBuy[1] != EMPTY_VALUE)
      {
         ArrayResize(msgs, msgCount + 1);
         msgs[msgCount++] = "MR BUY [" + IntegerToString((int)g_signalStrength[AbsIdx(1)]) + "]";
      }
      if(g_mrSell[1] != EMPTY_VALUE)
      {
         ArrayResize(msgs, msgCount + 1);
         msgs[msgCount++] = "MR SELL [" + IntegerToString((int)g_signalStrength[AbsIdx(1)]) + "]";
      }
      if(g_boBuy[1] != EMPTY_VALUE)
      {
         ArrayResize(msgs, msgCount + 1);
         msgs[msgCount++] = "BO BUY [" + IntegerToString((int)g_signalStrength[AbsIdx(1)]) + "]";
      }
      if(g_boSell[1] != EMPTY_VALUE)
      {
         ArrayResize(msgs, msgCount + 1);
         msgs[msgCount++] = "BO SELL [" + IntegerToString((int)g_signalStrength[AbsIdx(1)]) + "]";
      }
   }

   if(msgCount > 0)
   {
      GlobalVariableSet(signalGVKey, (double)(long)signalBarTime);

      string combined = Symbol() + " " + PeriodStr() + " | ";
      for(int a = 0; a < msgCount; a++)
      {
         if(a > 0) combined += " + ";
         combined += msgs[a];
      }

      FireAlertMessage(combined);
   }

   if(InpAlertEMACross)
   {
      double emaFast0 = iMA(Symbol(), 0, InpEMA_Fast, 0, InpMA_Method, PRICE_CLOSE, 0);
      double emaSlow0 = iMA(Symbol(), 0, InpEMA_Slow, 0, InpMA_Method, PRICE_CLOSE, 0);
      double emaFast1 = iMA(Symbol(), 0, InpEMA_Fast, 0, InpMA_Method, PRICE_CLOSE, 1);
      double emaSlow1 = iMA(Symbol(), 0, InpEMA_Slow, 0, InpMA_Method, PRICE_CLOSE, 1);
      double emaFast2 = iMA(Symbol(), 0, InpEMA_Fast, 0, InpMA_Method, PRICE_CLOSE, 2);
      double emaSlow2 = iMA(Symbol(), 0, InpEMA_Slow, 0, InpMA_Method, PRICE_CLOSE, 2);

      bool liveBull   = emaFast1 <= emaSlow1 && emaFast0 > emaSlow0;
      bool liveBear   = emaFast1 >= emaSlow1 && emaFast0 < emaSlow0;
      bool closedBull = emaFast2 <= emaSlow2 && emaFast1 > emaSlow1;
      bool closedBear = emaFast2 >= emaSlow2 && emaFast1 < emaSlow1;

      int emaEventId = 0;
      datetime emaEventTime = 0;
      string emaMsg = "";

      if(liveBull)
      {
         emaEventId = 1;
         emaEventTime = iTime(Symbol(), 0, 0);
         emaMsg = Symbol() + " " + PeriodStr() + " | EMA BULL CROSS ("
                + IntegerToString(InpEMA_Fast) + "/" + IntegerToString(InpEMA_Slow) + ")";
      }
      else if(liveBear)
      {
         emaEventId = 2;
         emaEventTime = iTime(Symbol(), 0, 0);
         emaMsg = Symbol() + " " + PeriodStr() + " | EMA BEAR CROSS ("
                + IntegerToString(InpEMA_Fast) + "/" + IntegerToString(InpEMA_Slow) + ")";
      }
      else if(closedBull)
      {
         emaEventId = 3;
         emaEventTime = iTime(Symbol(), 0, 1);
         emaMsg = Symbol() + " " + PeriodStr() + " | EMA BULL CROSS ("
                + IntegerToString(InpEMA_Fast) + "/" + IntegerToString(InpEMA_Slow) + ")";
      }
      else if(closedBear)
      {
         emaEventId = 4;
         emaEventTime = iTime(Symbol(), 0, 1);
         emaMsg = Symbol() + " " + PeriodStr() + " | EMA BEAR CROSS ("
                + IntegerToString(InpEMA_Fast) + "/" + IntegerToString(InpEMA_Slow) + ")";
      }

      if(emaEventId != 0)
      {
         string emaGVKey = g_gvPrefix + "lastEMACross";
         double emaEventCode = (double)((long)emaEventTime * 10 + emaEventId);
         double lastEMAEventCode = 0.0;
         if(GlobalVariableCheck(emaGVKey))
            lastEMAEventCode = GlobalVariableGet(emaGVKey);

         if(lastEMAEventCode != emaEventCode)
         {
            FireAlertMessage(emaMsg);
            GlobalVariableSet(emaGVKey, emaEventCode);
         }
      }
   }
}

   //+------------------------------------------------------------------+
   //| INFO PANEL (enhanced with ER, Win/Loss, Strength)                |
   //+------------------------------------------------------------------+
   void DrawPanel()
   {
      //--- Use cached values from main loop when available
      double adx, rsi, atr, bbUp, bbLo, bbMid, cls, er;
      if(g_panelCacheValid)
      {
         adx   = g_panelADX;
         rsi   = g_panelRSI;
         atr   = g_panelATR;
         bbUp  = g_panelBBUp;
         bbLo  = g_panelBBLo;
         bbMid = g_panelBBMid;
         cls   = g_panelCls;
         er    = g_panelER;
      }
      else
      {
         adx   = iADX(Symbol(), 0, InpADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
         rsi   = iRSI(Symbol(), 0, InpRSI_Period, PRICE_CLOSE, 1);
         atr   = iATR(Symbol(), 0, InpATR_Period, 1);
         bbUp  = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_UPPER, 1);
         bbLo  = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_LOWER, 1);
         bbMid = iBands(Symbol(), 0, InpBB_Period, InpBB_Dev, 0, PRICE_CLOSE, MODE_MAIN, 1);
         cls   = iClose(Symbol(), 0, 1);
         er    = CalcEfficiencyRatio(1, InpER_Period);
      }

      ENUM_REGIME regime = REGIME_NONE;
      int a1 = AbsIdx(1);   // v2.4: absolute-indexed state
      if(a1 >= 0 && a1 < ArraySize(g_lastRegime)) regime = g_lastRegime[a1];

      double bbRange = bbUp - bbLo;
      double bbPos   = (bbRange > 0) ? (cls - bbLo) / bbRange * 100.0 : 50.0;

      double bw = 0, avgBW = 0;
      if(bbMid > 0) bw = (bbUp - bbLo) / bbMid;
      int cnt = 0;
      if(g_bwCacheReady && ArraySize(g_bwCache) > InpBW_Lookback + 1)
      {
         for(int j = 1; j <= InpBW_Lookback; j++)
            if(g_bwCache[AbsIdx(j)] > 0) { avgBW += g_bwCache[AbsIdx(j)]; cnt++; }
      }
      if(cnt > 0) avgBW /= cnt;
      double sqzPct = (avgBW > 0) ? bw / avgBW * 100.0 : 100.0;

      //--- Signal counts
      int mrBuyCnt = 0, mrSellCnt = 0, boBuyCnt = 0, boSellCnt = 0;
      int lookback = MathMin(InpSignalCountBars, Bars - 1);
      for(int k = 1; k <= lookback; k++)
      {
         if(g_mrBuy[k]  != EMPTY_VALUE) mrBuyCnt++;
         if(g_mrSell[k] != EMPTY_VALUE) mrSellCnt++;
         if(g_boBuy[k]  != EMPTY_VALUE) boBuyCnt++;
         if(g_boSell[k] != EMPTY_VALUE) boSellCnt++;
      }

      string regStr = "NEUTRAL";
      color  regClr = C'100,110,130';
      color  regBG  = C'40,45,55';
      if(regime == REGIME_RANGE) { regStr = "RANGE"; regClr = C'60,160,240'; regBG = C'25,50,80'; }
      if(regime == REGIME_TREND) { regStr = "TREND"; regClr = C'200,100,220'; regBG = C'60,25,65'; }

      int px = g_panelX;
      int py = g_panelY;
      int pw = g_panelWidth;
      int lineH = 17;
      int pad = 10;
      int innerX = px + pad;
      int y = py;

      CreatePanelBG(g_prefix + "PBG", px, py, pw, 400, C'22,27,38', 200);
      y += 8;

      //=== HEADER ===
      CreateLabel(g_prefix + "hdr", innerX, y, "REGIME SWITCH v2", C'200,210,230', 10, true);
      y += 18;

      int badgeW = 80;
      if(regime == REGIME_RANGE) badgeW = 65;
      if(regime == REGIME_TREND) badgeW = 62;
      CreateBadge(g_prefix + "regBG", innerX, y, badgeW, 16, regBG);
      CreateLabel(g_prefix + "reg", innerX + 6, y + 1, regStr, regClr, 9, true);
      CreateLabel(g_prefix + "tf", innerX + badgeW + 8, y + 1,
                  Symbol() + " " + PeriodStr(), C'100,110,130', 8, false);
      y += 22;

      CreateSeparator(g_prefix + "sep1", innerX, y, pw - pad * 2, C'45,52,68');
      y += 6;

      //=== INDICATORS ===
      color dimClr = C'120,130,150';
      color valClr = C'200,210,225';

      // ADX
      color adxClr = dimClr;
      if(adx >= InpADX_TrendThresh) adxClr = C'200,100,220';
      else if(adx <= InpADX_RangeThresh) adxClr = C'60,160,240';
      CreateLabel(g_prefix + "adxL", innerX, y, "ADX", dimClr, 8, false);
      CreateLabel(g_prefix + "adxV", innerX + 70, y, DoubleToString(adx, 1), adxClr, 9, true);
      y += lineH;

      // NEW: Efficiency Ratio
      color erClr = valClr;
      if(er >= InpER_TrendThresh)      erClr = C'200,100,220';
      else if(er <= InpER_RangeThresh) erClr = C'60,160,240';
      CreateLabel(g_prefix + "erL", innerX, y, "Eff.Ratio", dimClr, 8, false);
      CreateLabel(g_prefix + "erV", innerX + 70, y, DoubleToString(er, 3), erClr, 9, true);
      CreateProgressBar(g_prefix + "erBar", innerX + 130, y + 4, 80, 5, er * 100.0, erClr, C'35,40,52');
      y += lineH;

      // RSI
      color rsiClr = valClr;
      if(rsi >= InpMR_RSI_OB)      rsiClr = C'220,80,80';
      else if(rsi <= InpMR_RSI_OS) rsiClr = C'60,180,130';
      CreateLabel(g_prefix + "rsiL", innerX, y, "RSI", dimClr, 8, false);
      CreateLabel(g_prefix + "rsiV", innerX + 70, y, DoubleToString(rsi, 1), rsiClr, 9, true);
      string rsiTag = "";
      if(rsi >= InpMR_RSI_OB)      rsiTag = "OVERBOUGHT";
      else if(rsi <= InpMR_RSI_OS) rsiTag = "OVERSOLD";
      CreateLabel(g_prefix + "rsiT", innerX + 110, y, rsiTag, rsiClr, 7, false);
      y += lineH;

      // ATR
      CreateLabel(g_prefix + "atrL", innerX, y, "ATR", dimClr, 8, false);
      CreateLabel(g_prefix + "atrV", innerX + 70, y, DoubleToString(atr, Digits), valClr, 9, true);
      y += lineH;

      // BB Position
      color bbpClr = valClr;
      if(bbPos > 90) bbpClr = C'220,80,80';
      else if(bbPos < 10) bbpClr = C'60,180,130';
      CreateLabel(g_prefix + "bbpL", innerX, y, "BB Pos", dimClr, 8, false);
      CreateLabel(g_prefix + "bbpV", innerX + 70, y, DoubleToString(bbPos, 1) + "%", bbpClr, 9, true);
      CreateProgressBar(g_prefix + "bbBar", innerX + 130, y + 4, 80, 5, bbPos, bbpClr, C'35,40,52');
      y += lineH + 4;

      // Squeeze
      bool sqzActive = (sqzPct < InpBB_SqzRatio * 100);
      color sqzClr = valClr;
      if(sqzActive) sqzClr = C'255,200,50';
      CreateLabel(g_prefix + "sqzL", innerX, y, "Squeeze", dimClr, 8, false);
      CreateLabel(g_prefix + "sqzV", innerX + 70, y, DoubleToString(sqzPct, 1) + "%", sqzClr, 9, true);
      CreateLabel(g_prefix + "sqzA", innerX + 130, y, sqzActive ? "ACTIVE" : "       ",
                  sqzActive ? C'255,200,50' : C'22,27,38', 7, sqzActive);
      y += lineH + 4;

      // NEW: Volume ratio (v2.3: show the real ratio even when the filter is off —
      // the old pass-through painted a meaningless "999.00x")
      double volR = GetVolumeRatio(1, true);
      color volClr = valClr;
      if(volR >= 1.5) volClr = C'0,220,130';
      else if(volR < 0.7) volClr = C'200,120,60';
      CreateLabel(g_prefix + "volL", innerX, y, "Vol Ratio", dimClr, 8, false);
      CreateLabel(g_prefix + "volV", innerX + 70, y, DoubleToString(volR, 2) + "x", volClr, 9, true);
      y += lineH + 4;

      CreateSeparator(g_prefix + "sep2", innerX, y, pw - pad * 2, C'45,52,68');
      y += 6;

      //=== SIGNAL COUNTS ===
      CreateLabel(g_prefix + "sigH", innerX, y, "SIGNALS  (last " + IntegerToString(lookback) + ")", C'100,110,130', 8, false);
      y += lineH;

      CreateLabel(g_prefix + "mrL", innerX + 4, y, "MR", C'60,160,240', 8, true);
      CreateLabel(g_prefix + "mrV", innerX + 30, y,
                  IntegerToString(mrBuyCnt) + " buy  " + IntegerToString(mrSellCnt) + " sell",
                  C'160,170,190', 8, false);
      y += lineH;

      CreateLabel(g_prefix + "boL", innerX + 4, y, "BO", C'120,230,100', 8, true);
      CreateLabel(g_prefix + "boV", innerX + 30, y,
                  IntegerToString(boBuyCnt) + " buy  " + IntegerToString(boSellCnt) + " sell",
                  C'160,170,190', 8, false);
      y += lineH + 2;

      //=== NEW: WIN/LOSS SECTION ===
      if(InpTrackWinLoss)
      {
         CreateSeparator(g_prefix + "sep2b", innerX, y, pw - pad * 2, C'45,52,68');
         y += 6;

         int total = g_wins + g_losses;
         double winRate = (total > 0) ? (double)g_wins / total * 100.0 : 0;

         CreateLabel(g_prefix + "wlH", innerX, y, "WIN / LOSS", C'100,110,130', 8, false);
         y += lineH;

         color wrClr = C'160,170,190';
         if(winRate >= 55) wrClr = C'0,220,130';
         else if(winRate < 45 && total > 5) wrClr = C'220,80,80';

         CreateLabel(g_prefix + "wlW", innerX + 4, y, IntegerToString(g_wins) + "W", C'0,190,130', 9, true);
         CreateLabel(g_prefix + "wlD", innerX + 50, y, "/", C'100,110,130', 9, false);
         CreateLabel(g_prefix + "wlL", innerX + 62, y, IntegerToString(g_losses) + "L", C'220,80,80', 9, true);
         string openTxt = "(" + IntegerToString(g_pending) + " open";
         if(InpMR_UseEMA9Invalidator) openTxt += ", " + IntegerToString(g_flat) + " flat";   // v2.4
         CreateLabel(g_prefix + "wlP", innerX + 110, y, openTxt + ")", C'100,110,130', 7, false);
         y += lineH;

         CreateLabel(g_prefix + "wrL", innerX + 4, y, "Win Rate", dimClr, 8, false);
         CreateLabel(g_prefix + "wrV", innerX + 70, y, DoubleToString(winRate, 1) + "%", wrClr, 9, true);
         if(total > 0)
            CreateProgressBar(g_prefix + "wrBar", innerX + 130, y + 4, 80, 5, winRate, wrClr, C'35,40,52');
         y += lineH + 2;
      }

      //=== v2.1: REJECTED-SIGNAL COUNTERS ===
      CreateSeparator(g_prefix + "sep2c", innerX, y, pw - pad * 2, C'45,52,68');
      y += 6;
      CreateLabel(g_prefix + "rjH", innerX, y, "REJECTED  (since recalc)", C'100,110,130', 8, false);
      y += lineH;
      string rj1 = "vol " + IntegerToString(g_rejVolume) +
                   "  div "  + IntegerToString(g_rejDiv) +
                   "  str "  + IntegerToString(g_rejStrength);
      string rj2 = "cool " + IntegerToString(g_rejCooldown) +
                   "  pb "   + IntegerToString(g_rejPullback) +
                   "  stk "  + IntegerToString(g_rejStack) +
                   "  cost " + IntegerToString(g_rejCost);
      CreateLabel(g_prefix + "rj1", innerX + 4, y, rj1, C'160,170,190', 8, false);
      y += lineH;
      CreateLabel(g_prefix + "rj2", innerX + 4, y, rj2, C'160,170,190', 8, false);
      y += lineH + 2;

      CreateSeparator(g_prefix + "sep3", innerX, y, pw - pad * 2, C'45,52,68');
      y += 6;

      //=== LEGEND ===
      CreateLabel(g_prefix + "legH", innerX, y, "LEGEND", C'100,110,130', 8, false);
      y += lineH;

      CreateLabelWingdings(g_prefix + "leg1i", innerX + 2, y, ShortToString(233), C'60,160,240', 10);
      CreateLabel(g_prefix + "leg1t", innerX + 20, y, "MR Buy", C'60,160,240', 8, false);
      CreateLabelWingdings(g_prefix + "leg2i", innerX + 80, y, ShortToString(234), C'220,100,60', 10);
      CreateLabel(g_prefix + "leg2t", innerX + 98, y, "MR Sell", C'220,100,60', 8, false);
      y += lineH;

      CreateLabelWingdings(g_prefix + "leg3i", innerX + 2, y, ShortToString(241), C'120,230,100', 10);
      CreateLabel(g_prefix + "leg3t", innerX + 20, y, "BO Buy", C'120,230,100', 8, false);
      CreateLabelWingdings(g_prefix + "leg4i", innerX + 80, y, ShortToString(242), C'200,100,220', 10);
      CreateLabel(g_prefix + "leg4t", innerX + 98, y, "BO Sell", C'200,100,220', 8, false);
      y += lineH;

      if(InpInvalidateSignals)
      {
         CreateLabelWingdings(g_prefix + "leg5i", innerX + 2, y, ShortToString(251), InpInvalidColor, 10);
         CreateLabel(g_prefix + "leg5t", innerX + 20, y, "SL Hit", InpInvalidColor, 8, false);
         y += lineH;
      }

      int totalH = y - py + 10;
      ObjectSetInteger(0, g_prefix + "PBG", OBJPROP_YSIZE, totalH);
   }

   //+------------------------------------------------------------------+
   //| PANEL HELPER FUNCTIONS                                           |
   //+------------------------------------------------------------------+
   void CreatePanelBG(string name, int x, int y, int w, int h, color bgClr, int opacity=180)
   {
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
      }
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'45,52,68');
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }

   void CreateSeparator(string name, int x, int y, int w, color clr)
   {
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
      }
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 1);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clr);
   }

   void CreateBadge(string name, int x, int y, int w, int h, color bgClr)
   {
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
      }
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, bgClr);
   }

   void CreateProgressBar(string name, int x, int y, int totalW, int h, double pct, color fillClr, color bgClr)
   {
      string bgName = name + "_bg";
      if(ObjectFind(0, bgName) < 0)
      {
         ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, bgName, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, bgName, OBJPROP_XSIZE, totalW);
      ObjectSetInteger(0, bgName, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, bgClr);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, bgClr);

      string fName = name + "_fl";
      int fillW = (int)MathMax(1, MathRound(totalW * MathMin(pct, 100.0) / 100.0));
      if(ObjectFind(0, fName) < 0)
      {
         ObjectCreate(0, fName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, fName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, fName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, fName, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, fName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, fName, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, fName, OBJPROP_XSIZE, fillW);
      ObjectSetInteger(0, fName, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, fName, OBJPROP_BGCOLOR, fillClr);
      ObjectSetInteger(0, fName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, fName, OBJPROP_BORDER_COLOR, fillClr);
   }

   void CreateLabel(string name, int x, int y, string text, color clr, int fontSize, bool bold)
   {
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
      }
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Consolas");
   }

   void CreateLabelWingdings(string name, int x, int y, string text, color clr, int fontSize)
   {
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
      }
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Wingdings");
   }

   //+------------------------------------------------------------------+
   //| SESSION CHECK                                                    |
   //+------------------------------------------------------------------+
   bool IsBarInSession(int shift)
   {
      int hour = TimeHour(iTime(Symbol(), 0, shift));
      if(InpSessionStartHour < InpSessionEndHour)
         return (hour >= InpSessionStartHour && hour < InpSessionEndHour);
      else
         return (hour >= InpSessionStartHour || hour < InpSessionEndHour);
   }

   //+------------------------------------------------------------------+
   //| PERIOD STRING                                                    |
   //+------------------------------------------------------------------+
   string PeriodStr()
   {
      switch(Period())
      {
         case PERIOD_M1:  return "M1";
         case PERIOD_M5:  return "M5";
         case PERIOD_M15: return "M15";
         case PERIOD_M30: return "M30";
         case PERIOD_H1:  return "H1";
         case PERIOD_H4:  return "H4";
         case PERIOD_D1:  return "D1";
         case PERIOD_W1:  return "W1";
         case PERIOD_MN1: return "MN";
         default:         return "TF" + IntegerToString(Period());
      }
   }
   //+------------------------------------------------------------------+
