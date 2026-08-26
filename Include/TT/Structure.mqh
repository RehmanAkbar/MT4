//+------------------------------------------------------------------+
//|                                                     Structure.mqh |
//|                       TT_LiquidityScalper - structural foundation |
//|                                                                   |
//|  Contents:                                                        |
//|    * CTfData          - cached OHLC + ATR window for one timeframe |
//|    * CValueTrack      - time-stamped state history (no look-ahead) |
//|    * CSwingRing       - ring buffer of confirmed swing points      |
//|    * CEventRing       - ring buffer of MS / BOS events             |
//|    * CStructureEngine - swing detection, MS/BOS, strong/weak level |
//|                                                                   |
//|  ================= INDEXING CONVENTION (whole package) ==========  |
//|  Every price/time array in this package is SERIES INDEXED          |
//|  (ArraySetAsSeries == true):                                       |
//|        index 0  = the currently forming bar                        |
//|        index 1  = the last CLOSED bar                              |
//|        index n  = n bars into the past                             |
//|  Consequences, applied without exception:                          |
//|    - Walking history FORWARD in time counts DOWN:                  |
//|          for(int b = oldest; b >= 1; b--)                          |
//|    - "left of a bar"  (older) == a HIGHER index                    |
//|    - "right of a bar" (newer) == a LOWER index                     |
//|    - No decision is ever taken on index 0. Index 0 is the live bar |
//|      and reading it would repaint.                                 |
//|  ================================================================  |
//|                                                                   |
//|  Progress through history is stored as a BAR OPEN TIME, never as   |
//|  an index. Series indices only shift when new bars arrive on the   |
//|  right, and a stored time is re-resolved with iBarShift(), so      |
//|  deeper history downloads cannot corrupt the forward-only state.   |
//+------------------------------------------------------------------+
#ifndef __TT_STRUCTURE_MQH__
#define __TT_STRUCTURE_MQH__

//--- object prefix shared by every drawn element (see Draw.mqh)
#define TTLS_PREFIX              "TTLS_"

//--- Container capacities. Ring buffers drop their oldest entry when full.
//--- These must comfortably span MaxHistoryBars' worth of events, because the
//--- EntryTF rings are queried CROSS-TIMEFRAME by the slower SetupTF loop: if
//--- an event the live run could see had already been evicted by the time a
//--- rebuild asked for it, the rebuild would produce a different signal set.
//--- Structure breaks and swings are far rarer than bars, so these caps cover
//--- a few thousand bars per timeframe with room to spare.
//--- Swings: every consumer (NewestUnbroken, ExtremeInWindow, FindByTime) asks
//--- about the CURRENT leg, so evicting ancient swings costs nothing.
#define TTLS_MAX_SWINGS          512
//--- Events: FirstShiftAfter() is a genuinely HISTORICAL query - it scans the
//--- whole ring for the oldest shift in a window that can sit thousands of bars
//--- back. The ring therefore has to span the entire rebuilt history or an
//--- evicted event silently changes the conservative signal set on reload, the
//--- same defect the per-timeframe history depth used to cause. Sized for the
//--- EntryTF, which now covers the SetupTF's full span (see TTHistoryBarsFor)
//--- and so holds the most events of the three engines.
#define TTLS_MAX_EVENTS          4096
//--- The per-direction STATE tracks transition several times per setup, so this
//--- cap is hit far sooner than the trend/level tracks. Once a track evicts its
//--- oldest half ValueAt() clamps to the oldest survivor, and the SetupState
//--- buffer silently reads IDLE on older bars - which matters because an EA
//--- consumes that buffer. Sized for a full MaxHistoryBars rebuild instead.
#define TTLS_MAX_TRACK           4096

//--- how far back from a structure break we hunt for the origin candle
#define TTLS_ZONE_LOOKBACK       30
//--- window used to decide whether a zone sits at an untested extreme
#define TTLS_EXTREME_LOOKBACK    50
//--- floor for any ATR-derived distance so a dead ATR cannot produce 0
#define TTLS_MIN_TOL_POINTS      2

//+------------------------------------------------------------------+
//| Trend direction. Numeric values double as the BiasState buffer    |
//| contract (+1 bull / -1 bear / 0 neutral), so do not renumber.     |
//+------------------------------------------------------------------+
enum TT_TREND
  {
   TT_TREND_BEAR    = -1,
   TT_TREND_NEUTRAL =  0,
   TT_TREND_BULL    =  1
  };

//+------------------------------------------------------------------+
//| A confirmed swing point. Confirmed means SwingRightBars bars have |
//| CLOSED to its right - it can never be revoked.                    |
//+------------------------------------------------------------------+
struct TTSwing
  {
   datetime          time;      // open time of the pivot bar
   double            price;     // pivot high or pivot low
   bool              isHigh;    // true = swing high, false = swing low
   bool              swept;     // liquidity above/below it has been taken
   bool              broken;    // consumed by a structure break (MS/BOS)
  };

