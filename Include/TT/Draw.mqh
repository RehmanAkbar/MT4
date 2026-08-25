//+------------------------------------------------------------------+
//|                                                          Draw.mqh |
//|      TT_LiquidityScalper - every chart object lives in this file   |
//|                                                                   |
//|  Indexing: SERIES (index 0 = forming bar, 1 = last closed bar).    |
//|  See the convention block at the top of Structure.mqh.             |
//|                                                                   |
//|  Object naming: EVERY object created here starts with TTLS_ so a  |
//|  single ObjectsDeleteAll(0, TTLS_PREFIX) in OnDeinit leaves the    |
//|  chart exactly as it was found. Names are derived from immutable   |
//|  facts (bar time, zone id) so a redraw reproduces the identical    |
//|  object set rather than accumulating duplicates.                   |
//|                                                                   |
//|  Nothing in this file makes a trading decision - it renders state  |
//|  that the engines already committed to.                            |
//+------------------------------------------------------------------+
#ifndef __TT_DRAW_MQH__
#define __TT_DRAW_MQH__

#include <TT/Structure.mqh>
#include <TT/Liquidity.mqh>
#include <TT/Zones.mqh>

//--- display scaling only (never used for logic)
#define TTLS_LIQ_SEG_BARS        6     // width of a liquidity segment, chart bars
#define TTLS_SIGNAL_BOX_BARS     14    // width of the SL/TP boxes, chart bars
#define TTLS_PANEL_ROW_H         15
#define TTLS_PANEL_MARGIN        10
#define TTLS_PANEL_WIDTH         248
#define TTLS_PANEL_ROWS          11

//+------------------------------------------------------------------+
//| Everything the renderer needs to know about colours and toggles.  |
//+------------------------------------------------------------------+
struct TTDrawCfg
  {
   color             clrBull;
   color             clrBear;
   color             clrZoneBull;
   color             clrZoneBear;
   color             clrInvalid;
   color             clrLiquidity;
   color             clrStrongWeak;
   color             clrStructure;
   color             clrText;
   int               fontSize;
   int               extendZonesBars;
   bool              keepSwept;
   bool              showMS;
   bool              showBOS;
   bool              showStrongWeak;
   bool              showLiquidity;
   bool              showPanel;
   ENUM_BASE_CORNER  corner;
  };

//+------------------------------------------------------------------+
//| A committed signal. Written once, never modified except for its   |
//| outcome, which is resolved by later bars.                         |
//+------------------------------------------------------------------+
struct TTSignal
  {
   datetime          barTime;    // open time of the bar that fired it
   datetime          closeTime;  // when that bar closed = when it became actionable
   ENUM_TIMEFRAMES   tf;         // timeframe the firing bar belongs to
   bool              bullish;
   bool              aggressive;
   double            entry;
   double            sl;
   double            tp;
   double            tp2;        // secondary target at the HTF weak level (0 = none)
   double            rr;
   int               quality;
   double            lots;
   int               outcome;    // 0 open, 1 target hit, 2 stop hit, 3 missed
  };

//+------------------------------------------------------------------+
//| Panel contents.                                                   |
//+------------------------------------------------------------------+
struct TTPanelInfo
  {
   string            symbol;
   string            biasTfLabel;
   string            setupTfLabel;
   int               biasTrend;
   int               setupTrend;
   string            bullState;
   string            bearState;
   int               zonesBull;
   int               zonesBear;
   int               liquidityUnswept;
   int               signalsToday;
   string            lastResult;
   int               lastQuality;
   double            lastLots;
   double            spreadPoints;
   bool              dailyLossBreached;
   string            note;
  };

//+------------------------------------------------------------------+
//| Timeframe label in the markup's own style: 1H, 15M, 4H, 1D.       |
//+------------------------------------------------------------------+
string TTTfLabel(const ENUM_TIMEFRAMES tf)
  {
   int m = PeriodSeconds(tf) / 60;
   if(m <= 0)
      return("?");
   if(m < 60)
      return(IntegerToString(m) + "M");
   if(m < 1440)
      return(IntegerToString(m / 60) + "H");
   if(m < 10080)
      return(IntegerToString(m / 1440) + "D");
   if(m < 43200)
      return(IntegerToString(m / 10080) + "W");
   return(IntegerToString(m / 43200) + "MN");
  }
