# Formal Specification Guidelines

**Purpose**: This project uses Idris2 formal specifications to define types and interfaces. Python implements these specs with runtime validation.

## Core Principle: Skeleton Over Details

Formal specs should provide **structure and type signatures ONLY**. Leave implementation details, proofs, and complex logic to the user.

---

## ✅ DO: Write Clean Type Signatures

```idris
||| Compute cost matrix with temporal regularization
|||
||| Cost = spatialCost + temporalWeight * temporalCost
|||
||| @ts1 Query pattern
||| @ts2 Candidate pattern
||| @params Algorithm parameters
public export
computeCostMatrixTemporal : (ts1 : TimeSeriesPattern) ->
                            (ts2 : TimeSeriesPattern) ->
                            (params : SinkhornParams) ->
                            CostMatrix
```

**Why**: Clear interface, minimal clutter. User fills in implementation.

---

## ❌ DON'T: Write Long Implementation Guides

```idris
-- BAD: Too much detail in spec
export
pythonGuide : String
pythonGuide = """
Complete step-by-step implementation with code examples...

```python
def compute_cost_matrix(pattern1, pattern2):
    # Step 1: Initialize matrix
    cost = np.zeros((len(pattern1), len(pattern2)))

    # Step 2: Compute pairwise distances
    for i in range(len(pattern1)):
        for j in range(len(pattern2)):
            cost[i][j] = np.linalg.norm(pattern1[i] - pattern2[j])
    ...
```
"""
```

**Why**: This belongs in Python code, not Idris spec. Spec should only define **what**, not **how**.

---

## Structure Template

```idris
module Specs.MyModule

import Specs.Core.Types

%default total

--------------------------------------------------------------------------------
-- Module purpose (1-2 lines)
--------------------------------------------------------------------------------

||| Core type definition
public export
record MyType where
  constructor MkMyType
  field1 : SomeType
  field2 : AnotherType

||| Function specification
|||
||| Brief description (1-3 lines)
|||
||| @param1 Description
||| @param2 Description
public export
myFunction : (param1 : Type1) ->
             (param2 : Type2) ->
             ReturnType

{- Property: What this function guarantees (optional, if important)
   - Invariant 1
   - Invariant 2
-}
```

---

## Performance Notes

Add performance-critical notes **inline** with type signatures:

```idris
||| Analyze future returns
|||
||| PERFORMANCE: O(N) with hash lookups, NOT O(N*M) filters
|||
||| @matches Input candidates
public export
analyzeFutureReturns : List Candidate -> List FutureReturn
```

**Why**: Developers need to know critical complexity constraints upfront.

---

## What Belongs Where

### In Idris Spec (Formal)
- ✅ Type signatures
- ✅ Data type definitions
- ✅ Core invariants (as comments)
- ✅ Performance requirements (Big-O complexity)
- ✅ Brief descriptions (1-3 lines)

### In Python Code (Implementation)
- ✅ Concrete algorithms
- ✅ Error handling
- ✅ Optimization techniques
- ✅ Detailed documentation
- ✅ Tests and examples

---

## Example: Before vs After

### ❌ BEFORE (Too Detailed)

```idris
public export
computeOTDistance : Pattern -> Pattern -> Double

export
pythonGuide : String
pythonGuide = """
Step 1: Compute cost matrix
```python
C = np.zeros((n, m))
for i in range(n):
    for j in range(m):
        C[i,j] = distance(p1[i], p2[j])
```

Step 2: Run Sinkhorn algorithm
```python
K = np.exp(-C / reg)
u = np.ones(n)
v = np.ones(m)
for iteration in range(max_iter):
    u = a / (K @ v)
    v = b / (K.T @ u)
```
"""
```

### ✅ AFTER (Clean Skeleton)

```idris
||| Compute OT distance using Sinkhorn algorithm
|||
||| PRECONDITION: Inputs must be normalized distributions (sum=1)
||| PERFORMANCE: O(n² * iterations), use GPU for n > 100
|||
||| @pattern1 Source distribution
||| @pattern2 Target distribution
public export
computeOTDistance : (pattern1 : Pattern) ->
                    (pattern2 : Pattern) ->
                    (params : SinkhornParams) ->
                    OTDistance

{- Property: Metric properties
   1. d(a,b) ≥ 0
   2. d(a,b) = 0 ⟺ a = b
   3. d(a,b) = d(b,a)
   4. d(a,c) ≤ d(a,b) + d(b,c)
-}
```

**Why**: Type signature + constraints are enough. User implements the algorithm in Python.

---

## Golden Rules

1. **Brevity**: 1-3 line descriptions max
2. **Types First**: Signature is the spec
3. **Properties as Comments**: Use `{- -}` blocks for invariants
4. **No Code**: Python code belongs in `.py` files
5. **User Fills Gaps**: Spec is a skeleton, user adds flesh

---

## Applying to This Project

All future Idris specs in `Specs/` should follow this guide:
- Keep type signatures clean
- Add performance notes inline (Big-O)
- Use comment blocks for properties
- **NO** long `pythonGuide` exports with example code
- Let user implement and prove correctness

**The user will fill in proofs and implementation details.**
