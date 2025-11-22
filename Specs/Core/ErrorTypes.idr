module Specs.Core.ErrorTypes

%default total

--------------------------------------------------------------------------------
-- 에러 타입 정의
-- 목적: 시스템 전반의 에러 상황 명시
--------------------------------------------------------------------------------

||| Kiwoom API 호출 에러
public export
data APIError
  = RateLimitExceeded           -- 초당 5회 제한 초과
  | AuthenticationFailed        -- 인증 실패
  | NetworkTimeout              -- 네트워크 타임아웃
  | InvalidStockCode String     -- 잘못된 종목 코드
  | NoDataAvailable             -- 데이터 없음
  | UnknownAPIError String      -- 기타 API 에러

public export
Show APIError where
  show RateLimitExceeded = "Rate limit exceeded (5 req/sec)"
  show AuthenticationFailed = "Kiwoom API authentication failed"
  show NetworkTimeout = "Network timeout"
  show (InvalidStockCode code) = "Invalid stock code: " ++ code
  show NoDataAvailable = "No data available for the requested period"
  show (UnknownAPIError msg) = "Unknown API error: " ++ msg

||| 데이터 검증 에러
public export
data ValidationError
  = InvalidPrice Double         -- 가격 <= 0
  | InvalidVolume Integer       -- 거래량 < 0
  | DateNotContinuous           -- 날짜 불연속
  | DuplicateData               -- 중복 데이터
  | MissingRequiredField String -- 필수 필드 누락

public export
Show ValidationError where
  show (InvalidPrice p) = "Invalid price: " ++ show p ++ " (must be > 0)"
  show (InvalidVolume v) = "Invalid volume: " ++ show v ++ " (must be >= 0)"
  show DateNotContinuous = "Date continuity check failed"
  show DuplicateData = "Duplicate data detected"
  show (MissingRequiredField f) = "Missing required field: " ++ f

||| 데이터베이스 에러
public export
data DatabaseError
  = ConnectionFailed String     -- DB 연결 실패
  | InsertFailed String         -- 삽입 실패
  | QueryFailed String          -- 쿼리 실패
  | TransactionFailed           -- 트랜잭션 실패

public export
Show DatabaseError where
  show (ConnectionFailed msg) = "Database connection failed: " ++ msg
  show (InsertFailed msg) = "Insert operation failed: " ++ msg
  show (QueryFailed msg) = "Query failed: " ++ msg
  show TransactionFailed = "Transaction failed"

||| 파일 동기화 에러
public export
data SyncError
  = FileTransferFailed String   -- 파일 전송 실패
  | SSHConnectionFailed         -- SSH 연결 실패
  | DiskSpaceFull               -- 디스크 공간 부족
  | PermissionDenied String     -- 권한 없음

public export
Show SyncError where
  show (FileTransferFailed msg) = "File transfer failed: " ++ msg
  show SSHConnectionFailed = "SSH connection failed"
  show DiskSpaceFull = "Disk space full"
  show (PermissionDenied path) = "Permission denied: " ++ path

||| 전체 시스템 에러 (합성 타입)
public export
data SystemError
  = API APIError
  | Validation ValidationError
  | Database DatabaseError
  | Sync SyncError

public export
Show SystemError where
  show (API err) = "API Error: " ++ show err
  show (Validation err) = "Validation Error: " ++ show err
  show (Database err) = "Database Error: " ++ show err
  show (Sync err) = "Sync Error: " ++ show err

||| Result 타입 (Either의 명확한 버전)
public export
DataResult : Type -> Type
DataResult a = Either SystemError a
