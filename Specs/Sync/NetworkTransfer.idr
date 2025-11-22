module Specs.Sync.NetworkTransfer

import Specs.Core.ErrorTypes
import Specs.Sync.Strategy
import Data.Nat

%default total

--------------------------------------------------------------------------------
-- 네트워크 파일 전송 (SFTP/Rsync over SSH)
-- 목적: Windows → Mac 안전하고 효율적인 파일 전송 (체크섬 검증)
--------------------------------------------------------------------------------

||| 전송 프로토콜
public export
data TransferProtocol = Rsync | SFTP

public export
Show TransferProtocol where
  show Rsync = "Rsync"
  show SFTP = "SFTP"

||| Windows에서는 SFTP가 더 안정적 (Paramiko 라이브러리)
public export
defaultProtocol : TransferProtocol
defaultProtocol = SFTP

||| 파일 체크섬 (무결성 검증)
public export
record FileChecksum where
  constructor MkChecksum
  hash : String  -- SHA256

||| 체크섬 검증
public export
verifySync : FileChecksum -> FileChecksum -> Bool
verifySync source target = source.hash == target.hash

||| rsync 옵션
public export
record RsyncOptions where
  constructor MkRsyncOptions
  archive : Bool            -- -a (권한, 시간 보존)
  verbose : Bool            -- -v (진행 상황 표시)
  compress : Bool           -- -z (전송 중 압축)
  progress : Bool           -- --progress (진행률)
  delete : Bool             -- --delete (대상에서 삭제된 파일 제거)
  bwlimit : Maybe Nat       -- --bwlimit (대역폭 제한 KB/s)

||| 기본 rsync 옵션 (안전한 설정)
public export
defaultRsyncOptions : RsyncOptions
defaultRsyncOptions = MkRsyncOptions
  True   -- archive
  True   -- verbose
  True   -- compress
  True   -- progress
  False  -- delete (안전을 위해 기본 off)
  Nothing  -- bwlimit (제한 없음)

||| 전송 작업
public export
record TransferTask where
  constructor MkTransferTask
  sourcePath : String       -- Windows 경로
  targetPath : String       -- Mac 경로
  protocol : TransferProtocol
  network : NetworkConfig
  verifyChecksum : Bool     -- 체크섬 검증 여부

||| 전송 상태
public export
data TransferStatus
  = NotStarted
  | InProgress Nat Nat      -- (전송된 바이트, 전체 바이트)
  | Verifying FileChecksum  -- 체크섬 검증 중
  | Completed Nat           -- 전송된 바이트
  | Failed SyncError

public export
Show TransferStatus where
  show NotStarted = "Not Started"
  show (InProgress sent totalBytes) =
    "In Progress: " ++ show sent ++ " / " ++ show totalBytes ++ " bytes"
  show (Verifying checksum) = "Verifying checksum: " ++ checksum.hash
  show (Completed bytes) = "Completed: " ++ show bytes ++ " bytes"
  show (Failed err) = "Failed: " ++ show err

||| 전송 결과
public export
record TransferResult where
  constructor MkTransferResult
  task : TransferTask
  status : TransferStatus
  duration : Nat            -- 소요 시간 (초)
  averageSpeed : Nat        -- 평균 속도 (KB/s)
  checksumVerified : Bool   -- 체크섬 검증 통과 여부

||| 전송 속도 계산
public export
calculateSpeed : Nat -> Nat -> Nat
calculateSpeed bytes seconds =
  if seconds == 0
    then 0
    else (bytes `div` 1024) `div` seconds  -- KB/s

||| SSH 연결 테스트
public export
record SSHConnectionTest where
  constructor MkSSHTest
  host : String
  port : Nat
  user : String
  keyPath : String
  timeout : Nat  -- 초

||| 대역폭 관리 (야간/주간 차등)
public export
data BandwidthPolicy
  = Unlimited
  | DayTime Nat      -- 주간 제한 (KB/s)
  | NightTime Nat    -- 야간 제한 (KB/s)
  | Adaptive         -- 자동 조절

