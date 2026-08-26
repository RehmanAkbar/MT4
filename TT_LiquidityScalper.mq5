//+------------------------------------------------------------------+
//|                                          TT_LiquidityScalper.mq5 |
//|                  Liquidity sweep scalper (Smart Money Concepts)   |
//|                                                                   |
//|  HTF/MTF bias alignment -> POI mitigation -> liquidity sweep ->    |
//|  entry trigger -> fixed target at the next liquidity pool.         |
//|                                                                   |
//|  NON-REPAINTING CONTRACT                                           |
//|   * Every decision is taken on a CLOSED bar. Index 0 is never read |
//|     for logic.                                                     |
//|   * A swing is confirmed only after SwingRightBars bars have       |
//|     closed to its right, so a printed arrow can never be revoked.  |
//|   * The state machine only moves forward. On prev_calculated == 0  |
//|     history is rebuilt deterministically from the oldest bar       |
//|     towards the newest, reproducing the identical signal set.      |
//|   * Multi-timeframe reads are all checked; when higher-timeframe   |
//|     data is not ready OnCalculate returns 0 so MT5 retries rather  |
//|     than committing to partial data.                               |
//|                                                                   |
//|  INDEXING: series indexing everywhere (0 = forming bar, 1 = last   |
//|  closed bar). Walking history forward counts DOWN. See the         |
//|  convention block at the top of Include/TT/Structure.mqh.          |
//|                                                                   |
//|  Chart timeframe independence: Period() is used for display        |
//|  scaling only. All logic runs on BiasTF / SetupTF / EntryTF, so    |
//|  the same signals appear whatever timeframe the chart shows.       |
//+------------------------------------------------------------------+
#property copyright "TT_LiquidityScalper"
#property link      ""
#property version   "1.00"
#property description "SMC liquidity sweep scalper - bias, POI, sweep, entry, target"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   2

#property indicator_type1   DRAW_ARROW
#property indicator_label1  "TTLS Buy"
#property indicator_type2   DRAW_ARROW
#property indicator_label2  "TTLS Sell"

#include <TT/Structure.mqh>
#include <TT/Liquidity.mqh>
#include <TT/Zones.mqh>
#include <TT/Risk.mqh>
#include <TT/Draw.mqh>

//--- ceiling on stored signals; the oldest are dropped first
#define TTLS_MAX_SIGNALS         512
//--- bars an aggressive setup may wait for its confirmation candle
#define TTLS_MAX_CONFIRM_BARS    5
//--- How much markup is rendered. Chart hygiene only - none of these affect
//--- a single decision, they just stop the chart turning into a colour wash.
#define TTLS_DRAW_MAX_EVENTS     18
#define TTLS_DRAW_MAX_SIGNALS    40
#define TTLS_DRAW_MAX_DEAD_ZONES 3
#define TTLS_DRAW_MAX_LIQUIDITY  30
//--- ATR period used for every adaptive tolerance in the package
#define TTLS_ATR_PERIOD          14

//+------------------------------------------------------------------+
//| Enumerations exposed as inputs                                    |
//+------------------------------------------------------------------+
enum ENTRY_MODE
  {
   ENTRY_AGGRESSIVE   = 0,  // Aggressive - fire on the sweep bar close
   ENTRY_CONSERVATIVE = 1,  // Conservative - await LTF shift + pullback
   ENTRY_BOTH         = 2   // Both - whichever triggers first
  };

enum TARGET_MODE
  {
   TARGET_NEAREST_INTERNAL  = 0, // Nearest unswept opposing pool (SetupTF)
   TARGET_HTF_WEAK          = 1, // HTF weak level
   TARGET_NEXT_OPPOSING_POI = 2  // Next opposing zone
  };

//--- SetupState buffer contract. Do not renumber: an EA reads these.
enum TT_SM_STATE
  {
   SM_IDLE    = 0,
   SM_ARMED   = 1,
   SM_AT_POI  = 2,
   SM_SWEPT   = 3,
   SM_PENDING = 4,   // conservative: LTF shift found, awaiting the pullback
   SM_SIGNAL  = 5,   // one bar only, on the bar that fired
   SM_MISSED  = 6    // conservative setup expired without a pullback
  };

//+------------------------------------------------------------------+
input group "=== Timeframes ==="
input ENUM_TIMEFRAMES InpBiasTF              = PERIOD_H1;   // BiasTF - directional filter
input ENUM_TIMEFRAMES InpSetupTF             = PERIOD_M15;  // SetupTF - POIs, liquidity, sweeps
input ENUM_TIMEFRAMES InpEntryTF             = PERIOD_M5;   // EntryTF - conservative trigger
input int             InpMaxHistoryBars      = 2000;        // Max SetupTF bars rebuilt (other TFs matched by time)

input group "=== Structure ==="
input int             InpSwingLeftBars       = 3;      // SwingLeftBars
input int             InpSwingRightBars      = 3;      // SwingRightBars (confirmation lag)
input bool            InpUseWickBreaks       = false;  // UseWickBreaks (false = close-based)
input bool            InpShowMS              = true;   // ShowMS
input bool            InpShowBOS             = true;   // ShowBOS
input bool            InpShowStrongWeak      = true;   // ShowStrongWeak

input group "=== Zones ==="
input bool            InpUseDemandSupply     = true;   // UseDemandSupply
input bool            InpUseOrderBlocks      = true;   // UseOrderBlocks
input bool            InpUseFVG              = true;   // UseFVG
input bool            InpUseBreakers         = true;   // UseBreakers
input ZONE_MODE       InpZoneMode            = ZONE_PIVOT_CANDLE; // ZoneMode
input int             InpMaxActiveZones      = 3;      // MaxActiveZones (per direction)
input int             InpExtendZonesBars     = 60;     // ExtendZonesBars

input group "=== Liquidity ==="
input bool            InpShowLiquidity       = true;   // ShowLiquidity
input double          InpEqualLevelToleranceATR = 0.15;// EqualLevelToleranceATR
input double          InpSweepBufferPoints   = 0;      // SweepBufferPoints (0 = auto from ATR)
input int             InpSweepCloseBackBars  = 1;      // SweepCloseBackBars
input double          InpSweepProximityPoints = 0;     // SweepProximityPoints (0 = auto)
input bool            InpKeepSweptLiquidity  = true;   // KeepSweptLiquidity

input group "=== Entry ==="
input ENTRY_MODE      InpEntryMode           = ENTRY_AGGRESSIVE; // EntryMode
input bool            InpRequireConfirmationCandle = false;      // RequireConfirmationCandle
input int             InpConservativeExpiryBars = 12;  // ConservativeExpiryBars (EntryTF bars)
input TARGET_MODE     InpTargetMode          = TARGET_NEAREST_INTERNAL; // TargetMode
input double          InpMinRR               = 1.5;    // MinRR
input double          InpStopBufferPoints    = 0;      // StopBufferPoints (0 = auto 0.2*ATR)

input group "=== Filters ==="
input bool            InpUseSessionFilter    = false;  // UseSessionFilter
input int             InpSessionStartHour    = 7;      // SessionStartHour (server time)
input int             InpSessionEndHour      = 20;     // SessionEndHour (server time)
input int             InpMaxSignalsPerDay    = 3;      // MaxSignalsPerDay (0 = unlimited)
input int             InpMinBarsBetweenSignals = 5;    // MinBarsBetweenSignals (SetupTF bars)
input int             InpAvoidHighImpactMinutes = 0;   // AvoidHighImpactMinutes (0 = off)
input string          InpBlackoutTimes       = "12:30,14:00"; // Blackout times HH:MM,HH:MM
input double          InpMaxSpreadPoints     = 0;      // MaxSpreadPoints (0 = no spread gate)

input group "=== Risk ==="
input double          InpAccountRiskPercent  = 0.5;    // AccountRiskPercent
input bool            InpShowLotSize         = true;   // ShowLotSize
input double          InpMaxDailyLossPercent = 0;      // MaxDailyLossPercent (0 = off)

