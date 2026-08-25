# TT_LiquidityScalper

A non-repainting, multi-timeframe **Smart Money Concepts** chart indicator for MetaTrader 5.
Built for XAUUSD scalping but entirely symbol-agnostic — nothing in the logic knows or cares
what the instrument is called.

The model it implements:

```
HTF/MTF bias alignment  ->  POI mitigation  ->  liquidity sweep  ->  entry trigger
                                                                 ->  target at the next liquidity pool
```

It draws the full markup (MS/BOS, zones, liquidity, strong/weak levels, entry/SL/TP boxes),
prints the levels, and exposes everything through indicator buffers so an EA can consume it
with `iCustom`.

---

## Repository contents

| Path | Purpose |
|---|---|
| `TT_LiquidityScalper.mq5` | `OnCalculate`, inputs, buffers, orchestration, entry state machine |
| `Include/TT/Structure.mqh` | Swing detection, MS/BOS engine, strong/weak levels, timeframe data cache |
| `Include/TT/Liquidity.mqh` | Liquidity pool mapping and sweep detection |
| `Include/TT/Zones.mqh` | Demand/supply, order blocks, FVG, breakers, mitigation life cycle |
| `Include/TT/Draw.mqh` | Every `ObjectCreate` in the package, single `TTLS_` prefix |
| `Include/TT/Risk.mqh` | Lot sizing, RR filter, session/spread/daily guardrails, quality score |
| `DowTheorySwingStructure.mq4` | Unrelated legacy MT4 indicator that predates this package |

## Install

1. In MetaTrader 5: **File → Open Data Folder**.
2. Copy `TT_LiquidityScalper.mq5` into `MQL5/Indicators/`.
3. Copy the whole `Include/TT/` folder into `MQL5/Include/` so you end up with
   `MQL5/Include/TT/Structure.mqh` and its four siblings.
4. Open `TT_LiquidityScalper.mq5` in MetaEditor and press **F7**.

The includes are angle-bracket (`#include <TT/Structure.mqh>`), so the headers must live under
`MQL5/Include/TT/` — dropping everything into one folder will not compile.

Requires build 4000 or later. No DLLs, no `#import`, no external dependencies.

---

## Strategy pipeline

### Bias gate
Structure is computed independently on `BiasTF` and `SetupTF`. A setup may only arm when both
agree and neither is neutral. The alignment state is published on buffer 5.

### Structure engine
A swing high at bar *i* must be **strictly** higher than `SwingLeftBars` highs to its left and
`SwingRightBars` highs to its right; swing lows mirror this. A swing is confirmed only once those
right-hand bars have **closed**, which is the root of the non-repainting guarantee.

* **MS (CHoCH)** — a break against the prevailing trend. Flips the trend.
* **BOS** — a break in the direction of the prevailing trend. Continuation.

Breaks are close-based by default; `UseWickBreaks` switches to high/low.

After a bullish break the **Strong Low** is the protected origin of the breaking leg and the
**Weak High** is the level the market will reach for next. They render as long rays labelled
`1H Strong Low` / `1H Weak High` (the prefix follows `BiasTF`).

### Points of interest
Four independently toggleable types, built on both `BiasTF` and `SetupTF`:

* **Demand / supply** — the last opposing-close candle (or contiguous cluster) before the impulse
  that produced the MS/BOS.
* **Order block** — the same origin, restricted to the single pivot candle.
* **FVG** — three-bar imbalance.
* **Breaker** — a failed zone that price closed decisively through, flipped in polarity.

`ZoneMode` picks how much of the origin becomes the box: `ZONE_PIVOT_CANDLE` uses the pivot
candle's range, `ZONE_FULL_RANGE` absorbs the contiguous base before the impulse. Both exist
because a retracement can miss one and mitigate the other.

Life cycle: **LIVE → TOUCHED → MITIGATED**, or **INVALID** when a bar closes fully beyond the far
edge. Invalidated zones stop generating signals and render greyed. Zones are ranked outward from
current price and only the nearest `MaxActiveZones` per direction are live. Overlapping zones of
the same type and direction merge into the larger box rather than firing twice off one event.

### Liquidity
Every unswept confirmed swing high is buy-side liquidity, every unswept low is sell-side. Swings
within `EqualLevelToleranceATR × ATR(14)` of each other cluster into one pool carrying a hit count
— equal highs/lows are weighted higher in the quality score. Pools render as horizontal segments
with a `$` label (`$3` = a three-swing cluster).

