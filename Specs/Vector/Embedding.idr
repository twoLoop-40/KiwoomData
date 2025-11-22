module Specs.Vector.Embedding

import Specs.Core.Types
import Specs.Vector.SlidingWindow
import Specs.Vector.FeatureEngineering

%default total

--------------------------------------------------------------------------------
-- 벡터 임베딩 (HNSW + PCA 최적화)
-- 목적: 60~120 캔들 × 특성 → 고차원 벡터 (Milvus 저장용)
--------------------------------------------------------------------------------

||| 벡터 차원 상수화
public export
RawDim : Nat
RawDim = 600  -- 60 캔들 × 10 특성

public export
ReducedDim : Nat
ReducedDim = 64  -- PCA/Autoencoder 압축 후

||| 벡터 타입 세분화
public export
data VectorType = Raw | Reduced

||| 벡터 타입별 차원
public export
Vector : VectorType -> Type
Vector Raw = List Double      -- 길이 600
Vector Reduced = List Double  -- 길이 64

||| 임베딩 레코드
public export
record VectorEmbedding (vt : VectorType) where
  constructor MkEmbedding
  stockCode : StockCode
  timestamp : Integer        -- 윈도우 종료 시각
  vector : Vector vt

||| 벡터 메타데이터 (검색 결과용)
public export
record VectorMetadata where
  constructor MkMetadata
  stockCode : StockCode
  timestamp : Integer
  windowSize : Nat
  similarity : Double        -- 유사도 점수 (0~1)

--------------------------------------------------------------------------------
-- Python 구현 가이드 (HNSW + PCA)
--------------------------------------------------------------------------------

export
pythonGuide : String
pythonGuide = """
=== Vector Embedding (Advanced: HNSW + PCA) ===

성능 최적화:
  1. Index: IVF_FLAT → HNSW (메모리 충분 시 검색 속도 10배 향상)
  2. PCA: 600차원 → 64차원 축소 (검색 정확도 향상)

```python
import numpy as np
import polars as pl
from pymilvus import connections, Collection, FieldSchema, CollectionSchema, DataType
from sklearn.decomposition import PCA
import joblib

class VectorEmbedder:
    def __init__(self, milvus_host: str = 'localhost', milvus_port: int = 19530):
        # Milvus 연결
        connections.connect(host=milvus_host, port=milvus_port)

        # PCA 모델 로드 (사전 학습됨)
        try:
            self.pca = joblib.load('models/pca_600_to_64.pkl')
            self.use_pca = True
            self.vector_dim = 64
        except FileNotFoundError:
            print("PCA model not found, using raw 600-dim vectors")
            self.use_pca = False
            self.vector_dim = 600

        # 벡터 컬렉션 생성
        self.create_collection()

    def create_collection(self):
        \"\"\"Milvus 컬렉션 생성 (HNSW 인덱스)\"\"\"

        fields = [
            FieldSchema(name='id', dtype=DataType.INT64, is_primary=True, auto_id=True),
            FieldSchema(name='stock_code', dtype=DataType.VARCHAR, max_length=10),
            FieldSchema(name='timestamp', dtype=DataType.INT64),
            FieldSchema(name='vector', dtype=DataType.FLOAT_VECTOR, dim=self.vector_dim),
        ]

        schema = CollectionSchema(fields=fields, description='Stock pattern vectors')
        self.collection = Collection(name='stock_patterns', schema=schema)

        # HNSW 인덱스 (메모리 기반 고속 검색)
        index_params = {
            'metric_type': 'L2',  # 유클리드 거리
            'index_type': 'HNSW',
            'params': {'M': 16, 'efConstruction': 500}
        }
        self.collection.create_index(field_name='vector', index_params=index_params)

    def window_to_vector(self, window_df: pl.DataFrame) -> np.ndarray:
        \"\"\"윈도우 → 벡터 변환 (600차원 or 64차원)\"\"\"

        # 1. 특성 선택 (10개)
        features = window_df.select([
            'open_norm', 'high_norm', 'low_norm', 'close_norm', 'volume_norm',
            'rsi', 'macd', 'bb_upper', 'sma_20', 'ema_12'
        ]).to_numpy()

        # 2. Flatten: (60, 10) → (600,)
        vector = features.flatten()

        # 3. NaN 처리 (0으로 대체)
        vector = np.nan_to_num(vector, nan=0.0)

        # 4. PCA 적용 (선택적)
        if self.use_pca:
            vector = self.pca.transform(vector.reshape(1, -1))[0]  # (600,) → (64,)

        return vector

    def insert_vector(self, stock_code: str, timestamp: int, vector: np.ndarray):
        \"\"\"벡터를 Milvus에 저장\"\"\"

        entities = [
            [stock_code],
            [timestamp],
            [vector.tolist()]
        ]

        self.collection.insert(entities)
        self.collection.flush()

    def search_similar(self, query_vector: np.ndarray, top_k: int = 10):
        \"\"\"유사한 패턴 검색 (HNSW)\"\"\"

        self.collection.load()

        search_params = {
            'metric_type': 'L2',
            'params': {'ef': 200}  # HNSW 검색 정확도
        }

        results = self.collection.search(
            data=[query_vector.tolist()],
            anns_field='vector',
            param=search_params,
            limit=top_k,
            output_fields=['stock_code', 'timestamp']
        )

        return results

    def train_pca(self, all_vectors: np.ndarray):
        \"\"\"PCA 모델 학습 (600 → 64 차원 축소)\"\"\"

        pca = PCA(n_components=64)
        pca.fit(all_vectors)

        # 모델 저장
        joblib.dump(pca, 'models/pca_600_to_64.pkl')

        print(f"PCA trained: 600 → 64 dims, "
              f"Explained variance: {pca.explained_variance_ratio_.sum():.2%}")

# 사용 예제

# 1. 임베딩 생성
embedder = VectorEmbedder()

# 2. 윈도우 → 벡터 변환
window_df = ...  # FeatureEngineering.idr 참조
vector = embedder.window_to_vector(window_df)

print(f"Vector dim: {len(vector)}")  # 64 (PCA) or 600 (Raw)

# 3. Milvus에 저장
embedder.insert_vector(
    stock_code='005930',
    timestamp=int(time.time()),
    vector=vector
)

# 4. 유사 패턴 검색
current_pattern = embedder.window_to_vector(current_window)
similar_patterns = embedder.search_similar(current_pattern, top_k=10)

for hit in similar_patterns[0]:
    print(f"Stock: {hit.entity.get('stock_code')}, "
          f"Distance: {hit.distance:.4f}")
```

설치:
```bash
pip install pymilvus scikit-learn joblib
docker run -d --name milvus -p 19530:19530 milvusdb/milvus:latest
```

HNSW vs IVF_FLAT:
  - HNSW: 메모리 많음, 검색 빠름 (추천)
  - IVF_FLAT: 메모리 적음, 검색 느림

PCA 효과:
  - 600차원 → 64차원: 검색 속도 3배 향상
  - 차원의 저주 완화: 검색 정확도 향상
"""
