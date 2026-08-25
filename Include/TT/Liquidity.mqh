//+------------------------------------------------------------------+
//|                                                     Liquidity.mqh |
//|            TT_LiquidityScalper - liquidity pools + sweep detection |
//|                                                                   |
//|  Indexing: SERIES (index 0 = forming bar, 1 = last closed bar).    |
//|  See the convention block at the top of Structure.mqh.             |
//|                                                                   |
//|  What a "pool" is                                                  |
//|    Every unswept confirmed swing high is buy-side liquidity and    |
//|    every unswept confirmed swing low is sell-side liquidity.       |
//|    Swings whose prices sit within EqualLevelTolerance of each      |
//|    other are the same resting order block for the market, so they  |
//|    are merged into ONE pool carrying a hit count. Equal highs and  |
//|    equal lows are the highest quality targets, which is why the    |
//|    count feeds the signal quality score.                           |
//+------------------------------------------------------------------+
#ifndef __TT_LIQUIDITY_MQH__
#define __TT_LIQUIDITY_MQH__

#include <TT/Structure.mqh>

#define TTLS_MAX_POOLS           512
//--- auto-tuning factors used when the matching input is left at 0
#define TTLS_AUTO_SWEEP_BUF_ATR  0.10
#define TTLS_AUTO_PROXIMITY_ATR  0.25

//+------------------------------------------------------------------+
//| Liquidity configuration.                                          |
//+------------------------------------------------------------------+
struct TTLiqCfg
  {
   double            eqTolAtr;       // equal-level tolerance as a fraction of ATR
   double            sweepBufPts;    // penetration required, in points (0 = auto from ATR)
   int               closeBackBars;  // bars allowed for the close-back (0 = same bar only)
   double            proximityPts;   // sweep-to-zone distance allowance (0 = auto from ATR)
  };

//+------------------------------------------------------------------+
//| One liquidity pool.                                               |
//+------------------------------------------------------------------+
struct TTLiqPool
  {
   int               id;
   double            price;        // the extreme of the cluster - the level that must break
   datetime          firstTime;    // oldest swing in the cluster
   datetime          lastTime;     // newest swing in the cluster
   int               count;        // number of clustered swings (>=2 == equal highs/lows)
   bool              buySide;      // true = above price (swing highs), false = below
   bool              active;       // still a valid target
   bool              swept;        // taken and rejected
   bool              broken;       // traded clean through - consumed, not swept
   datetime          sweepTime;    // open time of the bar that took it
   double            sweepExtreme; // deepest penetration = the protected high/low
   //--- multi-bar close-back bookkeeping
   int               pendBars;     // bars elapsed since the straddle bar (-1 = not pending)
   datetime          pendTime;
   double            pendExtreme;
  };

//+------------------------------------------------------------------+
//| Description of a completed sweep, handed to the state machine.    |
//+------------------------------------------------------------------+
struct TTSweepInfo
  {
   int               poolId;
   double            poolPrice;
   double            extreme;      // protected low (buy setup) / high (sell setup)
   bool              buySide;      // side of liquidity that was taken
   int               poolCount;
   datetime          sweepBarTime; // bar that penetrated the level
   datetime          doneBarTime;  // bar whose close confirmed the rejection
  };

//+------------------------------------------------------------------+
//| CLiquidityMap                                                     |
//|                                                                   |
//| Contract: pools are created only from CONFIRMED swings and their  |
//| state only ever moves forward (live -> swept | broken). Nothing    |
//| is recomputed from scratch on a tick, so a pool that was swept on  |
//| bar N is still swept on bar N after a reload.                      |
//+------------------------------------------------------------------+
class CLiquidityMap
  {
private:
   CTfData          *m_data;
   TTLiqCfg          m_cfg;
   TTLiqPool         m_pools[];
   int               m_count;
   int               m_nextId;

   double            PointSize(void);
   double            SweepBuffer(const int b);
   int               FindMergeable(const double price, const bool buySide, const double tol);
   void              Compact(void);
   bool              CompleteSweep(const int i, const int b, TTSweepInfo &out);
   bool              StepPending(const int i, const int b, TTSweepInfo &out);
   bool              StepFresh(const int i, const int b, const double buf, TTSweepInfo &out);
public:
                     CLiquidityMap(void);
   void              Init(CTfData *data, const TTLiqCfg &cfg);
   void              Reset(void);
   //--- register a freshly confirmed swing (call once per confirmation)
   void              OnSwingConfirmed(const TTSwing &s, const double atr);
   //--- evaluate bar b against every live pool; true when a sweep completed
   bool              PhaseSweep(const int b, TTSweepInfo &out);
   //--- distance allowed between a sweep and the zone it must belong to
   double            ProximityPrice(const int b);

   int               Count(void) { return m_count; }
   bool              Get(const int i, TTLiqPool &out);
   int               UnsweptCount(const datetime asOf);
   //--- nearest live pool beyond `from` on the requested side (target hunting)
   bool              NearestUnswept(const double from, const bool buySide,
                                    const datetime asOf, TTLiqPool &out);
   bool              PoolById(const int id, TTLiqPool &out);
  };

