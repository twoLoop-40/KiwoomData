module Specs.Validation.Deduplication

import Specs.Core.Types
import Data.Nat

%default total

--------------------------------------------------------------------------------
-- 중복 제거 (Deterministic Policy)
-- 목적: 동일 (timestamp, stock_code) 중복 데이터 제거
--------------------------------------------------------------------------------

||| 중복 해결 정책
public export
data DedupPolicy
  = KeepFirst  -- 기존 데이터 보존 (Immutable)
  | KeepLast   -- 최신 데이터로 덮어쓰기 (Update)

||| 중복 키 (Primary Key)
public export
record DuplicateKey where
  constructor MkDupKey
  timestamp : Integer
  stockCode : StockCode

||| 중복 제거 결과
public export
record DeduplicationResult where
  constructor MkDedupResult
  totalRows : Nat
  uniqueRows : Nat
  duplicateRows : Nat

public export
calculateDuplicates : Nat -> Nat -> Nat
calculateDuplicates totalRows uniqueRows = minus totalRows uniqueRows

--------------------------------------------------------------------------------
-- Python 구현 가이드 (Deterministic Deduplication)
--------------------------------------------------------------------------------

export
pythonGuide : String
pythonGuide = """
=== Deterministic Deduplication (정렬 기반) ===

핵심:
  - `unique(keep='last')`를 쓰려면 데이터가 **반드시 정렬**되어 있어야 함
  - 그렇지 않으면 매번 실행할 때마다 결과가 달라질 수 있음

```python
import polars as pl

class Deduplicator:
    def remove_duplicates(self, df: pl.DataFrame,
                          policy: str = 'last') -> pl.DataFrame:
        \"\"\"중복 제거 (Deterministic)\"\"\"

        # 1. 정렬 (Determinism 보장)
        # timestamp 기준 정렬 (같은 시간이면 나중에 수집된 것이 뒤로)
        sort_cols = ['timestamp']
        if 'created_at' in df.columns:
            sort_cols.append('created_at')

        df_sorted = df.sort(sort_cols, descending=False)

        # 2. 중복 제거
        if policy == 'last':
            # 마지막 = 최신 데이터 유지
            df_unique = df_sorted.unique(
                subset=['timestamp', 'stock_code'],
                keep='last'
            )
        elif policy == 'first':
            # 첫 번째 = 기존 데이터 유지
            df_unique = df_sorted.unique(
                subset=['timestamp', 'stock_code'],
                keep='first'
            )

        # 3. 통계
        total = len(df)
        unique = len(df_unique)
        duplicates = total - unique

        print(f"Total: {total}, Unique: {unique}, "
              f"Duplicates: {duplicates} ({duplicates/total*100:.2f}%)")

        return df_unique

# 사용 예제
deduplicator = Deduplicator()

# KeepLast 정책 (최신 데이터 유지)
df_clean = deduplicator.remove_duplicates(df, policy='last')
```

정책 선택 가이드:
  - KeepFirst: 원본 보존 (감사/추적 중요)
  - KeepLast: 최신 우선 (실시간 트레이딩)
"""