A sell-side pool at price `P` is **swept** when a bar's low goes below `P - SweepBufferPoints`
**and** price closes back above `P` (same bar, or within `SweepCloseBackBars` bars). The sweeping
bar's extreme becomes the protected low. A level price simply closes through is marked **broken**,
not swept — it is drawn dim and loses its `$`.

### Entry state machine

```
IDLE     -> bias aligned                                 -> ARMED
ARMED    -> price trades into a live SetupTF POI         -> AT_POI
         -> chosen POI invalidated                       -> ARMED (roll to next)
AT_POI   -> liquidity swept at/inside that POI           -> SWEPT
         -> a bar closes beyond the POI's far edge       -> IDLE
SWEPT    -> AGGRESSIVE                                   -> SIGNAL on the sweep bar's close
         -> CONSERVATIVE  -> LTF shift -> pullback       -> SIGNAL
         -> sweep extreme violated first                 -> IDLE (failed sweep)
PENDING  -> no pullback within ConservativeExpiryBars    -> MISSED (logged, never chased)
```

The sweep must land inside the mitigated zone or within `SweepProximityPoints` of it. **A sweep in
open space is not a setup.**

### Levels
* **Entry** — aggressive: the close of the sweep (or confirmation) bar. Conservative: the proximal
  edge of the LTF shift zone.
* **Stop** — beyond the swept extreme by `StopBufferPoints` (0 = `0.2 × ATR`), plus the signal
  bar's recorded spread, then widened if needed to satisfy `SYMBOL_TRADE_STOPS_LEVEL`.
* **Target** — per `TargetMode`. TP2 draws as a dashed line at the HTF weak level when it sits
  beyond TP.
* **RR filter** — setups below `MinRR` are discarded.

---

## Inputs

### Timeframes
| Input | Default | Meaning |
|---|---|---|
| `BiasTF` | H1 | Directional filter |
| `SetupTF` | M15 | POIs, liquidity, sweeps, the state machine |
| `EntryTF` | M5 | Conservative trigger |
| `MaxHistoryBars` | 2000 | Bars rebuilt per timeframe (clamped to 200–20000) |

`PERIOD_CURRENT` is **rejected** on these three — accepting it would tie the analysis to whatever
the chart happens to show and break timeframe independence.

### Structure
| Input | Default | Meaning |
|---|---|---|
| `SwingLeftBars` | 3 | Bars required left of a pivot |
| `SwingRightBars` | 3 | Bars required right — this is the confirmation lag |
| `UseWickBreaks` | false | false = close-based breaks, true = high/low |
| `ShowMS` / `ShowBOS` / `ShowStrongWeak` | true | Markup toggles |

### Zones
| Input | Default | Meaning |
|---|---|---|
| `UseDemandSupply` / `UseOrderBlocks` / `UseFVG` / `UseBreakers` | true | Zone types |
| `ZoneMode` | `ZONE_PIVOT_CANDLE` | Pivot candle only, or the full base |
| `MaxActiveZones` | 3 | Live zones per direction |
| `ExtendZonesBars` | 60 | Box extension, in bars of the zone's own timeframe |

### Liquidity
| Input | Default | Meaning |
|---|---|---|
| `ShowLiquidity` | true | Draw pools |
| `EqualLevelToleranceATR` | 0.15 | Equal-level clustering, as a fraction of ATR(14) |
| `SweepBufferPoints` | 0 | Penetration required (0 = auto, `0.10 × ATR`) |
| `SweepCloseBackBars` | 1 | Bars allowed for the close-back (0 = same bar only) |
| `SweepProximityPoints` | 0 | Sweep-to-zone allowance (0 = auto, `0.25 × ATR`) |
| `KeepSweptLiquidity` | true | Keep swept pools on the chart, dimmed |

### Entry
| Input | Default | Meaning |
|---|---|---|
| `EntryMode` | `AGGRESSIVE` | `AGGRESSIVE`, `CONSERVATIVE`, `BOTH` |
| `RequireConfirmationCandle` | false | Aggressive waits for one candle closing in-direction |
| `ConservativeExpiryBars` | 12 | EntryTF bars before a pending setup is marked MISSED |
| `TargetMode` | `TARGET_NEAREST_INTERNAL` | Also `TARGET_HTF_WEAK`, `TARGET_NEXT_OPPOSING_POI` |
| `MinRR` | 1.5 | Reject anything below this |
| `StopBufferPoints` | 0 | 0 = auto, `0.2 × ATR` |

