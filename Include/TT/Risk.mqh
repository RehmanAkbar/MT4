//+------------------------------------------------------------------+
//|                                                          Risk.mqh |
//|   TT_LiquidityScalper - position sizing, RR filter, session and    |
//|   daily guardrails, signal quality scoring                         |
//|                                                                   |
//|  Indexing: SERIES (index 0 = forming bar, 1 = last closed bar).    |
//|  See the convention block at the top of Structure.mqh.             |
//|                                                                   |
//|  This module never places, modifies or closes an order. It sizes   |
//|  and grades what the indicator draws, nothing more.                |
//|                                                                   |
//|  All distance and money maths is derived from SymbolInfoDouble.    |
//|  Nothing here knows or cares what the symbol is called, so a       |
//|  2-digit XAUUSD, a 3-digit XAUUSD.raw and a GOLD alias all size    |
//|  identically.                                                      |
//+------------------------------------------------------------------+
#ifndef __TT_RISK_MQH__
#define __TT_RISK_MQH__

#include <TT/Structure.mqh>

//--- auto stop buffer when StopBufferPoints is left at 0
#define TTLS_AUTO_STOP_ATR       0.20
//--- signal quality weights (they add up to 100)
#define TTQ_ALIGNED              30
#define TTQ_SWEEP_INSIDE         20
#define TTQ_UNTESTED_EXTREME     15
#define TTQ_EQUAL_LEVELS         15
#define TTQ_RR2                  10
#define TTQ_SESSION              10
//--- RR at or above which the quality bonus is granted
#define TTQ_RR2_THRESHOLD        2.0

//+------------------------------------------------------------------+
//| Time-based gating. Everything here is evaluated against the       |
//| SIGNAL BAR's own time so a history rebuild reaches the same       |
//| verdict the live run did.                                         |
//+------------------------------------------------------------------+
//--- Throttling (signals per day, bars between signals) is NOT here: it lives
//--- in CSignalGovernor, which owns the counters that enforce it. Mirroring
//--- those inputs into this struct as well left two copies where only one was
//--- ever read.
struct TTFilterCfg
  {
   bool              useSession;
   int               sessionStartHour;    // server time
   int               sessionEndHour;      // server time, exclusive
   int               avoidMinutes;        // 0 = blackout list disabled
   string            blackoutCsv;         // "HH:MM,HH:MM,..." server time
  };

//+------------------------------------------------------------------+
double TTPointSize(const string sym)
  {
   double p = SymbolInfoDouble(sym, SYMBOL_POINT);
   return(p > 0.0 ? p : _Point);
  }
//+------------------------------------------------------------------+
//| Distance placed beyond the swept extreme before the stop sits.    |
//| Scaling it with ATR is what keeps one setting valid across a      |
//| quiet Asian range and a CPI candle.                               |
//+------------------------------------------------------------------+
double TTStopBuffer(const string sym, const double atr, const double bufPoints)
  {
   double pt = TTPointSize(sym);
   if(bufPoints > 0.0)
      return(bufPoints * pt);
   double v   = atr * TTLS_AUTO_STOP_ATR;
   double flr = TTLS_MIN_TOL_POINTS * pt;
   return(v > flr ? v : flr);
  }
//+------------------------------------------------------------------+
double TTSpreadPoints(const string sym)
  {
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double pt  = TTPointSize(sym);
   if(ask <= 0.0 || bid <= 0.0 || pt <= 0.0)
      return(0.0);
   return((ask - bid) / pt);
  }
//+------------------------------------------------------------------+
//| Rounds a volume onto the broker's lot grid and clamps it.         |
//+------------------------------------------------------------------+
double TTNormalizeVolume(const string sym, const double lots)
  {
   double vmin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(vstep <= 0.0)
      vstep = 0.01;
   if(vmin <= 0.0)
      vmin = vstep;
   double v = MathFloor(lots / vstep) * vstep;
   if(v < vmin)
      v = vmin;
   if(vmax > 0.0 && v > vmax)
      v = vmax;
   //--- re-normalise to the step's own precision to avoid 0.30000000000000004
   int digits = 0;
   double s = vstep;
   while(s < 1.0 && digits < 8)
     {
      s *= 10.0;
      digits++;
     }
   return(NormalizeDouble(v, digits));
  }
