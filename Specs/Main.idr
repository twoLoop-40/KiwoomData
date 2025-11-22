module Specs.Main

-- Core Types
import Specs.Core.Types
import Specs.Core.TimeTypes
import Specs.Core.ErrorTypes

-- Collector
import Specs.Collector.API
import Specs.Collector.RateLimit
import Specs.Collector.HistoricalDownload

-- Sync
import Specs.Sync.Strategy
import Specs.Sync.FileExport
import Specs.Sync.NetworkTransfer

-- Database
import Specs.Database.Schema
import Specs.Database.Hypertable
import Specs.Database.Indexing

-- Vector
import Specs.Vector.SlidingWindow
import Specs.Vector.FeatureEngineering
import Specs.Vector.Embedding

-- Validation
import Specs.Validation.Invariants
import Specs.Validation.Continuity
import Specs.Validation.Deduplication

-- Resilience
import Specs.Resilience.NetworkFailure

%default total

--------------------------------------------------------------------------------
-- Kiwoom 데이터 수집 시스템 전체 명세
-- 목적: 20년치 주식 데이터 수집 + 벡터 임베딩 + 유사 패턴 검색
--------------------------------------------------------------------------------

||| 전체 시스템 구성
public export
record KiwoomDataSystem where
  constructor MkSystem
  -- 데이터 수집
  collector : Unit  -- Collector 모듈
  -- Windows ↔ Mac 동기화
  sync : Unit       -- Sync 모듈
  -- TimescaleDB 저장
  database : Unit   -- Database 모듈
  -- 벡터 임베딩
  vector : Unit     -- Vector 모듈
  -- 데이터 검증
  validation : Unit -- Validation 모듈
  -- 장애 대응
  resilience : Unit -- Resilience 모듈

--------------------------------------------------------------------------------
-- 시스템 개요
--------------------------------------------------------------------------------

export
systemOverview : String
systemOverview = """
=== Kiwoom 데이터 수집 시스템 (Formal Spec) ===

## 목표
- Kiwoom 증권 20년치 주식 데이터 수집
- TimescaleDB 저장 (일봉, 1분봉, 10분봉, 틱 데이터)
- 벡터 임베딩 (60~120 캔들 → 600차원 벡터)
- 유사 패턴 검색 (Milvus)
- 알고리즘 트레이딩 백테스팅 (VectorBT)

## 아키텍처

### Windows (로그 제피러스, RTX 5080, 2TB SSD)
- Kiwoom OpenAPI 데이터 수집
- SQLite 버퍼 (임시 저장)
- Parquet 변환 (1시간마다)
- SFTP → Mac 전송

### Mac (M3 Max, 128GB RAM, 8TB SSD)
- TimescaleDB (메인 저장소)
- Milvus (벡터 데이터베이스)
- VectorBT (백테스팅)
- ML 모델 학습

## 데이터 플로우

1. **수집** (Windows)
   Kiwoom API → Rate Limiter (5 req/sec) → SQLite

2. **변환** (Windows, 1시간마다)
   SQLite → Parquet (연도별 파티션)

3. **전송** (Windows → Mac)
   SFTP + 체크섬 검증 + Atomic 전송

4. **저장** (Mac)
   Parquet → TimescaleDB (하이퍼테이블 + 압축)

5. **벡터화** (Mac)
   60~120 캔들 윈도우 → 지표 계산 → 벡터 임베딩 → Milvus

6. **백테스팅** (Mac)
   유사 패턴 검색 → 과거 결과 분석 → VectorBT 시뮬레이션

## 주요 기술

### 타입 안전성
- GADT: API 요청 타입 보장
- Vect: 윈도우 길이 보장
- Smart Constructor: 검증된 데이터만 타입으로 표현

### 성능 최적화
- Polars: Pandas 대비 10배 빠른 처리
- TimescaleDB 압축: 5~10배 용량 절감
- HNSW 인덱스: IVF_FLAT 대비 10배 빠른 검색
- PCA: 600차원 → 64차원 (검색 속도 3배 향상)

### 장애 대응
- Rate Limiting: 초당 5회 제한 준수
- Exponential Backoff: 재시도 간격 점진적 증가
- Incremental Sync: 차이분만 동기화
- Throttling: 배치 전송 (10개씩, 1초 대기)
- Network Failure: 연결 끊겨도 각자 작업 계속

## 모듈 구조

Specs/
├── Core/                    # 핵심 타입
│   ├── Types.idr           # Stock, Candle, OHLCV
│   ├── TimeTypes.idr       # Timeframe, WindowSize
│   └── ErrorTypes.idr      # APIError, ValidationError
│
├── Collector/               # 데이터 수집
│   ├── API.idr             # Kiwoom API (GADT)
│   ├── RateLimit.idr       # 초당 5회 제한
│   └── HistoricalDownload.idr  # 20년 다운로드 전략
│
├── Sync/                    # Windows ↔ Mac 동기화
│   ├── Strategy.idr        # 3가지 전송 방식
│   ├── FileExport.idr      # SQLite → Parquet
│   └── NetworkTransfer.idr # SFTP + 체크섬
│
├── Database/                # TimescaleDB
│   ├── Schema.idr          # 테이블 스키마 (틱 포함)
│   ├── Hypertable.idr      # 압축 + 보존 정책
│   └── Indexing.idr        # BRIN + BTree 인덱스
│
├── Vector/                  # 벡터 임베딩
│   ├── SlidingWindow.idr   # 60~120 캔들 윈도우
│   ├── FeatureEngineering.idr  # RSI, MACD, Bollinger
│   └── Embedding.idr       # Milvus + HNSW + PCA
│
├── Validation/              # 데이터 검증
│   ├── Invariants.idr      # 가격>0, High>=Open
│   ├── Continuity.idr      # 날짜 연속성 (휴장일 고려)
│   └── Deduplication.idr   # 중복 제거
│
├── Resilience/              # 장애 대응
│   └── NetworkFailure.idr  # 연결 끊김 대응
│
└── Main.idr                 # 전체 시스템 통합

## 구현 순서 (Python)

1. **Core 타입 정의** (dataclass)
2. **Kiwoom 수집기** (KOAPY + Rate Limiter)
3. **SQLite 버퍼링** (임시 저장)
4. **Parquet 변환** (Polars + 파티셔닝)
5. **SFTP 전송** (Paramiko + 체크섬)
6. **TimescaleDB 저장** (psycopg2 + 하이퍼테이블)
7. **벡터 임베딩** (Milvus + HNSW)
8. **백테스팅** (VectorBT)

## 예상 성능

- **수집 속도**: 초당 5회 (Kiwoom 제한)
- **20년 데이터**: 6~12시간 (2500 종목)
- **압축률**: 5~10배 (TimescaleDB)
- **검색 속도**: 밀리초 내 수백만 벡터 (Milvus HNSW)

## 참고 문서

- Idris2: http://idris-lang.org/
- TimescaleDB: https://docs.timescale.com/
- Milvus: https://milvus.io/docs/
- Polars: https://pola-rs.github.io/polars/
- VectorBT: https://vectorbt.dev/
"""