//+------------------------------------------------------------------+
//| One market-structure event (CHoCH or continuation break).         |
//+------------------------------------------------------------------+
struct TTStructEvent
  {
   datetime          breakTime;  // open time of the bar that broke the level
   datetime          breakClose; // when that bar CLOSED = when the break became known.
                                 // Cross-timeframe queries must bound on this, never on
                                 // breakTime, or a bar that is still forming on a faster
                                 // timeframe would leak into a slower timeframe's decision.
   datetime          swingTime;  // open time of the swing that was broken
   double            price;      // the broken level
   bool              isBOS;      // true = BOS (continuation), false = MS/CHoCH
   bool              bullish;    // direction of the break
  };

//+------------------------------------------------------------------+
//| Config block for the structure engine.                            |
//+------------------------------------------------------------------+
struct TTStructCfg
  {
   int               leftBars;      // bars required to the left of a pivot
   int               rightBars;     // bars required to the right (confirmation lag)
   bool              useWickBreaks; // true = break on high/low, false = on close
  };

//+------------------------------------------------------------------+
//| CValueTrack                                                       |
//| Stores a step function of time -> int. Points are pushed in       |
//| strictly increasing time order while history is walked forward,   |
//| so ValueAt(t) answers "what did we know at time t" with no        |
//| look-ahead. Used for the bias/state buffers, which must show the  |
//| historical value on historical bars.                              |
//+------------------------------------------------------------------+
struct TTTrackPoint
  {
   datetime          time;
   int               value;
  };

class CValueTrack
  {
private:
   TTTrackPoint      m_pts[];
   int               m_count;
public:
                     CValueTrack(void) { m_count = 0; ArrayResize(m_pts, TTLS_MAX_TRACK); }
   void              Reset(void) { m_count = 0; }
   int               Count(void) { return m_count; }
   //--- record a transition; repeated identical values are collapsed
   void              Push(const datetime t, const int v);
   //--- value in force at time t (0 when t predates every stored point)
   int               ValueAt(const datetime t);
  };

//+------------------------------------------------------------------+
void CValueTrack::Push(const datetime t, const int v)
  {
   if(m_count > 0 && m_pts[m_count - 1].value == v)
      return;                                   // no change, nothing to record
   if(m_count > 0 && m_pts[m_count - 1].time > t)
      return;                                   // guard: never accept a back-dated point
   if(m_count >= TTLS_MAX_TRACK)
     {
      //--- drop the oldest half in one move; ValueAt() then clamps to the
      //--- oldest surviving point, which is correct for a step function
      int keep = TTLS_MAX_TRACK / 2;
      for(int i = 0; i < keep; i++)
         m_pts[i] = m_pts[m_count - keep + i];
      m_count = keep;
     }
   m_pts[m_count].time  = t;
   m_pts[m_count].value = v;
   m_count++;
  }
//+------------------------------------------------------------------+
int CValueTrack::ValueAt(const datetime t)
  {
   if(m_count <= 0 || t < m_pts[0].time)
      return(0);
   int lo = 0, hi = m_count - 1;
   while(lo < hi)                               // binary search: last point <= t
     {
      int mid = (lo + hi + 1) / 2;
      if(m_pts[mid].time <= t)
         lo = mid;
      else
         hi = mid - 1;
     }
   return(m_pts[lo].value);
  }

//+------------------------------------------------------------------+
//| CLevelTrack                                                       |
//| The price equivalent of CValueTrack: a step function of time ->   |
//| price level. Needed because a target that reads "the current HTF  |
//| weak level" would give a historical signal TODAY's level after a  |
//| reload, which is exactly the repainting this indicator forbids.   |
//| Each point is stamped with the moment the level became KNOWN (the |
//| close of the bar that produced it), never the bar it sits on.     |
//+------------------------------------------------------------------+
struct TTLevelPoint
  {
   datetime          time;
   double            value;
  };

class CLevelTrack
  {
private:
   TTLevelPoint      m_pts[];
   int               m_count;
public:
                     CLevelTrack(void) { m_count = 0; ArrayResize(m_pts, TTLS_MAX_TRACK); }
   void              Reset(void) { m_count = 0; }
   void              Push(const datetime t, const double v);
   bool              ValueAt(const datetime t, double &v);
  };

//+------------------------------------------------------------------+
void CLevelTrack::Push(const datetime t, const double v)
  {
   if(m_count > 0 && m_pts[m_count - 1].value == v)
      return;
   if(m_count > 0 && m_pts[m_count - 1].time > t)
      return;                                   // never accept a back-dated point
   if(m_count >= TTLS_MAX_TRACK)
     {
      int keep = TTLS_MAX_TRACK / 2;
      for(int i = 0; i < keep; i++)
         m_pts[i] = m_pts[m_count - keep + i];
      m_count = keep;
     }
   m_pts[m_count].time  = t;
   m_pts[m_count].value = v;
   m_count++;
  }