input group "=== Alerts ==="
input bool            InpAlertPopup          = true;   // AlertPopup
input bool            InpAlertPush           = false;  // AlertPush
input bool            InpAlertEmail          = false;  // AlertEmail
input bool            InpAlertOncePerSetup   = true;   // AlertOncePerSetup

input group "=== Display ==="
input ENUM_BASE_CORNER InpPanelCorner        = CORNER_LEFT_UPPER; // PanelCorner
input bool            InpShowInfoPanel       = true;   // ShowInfoPanel
input color           InpColorBull           = clrDodgerBlue;   // Bull colour
input color           InpColorBear           = clrOrangeRed;    // Bear colour
input color           InpColorZoneBull       = clrRoyalBlue;    // Demand zone colour
input color           InpColorZoneBear       = clrIndianRed;    // Supply zone colour
input color           InpColorInvalid        = clrDimGray;      // Invalidated colour
input color           InpColorLiquidity      = clrGoldenrod;    // Liquidity colour
input color           InpColorStrongWeak     = clrFireBrick;    // Strong/Weak colour
input color           InpColorStructure      = clrSilver;       // MS/BOS colour
input color           InpColorText           = clrWhiteSmoke;   // Panel text colour
input int             InpFontSize            = 8;      // FontSize

//+------------------------------------------------------------------+
//| Indicator buffers - see the iCustom contract table in README.md   |
//+------------------------------------------------------------------+
double BufBuy[];       // 0 arrow  entry price on a long signal bar
double BufSell[];      // 1 arrow  entry price on a short signal bar
double BufEntry[];     // 2 data   entry level
double BufSL[];        // 3 data   stop level
double BufTP[];        // 4 data   target level
double BufBias[];      // 5 data   +1 / -1 / 0
double BufState[];     // 6 data   TT_SM_STATE code
double BufQuality[];   // 7 data   0..100

//+------------------------------------------------------------------+
//| Engines                                                           |
//+------------------------------------------------------------------+
CStructureEngine g_stBias, g_stSetup, g_stEntry;
CZoneBook        g_zoneBias, g_zoneSetup, g_zoneEntry;
CLiquidityMap    g_liq;
CSignalGovernor  g_gov;
CValueTrack      g_trackBull, g_trackBear;

TTDrawCfg        g_draw;
TTFilterCfg      g_filter;

//+------------------------------------------------------------------+
//| Per-direction setup context (the state machine of section 3.6).   |
//+------------------------------------------------------------------+
struct TTSetupCtx
  {
   bool              bullish;
   int               state;
   //--- point of interest currently being watched
   int               zoneId;
   double            zoneTop, zoneBottom;
   bool              zoneUntested;
   //--- the sweep that armed the trigger
   datetime          sweptBarTime;    // bar whose close confirmed the sweep
   datetime          sweptBarClose;
   double            protectedPrice;  // sweep extreme - the level the stop hides behind
   double            poolPrice;
   int               poolCount;
   bool              sweepInside;     // inside the zone (not merely near it)
   double            atrAtSweep;
   int               spreadAtSweep;
   int               confirmBars;
   //--- conservative sub-sequence
   datetime          shiftSearchFrom;
   datetime          shiftTime;
   double            ltfTop, ltfBottom;
   double            pendingEntry;
   double            pendingTp;
   datetime          scanFrom;
   int               pullbackBars;
  };

TTSetupCtx  g_bull, g_bear;
TTSignal    g_signals[];
int         g_signalCount = 0;
datetime    g_lastAlertTime = 0;
datetime    g_lastSweepAlert = 0;
bool        g_dirty = true;           // markup needs a redraw
bool        g_lossBreached = false;
double      g_lossPct = 0.0;
datetime    g_lastLossCheck = 0;      // the daily-loss probe is throttled
int         g_digits = 2;
int         g_maxZones = 3;
string      g_sym = "";

//+------------------------------------------------------------------+
//| Forward declarations                                              |
//+------------------------------------------------------------------+
void   ResetCtx(TTSetupCtx &ctx);
void   PushState(TTSetupCtx &ctx, const datetime t, const int state);
bool   UpdateSimpleTf(CStructureEngine &st, CZoneBook &zb, const bool rebuild);
bool   UpdateSetupTf(const bool rebuild);
void   StepSetup(TTSetupCtx &ctx, const int b, const bool swept, const TTSweepInfo &sw);
void   AdvanceConservative(TTSetupCtx &ctx, const datetime upto);
void   FireSignal(TTSetupCtx &ctx, const bool aggressive, const double entry,
                  const datetime barTime, const ENUM_TIMEFRAMES tf);

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   g_sym    = _Symbol;
   g_digits = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);

   SetIndexBuffer(0, BufBuy,     INDICATOR_DATA);
   SetIndexBuffer(1, BufSell,    INDICATOR_DATA);
   SetIndexBuffer(2, BufEntry,   INDICATOR_DATA);
   SetIndexBuffer(3, BufSL,      INDICATOR_DATA);
   SetIndexBuffer(4, BufTP,      INDICATOR_DATA);
   SetIndexBuffer(5, BufBias,    INDICATOR_DATA);
   SetIndexBuffer(6, BufState,   INDICATOR_DATA);
   SetIndexBuffer(7, BufQuality, INDICATOR_DATA);

   //--- series indexing on every buffer: the one convention in this package
   ArraySetAsSeries(BufBuy,     true);
   ArraySetAsSeries(BufSell,    true);
   ArraySetAsSeries(BufEntry,   true);
   ArraySetAsSeries(BufSL,      true);
   ArraySetAsSeries(BufTP,      true);
   ArraySetAsSeries(BufBias,    true);
   ArraySetAsSeries(BufState,   true);
   ArraySetAsSeries(BufQuality, true);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 10);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpColorBull);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 2);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -10);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpColorBear);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, 2);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetInteger(INDICATOR_DIGITS, g_digits);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("TT_LiquidityScalper %s/%s/%s",
                                   TTTfLabel(InpBiasTF), TTTfLabel(InpSetupTF),
                                   TTTfLabel(InpEntryTF)));

   if(!ValidateInputs())
      return(INIT_FAILED);

   g_maxZones = (int)MathMax(1, InpMaxActiveZones);
   InitConfigs();
   if(!InitEngines())
      return(INIT_FAILED);

   ArrayResize(g_signals, TTLS_MAX_SIGNALS);
   ResetCtx(g_bull);
   ResetCtx(g_bear);
   g_bull.bullish = true;
   g_bear.bullish = false;
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Input validation.                                                 |
//|                                                                   |
//| PERIOD_CURRENT is rejected outright. Accepting it would make the  |
//| analysis timeframe follow whatever the chart happens to show, and |
//| chart-timeframe independence is a hard guarantee here, not a      |
//| preference - the same signals must appear on M5 and on M15.       |
//+------------------------------------------------------------------+
bool ValidateInputs(void)
  {
   if(InpBiasTF == PERIOD_CURRENT || InpSetupTF == PERIOD_CURRENT ||
      InpEntryTF == PERIOD_CURRENT)
     {
      Print("TTLS: BiasTF / SetupTF / EntryTF must name explicit timeframes. ",
            "\"Current timeframe\" would tie the analysis to the chart and break ",
            "timeframe independence. Defaults: H1 / M15 / M5.");
      return(false);
     }
   //--- a faster bias than setup, or a slower entry than setup, inverts the
   //--- whole model; warn but let the user proceed if it is deliberate
   if(PeriodSeconds(InpBiasTF) < PeriodSeconds(InpSetupTF) ||
      PeriodSeconds(InpSetupTF) < PeriodSeconds(InpEntryTF))
      Print("TTLS: warning - expected BiasTF >= SetupTF >= EntryTF, got ",
            TTTfLabel(InpBiasTF), " / ", TTTfLabel(InpSetupTF), " / ",
            TTTfLabel(InpEntryTF));
   if(InpMaxHistoryBars < 200)
      Print("TTLS: warning - MaxHistoryBars below 200 leaves too little context ",
            "for structure to establish itself.");
   return(true);
  }