//+------------------------------------------------------------------+
//| MT5 rectangles have no alpha channel, so semi-transparency is     |
//| emulated by mixing the fill colour into the chart background.     |
//| alpha 0 = invisible, 1 = solid.                                   |
//+------------------------------------------------------------------+
color TTBlend(const color fg, const double alpha)
  {
   uint f  = (uint)fg;
   uint bg = (uint)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   double a = alpha;
   if(a < 0.0) a = 0.0;
   if(a > 1.0) a = 1.0;

   uint c0 = (uint)((f        & 0xFF) * a + (bg        & 0xFF) * (1.0 - a));
   uint c1 = (uint)(((f >> 8) & 0xFF) * a + ((bg >> 8) & 0xFF) * (1.0 - a));
   uint c2 = (uint)(((f >> 16)& 0xFF) * a + ((bg >> 16)& 0xFF) * (1.0 - a));
   return((color)(c0 | (c1 << 8) | (c2 << 16)));
  }
//+------------------------------------------------------------------+
string TTObjName(const string kind, const string id)
  {
   return(TTLS_PREFIX + kind + "_" + id);
  }
//+------------------------------------------------------------------+
void TTDeleteAll(void)
  {
   ObjectsDeleteAll(0, TTLS_PREFIX);
  }
//+------------------------------------------------------------------+
//| Primitive builders. Each one recreates the object if the existing |
//| one has the wrong type, then sets every property explicitly, so a |
//| redraw can never leave a stale attribute behind.                  |
//+------------------------------------------------------------------+
bool TTEnsure(const string name, const ENUM_OBJECT type, const int points,
              const datetime t1, const double p1, const datetime t2, const double p2)
  {
   if(ObjectFind(0, name) >= 0 && (int)ObjectGetInteger(0, name, OBJPROP_TYPE) != (int)type)
      ObjectDelete(0, name);
   if(ObjectFind(0, name) < 0)
     {
      bool ok = (points >= 2) ? ObjectCreate(0, name, type, 0, t1, p1, t2, p2)
                              : ObjectCreate(0, name, type, 0, t1, p1);
      if(!ok)
         return(false);
     }
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   if(points >= 2)
     {
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   return(true);
  }
//+------------------------------------------------------------------+
void TTRect(const string name, const datetime t1, const double p1,
            const datetime t2, const double p2, const color clr, const bool fill)
  {
   if(!TTEnsure(name, OBJ_RECTANGLE, 2, t1, p1, t2, p2))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL,  fill);
   ObjectSetInteger(0, name, OBJPROP_BACK,  true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }
//+------------------------------------------------------------------+
void TTSegment(const string name, const datetime t1, const double p1,
               const datetime t2, const double p2, const color clr,
               const ENUM_LINE_STYLE style, const int width, const bool rayRight)
  {
   if(!TTEnsure(name, OBJ_TREND, 2, t1, p1, t2, p2))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,     style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     width);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
   ObjectSetInteger(0, name, OBJPROP_BACK,      true);
  }
//+------------------------------------------------------------------+
void TTText(const string name, const datetime t, const double p, const string txt,
            const color clr, const int fontSize, const ENUM_ANCHOR_POINT anchor)
  {
   if(!TTEnsure(name, OBJ_TEXT, 1, t, p, 0, 0.0))
      return;
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,    clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,   anchor);
   ObjectSetInteger(0, name, OBJPROP_BACK,     false);
  }
//+------------------------------------------------------------------+
void TTArrow(const string name, const datetime t, const double p, const int code,
             const color clr, const int width, const ENUM_ARROW_ANCHOR anchor)
  {
   if(!TTEnsure(name, OBJ_ARROW, 1, t, p, 0, 0.0))
      return;
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     width);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    anchor);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
  }
//+------------------------------------------------------------------+
//| MS / BOS markup: a thin line from the swing that was broken to    |
//| the bar that broke it, with the label centred above it.           |
//+------------------------------------------------------------------+
void TTDrawStructEvent(const TTStructEvent &ev, const ENUM_TIMEFRAMES tf,
                       const TTDrawCfg &cfg)
  {
   if(ev.isBOS ? !cfg.showBOS : !cfg.showMS)
      return;
   string id  = TTTfLabel(tf) + "_" + IntegerToString((long)ev.breakTime);
   string ln  = TTObjName("E", id);
   string tx  = TTObjName("ET", id);
   TTSegment(ln, ev.swingTime, ev.price, ev.breakTime, ev.price,
             cfg.clrStructure, STYLE_SOLID, 1, false);

   datetime mid = (datetime)((long)ev.swingTime + ((long)ev.breakTime - (long)ev.swingTime) / 2);
   string   txt = (ev.isBOS ? "BOS" : "MS");
   TTText(tx, mid, ev.price, txt, cfg.clrStructure, cfg.fontSize,
          ev.bullish ? ANCHOR_LOWER : ANCHOR_UPPER);
  }
