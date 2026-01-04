//+------------------------------------------------------------------+
//|                         DowTheorySwingStructure_Enhanced_v10.mq4 |
//|                           Dow Theory HH/HL/LH/LL + FVG + AutoFib |
//|                         Version 10.0 - Optimized & Feature Rich  |
//+------------------------------------------------------------------+
#property copyright "Enhanced Custom Indicator v10.0 SMC"
#property link      ""
#property version   "10.00"
#property strict
#property indicator_chart_window
#property indicator_separate_window
#property indicator_buffers 1
#property indicator_color1 DodgerBlue
#property indicator_width1 2
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_level1 30
#property indicator_level2 70
#property indicator_levelcolor DarkGray
#property indicator_levelstyle STYLE_DOT

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input string      Section1           = "=== Swing Detection Settings ===";
input int         SwingLookback      = 7;
input int         MinSwingBars       = 12;
input int         MaxBarsToAnalyze   = 500;
input bool        UseATRFilter       = true;
input double      ATRMultiplier      = 0.8;
input int         ATR_Period         = 14;
input bool        RequireSwingAlternation = true;
input bool        UseBodyConfirmation = true;
input double      EqualSwingTolerance = 0.15;
input int         MinSwingStrength   = 2;

input string      Section1b          = "=== Enhanced Accuracy Settings ===";
input bool        UseVolumeConfirmation = true;       // Require volume spike at swings
input double      VolumeMultiplier   = 1.2;           // Volume must be X times average
input bool        UseWickRejection   = true;          // Prefer wicks showing rejection
input double      MinWickRatio       = 0.25;          // Min wick as % of candle range
input bool        UseMomentumFilter  = true;          // RSI momentum confirmation
input int         MomentumLookback   = 5;             // Bars to check momentum
input bool        RequireCleanBreak  = true;          // Cleaner swing breaks
input double      CleanBreakATRMult  = 0.3;           // ATR multiplier for clean break
input bool        UseSwingCluster    = true;          // Detect swing clusters/zones
input double      ClusterATRMult     = 0.5;           // ATR mult for cluster detection
input int         MinConfluenceScore = 3;             // Min score for valid signal (1-5)

input string      Section2           = "=== RSI Settings ===";
input int         RSI_Period         = 14;
input bool        ShowRSI_TrendLines = true;
input bool        ShowRSI_Divergence = true;
input bool        ShowHiddenDivergence = true;
input int         DivergenceMinBars  = 8;
input int         DivergenceMaxBars  = 50;            // Max bars for divergence
input double      MinRSIDivergence   = 5.0;           // Min RSI difference for divergence

input string      Section3           = "=== Swing Label Colors ===";
input color       HH_Color           = clrLime;
input color       HL_Color           = clrGreen;
input color       LH_Color           = clrRed;
input color       LL_Color           = clrMaroon;
input color       BullishTrendColor  = clrLime;
input color       BearishTrendColor  = clrRed;

input string      Section4           = "=== Candle Colors ===";
input bool        ChangeCandleColors = true;
input color       BullishCandleColor = clrWhite;
input color       BearishCandleColor = clrRed;
input color       BullishWickColor   = clrWhite;
input color       BearishWickColor   = clrRed;

input string      Section5           = "=== Panel Settings ===";
input bool        ShowSignalPanel    = true;
input int         PanelX             = 10;
input int         PanelY             = 50;
input int         PanelWidth         = 320;
input color       PanelBgColor       = C'25,25,35';
input color       PanelBorderColor   = C'60,60,80';
input color       PanelTextColor     = clrWhite;
input color       BuySignalColor     = clrLime;
input color       SellSignalColor    = clrRed;
input color       NeutralColor       = clrGray;
input int         PanelFontSize      = 9;

input string      Section6           = "=== Neckline & BOS Settings ===";
input bool        ShowNecklines      = true;
input bool        ShowBOS            = true;
input bool        RequireBOSBodyClose = true;
input int         BOSConfirmationBars = 2;
input double      BOSMinATRBreak     = 0.3;           // Min ATR break for BOS
input bool        RequireBOSRetest   = false;         // Wait for retest after BOS
input color       BullishBOSColor    = clrLime;
input color       BearishBOSColor    = clrRed;
input color       NecklineColor      = clrGold;
input int         NecklineWidth      = 2;
input ENUM_LINE_STYLE NecklineStyle = STYLE_DASH;

input string      Section7           = "=== Display Settings ===";
input int         FontSize           = 10;
input bool        ShowStructureLines = true;
input bool        ShowSwingPriceLabels = false;
input bool        ShowConfluenceZones = true;         // Show support/resistance zones

input string      Section8           = "=== Chart Settings ===";
input bool        CleanChartOnLoad   = true;
input bool        SwitchToCandlestick = true;
input bool        RemoveGrid         = true;
input int         ChartZoomLevel     = 3;

input string      Section9           = "=== MTF Entry Settings ===";
input bool        EnableMTFEntry     = true;
input int         MTF_SwingLookback  = 5;
input int         MTF_MinSwingBars   = 6;
input double      MTF_ATRMultiplier  = 0.5;
input bool        MTF_RequireAlignment = true;        // LTF must align with HTF
input bool        MTF_UseRSIFilter   = true;          // Filter entries by RSI
input double      MTF_RSI_Oversold   = 35;
input double      MTF_RSI_Overbought = 65;

input string      Section10          = "=== Alert Settings ===";
input bool        EnableAlerts       = true;
input bool        AlertOnBOS         = true;
input bool        AlertOnDivergence  = true;
input bool        AlertOnMTFEntry    = true;
input bool        SendPushNotification = false;

input string      Section11          = "=== SMC / FVG Settings ===";
input bool        ShowFVG            = true;
input color       BullishFVGColor    = C'0,40,0';     // Dark Green
input color       BearishFVGColor    = C'40,0,0';     // Dark Red
input bool        ExtendFVG          = false;
input bool        ShowAutoFib        = true;          // Show Auto Fib on current trend

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum SWING_TYPE { SWING_NONE = 0, SWING_HIGH = 1, SWING_LOW = 2 };
enum SWING_LABEL { LABEL_NONE = 0, LABEL_HH = 1, LABEL_HL = 2, LABEL_LH = 3, LABEL_LL = 4, LABEL_EH = 5, LABEL_EL = 6 };
enum MARKET_PHASE { PHASE_UNKNOWN = 0, PHASE_ACCUMULATION = 1, PHASE_MARKUP = 2, PHASE_DISTRIBUTION = 3, PHASE_DECLINE = 4 };
enum TREND_STATE { TREND_UNKNOWN = 0, TREND_BULLISH = 1, TREND_BEARISH = 2, TREND_RANGING = 3 };
enum DIVERGENCE_TYPE { DIV_NONE = 0, DIV_REGULAR_BULLISH = 1, DIV_REGULAR_BEARISH = 2, DIV_HIDDEN_BULLISH = 3, DIV_HIDDEN_BEARISH = 4 };
enum SIGNAL_TYPE { SIG_NONE = 0, SIG_BUY_STRONG = 1, SIG_BUY_MODERATE = 2, SIG_BUY_WEAK = 3, SIG_SELL_STRONG = 4, SIG_SELL_MODERATE = 5, SIG_SELL_WEAK = 6, SIG_WAIT = 7 };
enum MTF_ENTRY_TYPE { MTF_NONE = 0, MTF_BUY_NOW = 1, MTF_BUY_PENDING = 2, MTF_SELL_NOW = 3, MTF_SELL_PENDING = 4, MTF_WAIT = 5 };

//+------------------------------------------------------------------+
//| Structure for Swing Points                                       |
//+------------------------------------------------------------------+
struct SwingPoint
{
   int         bar;
   double      price;
   double      rsi;
   double      atr;
   double      volume;
   datetime    time;
   SWING_TYPE  type;
   SWING_LABEL label;
   bool        isValid;
   bool        isBroken;
   int         strength;
   double      volumeRatio;       // Volume vs average
   double      wickRatio;         // Wick rejection ratio
   int         confluenceScore;   // Overall quality score
   bool        hasVolumeSpike;
   bool        hasWickRejection;
   bool        hasMomentum;
};

//+------------------------------------------------------------------+
//| Structure for Trading Signals                                     |
//+------------------------------------------------------------------+
struct TradingSignal
{
   SIGNAL_TYPE type;
   string      description;
   double      entryPrice;
   double      stopLoss;
   double      takeProfit;
   bool        hasDivergence;
   string      divergenceType;
   double      necklineLevel;
   bool        bosConfirmed;
   string      bosDirection;
   int         confluenceScore;
   string      confluenceDetails;
};

//+------------------------------------------------------------------+
//| Structure for MTF Entry Signal                                    |
//+------------------------------------------------------------------+
struct MTFEntrySignal
{
   MTF_ENTRY_TYPE type;
   string      description;
   string      entryTF;
   double      entryPrice;
   double      stopLoss;
   double      takeProfit;
   double      pendingLevel;
   string      condition;
   bool        isActive;
   double      ltfSupport;
   double      ltfResistance;
   double      ltfRSI;
   SWING_LABEL lastLTFHighLabel;
   SWING_LABEL lastLTFLowLabel;
   int         alignmentScore;
   bool        htfLtfAligned;
};

//+------------------------------------------------------------------+
//| Structure for Confluence Zone                                     |
//+------------------------------------------------------------------+
struct ConfluenceZone
{
   double      priceHigh;
   double      priceLow;
   int         touchCount;
   bool        isBullish;
   int         lastTouchBar;
};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
double RSI_Buffer[];
SwingPoint AllSwings[];
int SwingCount = 0;
SwingPoint SwingHighs[];
SwingPoint SwingLows[];
int HighCount = 0;
int LowCount = 0;

double LastValidHigh = 0;
double LastValidLow = 0;
int LastHighBar = 0;
int LastLowBar = 0;

TREND_STATE CurrentTrend = TREND_UNKNOWN;
MARKET_PHASE CurrentPhase = PHASE_UNKNOWN;
TradingSignal CurrentSignal;
MTFEntrySignal MTFEntry;

string IndicatorPrefix = "DT10_"; // Updated Prefix
bool IsValidTimeframe = false;

color OrigBullCandle, OrigBearCandle, OrigBullWick, OrigBearWick;
int OrigZoomLevel;

double ATR_Cache[];
double Volume_Cache[];
int ATR_CacheSize = 0;

// Key levels
double KeyResistance = 0;
double KeySupport = 0;
double CurrentNeckline = 0;
bool NecklineIsBullish = false;
bool BOSDetected = false;
bool BOSIsBullish = false;
int BOSBar = -1;
double BOSLevel = 0;

// Divergence tracking
bool HasBullishDivergence = false;
bool HasBearishDivergence = false;
bool HasHiddenBullishDiv = false;
bool HasHiddenBearishDiv = false;
int LastDivergenceBar = -1;
double DivergenceStrength = 0;

// Alert tracking
datetime LastAlertTime = 0;
string LastAlertMessage = "";

// MTF Variables
int EntryTimeframe = 0;
string EntryTFString = "";

// Confluence zones
ConfluenceZone SupportZones[];
ConfluenceZone ResistanceZones[];
int SupportZoneCount = 0;
int ResistanceZoneCount = 0;

// Trend scoring
int BullishScore = 0;
int BearishScore = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IsValidTimeframe = CheckTimeframe();

   if(!IsValidTimeframe)
   {
      Comment("Dow Theory Indicator: Only works on H1, H4, and D1 timeframes!");
      return(INIT_SUCCEEDED);
   }

   SetEntryTimeframe();

   OrigBullCandle = (color)ChartGetInteger(0, CHART_COLOR_CANDLE_BULL);
   OrigBearCandle = (color)ChartGetInteger(0, CHART_COLOR_CANDLE_BEAR);
   OrigBullWick = (color)ChartGetInteger(0, CHART_COLOR_CHART_UP);
   OrigBearWick = (color)ChartGetInteger(0, CHART_COLOR_CHART_DOWN);
   OrigZoomLevel = (int)ChartGetInteger(0, CHART_SCALE);

   SetIndexBuffer(0, RSI_Buffer);
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 2, DodgerBlue);
   SetIndexLabel(0, "RSI(" + IntegerToString(RSI_Period) + ")");

   // Optimized cache resizing
   ArrayResize(ATR_Cache, MaxBarsToAnalyze + 100);
   ArrayResize(Volume_Cache, MaxBarsToAnalyze + 100);
   ATR_CacheSize = 0;

   if(CleanChartOnLoad) CleanChart();
   if(ChangeCandleColors) SetCandleColors();
   SetChartZoom();

   ResetSignal();
   ResetMTFEntry();

   IndicatorShortName("Dow Theory v10.0 SMC [RSI " + IntegerToString(RSI_Period) + "]");
   Comment("");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Set entry timeframe based on current chart timeframe             |
//+------------------------------------------------------------------+
void SetEntryTimeframe()
{
   int currentTF = Period();

   switch(currentTF)
   {
      case PERIOD_H1:
         EntryTimeframe = PERIOD_M15;
         EntryTFString = "M15";
         break;
      case PERIOD_H4:
         EntryTimeframe = PERIOD_H1;
         EntryTFString = "H1";
         break;
      case PERIOD_D1:
         EntryTimeframe = PERIOD_H4;
         EntryTFString = "H4";
         break;
      default:
         EntryTimeframe = PERIOD_M15;
         EntryTFString = "M15";
         break;
   }
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Cleanup ALL objects on actual removal
   int totalObjects = ObjectsTotal();
   for(int i = totalObjects - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, IndicatorPrefix) >= 0)
         ObjectDelete(name);
   }

   Comment("");

   if(ChangeCandleColors) RestoreCandleColors();
   RestoreChartZoom();
}

//+------------------------------------------------------------------+
//| Reset trading signal                                             |
//+------------------------------------------------------------------+
void ResetSignal()
{
   CurrentSignal.type = SIG_NONE;
   CurrentSignal.description = "";
   CurrentSignal.entryPrice = 0;
   CurrentSignal.stopLoss = 0;
   CurrentSignal.takeProfit = 0;
   CurrentSignal.hasDivergence = false;
   CurrentSignal.divergenceType = "";
   CurrentSignal.necklineLevel = 0;
   CurrentSignal.bosConfirmed = false;
   CurrentSignal.bosDirection = "";
   CurrentSignal.confluenceScore = 0;
   CurrentSignal.confluenceDetails = "";
}

//+------------------------------------------------------------------+
//| Reset MTF Entry signal                                            |
//+------------------------------------------------------------------+
void ResetMTFEntry()
{
   MTFEntry.type = MTF_NONE;
   MTFEntry.description = "";
   MTFEntry.entryTF = EntryTFString;
   MTFEntry.entryPrice = 0;
   MTFEntry.stopLoss = 0;
   MTFEntry.takeProfit = 0;
   MTFEntry.pendingLevel = 0;
   MTFEntry.condition = "";
   MTFEntry.isActive = false;
   MTFEntry.ltfSupport = 0;
   MTFEntry.ltfResistance = 0;
   MTFEntry.ltfRSI = 0;
   MTFEntry.lastLTFHighLabel = LABEL_NONE;
   MTFEntry.lastLTFLowLabel = LABEL_NONE;
   MTFEntry.alignmentScore = 0;
   MTFEntry.htfLtfAligned = false;
}

