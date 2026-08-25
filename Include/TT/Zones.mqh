//+------------------------------------------------------------------+
//|                                                         Zones.mqh |
//|      TT_LiquidityScalper - demand/supply, order blocks, FVG,       |
//|      breakers, and their mitigation life cycle                     |
//|                                                                   |
//|  Indexing: SERIES (index 0 = forming bar, 1 = last closed bar).    |
//|  See the convention block at the top of Structure.mqh.             |
//|                                                                   |
//|  Life cycle of every zone (forward-only, never rewound):           |
//|      LIVE      - built, price has not returned                     |
//|      TOUCHED   - price traded into the box                         |
//|      MITIGATED - traded in AND closed back out on the origin side  |
//|      INVALID   - a bar closed fully beyond the far edge            |
//|  Only LIVE/TOUCHED/MITIGATED zones can arm a setup; INVALID zones  |
//|  are kept purely so the chart shows why a level stopped working.   |
//+------------------------------------------------------------------+
#ifndef __TT_ZONES_MQH__
#define __TT_ZONES_MQH__

#include <TT/Structure.mqh>

//--- see the capacity note in Structure.mqh: the EntryTF book is queried
//--- cross-timeframe, so it must outlive the SetupTF loop's reach
#define TTLS_MAX_ZONES           512
//--- how many contiguous base candles ZONE_FULL_RANGE may absorb
#define TTLS_MAX_BASE_CANDLES    5
//--- breakers that may be spawned by a single bar killing several zones
#define TTLS_MAX_BREAKERS_PER_BAR 8

//+------------------------------------------------------------------+
//| How much of the origin is treated as the zone.                    |
//|   ZONE_PIVOT_CANDLE - the single origin candle's high/low range   |
//|   ZONE_FULL_RANGE   - the whole contiguous base before the leg    |
//| Both exist because a retracement can miss one and mitigate the    |
//| other; running the wrong one silently drops valid setups.         |
//+------------------------------------------------------------------+
enum ZONE_MODE
  {
   ZONE_PIVOT_CANDLE = 0,  // Pivot candle only
   ZONE_FULL_RANGE   = 1   // Full base / consolidation
  };

enum TT_ZONE_TYPE
  {
   TTZ_DEMAND_SUPPLY = 0,
   TTZ_ORDER_BLOCK   = 1,
   TTZ_FVG           = 2,
   TTZ_BREAKER       = 3
  };

enum TT_ZONE_STATE
  {
   TTZS_LIVE      = 0,
   TTZS_TOUCHED   = 1,
   TTZS_MITIGATED = 2,
   TTZS_INVALID   = 3
  };

//+------------------------------------------------------------------+
struct TTZoneCfg
  {
   bool              useDemandSupply;
   bool              useOrderBlocks;
   bool              useFVG;
   bool              useBreakers;
   int               mode;          // ZONE_MODE
   int               maxActive;     // live zones kept per direction
  };

//+------------------------------------------------------------------+
struct TTZone
  {
   int               id;
   double            top;
   double            bottom;
   datetime          createdTime;   // origin candle - the box's left edge
   datetime          eventTime;     // bar whose close created the zone
   int               type;          // TT_ZONE_TYPE
   int               state;         // TT_ZONE_STATE
   bool              bullish;       // true = demand, false = supply
   bool              untestedExtreme;
   datetime          touchTime;
   datetime          mitigateTime;
   datetime          invalidTime;
   ENUM_TIMEFRAMES   tf;
  };