//+------------------------------------------------------------------+
//| Engine construction. Fails hard if a handle cannot be created -   |
//| running without ATR would silently disable every tolerance.       |
//+------------------------------------------------------------------+
bool InitEngines(void)
  {
   TTStructCfg sc;
   sc.leftBars      = (int)MathMax(1, InpSwingLeftBars);
   sc.rightBars     = (int)MathMax(1, InpSwingRightBars);
   sc.useWickBreaks = InpUseWickBreaks;

   if(!g_stBias.Init(g_sym, InpBiasTF, sc, TTLS_ATR_PERIOD))
      return(false);
   if(!g_stSetup.Init(g_sym, InpSetupTF, sc, TTLS_ATR_PERIOD))
      return(false);
   if(!g_stEntry.Init(g_sym, InpEntryTF, sc, TTLS_ATR_PERIOD))
      return(false);

   TTZoneCfg zc;
   zc.useDemandSupply = InpUseDemandSupply;
   zc.useOrderBlocks  = InpUseOrderBlocks;
   zc.useFVG          = InpUseFVG;
   zc.useBreakers     = InpUseBreakers;
   zc.mode            = (int)InpZoneMode;
   zc.maxActive       = g_maxZones;
   g_zoneBias.Init(g_stBias.Data(), zc);
   g_zoneSetup.Init(g_stSetup.Data(), zc);
   g_zoneEntry.Init(g_stEntry.Data(), zc);

   TTLiqCfg lc;
   lc.eqTolAtr      = InpEqualLevelToleranceATR;
   lc.sweepBufPts   = InpSweepBufferPoints;
   lc.closeBackBars = (int)MathMax(0, InpSweepCloseBackBars);
   lc.proximityPts  = InpSweepProximityPoints;
   g_liq.Init(g_stSetup.Data(), lc);

   g_gov.Init(InpMaxSignalsPerDay, InpMinBarsBetweenSignals);
   return(true);
  }
//+------------------------------------------------------------------+
void InitConfigs(void)
  {
   g_draw.clrBull         = InpColorBull;
   g_draw.clrBear         = InpColorBear;
   g_draw.clrZoneBull     = InpColorZoneBull;
   g_draw.clrZoneBear     = InpColorZoneBear;
   g_draw.clrInvalid      = InpColorInvalid;
   g_draw.clrLiquidity    = InpColorLiquidity;
   g_draw.clrStrongWeak   = InpColorStrongWeak;
   g_draw.clrStructure    = InpColorStructure;
   g_draw.clrText         = InpColorText;
   g_draw.fontSize        = MathMax(6, InpFontSize);
   g_draw.extendZonesBars = MathMax(1, InpExtendZonesBars);
   g_draw.keepSwept       = InpKeepSweptLiquidity;
   g_draw.showMS          = InpShowMS;
   g_draw.showBOS         = InpShowBOS;
   g_draw.showStrongWeak  = InpShowStrongWeak;
   g_draw.showLiquidity   = InpShowLiquidity;
   g_draw.showPanel       = InpShowInfoPanel;
   g_draw.corner          = InpPanelCorner;

   //--- MaxSignalsPerDay / MinBarsBetweenSignals are deliberately NOT mirrored
   //--- here: CSignalGovernor owns them (see InitEngines) and is the only
   //--- thing that enforces them.
   g_filter.useSession            = InpUseSessionFilter;
   g_filter.sessionStartHour      = InpSessionStartHour;
   g_filter.sessionEndHour        = InpSessionEndHour;
   g_filter.avoidMinutes          = InpAvoidHighImpactMinutes;
   g_filter.blackoutCsv           = InpBlackoutTimes;
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   TTDeleteAll();
   ChartRedraw();
  }
//+------------------------------------------------------------------+
//| OnCalculate                                                       |
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
   if(rates_total < 20)
      return(0);
   ArraySetAsSeries(time, true);

   bool rebuild = (prev_calculated == 0);
   int  limit   = rebuild ? rates_total - 1 : rates_total - prev_calculated;
   if(limit < 0)
      limit = 0;
   if(limit > rates_total - 1)
      limit = rates_total - 1;

   ClearRange(limit);

   //--- MTF data safety: a partial read is never carried forward
   if(!UpdateAllEngines(rebuild))
      return(0);

   PaintStateBuffers(limit, time);
   PaintSignals(rates_total, limit, time[rates_total - 1]);

   if(g_dirty)
     {
      RedrawMarkup();
      g_dirty = false;
     }
   UpdatePanel();
   HandleAlerts(rebuild);
   return(rates_total);
  }
//+------------------------------------------------------------------+
void ClearRange(const int limit)
  {
   for(int i = limit; i >= 0; i--)
     {
      BufBuy[i]     = EMPTY_VALUE;
      BufSell[i]    = EMPTY_VALUE;
      BufEntry[i]   = EMPTY_VALUE;
      BufSL[i]      = EMPTY_VALUE;
      BufTP[i]      = EMPTY_VALUE;
      BufQuality[i] = EMPTY_VALUE;
      BufBias[i]    = 0.0;
      BufState[i]   = 0.0;
     }
  }
//+------------------------------------------------------------------+
//| Engine order matters: bias and entry structure must be current    |
//| before the setup timeframe queries them. Both are queried with a  |
//| time bound, so being "ahead" cannot leak future information.      |
//+------------------------------------------------------------------+
bool UpdateAllEngines(const bool rebuild)
  {
   if(!UpdateSimpleTf(g_stBias, g_zoneBias, rebuild))
      return(false);
   if(!UpdateSimpleTf(g_stEntry, g_zoneEntry, rebuild))
      return(false);
   if(!UpdateSetupTf(rebuild))
      return(false);
   return(true);
  }
//+------------------------------------------------------------------+
//| How deep to rebuild one timeframe.                                |
//|                                                                   |
//| MaxHistoryBars counts SETUP timeframe bars; every other timeframe |
//| is given whatever bar count covers the SAME WALL-CLOCK SPAN.      |
//|                                                                   |
//| Applying one bar count to all three was a repaint hole, not just  |
//| a tuning wart. At the defaults it gave EntryTF 2000 M5 bars = 7   |
//| days while the SetupTF loop walked 2000 M15 bars = 20 days, so    |
//| for every SetupTF bar older than 7 days the EntryTF event ring    |
//| was simply empty: FirstShiftAfter() found nothing, the setup sat  |
//| in SWEPT until its protected level broke, and conservative-mode   |
//| signals the live run had fired could not be reproduced by a       |
//| reload. Matching the spans makes the three engines cover the same |
//| stretch of market, which is what the cross-timeframe queries      |
//| already assumed.                                                  |
//+------------------------------------------------------------------+
int TTHistoryBarsFor(const ENUM_TIMEFRAMES tf)
  {
   int setupSec = PeriodSeconds(InpSetupTF);
   int tfSec    = PeriodSeconds(tf);
   if(setupSec <= 0 || tfSec <= 0)
      return(InpMaxHistoryBars);
   long bars = ((long)InpMaxHistoryBars * (long)setupSec) / (long)tfSec;
   //--- the same clamp BeginUpdate() applies, so the caller sees no surprises
   if(bars < 200)   bars = 200;
   if(bars > 20000) bars = 20000;
   return((int)bars);
  }