### Filters
| Input | Default | Meaning |
|---|---|---|
| `UseSessionFilter` | false | Restrict signals to a server-time window |
| `SessionStartHour` / `SessionEndHour` | 7 / 20 | Server time; a window that wraps midnight works |
| `MaxSignalsPerDay` | 3 | 0 = unlimited |
| `MinBarsBetweenSignals` | 5 | Measured in SetupTF bars, both entry modes |
| `AvoidHighImpactMinutes` | 0 | 0 = blackout list off |
| `BlackoutTimes` | `12:30,14:00` | `HH:MM` list, server time, ± the minutes above |
| `MaxSpreadPoints` | 0 | 0 = no spread gate |

**Server time is not your time.** Most brokers run GMT+2/+3. Check with
`TimeToString(TimeCurrent())` in the terminal and offset the session and blackout hours yourself —
the indicator does no timezone conversion.

### Risk
| Input | Default | Meaning |
|---|---|---|
| `AccountRiskPercent` | 0.5 | Sizes the displayed lot |
| `ShowLotSize` | true | Compute and print the lot size |
| `MaxDailyLossPercent` | 0 | 0 = off. Greys the panel and mutes alerts once breached |

`MaxDailyLossPercent` is a **display and alert guardrail only**. The indicator never trades and
never blocks a signal on account state.

### Alerts
| Input | Default | Meaning |
|---|---|---|
| `AlertPopup` / `AlertPush` / `AlertEmail` | true / false / false | Channels |
| `AlertOncePerSetup` | true | true = one alert per fired signal. false = also alert on the sweep, before the trigger resolves |

### Display
`PanelCorner`, `ShowInfoPanel`, `FontSize`, and colours for bull, bear, demand, supply,
invalidated, liquidity, strong/weak and structure.

---

## iCustom contract

| # | Name | Type | Contents |
|---|---|---|---|
| 0 | `BuySignal` | arrow | Entry price on the signal bar, else `EMPTY_VALUE` |
| 1 | `SellSignal` | arrow | Entry price on the signal bar, else `EMPTY_VALUE` |
| 2 | `EntryPrice` | data | Entry level on the signal bar, else `EMPTY_VALUE` |
| 3 | `StopLoss` | data | SL level on the signal bar, else `EMPTY_VALUE` |
| 4 | `TakeProfit` | data | TP level on the signal bar, else `EMPTY_VALUE` |
| 5 | `BiasState` | data | `+1` bull aligned, `-1` bear aligned, `0` misaligned |
| 6 | `SetupState` | data | State-machine code (below) |
| 7 | `SignalQuality` | data | `0–100` on the signal bar, else `EMPTY_VALUE` |

`SetupState` codes: `0` IDLE, `1` ARMED, `2` AT_POI, `3` SWEPT, `4` PENDING, `5` SIGNAL,
`6` MISSED. The bias gate means only one direction is ever live, so a single buffer is
unambiguous — read buffer 5 for the direction and buffer 6 for the state.

Buffers 5 and 6 carry a value on **every** bar, reflecting what was known at that bar's close.
Buffers 0–4 and 7 only carry a value on signal bars.

```mql5
int h = iCustom(_Symbol, PERIOD_M15, "TT_LiquidityScalper");
double buy[], sl[], tp[], q[];
ArraySetAsSeries(buy, true);  ArraySetAsSeries(sl, true);
ArraySetAsSeries(tp, true);   ArraySetAsSeries(q, true);

// bar 1 = the last CLOSED bar; never act on bar 0
if(CopyBuffer(h, 0, 1, 1, buy) == 1 && buy[0] != EMPTY_VALUE)
  {
   CopyBuffer(h, 3, 1, 1, sl);
   CopyBuffer(h, 4, 1, 1, tp);
   CopyBuffer(h, 7, 1, 1, q);
   if(q[0] >= 70)
      /* open a long at buy[0] with sl[0] / tp[0] */;
  }
```

Arrows are placed on the bar that **produced** the signal. That bar is closed by the time the
value appears, so the trade is actionable from the next bar's open.

### Signal quality

| Component | Points |
|---|---|
| HTF + MTF aligned | 30 |
| Sweep landed **inside** the zone, not merely near it | 20 |
| Zone sits at an untested extreme | 15 |
| Equal highs/lows pool rather than a single swing | 15 |
| RR ≥ 2.0 | 10 |
| Inside the preferred session | 10 |

The session component is scored even when `UseSessionFilter` is off. Grade setups with this
number rather than taking every arrow.

---

## Visual legend