//+------------------------------------------------------------------+
//| CZoneBook                                                         |
//|                                                                   |
//| Contract - called once per freshly closed bar, in this order:     |
//|   PhaseUpdateStates(b)      mitigation/invalidation for bar b      |
//|   PhaseScanFVG(b)           three-bar imbalance ending at bar b    |
//|   PhaseBuildFromEvent(b,ev) origin zones behind an MS/BOS          |
//| Zones created on bar b are never mitigated by bar b - the bar      |
//| that builds a zone is part of the impulse away from it.            |
//+------------------------------------------------------------------+
class CZoneBook
  {
private:
   CTfData          *m_data;
   TTZoneCfg         m_cfg;
   TTZone            m_zones[];
   int               m_count;
   int               m_nextId;

   void              Compact(void);
   int               FindOriginCandle(const int b, const bool bullish);
   bool              BuildBox(const int k, const bool bullish, const bool forceSingle,
                              double &top, double &bottom, datetime &startTime);
   bool              IsUntestedExtreme(const int k, const bool bullish);
   int               FindOverlap(const double top, const double bottom, const bool bullish,
                                 const int type);
   void              AddZone(const double top, const double bottom, const datetime created,
                             const datetime evTime, const int type, const bool bullish,
                             const bool untested);
   bool              StepZone(const int i, const int b);
public:
                     CZoneBook(void);
   void              Init(CTfData *data, const TTZoneCfg &cfg);
   void              Reset(void);
   void              PhaseUpdateStates(const int b);
   void              PhaseScanFVG(const int b);
   void              PhaseBuildFromEvent(const int b, const TTStructEvent &ev);

   int               Count(void) { return m_count; }
   bool              Get(const int i, TTZone &out);
   bool              ZoneById(const int id, TTZone &out);
   //--- zone built by the break that closed at evTime; demand/supply is
   //--- preferred over the tighter order block because the conservative
   //--- entry wants the whole base to lean on
   bool              FindByEvent(const datetime evTime, const bool bullish, TTZone &out);
   //--- zones that may still produce a signal, ranked by distance from price
   int               LiveCount(const bool bullish, const datetime asOf);
   //--- i-th nearest live zone of one direction (0 = nearest), false when none
   bool              NearestLive(const int rank, const double price, const bool bullish,
                                 const datetime asOf, TTZone &out);
  };

//+------------------------------------------------------------------+
CZoneBook::CZoneBook(void)
  {
   m_data   = NULL;
   m_count  = 0;
   m_nextId = 0;
   m_cfg.useDemandSupply = true;
   m_cfg.useOrderBlocks  = true;
   m_cfg.useFVG          = true;
   m_cfg.useBreakers     = true;
   m_cfg.mode            = ZONE_PIVOT_CANDLE;
   m_cfg.maxActive       = 3;
   ArrayResize(m_zones, TTLS_MAX_ZONES);
  }
//+------------------------------------------------------------------+
void CZoneBook::Init(CTfData *data, const TTZoneCfg &cfg)
  {
   m_data = data;
   m_cfg  = cfg;
   if(m_cfg.maxActive < 1)
      m_cfg.maxActive = 1;
   Reset();
  }
//+------------------------------------------------------------------+
void CZoneBook::Reset(void)
  {
   m_count  = 0;
   m_nextId = 0;
  }
//+------------------------------------------------------------------+
bool CZoneBook::Get(const int i, TTZone &out)
  {
   if(i < 0 || i >= m_count)
      return(false);
   out = m_zones[i];
   return(true);
  }
//+------------------------------------------------------------------+
bool CZoneBook::ZoneById(const int id, TTZone &out)
  {
   for(int i = m_count - 1; i >= 0; i--)
      if(m_zones[i].id == id)
        {
         out = m_zones[i];
         return(true);
        }
   return(false);
  }
//+------------------------------------------------------------------+
bool CZoneBook::FindByEvent(const datetime evTime, const bool bullish, TTZone &out)
  {
   int best = -1;
   for(int i = m_count - 1; i >= 0; i--)
     {
      if(m_zones[i].eventTime != evTime || m_zones[i].bullish != bullish)
         continue;
      if(m_zones[i].type != TTZ_DEMAND_SUPPLY && m_zones[i].type != TTZ_ORDER_BLOCK)
         continue;
      if(best < 0 || m_zones[i].type == TTZ_DEMAND_SUPPLY)
         best = i;
      if(m_zones[i].type == TTZ_DEMAND_SUPPLY)
         break;
     }
   if(best < 0)
      return(false);
   out = m_zones[best];
   return(true);
  }
//+------------------------------------------------------------------+
//| Frees room by dropping invalidated zones oldest-first; if every   |
//| zone is still usable the oldest one goes, since zones far behind  |
//| price are the least likely to be revisited.                       |
//+------------------------------------------------------------------+
void CZoneBook::Compact(void)
  {
   int w = 0;
   for(int i = 0; i < m_count; i++)
      if(m_zones[i].state != TTZS_INVALID)
        {
         m_zones[w] = m_zones[i];
         w++;
        }
   if(w == m_count && m_count > 0)
     {
      for(int i = 1; i < m_count; i++)
         m_zones[i - 1] = m_zones[i];
      w = m_count - 1;
     }
   m_count = w;
  }