||| 시간대별 대역폭 정책
public export
getBandwidthLimit : Nat -> BandwidthPolicy -> Maybe Nat
getBandwidthLimit currentHour policy =
  case policy of
    Unlimited => Nothing
    DayTime limit => if currentHour >= 9 && currentHour < 18
                       then Just limit
                       else Nothing  -- 야간 무제한
    NightTime limit => if currentHour < 9 || currentHour >= 18
                         then Just limit
                         else Nothing  -- 주간 무제한
    Adaptive => Nothing  -- 구현 필요

--------------------------------------------------------------------------------
-- Python 구현 가이드 (SFTP + 체크섬)
--------------------------------------------------------------------------------

export
pythonGuide : String
pythonGuide = """
=== Network Transfer Implementation (SFTP + Checksum Verification) ===

추천: SFTP (Paramiko 라이브러리)
  이유:
    - Windows 네이티브 지원 (rsync는 WSL 필요)
    - Python만으로 구현 가능
    - 체크섬 검증 용이

```python
import paramiko
import hashlib
from pathlib import Path
from typing import Optional
from dataclasses import dataclass
import time

@dataclass
class FileChecksum:
    hash: str  # SHA256

def calculate_checksum(file_path: str) -> FileChecksum:
    \"\"\"SHA256 체크섬 계산\"\"\"
    sha256 = hashlib.sha256()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            sha256.update(chunk)
    return FileChecksum(hash=sha256.hexdigest())

class SFTPTransfer:
    def __init__(self, ssh_user: str, ssh_host: str,
                 ssh_port: int = 22, ssh_key: str = "~/.ssh/id_rsa"):
        self.ssh_user = ssh_user
        self.ssh_host = ssh_host
        self.ssh_port = ssh_port
        self.ssh_key = Path(ssh_key).expanduser()

    def test_connection(self, timeout: int = 10) -> bool:
        \"\"\"SSH 연결 테스트\"\"\"
        try:
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(
                hostname=self.ssh_host,
                port=self.ssh_port,
                username=self.ssh_user,
                key_filename=str(self.ssh_key),
                timeout=timeout
            )
            ssh.close()
            return True
        except Exception as e:
            print(f"Connection test failed: {e}")
            return False

    def transfer_file(self, local_path: str, remote_path: str,
                      verify_checksum: bool = True) -> bool:
        \"\"\"파일 전송 (Atomic + 체크섬 검증)\"\"\"

        # 1. 연결 테스트
        if not self.test_connection():
            print("SSH connection failed")
            return False

        # 2. 로컬 체크섬 계산
        local_checksum = calculate_checksum(local_path)
        print(f"Local checksum: {local_checksum.hash}")

        try:
            # 3. SFTP 연결
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(
                hostname=self.ssh_host,
                port=self.ssh_port,
                username=self.ssh_user,
                key_filename=str(self.ssh_key)
            )
            sftp = ssh.open_sftp()

            # 4. Atomic 전송 (임시 파일 → 이름 변경)
            temp_path = remote_path + ".tmp"
            start_time = time.time()

            sftp.put(local_path, temp_path)

            # 5. 체크섬 검증
            if verify_checksum:
                remote_checksum = self._remote_checksum(sftp, ssh, temp_path)
                print(f"Remote checksum: {remote_checksum.hash}")

                if not (local_checksum.hash == remote_checksum.hash):
                    print("Checksum mismatch! Aborting transfer")
                    sftp.remove(temp_path)
                    sftp.close()
                    ssh.close()
                    return False

            # 6. Atomic rename (성공 확정)
            sftp.posix_rename(temp_path, remote_path)

            # 7. 통계
            duration = time.time() - start_time
            file_size = Path(local_path).stat().st_size
            speed = (file_size / 1024) / duration if duration > 0 else 0

            print(f"Transfer completed: {file_size / 1024**2:.2f} MB "
                  f"in {duration:.2f}s ({speed:.2f} KB/s)")

            sftp.close()
            ssh.close()
            return True

        except Exception as e:
            print(f"Transfer failed: {e}")
            return False

    def _remote_checksum(self, sftp, ssh, remote_path: str) -> FileChecksum:
        \"\"\"원격 파일 체크섬 계산\"\"\"
        stdin, stdout, stderr = ssh.exec_command(f"sha256sum {remote_path}")
        result = stdout.read().decode().strip()
        # 출력 형식: "hash  filename"
        hash_value = result.split()[0]
        return FileChecksum(hash=hash_value)

    def sync_directory(self, local_dir: str, remote_dir: str,
                       bandwidth_limit: Optional[int] = None):
        \"\"\"디렉토리 전체 동기화\"\"\"
        local_path = Path(local_dir)
        success_count = 0
        fail_count = 0

        for local_file in local_path.rglob('*.parquet'):
            # 상대 경로 유지
            relative = local_file.relative_to(local_path)
            remote_file = f"{remote_dir}/{relative.as_posix()}"

            # 원격 디렉토리 생성
            remote_parent = str(Path(remote_file).parent)
            self._ensure_remote_dir(remote_parent)

            # 전송
            if self.transfer_file(str(local_file), remote_file):
                success_count += 1
            else:
                fail_count += 1

        print(f"Sync completed: {success_count} success, {fail_count} failed")

    def _ensure_remote_dir(self, remote_dir: str):
        \"\"\"원격 디렉토리 생성 (존재하지 않으면)\"\"\"
        try:
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(
                hostname=self.ssh_host,
                port=self.ssh_port,
                username=self.ssh_user,
                key_filename=str(self.ssh_key)
            )
            ssh.exec_command(f"mkdir -p {remote_dir}")
            ssh.close()
        except Exception as e:
            print(f"Failed to create remote directory: {e}")

# SSH 키 설정
'''
Windows (PowerShell):
  1. 키 생성:
     ssh-keygen -t rsa -b 4096
  2. Mac으로 복사:
     type $env:USERPROFILE\.ssh\id_rsa.pub | ssh joonho.lee@192.168.1.100 "cat >> ~/.ssh/authorized_keys"

Mac:
  1. SSH 서버 활성화:
     System Settings > General > Sharing > Remote Login (On)
  2. 방화벽 설정:
     Allow incoming SSH connections
'''

# 사용 예제
transfer = SFTPTransfer(
    ssh_user="joonho.lee",
    ssh_host="192.168.1.100",  # M3 Max IP
    ssh_port=22,
    ssh_key="~/.ssh/id_rsa"
)

# 1시간마다 동기화
import schedule
from datetime import datetime

def hourly_sync():
    # 시간대별 대역폭 제한
    current_hour = datetime.now().hour
    if 9 <= current_hour < 18:
        # 주간: 대역폭 제한 (5MB/s)
        bandwidth = 5000  # KB/s
    else:
        # 야간: 무제한
        bandwidth = None

    transfer.sync_directory(
        local_dir='C:/KiwoomData/parquet/',
        remote_dir='/Volumes/Data/KiwoomData/',
        bandwidth_limit=bandwidth
    )

schedule.every().hour.do(hourly_sync)

while True:
    schedule.run_pending()
    time.sleep(60)
```

최적화 팁:

1. Atomic 전송:
   - 임시 파일로 전송 (.tmp)
   - 성공 시 posix_rename (원자적 연산)
   - 실패 시 임시 파일 삭제

2. 체크섬 검증:
   - 로컬: Python hashlib
   - 원격: ssh.exec_command("sha256sum")
   - 불일치 시 재시도

3. 재시도 로직:
   - 네트워크 끊김 대비
   - exponential backoff

4. 대역폭 관리:
   - 주간: 제한 (업무 영향 최소화)
   - 야간: 무제한 (빠른 전송)

5. SFTP vs Rsync:
   - SFTP: Windows 네이티브, Python만으로 구현
   - Rsync: 더 빠름, WSL 필요
   - 추천: SFTP (안정성)
"""