//+------------------------------------------------------------------+
CLiquidityMap::CLiquidityMap(void)
  {
   m_data    = NULL;
   m_count   = 0;
   m_nextId  = 0;
   m_cfg.eqTolAtr      = 0.15;
   m_cfg.sweepBufPts   = 0.0;
   m_cfg.closeBackBars = 1;
   m_cfg.proximityPts  = 0.0;
   ArrayResize(m_pools, TTLS_MAX_POOLS);
  }
//+------------------------------------------------------------------+
void CLiquidityMap::Init(CTfData *data, const TTLiqCfg &cfg)
  {
   m_data = data;
   m_cfg  = cfg;
   if(m_cfg.closeBackBars < 0)
      m_cfg.closeBackBars = 0;
   Reset();
  }
//+------------------------------------------------------------------+
void CLiquidityMap::Reset(void)
  {
   m_count  = 0;
   m_nextId = 0;
  }
//+------------------------------------------------------------------+
double CLiquidityMap::PointSize(void)
  {
   double p = SymbolInfoDouble(m_data.Sym(), SYMBOL_POINT);
   return(p > 0.0 ? p : _Point);
  }
//+------------------------------------------------------------------+
//| Penetration a bar must achieve before the level counts as raided. |
//| Left at 0 the buffer scales with volatility, which is what keeps  |
//| the same settings usable on 2-digit and 3-digit gold feeds.       |
//+------------------------------------------------------------------+
double CLiquidityMap::SweepBuffer(const int b)
  {
   if(m_cfg.sweepBufPts > 0.0)
      return(m_cfg.sweepBufPts * PointSize());
   double atr = m_data.ATR(b);
   double v   = atr * TTLS_AUTO_SWEEP_BUF_ATR;
   double flr = TTLS_MIN_TOL_POINTS * PointSize();
   return(v > flr ? v : flr);
  }
//+------------------------------------------------------------------+
double CLiquidityMap::ProximityPrice(const int b)
  {
   if(m_cfg.proximityPts > 0.0)
      return(m_cfg.proximityPts * PointSize());
   double atr = m_data.ATR(b);
   double v   = atr * TTLS_AUTO_PROXIMITY_ATR;
   double flr = TTLS_MIN_TOL_POINTS * PointSize();
   return(v > flr ? v : flr);
  }
//+------------------------------------------------------------------+
bool CLiquidityMap::Get(const int i, TTLiqPool &out)
  {
   if(i < 0 || i >= m_count)
      return(false);
   out = m_pools[i];
   return(true);
  }
//+------------------------------------------------------------------+
bool CLiquidityMap::PoolById(const int id, TTLiqPool &out)
  {
   for(int i = m_count - 1; i >= 0; i--)
      if(m_pools[i].id == id)
        {
         out = m_pools[i];
         return(true);
        }
   return(false);
  }
//+------------------------------------------------------------------+
//| Drops consumed pools once the array is full. Live pools are never |
//| discarded, so target hunting cannot silently lose a level.        |
//+------------------------------------------------------------------+
void CLiquidityMap::Compact(void)
  {
   int w = 0;
   for(int i = 0; i < m_count; i++)
      if(m_pools[i].active)
        {
         m_pools[w] = m_pools[i];
         w++;
        }
   if(w == m_count && m_count > 0)               // everything is still live: drop the oldest
     {
      for(int i = 1; i < m_count; i++)
         m_pools[i - 1] = m_pools[i];
      w = m_count - 1;
     }
   m_count = w;
  }
//+------------------------------------------------------------------+
int CLiquidityMap::FindMergeable(const double price, const bool buySide, const double tol)
  {
   for(int i = m_count - 1; i >= 0; i--)         // newest pools first
     {
      if(!m_pools[i].active || m_pools[i].buySide != buySide)
         continue;
      if(MathAbs(m_pools[i].price - price) <= tol)
         return(i);
     }
   return(-1);
  }