//+------------------------------------------------------------------+
//| The origin candle of an impulsive leg: walking back from the      |
//| breaking bar, the last candle that closed AGAINST the break.      |
//| That candle is where the passive orders that drove the leg sat.   |
//+------------------------------------------------------------------+
int CZoneBook::FindOriginCandle(const int b, const bool bullish)
  {
   for(int k = b; k <= b + TTLS_ZONE_LOOKBACK; k++)
     {
      if(!m_data.Valid(k + 1))
         return(-1);
      if(bullish ? m_data.IsDown(k) : m_data.IsUp(k))
         return(k);
     }
   return(-1);
  }
//+------------------------------------------------------------------+
//| Turns the origin candle into a box.                               |
//| forceSingle == true is the ORDER BLOCK definition (pivot candle   |
//| only) regardless of ZoneMode; otherwise ZONE_FULL_RANGE absorbs   |
//| the contiguous base candles that preceded the impulse.            |
//+------------------------------------------------------------------+
bool CZoneBook::BuildBox(const int k, const bool bullish, const bool forceSingle,
                         double &top, double &bottom, datetime &startTime)
  {
   if(!m_data.Valid(k))
      return(false);
   top       = m_data.High(k);
   bottom    = m_data.Low(k);
   startTime = m_data.Time(k);

   if(!forceSingle && m_cfg.mode == ZONE_FULL_RANGE)
     {
      for(int j = k + 1; j <= k + TTLS_MAX_BASE_CANDLES; j++)
        {
         if(!m_data.Valid(j))
            break;
         bool sameSide = bullish ? m_data.IsDown(j) : m_data.IsUp(j);
         if(!sameSide)
            break;                                // consolidation ended
         top       = MathMax(top, m_data.High(j));
         bottom    = MathMin(bottom, m_data.Low(j));
         startTime = m_data.Time(j);
        }
     }
   return(top > bottom);
  }
