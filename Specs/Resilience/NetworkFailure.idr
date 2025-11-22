module Specs.Resilience.NetworkFailure

import Specs.Core.ErrorTypes

%default total

--------------------------------------------------------------------------------
-- 네트워크 장애 대응 (Windows ↔ Mac 연결 끊김)
-- 목적: 두 컴퓨터가 독립적으로 동작하다가 재연결 시 동기화
--------------------------------------------------------------------------------

||| 시스템 상태
public export
data SystemState
  = Connected      -- 정상 연결
  | Disconnected   -- 연결 끊김
  | Reconnecting   -- 재연결 중

public export
Show SystemState where
  show Connected = "Connected"
  show Disconnected = "Disconnected"
  show Reconnecting = "Reconnecting"

||| 호스트 역할
public export
data HostRole
  = WindowsCollector   -- Windows (데이터 수집)
  | MacAnalyzer        -- Mac (분석 + 백테스팅)

||| 연결 확인 방식
public export
data ConnectionCheckMethod
  = ICMP             -- Ping (방화벽에 막힐 수 있음)
  | TCPPort Nat      -- TCP 포트 체크 (더 안정적)

||| 기본 연결 확인: SSH 포트 (22)
public export
defaultCheckMethod : ConnectionCheckMethod
defaultCheckMethod = TCPPort 22

||| 연결 끊김 시 각 호스트의 동작
public export
record OfflineStrategy (role : HostRole) where
  constructor MkOfflineStrategy
  continueWork : Bool          -- 작업 계속 여부
  bufferData : Bool            -- 데이터 버퍼링 여부
  maxBufferSize : Nat          -- 최대 버퍼 크기 (MB)

||| Windows 오프라인 전략
public export
windowsOfflineStrategy : OfflineStrategy WindowsCollector
windowsOfflineStrategy = MkOfflineStrategy
  True   -- 수집 계속
  True   -- SQLite 버퍼링
  10000  -- 10GB

||| Mac 오프라인 전략
public export
macOfflineStrategy : OfflineStrategy MacAnalyzer
macOfflineStrategy = MkOfflineStrategy
  True   -- 백테스팅 계속
  False  -- 버퍼링 불필요
  0      -- 버퍼 없음

||| 재연결 프로토콜
public export
record ReconnectionProtocol where
  constructor MkReconnection
  checkIntervalSeconds : Nat    -- 재연결 시도 간격
  maxRetries : Nat              -- 최대 재시도 횟수
  backoffMultiplier : Double    -- Exponential backoff

||| 기본 재연결 설정
public export
defaultReconnection : ReconnectionProtocol
defaultReconnection = MkReconnection
  30     -- 30초마다 확인
  999    -- 무한 재시도
  1.5    -- 1.5배씩 증가

||| 동기화 재개 전략 (Throttling 포함)
public export
record SyncResume where
  constructor MkSyncResume
  lastSyncTime : Integer        -- 마지막 동기화 시각
  pendingFiles : List String    -- 대기 중인 파일들
  batchSize : Nat               -- 한 번에 보낼 파일 수 (10개)
  batchIntervalMs : Nat         -- 배치 간 휴식 시간 (1000ms)

||| 기본 동기화 재개 설정
public export
defaultSyncResume : SyncResume
defaultSyncResume = MkSyncResume
  0       -- 초기값
  []      -- 파일 없음
  10      -- 10개씩
  1000    -- 1초 대기

--------------------------------------------------------------------------------
-- Python 구현 가이드 (Socket Check + Throttling)
--------------------------------------------------------------------------------