//+------------------------------------------------------------------+
//| Registers a confirmed swing. Swings within tolerance of a live    |
//| pool are merged (equal highs / equal lows) and the pool's price   |
//| moves OUTWARD to the extreme of the cluster - price has to clear  |
//| every one of those highs to actually collect the stops behind it. |
//+------------------------------------------------------------------+
void CLiquidityMap::OnSwingConfirmed(const TTSwing &s, const double atr)
  {
   double tol = atr * m_cfg.eqTolAtr;
   double flr = TTLS_MIN_TOL_POINTS * PointSize();
   if(tol < flr)
      tol = flr;

   int m = FindMergeable(s.price, s.isHigh, tol);
   if(m >= 0)
     {
      m_pools[m].count++;
      m_pools[m].lastTime = s.time;
      if(s.isHigh)
        {
         if(s.price > m_pools[m].price)
            m_pools[m].price = s.price;
        }
      else
         if(s.price < m_pools[m].price)
            m_pools[m].price = s.price;
      return;
     }

   if(m_count >= TTLS_MAX_POOLS)
      Compact();
   if(m_count >= TTLS_MAX_POOLS)
      return;

   TTLiqPool p;
   p.id           = m_nextId;
   m_nextId++;
   p.price        = s.price;
   p.firstTime    = s.time;
   p.lastTime     = s.time;
   p.count        = 1;
   p.buySide      = s.isHigh;
   p.active       = true;
   p.swept        = false;
   p.broken       = false;
   p.sweepTime    = 0;
   p.sweepExtreme = 0.0;
   p.pendBars     = -1;
   p.pendTime     = 0;
   p.pendExtreme  = 0.0;
   m_pools[m_count] = p;
   m_count++;
  }
//+------------------------------------------------------------------+
//| Marks pool i swept using bar b as the confirming close.           |
//+------------------------------------------------------------------+
bool CLiquidityMap::CompleteSweep(const int i, const int b, TTSweepInfo &out)
  {
   m_pools[i].swept  = true;
   m_pools[i].active = false;
   if(m_pools[i].pendBars < 0)                   // same-bar sweep
     {
      m_pools[i].sweepTime    = m_data.Time(b);
      m_pools[i].sweepExtreme = m_pools[i].buySide ? m_data.High(b) : m_data.Low(b);
     }
   else                                          // multi-bar sweep: keep the deepest wick
     {
      m_pools[i].sweepTime    = m_pools[i].pendTime;
      double e = m_pools[i].pendExtreme;
      double c = m_pools[i].buySide ? m_data.High(b) : m_data.Low(b);
      m_pools[i].sweepExtreme = m_pools[i].buySide ? MathMax(e, c) : MathMin(e, c);
     }
   m_pools[i].pendBars = -1;

   out.poolId       = m_pools[i].id;
   out.poolPrice    = m_pools[i].price;
   out.extreme      = m_pools[i].sweepExtreme;
   out.buySide      = m_pools[i].buySide;
   out.poolCount    = m_pools[i].count;
   out.sweepBarTime = m_pools[i].sweepTime;
   out.doneBarTime  = m_data.Time(b);
   return(true);
  }
//+------------------------------------------------------------------+
//| Sweep detection for one closed bar.                               |
//|                                                                   |
//| A sell-side pool at P is swept when a bar trades below P by the   |
//| buffer AND price closes back above P (same bar, or within         |
//| SweepCloseBackBars bars).                                         |
//|                                                                   |
//| Gap guard: the bar must also REACH the level (High >= P). A       |
//| weekend gap that opens below P never traded through the resting   |
//| orders, so it is a break, not a sweep - exactly the distinction   |
//| that stops Monday-open gaps from arming a setup.                  |
//|                                                                   |
//| When several pools complete on the same bar the strongest one     |
//| wins (highest cluster count, then the deepest level), because     |
//| that is the level whose stops actually funded the reversal.       |
//+------------------------------------------------------------------+
bool CLiquidityMap::PhaseSweep(const int b, TTSweepInfo &out)
  {
   double buf   = SweepBuffer(b);
   bool   found = false;
   TTSweepInfo best;
   ZeroMemory(best);
   int    bestCount = -1;
   double bestDepth = 0.0;

   for(int i = 0; i < m_count; i++)
     {
      if(!m_pools[i].active)
         continue;

      TTSweepInfo s;
      ZeroMemory(s);
      bool done = (m_pools[i].pendBars >= 0) ? StepPending(i, b, s)
                                             : StepFresh(i, b, buf, s);
      if(!done)
         continue;

      //--- strongest pool wins: the deepest raid on the biggest cluster is
      //--- the one whose stops actually funded the reversal
      double depth = MathAbs(s.extreme - s.poolPrice);
      if(s.poolCount > bestCount || (s.poolCount == bestCount && depth > bestDepth))
        {
         best      = s;
         bestCount = s.poolCount;
         bestDepth = depth;
        }
      found = true;
     }

   if(found)
      out = best;
   return(found);
  }