//+------------------------------------------------------------------+
bool CLevelTrack::ValueAt(const datetime t, double &v)
  {
   if(m_count <= 0 || t < m_pts[0].time)
      return(false);
   int lo = 0, hi = m_count - 1;
   while(lo < hi)
     {
      int mid = (lo + hi + 1) / 2;
      if(m_pts[mid].time <= t)
         lo = mid;
      else
         hi = mid - 1;
     }
   v = m_pts[lo].value;
   return(true);
  }

//+------------------------------------------------------------------+
//| CSwingRing - newest-first access to the confirmed swing points.   |
//| Get(0) is the newest confirmed swing.                             |
//+------------------------------------------------------------------+
class CSwingRing
  {
private:
   TTSwing           m_buf[TTLS_MAX_SWINGS];
   int               m_head;                    // slot holding the newest entry
   int               m_count;
   int               Slot(const int i) { return((m_head - i + TTLS_MAX_SWINGS * 2) % TTLS_MAX_SWINGS); }
public:
                     CSwingRing(void) { Reset(); }
   void              Reset(void) { m_head = -1; m_count = 0; }
   int               Count(void) { return m_count; }
   void              Add(const TTSwing &s);
   bool              Get(const int i, TTSwing &out);
   void              MarkSwept(const int i);
   void              MarkBroken(const int i);
   //--- index of the newest unbroken swing on the requested side, -1 if none
   int               NewestUnbroken(const bool isHigh);
   //--- index of the swing that printed at bar-open time t, -1 if none
   int               FindByTime(const datetime t, const bool isHigh);
   //--- extreme confirmed swing of one side inside a time window (t1, t2]
   bool              ExtremeInWindow(const bool isHigh, const datetime t1, const datetime t2,
                                     double &price, datetime &time);
  };

//+------------------------------------------------------------------+
void CSwingRing::Add(const TTSwing &s)
  {
   m_head = (m_head + 1) % TTLS_MAX_SWINGS;
   m_buf[m_head] = s;
   if(m_count < TTLS_MAX_SWINGS)
      m_count++;
  }
//+------------------------------------------------------------------+
bool CSwingRing::Get(const int i, TTSwing &out)
  {
   if(i < 0 || i >= m_count)
      return(false);
   out = m_buf[Slot(i)];
   return(true);
  }
//+------------------------------------------------------------------+
void CSwingRing::MarkSwept(const int i)
  {
   if(i < 0 || i >= m_count)
      return;
   m_buf[Slot(i)].swept = true;
  }
//+------------------------------------------------------------------+
void CSwingRing::MarkBroken(const int i)
  {
   if(i >= 0 && i < m_count)
      m_buf[Slot(i)].broken = true;
  }
//+------------------------------------------------------------------+
int CSwingRing::NewestUnbroken(const bool isHigh)
  {
   for(int i = 0; i < m_count; i++)
     {
      int s = Slot(i);
      if(m_buf[s].isHigh == isHigh && !m_buf[s].broken)
         return(i);
     }
   return(-1);
  }
//+------------------------------------------------------------------+
int CSwingRing::FindByTime(const datetime t, const bool isHigh)
  {
   for(int i = 0; i < m_count; i++)
     {
      int s = Slot(i);
      if(m_buf[s].isHigh == isHigh && m_buf[s].time == t)
         return(i);
     }
   return(-1);
  }
//+------------------------------------------------------------------+
//| Lowest swing low (or highest swing high) strictly after t1 and    |
//| not later than t2. This is how the protected "strong" level is    |
//| located after a break: it is the origin of the breaking leg.      |
//+------------------------------------------------------------------+
bool CSwingRing::ExtremeInWindow(const bool isHigh, const datetime t1, const datetime t2,
                                 double &price, datetime &time)
  {
   bool found = false;
   for(int i = 0; i < m_count; i++)
     {
      int s = Slot(i);
      if(m_buf[s].isHigh != isHigh)
         continue;
      if(m_buf[s].time <= t1 || m_buf[s].time > t2)
         continue;
      if(!found || (isHigh ? m_buf[s].price > price : m_buf[s].price < price))
        {
         price = m_buf[s].price;
         time  = m_buf[s].time;
         found = true;
        }
     }
   return(found);
  }

//+------------------------------------------------------------------+
//| CEventRing - newest-first access to MS/BOS events.                |
//+------------------------------------------------------------------+
class CEventRing
  {
private:
   TTStructEvent     m_buf[TTLS_MAX_EVENTS];
   int               m_head;
   int               m_count;
   int               Slot(const int i) { return((m_head - i + TTLS_MAX_EVENTS * 2) % TTLS_MAX_EVENTS); }
public:
                     CEventRing(void) { Reset(); }
   void              Reset(void) { m_head = -1; m_count = 0; }
   int               Count(void) { return m_count; }
   void              Add(const TTStructEvent &e);
   bool              Get(const int i, TTStructEvent &out);
   //--- oldest event in (after, upto] matching direction. MS and BOS rank
   //--- equally - see the note on the definition for why refusing BOS would
   //--- disable conservative entries in a trending market.
   bool              FirstShiftAfter(const datetime after, const datetime upto,
                                     const bool bullish, TTStructEvent &out);
  };

