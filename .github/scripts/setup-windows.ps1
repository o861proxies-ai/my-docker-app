# Path: .github/scripts/setup-windows.ps1
# Mục đích: Setup môi trường cho Windows runner
#   1. Cài Ubuntu vào WSL2 (nếu chưa có)
#   2. Cài Docker Engine bên trong WSL2
#   3. Cài + chạy ttyd trong WSL2 (expose web terminal qua port 7681)
$ErrorActionPreference = "Stop"

# ── Helper: chạy bash trong WSL2 Ubuntu ──────────────────────────────
function Invoke-WSL {
    param([string]$Script)
    wsl -d Ubuntu -- bash -c $Script
    if ($LASTEXITCODE -ne 0) {
        throw "WSL2 command failed (exit $LASTEXITCODE)"
    }
}

# ── Lấy WSL_WORKSPACE từ GITHUB_ENV ──────────────────────────────────
$wslWorkspace = $env:WSL_WORKSPACE
if (-not $wslWorkspace) {
    throw "WSL_WORKSPACE is not set. Did detect-os.sh run successfully?"
}
Write-Host "WSL_WORKSPACE: $wslWorkspace"

# ════════════════════════════════════════════════════════════════════
#  PHẦN 1 — Kiểm tra và cài Ubuntu vào WSL2
# ════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== [setup-windows] Checking WSL2 distros ==="

# wsl -l output dùng UTF-16LE với null bytes → phải decode đúng
$wslListBytes = [System.Text.Encoding]::Unicode.GetBytes(
    (wsl -l 2>&1 | Out-String)
)
$wslClean = [System.Text.Encoding]::Unicode.GetString($wslListBytes) `
    -replace "`0", "" `
    -replace "\r", ""
Write-Host "Installed distros:"
Write-Host $wslClean

# Cách detect đáng tin hơn: gọi trực tiếp và check exit code
$ubuntuReady = $false
try {
    $testOutput = wsl -d Ubuntu -- echo "probe" 2>&1
    if ($testOutput -match "probe") {
        $ubuntuReady = $true
    }
}
catch {
    $ubuntuReady = $false
}

if (-not $ubuntuReady) {
    Write-Host "Ubuntu not responding — installing..."
    wsl --install -d Ubuntu --no-launch
    if ($LASTEXITCODE -ne 0) {
        throw "wsl --install failed (exit $LASTEXITCODE)"
    }

    Write-Host "Waiting for Ubuntu to initialise (up to 90s)..."
    for ($i = 0; $i -lt 18; $i++) {
        Start-Sleep -Seconds 5
        $check = wsl -d Ubuntu -- echo "ok" 2>$null
        if ("$check" -match "ok") {
            $ubuntuReady = $true
            Write-Host "✅ Ubuntu ready after $(($i+1)*5)s"
            break
        }
        Write-Host "  ... waiting ($( ($i+1)*5 )s)"
    }
    if (-not $ubuntuReady) {
        throw "Ubuntu did not become ready in 90s"
    }
    Write-Host "✅ Ubuntu installed and ready"
}
else {
    Write-Host "✅ Ubuntu already installed and responsive"
}

# ════════════════════════════════════════════════════════════════════
#  PHẦN 2 — Cài Docker Engine bên trong WSL2
# ════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== [setup-windows] Installing Docker Engine in WSL2 ==="

Invoke-WSL @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if command -v docker &>/dev/null; then
  echo "Docker already installed: $(docker --version)"
else
  echo "Installing Docker Engine via get.docker.com..."
  sudo apt-get update -qq
  curl -fsSL https://get.docker.com | sudo sh
  echo "✅ Docker installed: $(docker --version)"
fi

# Start dockerd nếu chưa chạy
if sudo docker info &>/dev/null 2>&1; then
  echo "dockerd already running"
else
  echo "Starting dockerd..."
  sudo dockerd > /tmp/dockerd.log 2>&1 &
  for i in $(seq 1 30); do
    sudo docker info &>/dev/null 2>&1 && break || true
    sleep 1
  done
  sudo docker info &>/dev/null 2>&1 \
    && echo "✅ dockerd is running" \
    || { echo "❌ dockerd failed"; cat /tmp/dockerd.log; exit 1; }
fi

sudo docker info | grep -E "OSType|Server Version"
'@

Write-Host "✅ Docker Linux engine ready in WSL2"

# ════════════════════════════════════════════════════════════════════
#  PHẦN 3 — Cài + chạy ttyd trong WSL2
# ════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== [setup-windows] Installing and starting ttyd in WSL2 ==="

Invoke-WSL @'
set -euo pipefail

if command -v ttyd &>/dev/null; then
  echo "ttyd already installed"
else
  echo "Installing ttyd..."
  sudo apt-get install -y ttyd 2>/dev/null && echo "✅ ttyd via apt" || {
    TTYD_VER="1.7.7"
    echo "Downloading ttyd binary v${TTYD_VER}..."
    sudo curl -fsSL \
      "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VER}/ttyd.x86_64" \
      -o /usr/local/bin/ttyd
    sudo chmod +x /usr/local/bin/ttyd
    echo "✅ ttyd binary installed"
  }
fi

# Stop instance cũ nếu có
pkill -x ttyd 2>/dev/null && echo "Stopped existing ttyd" || true
sleep 1

echo "Starting ttyd on 0.0.0.0:7681..."
nohup ttyd \
  -W \
  -p 7681 \
  -t fontSize=15 \
  -t "theme={\"background\":\"#1e1e1e\"}" \
  bash \
  > /tmp/ttyd.log 2>&1 &

sleep 2

if pgrep -x ttyd > /dev/null; then
  echo "✅ ttyd running (PID=$(pgrep -x ttyd))"
else
  echo "❌ ttyd failed to start"
  cat /tmp/ttyd.log
  exit 1
fi

ss -tlnp | grep 7681 \
  && echo "✅ Port 7681 listening in WSL2" \
  || echo "⚠️  Port 7681 not detected yet"
'@

# ── Verify từ Windows host ────────────────────────────────────────────
Write-Host ""
Write-Host "=== [setup-windows] Verifying port 7681 from Windows host ==="
Start-Sleep -Seconds 3
$portCheck = netstat -ano 2>$null | Select-String ":7681"
if ($portCheck) {
    Write-Host "✅ Port 7681 visible from Windows host"
    Write-Host $portCheck
}
else {
    Write-Host "⚠️  Port 7681 not yet visible — WSL2 auto-forward may take a moment, continuing..."
}

Write-Host ""
Write-Host "✅ [setup-windows] All done"