//+------------------------------------------------------------------+
//| A zone sitting at the extreme of the recent range has never been  |
//| traded against - those are the ones that hold. Feeds the quality  |
//| score rather than gating the signal.                              |
//+------------------------------------------------------------------+
bool CZoneBook::IsUntestedExtreme(const int k, const bool bullish)
  {
   double ref = bullish ? m_data.Low(k) : m_data.High(k);
   for(int j = k + 1; j <= k + TTLS_EXTREME_LOOKBACK; j++)
     {
      if(!m_data.Valid(j))
         break;
      if(bullish)
        {
         if(m_data.Low(j) < ref)
            return(false);
        }
      else
         if(m_data.High(j) > ref)
            return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
//| Overlap check. Nested or overlapping zones of the same direction  |
//| and type describe ONE structural event, so they are merged into   |
//| the larger box instead of firing twice off the same move.         |
//+------------------------------------------------------------------+
int CZoneBook::FindOverlap(const double top, const double bottom, const bool bullish,
                           const int type)
  {
   for(int i = m_count - 1; i >= 0; i--)
     {
      if(m_zones[i].state == TTZS_INVALID)
         continue;
      if(m_zones[i].bullish != bullish || m_zones[i].type != type)
         continue;
      if(top >= m_zones[i].bottom && bottom <= m_zones[i].top)
         return(i);
     }
   return(-1);
  }
//+------------------------------------------------------------------+
void CZoneBook::AddZone(const double top, const double bottom, const datetime created,
                        const datetime evTime, const int type, const bool bullish,
                        const bool untested)
  {
   if(top <= bottom)
      return;

   int ov = FindOverlap(top, bottom, bullish, type);
   if(ov >= 0)
     {
      //--- merge into the larger box, keeping the older origin as the anchor
      m_zones[ov].top    = MathMax(m_zones[ov].top, top);
      m_zones[ov].bottom = MathMin(m_zones[ov].bottom, bottom);
      if(created < m_zones[ov].createdTime)
         m_zones[ov].createdTime = created;
      m_zones[ov].untestedExtreme = (m_zones[ov].untestedExtreme || untested);
      return;
     }

   if(m_count >= TTLS_MAX_ZONES)
      Compact();
   if(m_count >= TTLS_MAX_ZONES)
      return;

   TTZone z;
   z.id              = m_nextId;
   m_nextId++;
   z.top             = top;
   z.bottom          = bottom;
   z.createdTime     = created;
   z.eventTime       = evTime;
   z.type            = type;
   z.state           = TTZS_LIVE;
   z.bullish         = bullish;
   z.untestedExtreme = untested;
   z.touchTime       = 0;
   z.mitigateTime    = 0;
   z.invalidTime     = 0;
   z.tf              = m_data.Tf();
   m_zones[m_count]  = z;
   m_count++;
  }
//+------------------------------------------------------------------+
//| Zone construction behind a confirmed MS/BOS.                      |
//| Demand/supply and order block share the same origin candle; the   |
//| difference is only how much of the base the box covers.           |
//+------------------------------------------------------------------+
void CZoneBook::PhaseBuildFromEvent(const int b, const TTStructEvent &ev)
  {
   if(!m_cfg.useDemandSupply && !m_cfg.useOrderBlocks)
      return;
   int k = FindOriginCandle(b, ev.bullish);
   if(k < 0)
      return;

   bool     untested = IsUntestedExtreme(k, ev.bullish);
   datetime evTime   = m_data.Time(b);
   double   top, bottom;
   datetime start;

   if(m_cfg.useDemandSupply && BuildBox(k, ev.bullish, false, top, bottom, start))
      AddZone(top, bottom, start, evTime, TTZ_DEMAND_SUPPLY, ev.bullish, untested);

   if(m_cfg.useOrderBlocks && BuildBox(k, ev.bullish, true, top, bottom, start))
      AddZone(top, bottom, start, evTime, TTZ_ORDER_BLOCK, ev.bullish, untested);
  }
//+------------------------------------------------------------------+
//| Three-bar imbalance ending at bar b.                              |
//| Series indexing: b is the newest of the three, b+2 the oldest.    |
//| Bullish gap when High[b+2] < Low[b] (the printed spec uses        |
//| left-to-right indices, which is the same pattern mirrored).       |
//+------------------------------------------------------------------+
void CZoneBook::PhaseScanFVG(const int b)
  {
   if(!m_cfg.useFVG || !m_data.Valid(b + 2))
      return;

   double h2 = m_data.High(b + 2);
   double l2 = m_data.Low(b + 2);
   double h0 = m_data.High(b);
   double l0 = m_data.Low(b);

   if(h2 < l0)                                   // bullish imbalance
      AddZone(l0, h2, m_data.Time(b + 2), m_data.Time(b), TTZ_FVG, true,
              IsUntestedExtreme(b + 2, true));
   else
      if(l2 > h0)                                // bearish imbalance
         AddZone(l2, h0, m_data.Time(b + 2), m_data.Time(b), TTZ_FVG, false,
                 IsUntestedExtreme(b + 2, false));
  }
//+------------------------------------------------------------------+
//| Advances one zone through bar b.                                  |
//| Order matters: invalidation is tested first, so a bar that blows  |
//| clean through a zone can never be recorded as a mitigation.       |
//| Returns true when the zone just died and owes the book a breaker; |
//| the caller adds it AFTER the sweep over the array, because        |
//| AddZone() may compact and reindex m_zones.                        |
//+------------------------------------------------------------------+
bool CZoneBook::StepZone(const int i, const int b)
  {
   double   hi = m_data.High(b);
   double   lo = m_data.Low(b);
   double   cl = m_data.Close(b);
   datetime bt = m_data.Time(b);
   bool     bull = m_zones[i].bullish;

   //--- closed fully beyond the far edge -> the level failed
   bool dead = bull ? (cl < m_zones[i].bottom) : (cl > m_zones[i].top);
   if(dead)
     {
      m_zones[i].state       = TTZS_INVALID;
      m_zones[i].invalidTime = bt;
      //--- a failed zone that price closed decisively through flips polarity:
      //--- the trapped side must defend it from the other direction
      return(m_cfg.useBreakers);
     }

   bool inside = (hi >= m_zones[i].bottom && lo <= m_zones[i].top);
   if(inside && m_zones[i].state == TTZS_LIVE)
     {
      m_zones[i].state     = TTZS_TOUCHED;
      m_zones[i].touchTime = bt;
     }

   //--- closed back out on the ORIGIN side = the zone did its job
   if(m_zones[i].state == TTZS_TOUCHED)
     {
      bool back = bull ? (cl > m_zones[i].top) : (cl < m_zones[i].bottom);
      if(back)
        {
         m_zones[i].state        = TTZS_MITIGATED;
         m_zones[i].mitigateTime = bt;
        }
     }
   return(false);
  }
//+------------------------------------------------------------------+
void CZoneBook::PhaseUpdateStates(const int b)
  {
   datetime bt = m_data.Time(b);
   double   brkTop[TTLS_MAX_BREAKERS_PER_BAR];
   double   brkBot[TTLS_MAX_BREAKERS_PER_BAR];
   bool     brkBull[TTLS_MAX_BREAKERS_PER_BAR];
   int      brkN = 0;

   int n = m_count;
   for(int i = 0; i < n; i++)
     {
      if(m_zones[i].state == TTZS_INVALID)
         continue;
      if(m_zones[i].eventTime >= bt)             // built by this bar or later
         continue;
      if(!StepZone(i, b))
         continue;
      if(brkN < TTLS_MAX_BREAKERS_PER_BAR)
        {
         brkTop[brkN]  = m_zones[i].top;
         brkBot[brkN]  = m_zones[i].bottom;
         brkBull[brkN] = !m_zones[i].bullish;
         brkN++;
        }
     }

   //--- safe to mutate the array now that the sweep is finished
   for(int j = 0; j < brkN; j++)
      AddZone(brkTop[j], brkBot[j], bt, bt, TTZ_BREAKER, brkBull[j], false);
  }
//+------------------------------------------------------------------+
int CZoneBook::LiveCount(const bool bullish, const datetime asOf)
  {
   int n = 0;
   for(int i = 0; i < m_count; i++)
     {
      if(m_zones[i].bullish != bullish || m_zones[i].state == TTZS_INVALID)
         continue;
      if(m_zones[i].eventTime > asOf)
         continue;
      if(m_zones[i].invalidTime != 0 && m_zones[i].invalidTime <= asOf)
         continue;
      n++;
     }
   return(n);
  }
//+------------------------------------------------------------------+
//| Zones are ranked outward from the current price. Only the nearest |
//| MaxActiveZones per direction are considered live, which stops a   |
//| stale zone 300 points away from arming a scalp.                   |
//+------------------------------------------------------------------+
bool CZoneBook::NearestLive(const int rank, const double price, const bool bullish,
                            const datetime asOf, TTZone &out)
  {
   if(rank < 0 || rank >= m_cfg.maxActive)
      return(false);

   int    idx[TTLS_MAX_ZONES];
   double dist[TTLS_MAX_ZONES];
   int    n = 0;

   for(int i = 0; i < m_count && n < TTLS_MAX_ZONES; i++)
     {
      if(m_zones[i].bullish != bullish || m_zones[i].state == TTZS_INVALID)
         continue;
      if(m_zones[i].eventTime > asOf)            // not known yet at that moment
         continue;
      //--- distance from price to the near edge of the box (0 when price is inside)
      double d = 0.0;
      if(price > m_zones[i].top)
         d = price - m_zones[i].top;
      else
         if(price < m_zones[i].bottom)
            d = m_zones[i].bottom - price;
      idx[n]  = i;
      dist[n] = d;
      n++;
     }
   if(rank >= n)
      return(false);

   //--- partial selection sort: only rank+1 passes are needed. Ties break on
   //--- zone id so the ordering is reproducible bar for bar.
   for(int r = 0; r <= rank; r++)
     {
      int best = r;
      for(int j = r + 1; j < n; j++)
        {
         bool better = (dist[j] < dist[best]) ||
                       (dist[j] == dist[best] && m_zones[idx[j]].id < m_zones[idx[best]].id);
         if(better)
            best = j;
        }
      if(best != r)
        {
         int    ti = idx[r];  idx[r]  = idx[best];  idx[best] = ti;
         double td = dist[r]; dist[r] = dist[best]; dist[best] = td;
        }
     }
   out = m_zones[idx[rank]];
   return(true);
  }

#endif // __TT_ZONES_MQH__
//+------------------------------------------------------------------+