//+------------------------------------------------------------------+
//| Check if current timeframe is valid                               |
//+------------------------------------------------------------------+
bool CheckTimeframe()
{
   int period = Period();
   return (period == PERIOD_H1 || period == PERIOD_H4 || period == PERIOD_D1);
}

//+------------------------------------------------------------------+
//| Set chart zoom level                                              |
//+------------------------------------------------------------------+
void SetChartZoom()
{
   int zoomLevel = MathMax(0, MathMin(5, ChartZoomLevel));
   ChartSetInteger(0, CHART_SCALE, zoomLevel);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Restore original chart zoom level                                 |
//+------------------------------------------------------------------+
void RestoreChartZoom()
{
   ChartSetInteger(0, CHART_SCALE, OrigZoomLevel);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Set custom candle colors                                          |
//+------------------------------------------------------------------+
void SetCandleColors()
{
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, BullishCandleColor);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, BearishCandleColor);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, BullishWickColor);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, BearishWickColor);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Restore original candle colors                                    |
//+------------------------------------------------------------------+
void RestoreCandleColors()
{
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, OrigBullCandle);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, OrigBearCandle);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, OrigBullWick);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, OrigBearWick);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Clean chart appearance                                            |
//+------------------------------------------------------------------+
void CleanChart()
{
   if(SwitchToCandlestick) ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   if(RemoveGrid) ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, false);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, false);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Smart Object Deletion (Anti-Flicker)                              |
//+------------------------------------------------------------------+
void DeleteObjectsByPrefix()
{
   // This function is now only called when necessary (init, timeframe change)
   // Routine drawing functions will use Update/Create logic instead
   int totalObjects = ObjectsTotal();
   for(int i = totalObjects - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, IndicatorPrefix) >= 0)
         ObjectDelete(name);
   }
}

//+------------------------------------------------------------------+
//| Initialize caches for ATR and Volume                              |
//+------------------------------------------------------------------+
void InitializeCaches()
{
   int cacheLimit = MathMin(Bars - ATR_Period - 1, MaxBarsToAnalyze + 50);

   // ATR cache
   for(int i = 0; i < cacheLimit; i++)
      ATR_Cache[i] = iATR(NULL, 0, ATR_Period, i);

   // Volume average cache
   for(int i = 0; i < cacheLimit; i++)
   {
      double avgVol = 0;
      for(int j = 0; j < 20 && i + j < Bars; j++)
         avgVol += (double)Volume[i + j];
      Volume_Cache[i] = avgVol / 20.0;
   }

   ATR_CacheSize = cacheLimit;
}

//+------------------------------------------------------------------+
//| Get cached ATR value for a specific bar                           |
//+------------------------------------------------------------------+
double GetATRAtBar(int bar)
{
   if(bar < 0 || bar >= Bars) return 0;

   if(ATR_CacheSize == 0) InitializeCaches();

   if(bar < ATR_CacheSize) return ATR_Cache[bar];
   return iATR(NULL, 0, ATR_Period, bar);
}

//+------------------------------------------------------------------+
//| Get average volume at bar                                         |
//+------------------------------------------------------------------+
double GetAvgVolumeAtBar(int bar)
{
   if(bar < 0 || bar >= Bars) return 0;

   if(ATR_CacheSize == 0) InitializeCaches();

   if(bar < ATR_CacheSize) return Volume_Cache[bar];

   double avgVol = 0;
   for(int j = 0; j < 20 && bar + j < Bars; j++)
      avgVol += (double)Volume[bar + j];
   return avgVol / 20.0;
}

//+------------------------------------------------------------------+
//| Calculate comprehensive swing strength score                      |
//+------------------------------------------------------------------+
int CalculateSwingStrength(int bar, SWING_TYPE type, double &volumeRatio, double &wickRatio,
                           bool &hasVolSpike, bool &hasWickRej, bool &hasMom)
{
   int strength = 0;
   double atr = GetATRAtBar(bar);
   if(atr <= 0) return 1;

   volumeRatio = 0;
   wickRatio = 0;
   hasVolSpike = false;
   hasWickRej = false;
   hasMom = false;

   double avgVol = GetAvgVolumeAtBar(bar);
   double currentVol = (double)Volume[bar];
   volumeRatio = (avgVol > 0) ? currentVol / avgVol : 1.0;

   if(type == SWING_HIGH)
   {
      double high = High[bar];
      int lowestBar = iLowest(NULL, 0, MODE_LOW, SwingLookback * 2 + 1, MathMax(0, bar - SwingLookback));
      double localLow = Low[lowestBar];
      double move = high - localLow;

      // Move strength
      if(move >= atr * 3.0) strength += 4;
      else if(move >= atr * 2.0) strength += 3;
      else if(move >= atr * 1.5) strength += 2;
      else if(move >= atr * 1.0) strength += 1;

      // Wick rejection analysis
      double bodyHigh = MathMax(Open[bar], Close[bar]);
      double upperWick = high - bodyHigh;
      double range = high - Low[bar];
      wickRatio = (range > 0) ? upperWick / range : 0;

      if(UseWickRejection && wickRatio >= MinWickRatio)
      {
         hasWickRej = true;
         strength += 2;
      }

      // Volume confirmation
      if(UseVolumeConfirmation && volumeRatio >= VolumeMultiplier)
      {
         hasVolSpike = true;
         strength += 2;
      }

      // Momentum check (RSI was rising into the high)
      if(UseMomentumFilter && bar + MomentumLookback < Bars)
      {
         double rsiAtHigh = RSI_Buffer[bar];
         double rsiPrior = RSI_Buffer[bar + MomentumLookback];
         if(rsiAtHigh > rsiPrior && rsiAtHigh > 50)
         {
            hasMom = true;
            strength += 1;
         }
         // Bonus for overbought rejection
         if(rsiAtHigh > 70) strength += 1;
      }

      // Dominance check
      int dominanceLeft = 0, dominanceRight = 0;
      for(int i = 1; i <= SwingLookback * 2 && bar + i < Bars; i++)
      {
         if(High[bar + i] < high) dominanceLeft++;
         else break;
      }
      for(int i = 1; i <= SwingLookback * 2 && bar - i >= 0; i++)
      {
         if(High[bar - i] < high) dominanceRight++;
         else break;
      }

      if(dominanceLeft >= SwingLookback * 2 && dominanceRight >= SwingLookback * 2) strength += 2;
      else if(dominanceLeft >= SwingLookback && dominanceRight >= SwingLookback) strength += 1;
   }
   else if(type == SWING_LOW)
   {
      double low = Low[bar];
      int highestBar = iHighest(NULL, 0, MODE_HIGH, SwingLookback * 2 + 1, MathMax(0, bar - SwingLookback));
      double localHigh = High[highestBar];
      double move = localHigh - low;

      // Move strength
      if(move >= atr * 3.0) strength += 4;
      else if(move >= atr * 2.0) strength += 3;
      else if(move >= atr * 1.5) strength += 2;
      else if(move >= atr * 1.0) strength += 1;

      // Wick rejection analysis
      double bodyLow = MathMin(Open[bar], Close[bar]);
      double lowerWick = bodyLow - low;
      double range = High[bar] - low;
      wickRatio = (range > 0) ? lowerWick / range : 0;

      if(UseWickRejection && wickRatio >= MinWickRatio)
      {
         hasWickRej = true;
         strength += 2;
      }

      // Volume confirmation
      if(UseVolumeConfirmation && volumeRatio >= VolumeMultiplier)
      {
         hasVolSpike = true;
         strength += 2;
      }

      // Momentum check (RSI was falling into the low)
      if(UseMomentumFilter && bar + MomentumLookback < Bars)
      {
         double rsiAtLow = RSI_Buffer[bar];
         double rsiPrior = RSI_Buffer[bar + MomentumLookback];
         if(rsiAtLow < rsiPrior && rsiAtLow < 50)
         {
            hasMom = true;
            strength += 1;
         }
         // Bonus for oversold bounce
         if(rsiAtLow < 30) strength += 1;
      }

      // Dominance check
      int dominanceLeft = 0, dominanceRight = 0;
      for(int i = 1; i <= SwingLookback * 2 && bar + i < Bars; i++)
      {
         if(Low[bar + i] > low) dominanceLeft++;
         else break;
      }
      for(int i = 1; i <= SwingLookback * 2 && bar - i >= 0; i++)
      {
         if(Low[bar - i] > low) dominanceRight++;
         else break;
      }

      if(dominanceLeft >= SwingLookback * 2 && dominanceRight >= SwingLookback * 2) strength += 2;
      else if(dominanceLeft >= SwingLookback && dominanceRight >= SwingLookback) strength += 1;
   }

   return MathMax(1, strength);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
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
   if(!IsValidTimeframe) return(rates_total);

   // RSI Calculation Loop
   int limit_rsi;
   if(prev_calculated == 0) limit_rsi = rates_total - 1;
   else limit_rsi = rates_total - prev_calculated;

   for(int i = limit_rsi; i >= 0; i--) {
      RSI_Buffer[i] = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE, i);
   }

   // PERFORMANCE OPTIMIZATION: Only recalculate heavy logic on new candles or significant updates
   // We force a recalc if it's the first run (prev==0) or if explicitly requested

   bool fullRecalc = (prev_calculated == 0);

   // For structure analysis, we generally need to re-scan mostly on new bars
   // or if we want to handle repainting of the current forming swing.
   // To avoid flickering, we only delete objects on full init.
   if(fullRecalc) {
       DeleteObjectsByPrefix();
       ATR_CacheSize = 0; // Clear cache
   }

   // Re-init arrays on every calc to ensure structure consistency (fast enough for arrays)
   // But we won't delete visual objects yet
   ClearAllArrays();
   ResetSignal();
   ResetMTFEntry();

   HasBullishDivergence = false;
   HasBearishDivergence = false;
   HasHiddenBullishDiv = false;
   HasHiddenBearishDiv = false;
   LastDivergenceBar = -1;
   DivergenceStrength = 0;

   BOSDetected = false;
   BOSIsBullish = false;
   BOSBar = -1;
   BOSLevel = 0;

   BullishScore = 0;
   BearishScore = 0;

   int barsToAnalyze = MathMin(rates_total - SwingLookback - 1, MaxBarsToAnalyze);

   // --- MAIN LOGIC ---
   FindAllSwingPointsEnhanced(barsToAnalyze);
   FilterSwingPointsImproved();
   if(RequireSwingAlternation) EnforceSwingAlternation();
   FilterByStrength();
   LabelSwingsWithContext();

   // --- DRAWING ---
   // Note: Functions updated to create/update instead of delete/create
   DrawSwingLabels();

   if(ShowStructureLines) DrawStructureLines();
   if(ShowRSI_TrendLines || ShowRSI_Divergence) DrawRSI_AnalysisEnhanced();
   if(ShowNecklines || ShowBOS) DetectAndDrawNecklinesEnhanced();
   if(ShowConfluenceZones) DetectConfluenceZones();
   if(ShowFVG) DetectFVG(barsToAnalyze);
   if(ShowAutoFib) DrawAutoFib();

   // Generate HTF trading signals with confluence scoring
   GenerateTradingSignalsEnhanced();

   // Generate MTF entry signals
   if(EnableMTFEntry)
      GenerateMTFEntrySignalsEnhanced();

   // Draw signal panel
   if(ShowSignalPanel) DrawSignalPanel();

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Clear all arrays                                                 |
//+------------------------------------------------------------------+
void ClearAllArrays()
{
   ArrayResize(AllSwings, 0);
   ArrayResize(SwingHighs, 0);
   ArrayResize(SwingLows, 0);
   ArrayResize(SupportZones, 0);
   ArrayResize(ResistanceZones, 0);
   SwingCount = 0;
   HighCount = 0;
   LowCount = 0;
   SupportZoneCount = 0;
   ResistanceZoneCount = 0;
   LastValidHigh = 0;
   LastValidLow = 0;
   LastHighBar = 0;
   LastLowBar = 0;
   CurrentTrend = TREND_UNKNOWN;
   CurrentPhase = PHASE_UNKNOWN;
}

//+------------------------------------------------------------------+
//| Find all swing points with enhanced detection                     |
//+------------------------------------------------------------------+
void FindAllSwingPointsEnhanced(int barsToAnalyze)
{
   for(int i = barsToAnalyze - 1; i >= SwingLookback; i--)
   {
      bool isHigh = IsValidSwingHighEnhanced(i);
      bool isLow = IsValidSwingLowEnhanced(i);

      // If both, determine which is more significant
      if(isHigh && isLow)
      {
         double atr = GetATRAtBar(i);
         double upMove = High[i] - Low[iLowest(NULL, 0, MODE_LOW, SwingLookback, MathMin(Bars-1, i + 1))];
         double downMove = High[iHighest(NULL, 0, MODE_HIGH, SwingLookback, MathMin(Bars-1, i + 1))] - Low[i];

         // Check candle type for additional context
         bool isBullishCandle = Close[i] > Open[i];

         if(upMove > downMove * 1.2) isLow = false;
         else if(downMove > upMove * 1.2) isHigh = false;
         else if(isBullishCandle) isLow = false;  // Bullish candle more likely swing low
         else isHigh = false;
      }

      if(isHigh)
      {
         SwingPoint sp;
         InitSwingPoint(sp);
         sp.bar = i;
         sp.price = High[i];
         sp.rsi = RSI_Buffer[i];
         sp.atr = GetATRAtBar(i);
         sp.volume = (double)Volume[i];
         sp.time = Time[i];
         sp.type = SWING_HIGH;
         sp.label = LABEL_NONE;
         sp.isValid = true;
         sp.isBroken = false;
         sp.strength = CalculateSwingStrength(i, SWING_HIGH, sp.volumeRatio, sp.wickRatio,
                                            sp.hasVolumeSpike, sp.hasWickRejection, sp.hasMomentum);
         sp.confluenceScore = CalculateConfluenceScore(sp);

         SwingCount++;
         ArrayResize(AllSwings, SwingCount);
         AllSwings[SwingCount - 1] = sp;
      }

      if(isLow)
      {
         SwingPoint sp;
         InitSwingPoint(sp);
         sp.bar = i;
         sp.price = Low[i];
         sp.rsi = RSI_Buffer[i];
         sp.atr = GetATRAtBar(i);
         sp.volume = (double)Volume[i];
         sp.time = Time[i];
         sp.type = SWING_LOW;
         sp.label = LABEL_NONE;
         sp.isValid = true;
         sp.isBroken = false;
         sp.strength = CalculateSwingStrength(i, SWING_LOW, sp.volumeRatio, sp.wickRatio,
                                            sp.hasVolumeSpike, sp.hasWickRejection, sp.hasMomentum);
         sp.confluenceScore = CalculateConfluenceScore(sp);

         SwingCount++;
         ArrayResize(AllSwings, SwingCount);
         AllSwings[SwingCount - 1] = sp;
      }
   }
}