//+------------------------------------------------------------------+
//| Bias and entry timeframes: structure + zones, no state machine.   |
//+------------------------------------------------------------------+
bool UpdateSimpleTf(CStructureEngine &st, CZoneBook &zb, const bool rebuild)
  {
   int startB = 0;
   if(!st.BeginUpdate(rebuild, TTHistoryBarsFor(st.Tf()), startB))
      return(false);
   if(st.DidReset())
      zb.Reset();
   if(startB < 1)
      return(true);

   for(int b = startB; b >= 1; b--)
     {
      st.PhasePivot(b);
      zb.PhaseUpdateStates(b);
      zb.PhaseScanFVG(b);
      TTStructEvent ev;
      if(st.PhaseBreak(b, ev))
         zb.PhaseBuildFromEvent(b, ev);
     }
   st.EndUpdate(startB);
   g_dirty = true;
   return(true);
  }
//+------------------------------------------------------------------+
//| Setup timeframe: the full pipeline.                               |
//|                                                                   |
//| Per-bar precedence (documented, and identical on a rebuild):      |
//|   0. pending conservative sub-sequences catch up to this bar      |
//|   1. pivot confirmation -> new liquidity pools                    |
//|   2. zone mitigation / invalidation                               |
//|   3. liquidity sweep                                              |
//|   4. structure break -> new zones                                 |
//|   5. outcome tracking for older signals                           |
//|   6. state machine                                                |
//| So when one bar both sweeps liquidity and shifts structure, the   |
//| SWEEP is registered first - the wick takes the stops, then the    |
//| body closes through structure. A setup may therefore advance      |
//| IDLE -> ARMED -> AT_POI -> SWEPT -> SIGNAL on a single bar close. |
//+------------------------------------------------------------------+
bool UpdateSetupTf(const bool rebuild)
  {
   int startB = 0;
   if(!g_stSetup.BeginUpdate(rebuild, TTHistoryBarsFor(InpSetupTF), startB))
      return(false);
   if(g_stSetup.DidReset())
      ResetSetupState();
   if(startB < 1)
     {
      AdvanceConservative(g_bull, TimeCurrent());
      AdvanceConservative(g_bear, TimeCurrent());
      return(true);
     }

   CTfData *d = g_stSetup.Data();
   for(int b = startB; b >= 1; b--)
     {
      datetime bc = d.CloseTime(b);
      AdvanceConservative(g_bull, bc);
      AdvanceConservative(g_bear, bc);

      g_stSetup.PhasePivot(b);
      for(int f = 0; f < g_stSetup.FreshCount(); f++)
        {
         TTSwing s;
         //--- bc is the close of the bar that CONFIRMED the swing, i.e. the
         //--- instant the pool became visible; the pool stores it so a
         //--- historical target query cannot reach for a level nobody could
         //--- have seen yet
         if(g_stSetup.Fresh(f, s))
            g_liq.OnSwingConfirmed(s, d.ATR(b), bc);
        }

      g_zoneSetup.PhaseUpdateStates(b);
      g_zoneSetup.PhaseScanFVG(b);

      TTSweepInfo sw;
      ZeroMemory(sw);
      bool swept = g_liq.PhaseSweep(b, sw);
      if(swept)
         MarkSweptSwing(sw);

      TTStructEvent ev;
      if(g_stSetup.PhaseBreak(b, ev))
         g_zoneSetup.PhaseBuildFromEvent(b, ev);

      TrackOutcomes(b);
      StepSetup(g_bull, b, swept, sw);
      StepSetup(g_bear, b, swept, sw);
     }
   g_stSetup.EndUpdate(startB);

   //--- tail: let a conservative sub-sequence finish on bars that closed
   //--- after the last SetupTF bar, so it is not delayed by a slower cursor
   AdvanceConservative(g_bull, TimeCurrent());
   AdvanceConservative(g_bear, TimeCurrent());
   g_dirty = true;
   return(true);
  }
//+------------------------------------------------------------------+
void ResetSetupState(void)
  {
   g_zoneSetup.Reset();
   g_liq.Reset();
   g_gov.Reset();
   g_trackBull.Reset();
   g_trackBear.Reset();
   ResetCtx(g_bull);
   ResetCtx(g_bear);
   g_bull.bullish   = true;
   g_bear.bullish   = false;
   g_signalCount    = 0;
   //--- both alert watermarks, not just one: leaving the sweep watermark set
   //--- muted the first sweep alert after every rebuild
   g_lastAlertTime  = 0;
   g_lastSweepAlert = 0;
  }
//+------------------------------------------------------------------+
//| Keeps the swing ring's swept flags in step with the pool that     |
//| consumed them, so the panel's unswept count matches the chart.    |
//+------------------------------------------------------------------+
void MarkSweptSwing(const TTSweepInfo &sw)
  {
   CSwingRing *ring = g_stSetup.Swings();
   TTLiqPool p;
   if(!g_liq.PoolById(sw.poolId, p))
      return;
   int i = ring.FindByTime(p.lastTime, p.buySide);
   if(i >= 0)
      ring.MarkSwept(i);
   i = ring.FindByTime(p.firstTime, p.buySide);
   if(i >= 0)
      ring.MarkSwept(i);
  }
//+------------------------------------------------------------------+
void ResetCtx(TTSetupCtx &ctx)
  {
   bool dir = ctx.bullish;
   ZeroMemory(ctx);
   ctx.bullish = dir;
   ctx.state   = SM_IDLE;
   ctx.zoneId  = -1;
  }
//+------------------------------------------------------------------+
void PushState(TTSetupCtx &ctx, const datetime t, const int state)
  {
   if(ctx.bullish)
      g_trackBull.Push(t, state);
   else
      g_trackBear.Push(t, state);
  }

//+------------------------------------------------------------------+
//| State machine, one closed SetupTF bar at a time.                  |
//+------------------------------------------------------------------+
void StepSetup(TTSetupCtx &ctx, const int b, const bool swept, const TTSweepInfo &sw)
  {
   CTfData *d  = g_stSetup.Data();
   datetime bc = d.CloseTime(b);

   //--- a sweep whose extreme is taken out before the setup triggers has
   //--- failed: the reversal never came, so the whole premise is void
   if(ctx.state == SM_SWEPT || ctx.state == SM_PENDING)
     {
      double ext = ctx.bullish ? d.Low(b) : d.High(b);
      bool   bad = ctx.bullish ? (ext < ctx.protectedPrice) : (ext > ctx.protectedPrice);
      if(bad)
         ResetCtx(ctx);
     }

   //--- bias gate: no alignment, no setup
   int want = ctx.bullish ? (int)TT_TREND_BULL : (int)TT_TREND_BEAR;
   if(g_stBias.TrendAt(bc) != want || g_stSetup.TrendAt(bc) != want)
     {
      ResetCtx(ctx);
      PushState(ctx, bc, SM_IDLE);
      return;
     }

   if(ctx.state == SM_IDLE || ctx.state == SM_MISSED)
      ctx.state = SM_ARMED;

   if(ctx.state == SM_ARMED)
      TryArmPoi(ctx, b);

   if(ctx.state == SM_AT_POI)
      TrySweepTrigger(ctx, b, swept, sw);

   if(ctx.state == SM_SWEPT)
      StepAggressive(ctx, b);

   PushState(ctx, bc, ctx.state);
  }
//+------------------------------------------------------------------+
//| ARMED -> AT_POI.                                                  |
//|                                                                   |
//| The nearest live zones are scanned outward from price; the first  |
//| one price has actually traded into arms the trigger. TOUCHED is   |
//| enough - waiting for full mitigation (a close back outside) would |
//| miss every setup where the sweep and the touch share a bar, which |
//| is the normal case on a scalping timeframe.                       |
//+------------------------------------------------------------------+
void TryArmPoi(TTSetupCtx &ctx, const int b)
  {
   CTfData *d   = g_stSetup.Data();
   datetime bc  = d.CloseTime(b);
   double   ref = d.Close(b);

   for(int rank = 0; rank < g_maxZones; rank++)
     {
      TTZone z;
      if(!g_zoneSetup.NearestLive(rank, ref, ctx.bullish, bc, z))
         return;
      if(z.state != TTZS_TOUCHED && z.state != TTZS_MITIGATED)
         continue;                                // not interacted with yet
      ctx.zoneId       = z.id;
      ctx.zoneTop      = z.top;
      ctx.zoneBottom   = z.bottom;
      ctx.zoneUntested = z.untestedExtreme;
      ctx.state        = SM_AT_POI;
      return;
     }
  }