//+------------------------------------------------------------------+
//| Zone box. Live zones extend to the right edge of the current data |
//| so they stay visible until price interacts with them; a zone that |
//| failed is frozen at its invalidation bar and greyed out.          |
//+------------------------------------------------------------------+
void TTDrawZone(const TTZone &z, const TTDrawCfg &cfg)
  {
   string id   = TTTfLabel(z.tf) + "_" + IntegerToString(z.id);
   string name = TTObjName("Z", id);

   datetime right = (datetime)((long)z.createdTime + (long)PeriodSeconds(z.tf) * cfg.extendZonesBars);
   if(z.state == TTZS_INVALID && z.invalidTime > 0)
      right = z.invalidTime;
   else
     {
      datetime now = TimeCurrent();
      if(right < now)
         right = now;
     }

   color base = z.bullish ? cfg.clrZoneBull : cfg.clrZoneBear;
   double alpha = 0.35;
   if(z.state == TTZS_INVALID)
     {
      base  = cfg.clrInvalid;
      alpha = 0.18;
     }
   else
      if(z.state == TTZS_MITIGATED)
         alpha = 0.22;                            // already used once

   TTRect(name, z.createdTime, z.top, right, z.bottom, TTBlend(base, alpha), true);

   //--- a one-letter tag keeps four overlapping zone types readable
   string tag = "DZ";
   if(z.type == TTZ_ORDER_BLOCK) tag = "OB";
   if(z.type == TTZ_FVG)         tag = "FVG";
   if(z.type == TTZ_BREAKER)     tag = "BRK";
   if(!z.bullish && z.type == TTZ_DEMAND_SUPPLY) tag = "SZ";
   TTText(TTObjName("ZT", id), z.createdTime, z.bullish ? z.bottom : z.top,
          tag + " " + TTTfLabel(z.tf), TTBlend(base, 0.9), cfg.fontSize - 1,
          z.bullish ? ANCHOR_UPPER : ANCHOR_LOWER);
  }
//+------------------------------------------------------------------+
//| Liquidity pool: a short segment with a $ at its right end. Equal  |
//| highs/lows carry their hit count, because those are the pools     |
//| worth waiting for.                                                |
//+------------------------------------------------------------------+
void TTDrawLiquidity(const TTLiqPool &p, const ENUM_TIMEFRAMES tf, const TTDrawCfg &cfg)
  {
   if(!cfg.showLiquidity)
      return;
   if(!p.active && !cfg.keepSwept)
      return;

   string id   = IntegerToString(p.id);
   string name = TTObjName("L", id);
   //--- the segment always reaches the present so a live pool is easy to see
   datetime t2 = p.active ? TimeCurrent()
                          : (datetime)((long)p.sweepTime + (long)PeriodSeconds(tf) * 2);
   if(t2 <= p.firstTime)
      t2 = (datetime)((long)p.firstTime + (long)PeriodSeconds(tf) * TTLS_LIQ_SEG_BARS);

   //--- a level price ran clean through was never raided, so it is drawn as
   //--- spent structure rather than as liquidity that paid out
   color clr = cfg.clrLiquidity;
   if(p.broken)
      clr = TTBlend(cfg.clrInvalid, 0.65);
   else
      if(!p.active)
         clr = TTBlend(cfg.clrLiquidity, 0.40);

   TTSegment(name, p.firstTime, p.price, t2, p.price, clr,
             p.active ? STYLE_SOLID : STYLE_DOT, 1, false);

   //--- the $ marks resting liquidity; a broken level no longer holds any
   if(!p.broken)
     {
      string txt = (p.count > 1) ? "$" + IntegerToString(p.count) : "$";
      TTText(TTObjName("LT", id), t2, p.price, txt, clr, cfg.fontSize, ANCHOR_LEFT);
     }
  }
