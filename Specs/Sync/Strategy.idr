module Specs.Sync.Strategy

import Specs.Core.Types
import Specs.Core.ErrorTypes

%default total

--------------------------------------------------------------------------------
-- Windows → Mac 데이터 동기화 전략
-- 목적: 3가지 방식 비교 및 선택 가이드
--------------------------------------------------------------------------------

||| 동기화 전송 방식
public export
data SyncStrategy
  = TimescaleReplication  -- PostgreSQL WAL 스트리밍 복제
  | RsyncOverSSH          -- 파일 기반 rsync 전송
  | HybridApproach        -- SQLite 버퍼 + Parquet + rsync

public export
Show SyncStrategy where
  show TimescaleReplication = "TimescaleDB Streaming Replication"
  show RsyncOverSSH = "Rsync over SSH"
  show HybridApproach = "Hybrid (SQLite + Parquet + Rsync)"

||| 동기화 설정
public export
record SyncConfig where
  constructor MkSyncConfig
  strategy : SyncStrategy
  sourceHost : String       -- Windows PC (로그 제피러스)
  targetHost : String       -- M3 Max
  syncIntervalMinutes : Nat -- 동기화 주기 (분)

||| 각 전략의 특성
public export
record StrategyCharacteristics where
  constructor MkCharacteristics
  latency : String          -- 지연 시간
  complexity : String       -- 설정 복잡도
  reliability : String      -- 안정성
  resourceUsage : String    -- 리소스 사용량

||| TimescaleDB Replication 특성
public export
timescaleReplicationChar : StrategyCharacteristics
timescaleReplicationChar = MkCharacteristics
  "실시간 (초 단위)"
  "높음 (양쪽 DB 설치)"
  "매우 높음 (PostgreSQL WAL)"
  "중간 (네트워크 대역폭)"

||| Rsync over SSH 특성
public export
rsyncOverSSHChar : StrategyCharacteristics
rsyncOverSSHChar = MkCharacteristics
  "중간 (1시간 단위)"
  "낮음 (간단한 스크립트)"
  "높음 (파일 기반)"
  "낮음 (증분 전송)"

||| Hybrid Approach 특성 (추천)
public export
hybridApproachChar : StrategyCharacteristics
hybridApproachChar = MkCharacteristics
  "중간 (1시간 단위)"
  "중간 (SQLite + 스크립트)"
  "매우 높음 (파일 손실 없음)"
  "낮음 (Parquet 압축)"

||| 전략 선택 헬퍼
||| 10분봉 단타용 → Hybrid 추천
public export
recommendStrategy : Nat -> SyncStrategy
recommendStrategy latencyRequirementMinutes =
  if latencyRequirementMinutes < 10
    then TimescaleReplication  -- 실시간 필요
    else HybridApproach        -- 1시간 지연 허용

||| 네트워크 설정 (SSH)
public export
record NetworkConfig where
  constructor MkNetworkConfig
  sshUser : String
  sshHost : String
  sshPort : Nat
  sshKeyPath : String  -- 비밀번호 없는 키 인증

||| 동기화 상태
public export
record SyncState where
  constructor MkSyncState
  lastSyncTime : Integer        -- Unix timestamp
  totalBytesSynced : Nat
  failedAttempts : Nat
  currentlySyncing : Bool

||| 동기화 결과
public export
data SyncResult
  = SyncSuccess Nat              -- 전송된 바이트 수
  | SyncPartial Nat (List String)  -- 부분 성공 (일부 파일 실패)
  | SyncFailure SyncError        -- 완전 실패

--------------------------------------------------------------------------------
-- Python 구현 가이드
--------------------------------------------------------------------------------

