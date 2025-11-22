||| KiwoomData Project TODO
|||
||| This file tracks remaining tasks for formal specification and implementation
|||
||| Status Legend:
||| ✅ DONE - Completed and verified
||| 🚧 IN PROGRESS - Currently working on
||| 📋 PLANNED - Designed but not started
||| 💡 IDEA - Future enhancement

module TODO

{-
================================================================================
Phase A: Data Pipeline ✅ DONE
================================================================================

[✅] Specs/Data/Types.idr - Core data types (Candle, OHLCV)
[✅] Specs/Validation/Invariants.idr - Smart constructors
[✅] Specs/Validation/Deduplication.idr - Duplicate detection
[✅] Python Implementation - All 52 tests passing
[✅] Demo: examples/demo_pipeline.py


================================================================================
Phase B: Vector Embedding ✅ DONE
================================================================================

[✅] Specs/Vector/Window.idr - Sliding window extraction
[✅] Specs/Vector/Features.idr - Technical indicators
[✅] Specs/Vector/Embedding.idr - PCA and similarity search
[✅] Python Implementation - All tests passing
[✅] Demo: examples/demo_vector_pipeline.py


================================================================================
Phase C: Backtesting Framework 🚧 IN PROGRESS
================================================================================

Formal Specifications (Idris2):
[✅] Specs/Backtesting/Core.idr
     - Position (GADT: NoPosition, Long, Short)
     - Signal (Buy, Sell, Hold)
     - Trade (immutable record)
     - executeSignal : Signal -> Position -> ... -> (Position, Maybe Trade)
     - CRITICAL: Returns completed Trade when position closes
     - Compiled successfully ✅

[✅] Specs/Backtesting/Performance/BasicMetrics.idr
     - totalPnL, averagePnL
     - winRate, profitFactor
     - longestWinStreak, longestLoseStreak

[✅] Specs/Backtesting/Performance/RiskMetrics.idr
     - maxDrawdown (requires initialCapital)
     - sharpeRatio (uses daily returns, annualized)
     - cagr (Compound Annual Growth Rate)
     - totalReturnPct (based on initialCapital)
     - DailyReturn type for correct Sharpe calculation

[📋] Specs/Backtesting/RiskManagement.idr (NEXT)
     - Stop-loss logic
     - Take-profit logic
     - Position sizing rules
     - Capital management

[📋] Verify all specs compile together
     - cd Specs && idris2 --check Backtesting/Core.idr
     - idris2 --check Backtesting/Performance/BasicMetrics.idr
     - idris2 --check Backtesting/Performance/RiskMetrics.idr

Python Implementation (NEXT PHASE):
[📋] src/kiwoomdata/backtesting/types.py
     - Position (NoPosition | LongPosition | ShortPosition)
     - Signal (Enum: BUY, SELL, HOLD)
     - Trade (Pydantic with validators)
     - TradeError (Enum)

[📋] src/kiwoomdata/backtesting/engine.py
     - execute_signal() - Returns (Position, Optional[Trade])
     - BacktestEngine class
     - Backtesting loop with trade collection

[📋] src/kiwoomdata/backtesting/metrics.py
     - PerformanceSummary (Pydantic)
     - calculate_performance(initial_capital, risk_free_rate, ...)
     - trades_to_daily_returns() using pandas resample
     - sharpe_ratio() with daily returns

[📋] src/kiwoomdata/backtesting/strategy.py
     - Strategy abstract base class
     - PatternMatcherStrategy (vector similarity-based)

[📋] tests/test_backtesting.py
     - Test Position transitions
     - Test Trade creation on close
     - Test performance metrics
     - Test Sharpe ratio with daily returns

[📋] examples/demo_backtesting.py
     - Simple moving average crossover strategy
     - Pattern-based strategy using vector similarity
     - Performance report generation


================================================================================
Phase D: REST API Integration 💡 IDEA (DISCOVERED TODAY!)
================================================================================

IMPORTANT DISCOVERY:
- Kiwoom Securities provides REST API (not just Windows OpenAPI!)
- URL: https://openapi.kiwoom.com/guide/apiguide?jobTpCode=07
- This means: ✨ MAC-COMPATIBLE DATA COLLECTION ✨

Architecture Change:
[💡] BEFORE: Windows (OpenAPI) → Mac (Milvus + Backtesting)
[💡] AFTER:  Mac (REST API + Milvus + Backtesting) - ALL IN ONE!

Tasks (Future):
[💡] Research Kiwoom REST API authentication (OAuth tokens)
[💡] Design REST API client spec (Specs/API/RestClient.idr)
[💡] Implement HTTP client (requests library)
[💡] Compare REST API vs OpenAPI feature parity
[💡] Migrate data collection to Mac
[💡] Remove Windows dependency entirely (optional)

Endpoints to explore:
- POST /api/dostk/chart - Historical OHLCV data
- Real-time streaming (WebSocket?)
- Order placement (for live trading - CAREFUL!)


================================================================================
Phase E: Production Deployment 📋 PLANNED
================================================================================

[📋] Milvus Setup on Mac
     - Docker Compose configuration
     - Vector collection schema
     - Index configuration (IVF_FLAT or HNSW)
     - Bulk insert pipeline

[📋] Data Pipeline Automation
     - Cron job for daily data collection
     - Incremental updates (avoid full reprocessing)
     - Error handling and retry logic

[📋] Backtesting at Scale
     - 2,500 stocks × 20 years of data
     - Parallel backtesting (multiprocessing)
     - Results storage (Parquet or SQLite)

[📋] Pattern Library
     - Pre-computed pattern vectors
     - Pattern labeling (bull flag, head & shoulders, etc.)
     - Pattern performance tracking


================================================================================
Future Enhancements 💡
================================================================================

[💡] Machine Learning Integration
     - Train classifier on pattern similarity → future returns
     - Reinforcement learning for strategy optimization
     - Feature importance analysis

[💡] Live Trading (VERY CAREFUL!)
     - Paper trading first (Kiwoom mock API)
     - Risk limits and circuit breakers
     - Real-time pattern matching
     - Order execution via REST API

[💡] Web Dashboard
     - Portfolio visualization
     - Live pattern alerts
     - Backtesting results browser
     - Performance analytics

[💡] Multi-Market Support
     - US stocks (Yahoo Finance API)
     - Crypto (Binance API)
     - Unified data model


================================================================================
Code Quality & Maintenance
================================================================================

[✅] All Phase A & B tests passing (52/52 tests)
[📋] Add Phase C tests
[📋] CI/CD pipeline (GitHub Actions)
[📋] Documentation
     - README updates
     - API documentation (mkdocs)
     - Tutorial notebooks
[📋] Performance profiling
     - Identify bottlenecks
     - Optimize hot paths
     - Memory usage analysis


================================================================================
Key Decisions Made
================================================================================

1. ✅ Mac-only Milvus deployment (not Windows)
   - Reason: Docker works better on Mac/Linux

2. ✅ PCA in-memory first, Milvus later
   - Reason: Simplicity for MVP

3. ✅ Sharpe Ratio uses DAILY returns (not per-trade)
   - Reason: Industry standard, time-weighted

4. ✅ Performance metrics require initialCapital
   - Reason: Accurate percentage calculations (MDD, CAGR, Total Return%)

5. ✅ executeSignal returns (Position, Maybe Trade)
   - Reason: Collect completed trades for performance analysis

6. 💡 Consider REST API instead of Windows OpenAPI
   - Reason: Mac compatibility discovered!


================================================================================
Next Session Tasks (Priority Order)
================================================================================

1. [HIGH] Verify all Idris2 specs compile
   - Fix any compilation errors
   - Ensure imports work correctly

2. [HIGH] Implement Phase C Python code
   - Start with types.py (Position, Signal, Trade)
   - Then engine.py (execute_signal, BacktestEngine)
   - Finally metrics.py (PerformanceSummary)

3. [MEDIUM] Write Phase C tests
   - Test state machine transitions
   - Test Trade creation on position close
   - Test Sharpe ratio with daily returns

4. [MEDIUM] Create demo_backtesting.py
   - Simple strategy example
   - Performance report

5. [LOW] Research Kiwoom REST API
   - Authentication flow
   - Available endpoints
   - Rate limits

6. [LOW] Update README with Phase C progress


================================================================================
Questions for User
================================================================================

Q1: Should we prioritize REST API research for Mac-native data collection?
Q2: Do you want to keep Windows OpenAPI support, or migrate fully to REST API?
Q3: For backtesting, should we implement Risk Management spec first, or go straight to Python?
Q4: Any specific backtesting strategies you want to test first?


================================================================================
Notes
================================================================================

- Project follows formal spec-first approach (Idris2 → Python)
- All data is immutable (Polars, Pydantic frozen=True)
- Type safety enforced at spec level, runtime validation in Python
- Performance-critical paths use Polars (not pandas)
- Vector search ready for Milvus migration (currently numpy-based)

- NEW: Kiwoom REST API enables Mac-native development!
  - No need for Windows VM
  - Simpler deployment
  - Cross-platform from day one
-}
