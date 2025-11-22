||| Basic Performance Metrics - Trade-level statistics
|||
||| Simple metrics that don't require initial capital:
||| - Total PnL, Average PnL
||| - Win/Loss counts, Win Rate
||| - Profit Factor, Streaks

module Backtesting.Performance.BasicMetrics

import Backtesting.Core
import Data.List

%default total

--------------------------------------------------------------------------------
-- PnL Metrics
--------------------------------------------------------------------------------

||| Calculate total PnL from list of trades
public export
totalPnL : List Trade -> Double
totalPnL trades = sum (map tradePnL trades)

||| Calculate average PnL per trade
public export
averagePnL : List Trade -> Double
averagePnL [] = 0.0
averagePnL trades =
  let total = totalPnL trades
      count = cast (length trades)
  in total / count

||| Calculate average return percentage (per trade, not time-weighted)
public export
averageReturn : List Trade -> Double
averageReturn [] = 0.0
averageReturn trades =
  let totalRet = sum (map tradeReturn trades)
      count = cast (length trades)
  in totalRet / count

--------------------------------------------------------------------------------
-- Win/Loss Statistics
--------------------------------------------------------------------------------

||| Count winning trades (PnL > 0)
public export
winningTrades : List Trade -> Nat
winningTrades trades = length (filter (\t => tradePnL t > 0.0) trades)

||| Count losing trades (PnL < 0)
public export
losingTrades : List Trade -> Nat
losingTrades trades = length (filter (\t => tradePnL t < 0.0) trades)

||| Calculate win rate (0.0 ~ 1.0)
public export
winRate : List Trade -> Double
winRate [] = 0.0
winRate trades =
  let wins = cast (winningTrades trades)
      total = cast (length trades)
  in wins / total

||| Calculate profit factor (gross profit / gross loss)
|||
||| Profit factor > 1.0 means profitable system
public export
profitFactor : List Trade -> Double
profitFactor trades =
  let grossProfit = sum (map tradePnL (filter (\t => tradePnL t > 0.0) trades))
      grossLoss = abs (sum (map tradePnL (filter (\t => tradePnL t < 0.0) trades)))
  in if grossLoss == 0.0
       then if grossProfit > 0.0 then 9999.0 else 0.0
       else grossProfit / grossLoss

--------------------------------------------------------------------------------
-- Streak Analysis
--------------------------------------------------------------------------------

||| Find longest winning streak
public export
longestWinStreak : List Trade -> Nat
longestWinStreak trades =
  let pnls = map tradePnL trades
      countStreak : List Double -> Nat -> Nat -> Nat
      countStreak [] current maxStreak = max current maxStreak
      countStreak (p :: ps) current maxStreak =
        if p > 0.0
          then countStreak ps (current + 1) (max (current + 1) maxStreak)
          else countStreak ps 0 maxStreak
  in countStreak pnls 0 0

||| Find longest losing streak
public export
longestLoseStreak : List Trade -> Nat
longestLoseStreak trades =
  let pnls = map tradePnL trades
      countStreak : List Double -> Nat -> Nat -> Nat
      countStreak [] current maxStreak = max current maxStreak
      countStreak (p :: ps) current maxStreak =
        if p < 0.0
          then countStreak ps (current + 1) (max (current + 1) maxStreak)
          else countStreak ps 0 maxStreak
  in countStreak pnls 0 0

||| Find largest winning trade
public export
largestWin : List Trade -> Double
largestWin trades =
  let wins = filter (\t => tradePnL t > 0.0) trades
  in case wins of
       [] => 0.0
       _  => maximum (map tradePnL wins)

||| Find largest losing trade
public export
largestLoss : List Trade -> Double
largestLoss trades =
  let losses = filter (\t => tradePnL t < 0.0) trades
  in case losses of
       [] => 0.0
       _  => minimum (map tradePnL losses)
