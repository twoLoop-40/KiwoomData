
module Specs.Vector.OptimalTransport

import Specs.Core.Types
import Specs.Vector.Embedding

%default total

--------------------------------------------------------------------------------
-- Optimal Transport Re-ranking
-- 목적: Vector search 결과를 Wasserstein distance로 재정렬
-- 이유: Cosine similarity는 벡터 방향만 고려, OT는 분포 형태까지 고려
--------------------------------------------------------------------------------

||| Cost matrix computation method
public export
data CostMethod = Euclidean | Manhattan | SquaredEuclidean

||| Cost matrix between two time series patterns
public export
record CostMatrix where
  constructor MkCostMatrix
  nRows : Nat
  nCols : Nat
  costs : List (List Double)

||| Sinkhorn algorithm parameters
public export
record SinkhornParams where
  constructor MkSinkhornParams
  reg : Double              -- Entropy regularization parameter (e.g., 0.1)
  maxIter : Nat             -- Maximum iterations (e.g., 1000)
  threshold : Double        -- Convergence threshold (e.g., 1e-9)
  method : CostMethod       -- Distance metric for cost matrix
  temporalWeight : Double   -- Temporal regularization weight (e.g., 0.5)

||| Default Sinkhorn parameters
public export
defaultSinkhornParams : SinkhornParams
defaultSinkhornParams = MkSinkhornParams 0.1 1000 1.0e-9 SquaredEuclidean 0.5

||| Parallel processing configuration
public export
record ParallelConfig where
  constructor MkParallelConfig
  useGPU : Bool
  numWorkers : Nat
  batchSize : Nat

||| Default parallel config
public export
defaultParallelConfig : ParallelConfig
defaultParallelConfig = MkParallelConfig False 8 100

||| OT distance result
public export
record OTDistance where
  constructor MkOTDistance
  value : Double         -- Wasserstein distance value
  converged : Bool       -- Did Sinkhorn converge?
  iterations : Nat       -- Number of iterations used

||| Search candidate with similarity score
public export
record Candidate where
  constructor MkCandidate
  stockCode : StockCode
  timestamp : Integer
  pattern : List (List Double)  -- Time series pattern (needed for OT)
  cosineSimilarity : Double     -- Initial cosine similarity (from vector search)
  otDistance : Maybe Double     -- OT distance (computed during re-ranking)

||| Re-ranking result
public export
record RerankResult where
  constructor MkRerankResult
  query : VectorEmbedding Reduced
  candidates : List Candidate    -- Sorted by OT distance (ascending)
  topK : Nat

--------------------------------------------------------------------------------
-- Time series structure
--------------------------------------------------------------------------------

||| Time series pattern: (n_candles × n_features) matrix
||| Represented as nested list for Idris2 simplicity
||| In Python: numpy array of shape (n_candles, n_features)
public export
TimeSeriesPattern : Type
TimeSeriesPattern = List (List Double)

||| Normalize to probability distribution (L1 norm, sum=1)
||| Required preprocessing for Sinkhorn algorithm
public export
normalizeL1 : List Double -> List Double

--------------------------------------------------------------------------------
-- Core specifications
--------------------------------------------------------------------------------

||| Compute cost matrix with temporal regularization
|||
||| Formula:
|||   C[i,j] = spatialCost[i,j] + temporalWeight * |i - j|²
|||
||| Where:
|||   spatialCost[i,j] = ||candle_i - candle_j||² (feature distance)
|||   temporalCost = |i - j|² (time step penalty)
|||
||| This ensures matching respects temporal order
|||
||| @ts1 Query pattern (n_candles × n_features)
||| @ts2 Candidate pattern (n_candles × n_features)
||| @params Algorithm parameters (includes temporalWeight)
public export
computeCostMatrixTemporal : (ts1 : TimeSeriesPattern) ->
                            (ts2 : TimeSeriesPattern) ->
                            (params : SinkhornParams) ->
                            CostMatrix

||| Compute Sinkhorn distance (entropy-regularized OT)
|||
||| PRECONDITION: a and b MUST be normalized (sum=1)
|||
||| Algorithm (log-domain for numerical stability):
|||   K = exp(-C / reg)
|||   Iterate: u ← a / (K @ v), v ← b / (K.T @ u)
|||   Distance = <u ⊙ (K @ v), C>
|||
||| @costMatrix Cost matrix with temporal regularization
||| @a Source distribution (MUST sum to 1)
||| @b Target distribution (MUST sum to 1)
||| @params Sinkhorn parameters
public export
computeSinkhornDistance : (costMatrix : CostMatrix) ->
                          (a : List Double) ->
                          (b : List Double) ->
                          (params : SinkhornParams) ->
                          OTDistance

||| Batch compute OT distances with parallel processing
|||
||| This is the KEY function for performance!
|||
||| For 500 candidates:
|||   - Sequential: ~500 × 50ms = 25 seconds
|||   - Parallel (20 workers): ~500 / 20 × 50ms = 1.25 seconds (20× speedup!)
|||   - GPU (RTX 5080): ~500 × 2ms = 1 second (50× speedup!)
|||
||| @query Query pattern
||| @candidatePatterns List of candidate patterns (500+)
||| @params Sinkhorn parameters
||| @parallelConfig Parallel processing config
|||
||| Returns: List of OT distances (same order as input)
public export
batchComputeOT : (query : TimeSeriesPattern) ->
                 (candidatePatterns : List TimeSeriesPattern) ->
                 (params : SinkhornParams) ->
                 (parallelConfig : ParallelConfig) ->
                 List OTDistance

||| Re-rank candidates using batch parallel OT
|||
||| Pipeline:
|||   1. Vector search → Top-500 candidates (Milvus, fast)
|||   2. Batch OT computation → 500 OT distances (parallel/GPU)
|||   3. Sort by OT distance → Top-K final results
|||
||| @query Query time series pattern
||| @candidates Initial candidates from vector search (500+)
||| @topK Final number of results (e.g., 10)
||| @params Sinkhorn parameters
||| @parallelConfig Parallel processing config
public export
rerankCandidates : (query : TimeSeriesPattern) ->
                   (candidates : List Candidate) ->
                   (topK : Nat) ->
                   (params : SinkhornParams) ->
                   (parallelConfig : ParallelConfig) ->
                   RerankResult

--------------------------------------------------------------------------------
-- Properties and invariants
--------------------------------------------------------------------------------

{- Property: OT distance is a metric
   For all patterns a, b, c:
   1. d_OT(a, b) ≥ 0                    (Non-negativity)
   2. d_OT(a, b) = 0 ⟺ a = b           (Identity)
   3. d_OT(a, b) = d_OT(b, a)          (Symmetry)
   4. d_OT(a, c) ≤ d_OT(a, b) + d_OT(b, c)  (Triangle inequality)
-}

{- Property: Convergence of Sinkhorn algorithm
   The Sinkhorn-Knopp algorithm converges when:
   - reg > 0 (positive regularization)
   - Cost matrix C has finite entries
   - Marginal distributions have full support
   Convergence rate: O(exp(-k/reg)) where k is iteration number
-}

{- Property: Re-ranking improves similarity
   For candlestick patterns with similar shapes but different scales:
   - Cosine similarity may rank them incorrectly (sensitive to magnitude)
   - OT distance captures shape similarity better
   Example:
     Pattern A: [100, 105, 98, 103] (low volatility)
     Pattern B: [200, 210, 196, 206] (high volatility, same shape)
     
     OT(A, B) should be small (similar shape)
-}
