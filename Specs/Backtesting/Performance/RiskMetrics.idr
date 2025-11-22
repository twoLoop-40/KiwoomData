||| Risk Metrics - Requires initial capital for accurate calculations
|||
||| Time-weighted metrics:
||| - Max Drawdown (based on equity curve)
||| - Sharpe Ratio (using daily returns, annualized)
||| - CAGR (Compound Annual Growth Rate)
|||
||| CRITICAL: All functions require initialCapital parameter

module Backtesting.Performance.RiskMetrics

import Backtesting.Core
import Backtesting.Performance.BasicMetrics
import Data.List

%default total

--------------------------------------------------------------------------------
-- Equity Curve
--------------------------------------------------------------------------------

||| Portfolio equity curve (absolute equity over time)
|||
||| @initialCapital Starting capital
public export
equityCurve : (initialCapital : Double) -> List Trade -> List (Timestamp, Double)
equityCurve initialCapital trades =
  let sortedTrades = sortBy (\t1, t2 => compare t1.exitTime t2.exitTime) trades
      scanEquity : List Trade -> Double -> List (Timestamp, Double)
      scanEquity [] equity = []
      scanEquity (t :: ts) equity =
        let newEquity = equity + tradePnL t
        in (t.exitTime, newEquity) :: scanEquity ts newEquity
  in (0, initialCapital) :: scanEquity sortedTrades initialCapital

--------------------------------------------------------------------------------
-- Drawdown Analysis
--------------------------------------------------------------------------------

||| Calculate maximum drawdown (largest peak-to-trough decline)
|||
||| MDD = max((Peak - Trough) / Peak)
||| Returns value 0.0 ~ 1.0 (e.g., 0.25 = 25% drawdown)
|||
||| @initialCapital Required for correct percentage calculation
public export
maxDrawdown : (initialCapital : Double) -> List Trade -> Double
maxDrawdown initialCapital trades =
  let equity = map snd (equityCurve initialCapital trades)
      calcDrawdown : List Double -> Double -> Double -> Double
      calcDrawdown [] _ maxDD = maxDD
      calcDrawdown (e :: es) peak maxDD =
        let newPeak = max peak e
            dd = if newPeak > 0.0 then (newPeak - e) / newPeak else 0.0
            newMaxDD = max maxDD dd
        in calcDrawdown es newPeak newMaxDD
  in calcDrawdown equity initialCapital 0.0

--------------------------------------------------------------------------------
-- Total Return
--------------------------------------------------------------------------------

||| Calculate total return percentage
|||
||| Total Return % = (Total PnL / Initial Capital) × 100
|||
||| @initialCapital Starting capital
public export
totalReturnPct : (initialCapital : Double) -> List Trade -> Double
totalReturnPct initialCapital trades =
  if initialCapital <= 0.0
    then 0.0
    else (totalPnL trades / initialCapital) * 100.0

--------------------------------------------------------------------------------
-- CAGR (Compound Annual Growth Rate)
--------------------------------------------------------------------------------

||| Calculate CAGR (Compound Annual Growth Rate)
|||
||| CAGR = (Final Equity / Initial Capital)^(1 / years) - 1
|||
||| @initialCapital Starting capital
||| @startTime Strategy start timestamp (milliseconds)
||| @endTime Strategy end timestamp (milliseconds)
public export
cagr : (initialCapital : Double) ->
       (startTime : Timestamp) ->
       (endTime : Timestamp) ->
       List Trade ->
       Double
cagr initialCapital startTime endTime trades =
  let finalEquity = initialCapital + totalPnL trades
      msPerYear = 1000.0 * 60.0 * 60.0 * 24.0 * 365.0
      yearsElapsed = cast (endTime - startTime) / msPerYear
  in if yearsElapsed <= 0.0 || initialCapital <= 0.0
       then 0.0
       else pow (finalEquity / initialCapital) (1.0 / yearsElapsed) - 1.0

--------------------------------------------------------------------------------
-- Daily Returns (for Sharpe Ratio)
--------------------------------------------------------------------------------

||| Daily return record
public export
record DailyReturn where
  constructor MkDailyReturn
  date : Timestamp  -- Day start timestamp (milliseconds)
  returnPct : Double  -- Daily return percentage