//+------------------------------------------------------------------+
//| An in-flight straddle waiting for its close-back. Returns true     |
//| when the sweep completed on this bar.                              |
//+------------------------------------------------------------------+
bool CLiquidityMap::StepPending(const int i, const int b, TTSweepInfo &out)
  {
   double P  = m_pools[i].price;
   bool   bs = m_pools[i].buySide;
   double hi = m_data.High(b);
   double lo = m_data.Low(b);

   m_pools[i].pendExtreme = bs ? MathMax(m_pools[i].pendExtreme, hi)
                               : MathMin(m_pools[i].pendExtreme, lo);
   bool back = bs ? (m_data.Close(b) < P) : (m_data.Close(b) > P);
   if(back)
      return(CompleteSweep(i, b, out));

   m_pools[i].pendBars++;
   if(m_pools[i].pendBars > m_cfg.closeBackBars)
     {
      //--- never closed back: the level was run through, not raided
      m_pools[i].pendBars = -1;
      m_pools[i].active   = false;
      m_pools[i].broken   = true;
     }
   return(false);
  }
//+------------------------------------------------------------------+
//| First contact with the level on this bar. Returns true when the    |
//| sweep completed same-bar.                                          |
//+------------------------------------------------------------------+
bool CLiquidityMap::StepFresh(const int i, const int b, const double buf, TTSweepInfo &out)
  {
   double P  = m_pools[i].price;
   bool   bs = m_pools[i].buySide;
   double hi = m_data.High(b);
   double lo = m_data.Low(b);
   double cl = m_data.Close(b);

   //--- the bar must both PENETRATE the level and REACH it from the other
   //--- side; the second half is the gap guard
   bool straddle = bs ? (hi > P + buf && lo <= P)
                      : (lo < P - buf && hi >= P);
   if(straddle)
     {
      bool back = bs ? (cl < P) : (cl > P);
      if(back)
         return(CompleteSweep(i, b, out));
      if(m_cfg.closeBackBars > 0)
        {
         m_pools[i].pendBars    = 1;
         m_pools[i].pendTime    = m_data.Time(b);
         m_pools[i].pendExtreme = bs ? hi : lo;
         return(false);
        }
     }

   //--- closed clean through: liquidity consumed, not swept
   bool through = bs ? (cl > P + buf) : (cl < P - buf);
   if(through)
     {
      m_pools[i].active = false;
      m_pools[i].broken = true;
     }
   return(false);
  }
//+------------------------------------------------------------------+
int CLiquidityMap::UnsweptCount(const datetime asOf)
  {
   int n = 0;
   for(int i = 0; i < m_count; i++)
      if(m_pools[i].active && m_pools[i].firstTime <= asOf)
         n++;
   return(n);
  }
//+------------------------------------------------------------------+
//| Nearest live pool beyond `from`. Used for TARGET_NEAREST_INTERNAL:|
//| a scalp is closed where the next batch of resting orders sits,    |
//| not at an arbitrary multiple of risk.                             |
//+------------------------------------------------------------------+
bool CLiquidityMap::NearestUnswept(const double from, const bool buySide,
                                   const datetime asOf, TTLiqPool &out)
  {
   bool   found = false;
   double bestD = 0.0;
   for(int i = 0; i < m_count; i++)
     {
      if(!m_pools[i].active || m_pools[i].buySide != buySide)
         continue;
      if(m_pools[i].firstTime > asOf)            // not yet known at that moment
         continue;
      double d = buySide ? (m_pools[i].price - from) : (from - m_pools[i].price);
      if(d <= 0.0)
         continue;
      if(!found || d < bestD)
        {
         bestD = d;
         out   = m_pools[i];
         found = true;
        }
     }
   return(found);
  }

#endif // __TT_LIQUIDITY_MQH__
//+------------------------------------------------------------------+