//+------------------------------------------------------------------+
//| Initialize swing point structure                                  |
//+------------------------------------------------------------------+
void InitSwingPoint(SwingPoint &sp)
{
   sp.bar = 0;
   sp.price = 0;
   sp.rsi = 0;
   sp.atr = 0;
   sp.volume = 0;
   sp.time = 0;
   sp.type = SWING_NONE;
   sp.label = LABEL_NONE;
   sp.isValid = false;
   sp.isBroken = false;
   sp.strength = 0;
   sp.volumeRatio = 0;
   sp.wickRatio = 0;
   sp.confluenceScore = 0;
   sp.hasVolumeSpike = false;
   sp.hasWickRejection = false;
   sp.hasMomentum = false;
}

//+------------------------------------------------------------------+
//| Calculate confluence score for swing point                        |
//+------------------------------------------------------------------+
int CalculateConfluenceScore(SwingPoint &sp)
{
   int score = 0;

   // Base score from strength
   if(sp.strength >= 8) score += 2;
   else if(sp.strength >= 5) score += 1;

   // Volume confirmation
   if(sp.hasVolumeSpike) score += 1;

   // Wick rejection
   if(sp.hasWickRejection) score += 1;

   // Momentum alignment
   if(sp.hasMomentum) score += 1;

   // RSI extremes
   if(sp.type == SWING_HIGH && sp.rsi > 65) score += 1;
   if(sp.type == SWING_LOW && sp.rsi < 35) score += 1;

   return MathMin(5, score);
}