//+------------------------------------------------------------------+
//| Lot size for a fixed fractional risk.                             |
//|                                                                   |
//| Money per lot per unit of price = TICK_VALUE / TICK_SIZE. Using   |
//| that ratio rather than a hardcoded pip value is what makes this   |
//| correct on gold, indices and FX alike, whatever the digits.       |
//|                                                                   |
//| Returns 0 when the broker has not published usable contract data, |
//| AND when the requested risk does not buy even one minimum lot.    |
//| Rounding that case UP to VOLUME_MIN is what a naive sizer does,   |
//| and it silently turns 0.5% risk into 2% on a small account - the  |
//| trader reads a lot size off the panel with no hint that it broke  |
//| the risk budget. 0.00 lots says "this setup does not fit", which  |
//| is the honest answer.                                             |
//+------------------------------------------------------------------+
double TTLotSize(const string sym, const double riskPercent, const double slDistance)
  {
   if(riskPercent <= 0.0 || slDistance <= 0.0)
      return(0.0);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return(0.0);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
      return(0.0);
   double riskMoney   = balance * riskPercent / 100.0;
   double moneyPerLot = (slDistance / tickSize) * tickValue;
   if(moneyPerLot <= 0.0)
      return(0.0);

   double raw  = riskMoney / moneyPerLot;
   double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   if(vmin > 0.0 && raw < vmin)
      return(0.0);                               // one min lot already over-risks
   return(TTNormalizeVolume(sym, raw));
  }
//+------------------------------------------------------------------+
//| Pushes the stop out to the broker's minimum stop distance when a  |
//| structurally correct stop would be rejected. Widening the stop    |
//| (never tightening it) keeps the level valid; the RR filter        |
//| downstream then decides whether the setup still pays.             |
//+------------------------------------------------------------------+
void TTEnforceStopsLevel(const string sym, const double entry, const bool isBuy,
                         double &sl, double &tp)
  {
   long stopsLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze     = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
   long lvl        = MathMax(stopsLevel, freeze);
   if(lvl <= 0)
      return;
   double minDist = (double)lvl * TTPointSize(sym);
   int    digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   if(isBuy)
     {
      if(entry - sl < minDist)
         sl = NormalizeDouble(entry - minDist, digits);
      if(tp - entry < minDist)
         tp = NormalizeDouble(entry + minDist, digits);
     }
   else
     {
      if(sl - entry < minDist)
         sl = NormalizeDouble(entry + minDist, digits);
      if(entry - tp < minDist)
         tp = NormalizeDouble(entry - minDist, digits);
     }
  }
//+------------------------------------------------------------------+
double TTRewardRisk(const double entry, const double sl, const double tp)
  {
   double risk = MathAbs(entry - sl);
   if(risk <= 0.0)
      return(0.0);
   return(MathAbs(tp - entry) / risk);
  }
//+------------------------------------------------------------------+
//| Server-time session window. start == end means "always on".       |
//| A window that wraps midnight (e.g. 22 -> 6) is supported.         |
//+------------------------------------------------------------------+
bool TTSessionOk(const datetime t, const TTFilterCfg &f)
  {
   if(!f.useSession)
      return(true);
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int s = f.sessionStartHour;
   int e = f.sessionEndHour;
   if(s == e)
      return(true);
   if(s < e)
      return(dt.hour >= s && dt.hour < e);
   return(dt.hour >= s || dt.hour < e);          // wraps midnight
  }
//+------------------------------------------------------------------+
//| Minute-of-day distance, shortest way round the clock.             |
//+------------------------------------------------------------------+
int TTClockDistance(const int a, const int b)
  {
   int d = (int)MathAbs(a - b);
   if(d > 720)
      d = 1440 - d;
   return(d);
  }