//+------------------------------------------------------------------+
//| "1H Strong" / "1H Weak" rays in the muted red of the reference    |
//| markup. Strong = protected origin of the leg, Weak = the level    |
//| the market is most likely to reach for next.                      |
//+------------------------------------------------------------------+
void TTDrawStrongWeak(const ENUM_TIMEFRAMES tf, const bool hasStrong, const double strongPrice,
                      const datetime strongTime, const bool strongIsLow,
                      const bool hasWeak, const double weakPrice, const datetime weakTime,
                      const TTDrawCfg &cfg)
  {
   if(!cfg.showStrongWeak)
      return;
   string lbl = TTTfLabel(tf);
   datetime right = (datetime)((long)TimeCurrent() + (long)PeriodSeconds(tf) * 10);

   if(hasStrong)
     {
      string id = lbl + "_STRONG";
      TTSegment(TTObjName("SW", id), strongTime, strongPrice, right, strongPrice,
                cfg.clrStrongWeak, STYLE_SOLID, 1, true);
      TTText(TTObjName("SWT", id), right, strongPrice,
             lbl + " Strong " + (strongIsLow ? "Low" : "High"),
             cfg.clrStrongWeak, cfg.fontSize, ANCHOR_RIGHT);
     }
   if(hasWeak)
     {
      string id = lbl + "_WEAK";
      TTSegment(TTObjName("SW", id), weakTime, weakPrice, right, weakPrice,
                cfg.clrStrongWeak, STYLE_DASH, 1, true);
      TTText(TTObjName("SWT", id), right, weakPrice,
             lbl + " Weak " + (strongIsLow ? "High" : "Low"),
             cfg.clrStrongWeak, cfg.fontSize, ANCHOR_RIGHT);
     }
  }
//+------------------------------------------------------------------+
//| Fired signal: arrow, red risk box, green reward box, and a        |
//| one-line summary of the numbers a trader actually needs.          |
//|                                                                   |
//| `anchor` is the CHART bar the signal is pinned to. It is passed in |
//| rather than derived here so the drawn markup and the indicator     |
//| buffers always land on the same bar, whatever timeframe the chart  |
//| happens to be showing.                                             |
//+------------------------------------------------------------------+
void TTDrawSignal(const TTSignal &s, const datetime anchor, const TTDrawCfg &cfg,
                  const int digits)
  {
   string id = IntegerToString((long)s.closeTime) + (s.bullish ? "B" : "S");
   color  dirClr = s.bullish ? cfg.clrBull : cfg.clrBear;

   TTArrow(TTObjName("SIG", id), anchor, s.entry, s.bullish ? 233 : 234,
           dirClr, 2, s.bullish ? ANCHOR_TOP : ANCHOR_BOTTOM);

   //--- box width is pure display scaling, hence PERIOD_CURRENT here
   datetime right = (datetime)((long)anchor +
                               (long)PeriodSeconds(PERIOD_CURRENT) * TTLS_SIGNAL_BOX_BARS);
   TTRect(TTObjName("SLB", id), anchor, s.entry, right, s.sl,
          TTBlend(clrCrimson, 0.28), true);
   TTRect(TTObjName("TPB", id), anchor, s.entry, right, s.tp,
          TTBlend(clrSeaGreen, 0.28), true);
   if(s.tp2 > 0.0)
      TTSegment(TTObjName("TP2", id), anchor, s.tp2, right, s.tp2,
                clrSeaGreen, STYLE_DASH, 1, false);

   string txt = StringFormat("%s  RR %.2f  Q%d  %.2f lots",
                             s.aggressive ? "AGG" : "CON", s.rr, s.quality, s.lots);
   if(s.outcome == 1) txt += "  [TP]";
   if(s.outcome == 2) txt += "  [SL]";
   if(s.outcome == 3) txt += "  [MISSED]";
   TTText(TTObjName("SIGT", id), anchor, s.entry, txt, dirClr, cfg.fontSize,
          s.bullish ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);

   //--- the exact levels, printed where they are read
   TTText(TTObjName("SLT", id), right, s.sl,
          "SL " + DoubleToString(s.sl, digits), clrCrimson, cfg.fontSize - 1, ANCHOR_LEFT);
   TTText(TTObjName("TPT", id), right, s.tp,
          "TP " + DoubleToString(s.tp, digits), clrSeaGreen, cfg.fontSize - 1, ANCHOR_LEFT);
  }
