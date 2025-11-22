module Specs.Core.TimeTypes

import Data.List

%default total

--------------------------------------------------------------------------------
-- 시간 관련 타입 정의
-- 목적: 캔들 주기, 날짜 범위, 슬라이딩 윈도우 정의
--------------------------------------------------------------------------------

||| 캔들 주기 (Timeframe)
||| 1분봉, 5분봉, 10분봉, 60분봉, 일봉
public export
data Timeframe
  = Tick            -- 틱 데이터
  | Min1            -- 1분봉
  | Min5            -- 5분봉
  | Min10           -- 10분봉 (주요 타겟)
  | Min60           -- 60분봉
  | Daily           -- 일봉

public export
Show Timeframe where
  show Tick = "Tick"
  show Min1 = "1분봉"
  show Min5 = "5분봉"
  show Min10 = "10분봉"
  show Min60 = "60분봉"
  show Daily = "일봉"

||| 시간프레임을 분 단위로 변환
public export
timeframeToMinutes : Timeframe -> Nat
timeframeToMinutes Tick = 0
timeframeToMinutes Min1 = 1
timeframeToMinutes Min5 = 5
timeframeToMinutes Min10 = 10
timeframeToMinutes Min60 = 60
timeframeToMinutes Daily = 1440  -- 24 * 60

||| 날짜 범위 (시작일 ~ 종료일)
||| 예: 2005-01-01 ~ 2025-01-01 (20년)
public export
record DateRange where
  constructor MkDateRange
  startDate : Integer  -- Unix timestamp
  endDate : Integer    -- Unix timestamp

||| 슬라이딩 윈도우 크기
||| 연구 결과: 60~120개 캔들이 최적
public export
data WindowSize
  = Small   -- 60개 캔들 (10분봉 기준 10시간)
  | Medium  -- 90개 캔들 (15시간)
  | Large   -- 120개 캔들 (20시간)

public export
windowSizeToNat : WindowSize -> Nat
windowSizeToNat Small = 60
windowSizeToNat Medium = 90
windowSizeToNat Large = 120

||| 슬라이딩 윈도우 설정
public export
record SlidingWindowConfig where
  constructor MkWindowConfig
  size : WindowSize
  stride : Nat  -- 윈도우 이동 간격 (기본 1)
  timeframe : Timeframe

||| 거래 시간 정의 (한국 증시)
||| 09:00 ~ 15:30 (6시간 30분 = 390분)
public export
record TradingHours where
  constructor MkTradingHours
  openTime : (Nat, Nat)    -- (9, 0)
  closeTime : (Nat, Nat)   -- (15, 30)

||| 한국 증시 기본 거래시간
public export
koreanMarketHours : TradingHours
koreanMarketHours = MkTradingHours (9, 0) (15, 30)

||| 하루 거래 시간 내 10분봉 개수
||| 09:00 ~ 15:30 = 390분 / 10분 = 39개
public export
candlesPerDay : Timeframe -> Nat
candlesPerDay Min10 = 39
candlesPerDay Min1 = 390
candlesPerDay Daily = 1
candlesPerDay _ = 0  -- 다른 주기는 계산 필요