| Element | Appearance |
|---|---|
| MS / BOS | Thin grey line from the broken swing to the breaking bar, label centred |
| Zones | Semi-transparent boxes, tagged `DZ` / `SZ` / `OB` / `FVG` / `BRK` + timeframe; grey when invalidated |
| Liquidity | Horizontal segment with `$` (or `$n` for a cluster) at the right end; dotted when swept, dim and unlabelled when broken |
| Strong / Weak | Long rays in muted red with right-aligned labels |
| Signal | Arrow, red risk box to SL, green reward box to TP, dashed TP2, and a line reading `AGG/CON · RR · quality · lots` |
| Panel | Symbol, both biases, per-direction state, zone counts, unswept liquidity, signals today, last result |

MS/BOS and zone markup is drawn for `BiasTF` and `SetupTF`. `EntryTF` structure drives the
conservative trigger but is deliberately not drawn — it would bury the chart.

---

## Non-repainting guarantees

1. **Closed bars only.** Index 0 is never read for logic anywhere in the package.
2. **Confirmation lag is real.** A swing needs `SwingRightBars` closed bars to its right; a signal
   printed on bar N cannot move, vanish or flip afterwards.
3. **Forward-only state.** The state machine advances and never rewinds. On `prev_calculated == 0`
   history is rebuilt from the oldest bar towards the newest, reproducing the same signal set.
4. **Bounded cross-timeframe queries.** When the SetupTF loop asks the EntryTF engine a question it
   bounds the answer by the *close* of the relevant bar, so a faster timeframe that has already
   been updated to the present cannot leak future information into a historical decision.
5. **Historical values, not live ones.** Bias, weak levels and spread are all read as they stood at
   the bar in question — via time-indexed history for the first two, and `MqlRates.spread` for the
   third. Reading the live ask/bid would make a reload disagree with the original run.
6. **Fixed rebuild depth.** `MaxHistoryBars` anchors the rebuild so that downloading more history
   does not shift the oldest signals.
7. **All MTF reads are checked.** If any timeframe or its ATR is not ready, `OnCalculate` returns
   `0` and MT5 retries — partial data is never carried forward.

### Documented design decisions

Where the model admits more than one reading, this is what was chosen and why.

* **Same-bar precedence.** Within one closed bar: zone mitigation → liquidity sweep → structure
  break → signal. The wick takes the stops before the body closes through structure. A setup can
  therefore advance `IDLE → ARMED → AT_POI → SWEPT → SIGNAL` on a single bar close.
* **One structure event per bar.** When a single bar breaks both sides, the break that *continues*
  the prevailing trend is taken; from neutral, the bullish one.
* **AT_POI on TOUCHED.** Price trading into the zone is enough to arm the trigger. Requiring full
  mitigation (a close back outside) would miss every setup where the touch and the sweep share a
  bar — the normal case on a scalping timeframe.
* **Strong level = the lowest confirmed swing low inside the breaking leg** (mirrored for bearish),
  falling back to the most recent confirmed low, then to the breaking bar's own extreme.
* **The LTF shift accepts MS or BOS.** If the entry timeframe already trended the trade's way an MS
  would never print and conservative mode would silently never trigger.
* **`ConservativeExpiryBars` counts EntryTF bars**, since the pullback is an LTF event.
* **`MinBarsBetweenSignals` always counts SetupTF bars**, so the throttle means the same thing in
  both entry modes.
* **Session and blackout filters key on the signal bar's open time** — the candle's own identity.
* **Spread is always folded into the stop buffer**, and `MaxSpreadPoints` suppresses the signal
  outright above the threshold, using the spread recorded on the sweep bar.
* **No target pool, no signal.** If no unswept opposing liquidity exists beyond entry, the setup is
  discarded rather than given an invented target.
* **`EntryMode = BOTH`** runs both paths; whichever triggers first wins. With
  `RequireConfirmationCandle = false` the aggressive path almost always wins, which is intended.
* **The aggressive confirmation candle expires after 5 bars** rather than carrying a stale setup.
* **A filtered-out trigger consumes the setup.** It does not stay armed waiting for a second chance.
* **Lot size uses the current account balance**, so it is advisory and not part of a signal's
  identity — the levels and times are.

### Edge cases handled explicitly

* **Gold pricing.** Every distance and money calculation derives from `SYMBOL_POINT`,
  `SYMBOL_TRADE_TICK_VALUE` and `SYMBOL_TRADE_TICK_SIZE`. 2-digit and 3-digit gold feeds behave
  identically; no pip value is hardcoded anywhere.
