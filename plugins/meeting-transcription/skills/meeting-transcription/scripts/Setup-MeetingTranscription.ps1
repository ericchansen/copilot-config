[CmdletBinding()]
param(
    [string]$ToolRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-ToolRoot {
    param([string]$RequestedRoot)

    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        return [IO.Path]::GetFullPath($RequestedRoot)
    }

    $configuredRoot = [Environment]::GetEnvironmentVariable("MEETING_TRANSCRIPTION_HOME")
    if (-not [string]::IsNullOrWhiteSpace($configuredRoot)) {
        return [IO.Path]::GetFullPath($configuredRoot)
    }

    $localShare = Join-Path (Join-Path $HOME ".local") "share"
    return [IO.Path]::GetFullPath((Join-Path $localShare "meeting-transcription"))
}

function Get-VenvPython {
    param([string]$VenvRoot)

    $candidates = @(
        (Join-Path (Join-Path $VenvRoot "Scripts") "python.exe")
        (Join-Path (Join-Path $VenvRoot "bin") "python")
    )
    return $candidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}

foreach ($command in @("uv", "ffmpeg", "ffprobe")) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' is not installed or not available on PATH."
    }
}

$toolRoot = Resolve-ToolRoot -RequestedRoot $ToolRoot
$venv = Join-Path $toolRoot ".venv"
New-Item -ItemType Directory -Force -Path $toolRoot | Out-Null

$python = Get-VenvPython -VenvRoot $venv
if (-not $python) {
    & uv venv --python 3.11 $venv
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create the Python environment."
    }
    $python = Get-VenvPython -VenvRoot $venv
    if (-not $python) {
        throw "The Python environment was created without a usable interpreter."
    }
}

& $python -c "import torch, whisperx; raise SystemExit(0 if torch.cuda.is_available() else 1)" 2>$null
$ready = $LASTEXITCODE -eq 0

if (-not $ready) {
    & uv pip install --python $python whisperx
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install WhisperX."
    }

    & uv pip install --python $python --reinstall `
        --index-url "https://download.pytorch.org/whl/cu128" `
        "torch==2.8.0+cu128" "torchaudio==2.8.0+cu128" "torchvision==0.23.0+cu128"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install CUDA-enabled PyTorch."
    }
}

& $python -c @"
import torch
import whisperx
if not torch.cuda.is_available():
    raise SystemExit("CUDA is unavailable in the meeting transcription environment.")
print(f"Meeting transcription environment ready: torch={torch.__version__}, gpu={torch.cuda.get_device_name(0)}")
"@
if ($LASTEXITCODE -ne 0) {
    throw "Meeting transcription environment validation failed."
}