//+------------------------------------------------------------------+
void CEventRing::Add(const TTStructEvent &e)
  {
   m_head = (m_head + 1) % TTLS_MAX_EVENTS;
   m_buf[m_head] = e;
   if(m_count < TTLS_MAX_EVENTS)
      m_count++;
  }
//+------------------------------------------------------------------+
bool CEventRing::Get(const int i, TTStructEvent &out)
  {
   if(i < 0 || i >= m_count)
      return(false);
   out = m_buf[Slot(i)];
   return(true);
  }
//+------------------------------------------------------------------+
//| Used by the conservative entry sub-sequence: after liquidity has  |
//| been swept we need the FIRST lower-timeframe shift in the trade   |
//| direction. Both MS and BOS qualify - if the LTF was already       |
//| trending our way the shift is labelled BOS, and refusing it would |
//| silently disable the whole conservative mode in trending markets. |
//+------------------------------------------------------------------+
bool CEventRing::FirstShiftAfter(const datetime after, const datetime upto,
                                 const bool bullish, TTStructEvent &out)
  {
   bool found = false;
   for(int i = 0; i < m_count; i++)                 // newest first, so keep scanning
     {                                             // for the OLDEST qualifying event
      int s = Slot(i);
      if(m_buf[s].bullish != bullish)
         continue;
      //--- bound on the CLOSE of the breaking bar: a break is not knowledge
      //--- until its bar has actually closed
      if(m_buf[s].breakClose <= after || m_buf[s].breakClose > upto)
         continue;
      out   = m_buf[s];
      found = true;
     }
   return(found);
  }

//+------------------------------------------------------------------+
//| CTfData                                                           |
//| One cached, series-indexed OHLC + ATR window per timeframe.       |
//| Contract: Load() returns false whenever the terminal cannot yet   |
//| serve the requested history. Callers must propagate that upward   |
//| so OnCalculate() can return 0 and be retried - never carry on     |
//| with partial multi-timeframe data.                                |
//+------------------------------------------------------------------+
class CTfData
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   MqlRates          m_rates[];
   int               m_count;
   int               m_atrHandle;
   double            m_atr[];
   int               m_atrCount;
public:
                     CTfData(void);
                    ~CTfData(void);
   bool              Init(const string sym, const ENUM_TIMEFRAMES tf, const int atrPeriod);
   void              Release(void);
   bool              Load(const int count);
   int               Count(void) { return m_count; }
   bool              Valid(const int i) { return(i >= 0 && i < m_count); }
   double            High(const int i)  { return(Valid(i) ? m_rates[i].high  : 0.0); }
   double            Low(const int i)   { return(Valid(i) ? m_rates[i].low   : 0.0); }
   double            Open(const int i)  { return(Valid(i) ? m_rates[i].open  : 0.0); }
   double            Close(const int i) { return(Valid(i) ? m_rates[i].close : 0.0); }
   datetime          Time(const int i)  { return(Valid(i) ? m_rates[i].time  : (datetime)0); }
   //--- close time of bar i, i.e. the instant its information became usable
   datetime          CloseTime(const int i) { return(Time(i) + (datetime)PeriodSeconds(m_tf)); }
   bool              IsUp(const int i)   { return(Close(i) > Open(i)); }
   bool              IsDown(const int i) { return(Close(i) < Open(i)); }
   //--- spread RECORDED on bar i, in points. Historical and therefore
   //--- deterministic - unlike the live ask/bid, which would make a
   //--- history rebuild disagree with the original run.
   int               Spread(const int i) { return(Valid(i) ? (int)m_rates[i].spread : 0); }
   double            ATR(const int i);
   ENUM_TIMEFRAMES   Tf(void) { return m_tf; }
   string            Sym(void) { return m_symbol; }
  };

//+------------------------------------------------------------------+
CTfData::CTfData(void)
  {
   m_symbol    = "";
   m_tf        = PERIOD_CURRENT;
   m_count     = 0;
   m_atrHandle = INVALID_HANDLE;
   m_atrCount  = 0;
  }
//+------------------------------------------------------------------+
CTfData::~CTfData(void)
  {
   Release();
  }
//+------------------------------------------------------------------+
void CTfData::Release(void)
  {
   if(m_atrHandle != INVALID_HANDLE)
     {
      IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
     }
   m_count    = 0;
   m_atrCount = 0;
  }
//+------------------------------------------------------------------+
bool CTfData::Init(const string sym, const ENUM_TIMEFRAMES tf, const int atrPeriod)
  {
   Release();
   m_symbol = sym;
   m_tf     = tf;
   ArraySetAsSeries(m_rates, true);
   ArraySetAsSeries(m_atr,   true);
   m_atrHandle = iATR(m_symbol, m_tf, atrPeriod);
   return(m_atrHandle != INVALID_HANDLE);
  }