* **Symbol suffixes.** `XAUUSD.m`, `XAUUSD.raw`, `GOLD` — the symbol name is never string-matched.
* **Weekend and session gaps.** A sweep requires the bar to both penetrate the level *and* reach it
  from the other side. A gap that jumps a level without trading through it is a break, not a sweep.
* **Rollover spread.** Folded into the stop; `MaxSpreadPoints` suppresses signals above threshold.
* **Zone overlap.** Nested or overlapping zones of the same type and direction merge into the
  larger box.
* **Chart timeframe independence.** `Period()` is used only for display scaling (signal box width),
  never for logic.

---

## Acceptance tests

A manual checklist. Run it after any change to the engines.

1. **Timeframe independence.** Load on XAUUSD M5 and M15 with identical inputs. The signal times
   and prices must be identical on both. (Arrow *bar positions* differ — an M15 signal lands on
   whichever M5 bar was live when that M15 bar closed — but the levels and times must match.)
2. **Reload stability.** Screenshot the chart, restart MT5, reload the indicator. The historical
   signal set must be identical. Keep `MaxHistoryBars` below the chart's available history.
3. **Bias disagreement.** Force `BiasTF` and `SetupTF` into disagreement over a known date. There
   must be zero signals in that window, and buffer 5 must read `0` throughout.
4. **Mitigation without a sweep.** Find a POI that price mitigates with no liquidity sweep. No
   signal may fire and buffer 6 must sit at `2` (AT_POI).
5. **Sweep in open space.** Find a sweep with no zone mitigation. No signal may fire.
6. **Visual mode.** Run the Strategy Tester in visual mode across one trending week and one ranging
   week. Arrows must only appear on closed bars and must never shift once printed.
7. **Throttling across midnight.** Set `MaxSignalsPerDay = 1` and `MinBarsBetweenSignals = 5` and
   confirm both throttle correctly over a 23:00–01:00 window: the daily counter resets at the
   server date change while the spacing rule keeps counting through it.

---

## Tuning notes

**Start here for XAUUSD M15 scalping.** Defaults are deliberately conservative:
`AGGRESSIVE` entry, `MinRR 1.5`, three signals a day.

* **Too few signals?** Lower `SwingLeftBars`/`SwingRightBars` to 2 — more swings means more
  liquidity pools and more structure events. Raise `MaxActiveZones` to 4–5. Try
  `ZoneMode = ZONE_FULL_RANGE`, which produces wider boxes that price is more likely to tag.
* **Too many low-quality signals?** Raise `MinRR` to 2.0, turn on `RequireConfirmationCandle`, and
  filter on buffer 7 — a score of 70+ requires alignment, a sweep inside the zone, and at least two
  of the remaining components.
* **Sweeps firing on noise.** Raise `SweepBufferPoints` above the auto value (start around
  `0.20 × ATR` expressed in points for your feed). On gold at 2-digit pricing that is typically
  60–120 points.
* **Sweeps never firing.** `SweepCloseBackBars = 0` demands the close-back on the sweeping bar
  itself, which is strict on fast feeds — 1 or 2 is more realistic.
* **Stops getting clipped.** Raise `StopBufferPoints`, or leave it at 0 and let ATR scale it. The
  bar's recorded spread is already added on top.
* **Conservative mode never triggers.** It needs an EntryTF structure shift *and* a pullback within
  `ConservativeExpiryBars`. On M5 with a 12-bar expiry that is one hour. Widen the expiry or switch
  to `BOTH`.
* **News.** Set `AvoidHighImpactMinutes` to 30 and put your own release times in `BlackoutTimes`,
  in **server** time. There is no news feed — this is a static list by design, so history replays
  identically.

### Performance

Engines only reprocess bars that have closed since the last call, and the markup is only redrawn
when a bar actually closed. A full rebuild (`prev_calculated == 0`) walks `MaxHistoryBars` bars on
each of the three timeframes; on a slow machine, dropping it to 1000 roughly halves load time at
the cost of shallower history.

### Known limitations

* Conservative-mode reconstruction of *old* history is bounded by the EntryTF container caps and by
  `MaxHistoryBars` on `EntryTF`. With the defaults there is ample headroom; if you raise
  `MaxHistoryBars` well past 2000 the oldest conservative setups may be clipped. Aggressive mode is
  unaffected.
* Trade outcomes on the panel are resolved from SetupTF bars. A bar that touches both SL and TP is
  scored as a loss, since intrabar order cannot be recovered from bar data.
* On a chart timeframe coarser than `SetupTF`, several signals can map onto one chart bar; the
  buffers keep the last one. Read the indicator on `SetupTF` or finer.