||| Convert trades to daily returns
|||
||| Algorithm (implemented in Python):
||| 1. Build equity curve from trades
||| 2. Resample to daily frequency
||| 3. Calculate daily_return = (equity_today - equity_yesterday) / equity_yesterday
|||
||| @initialCapital Starting capital
|||
||| Note: This is a specification - actual implementation in Python
public export
tradesToDailyReturns : (initialCapital : Double) ->
                       (startTime : Timestamp) ->
                       (endTime : Timestamp) ->
                       List Trade ->
                       List DailyReturn
tradesToDailyReturns initialCapital startTime endTime trades =
  []  -- Placeholder - implement in Python with pandas resample

--------------------------------------------------------------------------------
-- Sharpe Ratio (using Daily Returns)
--------------------------------------------------------------------------------

||| Calculate annualized Sharpe ratio from daily returns
|||
||| Sharpe = (Avg Daily Return - Daily Risk-Free) / Daily StdDev × sqrt(252)
|||
||| @riskFreeRate ANNUAL risk-free rate (e.g., 0.03 for 3%)
public export
sharpeRatio : (riskFreeRate : Double) -> List DailyReturn -> Double
sharpeRatio riskFreeRate [] = 0.0
sharpeRatio riskFreeRate dailyReturns =
  let rets = map (\r => r.returnPct) dailyReturns
      n = cast (length rets)
      avgDaily = sum rets / n
      dailyRF = riskFreeRate / 252.0  -- Convert annual to daily

      -- Sample standard deviation
      variance = sum (map (\r => (r - avgDaily) * (r - avgDaily)) rets) / (n - 1.0)
      stdDev = sqrt variance
  in if stdDev == 0.0
       then 0.0
       else let dailySharpe = (avgDaily - dailyRF) / stdDev
            in dailySharpe * sqrt 252.0  -- Annualize

--------------------------------------------------------------------------------
-- Python Implementation Guide
--------------------------------------------------------------------------------

{-
Python implementation:

1. Daily returns conversion (pandas):

```python
import pandas as pd
from datetime import datetime

def trades_to_daily_returns(
    trades: list[Trade],
    initial_capital: float,
    start_time: int,
    end_time: int
) -> list[DailyReturn]:
    # Build equity curve
    equity_data = [(start_time, initial_capital)]
    current_equity = initial_capital

    for trade in sorted(trades, key=lambda t: t.exit_time):
        current_equity += trade.pnl()
        equity_data.append((trade.exit_time, current_equity))

    # Convert to DataFrame
    df = pd.DataFrame(equity_data, columns=['timestamp', 'equity'])
    df['date'] = pd.to_datetime(df['timestamp'], unit='ms')
    df = df.set_index('date')

    # Resample to daily (forward fill for non-trading days)
    daily_equity = df['equity'].resample('D').last().ffill()

    # Calculate daily returns
    daily_returns = daily_equity.pct_change() * 100  # Percentage

    # Convert to DailyReturn objects
    result = []
    for date, ret in daily_returns.items():
        if pd.notna(ret):
            result.append(DailyReturn(
                date=int(date.timestamp() * 1000),
                return_pct=ret
            ))

    return result
```

2. Sharpe ratio:

```python
import numpy as np

def sharpe_ratio(
    daily_returns: list[DailyReturn],
    risk_free_rate: float = 0.03
) -> float:
    if not daily_returns:
        return 0.0

    rets = np.array([r.return_pct for r in daily_returns])
    avg_daily = np.mean(rets)
    daily_rf = risk_free_rate / 252

    std_daily = np.std(rets, ddof=1)  # Sample std dev

    if std_daily == 0:
        return 0.0

    daily_sharpe = (avg_daily - daily_rf) / std_daily
    annual_sharpe = daily_sharpe * np.sqrt(252)

    return annual_sharpe
```

3. CAGR:

```python
def cagr(
    trades: list[Trade],
    initial_capital: float,
    start_time: int,
    end_time: int
) -> float:
    total_pnl = sum(t.pnl() for t in trades)
    final_equity = initial_capital + total_pnl

    years = (end_time - start_time) / (1000 * 60 * 60 * 24 * 365)

    if years <= 0 or initial_capital <= 0:
        return 0.0

    return (final_equity / initial_capital) ** (1 / years) - 1
```
-}