//+------------------------------------------------------------------+
//| Copies the newest `count` bars starting at index 0, so the array  |
//| index equals the chart series index with no offset arithmetic.    |
//+------------------------------------------------------------------+
bool CTfData::Load(const int count)
  {
   int avail = Bars(m_symbol, m_tf);             // also kicks off the history download
   if(avail <= 0)
      return(false);
   int want = count;
   if(want > avail)
      want = avail;
   if(want < 10)
      return(false);

   ArraySetAsSeries(m_rates, true);
   int copied = CopyRates(m_symbol, m_tf, 0, want, m_rates);
   if(copied <= 0)
      return(false);                             // not synchronised yet - retry later
   m_count = copied;

   ArraySetAsSeries(m_atr, true);
   m_atrCount = 0;
   if(m_atrHandle == INVALID_HANDLE)
      return(false);
   int a = CopyBuffer(m_atrHandle, 0, 0, want, m_atr);
   if(a <= 0)
      return(false);                             // ATR not calculated yet - retry later
   m_atrCount = a;
   return(true);
  }
//+------------------------------------------------------------------+
//| ATR at bar i. Bars older than the ATR warm-up reuse the oldest    |
//| available value: every tolerance built on it is then still        |
//| deterministic, which is what the non-repainting contract needs.   |
//+------------------------------------------------------------------+
double CTfData::ATR(const int i)
  {
   if(m_atrCount <= 0)
      return(0.0);
   int k = i;
   if(k < 0)
      k = 0;
   if(k >= m_atrCount)
      k = m_atrCount - 1;
   if(m_atr[k] > 0.0)
      return(m_atr[k]);
   for(int j = k; j >= 0; j--)                   // walk towards the newest valid value
      if(m_atr[j] > 0.0)
         return(m_atr[j]);
   return(0.0);
  }

//+------------------------------------------------------------------+
//| Single-bar fetch for ad-hoc lower-timeframe scans that must not   |
//| depend on an engine's cached window. Returns false when the       |
//| terminal cannot serve the bar - callers must not guess.           |
//+------------------------------------------------------------------+
bool TTGetBar(const string sym, const ENUM_TIMEFRAMES tf, const int shift, MqlRates &r)
  {
   if(shift < 0)
      return(false);
   MqlRates tmp[];
   ArraySetAsSeries(tmp, true);
   if(CopyRates(sym, tf, shift, 1, tmp) != 1)
      return(false);
   r = tmp[0];
   return(true);
  }

//+------------------------------------------------------------------+
//| CStructureEngine                                                  |
//|                                                                   |
//| Contract                                                          |
//|   BeginUpdate() resolves how many freshly closed bars must be     |
//|   processed and loads exactly that window (plus context padding). |
//|   The caller then walks b from `startB` down to 1 and calls, in   |
//|   this order and interleaved with the other engines:              |
//|        PhasePivot(b)   - confirm the pivot that just matured      |
//|        ...             - liquidity / zones / state machine        |
//|        PhaseBreak(b)   - detect a structure break on bar b        |
//|   EndUpdate() commits the cursor. State only ever moves forward.  |
//+------------------------------------------------------------------+
class CStructureEngine
  {
private:
   CTfData           m_data;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   TTStructCfg       m_cfg;
   CSwingRing        m_swings;
   CEventRing        m_events;
   CValueTrack       m_trendTrack;
   CLevelTrack       m_weakTrack;              // history of the weak-side target
   int               m_trend;
   datetime          m_cursorTime;             // open time of the last processed bar
   bool              m_didReset;               // set when the last BeginUpdate wiped state
   //--- most recent confirmed swing that has not been consumed by a break
   bool              m_hasActHigh, m_hasActLow;
   double            m_actHigh,    m_actLow;
   datetime          m_actHighTime, m_actLowTime;
   //--- protected (strong) and target (weak) levels of the current leg
   bool              m_hasStrong,  m_hasWeak;
   double            m_strongPrice, m_weakPrice;
   datetime          m_strongTime,  m_weakTime;
   bool              m_strongIsLow;             // true in a bull leg, false in a bear leg
   //--- Which side the weak level sits on, recorded WHERE IT IS SET rather than
   //--- inferred from m_strongIsLow: the two are set independently, and a weak
   //--- level that exists without a strong one would otherwise be labelled from
   //--- m_strongIsLow's default and come out backwards.
   bool              m_weakIsHigh;
   //--- swings confirmed during the current bar (fed to the liquidity map)
   int               m_freshCount;
   TTSwing           m_fresh[4];

   bool              IsSwingHigh(const int p);
   bool              IsSwingLow(const int p);
   //--- b is the bar whose close CONFIRMED the pivot at p; the weak-level
   //--- history is stamped with that bar's close, not with the pivot's own bar
   void              RegisterSwing(const int p, const bool isHigh, const int b);
   void              ApplyBullBreak(const int b, const int hiIdx, const TTSwing &brokenHigh);
   void              ApplyBearBreak(const int b, const int loIdx, const TTSwing &brokenLow);
   void              ResetState(void);
public:
                     CStructureEngine(void);
   bool              Init(const string sym, const ENUM_TIMEFRAMES tf,
                          const TTStructCfg &cfg, const int atrPeriod);
   bool              BeginUpdate(const bool rebuild, const int maxHistory, int &startB);
   void              PhasePivot(const int b);
   bool              PhaseBreak(const int b, TTStructEvent &ev);
   void              EndUpdate(const int startB);

   //--- true when the last BeginUpdate() discarded history: every dependent
   //--- book (zones, liquidity, state machine) must reset in the same tick
   bool              DidReset(void) { return m_didReset; }
   CTfData          *Data(void) { return(GetPointer(m_data)); }
   CSwingRing       *Swings(void) { return(GetPointer(m_swings)); }
   CEventRing       *Events(void) { return(GetPointer(m_events)); }
   ENUM_TIMEFRAMES   Tf(void) { return m_tf; }
   int               Trend(void) { return m_trend; }
   int               TrendAt(const datetime t) { return m_trendTrack.ValueAt(t); }
   //--- weak-side level as it stood at time t. Targets MUST use this rather
   //--- than WeakPrice(), which is only safe for drawing the live chart.
   bool              WeakPriceAt(const datetime t, double &v) { return m_weakTrack.ValueAt(t, v); }
   bool              HasStrong(void) { return m_hasStrong; }
   bool              HasWeak(void) { return m_hasWeak; }
   double            StrongPrice(void) { return m_strongPrice; }
   double            WeakPrice(void) { return m_weakPrice; }
   datetime          StrongTime(void) { return m_strongTime; }
   datetime          WeakTime(void) { return m_weakTime; }
   bool              StrongIsLow(void) { return m_strongIsLow; }
   bool              WeakIsHigh(void) { return m_weakIsHigh; }
   //--- swings confirmed by the most recent PhasePivot() call
   int               FreshCount(void) { return m_freshCount; }
   bool              Fresh(const int i, TTSwing &out);
  };

