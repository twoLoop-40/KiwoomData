module Specs.Collector.API

import Specs.Core.Types
import Specs.Core.TimeTypes
import Specs.Core.ErrorTypes

%default total

--------------------------------------------------------------------------------
-- Kiwoom OpenAPI 인터페이스 정의 (GADT 사용)
-- 목적: API 호출 시그니처를 타입 레벨에서 보장
--------------------------------------------------------------------------------

||| Kiwoom API 인증 정보
public export
record KiwoomAuth where
  constructor MkAuth
  accountNumber : String
  password : String
  certPassword : String

||| 분봉 타임프레임 검증
public export
isMinuteFrame : Timeframe -> Bool
isMinuteFrame Min1 = True
isMinuteFrame Min5 = True
isMinuteFrame Min10 = True
isMinuteFrame Min60 = True
isMinuteFrame _ = False

||| API 요청 타입 (GADT - 리턴 타입을 인자로 받음)
||| 각 요청이 반드시 특정 타입을 돌려준다는 것을 타입 레벨에서 보장
public export
data KiwoomRequest : Type -> Type where
  ||| 전체 종목 리스트 요청 → List Stock 보장
  ReqStockList : Market -> KiwoomRequest (List Stock)

  ||| 일봉 데이터 요청 → List Candle 보장
  ||| 제약: 한 번에 최대 600일 (Kiwoom 제한)
  ReqDailyCandles : StockCode -> DateRange -> KiwoomRequest (List Candle)

  ||| 분봉 데이터 요청 → List Candle 보장
  ||| 제약: 분봉 타임프레임만 허용 (컴파일 타임 체크)
  ||| 제약: 한 번에 최대 900개 캔들 (Kiwoom 제한)
  ReqMinuteCandles : StockCode -> DateRange -> (tf : Timeframe) ->
                     {auto prf : isMinuteFrame tf = True} ->
                     KiwoomRequest (List Candle)

  ||| 현재가 조회 → Double 보장
  ReqCurrentPrice : StockCode -> KiwoomRequest Double

||| Kiwoom API 인터페이스
||| 실제 구현은 Python에서 pykiwoom 또는 KOAPY 사용
public export
interface KiwoomAPI where
  ||| API 인증 (로그인)
  authenticate : KiwoomAuth -> IO (DataResult ())

  ||| GADT를 사용한 타입 안전 요청
  ||| 요청 타입에 따라 자동으로 올바른 반환 타입 보장
  executeRequest : KiwoomRequest a -> IO (DataResult a)

  ||| 종목 리스트 조회 (헬퍼 함수)
  getStockList : Market -> IO (DataResult (List Stock))
  getStockList market = executeRequest (ReqStockList market)

  ||| 일봉 조회 (헬퍼 함수)
  getDailyCandles : StockCode -> DateRange -> IO (DataResult (List Candle))
  getDailyCandles code range = executeRequest (ReqDailyCandles code range)

  ||| 분봉 조회 (헬퍼 함수)
  ||| 타입 시스템이 분봉 타임프레임만 허용하도록 강제
  getMinuteCandles : StockCode -> DateRange -> (tf : Timeframe) ->
                     {auto prf : isMinuteFrame tf = True} ->
                     IO (DataResult (List Candle))
  getMinuteCandles code range tf = executeRequest (ReqMinuteCandles code range tf)

--------------------------------------------------------------------------------
-- Python 구현 가이드
--------------------------------------------------------------------------------

export
pythonGuide : String
pythonGuide = """
=== Python Implementation Guide (Type-Safe) ===

라이브러리 선택:
  - KOAPY: 추천 (CLI 지원, 자동 연속 조회)
  - breadum/kiwoom: 간단함
  - pystockhub/pykiwoom: 커뮤니티 활발

설치:
  pip install koapy

타입 안전 구현 예제:

```python
from typing import TypeVar, Generic, Union, List
from dataclasses import dataclass
from koapy import KiwoomOpenApiPlusContext

T = TypeVar('T')

# GADT 스타일 요청 클래스
@dataclass
class ReqStockList:
    market: str  # '0' (KOSPI) or '10' (KOSDAQ)

@dataclass
class ReqDailyCandles:
    stock_code: str
    start_date: str
    end_date: str

@dataclass
class ReqMinuteCandles:
    stock_code: str
    start_date: str
    end_date: str
    timeframe: int  # 1, 5, 10, 60만 허용

    def __post_init__(self):
        # 런타임 검증 (컴파일 타임에 못하는 것 보완)
        if self.timeframe not in [1, 5, 10, 60]:
            raise ValueError(f"Invalid minute timeframe: {self.timeframe}")

KiwoomRequest = Union[ReqStockList, ReqDailyCandles, ReqMinuteCandles]

class KiwoomAPIImpl:
    def __init__(self):
        self.context = KiwoomOpenApiPlusContext()

    def authenticate(self, account: str, password: str) -> bool:
        # KOAPY는 자동 로그인
        return True

    def execute_request(self, request: KiwoomRequest):
        # 패턴 매칭으로 타입별 처리
        if isinstance(request, ReqStockList):
            codes = self.context.GetCodeListByMarket(request.market)
            return [{'code': c, 'name': self.context.GetMasterCodeName(c)}
                    for c in codes]

        elif isinstance(request, ReqDailyCandles):
            return self.context.GetDailyStockDataAsDataFrame(
                request.stock_code,
                start=request.start_date,
                end=request.end_date
            )

        elif isinstance(request, ReqMinuteCandles):
            return self.context.GetMinuteStockDataAsDataFrame(
                request.stock_code,
                tick_range=request.timeframe,
                start=request.start_date,
                end=request.end_date
            )

# 사용 예제
api = KiwoomAPIImpl()

# 1. 종목 리스트 (타입 보장: List[Dict])
stocks = api.execute_request(ReqStockList(market='0'))

# 2. 일봉 (타입 보장: DataFrame)
daily = api.execute_request(ReqDailyCandles('005930', '20240101', '20250101'))

# 3. 분봉 (타입 검증: 60만 허용)
minute = api.execute_request(ReqMinuteCandles('005930', '20240101', '20250101', 60))

# 4. 잘못된 타임프레임 → ValueError
# minute = api.execute_request(ReqMinuteCandles('005930', '20240101', '20250101', 99))  # Error!
```

주의사항:
  - Rate Limit: 초당 5회 제한 (RateLimit.idr 참조)
  - 연속 조회: 600일/900개 제한 → 자동 분할 필요
  - Windows 전용: OpenAPI는 ActiveX 기반
"""