export
pythonGuide : String
pythonGuide = """
=== Advanced Resilience Implementation (TCP Port + Throttling) ===

핵심 변경:
  1. Ping → TCP Port 22 체크 (방화벽 우회)
  2. 밀린 데이터 전송 시 Throttling (네트워크 보호)

```python
import time
import socket
import polars as pl
from pathlib import Path
from dataclasses import dataclass
from enum import Enum

class SystemState(Enum):
    CONNECTED = "connected"
    DISCONNECTED = "disconnected"
    RECONNECTING = "reconnecting"

class HostRole(Enum):
    WINDOWS_COLLECTOR = "windows"
    MAC_ANALYZER = "mac"

@dataclass
class OfflineStrategy:
    continue_work: bool
    buffer_data: bool
    max_buffer_mb: int

@dataclass
class SyncResume:
    last_sync_time: int
    pending_files: list
    batch_size: int = 10
    batch_interval_ms: int = 1000

class ResilienceManager:
    def __init__(self, role: HostRole):
        self.role = role
        self.state = SystemState.CONNECTED
        self.sync_resume = SyncResume(
            last_sync_time=0,
            pending_files=[],
            batch_size=10,
            batch_interval_ms=1000
        )

        # 오프라인 전략
        if role == HostRole.WINDOWS_COLLECTOR:
            self.strategy = OfflineStrategy(
                continue_work=True,
                buffer_data=True,
                max_buffer_mb=10000
            )
        else:  # MAC_ANALYZER
            self.strategy = OfflineStrategy(
                continue_work=True,
                buffer_data=False,
                max_buffer_mb=0
            )

    def check_connection(self, remote_host: str, port: int = 22) -> bool:
        \"\"\"TCP 포트 접속 테스트 (Ping보다 정확함)\"\"\"
        try:
            with socket.create_connection((remote_host, port), timeout=2):
                return True
        except (socket.timeout, ConnectionRefusedError, OSError):
            return False

    def handle_disconnection(self):
        \"\"\"연결 끊김 시 동작\"\"\"
        self.state = SystemState.DISCONNECTED

        if self.role == HostRole.WINDOWS_COLLECTOR:
            print("📡 Connection lost. Buffering data to SQLite...")
            # SQLite에 계속 저장
        else:  # MAC_ANALYZER
            print("📡 Connection lost. Using cached data...")
            # 기존 데이터로 백테스팅만 계속

    def handle_reconnection(self):
        \"\"\"재연결 시 동기화 재개 (Throttling 적용)\"\"\"
        self.state = SystemState.RECONNECTING

        if self.role == HostRole.WINDOWS_COLLECTOR:
            print("🔄 Reconnected! Starting incremental sync...")

            # 1. 버퍼링된 데이터 Parquet 변환
            self.export_buffered_data()

            # 2. 밀린 파일 전송 (Throttling)
            self.resume_sync()

        self.state = SystemState.CONNECTED

    def get_pending_files(self) -> list:
        \"\"\"마지막 동기화 이후 생성된 파일들\"\"\"
        parquet_dir = Path('C:/KiwoomData/parquet')
        all_files = list(parquet_dir.rglob('*.parquet'))

        # 마지막 동기화 이후 파일만
        pending = [
            str(f) for f in all_files
            if f.stat().st_mtime > self.sync_resume.last_sync_time
        ]

        return pending

    def resume_sync(self):
        \"\"\"밀린 데이터 전송 (Throttling 적용)\"\"\"
        pending_files = self.get_pending_files()

        if not pending_files:
            print("✅ No pending files to sync")
            return

        print(f"📦 Found {len(pending_files)} pending files")

        # 배치 단위로 전송
        batch_size = self.sync_resume.batch_size

        for i in range(0, len(pending_files), batch_size):
            batch = pending_files[i:i+batch_size]
            batch_num = i // batch_size + 1
            total_batches = (len(pending_files) + batch_size - 1) // batch_size

            print(f"📤 Syncing batch {batch_num}/{total_batches} "
                  f"({len(batch)} files)...")

            for file in batch:
                # NetworkTransfer.idr 참조
                self.transfer_file(file)

            # 네트워크 숨 고르기 (Throttling)
            if i + batch_size < len(pending_files):
                wait_sec = self.sync_resume.batch_interval_ms / 1000.0
                print(f"⏸️  Waiting {wait_sec}s before next batch...")
                time.sleep(wait_sec)

        # 동기화 완료
        self.sync_resume.last_sync_time = int(time.time())
        print(f"✅ Sync completed: {len(pending_files)} files")

    def export_buffered_data(self):
        \"\"\"버퍼링된 데이터를 Parquet로 변환\"\"\"
        # SQLite → Parquet (FileExport.idr 참조)
        print("🔄 Exporting buffered data...")
        # 구현...

    def transfer_file(self, file_path: str):
        \"\"\"파일 전송 (체크섬 검증 포함)\"\"\"
        # NetworkTransfer.idr 참조
        # SFTP + Checksum 검증
        pass

    def run_monitoring_loop(self, remote_host: str, port: int = 22):
        \"\"\"연결 상태 모니터링 루프\"\"\"
        retry_count = 0
        interval = 30  # seconds

        while True:
            is_connected = self.check_connection(remote_host, port)

            if is_connected and self.state != SystemState.CONNECTED:
                # 재연결됨
                self.handle_reconnection()
                retry_count = 0
                interval = 30

            elif not is_connected and self.state == SystemState.CONNECTED:
                # 연결 끊김
                self.handle_disconnection()
                retry_count = 0

            elif not is_connected:
                # 계속 끊김 (Exponential backoff)
                retry_count += 1
                interval = min(30 * (1.5 ** retry_count), 300)  # 최대 5분
                print(f"⏳ Retry {retry_count}, next check in {interval:.0f}s")

            time.sleep(interval)

# Windows 사용 예제
manager = ResilienceManager(HostRole.WINDOWS_COLLECTOR)

# 백그라운드 스레드로 모니터링
import threading
monitor_thread = threading.Thread(
    target=manager.run_monitoring_loop,
    args=('192.168.1.100', 22),  # Mac IP + SSH port
    daemon=True
)
monitor_thread.start()

# 메인 작업 (데이터 수집) 계속
while True:
    # Kiwoom 데이터 수집
    collect_data()

    # 연결 상태에 따라 동기화 또는 버퍼링
    if manager.state == SystemState.CONNECTED:
        sync_to_mac()
    else:
        buffer_to_sqlite()

    time.sleep(60)
```

핵심 원칙:
  1. **Never Stop**: 연결 끊겨도 각자 작업 계속
  2. **Buffer Everything**: Windows는 SQLite에 버퍼링
  3. **Incremental Sync**: 재연결 시 차이분만 동기화
  4. **Throttling**: 배치 전송 (10개씩, 1초 대기)
  5. **TCP Port Check**: Ping 대신 SSH 포트 확인
"""