//+------------------------------------------------------------------+
CStructureEngine::CStructureEngine(void)
  {
   m_symbol          = "";
   m_tf              = PERIOD_CURRENT;
   m_cfg.leftBars    = 3;
   m_cfg.rightBars   = 3;
   m_cfg.useWickBreaks = false;
   ResetState();
  }
//+------------------------------------------------------------------+
void CStructureEngine::ResetState(void)
  {
   m_swings.Reset();
   m_events.Reset();
   m_trendTrack.Reset();
   m_weakTrack.Reset();
   m_trend        = TT_TREND_NEUTRAL;
   m_cursorTime   = 0;
   m_hasActHigh   = false;
   m_hasActLow    = false;
   m_actHigh      = 0.0;
   m_actLow       = 0.0;
   m_actHighTime  = 0;
   m_actLowTime   = 0;
   m_hasStrong    = false;
   m_hasWeak      = false;
   m_strongPrice  = 0.0;
   m_weakPrice    = 0.0;
   m_strongTime   = 0;
   m_weakTime     = 0;
   m_strongIsLow  = true;
   m_weakIsHigh   = true;
   m_freshCount   = 0;
   m_didReset     = true;
  }
//+------------------------------------------------------------------+
bool CStructureEngine::Init(const string sym, const ENUM_TIMEFRAMES tf,
                            const TTStructCfg &cfg, const int atrPeriod)
  {
   m_symbol = sym;
   m_tf     = tf;
   m_cfg    = cfg;
   if(m_cfg.leftBars  < 1) m_cfg.leftBars  = 1;
   if(m_cfg.rightBars < 1) m_cfg.rightBars = 1;
   ResetState();
   return(m_data.Init(sym, tf, atrPeriod));
  }
//+------------------------------------------------------------------+
bool CStructureEngine::Fresh(const int i, TTSwing &out)
  {
   if(i < 0 || i >= m_freshCount)
      return(false);
   out = m_fresh[i];
   return(true);
  }