//+------------------------------------------------------------------+
//| Panel helpers.                                                    |
//+------------------------------------------------------------------+
void TTPanelLabel(const string name, const int row, const int rows, const string txt,
                  const color clr, const TTDrawCfg &cfg)
  {
   bool lower = (cfg.corner == CORNER_LEFT_LOWER || cfg.corner == CORNER_RIGHT_LOWER);
   bool right = (cfg.corner == CORNER_RIGHT_UPPER || cfg.corner == CORNER_RIGHT_LOWER);
   int  slot  = lower ? (rows - 1 - row) : row;

   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return;
   ObjectSetInteger(0, name, OBJPROP_CORNER,    cfg.corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, TTLS_PANEL_MARGIN + 8);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, TTLS_PANEL_MARGIN + 6 + slot * TTLS_PANEL_ROW_H);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  cfg.fontSize);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
  }
//+------------------------------------------------------------------+
string TTTrendWord(const int t)
  {
   if(t > 0) return("BULL");
   if(t < 0) return("BEAR");
   return("NEUTRAL");
  }
//+------------------------------------------------------------------+
//| Info panel. Greyed out entirely once the daily loss guard trips,  |
//| which is the visual cue that alerts have been muted too.          |
//+------------------------------------------------------------------+
void TTDrawPanel(const TTPanelInfo &info, const TTDrawCfg &cfg)
  {
   if(!cfg.showPanel)
      return;

   string bg = TTObjName("PANEL", "BG");
   if(ObjectFind(0, bg) < 0)
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER,     cfg.corner);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,  TTLS_PANEL_MARGIN);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,  TTLS_PANEL_MARGIN);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,      TTLS_PANEL_WIDTH);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,      TTLS_PANEL_ROWS * TTLS_PANEL_ROW_H + 12);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,    TTBlend(clrBlack, 0.55));
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR,      TTBlend(cfg.clrText, 0.35));
   ObjectSetInteger(0, bg, OBJPROP_BACK,       false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN,     true);

   color normal = info.dailyLossBreached ? cfg.clrInvalid : cfg.clrText;
   color bull   = info.dailyLossBreached ? cfg.clrInvalid : cfg.clrBull;
   color bear   = info.dailyLossBreached ? cfg.clrInvalid : cfg.clrBear;
   int   r      = 0;

   TTPanelLabel(TTObjName("P", "0"), r++, TTLS_PANEL_ROWS,
                "TT LiquidityScalper  " + info.symbol, normal, cfg);
   TTPanelLabel(TTObjName("P", "1"), r++, TTLS_PANEL_ROWS,
                info.biasTfLabel + " bias   : " + TTTrendWord(info.biasTrend),
                info.biasTrend > 0 ? bull : (info.biasTrend < 0 ? bear : normal), cfg);
   TTPanelLabel(TTObjName("P", "2"), r++, TTLS_PANEL_ROWS,
                info.setupTfLabel + " setup  : " + TTTrendWord(info.setupTrend),
                info.setupTrend > 0 ? bull : (info.setupTrend < 0 ? bear : normal), cfg);
   TTPanelLabel(TTObjName("P", "3"), r++, TTLS_PANEL_ROWS,
                "Long state : " + info.bullState, bull, cfg);
   TTPanelLabel(TTObjName("P", "4"), r++, TTLS_PANEL_ROWS,
                "Short state: " + info.bearState, bear, cfg);
   TTPanelLabel(TTObjName("P", "5"), r++, TTLS_PANEL_ROWS,
                StringFormat("Zones      : %d dem / %d sup", info.zonesBull, info.zonesBear),
                normal, cfg);
   TTPanelLabel(TTObjName("P", "6"), r++, TTLS_PANEL_ROWS,
                StringFormat("Liquidity  : %d unswept", info.liquidityUnswept), normal, cfg);
   TTPanelLabel(TTObjName("P", "7"), r++, TTLS_PANEL_ROWS,
                StringFormat("Signals    : %d today", info.signalsToday), normal, cfg);
   TTPanelLabel(TTObjName("P", "8"), r++, TTLS_PANEL_ROWS,
                StringFormat("Last       : %s  Q%d  %.2f lots",
                             info.lastResult, info.lastQuality, info.lastLots), normal, cfg);
   TTPanelLabel(TTObjName("P", "9"), r++, TTLS_PANEL_ROWS,
                StringFormat("Spread     : %.0f pts", info.spreadPoints), normal, cfg);
   TTPanelLabel(TTObjName("P", "10"), r++, TTLS_PANEL_ROWS,
                info.note, info.dailyLossBreached ? cfg.clrInvalid : cfg.clrStrongWeak, cfg);
  }

#endif // __TT_DRAW_MQH__
//+------------------------------------------------------------------+