//+------------------------------------------------------------------+
//| AT_POI -> SWEPT.                                                  |
//|                                                                   |
//| A long setup needs SELL-SIDE liquidity taken (a low raided), and  |
//| the raid has to belong to the zone: its extreme must sit inside   |
//| the box or within SweepProximityPoints of it. A sweep in open     |
//| space is not a setup, it is just a wick.                          |
//+------------------------------------------------------------------+
void TrySweepTrigger(TTSetupCtx &ctx, const int b, const bool swept, const TTSweepInfo &sw)
  {
   CTfData *d = g_stSetup.Data();

   //--- the zone failing outright ends the setup
   TTZone z;
   if(g_zoneSetup.ZoneById(ctx.zoneId, z) && z.state == TTZS_INVALID)
     {
      ResetCtx(ctx);
      return;
     }
   if(!swept || sw.buySide == ctx.bullish)
      return;

   double prox   = g_liq.ProximityPrice(b);
   bool   inside = (sw.extreme >= ctx.zoneBottom && sw.extreme <= ctx.zoneTop);
   bool   isNear = (sw.extreme >= ctx.zoneBottom - prox && sw.extreme <= ctx.zoneTop + prox);
   if(!isNear)
      return;

   ctx.state          = SM_SWEPT;
   ctx.sweptBarTime   = sw.doneBarTime;
   ctx.sweptBarClose  = d.CloseTime(b);
   ctx.protectedPrice = sw.extreme;
   ctx.poolPrice      = sw.poolPrice;
   ctx.poolCount      = sw.poolCount;
   ctx.sweepInside    = inside;
   ctx.atrAtSweep     = d.ATR(b);
   ctx.spreadAtSweep  = d.Spread(b);
   ctx.confirmBars    = 0;
   ctx.shiftSearchFrom = 0;
  }
//+------------------------------------------------------------------+
//| Aggressive trigger. Without confirmation it fires on the close of |
//| the sweep bar itself; with confirmation it waits for one candle   |
//| closing in the trade direction, and gives up after a few bars     |
//| rather than carrying a stale setup forward.                       |
//+------------------------------------------------------------------+
void StepAggressive(TTSetupCtx &ctx, const int b)
  {
   if(InpEntryMode == ENTRY_CONSERVATIVE)
      return;
   CTfData *d = g_stSetup.Data();

   if(!InpRequireConfirmationCandle)
     {
      if(d.Time(b) == ctx.sweptBarTime)
         FireSignal(ctx, true, d.Close(b), d.Time(b), InpSetupTF);
      return;
     }

   if(d.Time(b) <= ctx.sweptBarTime)
      return;                                     // the sweep bar cannot confirm itself
   ctx.confirmBars++;
   bool ok = ctx.bullish ? (d.Close(b) > d.Open(b)) : (d.Close(b) < d.Open(b));
   if(ok)
     {
      FireSignal(ctx, true, d.Close(b), d.Time(b), InpSetupTF);
      return;
     }
   if(ctx.confirmBars >= TTLS_MAX_CONFIRM_BARS)
      ResetCtx(ctx);
  }

//+------------------------------------------------------------------+
//| Conservative sub-sequence.                                        |
//|                                                                   |
//| After the sweep, wait on EntryTF for a structure break in the     |
//| trade direction, build the zone behind that break, then wait for  |
//| price to come back into it. Both MS and BOS count as the shift:   |
//| if the entry timeframe already trended our way an MS would never  |
//| print and the mode would silently never trigger.                  |
//|                                                                   |
//| Advanced up to `upto` only, so a history rebuild walks exactly    |
//| the same bars in the same order as the live run did.              |
//+------------------------------------------------------------------+
void AdvanceConservative(TTSetupCtx &ctx, const datetime upto)
  {
   if(InpEntryMode == ENTRY_AGGRESSIVE)
      return;
   if(ctx.state != SM_SWEPT && ctx.state != SM_PENDING)
      return;

   if(ctx.state == SM_SWEPT)
     {
      datetime after = (ctx.shiftSearchFrom > 0) ? ctx.shiftSearchFrom
                                                 : (datetime)((long)ctx.sweptBarClose - 1);
      TTStructEvent ev;
      if(!g_stEntry.Events().FirstShiftAfter(after, upto, ctx.bullish, ev))
         return;
      ctx.shiftSearchFrom = ev.breakClose;       // a rejected shift is never retried
      TTZone z;
      if(!ResolveShiftZone(ctx, ev, z))
         return;                                 // no zone behind it - wait for the next
      if(!ArmPending(ctx, ev, z))
         return;
     }
   ScanPullback(ctx, upto);
  }
//+------------------------------------------------------------------+
//| The zone behind an LTF shift.                                     |
//|                                                                   |
//| FindByEvent() matches on identity - the zone still carrying this  |
//| break's event time - which is right when the break built its own  |
//| box. But CZoneBook::AddZone MERGES a new box into an overlapping  |
//| live one and the survivor keeps the OLDER event time, so nothing  |
//| carries this event at all. That is not a rare corner: two breaks  |
//| in one impulse routinely walk back to the same origin candle and  |
//| produce an identical box. The old code returned false there, and  |
//| because shiftSearchFrom had already advanced past the shift, the  |
//| setup was discarded outright - conservative mode quietly dropped  |
//| a large share of its entries.                                     |
//|                                                                   |
//| So: try identity first, then fall back to the nearest live zone   |
//| on the ORIGIN side of the break, as the book stood when the break |
//| closed. That is the merged box in practice, and the asOf bound    |
//| keeps the fallback free of hindsight.                             |
//+------------------------------------------------------------------+
bool ResolveShiftZone(TTSetupCtx &ctx, const TTStructEvent &ev, TTZone &z)
  {
   if(g_zoneEntry.FindByEvent(ev.breakTime, ctx.bullish, z))
      return(true);

   for(int rank = 0; rank < g_maxZones; rank++)
     {
      TTZone c;
      if(!g_zoneEntry.NearestLive(rank, ev.price, ctx.bullish, ev.breakClose, c))
         break;
      //--- demand must sit at or below the level that broke, supply at or above
      if(ctx.bullish ? (c.bottom <= ev.price) : (c.top >= ev.price))
        {
         z = c;
         return(true);
        }
     }
   return(false);
  }
//+------------------------------------------------------------------+
//| Arms a pending entry at the proximal edge of the LTF shift zone.  |
//| The provisional target is stored so the "price reached the target |
//| before it ever came back" case can be marked MISSED rather than   |
//| chased.                                                           |
//+------------------------------------------------------------------+
bool ArmPending(TTSetupCtx &ctx, const TTStructEvent &ev, const TTZone &z)
  {
   double   entry = ctx.bullish ? z.top : z.bottom;
   double   tp    = 0.0;
   datetime asOf  = ev.breakClose;
   if(!ResolveTarget(ctx, entry, asOf, tp))
      return(false);

   ctx.shiftTime    = ev.breakTime;
   ctx.ltfTop       = z.top;
   ctx.ltfBottom    = z.bottom;
   ctx.pendingEntry = entry;
   ctx.pendingTp    = tp;
   ctx.scanFrom     = ev.breakTime;
   ctx.pullbackBars = 0;
   ctx.state        = SM_PENDING;
   PushState(ctx, asOf, SM_PENDING);
   return(true);
  }