export
pythonGuide : String
pythonGuide = """
=== Sync Strategy Implementation ===

추천: Hybrid Approach
  이유:
    1. Windows는 수집만 (가볍게)
    2. Mac에서 무거운 작업 (128GB RAM 활용)
    3. 파일 기반 = 재처리 가능
    4. 1시간 지연 허용 (10분봉 단타에 충분)

```python
from enum import Enum
from dataclasses import dataclass
from typing import Optional
import subprocess
from pathlib import Path

class SyncStrategy(Enum):
    TIMESCALE_REPLICATION = "timescale"
    RSYNC_OVER_SSH = "rsync"
    HYBRID = "hybrid"

@dataclass
class NetworkConfig:
    ssh_user: str
    ssh_host: str
    ssh_port: int = 22
    ssh_key_path: str = "~/.ssh/id_rsa"

@dataclass
class SyncConfig:
    strategy: SyncStrategy
    source_host: str
    target_host: str
    sync_interval_minutes: int
    network: NetworkConfig

    @classmethod
    def create_hybrid_config(cls, ssh_user: str, mac_ip: str):
        \"\"\"Hybrid 전략 기본 설정\"\"\"
        return cls(
            strategy=SyncStrategy.HYBRID,
            source_host="localhost",  # Windows
            target_host=mac_ip,
            sync_interval_minutes=60,
            network=NetworkConfig(
                ssh_user=ssh_user,
                ssh_host=mac_ip,
                ssh_port=22,
                ssh_key_path=str(Path.home() / ".ssh" / "id_rsa")
            )
        )

class SyncOrchestrator:
    def __init__(self, config: SyncConfig):
        self.config = config

    def sync(self):
        \"\"\"전략에 따른 동기화 실행\"\"\"
        if self.config.strategy == SyncStrategy.TIMESCALE_REPLICATION:
            return self.sync_timescale()
        elif self.config.strategy == SyncStrategy.RSYNC_OVER_SSH:
            return self.sync_rsync()
        elif self.config.strategy == SyncStrategy.HYBRID:
            return self.sync_hybrid()

    def sync_timescale(self):
        \"\"\"TimescaleDB Replication (자동 동기화)\"\"\"
        # PostgreSQL 설정으로 자동 처리
        # 별도 구현 불필요 (설정만 필요)
        print("TimescaleDB replication running automatically")

    def sync_rsync(self):
        \"\"\"Rsync over SSH\"\"\"
        # FileExport.idr 참조
        cmd = [
            "rsync",
            "-avz",
            "--progress",
            "C:/KiwoomData/parquet/",
            f"{self.config.network.ssh_user}@{self.config.network.ssh_host}:/Volumes/Data/KiwoomData/"
        ]
        subprocess.run(cmd, check=True)

    def sync_hybrid(self):
        \"\"\"Hybrid Approach\"\"\"
        # 1. SQLite → Parquet 변환 (FileExport.idr 참조)
        # 2. Rsync 전송 (NetworkTransfer.idr 참조)
        print("Hybrid sync: SQLite → Parquet → Rsync")

# 사용 예제
config = SyncConfig.create_hybrid_config(
    ssh_user="joonho.lee",
    mac_ip="192.168.1.100"  # M3 Max IP
)

orchestrator = SyncOrchestrator(config)

# 스케줄링 (1시간마다)
import schedule
import time

schedule.every().hour.do(orchestrator.sync)

while True:
    schedule.run_pending()
    time.sleep(60)
```

전략별 설정 가이드:

1. TimescaleDB Replication:
   - Windows: TimescaleDB 설치 (Primary)
   - Mac: TimescaleDB 설치 (Replica)
   - postgresql.conf 수정 (WAL 설정)
   - 자동 동기화 (별도 스크립트 불필요)

2. Rsync over SSH:
   - Windows: rsync 설치 (Cygwin 또는 WSL)
   - Mac: SSH 서버 활성화
   - 공개키 인증 설정
   - Python 스크립트로 주기적 실행

3. Hybrid (추천):
   - Windows: SQLite (수집 버퍼)
   - Parquet 변환 (1시간마다)
   - Rsync 전송
   - Mac: TimescaleDB 로드
"""