//+------------------------------------------------------------------+
//| Check if bar is a valid swing high (enhanced)                     |
//+------------------------------------------------------------------+
bool IsValidSwingHighEnhanced(int bar)
{
   if(bar < SwingLookback || bar + SwingLookback >= Bars) return false;

   double currentHigh = High[bar];
   double atr = GetATRAtBar(bar);

   // Basic fractal check with stricter validation
   for(int i = 1; i <= SwingLookback; i++)
   {
      if(High[bar + i] >= currentHigh) return false;
   }

   for(int i = 1; i <= SwingLookback; i++)
   {
      if(High[bar - i] >= currentHigh) return false;
   }

   // Clean break validation - ensure clear separation from surrounding highs
   if(RequireCleanBreak)
   {
      double minSeparation = atr * CleanBreakATRMult;
      int nearbyHighCount = 0;

      for(int i = 1; i <= SwingLookback; i++)
      {
         if(MathAbs(High[bar + i] - currentHigh) < minSeparation) nearbyHighCount++;
         if(MathAbs(High[bar - i] - currentHigh) < minSeparation) nearbyHighCount++;
      }

      // If too many highs are clustered nearby, it's not a clean swing
      if(nearbyHighCount > SwingLookback / 2) return false;
   }

   // Body confirmation
   if(UseBodyConfirmation)
   {
      double bodyHigh = MathMax(Open[bar], Close[bar]);
      double upperWick = currentHigh - bodyHigh;
      double range = currentHigh - Low[bar];

      if(range > atr * 0.3)
      {
         bool hasWickRejection = (range > 0 && upperWick >= range * 0.15);
         bool isStrongBullishMove = (Close[bar] > Open[bar] && (Close[bar] - Open[bar]) >= range * 0.5);

         if(!hasWickRejection && !isStrongBullishMove)
         {
            bool confirmed = false;
            for(int j = 1; j <= MathMin(4, SwingLookback); j++)
            {
               if(bar - j >= 0 && High[bar - j] < currentHigh - atr * 0.1)
               {
                  confirmed = true;
                  break;
               }
            }
            if(!confirmed) return false;
         }
      }
   }

   // ATR filter
   if(UseATRFilter && atr > 0)
   {
      int searchStart = MathMin(bar + SwingLookback, Bars - 1);
      int searchEnd = MathMax(bar - SwingLookback, 0);
      int lowestBar = iLowest(NULL, 0, MODE_LOW, searchStart - searchEnd + 1, searchEnd);
      double localLow = Low[lowestBar];

      if((currentHigh - localLow) < atr * ATRMultiplier) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a valid swing low (enhanced)                      |
//+------------------------------------------------------------------+
bool IsValidSwingLowEnhanced(int bar)
{
   if(bar < SwingLookback || bar + SwingLookback >= Bars) return false;

   double currentLow = Low[bar];
   double atr = GetATRAtBar(bar);

   // Basic fractal check
   for(int i = 1; i <= SwingLookback; i++)
   {
      if(Low[bar + i] <= currentLow) return false;
   }

   for(int i = 1; i <= SwingLookback; i++)
   {
      if(Low[bar - i] <= currentLow) return false;
   }

   // Clean break validation
   if(RequireCleanBreak)
   {
      double minSeparation = atr * CleanBreakATRMult;
      int nearbyLowCount = 0;

      for(int i = 1; i <= SwingLookback; i++)
      {
         if(MathAbs(Low[bar + i] - currentLow) < minSeparation) nearbyLowCount++;
         if(MathAbs(Low[bar - i] - currentLow) < minSeparation) nearbyLowCount++;
      }

      if(nearbyLowCount > SwingLookback / 2) return false;
   }

   // Body confirmation
   if(UseBodyConfirmation)
   {
      double bodyLow = MathMin(Open[bar], Close[bar]);
      double lowerWick = bodyLow - currentLow;
      double range = High[bar] - currentLow;

      if(range > atr * 0.3)
      {
         bool hasWickRejection = (range > 0 && lowerWick >= range * 0.15);
         bool isStrongBearishMove = (Close[bar] < Open[bar] && (Open[bar] - Close[bar]) >= range * 0.5);

         if(!hasWickRejection && !isStrongBearishMove)
         {
            bool confirmed = false;
            for(int j = 1; j <= MathMin(4, SwingLookback); j++)
            {
               if(bar - j >= 0 && Low[bar - j] > currentLow + atr * 0.1)
               {
                  confirmed = true;
                  break;
               }
            }
            if(!confirmed) return false;
         }
      }
   }

   // ATR filter
   if(UseATRFilter && atr > 0)
   {
      int searchStart = MathMin(bar + SwingLookback, Bars - 1);
      int searchEnd = MathMax(bar - SwingLookback, 0);
      int highestBar = iHighest(NULL, 0, MODE_HIGH, searchStart - searchEnd + 1, searchEnd);
      double localHigh = High[highestBar];

      if((localHigh - currentLow) < atr * ATRMultiplier) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Filter swing points (Memory Optimized)                            |
//+------------------------------------------------------------------+
void FilterSwingPointsImproved()
{
   if(SwingCount == 0) return;

   // Allocate max possible size once
   SwingPoint filteredSwings[];
   ArrayResize(filteredSwings, SwingCount);

   int filteredCount = 0;
   int lastHighIdx = -1;
   int lastLowIdx = -1;

   for(int i = 0; i < SwingCount; i++)
   {
      bool keep = true;

      if(AllSwings[i].type == SWING_HIGH)
      {
         if(lastHighIdx >= 0)
         {
            int distance = MathAbs(AllSwings[i].bar - filteredSwings[lastHighIdx].bar);

            if(distance < MinSwingBars)
            {
               bool currentBetter = false;

               // Prefer higher prices
               if(AllSwings[i].price > filteredSwings[lastHighIdx].price + filteredSwings[lastHighIdx].atr * 0.1)
                  currentBetter = true;
               // If prices similar, prefer higher confluence score
               else if(MathAbs(AllSwings[i].price - filteredSwings[lastHighIdx].price) <= filteredSwings[lastHighIdx].atr * 0.1)
               {
                  if(AllSwings[i].confluenceScore > filteredSwings[lastHighIdx].confluenceScore)
                     currentBetter = true;
                  else if(AllSwings[i].confluenceScore == filteredSwings[lastHighIdx].confluenceScore &&
                          AllSwings[i].strength > filteredSwings[lastHighIdx].strength)
                     currentBetter = true;
               }

               if(currentBetter) filteredSwings[lastHighIdx] = AllSwings[i];
               keep = false;
            }
         }

         if(keep)
         {
            filteredSwings[filteredCount] = AllSwings[i];
            lastHighIdx = filteredCount;
            filteredCount++;
         }
      }
      else if(AllSwings[i].type == SWING_LOW)
      {
         if(lastLowIdx >= 0)
         {
            int distance = MathAbs(AllSwings[i].bar - filteredSwings[lastLowIdx].bar);

            if(distance < MinSwingBars)
            {
               bool currentBetter = false;

               if(AllSwings[i].price < filteredSwings[lastLowIdx].price - filteredSwings[lastLowIdx].atr * 0.1)
                  currentBetter = true;
               else if(MathAbs(AllSwings[i].price - filteredSwings[lastLowIdx].price) <= filteredSwings[lastLowIdx].atr * 0.1)
               {
                  if(AllSwings[i].confluenceScore > filteredSwings[lastLowIdx].confluenceScore)
                     currentBetter = true;
                  else if(AllSwings[i].confluenceScore == filteredSwings[lastLowIdx].confluenceScore &&
                          AllSwings[i].strength > filteredSwings[lastLowIdx].strength)
                     currentBetter = true;
               }

               if(currentBetter) filteredSwings[lastLowIdx] = AllSwings[i];
               keep = false;
            }
         }

         if(keep)
         {
            filteredSwings[filteredCount] = AllSwings[i];
            lastLowIdx = filteredCount;
            filteredCount++;
         }
      }
   }

   // Resize down to actual count
   SwingCount = filteredCount;
   ArrayResize(AllSwings, SwingCount);
   for(int i = 0; i < SwingCount; i++)
      AllSwings[i] = filteredSwings[i];

   BuildSeparateArrays();
}

//+------------------------------------------------------------------+
//| Enforce swing alternation                                         |
//+------------------------------------------------------------------+
void EnforceSwingAlternation()
{
   if(SwingCount < 3) return;

   SortSwingsByBar();

   SwingPoint alternatedSwings[];
   ArrayResize(alternatedSwings, SwingCount); // Pre-allocate
   int altCount = 0;
   SWING_TYPE lastType = SWING_NONE;

   for(int i = 0; i < SwingCount; i++)
   {
      if(lastType == SWING_NONE)
      {
         alternatedSwings[altCount] = AllSwings[i];
         lastType = AllSwings[i].type;
         altCount++;
      }
      else if(AllSwings[i].type != lastType)
      {
         alternatedSwings[altCount] = AllSwings[i];
         lastType = AllSwings[i].type;
         altCount++;
      }
      else
      {
         int lastIdx = altCount - 1;
         bool replaceLast = false;

         if(AllSwings[i].type == SWING_HIGH)
         {
            if(AllSwings[i].price > alternatedSwings[lastIdx].price)
               replaceLast = true;
            else if(AllSwings[i].price == alternatedSwings[lastIdx].price &&
                    AllSwings[i].confluenceScore > alternatedSwings[lastIdx].confluenceScore)
               replaceLast = true;
         }
         else
         {
            if(AllSwings[i].price < alternatedSwings[lastIdx].price)
               replaceLast = true;
            else if(AllSwings[i].price == alternatedSwings[lastIdx].price &&
                    AllSwings[i].confluenceScore > alternatedSwings[lastIdx].confluenceScore)
               replaceLast = true;
         }

         if(replaceLast) alternatedSwings[lastIdx] = AllSwings[i];
      }
   }

   SwingCount = altCount;
   ArrayResize(AllSwings, SwingCount);
   for(int i = 0; i < SwingCount; i++)
      AllSwings[i] = alternatedSwings[i];

   BuildSeparateArrays();
}

//+------------------------------------------------------------------+
//| Filter by minimum strength                                        |
//+------------------------------------------------------------------+
void FilterByStrength()
{
   if(MinSwingStrength <= 1 || SwingCount == 0) return;

   SwingPoint strongSwings[];
   ArrayResize(strongSwings, SwingCount); // Pre-allocate
   int strongCount = 0;

   for(int i = 0; i < SwingCount; i++)
   {
      if(AllSwings[i].strength >= MinSwingStrength || AllSwings[i].confluenceScore >= 3)
      {
         strongSwings[strongCount] = AllSwings[i];
         strongCount++;
      }
   }

   if(strongCount >= 6)
   {
      SwingCount = strongCount;
      ArrayResize(AllSwings, SwingCount);
      for(int i = 0; i < SwingCount; i++)
         AllSwings[i] = strongSwings[i];

      BuildSeparateArrays();
   }
}

//+------------------------------------------------------------------+
//| Sort swings by bar number                                         |
//+------------------------------------------------------------------+
void SortSwingsByBar()
{
   for(int i = 0; i < SwingCount - 1; i++)
   {
      for(int j = 0; j < SwingCount - i - 1; j++)
      {
         if(AllSwings[j].bar < AllSwings[j + 1].bar)
         {
            SwingPoint temp = AllSwings[j];
            AllSwings[j] = AllSwings[j + 1];
            AllSwings[j + 1] = temp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Build separate arrays                                             |
//+------------------------------------------------------------------+
void BuildSeparateArrays()
{
   HighCount = 0;
   LowCount = 0;

   // Allocate max possible
   ArrayResize(SwingHighs, SwingCount);
   ArrayResize(SwingLows, SwingCount);

   for(int i = 0; i < SwingCount; i++)
   {
      if(AllSwings[i].type == SWING_HIGH)
      {
         SwingHighs[HighCount] = AllSwings[i];
         HighCount++;
      }
      else
      {
         SwingLows[LowCount] = AllSwings[i];
         LowCount++;
      }
   }

   ArrayResize(SwingHighs, HighCount);
   ArrayResize(SwingLows, LowCount);
}

//+------------------------------------------------------------------+
//| Label swings with context                                         |
//+------------------------------------------------------------------+
void LabelSwingsWithContext()
{
   double prevHigh = 0;
   for(int i = 0; i < HighCount; i++)
   {
      if(prevHigh == 0)
      {
         SwingHighs[i].label = LABEL_NONE;
      }
      else
      {
         double tolerance = SwingHighs[i].atr * EqualSwingTolerance;

         if(SwingHighs[i].price > prevHigh + tolerance)
            SwingHighs[i].label = LABEL_HH;
         else if(SwingHighs[i].price < prevHigh - tolerance)
            SwingHighs[i].label = LABEL_LH;
         else
            SwingHighs[i].label = LABEL_EH;
      }
      prevHigh = SwingHighs[i].price;
   }

   double prevLow = 0;
   for(int i = 0; i < LowCount; i++)
   {
      if(prevLow == 0)
      {
         SwingLows[i].label = LABEL_NONE;
      }
      else
      {
         double tolerance = SwingLows[i].atr * EqualSwingTolerance;

         if(SwingLows[i].price > prevLow + tolerance)
            SwingLows[i].label = LABEL_HL;
         else if(SwingLows[i].price < prevLow - tolerance)
            SwingLows[i].label = LABEL_LL;
         else
            SwingLows[i].label = LABEL_EL;
      }
      prevLow = SwingLows[i].price;
   }

   int hiIdx = 0, loIdx = 0;
   for(int i = 0; i < SwingCount; i++)
   {
      if(AllSwings[i].type == SWING_HIGH && hiIdx < HighCount)
      {
         AllSwings[i].label = SwingHighs[hiIdx].label;
         hiIdx++;
      }
      else if(AllSwings[i].type == SWING_LOW && loIdx < LowCount)
      {
         AllSwings[i].label = SwingLows[loIdx].label;
         loIdx++;
      }
   }

   DetermineTrendStateEnhanced();

   if(HighCount > 0) KeyResistance = SwingHighs[HighCount - 1].price;
   if(LowCount > 0) KeySupport = SwingLows[LowCount - 1].price;
}

//+------------------------------------------------------------------+
//| Determine trend state with enhanced accuracy                      |
//+------------------------------------------------------------------+
void DetermineTrendStateEnhanced()
{
   if(HighCount < 2 || LowCount < 2)
   {
      CurrentTrend = TREND_UNKNOWN;
      return;
   }

   // Score-based trend determination
   BullishScore = 0;
   BearishScore = 0;

   int checkCount = MathMin(4, MathMin(HighCount, LowCount));

   // Weight recent swings more heavily
   for(int i = 0; i < checkCount; i++)
   {
      int weight = checkCount - i;  // More recent = higher weight

      SWING_LABEL highLabel = SwingHighs[HighCount - 1 - i].label;
      SWING_LABEL lowLabel = SwingLows[LowCount - 1 - i].label;
      int highConfluence = SwingHighs[HighCount - 1 - i].confluenceScore;
      int lowConfluence = SwingLows[LowCount - 1 - i].confluenceScore;

      // High labels
      if(highLabel == LABEL_HH)
      {
         BullishScore += weight * (1 + highConfluence / 2);
      }
      else if(highLabel == LABEL_LH)
      {
         BearishScore += weight * (1 + highConfluence / 2);
      }

      // Low labels
      if(lowLabel == LABEL_HL)
      {
         BullishScore += weight * (1 + lowConfluence / 2);
      }
      else if(lowLabel == LABEL_LL)
      {
         BearishScore += weight * (1 + lowConfluence / 2);
      }
   }

   // Check most recent structure break
   if(HighCount >= 2 && LowCount >= 2)
   {
      // Check if most recent high broke above previous high (bullish)
      if(SwingHighs[HighCount-1].label == LABEL_HH && SwingHighs[HighCount-1].bar < SwingLows[LowCount-1].bar)
         BullishScore += 3;

      // Check if most recent low broke below previous low (bearish)
      if(SwingLows[LowCount-1].label == LABEL_LL && SwingLows[LowCount-1].bar < SwingHighs[HighCount-1].bar)
         BearishScore += 3;
   }

   // Determine trend based on scores
   int scoreDiff = BullishScore - BearishScore;
   int minScoreThreshold = 3;

   if(scoreDiff >= minScoreThreshold)
      CurrentTrend = TREND_BULLISH;
   else if(scoreDiff <= -minScoreThreshold)
      CurrentTrend = TREND_BEARISH;
   else if(BullishScore > 0 && BearishScore > 0)
      CurrentTrend = TREND_RANGING;
   else
      CurrentTrend = TREND_UNKNOWN;
}

//+------------------------------------------------------------------+
//| Detect Fair Value Gaps (SMC)                                      |
//+------------------------------------------------------------------+
void DetectFVG(int limit)
{
   if(!ShowFVG) return;

   // Limit lookback
   int start = MathMax(3, limit);
   // We look back from 'start' down to '1' (not 0 because we need i-2, i+2 logic, kept simple)

   for(int i = start; i >= 1; i--)
   {
      // Bullish FVG: Low of candle i+2 > High of candle i
      // We index chronologically: [i+2] is OLDER, [i] is NEWER relative to loop direction if using classic MT4 array indexing
      // Wait, standard MT4 indexing: [0] is current, [1] is previous.
      // So [i+2] is 2 bars older than [i].
      // Bullish FVG pattern: Candle 1 High < Candle 3 Low (Gap in between)
      // Indexes: i (Newest/Right), i+1 (Middle), i+2 (Oldest/Left)

      if(Low[i+2] > High[i] && Close[i+1] > Open[i+1]) // Gap exists + Middle is Green
      {
         string name = IndicatorPrefix + "FVG_Bull_" + IntegerToString(Time[i+1]);
         if(ObjectFind(name) < 0)
         {
            ObjectCreate(name, OBJ_RECTANGLE, 0, Time[i+2], Low[i+2], Time[i], High[i]);
            ObjectSetInteger(0, name, OBJPROP_COLOR, BullishFVGColor);
            ObjectSetInteger(0, name, OBJPROP_BACK, true);
            ObjectSetInteger(0, name, OBJPROP_FILL, true);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 0); // No border
            if(ExtendFVG) ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
         }
      }

      // Bearish FVG: High of candle i+2 < Low of candle i
      else if(High[i+2] < Low[i] && Close[i+1] < Open[i+1]) // Gap exists + Middle is Red
      {
         string name = IndicatorPrefix + "FVG_Bear_" + IntegerToString(Time[i+1]);
         if(ObjectFind(name) < 0)
         {
            ObjectCreate(name, OBJ_RECTANGLE, 0, Time[i+2], High[i+2], Time[i], Low[i]);
            ObjectSetInteger(0, name, OBJPROP_COLOR, BearishFVGColor);
            ObjectSetInteger(0, name, OBJPROP_BACK, true);
            ObjectSetInteger(0, name, OBJPROP_FILL, true);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 0); // No border
            if(ExtendFVG) ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw Auto Fibonacci                                               |
//+------------------------------------------------------------------+
void DrawAutoFib()
{
   if(!ShowAutoFib) return;

   string fibName = IndicatorPrefix + "AutoFib";
   ObjectDelete(fibName); // Always redraw active fib

   if(HighCount < 1 || LowCount < 1) return;

   // If Trend is Bullish, Draw Fib from Last Low to Last High
   if(CurrentTrend == TREND_BULLISH)
   {
      ObjectCreate(fibName, OBJ_FIBO, 0, Time[SwingLows[LowCount-1].bar], SwingLows[LowCount-1].price, Time[SwingHighs[HighCount-1].bar], SwingHighs[HighCount-1].price);
      ObjectSetInteger(0, fibName, OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, fibName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, fibName, OBJPROP_STYLE, STYLE_DOT);
      // Premium/Discount Levels
      ObjectSetDouble(0, fibName, OBJPROP_LEVELVALUE, 0, 0.5);
      ObjectSetString(0, fibName, OBJPROP_LEVELTEXT, 0, "EQ (0.5)");
      ObjectSetDouble(0, fibName, OBJPROP_LEVELVALUE, 1, 0.618);
      ObjectSetString(0, fibName, OBJPROP_LEVELTEXT, 1, "Golden (0.618)");
      ObjectSetDouble(0, fibName, OBJPROP_LEVELVALUE, 2, 0.786);
      ObjectSetString(0, fibName, OBJPROP_LEVELTEXT, 2, "OTE (0.786)");
   }
   // If Trend is Bearish, Draw Fib from Last High to Last Low
   else if(CurrentTrend == TREND_BEARISH)
   {
      ObjectCreate(fibName, OBJ_FIBO, 0, Time[SwingHighs[HighCount-1].bar], SwingHighs[HighCount-1].price, Time[SwingLows[LowCount-1].bar], SwingLows[LowCount-1].price);
      ObjectSetInteger(0, fibName, OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, fibName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, fibName, OBJPROP_STYLE, STYLE_DOT);

      ObjectSetDouble(0, fibName, OBJPROP_LEVELVALUE, 0, 0.5);
      ObjectSetString(0, fibName, OBJPROP_LEVELTEXT, 0, "EQ (0.5)");
      ObjectSetDouble(0, fibName, OBJPROP_LEVELVALUE, 1, 0.618);
      ObjectSetString(0, fibName, OBJPROP_LEVELTEXT, 1, "Golden (0.618)");
      ObjectSetDouble(0, fibName, OBJPROP_LEVELVALUE, 2, 0.786);
      ObjectSetString(0, fibName, OBJPROP_LEVELTEXT, 2, "OTE (0.786)");
   }
}

//+------------------------------------------------------------------+
//| Detect confluence zones                                           |
//+------------------------------------------------------------------+
void DetectConfluenceZones()
{
   if(!UseSwingCluster || SwingCount < 4) return;

   double atr = GetATRAtBar(0);
   double zoneRange = atr * ClusterATRMult;

   // Find resistance zones (clustered highs)
   for(int i = 0; i < HighCount; i++)
   {
      double basePrice = SwingHighs[i].price;
      int touchCount = 1;
      double zoneHigh = basePrice;
      double zoneLow = basePrice;
      int lastTouch = SwingHighs[i].bar;

      // Check for nearby highs
      for(int j = 0; j < HighCount; j++)
      {
         if(i == j) continue;
         if(MathAbs(SwingHighs[j].price - basePrice) <= zoneRange)
         {
            touchCount++;
            zoneHigh = MathMax(zoneHigh, SwingHighs[j].price);
            zoneLow = MathMin(zoneLow, SwingHighs[j].price);
            if(SwingHighs[j].bar < lastTouch) lastTouch = SwingHighs[j].bar;
         }
      }

      // Also check lows that approached this level
      for(int j = 0; j < LowCount; j++)
      {
         double highOfLowBar = High[SwingLows[j].bar];
         if(MathAbs(highOfLowBar - basePrice) <= zoneRange)
         {
            touchCount++;
            if(SwingLows[j].bar < lastTouch) lastTouch = SwingLows[j].bar;
         }
      }

      if(touchCount >= 2)
      {
         // Check if zone already exists
         bool exists = false;
         for(int z = 0; z < ResistanceZoneCount; z++)
         {
            if(MathAbs(ResistanceZones[z].priceHigh - zoneHigh) <= zoneRange &&
               MathAbs(ResistanceZones[z].priceLow - zoneLow) <= zoneRange)
            {
               exists = true;
               if(touchCount > ResistanceZones[z].touchCount)
               {
                  ResistanceZones[z].touchCount = touchCount;
                  ResistanceZones[z].lastTouchBar = lastTouch;
               }
               break;
            }
         }

         if(!exists)
         {
            ResistanceZoneCount++;
            ArrayResize(ResistanceZones, ResistanceZoneCount);
            ResistanceZones[ResistanceZoneCount-1].priceHigh = zoneHigh + atr * 0.1;
            ResistanceZones[ResistanceZoneCount-1].priceLow = zoneLow - atr * 0.1;
            ResistanceZones[ResistanceZoneCount-1].touchCount = touchCount;
            ResistanceZones[ResistanceZoneCount-1].isBullish = false;
            ResistanceZones[ResistanceZoneCount-1].lastTouchBar = lastTouch;
         }
      }
   }

   // Find support zones (clustered lows)
   for(int i = 0; i < LowCount; i++)
   {
      double basePrice = SwingLows[i].price;
      int touchCount = 1;
      double zoneHigh = basePrice;
      double zoneLow = basePrice;
      int lastTouch = SwingLows[i].bar;

      for(int j = 0; j < LowCount; j++)
      {
         if(i == j) continue;
         if(MathAbs(SwingLows[j].price - basePrice) <= zoneRange)
         {
            touchCount++;
            zoneHigh = MathMax(zoneHigh, SwingLows[j].price);
            zoneLow = MathMin(zoneLow, SwingLows[j].price);
            if(SwingLows[j].bar < lastTouch) lastTouch = SwingLows[j].bar;
         }
      }

      // Also check highs that approached this level
      for(int j = 0; j < HighCount; j++)
      {
         double lowOfHighBar = Low[SwingHighs[j].bar];
         if(MathAbs(lowOfHighBar - basePrice) <= zoneRange)
         {
            touchCount++;
            if(SwingHighs[j].bar < lastTouch) lastTouch = SwingHighs[j].bar;
         }
      }

      if(touchCount >= 2)
      {
         bool exists = false;
         for(int z = 0; z < SupportZoneCount; z++)
         {
            if(MathAbs(SupportZones[z].priceHigh - zoneHigh) <= zoneRange &&
               MathAbs(SupportZones[z].priceLow - zoneLow) <= zoneRange)
            {
               exists = true;
               if(touchCount > SupportZones[z].touchCount)
               {
                  SupportZones[z].touchCount = touchCount;
                  SupportZones[z].lastTouchBar = lastTouch;
               }
               break;
            }
         }

         if(!exists)
         {
            SupportZoneCount++;
            ArrayResize(SupportZones, SupportZoneCount);
            SupportZones[SupportZoneCount-1].priceHigh = zoneHigh + atr * 0.1;
            SupportZones[SupportZoneCount-1].priceLow = zoneLow - atr * 0.1;
            SupportZones[SupportZoneCount-1].touchCount = touchCount;
            SupportZones[SupportZoneCount-1].isBullish = true;
            SupportZones[SupportZoneCount-1].lastTouchBar = lastTouch;
         }
      }
   }

   // Draw zones
   DrawConfluenceZones();
}

//+------------------------------------------------------------------+
//| Draw confluence zones                                             |
//+------------------------------------------------------------------+
void DrawConfluenceZones()
{
   // Draw resistance zones
   for(int i = 0; i < ResistanceZoneCount; i++)
   {
      if(ResistanceZones[i].touchCount < 2) continue;

      string objName = IndicatorPrefix + "ResZone_" + IntegerToString(i);
      int startBar = MathMin(ResistanceZones[i].lastTouchBar + 20, Bars - 1);

      if(ObjectFind(objName) < 0)
         ObjectCreate(objName, OBJ_RECTANGLE, 0, Time[startBar], ResistanceZones[i].priceHigh, Time[0], ResistanceZones[i].priceLow);
      else
         ObjectSetDouble(0, objName, OBJPROP_PRICE2, ResistanceZones[i].priceLow); // Update logic

      ObjectSetInteger(0, objName, OBJPROP_COLOR, clrMaroon);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objName, OBJPROP_FILL, true);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);

      // Zone label
      string labelName = IndicatorPrefix + "ResZoneLabel_" + IntegerToString(i);
      if(ObjectFind(labelName) < 0)
         ObjectCreate(labelName, OBJ_TEXT, 0, Time[5], ResistanceZones[i].priceHigh);
      ObjectSetText(labelName, "R(" + IntegerToString(ResistanceZones[i].touchCount) + ")", 7, "Arial", clrRed);
   }

   // Draw support zones
   for(int i = 0; i < SupportZoneCount; i++)
   {
      if(SupportZones[i].touchCount < 2) continue;

      string objName = IndicatorPrefix + "SupZone_" + IntegerToString(i);
      int startBar = MathMin(SupportZones[i].lastTouchBar + 20, Bars - 1);

      if(ObjectFind(objName) < 0)
         ObjectCreate(objName, OBJ_RECTANGLE, 0, Time[startBar], SupportZones[i].priceHigh, Time[0], SupportZones[i].priceLow);
      else
         ObjectSetDouble(0, objName, OBJPROP_PRICE2, SupportZones[i].priceLow);

      ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDarkGreen);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objName, OBJPROP_FILL, true);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);

      string labelName = IndicatorPrefix + "SupZoneLabel_" + IntegerToString(i);
      if(ObjectFind(labelName) < 0)
         ObjectCreate(labelName, OBJ_TEXT, 0, Time[5], SupportZones[i].priceLow);
      ObjectSetText(labelName, "S(" + IntegerToString(SupportZones[i].touchCount) + ")", 7, "Arial", clrGreen);
   }
}

//+------------------------------------------------------------------+
//| Draw swing labels                                                 |
//+------------------------------------------------------------------+
void DrawSwingLabels()
{
   for(int i = 0; i < SwingCount; i++)
   {
      if(AllSwings[i].label == LABEL_NONE) continue;

      string labelText = "";
      color labelColor = clrGray;

      switch(AllSwings[i].label)
      {
         case LABEL_HH: labelText = "HH"; labelColor = HH_Color; break;
         case LABEL_HL: labelText = "HL"; labelColor = HL_Color; break;
         case LABEL_LH: labelText = "LH"; labelColor = LH_Color; break;
         case LABEL_LL: labelText = "LL"; labelColor = LL_Color; break;
         case LABEL_EH: labelText = "EH"; labelColor = clrGray; break;
         case LABEL_EL: labelText = "EL"; labelColor = clrGray; break;
         default: continue;
      }

      // Add confluence indicator
      if(AllSwings[i].confluenceScore >= 4)
         labelText += "*";

      bool isHigh = (AllSwings[i].type == SWING_HIGH);
      CreateSwingLabel(AllSwings[i].bar, AllSwings[i].price, labelText, labelColor, isHigh);
   }
}

//+------------------------------------------------------------------+
//| Create swing label                                                |
//+------------------------------------------------------------------+
void CreateSwingLabel(int bar, double price, string text, color clr, bool isHigh)
{
   string objName = IndicatorPrefix + "Label_" + IntegerToString(bar) + "_" + text;

   double range = High[iHighest(NULL, 0, MODE_HIGH, 50, 0)] - Low[iLowest(NULL, 0, MODE_LOW, 50, 0)];
   double offset = range * 0.025;

   if(!isHigh) offset = -offset;

   ENUM_ANCHOR_POINT anchor = isHigh ? ANCHOR_LOWER : ANCHOR_UPPER;

   if(ObjectFind(objName) < 0)
      ObjectCreate(objName, OBJ_TEXT, 0, Time[bar], price + offset);

   ObjectSetText(objName, text, FontSize, "Arial Bold", clr);
   ObjectSetInteger(0, objName, OBJPROP_ANCHOR, anchor);
}

//+------------------------------------------------------------------+
//| Draw structure lines                                              |
//+------------------------------------------------------------------+
void DrawStructureLines()
{
   for(int i = 1; i < HighCount; i++)
   {
      color lineColor = (SwingHighs[i].label == LABEL_HH) ? HH_Color : LH_Color;
      if(SwingHighs[i].label == LABEL_EH) lineColor = clrGray;
      if(SwingHighs[i].label == LABEL_NONE) continue;

      int width = (SwingHighs[i].confluenceScore >= 3) ? 2 : 1;

      string objName = IndicatorPrefix + "HighLine_" + IntegerToString(i);
      if(ObjectFind(objName) < 0)
         ObjectCreate(objName, OBJ_TREND, 0, Time[SwingHighs[i-1].bar], SwingHighs[i-1].price, Time[SwingHighs[i].bar], SwingHighs[i].price);
      else {
         ObjectSetDouble(0, objName, OBJPROP_PRICE1, SwingHighs[i-1].price);
         ObjectSetDouble(0, objName, OBJPROP_PRICE2, SwingHighs[i].price);
      }

      ObjectSetInteger(0, objName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
   }

   for(int i = 1; i < LowCount; i++)
   {
      color lineColor = (SwingLows[i].label == LABEL_HL) ? HL_Color : LL_Color;
      if(SwingLows[i].label == LABEL_EL) lineColor = clrGray;
      if(SwingLows[i].label == LABEL_NONE) continue;

      int width = (SwingLows[i].confluenceScore >= 3) ? 2 : 1;

      string objName = IndicatorPrefix + "LowLine_" + IntegerToString(i);
      if(ObjectFind(objName) < 0)
         ObjectCreate(objName, OBJ_TREND, 0, Time[SwingLows[i-1].bar], SwingLows[i-1].price, Time[SwingLows[i].bar], SwingLows[i].price);
      else {
         ObjectSetDouble(0, objName, OBJPROP_PRICE1, SwingLows[i-1].price);
         ObjectSetDouble(0, objName, OBJPROP_PRICE2, SwingLows[i].price);
      }

      ObjectSetInteger(0, objName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
   }
}

//+------------------------------------------------------------------+
//| Draw RSI analysis enhanced                                        |
//+------------------------------------------------------------------+
void DrawRSI_AnalysisEnhanced()
{
   int windowIndex = WindowFind("Dow Theory v10.0 SMC [RSI " + IntegerToString(RSI_Period) + "]");
   if(windowIndex < 0) windowIndex = 1;

   if(ShowRSI_TrendLines)
   {
      for(int i = 1; i < HighCount; i++)
      {
         if(SwingHighs[i].label == LABEL_NONE) continue;

         string objName = IndicatorPrefix + "RSI_HighLine_" + IntegerToString(i);
         if(ObjectFind(objName) < 0)
            ObjectCreate(objName, OBJ_TREND, windowIndex, Time[SwingHighs[i-1].bar], SwingHighs[i-1].rsi, Time[SwingHighs[i].bar], SwingHighs[i].rsi);

         ObjectSetInteger(0, objName, OBJPROP_COLOR, BearishTrendColor);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
      }

      for(int i = 1; i < LowCount; i++)
      {
         if(SwingLows[i].label == LABEL_NONE) continue;

         string objName = IndicatorPrefix + "RSI_LowLine_" + IntegerToString(i);
         if(ObjectFind(objName) < 0)
            ObjectCreate(objName, OBJ_TREND, windowIndex, Time[SwingLows[i-1].bar], SwingLows[i-1].rsi, Time[SwingLows[i].bar], SwingLows[i].rsi);

         ObjectSetInteger(0, objName, OBJPROP_COLOR, BullishTrendColor);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
      }
   }

   if(ShowRSI_Divergence) DetectDivergencesEnhanced();

   DrawRSILevelLabels(windowIndex);
}

//+------------------------------------------------------------------+
//| Detect divergences with enhanced accuracy                         |
//+------------------------------------------------------------------+
void DetectDivergencesEnhanced()
{
   int checkRange = MathMin(5, HighCount);

   // Bearish divergence check
   for(int i = 1; i < checkRange; i++)
   {
      int barDist = MathAbs(SwingHighs[HighCount - i].bar - SwingHighs[HighCount - i - 1].bar);
      if(barDist < DivergenceMinBars || barDist > DivergenceMaxBars) continue;

      int idx = HighCount - i;

      // Regular bearish: price HH but RSI lower
      if(SwingHighs[idx].label == LABEL_HH)
      {
         double rsiDiff = SwingHighs[idx-1].rsi - SwingHighs[idx].rsi;

         if(rsiDiff >= MinRSIDivergence)
         {
            if(ValidateDivergenceEnhanced(SwingHighs[idx-1], SwingHighs[idx], DIV_REGULAR_BEARISH))
            {
               HasBearishDivergence = true;
               LastDivergenceBar = SwingHighs[idx].bar;
               DivergenceStrength = rsiDiff;
               DrawDivergenceMarker(SwingHighs[idx].bar, SwingHighs[idx].price, DIV_REGULAR_BEARISH);
               DrawDivergenceLine(SwingHighs[idx-1].bar, SwingHighs[idx-1].price,
                                  SwingHighs[idx].bar, SwingHighs[idx].price, DIV_REGULAR_BEARISH);
               break;  // Only mark strongest
            }
         }
      }
      // Hidden bearish: price LH but RSI higher
      else if(ShowHiddenDivergence && SwingHighs[idx].label == LABEL_LH)
      {
         double rsiDiff = SwingHighs[idx].rsi - SwingHighs[idx-1].rsi;

         if(rsiDiff >= MinRSIDivergence)
         {
            if(ValidateDivergenceEnhanced(SwingHighs[idx-1], SwingHighs[idx], DIV_HIDDEN_BEARISH))
            {
               HasHiddenBearishDiv = true;
               LastDivergenceBar = SwingHighs[idx].bar;
               DivergenceStrength = rsiDiff;
               DrawDivergenceMarker(SwingHighs[idx].bar, SwingHighs[idx].price, DIV_HIDDEN_BEARISH);
               DrawDivergenceLine(SwingHighs[idx-1].bar, SwingHighs[idx-1].price,
                                  SwingHighs[idx].bar, SwingHighs[idx].price, DIV_HIDDEN_BEARISH);
               break;
            }
         }
      }
   }

   checkRange = MathMin(5, LowCount);

   // Bullish divergence check
   for(int i = 1; i < checkRange; i++)
   {
      int barDist = MathAbs(SwingLows[LowCount - i].bar - SwingLows[LowCount - i - 1].bar);
      if(barDist < DivergenceMinBars || barDist > DivergenceMaxBars) continue;

      int idx = LowCount - i;

      // Regular bullish: price LL but RSI higher
      if(SwingLows[idx].label == LABEL_LL)
      {
         double rsiDiff = SwingLows[idx].rsi - SwingLows[idx-1].rsi;

         if(rsiDiff >= MinRSIDivergence)
         {
            if(ValidateDivergenceEnhanced(SwingLows[idx-1], SwingLows[idx], DIV_REGULAR_BULLISH))
            {
               HasBullishDivergence = true;
               LastDivergenceBar = SwingLows[idx].bar;
               DivergenceStrength = rsiDiff;
               DrawDivergenceMarker(SwingLows[idx].bar, SwingLows[idx].price, DIV_REGULAR_BULLISH);
               DrawDivergenceLine(SwingLows[idx-1].bar, SwingLows[idx-1].price,
                                  SwingLows[idx].bar, SwingLows[idx].price, DIV_REGULAR_BULLISH);
               break;
            }
         }
      }
      // Hidden bullish: price HL but RSI lower
      else if(ShowHiddenDivergence && SwingLows[idx].label == LABEL_HL)
      {
         double rsiDiff = SwingLows[idx-1].rsi - SwingLows[idx].rsi;

         if(rsiDiff >= MinRSIDivergence)
         {
            if(ValidateDivergenceEnhanced(SwingLows[idx-1], SwingLows[idx], DIV_HIDDEN_BULLISH))
            {
               HasHiddenBullishDiv = true;
               LastDivergenceBar = SwingLows[idx].bar;
               DivergenceStrength = rsiDiff;
               DrawDivergenceMarker(SwingLows[idx].bar, SwingLows[idx].price, DIV_HIDDEN_BULLISH);
               DrawDivergenceLine(SwingLows[idx-1].bar, SwingLows[idx-1].price,
                                  SwingLows[idx].bar, SwingLows[idx].price, DIV_HIDDEN_BULLISH);
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Validate divergence with enhanced checks                          |
//+------------------------------------------------------------------+
bool ValidateDivergenceEnhanced(SwingPoint &sp1, SwingPoint &sp2, DIVERGENCE_TYPE divType)
{
   // RSI zone validation
   switch(divType)
   {
      case DIV_REGULAR_BEARISH:
         if(sp2.rsi < 45) return false;  // RSI should be elevated
         break;
      case DIV_REGULAR_BULLISH:
         if(sp2.rsi > 55) return false;  // RSI should be depressed
         break;
      case DIV_HIDDEN_BEARISH:
         if(sp2.rsi < 40) return false;
         break;
      case DIV_HIDDEN_BULLISH:
         if(sp2.rsi > 60) return false;
         break;
   }

   // Price move validation
   double priceDiff = MathAbs(sp2.price - sp1.price);
   if(priceDiff < sp2.atr * 0.5) return false;

   // Check RSI didn't cross middle significantly between points
   int startBar = MathMax(sp1.bar, sp2.bar);
   int endBar = MathMin(sp1.bar, sp2.bar);

   if(divType == DIV_REGULAR_BEARISH || divType == DIV_HIDDEN_BEARISH)
   {
      // For bearish div, RSI shouldn't have gone oversold between points
      for(int i = endBar; i <= startBar; i++)
      {
         if(RSI_Buffer[i] < 25) return false;
      }
   }
   else
   {
      // For bullish div, RSI shouldn't have gone overbought between points
      for(int i = endBar; i <= startBar; i++)
      {
         if(RSI_Buffer[i] > 75) return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Draw divergence marker                                            |
//+------------------------------------------------------------------+
void DrawDivergenceMarker(int bar, double price, DIVERGENCE_TYPE divType)
{
   string objName = IndicatorPrefix + "Div_" + IntegerToString(bar);
   double offset = GetATRAtBar(0) * 0.6;

   string divText = "";
   color divColor = clrGray;
   bool isAbove = false;

   switch(divType)
   {
      case DIV_REGULAR_BULLISH: divText = "DIV+"; divColor = BullishTrendColor; isAbove = false; break;
      case DIV_REGULAR_BEARISH: divText = "DIV-"; divColor = BearishTrendColor; isAbove = true; break;
      case DIV_HIDDEN_BULLISH: divText = "hDIV+"; divColor = clrDodgerBlue; isAbove = false; break;
      case DIV_HIDDEN_BEARISH: divText = "hDIV-"; divColor = clrOrange; isAbove = true; break;
   }

   double labelPrice = isAbove ? price + offset : price - offset;

   if(ObjectFind(objName) < 0)
      ObjectCreate(objName, OBJ_TEXT, 0, Time[bar], labelPrice);

   ObjectSetText(objName, divText, FontSize - 1, "Arial Bold", divColor);
   ObjectSetInteger(0, objName, OBJPROP_ANCHOR, isAbove ? ANCHOR_LOWER : ANCHOR_UPPER);
}

//+------------------------------------------------------------------+
//| Draw divergence line                                              |
//+------------------------------------------------------------------+
void DrawDivergenceLine(int bar1, double price1, int bar2, double price2, DIVERGENCE_TYPE divType)
{
   string objName = IndicatorPrefix + "DivLine_" + IntegerToString(bar2);

   color lineColor = clrGray;
   int lineStyle = STYLE_DOT;

   switch(divType)
   {
      case DIV_REGULAR_BULLISH: lineColor = BullishTrendColor; lineStyle = STYLE_SOLID; break;
      case DIV_REGULAR_BEARISH: lineColor = BearishTrendColor; lineStyle = STYLE_SOLID; break;
      case DIV_HIDDEN_BULLISH: lineColor = clrDodgerBlue; lineStyle = STYLE_DASH; break;
      case DIV_HIDDEN_BEARISH: lineColor = clrOrange; lineStyle = STYLE_DASH; break;
   }

   if(ObjectFind(objName) < 0)
      ObjectCreate(objName, OBJ_TREND, 0, Time[bar1], price1, Time[bar2], price2);
   else {
      ObjectSetDouble(0, objName, OBJPROP_PRICE1, price1);
      ObjectSetDouble(0, objName, OBJPROP_PRICE2, price2);
   }

   ObjectSetInteger(0, objName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, lineStyle);
   ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
}

//+------------------------------------------------------------------+
//| Draw RSI level labels                                             |
//+------------------------------------------------------------------+
void DrawRSILevelLabels(int windowIndex)
{
   string obName = IndicatorPrefix + "RSI_OB";
   if(ObjectFind(obName) < 0)
      ObjectCreate(obName, OBJ_TEXT, windowIndex, Time[10], 75);
   ObjectSetText(obName, "Overbought", 8, "Arial", clrRed);

   string osName = IndicatorPrefix + "RSI_OS";
   if(ObjectFind(osName) < 0)
      ObjectCreate(osName, OBJ_TEXT, windowIndex, Time[10], 25);
   ObjectSetText(osName, "Oversold", 8, "Arial", clrGreen);
}

//+------------------------------------------------------------------+
//| Detect and draw necklines enhanced                                |
//+------------------------------------------------------------------+
void DetectAndDrawNecklinesEnhanced()
{
   if(HighCount < 2 || LowCount < 2) return;

   int latestBearishPatternIdx = -1;
   int latestBullishPatternIdx = -1;
   int latestBearishBar = 999999;
   int latestBullishBar = 999999;

   for(int i = HighCount - 1; i >= 1; i--)
   {
      if(SwingHighs[i].label == LABEL_LH && SwingHighs[i-1].label == LABEL_HH)
      {
         latestBearishPatternIdx = i;
         latestBearishBar = SwingHighs[i].bar;
         break;
      }
   }

   for(int i = LowCount - 1; i >= 1; i--)
   {
      if(SwingLows[i].label == LABEL_HL && SwingLows[i-1].label == LABEL_LL)
      {
         latestBullishPatternIdx = i;
         latestBullishBar = SwingLows[i].bar;
         break;
      }
   }

   bool drawBearish = false;
   bool drawBullish = false;

   if(latestBearishPatternIdx >= 0 && latestBullishPatternIdx >= 0)
   {
      if(latestBearishBar < latestBullishBar) drawBearish = true;
      else drawBullish = true;
   }
   else if(latestBearishPatternIdx >= 0) drawBearish = true;
   else if(latestBullishPatternIdx >= 0) drawBullish = true;

   if(drawBearish && latestBearishPatternIdx >= 0)
   {
      int i = latestBearishPatternIdx;
      double necklineLevel = FindLowestBetween(SwingHighs[i-1].bar, SwingHighs[i].bar);

      CurrentNeckline = necklineLevel;
      NecklineIsBullish = false;

      if(necklineLevel > 0 && ShowNecklines)
         DrawNeckline(SwingHighs[i-1].bar, SwingHighs[i].bar, necklineLevel, false);

      if(ShowBOS && necklineLevel > 0)
      {
         int breakBar = FindNecklineBreakEnhanced(SwingHighs[i].bar, necklineLevel, false);
         if(breakBar >= 0)
         {
            BOSDetected = true;
            BOSIsBullish = false;
            BOSBar = breakBar;
            BOSLevel = necklineLevel;
            DrawBOSMarker(breakBar, necklineLevel, false);
         }
      }
   }

   if(drawBullish && latestBullishPatternIdx >= 0)
   {
      int i = latestBullishPatternIdx;
      double necklineLevel = FindHighestBetween(SwingLows[i-1].bar, SwingLows[i].bar);

      CurrentNeckline = necklineLevel;
      NecklineIsBullish = true;

      if(necklineLevel > 0 && ShowNecklines)
         DrawNeckline(SwingLows[i-1].bar, SwingLows[i].bar, necklineLevel, true);

      if(ShowBOS && necklineLevel > 0)
      {
         int breakBar = FindNecklineBreakEnhanced(SwingLows[i].bar, necklineLevel, true);
         if(breakBar >= 0)
         {
            BOSDetected = true;
            BOSIsBullish = true;
            BOSBar = breakBar;
            BOSLevel = necklineLevel;
            DrawBOSMarker(breakBar, necklineLevel, true);
         }
      }
   }

   DrawKeyStructureLevels();
}

//+------------------------------------------------------------------+
//| Find lowest/highest between bars                                  |
//+------------------------------------------------------------------+
double FindLowestBetween(int bar1, int bar2)
{
   int startBar = MathMax(bar1, bar2);
   int endBar = MathMin(bar1, bar2);
   int lowestBar = iLowest(NULL, 0, MODE_LOW, startBar - endBar + 1, endBar);
   if(lowestBar >= 0) return Low[lowestBar];
   return 0;
}

double FindHighestBetween(int bar1, int bar2)
{
   int startBar = MathMax(bar1, bar2);
   int endBar = MathMin(bar1, bar2);
   int highestBar = iHighest(NULL, 0, MODE_HIGH, startBar - endBar + 1, endBar);
   if(highestBar >= 0) return High[highestBar];
   return 0;
}

//+------------------------------------------------------------------+
//| Find neckline break enhanced                                      |
//+------------------------------------------------------------------+
int FindNecklineBreakEnhanced(int startBar, double necklineLevel, bool bullishBreak)
{
   double atr = GetATRAtBar(0);
   double minBreakDistance = atr * BOSMinATRBreak;

   for(int i = startBar - 1; i >= BOSConfirmationBars; i--)
   {
      if(bullishBreak)
      {
         bool levelBroken = false;

         if(RequireBOSBodyClose)
         {
            // Body must close above neckline with minimum distance
            levelBroken = (Close[i] > necklineLevel + minBreakDistance && Close[i+1] <= necklineLevel);
         }
         else
         {
            levelBroken = (High[i] > necklineLevel + minBreakDistance && High[i+1] <= necklineLevel);
         }

         if(levelBroken)
         {
            bool confirmed = true;
            for(int j = 1; j <= BOSConfirmationBars && i - j >= 0; j++)
            {
               if((RequireBOSBodyClose && Close[i-j] < necklineLevel) ||
                  (!RequireBOSBodyClose && Low[i-j] < necklineLevel - minBreakDistance))
               { confirmed = false; break; }
            }

            if(confirmed)
            {
               // Check for retest if required
               if(RequireBOSRetest)
               {
                  bool retested = false;
                  for(int j = 1; j <= 10 && i - j >= 0; j++)
                  {
                     if(Low[i-j] <= necklineLevel + atr * 0.2 && Close[i-j] > necklineLevel)
                     {
                        retested = true;
                        return i - j;
                     }
                  }
                  if(!retested) continue;  // No retest yet
               }
               return i;
            }
         }
      }
      else
      {
         bool levelBroken = false;

         if(RequireBOSBodyClose)
         {
            levelBroken = (Close[i] < necklineLevel - minBreakDistance && Close[i+1] >= necklineLevel);
         }
         else
         {
            levelBroken = (Low[i] < necklineLevel - minBreakDistance && Low[i+1] >= necklineLevel);
         }

         if(levelBroken)
         {
            bool confirmed = true;
            for(int j = 1; j <= BOSConfirmationBars && i - j >= 0; j++)
            {
               if((RequireBOSBodyClose && Close[i-j] > necklineLevel) ||
                  (!RequireBOSBodyClose && High[i-j] > necklineLevel + minBreakDistance))
               { confirmed = false; break; }
            }

            if(confirmed)
            {
               if(RequireBOSRetest)
               {
                  bool retested = false;
                  for(int j = 1; j <= 10 && i - j >= 0; j++)
                  {
                     if(High[i-j] >= necklineLevel - atr * 0.2 && Close[i-j] < necklineLevel)
                     {
                        retested = true;
                        return i - j;
                     }
                  }
                  if(!retested) continue;
               }
               return i;
            }
         }
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Draw neckline                                                     |
//+------------------------------------------------------------------+
void DrawNeckline(int bar1, int bar2, double level, bool isBullish)
{
   string objName = IndicatorPrefix + "Neckline_" + IntegerToString(bar1);
   int extendBars = MathMin(bar2, 20);

   if(ObjectFind(objName) < 0)
      ObjectCreate(objName, OBJ_TREND, 0, Time[bar1], level, Time[MathMax(0, bar2 - extendBars)], level);

   ObjectSetInteger(0, objName, OBJPROP_COLOR, NecklineColor);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, NecklineWidth);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, NecklineStyle);
   ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, true);

   string labelName = IndicatorPrefix + "NeckLabel_" + IntegerToString(bar1);
   double offset = GetATRAtBar(0) * 0.3;

   if(ObjectFind(labelName) < 0)
      ObjectCreate(labelName, OBJ_TEXT, 0, Time[bar2], level + (isBullish ? offset : -offset));

   ObjectSetText(labelName, "NECKLINE", FontSize - 2, "Arial", NecklineColor);
}

//+------------------------------------------------------------------+
//| Draw BOS marker                                                   |
//+------------------------------------------------------------------+
void DrawBOSMarker(int bar, double level, bool isBullish)
{
   string objName = IndicatorPrefix + "BOS_" + IntegerToString(bar);
   color bosColor = isBullish ? BullishBOSColor : BearishBOSColor;
   string bosText = isBullish ? "BOS UP" : "BOS DN";

   double offset = GetATRAtBar(0) * 0.5;
   double labelPrice = isBullish ? level + offset : level - offset;

   if(ObjectFind(objName) < 0)
      ObjectCreate(objName, OBJ_TEXT, 0, Time[bar], labelPrice);

   ObjectSetText(objName, bosText, FontSize, "Arial Bold", bosColor);
   ObjectSetInteger(0, objName, OBJPROP_ANCHOR, isBullish ? ANCHOR_LOWER : ANCHOR_UPPER);

   string arrowName = IndicatorPrefix + "BOSArrow_" + IntegerToString(bar);
   if(ObjectFind(arrowName) < 0)
      ObjectCreate(arrowName, OBJ_ARROW, 0, Time[bar], level);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, isBullish ? 233 : 234);
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, bosColor);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
}

//+------------------------------------------------------------------+
//| Draw key structure levels                                         |
//+------------------------------------------------------------------+
void DrawKeyStructureLevels()
{
   if(HighCount < 1 || LowCount < 1) return;

   int lastHighIdx = HighCount - 1;
   string resName = IndicatorPrefix + "Resistance";
   if(ObjectFind(resName) < 0)
      ObjectCreate(resName, OBJ_HLINE, 0, 0, SwingHighs[lastHighIdx].price);
   else
      ObjectSetDouble(0, resName, OBJPROP_PRICE1, SwingHighs[lastHighIdx].price);

   ObjectSetInteger(0, resName, OBJPROP_COLOR, LH_Color);
   ObjectSetInteger(0, resName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, resName, OBJPROP_STYLE, STYLE_DOT);

   int lastLowIdx = LowCount - 1;
   string supName = IndicatorPrefix + "Support";
   if(ObjectFind(supName) < 0)
      ObjectCreate(supName, OBJ_HLINE, 0, 0, SwingLows[lastLowIdx].price);
   else
      ObjectSetDouble(0, supName, OBJPROP_PRICE1, SwingLows[lastLowIdx].price);

   ObjectSetInteger(0, supName, OBJPROP_COLOR, HL_Color);
   ObjectSetInteger(0, supName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, supName, OBJPROP_STYLE, STYLE_DOT);
}

//+------------------------------------------------------------------+
//| Generate HTF trading signals with confluence scoring              |
//+------------------------------------------------------------------+
void GenerateTradingSignalsEnhanced()
{
   if(HighCount < 2 || LowCount < 2) return;

   double bidPrice = MarketInfo(Symbol(), MODE_BID);
   double askPrice = MarketInfo(Symbol(), MODE_ASK);
   double spread = askPrice - bidPrice;
   double atr = GetATRAtBar(0);
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   SWING_LABEL lastHigh = SwingHighs[HighCount - 1].label;
   SWING_LABEL prevHigh = (HighCount >= 2) ? SwingHighs[HighCount - 2].label : LABEL_NONE;
   SWING_LABEL lastLow = SwingLows[LowCount - 1].label;
   SWING_LABEL prevLow = (LowCount >= 2) ? SwingLows[LowCount - 2].label : LABEL_NONE;

   double lastHighPrice = SwingHighs[HighCount - 1].price;
   double lastLowPrice = SwingLows[LowCount - 1].price;
   int lastHighConfluence = SwingHighs[HighCount - 1].confluenceScore;
   int lastLowConfluence = SwingLows[LowCount - 1].confluenceScore;

   // Calculate confluence score
   int confluenceScore = 0;
   string confluenceDetails = "";

   // Trend alignment
   if(CurrentTrend == TREND_BULLISH) { confluenceScore += 1; confluenceDetails += "Trend+ "; }
   else if(CurrentTrend == TREND_BEARISH) { confluenceScore += 1; confluenceDetails += "Trend- "; }

   // BOS
   if(BOSDetected && BOSBar <= 10)
   {
      confluenceScore += 2;
      confluenceDetails += BOSIsBullish ? "BOS+ " : "BOS- ";
   }

   // Divergence
   if(HasBullishDivergence || HasHiddenBullishDiv)
   {
      confluenceScore += 1;
      confluenceDetails += "Div+ ";
   }
   if(HasBearishDivergence || HasHiddenBearishDiv)
   {
      confluenceScore += 1;
      confluenceDetails += "Div- ";
   }

   // RSI position
   double currentRSI = RSI_Buffer[0];
   if(currentRSI < 35) { confluenceScore += 1; confluenceDetails += "RSI_OS "; }
   else if(currentRSI > 65) { confluenceScore += 1; confluenceDetails += "RSI_OB "; }

   // Swing quality
   if(lastHighConfluence >= 3 || lastLowConfluence >= 3)
   {
      confluenceScore += 1;
      confluenceDetails += "Quality ";
   }

   // Price at key level
   if(MathAbs(bidPrice - lastHighPrice) <= atr * 0.5 || MathAbs(bidPrice - lastLowPrice) <= atr * 0.5)
   {
      confluenceScore += 1;
      confluenceDetails += "AtLevel ";
   }

   CurrentSignal.confluenceScore = confluenceScore;
   CurrentSignal.confluenceDetails = confluenceDetails;

   // ========== GENERATE SIGNALS ==========

   // SELL SIGNALS
   if(BOSDetected && !BOSIsBullish && BOSBar <= 10)
   {
      if((HasBearishDivergence || HasHiddenBearishDiv) && confluenceScore >= MinConfluenceScore)
      {
         CurrentSignal.type = SIG_SELL_STRONG;
         CurrentSignal.description = "BOS DN + DIV [" + IntegerToString(confluenceScore) + "]";
         CurrentSignal.hasDivergence = true;
         CurrentSignal.divergenceType = HasBearishDivergence ? "Regular Bearish" : "Hidden Bearish";
      }
      else if(confluenceScore >= MinConfluenceScore - 1)
      {
         CurrentSignal.type = SIG_SELL_MODERATE;
         CurrentSignal.description = "BOS DN [" + IntegerToString(confluenceScore) + "]";
      }
      else
      {
         CurrentSignal.type = SIG_SELL_WEAK;
         CurrentSignal.description = "BOS DN (low conf)";
      }
      CurrentSignal.entryPrice = NormalizeDouble(bidPrice, digits);
      CurrentSignal.stopLoss = NormalizeDouble(lastHighPrice + atr * 0.5 + spread, digits);
      CurrentSignal.takeProfit = NormalizeDouble(lastLowPrice - atr - spread, digits);
      CurrentSignal.bosConfirmed = true;
      CurrentSignal.bosDirection = "DOWN";
      CurrentSignal.necklineLevel = CurrentNeckline;
   }
   else if(lastHigh == LABEL_LH && prevHigh == LABEL_HH && CurrentTrend != TREND_BULLISH)
   {
      if(confluenceScore >= MinConfluenceScore)
      {
         CurrentSignal.type = HasBearishDivergence ? SIG_SELL_MODERATE : SIG_SELL_WEAK;
         CurrentSignal.description = HasBearishDivergence ? "LH + DIV [" + IntegerToString(confluenceScore) + "]" : "LH [" + IntegerToString(confluenceScore) + "]";
         CurrentSignal.hasDivergence = HasBearishDivergence;
      }
      else
      {
         CurrentSignal.type = SIG_WAIT;
         CurrentSignal.description = "LH - Need more confluence";
      }
      CurrentSignal.entryPrice = NormalizeDouble(bidPrice, digits);
      CurrentSignal.stopLoss = NormalizeDouble(lastHighPrice + atr * 0.3 + spread, digits);
      CurrentSignal.takeProfit = NormalizeDouble(lastLowPrice - spread, digits);
      CurrentSignal.necklineLevel = CurrentNeckline;
   }
   // BUY SIGNALS
   else if(BOSDetected && BOSIsBullish && BOSBar <= 10)
   {
      if((HasBullishDivergence || HasHiddenBullishDiv) && confluenceScore >= MinConfluenceScore)
      {
         CurrentSignal.type = SIG_BUY_STRONG;
         CurrentSignal.description = "BOS UP + DIV [" + IntegerToString(confluenceScore) + "]";
         CurrentSignal.hasDivergence = true;
         CurrentSignal.divergenceType = HasBullishDivergence ? "Regular Bullish" : "Hidden Bullish";
      }
      else if(confluenceScore >= MinConfluenceScore - 1)
      {
         CurrentSignal.type = SIG_BUY_MODERATE;
         CurrentSignal.description = "BOS UP [" + IntegerToString(confluenceScore) + "]";
      }
      else
      {
         CurrentSignal.type = SIG_BUY_WEAK;
         CurrentSignal.description = "BOS UP (low conf)";
      }
      CurrentSignal.entryPrice = NormalizeDouble(askPrice, digits);
      CurrentSignal.stopLoss = NormalizeDouble(lastLowPrice - atr * 0.5 - spread, digits);
      CurrentSignal.takeProfit = NormalizeDouble(lastHighPrice + atr + spread, digits);
      CurrentSignal.bosConfirmed = true;
      CurrentSignal.bosDirection = "UP";
      CurrentSignal.necklineLevel = CurrentNeckline;
   }
   else if(lastLow == LABEL_HL && prevLow == LABEL_LL && CurrentTrend != TREND_BEARISH)
   {
      if(confluenceScore >= MinConfluenceScore)
      {
         CurrentSignal.type = HasBullishDivergence ? SIG_BUY_MODERATE : SIG_BUY_WEAK;
         CurrentSignal.description = HasBullishDivergence ? "HL + DIV [" + IntegerToString(confluenceScore) + "]" : "HL [" + IntegerToString(confluenceScore) + "]";
         CurrentSignal.hasDivergence = HasBullishDivergence;
      }
      else
      {
         CurrentSignal.type = SIG_WAIT;
         CurrentSignal.description = "HL - Need more confluence";
      }
      CurrentSignal.entryPrice = NormalizeDouble(askPrice, digits);
      CurrentSignal.stopLoss = NormalizeDouble(lastLowPrice - atr * 0.3 - spread, digits);
      CurrentSignal.takeProfit = NormalizeDouble(lastHighPrice + spread, digits);
      CurrentSignal.necklineLevel = CurrentNeckline;
   }
   else if(CurrentTrend == TREND_RANGING)
   {
      CurrentSignal.type = SIG_WAIT;
      CurrentSignal.description = "Ranging - Wait for BOS";
      CurrentSignal.necklineLevel = CurrentNeckline;
   }
   else
   {
      CurrentSignal.type = SIG_WAIT;
      CurrentSignal.description = "No clear setup";
   }
}

//+------------------------------------------------------------------+
//| Generate MTF Entry Signals Enhanced                               |
//+------------------------------------------------------------------+
void GenerateMTFEntrySignalsEnhanced()
{
   MTFEntry.entryTF = EntryTFString;

   double ltfClose = iClose(NULL, EntryTimeframe, 0);
   double ltfRSI = iRSI(NULL, EntryTimeframe, RSI_Period, PRICE_CLOSE, 0);
   double ltfATR = iATR(NULL, EntryTimeframe, ATR_Period, 0);

   if(ltfATR <= 0) ltfATR = GetATRAtBar(0) * 0.25;

   MTFEntry.ltfRSI = ltfRSI;

   // Find LTF swing points
   double ltfSwingHigh = 0, ltfSwingLow = 0;
   int ltfSwingHighBar = -1, ltfSwingLowBar = -1;
   bool foundHigh = false, foundLow = false;

   for(int i = MTF_SwingLookback; i < 100; i++)
   {
      if(!foundHigh && IsLTFSwingHigh(i))
      {
         ltfSwingHigh = iHigh(NULL, EntryTimeframe, i);
         ltfSwingHighBar = i;
         foundHigh = true;
      }
      if(!foundLow && IsLTFSwingLow(i))
      {
         ltfSwingLow = iLow(NULL, EntryTimeframe, i);
         ltfSwingLowBar = i;
         foundLow = true;
      }
      if(foundHigh && foundLow) break;
   }

   // Find second LTF swings for labeling
   double ltfSwingHigh2 = 0, ltfSwingLow2 = 0;
   bool foundHigh2 = false, foundLow2 = false;

   if(ltfSwingHighBar > 0)
   {
      for(int i = ltfSwingHighBar + MTF_MinSwingBars; i < 150; i++)
      {
         if(IsLTFSwingHigh(i))
         {
            ltfSwingHigh2 = iHigh(NULL, EntryTimeframe, i);
            foundHigh2 = true;
            break;
         }
      }
   }

   if(ltfSwingLowBar > 0)
   {
      for(int i = ltfSwingLowBar + MTF_MinSwingBars; i < 150; i++)
      {
         if(IsLTFSwingLow(i))
         {
            ltfSwingLow2 = iLow(NULL, EntryTimeframe, i);
            foundLow2 = true;
            break;
         }
      }
   }

   // Label LTF swings
   if(foundHigh && foundHigh2)
   {
      double tol = ltfATR * EqualSwingTolerance;
      if(ltfSwingHigh > ltfSwingHigh2 + tol) MTFEntry.lastLTFHighLabel = LABEL_HH;
      else if(ltfSwingHigh < ltfSwingHigh2 - tol) MTFEntry.lastLTFHighLabel = LABEL_LH;
      else MTFEntry.lastLTFHighLabel = LABEL_EH;
   }

   if(foundLow && foundLow2)
   {
      double tol = ltfATR * EqualSwingTolerance;
      if(ltfSwingLow > ltfSwingLow2 + tol) MTFEntry.lastLTFLowLabel = LABEL_HL;
      else if(ltfSwingLow < ltfSwingLow2 - tol) MTFEntry.lastLTFLowLabel = LABEL_LL;
      else MTFEntry.lastLTFLowLabel = LABEL_EL;
   }

   MTFEntry.ltfResistance = foundHigh ? ltfSwingHigh : 0;
   MTFEntry.ltfSupport = foundLow ? ltfSwingLow : 0;

   // Check HTF-LTF alignment
   MTFEntry.htfLtfAligned = false;
   MTFEntry.alignmentScore = 0;

   bool isSellSetup = (CurrentSignal.type == SIG_SELL_STRONG || CurrentSignal.type == SIG_SELL_MODERATE || CurrentSignal.type == SIG_SELL_WEAK);
   bool isBuySetup = (CurrentSignal.type == SIG_BUY_STRONG || CurrentSignal.type == SIG_BUY_MODERATE || CurrentSignal.type == SIG_BUY_WEAK);

   if(isSellSetup && MTFEntry.lastLTFHighLabel == LABEL_LH)
   {
      MTFEntry.htfLtfAligned = true;
      MTFEntry.alignmentScore += 2;
   }
   if(isBuySetup && MTFEntry.lastLTFLowLabel == LABEL_HL)
   {
      MTFEntry.htfLtfAligned = true;
      MTFEntry.alignmentScore += 2;
   }

   // RSI alignment bonus
   if(isSellSetup && ltfRSI > MTF_RSI_Overbought) MTFEntry.alignmentScore += 1;
   if(isBuySetup && ltfRSI < MTF_RSI_Oversold) MTFEntry.alignmentScore += 1;

   double bidPrice = MarketInfo(Symbol(), MODE_BID);
   double askPrice = MarketInfo(Symbol(), MODE_ASK);
   double spread = askPrice - bidPrice;
   double htfATR = GetATRAtBar(0);
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   // ========== GENERATE MTF ENTRY ==========

   // HTF SELL Signal
   if(isSellSetup)
   {
      if(!foundHigh)
      {
         MTFEntry.type = MTF_WAIT;
         MTFEntry.description = "No LTF swing high";
         MTFEntry.condition = "Wait for LTF structure";
      }
      else if(MTF_RequireAlignment && !MTFEntry.htfLtfAligned)
      {
         MTFEntry.type = MTF_WAIT;
         MTFEntry.description = "LTF not aligned (need LH)";
         MTFEntry.condition = "Wait for LTF LH";
      }
      else if(MTF_UseRSIFilter && ltfRSI < 45)
      {
         MTFEntry.type = MTF_WAIT;
         MTFEntry.description = "LTF RSI too low for sell";
         MTFEntry.condition = "Wait for RSI > 45";
      }
      else if(MTFEntry.lastLTFHighLabel == LABEL_LH || bidPrice >= ltfSwingHigh - ltfATR * 0.5)
      {
         MTFEntry.type = MTF_SELL_NOW;
         MTFEntry.description = MTFEntry.htfLtfAligned ? "Aligned SELL [" + IntegerToString(MTFEntry.alignmentScore) + "]" : "SELL at resistance";
         MTFEntry.entryPrice = NormalizeDouble(bidPrice, digits);
         double slBase = MathMax(ltfSwingHigh, bidPrice) + ltfATR * 0.5 + spread;
         MTFEntry.stopLoss = NormalizeDouble(slBase, digits);
         MTFEntry.takeProfit = NormalizeDouble(KeySupport - spread, digits);
         MTFEntry.isActive = true;
         MTFEntry.condition = "SELL @ " + DoubleToString(MTFEntry.entryPrice, digits);
      }
      else if(ltfSwingHigh > bidPrice)
      {
         MTFEntry.type = MTF_SELL_PENDING;
         MTFEntry.description = "Wait for pullback";
         MTFEntry.pendingLevel = NormalizeDouble(ltfSwingHigh - ltfATR * 0.1, digits);
         MTFEntry.entryPrice = MTFEntry.pendingLevel;
         MTFEntry.stopLoss = NormalizeDouble(ltfSwingHigh + ltfATR * 0.5 + spread, digits);
         MTFEntry.takeProfit = NormalizeDouble(KeySupport - spread, digits);
         MTFEntry.isActive = false;
         MTFEntry.condition = "SELL LIMIT @ " + DoubleToString(MTFEntry.pendingLevel, digits);
      }
      else
      {
         MTFEntry.type = MTF_WAIT;
         MTFEntry.description = "Wait for LTF pullback";
         MTFEntry.condition = "No entry yet";
      }
   }
   // HTF BUY Signal
   else if(isBuySetup)
   {
      if(!foundLow)
      {
         MTFEntry.type = MTF_WAIT;
         MTFEntry.description = "No LTF swing low";
         MTFEntry.condition = "Wait for LTF structure";
      }
      else if(MTF_RequireAlignment && !MTFEntry.htfLtfAligned)
      {
         MTFEntry.type = MTF_WAIT;
         MTFEntry.description = "LTF not aligned (need HL)";
         MTFEntry.condition = "Wait for LTF HL";
      }
      else if(MTF_UseRSIFilter && ltfRSI > 55)
      {
         MTFEntry.type = MTF_WAIT;
         MTFEntry.description = "LTF RSI too high for buy";
         MTFEntry.condition = "Wait for RSI < 55";
      }
      else if(MTFEntry.lastLTFLowLabel == LABEL_HL || askPrice <= ltfSwingLow + ltfATR * 0.5)
      {
         MTFEntry.type = MTF_BUY_NOW;
         MTFEntry.description = MTFEntry.htfLtfAligned ? "Aligned BUY [" + IntegerToString(MTFEntry.alignmentScore) + "]" : "BUY at support";
         MTFEntry.entryPrice = NormalizeDouble(askPrice, digits);
         double slBase = MathMin(ltfSwingLow, askPrice) - ltfATR * 0.5 - spread;
         MTFEntry.stopLoss = NormalizeDouble(slBase, digits);
         MTFEntry.takeProfit = NormalizeDouble(KeyResistance + spread, digits);
         MTFEntry.isActive = true;
         MTFEntry.condition = "BUY @ " + DoubleToString(MTFEntry.entryPrice, digits);
      }
      else if(ltfSwingLow < askPrice && ltfSwingLow > 0)
      {
         MTFEntry.type = MTF_BUY_PENDING;
         MTFEntry.description = "Wait for pullback";
         MTFEntry.pendingLevel = NormalizeDouble(ltfSwingLow + ltfATR * 0.1, digits);
         MTFEntry.entryPrice = MTFEntry.pendingLevel;
         MTFEntry.stopLoss = NormalizeDouble(ltfSwingLow - ltfATR * 0.5 - spread, digits);
         MTFEntry.takeProfit = NormalizeDouble(KeyResistance + spread, digits);
         MTFEntry.isActive = false;
         MTFEntry.condition = "BUY LIMIT @ " + DoubleToString(MTFEntry.pendingLevel, digits);
      }
      else
      {
         MTFEntry.type = MTF_WAIT;
         MTFEntry.description = "Wait for LTF pullback";
         MTFEntry.condition = "No entry yet";
      }
   }
   else
   {
      MTFEntry.type = MTF_WAIT;
      MTFEntry.description = "No HTF signal";
      MTFEntry.condition = "Wait for HTF setup";
   }

   // Send MTF alert
   if(EnableAlerts && AlertOnMTFEntry && MTFEntry.isActive)
   {
      SendMTFAlert();
   }
}

//+------------------------------------------------------------------+
//| Check if bar is LTF swing high                                    |
//+------------------------------------------------------------------+
bool IsLTFSwingHigh(int bar)
{
   double currentHigh = iHigh(NULL, EntryTimeframe, bar);
   double ltfATR = iATR(NULL, EntryTimeframe, ATR_Period, bar);

   for(int i = 1; i <= MTF_SwingLookback; i++)
   {
      if(iHigh(NULL, EntryTimeframe, bar + i) >= currentHigh) return false;
      if(iHigh(NULL, EntryTimeframe, bar - i) >= currentHigh) return false;
   }

   double localLow = iLow(NULL, EntryTimeframe, iLowest(NULL, EntryTimeframe, MODE_LOW, MTF_SwingLookback * 2 + 1, bar - MTF_SwingLookback));
   if((currentHigh - localLow) < ltfATR * MTF_ATRMultiplier) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is LTF swing low                                     |
//+------------------------------------------------------------------+
bool IsLTFSwingLow(int bar)
{
   double currentLow = iLow(NULL, EntryTimeframe, bar);
   double ltfATR = iATR(NULL, EntryTimeframe, ATR_Period, bar);

   for(int i = 1; i <= MTF_SwingLookback; i++)
   {
      if(iLow(NULL, EntryTimeframe, bar + i) <= currentLow) return false;
      if(iLow(NULL, EntryTimeframe, bar - i) <= currentLow) return false;
   }

   double localHigh = iHigh(NULL, EntryTimeframe, iHighest(NULL, EntryTimeframe, MODE_HIGH, MTF_SwingLookback * 2 + 1, bar - MTF_SwingLookback));
   if((localHigh - currentLow) < ltfATR * MTF_ATRMultiplier) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Send MTF Entry Alert                                              |
//+------------------------------------------------------------------+
void SendMTFAlert()
{
   string alertMsg = Symbol() + " " + GetTimeframeString() + " MTF Entry: " + MTFEntry.condition;
   if(MTFEntry.htfLtfAligned) alertMsg += " [ALIGNED]";

   if(alertMsg != LastAlertMessage || TimeCurrent() - LastAlertTime > 3600)
   {
      Alert(alertMsg);
      if(SendPushNotification) SendNotification(alertMsg);

      LastAlertMessage = alertMsg;
      LastAlertTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Get timeframe string                                              |
//+------------------------------------------------------------------+
string GetTimeframeString()
{
   switch(Period())
   {
      case PERIOD_H1: return "H1";
      case PERIOD_H4: return "H4";
      case PERIOD_D1: return "D1";
      default: return "??";
   }
}

//+------------------------------------------------------------------+
//| Draw Signal Panel                                                 |
//+------------------------------------------------------------------+
void DrawSignalPanel()
{
   int x = PanelX;
   int y = PanelY;
   int width = PanelWidth;
   int lineHeight = 18;
   int padding = 10;
   int currentY = y;
   int panelHeight = 580;

   // Panel background
   string bgName = IndicatorPrefix + "PanelBG";
   if(ObjectFind(bgName) < 0) {
      ObjectCreate(bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, bgName, OBJPROP_XSIZE, width);
      ObjectSetInteger(0, bgName, OBJPROP_YSIZE, panelHeight);
      ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, PanelBgColor);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgName, OBJPROP_COLOR, PanelBorderColor);
      ObjectSetInteger(0, bgName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
   }

   currentY += padding;

   // Title
   CreatePanelLabel("Title", "DOW THEORY v10.0 SMC", x + padding, currentY, clrGold, PanelFontSize + 2, true);
   currentY += lineHeight;
   CreatePanelLabel("TitleTF", "HTF: " + GetTimeframeString() + " | Entry: " + EntryTFString, x + padding, currentY, clrSilver, PanelFontSize - 1, false);
   currentY += lineHeight + 3;

   CreatePanelLabel("Sep1", "--------------------------------", x + padding, currentY, PanelBorderColor, PanelFontSize, false);
   currentY += lineHeight;

   // HTF Section
   CreatePanelLabel("HTFTitle", "HTF ANALYSIS (" + GetTimeframeString() + ")", x + padding, currentY, clrWhite, PanelFontSize, true);
   currentY += lineHeight;

   // Trend with score
   string trendText = "UNKNOWN";
   color trendColor = NeutralColor;
   switch(CurrentTrend)
   {
      case TREND_BULLISH: trendText = "BULLISH (" + IntegerToString(BullishScore) + ")"; trendColor = BuySignalColor; break;
      case TREND_BEARISH: trendText = "BEARISH (" + IntegerToString(BearishScore) + ")"; trendColor = SellSignalColor; break;
      case TREND_RANGING: trendText = "RANGING"; trendColor = clrYellow; break;
   }
   CreatePanelLabel("TrendL", "Trend:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
   CreatePanelLabel("TrendV", trendText, x + 90, currentY, trendColor, PanelFontSize, true);
   currentY += lineHeight;

   // HTF Signal
   string htfSigText = "";
   color htfSigColor = NeutralColor;
   switch(CurrentSignal.type)
   {
      case SIG_BUY_STRONG: htfSigText = "STRONG BUY"; htfSigColor = BuySignalColor; break;
      case SIG_BUY_MODERATE: htfSigText = "BUY"; htfSigColor = BuySignalColor; break;
      case SIG_BUY_WEAK: htfSigText = "Weak Buy"; htfSigColor = clrDarkGreen; break;
      case SIG_SELL_STRONG: htfSigText = "STRONG SELL"; htfSigColor = SellSignalColor; break;
      case SIG_SELL_MODERATE: htfSigText = "SELL"; htfSigColor = SellSignalColor; break;
      case SIG_SELL_WEAK: htfSigText = "Weak Sell"; htfSigColor = clrDarkRed; break;
      case SIG_WAIT: htfSigText = "WAIT"; htfSigColor = clrYellow; break;
      default: htfSigText = "NONE"; break;
   }
   CreatePanelLabel("HTFSigL", "Signal:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
   CreatePanelLabel("HTFSigV", htfSigText, x + 90, currentY, htfSigColor, PanelFontSize, true);
   currentY += lineHeight;

   CreatePanelLabel("HTFDesc", CurrentSignal.description, x + padding, currentY, clrSilver, PanelFontSize - 1, false);
   currentY += lineHeight;

   // Confluence details
   if(CurrentSignal.confluenceDetails != "")
   {
      CreatePanelLabel("ConfDet", "Conf: " + CurrentSignal.confluenceDetails, x + padding, currentY, clrCyan, PanelFontSize - 1, false);
      currentY += lineHeight;
   }

   currentY += 3;
   CreatePanelLabel("Sep2", "--------------------------------", x + padding, currentY, PanelBorderColor, PanelFontSize, false);
   currentY += lineHeight;

   // LTF Entry Section
   CreatePanelLabel("LTFTitle", "ENTRY SIGNAL (" + EntryTFString + ")", x + padding, currentY, clrCyan, PanelFontSize + 1, true);
   currentY += lineHeight;

   // MTF Entry Type
   string mtfText = "";
   color mtfColor = NeutralColor;
   switch(MTFEntry.type)
   {
      case MTF_BUY_NOW: mtfText = ">>> BUY NOW <<<"; mtfColor = BuySignalColor; break;
      case MTF_BUY_PENDING: mtfText = "BUY LIMIT"; mtfColor = clrDodgerBlue; break;
      case MTF_SELL_NOW: mtfText = ">>> SELL NOW <<<"; mtfColor = SellSignalColor; break;
      case MTF_SELL_PENDING: mtfText = "SELL LIMIT"; mtfColor = clrOrange; break;
      case MTF_WAIT: mtfText = "WAIT"; mtfColor = clrYellow; break;
      default: mtfText = "NO ENTRY"; break;
   }
   CreatePanelLabel("MTFSig", mtfText, x + padding, currentY, mtfColor, PanelFontSize + 1, true);
   currentY += lineHeight;

   CreatePanelLabel("MTFDesc", MTFEntry.description, x + padding, currentY, PanelTextColor, PanelFontSize - 1, false);
   currentY += lineHeight;

   // Alignment indicator
   string alignText = MTFEntry.htfLtfAligned ? "ALIGNED [" + IntegerToString(MTFEntry.alignmentScore) + "]" : "Not Aligned";
   color alignColor = MTFEntry.htfLtfAligned ? BuySignalColor : clrYellow;
   CreatePanelLabel("AlignL", "HTF-LTF:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
   CreatePanelLabel("AlignV", alignText, x + 90, currentY, alignColor, PanelFontSize, false);
   currentY += lineHeight;

   CreatePanelLabel("MTFCond", MTFEntry.condition, x + padding, currentY, mtfColor, PanelFontSize, true);
   currentY += lineHeight + 3;

   // Entry details if active
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   if(MTFEntry.type != MTF_NONE && MTFEntry.type != MTF_WAIT)
   {
      if(MTFEntry.type == MTF_BUY_PENDING || MTFEntry.type == MTF_SELL_PENDING)
      {
         CreatePanelLabel("PendL", "Pending:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
         CreatePanelLabel("PendV", DoubleToString(MTFEntry.pendingLevel, digits), x + 90, currentY, mtfColor, PanelFontSize, false);
         currentY += lineHeight;
      }
      else
      {
         CreatePanelLabel("EntryL", "Entry:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
         CreatePanelLabel("EntryV", DoubleToString(MTFEntry.entryPrice, digits), x + 90, currentY, clrWhite, PanelFontSize, false);
         currentY += lineHeight;
      }

      CreatePanelLabel("SLL", "Stop Loss:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
      CreatePanelLabel("SLV", DoubleToString(MTFEntry.stopLoss, digits), x + 90, currentY, SellSignalColor, PanelFontSize, false);
      currentY += lineHeight;

      CreatePanelLabel("TPL", "Take Profit:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
      CreatePanelLabel("TPV", DoubleToString(MTFEntry.takeProfit, digits), x + 90, currentY, BuySignalColor, PanelFontSize, false);
      currentY += lineHeight;

      // Risk/Reward
      double entryForRR = MTFEntry.entryPrice;
      double riskPips = MathAbs(entryForRR - MTFEntry.stopLoss);
      double rewardPips = MathAbs(MTFEntry.takeProfit - entryForRR);
      double rr = (riskPips > 0) ? rewardPips / riskPips : 0;
      CreatePanelLabel("RRL", "Risk:Reward:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
      CreatePanelLabel("RRV", "1:" + DoubleToString(rr, 1), x + 90, currentY, (rr >= 2) ? BuySignalColor : (rr >= 1) ? clrYellow : SellSignalColor, PanelFontSize, false);
      currentY += lineHeight + 3;
   }
   else
   {
      currentY += lineHeight * 4 + 3;
   }

   CreatePanelLabel("Sep3", "--------------------------------", x + padding, currentY, PanelBorderColor, PanelFontSize, false);
   currentY += lineHeight;

   // LTF Structure Info
   CreatePanelLabel("LTFStruct", "LTF STRUCTURE", x + padding, currentY, clrWhite, PanelFontSize, true);
   currentY += lineHeight;

   string ltfHighText = GetSwingLabelText(MTFEntry.lastLTFHighLabel);
   color ltfHighColor = (MTFEntry.lastLTFHighLabel == LABEL_HH) ? HH_Color :
                        (MTFEntry.lastLTFHighLabel == LABEL_LH) ? LH_Color : NeutralColor;
   CreatePanelLabel("LTFHighL", "Last High:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
   CreatePanelLabel("LTFHighV", ltfHighText, x + 90, currentY, ltfHighColor, PanelFontSize, false);
   currentY += lineHeight;

   string ltfLowText = GetSwingLabelText(MTFEntry.lastLTFLowLabel);
   color ltfLowColor = (MTFEntry.lastLTFLowLabel == LABEL_HL) ? HL_Color :
                       (MTFEntry.lastLTFLowLabel == LABEL_LL) ? LL_Color : NeutralColor;
   CreatePanelLabel("LTFLowL", "Last Low:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
   CreatePanelLabel("LTFLowV", ltfLowText, x + 90, currentY, ltfLowColor, PanelFontSize, false);
   currentY += lineHeight;

   color rsiColor = (MTFEntry.ltfRSI > 70) ? SellSignalColor : (MTFEntry.ltfRSI < 30) ? BuySignalColor : PanelTextColor;
   CreatePanelLabel("LTFRSIL", "LTF RSI:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
   CreatePanelLabel("LTFRSIV", DoubleToString(MTFEntry.ltfRSI, 1), x + 90, currentY, rsiColor, PanelFontSize, false);
   currentY += lineHeight + 3;

   CreatePanelLabel("Sep4", "--------------------------------", x + padding, currentY, PanelBorderColor, PanelFontSize, false);
   currentY += lineHeight;

   // Key Levels
   CreatePanelLabel("KeyLvl", "KEY LEVELS", x + padding, currentY, clrWhite, PanelFontSize, true);
   currentY += lineHeight;

   CreatePanelLabel("ResL", "HTF Resist:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
   CreatePanelLabel("ResV", DoubleToString(KeyResistance, digits), x + 90, currentY, SellSignalColor, PanelFontSize, false);
   currentY += lineHeight;

   CreatePanelLabel("SupL", "HTF Support:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
   CreatePanelLabel("SupV", DoubleToString(KeySupport, digits), x + 90, currentY, BuySignalColor, PanelFontSize, false);
   currentY += lineHeight;

   if(MTFEntry.ltfResistance > 0)
   {
      CreatePanelLabel("LTFResL", "LTF Resist:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
      CreatePanelLabel("LTFResV", DoubleToString(MTFEntry.ltfResistance, digits), x + 90, currentY, clrOrange, PanelFontSize, false);
      currentY += lineHeight;
   }

   if(MTFEntry.ltfSupport > 0)
   {
      CreatePanelLabel("LTFSupL", "LTF Support:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
      CreatePanelLabel("LTFSupV", DoubleToString(MTFEntry.ltfSupport, digits), x + 90, currentY, clrDodgerBlue, PanelFontSize, false);
      currentY += lineHeight;
   }

   // Zone counts
   if(ShowConfluenceZones && (SupportZoneCount > 0 || ResistanceZoneCount > 0))
   {
      CreatePanelLabel("ZonesL", "Zones:", x + padding, currentY, PanelTextColor, PanelFontSize, false);
      CreatePanelLabel("ZonesV", "S:" + IntegerToString(SupportZoneCount) + " R:" + IntegerToString(ResistanceZoneCount), x + 90, currentY, clrSilver, PanelFontSize, false);
   }
}

//+------------------------------------------------------------------+
//| Get swing label text                                              |
//+------------------------------------------------------------------+
string GetSwingLabelText(SWING_LABEL label)
{
   switch(label)
   {
      case LABEL_HH: return "HH";
      case LABEL_HL: return "HL";
      case LABEL_LH: return "LH";
      case LABEL_LL: return "LL";
      case LABEL_EH: return "EH";
      case LABEL_EL: return "EL";
      default: return "N/A";
   }
}

//+------------------------------------------------------------------+
//| Create panel label helper                                         |
//+------------------------------------------------------------------+
void CreatePanelLabel(string name, string text, int xPos, int yPos, color clr, int fontSize, bool bold)
{
   string objName = IndicatorPrefix + "Panel_" + name;

   if(ObjectFind(objName) < 0) {
      ObjectCreate(objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, xPos);
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, yPos);
      ObjectSetString(0, objName, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fontSize);
   }

   // Update text and color if needed
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| ChartEvent function                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE) ChartRedraw();
}
//+------------------------------------------------------------------+