//+------------------------------------------------------------------+
//| Resolves the oldest unprocessed closed bar and loads the window.  |
//| startB == 0 means "nothing new"; the caller must skip its loop.   |
//| Returns false only when history/ATR are not ready yet.            |
//+------------------------------------------------------------------+
bool CStructureEngine::BeginUpdate(const bool rebuild, const int maxHistory, int &startB)
  {
   startB     = 0;
   m_didReset = false;
   int bars = Bars(m_symbol, m_tf);
   //--- Context padding loaded BEHIND the oldest bar we process. It has to
   //--- cover the deepest backward reach of every phase, or a phase silently
   //--- sees a truncated window and answers differently on an incremental
   //--- update (window == startB + span) than on a rebuild (window == 2000+).
   //--- The deepest reach is IsUntestedExtreme(), which starts from an origin
   //--- candle up to TTLS_ZONE_LOOKBACK back and then scans a further
   //--- TTLS_EXTREME_LOOKBACK bars: omitting the second term made a live run
   //--- grade a zone "untested" that a reload graded "tested", moving the
   //--- published quality score by TTQ_UNTESTED_EXTREME points.
   int span = m_cfg.leftBars + m_cfg.rightBars
              + TTLS_ZONE_LOOKBACK + TTLS_EXTREME_LOOKBACK + 12;
   if(bars < span + 10)
      return(false);                              // history still loading

   //--- A FIXED rebuild depth is what makes reloads reproducible: anchoring
   //--- to "all available history" would shift the starting bar whenever the
   //--- terminal downloads more of it, and with it the oldest signals.
   int mh = maxHistory;
   if(mh < 200)   mh = 200;
   if(mh > 20000) mh = 20000;

   if(rebuild || m_cursorTime == 0)
     {
      ResetState();
      startB = MathMin(mh, bars - span);
     }
   else
     {
      int sh = iBarShift(m_symbol, m_tf, m_cursorTime, false);
      if(sh < 0)                                  // cursor lost (symbol resync) -> rebuild
        {
         ResetState();
         startB = MathMin(mh, bars - span);
        }
      else
         startB = sh - 1;                         // the bar right after the cursor
     }

   if(startB < 1)
     {
      startB = 0;
      return(true);                               // up to date, window not reloaded
     }
   return(m_data.Load(startB + span));
  }
//+------------------------------------------------------------------+
void CStructureEngine::EndUpdate(const int startB)
  {
   if(startB >= 1 && m_data.Valid(1))
      m_cursorTime = m_data.Time(1);
  }
//+------------------------------------------------------------------+
//| A swing high must be STRICTLY higher than leftBars highs to its   |
//| left and rightBars highs to its right. Ties are rejected on both  |
//| sides so a flat cluster produces at most one pivot.               |
//+------------------------------------------------------------------+
bool CStructureEngine::IsSwingHigh(const int p)
  {
   double h = m_data.High(p);
   for(int k = 1; k <= m_cfg.leftBars; k++)
      if(m_data.High(p + k) >= h)
         return(false);
   for(int k = 1; k <= m_cfg.rightBars; k++)
      if(m_data.High(p - k) >= h)
         return(false);
   return(true);
  }
//+------------------------------------------------------------------+
bool CStructureEngine::IsSwingLow(const int p)
  {
   double l = m_data.Low(p);
   for(int k = 1; k <= m_cfg.leftBars; k++)
      if(m_data.Low(p + k) <= l)
         return(false);
   for(int k = 1; k <= m_cfg.rightBars; k++)
      if(m_data.Low(p - k) <= l)
         return(false);
   return(true);
  }
//+------------------------------------------------------------------+
//| Bar b has just closed. The pivot sitting rightBars bars to its    |
//| left has therefore just gained its last confirming bar - that is  |
//| the exact moment the swing becomes real, and it is why a signal   |
//| can never be revoked later.                                       |
//+------------------------------------------------------------------+
void CStructureEngine::PhasePivot(const int b)
  {
   m_freshCount = 0;
   int p = b + m_cfg.rightBars;
   if(!m_data.Valid(p + m_cfg.leftBars))
      return;                                     // not enough left-hand context
   if(IsSwingHigh(p))
      RegisterSwing(p, true, b);
   if(IsSwingLow(p))
      RegisterSwing(p, false, b);                 // an outside bar may be both
  }
//+------------------------------------------------------------------+
void CStructureEngine::RegisterSwing(const int p, const bool isHigh, const int b)
  {
   TTSwing s;
   s.time   = m_data.Time(p);
   s.price  = isHigh ? m_data.High(p) : m_data.Low(p);
   s.isHigh = isHigh;
   s.swept  = false;
   s.broken = false;
   m_swings.Add(s);
   if(m_freshCount < 4)
     {
      m_fresh[m_freshCount] = s;
      m_freshCount++;
     }

   //--- the newest confirmed swing is always the level that matters next
   if(isHigh)
     {
      m_hasActHigh  = true;
      m_actHigh     = s.price;
      m_actHighTime = s.time;
      //--- in a bull leg the highs are the weak side: each new one is the target
      if(m_trend == TT_TREND_BULL)
        {
         m_hasWeak    = true;
         m_weakPrice  = s.price;
         m_weakTime   = s.time;
         m_weakIsHigh = true;
         m_weakTrack.Push(m_data.CloseTime(b), m_weakPrice);
        }
     }
   else
     {
      m_hasActLow  = true;
      m_actLow     = s.price;
      m_actLowTime = s.time;
      if(m_trend == TT_TREND_BEAR)
        {
         m_hasWeak    = true;
         m_weakPrice  = s.price;
         m_weakTime   = s.time;
         m_weakIsHigh = false;
         m_weakTrack.Push(m_data.CloseTime(b), m_weakPrice);
        }
     }
  }