//+------------------------------------------------------------------+
//| Walks EntryTF bars after the shift looking for the pullback.      |
//| Progress is stored in ctx.scanFrom, so every bar is examined at   |
//| most once no matter how often this is called.                     |
//+------------------------------------------------------------------+
void ScanPullback(TTSetupCtx &ctx, const datetime upto)
  {
   int idx = iBarShift(g_sym, InpEntryTF, ctx.scanFrom, false);
   if(idx < 1)
      return;

   for(int i = idx - 1; i >= 1; i--)
     {
      MqlRates r;
      if(!TTGetBar(g_sym, InpEntryTF, i, r))
         return;
      datetime bc = (datetime)((long)r.time + PeriodSeconds(InpEntryTF));
      if(bc > upto)
         return;
      ctx.scanFrom = r.time;
      ctx.pullbackBars++;

      //--- the protected extreme going is fatal wherever we are in the sequence
      double ext = ctx.bullish ? r.low : r.high;
      if(ctx.bullish ? (ext < ctx.protectedPrice) : (ext > ctx.protectedPrice))
        {
         ResetCtx(ctx);
         PushState(ctx, bc, SM_IDLE);
         return;
        }
      //--- target reached without us: the move is spent, do not chase it
      if(ctx.bullish ? (r.high >= ctx.pendingTp) : (r.low <= ctx.pendingTp))
        {
         MarkMissed(ctx, bc);
         return;
        }
      //--- pullback into the shift zone
      if(r.high >= ctx.ltfBottom && r.low <= ctx.ltfTop)
        {
         FireSignal(ctx, false, ctx.pendingEntry, r.time, InpEntryTF);
         return;
        }
      if(ctx.pullbackBars >= InpConservativeExpiryBars)
        {
         MarkMissed(ctx, bc);
         return;
        }
     }
  }
//+------------------------------------------------------------------+
void MarkMissed(TTSetupCtx &ctx, const datetime t)
  {
   bool bullish = ctx.bullish;
   PushState(ctx, t, SM_MISSED);
   ResetCtx(ctx);
   ctx.state = SM_MISSED;
   //--- log live misses only; a 2000-bar rebuild must not flood the journal
   if(t >= (datetime)((long)TimeCurrent() - (long)PeriodSeconds(InpSetupTF) * 5))
      PrintFormat("TTLS: %s setup MISSED at %s (no pullback within %d %s bars)",
                  bullish ? "long" : "short", TimeToString(t),
                  InpConservativeExpiryBars, TTTfLabel(InpEntryTF));
  }

