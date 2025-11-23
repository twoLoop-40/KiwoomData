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
Phase D: Optimal Transport Re-ranking 📋 PLANNED (START HERE!)
================================================================================

GOAL: Improve vector search results using Optimal Transport distance

Background:
- Vector search (cosine similarity) gives initial candidates
- OT re-ranks candidates using Earth Mover's Distance
- Better captures shape similarity between time series patterns

Architecture:
[📋] Vector Search (Phase 1) → OT Re-ranking (Phase 2) → Final Results

[📋] Research Optimal Transport for time series
     - Sinkhorn algorithm (entropy-regularized OT)
     - Python library: POT (Python Optimal Transport)
     - Application to candlestick patterns

[📋] Design Specs/Vector/OptimalTransport.idr
     - Cost matrix computation
     - Sinkhorn distance calculation
     - Re-ranking algorithm specification

[📋] Implement src/kiwoomdata/vector/ot_rerank.py
     - compute_ot_distance(pattern1, pattern2) using POT library
     - rerank_candidates(query, candidates, top_k)
     - Integration with existing vector pipeline

[📋] Add tests: tests/test_ot_rerank.py
     - Test OT distance computation
     - Compare OT vs cosine similarity rankings
     - Performance benchmarks

[📋] Update examples/demo_vector_pipeline.py
     - Show before/after re-ranking
     - Visualize similarity improvements

Dependencies to install:
- POT: pip install POT (Python Optimal Transport)
- NumPy/SciPy for matrix operations


================================================================================
Phase E: Kiwoom REST API → Idris2 Dictionary 📋 PLANNED
================================================================================

IMPORTANT DISCOVERY:
- Kiwoom Securities provides REST API (not just Windows OpenAPI!)
- URL: https://openapi.kiwoom.com/guide/apiguide?jobTpCode=07
- This means: ✨ MAC-COMPATIBLE DATA COLLECTION ✨

Architecture Change:
[💡] BEFORE: Windows (OpenAPI) → Mac (Milvus + Backtesting)
[💡] AFTER:  Mac (REST API + Milvus + Backtesting) - ALL IN ONE!

NEW GOAL: Create KiwoomIdris - Formal API Specification Dictionary
[📋] Research all Kiwoom REST API endpoints
     - Authentication (OAuth 2.0, token management)
     - Market data endpoints (OHLCV, real-time quotes)
     - Order endpoints (buy/sell, cancel)
     - Account endpoints (balance, positions)
     - Rate limits and quotas

[📋] Design Specs/API/Kiwoom/Endpoints.idr
     - Endpoint catalog with types
     - Request/Response schemas
     - Error codes enumeration
     - Rate limit specifications

[📋] Design Specs/API/Kiwoom/Auth.idr
     - OAuth flow state machine
     - Token refresh logic
     - Credential management

[📋] Design Specs/API/Kiwoom/Client.idr
     - HTTP client interface
     - Request builder with type safety
     - Response parser with validation

[📋] Implement Python client: src/kiwoomdata/api/
     - rest_client.py (HTTP requests)
     - auth.py (OAuth handler)
     - endpoints.py (typed endpoint functions)
     - models.py (Pydantic request/response models)

[📋] Create API documentation
     - KiwoomIdris.md - Complete endpoint reference
     - Usage examples
     - Error handling guide


================================================================================
Phase F: Paper Trading App 📋 PLANNED
================================================================================

GOAL: Real-time paper trading application with pattern matching

Features:
[📋] Real-time market data streaming
     - Connect to Kiwoom REST API (or WebSocket)
     - Live price updates
     - Real-time pattern detection

[📋] Pattern matching engine
     - Vector search for similar historical patterns
     - OT re-ranking for best matches
     - Signal generation (Buy/Sell/Hold)

[📋] Virtual portfolio management
     - Paper trading account (no real money!)
     - Position tracking
     - Order execution simulation
     - P&L calculation

[📋] Risk management
     - Stop-loss automation
     - Take-profit automation
     - Position sizing rules
     - Maximum drawdown limits

[📋] Web dashboard (optional)
     - Live chart with pattern overlays
     - Portfolio summary
     - Trade history
     - Performance metrics

[📋] Specs/PaperTrading/Core.idr
     - VirtualAccount type
     - Order type (Market, Limit, Stop)
     - OrderStatus (Pending, Filled, Cancelled)
     - Portfolio state machine

[📋] Implementation: src/kiwoomdata/papertrading/
     - account.py (VirtualAccount class)
     - order_manager.py (Order execution simulation)
     - strategy_runner.py (Live pattern matching)
     - dashboard.py (Streamlit or FastAPI)

Safety Features:
- ⚠️ NEVER connect to real trading API
- ⚠️ Always use paper trading endpoints
- ⚠️ Clear warnings in UI: "PAPER TRADING ONLY"


================================================================================
Phase G: Production Deployment 📋 PLANNED
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
Next Session Tasks (Priority Order) - UPDATED!
================================================================================

1. [HIGH] Phase D: Optimal Transport Re-ranking (START HERE!)
   - Research POT library (Python Optimal Transport)
   - Design Specs/Vector/OptimalTransport.idr
   - Implement ot_rerank.py with Sinkhorn algorithm
   - Test OT distance vs cosine similarity
   - Update demo_vector_pipeline.py

2. [HIGH] Phase C: Backtesting Implementation
   - Implement types.py (Position, Signal, Trade)
   - Implement engine.py (execute_signal, BacktestEngine)
   - Implement metrics.py (PerformanceSummary)
   - Write tests
   - Create demo_backtesting.py

3. [MEDIUM] Phase E: Kiwoom REST API Research
   - Study https://openapi.kiwoom.com/guide/apiguide?jobTpCode=07
   - Create KiwoomIdris endpoint dictionary
   - Design Specs/API/Kiwoom/*.idr
   - Document all endpoints, auth flow, rate limits

4. [MEDIUM] Phase F: Paper Trading App
   - Design Specs/PaperTrading/Core.idr
   - Implement virtual account management
   - Create real-time pattern matching engine
   - Build web dashboard (Streamlit)

5. [LOW] Update README with new roadmap
   - Add OT re-ranking section
   - Add paper trading section
   - Update architecture diagram


================================================================================
Questions for User (RESOLVED)
================================================================================

Q1: Should we prioritize REST API research for Mac-native data collection?
A1: Yes, but AFTER Optimal Transport re-ranking (Phase E)

Q2: Should we start with OT re-ranking or backtesting?
A2: ✅ START WITH OPTIMAL TRANSPORT RE-RANKING (Phase D)

Q3: What libraries to use for OT?
A3: ✅ POT (Python Optimal Transport) with Sinkhorn algorithm

Q4: Paper trading app needed?
A4: ✅ YES - Phase F (after backtesting)

Q5: Should we create KiwoomIdris API dictionary?
A5: ✅ YES - Complete formal specification of all endpoints


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