//+------------------------------------------------------------------+
//| Structure break on bar b.                                         |
//|                                                                   |
//| Precedence when one bar breaks both sides (documented behaviour): |
//| the break that CONTINUES the prevailing trend is taken; from      |
//| NEUTRAL the bullish break is taken. At most one event per bar.    |
//+------------------------------------------------------------------+
bool CStructureEngine::PhaseBreak(const int b, TTStructEvent &ev)
  {
   double up = m_cfg.useWickBreaks ? m_data.High(b) : m_data.Close(b);
   double dn = m_cfg.useWickBreaks ? m_data.Low(b)  : m_data.Close(b);

   bool canUp = (m_hasActHigh && up > m_actHigh);
   bool canDn = (m_hasActLow  && dn < m_actLow);
   if(!canUp && !canDn)
      return(false);

   bool takeUp = canUp;
   if(canUp && canDn)
      takeUp = (m_trend != TT_TREND_BEAR);

   //--- classify BEFORE the trend is mutated: a break in the direction we
   //--- were already trending is continuation (BOS), everything else is a
   //--- change of character (MS / CHoCH)
   int  trendBefore = m_trend;
   bool isBOS = takeUp ? (trendBefore == TT_TREND_BULL)
                       : (trendBefore == TT_TREND_BEAR);

   TTSwing broken;
   broken.time   = takeUp ? m_actHighTime : m_actLowTime;
   broken.price  = takeUp ? m_actHigh     : m_actLow;
   broken.isHigh = takeUp;
   broken.swept  = false;
   broken.broken = true;

   int idx = m_swings.NewestUnbroken(takeUp);
   if(takeUp)
      ApplyBullBreak(b, idx, broken);
   else
      ApplyBearBreak(b, idx, broken);

   ev.breakTime  = m_data.Time(b);
   ev.breakClose = m_data.CloseTime(b);
   ev.swingTime = broken.time;
   ev.price     = broken.price;
   ev.bullish   = takeUp;
   ev.isBOS     = isBOS;
   m_events.Add(ev);
   return(true);
  }
//+------------------------------------------------------------------+
//| Bullish break bookkeeping.                                        |
//| The protected (strong) low is the LOWEST confirmed swing low      |
//| between the broken high and the breaking bar: that low is the     |
//| origin of the leg that took the level, so price trading back      |
//| below it invalidates the whole bullish premise.                   |
//+------------------------------------------------------------------+
void CStructureEngine::ApplyBullBreak(const int b, const int hiIdx, const TTSwing &brokenHigh)
  {
   if(hiIdx >= 0)
      m_swings.MarkBroken(hiIdx);
   m_hasActHigh = false;

   double   lp = 0.0;
   datetime lt = 0;
   if(m_swings.ExtremeInWindow(false, brokenHigh.time, m_data.Time(b), lp, lt))
     {
      m_strongPrice = lp;
      m_strongTime  = lt;
     }
   else
      if(m_hasActLow)                              // no confirmed low inside the leg
        {
         m_strongPrice = m_actLow;
         m_strongTime  = m_actLowTime;
        }
      else
        {
         m_strongPrice = m_data.Low(b);
         m_strongTime  = m_data.Time(b);
        }
   m_hasStrong   = true;
   m_strongIsLow = true;
   //--- the protected low becomes the level whose loss would flip structure
   m_hasActLow  = true;
   m_actLow     = m_strongPrice;
   m_actLowTime = m_strongTime;
   //--- until a fresh high prints, the broken high is the weak-side reference
   m_hasWeak    = true;
   m_weakPrice  = brokenHigh.price;
   m_weakTime   = brokenHigh.time;
   m_weakIsHigh = true;
   m_weakTrack.Push(m_data.CloseTime(b), m_weakPrice);

   m_trend = TT_TREND_BULL;
   m_trendTrack.Push(m_data.CloseTime(b), m_trend);
  }
//+------------------------------------------------------------------+
void CStructureEngine::ApplyBearBreak(const int b, const int loIdx, const TTSwing &brokenLow)
  {
   if(loIdx >= 0)
      m_swings.MarkBroken(loIdx);
   m_hasActLow = false;

   double   hp = 0.0;
   datetime ht = 0;
   if(m_swings.ExtremeInWindow(true, brokenLow.time, m_data.Time(b), hp, ht))
     {
      m_strongPrice = hp;
      m_strongTime  = ht;
     }
   else
      if(m_hasActHigh)
        {
         m_strongPrice = m_actHigh;
         m_strongTime  = m_actHighTime;
        }
      else
        {
         m_strongPrice = m_data.High(b);
         m_strongTime  = m_data.Time(b);
        }
   m_hasStrong   = true;
   m_strongIsLow = false;
   m_hasActHigh  = true;
   m_actHigh     = m_strongPrice;
   m_actHighTime = m_strongTime;
   m_hasWeak    = true;
   m_weakPrice  = brokenLow.price;
   m_weakTime   = brokenLow.time;
   m_weakIsHigh = false;
   m_weakTrack.Push(m_data.CloseTime(b), m_weakPrice);

   m_trend = TT_TREND_BEAR;
   m_trendTrack.Push(m_data.CloseTime(b), m_trend);
  }

#endif // __TT_STRUCTURE_MQH__
//+------------------------------------------------------------------+