//+------------------------------------------------------------------+
//| Target resolution. Falls back to the nearest unswept opposing     |
//| pool whenever the chosen mode cannot produce a level beyond the   |
//| entry - a scalp without a liquidity target is not a scalp.        |
//+------------------------------------------------------------------+
bool ResolveTarget(TTSetupCtx &ctx, const double entry, const datetime asOf, double &tp)
  {
   double w = 0.0;
   //--- the weak level AS IT STOOD at asOf, never today's value
   bool hasWeak = g_stBias.WeakPriceAt(asOf, w);
   if(InpTargetMode == TARGET_HTF_WEAK && hasWeak)
     {
      if(ctx.bullish ? (w > entry) : (w < entry))
        {
         tp = w;
         return(true);
        }
     }
   if(InpTargetMode == TARGET_NEXT_OPPOSING_POI)
     {
      for(int rank = 0; rank < g_maxZones; rank++)
        {
         TTZone z;
         if(!g_zoneSetup.NearestLive(rank, entry, !ctx.bullish, asOf, z))
            break;
         double edge = ctx.bullish ? z.bottom : z.top;
         if(ctx.bullish ? (edge > entry) : (edge < entry))
           {
            tp = edge;
            return(true);
           }
        }
     }
   TTLiqPool p;
   if(g_liq.NearestUnswept(entry, ctx.bullish, asOf, p))
     {
      tp = p.price;
      return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
//| Builds the three levels. Returns false when the geometry is not   |
//| tradeable (inverted stop, no target, target on the wrong side).   |
//+------------------------------------------------------------------+
bool BuildLevels(TTSetupCtx &ctx, const double entry, const datetime asOf, TTSignal &sig)
  {
   double pt  = TTPointSize(g_sym);
   double buf = TTStopBuffer(g_sym, ctx.atrAtSweep, InpStopBufferPoints);
   //--- gold's spread widens brutally at rollover; folding the bar's own
   //--- recorded spread into the stop keeps it out of the noise
   double spr = (double)ctx.spreadAtSweep * pt;

   double sl = ctx.bullish ? (ctx.protectedPrice - buf - spr)
                           : (ctx.protectedPrice + buf + spr);
   double tp = 0.0;
   if(!ResolveTarget(ctx, entry, asOf, tp))
      return(false);

   if(ctx.bullish && (sl >= entry || tp <= entry))
      return(false);
   if(!ctx.bullish && (sl <= entry || tp >= entry))
      return(false);

   TTEnforceStopsLevel(g_sym, entry, ctx.bullish, sl, tp);

   sig.entry = NormalizeDouble(entry, g_digits);
   sig.sl    = NormalizeDouble(sl, g_digits);
   sig.tp    = NormalizeDouble(tp, g_digits);
   sig.tp2   = 0.0;
   double w = 0.0;
   if(g_stBias.WeakPriceAt(asOf, w))
     {
      if(ctx.bullish ? (w > sig.tp) : (w < sig.tp))
         sig.tp2 = NormalizeDouble(w, g_digits);
     }
   sig.rr = TTRewardRisk(sig.entry, sig.sl, sig.tp);
   return(sig.rr > 0.0);
  }
//+------------------------------------------------------------------+
//| Every gate a setup must clear. All of them key on the SIGNAL      |
//| BAR's own time and on data recorded on that bar, never on the     |
//| live clock or the live spread - that is what makes a rebuild      |
//| reproduce the original decisions exactly.                         |
//+------------------------------------------------------------------+
bool PassesFilters(const TTSignal &sig)
  {
   if(!TTSessionOk(sig.barTime, g_filter))
      return(false);
   if(!TTBlackoutOk(sig.barTime, g_filter))
      return(false);
   if(sig.rr < InpMinRR)
      return(false);
   //--- throttling is measured in SetupTF bars for both entry modes
   if(!g_gov.Allow(sig.barTime, PeriodSeconds(InpSetupTF)))
      return(false);
   return(true);
  }
//+------------------------------------------------------------------+
//| Commits a signal: levels, filters, score, size, storage.          |
//| Whatever the outcome the setup is consumed - a trigger that was   |
//| filtered out does not stay armed waiting for a second chance.     |
//+------------------------------------------------------------------+
void FireSignal(TTSetupCtx &ctx, const bool aggressive, const double entry,
                const datetime barTime, const ENUM_TIMEFRAMES tf)
  {
   datetime bc = (datetime)((long)barTime + PeriodSeconds(tf));

   TTSignal sig;
   ZeroMemory(sig);
   sig.barTime    = barTime;
   sig.closeTime  = bc;
   sig.tf         = tf;
   sig.bullish    = ctx.bullish;
   sig.aggressive = aggressive;
   sig.outcome    = 0;

   bool ok = BuildLevels(ctx, entry, bc, sig);
   if(ok)
     {
      TTFilterCfg sessionScore = g_filter;
      sessionScore.useSession  = true;            // score the session even when not filtering
      //--- read the alignment back rather than passing a literal true: the bias
      //--- gate should guarantee it, and if it ever stops doing so the score
      //--- should say so instead of awarding the points regardless
      int  want    = ctx.bullish ? (int)TT_TREND_BULL : (int)TT_TREND_BEAR;
      bool aligned = (g_stBias.TrendAt(bc) == want && g_stSetup.TrendAt(bc) == want);
      sig.quality = TTQualityScore(aligned, ctx.sweepInside, ctx.zoneUntested,
                                   ctx.poolCount > 1, sig.rr,
                                   TTSessionOk(barTime, sessionScore));
      sig.lots = InpShowLotSize
                 ? TTLotSize(g_sym, InpAccountRiskPercent, MathAbs(sig.entry - sig.sl))
                 : 0.0;
      if(SpreadGateOk(ctx) && PassesFilters(sig))
        {
         StoreSignal(sig);
         g_gov.Register(sig.barTime);
         PushState(ctx, bc, SM_SIGNAL);
        }
     }
   ResetCtx(ctx);
   PushState(ctx, (datetime)((long)bc + 1), SM_IDLE);
  }
//+------------------------------------------------------------------+
//| Spread gate. Uses the spread recorded on the sweep bar so the     |
//| decision is reproducible; the live spread only drives the panel.  |
//+------------------------------------------------------------------+
bool SpreadGateOk(const TTSetupCtx &ctx)
  {
   if(InpMaxSpreadPoints <= 0.0)
      return(true);
   return((double)ctx.spreadAtSweep <= InpMaxSpreadPoints);
  }
//+------------------------------------------------------------------+
void StoreSignal(const TTSignal &sig)
  {
   if(g_signalCount >= TTLS_MAX_SIGNALS)
     {
      for(int i = 1; i < g_signalCount; i++)
         g_signals[i - 1] = g_signals[i];
      g_signalCount--;
     }
   g_signals[g_signalCount] = sig;
   g_signalCount++;
   //--- a conservative signal can fire from the tail catch-up, outside the
   //--- SetupTF bar loop that normally raises this. Without it the arrow and
   //--- the SL/TP boxes stayed invisible until the next SetupTF bar closed,
   //--- even though the buffers and the alert had already gone out.
   g_dirty = true;
  }
//+------------------------------------------------------------------+
//| Resolves what happened to earlier signals using SetupTF bars.     |
//| A bar that touches both levels is scored as a loss - the pessimistic|
//| reading, since intrabar order is unknowable from bar data.        |
//+------------------------------------------------------------------+
void TrackOutcomes(const int b)
  {
   CTfData *d  = g_stSetup.Data();
   datetime bt = d.Time(b);
   double   hi = d.High(b);
   double   lo = d.Low(b);

   for(int i = g_signalCount - 1; i >= 0; i--)
     {
      if(g_signals[i].outcome != 0)
         continue;
      if(g_signals[i].closeTime > bt)
         continue;
      bool hitSl = g_signals[i].bullish ? (lo <= g_signals[i].sl) : (hi >= g_signals[i].sl);
      bool hitTp = g_signals[i].bullish ? (hi >= g_signals[i].tp) : (lo <= g_signals[i].tp);
      if(hitSl)
         g_signals[i].outcome = 2;
      else
         if(hitTp)
            g_signals[i].outcome = 1;
     }
  }

//+------------------------------------------------------------------+
//| Buffer painting                                                   |
//+------------------------------------------------------------------+
void PaintStateBuffers(const int limit, const datetime &time[])
  {
   int sec = PeriodSeconds(PERIOD_CURRENT);
   for(int i = limit; i >= 0; i--)
     {
      datetime bc = (datetime)((long)time[i] + sec);
      int bias  = g_stBias.TrendAt(bc);
      int setup = g_stSetup.TrendAt(bc);
      BufBias[i] = (bias != 0 && bias == setup) ? (double)bias : 0.0;

      //--- the bias gate means at most one direction is ever live, so the
      //--- two per-direction tracks collapse into one buffer without loss
      int sBull = g_trackBull.ValueAt(bc);
      int sBear = g_trackBear.ValueAt(bc);
      BufState[i] = (double)(sBull != (int)SM_IDLE ? sBull : sBear);
     }
  }
//+------------------------------------------------------------------+
//| Signals are repainted from the stored list rather than recomputed,|
//| so a bar that scrolled through the recalculated window keeps the  |
//| exact value it was first given.                                   |
//|                                                                   |
//| Only the bars ClearRange() just wiped need repainting, and signals |
//| are stored oldest-first, so walking backwards lets us stop as soon |
//| as we leave that window instead of re-resolving all of history on  |
//| every tick.                                                        |
//+------------------------------------------------------------------+
void PaintSignals(const int rates_total, const int limit, const datetime oldestBar)
  {
   for(int k = g_signalCount - 1; k >= 0; k--)
     {
      //--- a signal older than the loaded chart history has no bar to sit on
      if(g_signals[k].closeTime <= oldestBar)
         return;
      int idx = SignalChartIndex(g_signals[k]);
      if(idx < 0 || idx >= rates_total)
         continue;
      if(idx > limit)
         return;                                  // outside the recalculated window
      if(g_signals[k].bullish)
         BufBuy[idx] = g_signals[k].entry;
      else
         BufSell[idx] = g_signals[k].entry;
      BufEntry[idx]   = g_signals[k].entry;
      BufSL[idx]      = g_signals[k].sl;
      BufTP[idx]      = g_signals[k].tp;
      BufQuality[idx] = (double)g_signals[k].quality;
     }
  }
//+------------------------------------------------------------------+
//| Chart bar that owns a signal: the bar containing the last instant |
//| of the bar that fired it. On its own timeframe that is the firing |
//| bar itself; on any other it is whichever bar was live then.       |
//+------------------------------------------------------------------+
int SignalChartIndex(const TTSignal &sig)
  {
   return(iBarShift(g_sym, PERIOD_CURRENT, (datetime)((long)sig.closeTime - 1), false));
  }

//+------------------------------------------------------------------+
//| Markup                                                            |
//+------------------------------------------------------------------+
void RedrawMarkup(void)
  {
   TTRefreshTheme();                              // one background read per redraw
   TTDeleteAll();
   //--- the scope tags keep the two books' object names apart when a user runs
   //--- BiasTF == SetupTF; zone ids are per-book and would otherwise collide
   DrawTfMarkup(g_stBias, g_zoneBias, InpBiasTF, "B", true);
   DrawTfMarkup(g_stSetup, g_zoneSetup, InpSetupTF, "S", false);
   DrawLiquidity();
   DrawSignals();
   ChartRedraw();
  }
//+------------------------------------------------------------------+
void DrawTfMarkup(CStructureEngine &st, CZoneBook &zb, const ENUM_TIMEFRAMES tf,
                  const string scope, const bool withStrongWeak)
  {
   CEventRing *ev = st.Events();
   int n = (int)MathMin(ev.Count(), TTLS_DRAW_MAX_EVENTS);
   for(int i = 0; i < n; i++)
     {
      TTStructEvent e;
      if(ev.Get(i, e))
         TTDrawStructEvent(e, tf, scope, g_draw);
     }
   DrawZonesFor(zb, tf, scope, true);
   DrawZonesFor(zb, tf, scope, false);
   if(withStrongWeak)
      TTDrawStrongWeak(tf, st.HasStrong(), st.StrongPrice(), st.StrongTime(),
                       st.StrongIsLow(), st.HasWeak(), st.WeakPrice(), st.WeakTime(),
                       st.WeakIsHigh(), g_draw);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Zone rendering deliberately mirrors the ENGINE's view rather than |
//| the book's full contents. Only the nearest MaxActiveZones per     |
//| direction can ever arm a setup, so drawing the other forty-odd    |
//| mapped zones - each stretched to the current bar - buried the     |
//| chart under overlapping boxes and showed levels that could not    |
//| produce a signal. Failed zones stay on for a while, greyed, so    |
//| it is still visible WHY a level stopped working.                  |
//+------------------------------------------------------------------+
void DrawZonesFor(CZoneBook &zb, const ENUM_TIMEFRAMES tf, const string scope,
                  const bool bullish)
  {
   double   px  = SymbolInfoDouble(g_sym, SYMBOL_BID);
   datetime now = TimeCurrent();
   if(px <= 0.0)
      return;

   for(int rank = 0; rank < g_maxZones; rank++)
     {
      TTZone z;
      if(!zb.NearestLive(rank, px, bullish, now, z))
         break;
      TTDrawZone(z, scope, g_draw);
     }

   //--- recently invalidated zones, capped so history cannot pile up
   datetime cutoff = (datetime)((long)now - (long)PeriodSeconds(tf) * g_draw.extendZonesBars);
   int shown = 0;
   for(int i = zb.Count() - 1; i >= 0 && shown < TTLS_DRAW_MAX_DEAD_ZONES; i--)
     {
      TTZone z;
      if(!zb.Get(i, z))
         continue;
      if(z.state != TTZS_INVALID || z.bullish != bullish)
         continue;
      if(z.invalidTime < cutoff)
         continue;
      TTDrawZone(z, scope, g_draw);
      shown++;
     }
  }
//+------------------------------------------------------------------+
//| Liquidity was the one renderer with no ceiling: up to 512 pools,  |
//| two objects each, deleted and recreated on every new bar. Events, |
//| signals and dead zones are all capped - this now matches them and |
//| draws the newest pools, which are the ones still in play.         |
//+------------------------------------------------------------------+
void DrawLiquidity(void)
  {
   int from = (int)MathMax(0, g_liq.Count() - TTLS_DRAW_MAX_LIQUIDITY);
   for(int i = from; i < g_liq.Count(); i++)
     {
      TTLiqPool p;
      if(g_liq.Get(i, p))
         TTDrawLiquidity(p, InpSetupTF, g_draw);
     }
  }
//+------------------------------------------------------------------+
void DrawSignals(void)
  {
   int chartBars = Bars(g_sym, PERIOD_CURRENT);
   if(chartBars < 2)
      return;
   //--- a signal predating the loaded chart history has no bar to anchor to;
   //--- iBarShift would clamp it onto the oldest bar and draw it in the wrong place
   datetime oldest = iTime(g_sym, PERIOD_CURRENT, chartBars - 1);

   int from = (int)MathMax(0, g_signalCount - TTLS_DRAW_MAX_SIGNALS);
   for(int k = from; k < g_signalCount; k++)
     {
      if(oldest > 0 && g_signals[k].closeTime <= oldest)
         continue;
      int idx = SignalChartIndex(g_signals[k]);
      if(idx < 0)
         continue;
      datetime anchor = iTime(g_sym, PERIOD_CURRENT, idx);
      if(anchor == 0)
         continue;
      TTDrawSignal(g_signals[k], anchor, g_draw, g_digits);
     }
  }
//+------------------------------------------------------------------+
string StateWord(const int s)
  {
   switch(s)
     {
      case SM_ARMED:   return("ARMED");
      case SM_AT_POI:  return("AT_POI");
      case SM_SWEPT:   return("SWEPT");
      case SM_PENDING: return("PENDING");
      case SM_SIGNAL:  return("SIGNAL");
      case SM_MISSED:  return("MISSED");
     }
   return("IDLE");
  }
//+------------------------------------------------------------------+
void UpdatePanel(void)
  {
   datetime now = TimeCurrent();
   //--- HistorySelect is expensive; once a minute is plenty for a guardrail
   if(InpMaxDailyLossPercent > 0.0 && now - g_lastLossCheck >= 60)
     {
      g_lossBreached  = TTDailyLossBreached(InpMaxDailyLossPercent, g_lossPct);
      g_lastLossCheck = now;
     }
   if(!InpShowInfoPanel)
      return;

   TTPanelInfo info;
   info.symbol            = g_sym;
   info.biasTfLabel       = TTTfLabel(InpBiasTF);
   info.setupTfLabel      = TTTfLabel(InpSetupTF);
   info.biasTrend         = g_stBias.Trend();
   info.setupTrend        = g_stSetup.Trend();
   info.bullState         = StateWord(g_bull.state);
   info.bearState         = StateWord(g_bear.state);
   info.zonesBull         = g_zoneSetup.LiveCount(true, now);
   info.zonesBear         = g_zoneSetup.LiveCount(false, now);
   info.zonesArmable      = g_maxZones;
   info.liquidityUnswept  = g_liq.UnsweptCount(now);
   info.signalsToday      = g_gov.CountOn(now);
   info.spreadPoints      = TTSpreadPoints(g_sym);
   info.dailyLossBreached = g_lossBreached;

   info.lastResult  = "-";
   info.lastQuality = 0;
   info.lastLots    = 0.0;
   if(g_signalCount > 0)
     {
      TTSignal s = g_signals[g_signalCount - 1];
      info.lastQuality = s.quality;
      info.lastLots    = s.lots;
      string dir = s.bullish ? "LONG" : "SHORT";
      string res = "open";
      if(s.outcome == 1) res = "TP";
      if(s.outcome == 2) res = "SL";
      info.lastResult = dir + " " + res;
     }
   info.note = g_lossBreached
               ? StringFormat("DAILY LOSS %.2f%% - alerts muted", g_lossPct)
               : StringFormat("%s entry / %s target",
                              InpEntryMode == ENTRY_AGGRESSIVE ? "AGG" :
                              (InpEntryMode == ENTRY_CONSERVATIVE ? "CON" : "BOTH"),
                              InpTargetMode == TARGET_NEAREST_INTERNAL ? "pool" :
                              (InpTargetMode == TARGET_HTF_WEAK ? "HTF weak" : "opp POI"));
   TTDrawPanel(info, g_draw);
  }
//+------------------------------------------------------------------+
//| Alerts fire once, for freshly closed signals only. A history      |
//| rebuild silently fast-forwards the watermark so reloading a chart |
//| never replays weeks of alerts.                                    |
//+------------------------------------------------------------------+
void HandleAlerts(const bool rebuild)
  {
   //--- AlertOncePerSetup == false additionally announces a setup the moment
   //--- liquidity is taken, before the entry trigger resolves
   if(!InpAlertOncePerSetup && !rebuild && !g_lossBreached)
      AlertOnSweep();

   if(g_signalCount <= 0)
      return;
   TTSignal s = g_signals[g_signalCount - 1];
   if(s.closeTime <= g_lastAlertTime)
      return;
   g_lastAlertTime = s.closeTime;
   if(rebuild || g_lossBreached)
      return;                                     // watermark moved, but stay quiet

   string msg = StringFormat("%s %s %s @ %s  SL %s  TP %s  RR %.2f  Q%d",
                             g_sym, TTTfLabel(s.tf),
                             s.bullish ? "BUY" : "SELL",
                             DoubleToString(s.entry, g_digits),
                             DoubleToString(s.sl, g_digits),
                             DoubleToString(s.tp, g_digits),
                             s.rr, s.quality);
   if(InpAlertPopup)
      Alert("TTLS: " + msg);
   if(InpAlertPush)
      SendNotification("TTLS: " + msg);
   if(InpAlertEmail)
      SendMail("TT_LiquidityScalper signal", msg);
  }
//+------------------------------------------------------------------+
//| Heads-up alert on a fresh sweep. Deduplicated on the sweep bar so |
//| a setup sitting in SWEPT for several bars only announces once.    |
//+------------------------------------------------------------------+
void AlertOnSweep(void)
  {
   datetime t = 0;
   bool     bull = false;
   if(g_bull.state == SM_SWEPT || g_bull.state == SM_PENDING)
     {
      t    = g_bull.sweptBarClose;
      bull = true;
     }
   else
      if(g_bear.state == SM_SWEPT || g_bear.state == SM_PENDING)
         t = g_bear.sweptBarClose;
   if(t == 0 || t <= g_lastSweepAlert)
      return;
   g_lastSweepAlert = t;

   string msg = StringFormat("TTLS: %s %s liquidity swept - %s setup arming",
                             g_sym, TTTfLabel(InpSetupTF), bull ? "LONG" : "SHORT");
   if(InpAlertPopup)
      Alert(msg);
   if(InpAlertPush)
      SendNotification(msg);
  }
//+------------------------------------------------------------------+
