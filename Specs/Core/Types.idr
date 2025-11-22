module Specs.Core.Types

%default total

--------------------------------------------------------------------------------
-- 핵심 데이터 타입 정의
-- 목적: Kiwoom 증권 데이터의 기본 구조 정의
--------------------------------------------------------------------------------

||| 주식 종목 코드 (6자리 숫자)
||| 예: "005930" (삼성전자), "000660" (SK하이닉스)
public export
StockCode : Type
StockCode = String

||| 시장 구분
public export
data Market = KOSPI | KOSDAQ

public export
Show Market where
  show KOSPI = "KOSPI"
  show KOSDAQ = "KOSDAQ"

||| 주식 종목 정보
public export
record Stock where
  constructor MkStock
  code : StockCode
  name : String
  market : Market  -- KOSPI or KOSDAQ

||| OHLCV - 캔들 데이터의 핵심
||| Open, High, Low, Close, Volume
public export
record OHLCV where
  constructor MkOHLCV
  openPrice : Double      -- 시가
  highPrice : Double      -- 고가
  lowPrice : Double       -- 저가
  closePrice : Double     -- 종가
  volume : Nat            -- 거래량

||| 캔들스틱 데이터 (1개 시간봉)
public export
record Candle where
  constructor MkCandle
  stock : StockCode
  timestamp : Integer  -- Unix timestamp
  ohlcv : OHLCV

||| 기술적 지표
||| RSI, MACD, Bollinger Bands 등
public export
record TechnicalIndicators where
  constructor MkIndicators
  rsi : Maybe Double           -- RSI (0~100)
  macd : Maybe Double          -- MACD
  macd_signal : Maybe Double   -- MACD 시그널
  bb_upper : Maybe Double      -- 볼린저 밴드 상단
  bb_lower : Maybe Double      -- 볼린저 밴드 하단

||| 완전한 시장 데이터 포인트
||| OHLCV + 기술적 지표
public export
record MarketDataPoint where
  constructor MkDataPoint
  candle : Candle
  indicators : TechnicalIndicators