//+------------------------------------------------------------------+
//| Static blackout windows around known release times. Deliberately  |
//| a fixed list rather than a news feed: no external dependency, and |
//| the same list produces the same history on every reload.          |
//+------------------------------------------------------------------+
bool TTBlackoutOk(const datetime t, const TTFilterCfg &f)
  {
   if(f.avoidMinutes <= 0 || StringLen(f.blackoutCsv) == 0)
      return(true);

   MqlDateTime dt;
   TimeToStruct(t, dt);
   int nowMin = dt.hour * 60 + dt.min;

   string parts[];
   int n = StringSplit(f.blackoutCsv, StringGetCharacter(",", 0), parts);
   for(int i = 0; i < n; i++)
     {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(StringLen(p) == 0)
         continue;
      string hm[];
      if(StringSplit(p, StringGetCharacter(":", 0), hm) != 2)
         continue;
      int hh = (int)StringToInteger(hm[0]);
      int mm = (int)StringToInteger(hm[1]);
      if(hh < 0 || hh > 23 || mm < 0 || mm > 59)
         continue;
      if(TTClockDistance(nowMin, hh * 60 + mm) <= f.avoidMinutes)
         return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
//| Additive quality score, 0-100. Every component is a property the  |
//| setup either has or has not, so the number is comparable across   |
//| symbols and can be used to grade rather than to filter blindly.   |
//+------------------------------------------------------------------+
int TTQualityScore(const bool aligned, const bool sweepInside, const bool untestedExtreme,
                   const bool equalLevels, const double rr, const bool inSession)
  {
   int q = 0;
   if(aligned)                 q += TTQ_ALIGNED;
   if(sweepInside)             q += TTQ_SWEEP_INSIDE;
   if(untestedExtreme)         q += TTQ_UNTESTED_EXTREME;
   if(equalLevels)             q += TTQ_EQUAL_LEVELS;
   if(rr >= TTQ_RR2_THRESHOLD) q += TTQ_RR2;
   if(inSession)               q += TTQ_SESSION;
   return(q);
  }
//+------------------------------------------------------------------+
//| Realised P/L booked since midnight server time. Used only to grey |
//| the panel out and mute alerts - the indicator never trades.       |
//+------------------------------------------------------------------+
double TTDailyRealizedPL(void)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime dayStart = StructToTime(dt);
   if(!HistorySelect(dayStart, TimeCurrent() + 1))
      return(0.0);

   double pl = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
         continue;                                // skip the opening half of a round trip
      pl += HistoryDealGetDouble(ticket, DEAL_PROFIT)
          + HistoryDealGetDouble(ticket, DEAL_SWAP)
          + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
     }
   return(pl);
  }
//+------------------------------------------------------------------+
bool TTDailyLossBreached(const double maxPct, double &lossPct)
  {
   lossPct = 0.0;
   if(maxPct <= 0.0)
      return(false);
   double pl = TTDailyRealizedPL();
   if(pl >= 0.0)
      return(false);
   //--- balance before today's damage is the honest denominator
   double startBalance = AccountInfoDouble(ACCOUNT_BALANCE) - pl;
   if(startBalance <= 0.0)
      return(false);
   lossPct = (-pl) / startBalance * 100.0;
   return(lossPct >= maxPct);
  }

//+------------------------------------------------------------------+
//| CSignalGovernor                                                   |
//|                                                                   |
//| Throttles how often a setup may fire. Both limits are evaluated   |
//| against the SIGNAL BAR's time, not the wall clock, so a history   |
//| rebuild reproduces exactly the same throttling decisions.         |
//|                                                                   |
//| The daily counter keys on (year, day-of-year), and the spacing    |
//| rule works on absolute seconds - so a signal at 23:58 and one at  |
//| 00:04 are correctly six minutes apart AND on different days.      |
//+------------------------------------------------------------------+
class CSignalGovernor
  {
private:
   int               m_maxPerDay;
   int               m_minBars;
   datetime          m_lastTime;
   int               m_todayCount;
   int               m_dayKey;
   int               DayKey(const datetime t);
public:
                     CSignalGovernor(void) { m_maxPerDay = 0; m_minBars = 0; Reset(); }
   void              Init(const int maxPerDay, const int minBars)
     {
      m_maxPerDay = maxPerDay;
      m_minBars   = minBars;
      Reset();
     }
   void              Reset(void) { m_lastTime = 0; m_todayCount = 0; m_dayKey = -1; }
   bool              Allow(const datetime t, const int tfSeconds);
   void              Register(const datetime t);
   int               CountOn(const datetime t) { return(DayKey(t) == m_dayKey ? m_todayCount : 0); }
   datetime          LastTime(void) { return m_lastTime; }
  };

//+------------------------------------------------------------------+
int CSignalGovernor::DayKey(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return(dt.year * 1000 + dt.day_of_year);
  }
//+------------------------------------------------------------------+
bool CSignalGovernor::Allow(const datetime t, const int tfSeconds)
  {
   int cnt = (DayKey(t) == m_dayKey) ? m_todayCount : 0;
   if(m_maxPerDay > 0 && cnt >= m_maxPerDay)
      return(false);
   if(m_minBars > 0 && m_lastTime > 0 && tfSeconds > 0)
     {
      long gap = (long)(t - m_lastTime) / (long)tfSeconds;
      if(gap < (long)m_minBars)
         return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
void CSignalGovernor::Register(const datetime t)
  {
   int k = DayKey(t);
   if(k != m_dayKey)
     {
      m_dayKey     = k;
      m_todayCount = 0;
     }
   m_todayCount++;
   m_lastTime = t;
  }

#endif // __TT_RISK_MQH__
//+------------------------------------------------------------------+
