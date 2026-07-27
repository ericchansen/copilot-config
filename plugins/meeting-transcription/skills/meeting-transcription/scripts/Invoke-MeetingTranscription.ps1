[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$VideoPath,

    [string]$OutputDirectory,

    [string]$ToolRoot,

    [ValidateRange(1, 50)]
    [int]$MinSpeakers = 2,

    [ValidateRange(1, 50)]
    [int]$MaxSpeakers = 12,

    [string]$Language = "en",

    [string]$Model = "large-v3",

    [ValidateRange(1, 128)]
    [int]$BatchSize = 16,

    [switch]$ForceTranscription,

    [switch]$ResetSpeakerMap,

    [switch]$AcceptSpeakerMapForChangedTranscript
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

function Get-VenvCommand {
    param(
        [string]$VenvRoot,
        [ValidateSet("python", "whisperx")]
        [string]$Command
    )

    $windowsName = if ($Command -eq "python") { "python.exe" } else { "whisperx.exe" }
    $candidates = @(
        (Join-Path (Join-Path $VenvRoot "Scripts") $windowsName)
        (Join-Path (Join-Path $VenvRoot "bin") $Command)
    )
    return $candidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}

if ($MinSpeakers -gt $MaxSpeakers) {
    throw "MinSpeakers cannot be greater than MaxSpeakers."
}

$resolvedVideo = (Resolve-Path -LiteralPath $VideoPath).Path
$baseName = [IO.Path]::GetFileNameWithoutExtension($resolvedVideo)
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path ([IO.Path]::GetDirectoryName($resolvedVideo)) "$baseName transcript"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$rawDirectory = Join-Path $OutputDirectory "raw"
$audio = Join-Path $OutputDirectory "$baseName.audio-16k-mono.wav"
$transcriptJson = Join-Path $rawDirectory "$baseName.audio-16k-mono.json"
$speakerMap = Join-Path $OutputDirectory "speaker-map.json"
$outputStem = Join-Path $OutputDirectory "$baseName - Speaker Transcript"

$setup = Join-Path $PSScriptRoot "Setup-MeetingTranscription.ps1"
$toolRoot = Resolve-ToolRoot -RequestedRoot $ToolRoot
$venv = Join-Path $toolRoot ".venv"

& $setup -ToolRoot $toolRoot

$python = Get-VenvCommand -VenvRoot $venv -Command "python"
$whisperx = Get-VenvCommand -VenvRoot $venv -Command "whisperx"
if (-not $python -or -not $whisperx) {
    throw "Meeting transcription executables are missing under '$venv'."
}

New-Item -ItemType Directory -Force -Path $OutputDirectory, $rawDirectory | Out-Null

if ($ForceTranscription -or -not (Test-Path -LiteralPath $transcriptJson)) {
    if ($ForceTranscription -or -not (Test-Path -LiteralPath $audio)) {
        Write-Host "Extracting normalized mono audio..."
        & ffmpeg -hide_banner -loglevel error -y -i $resolvedVideo `
            -vn -ac 1 -ar 16000 -c:a pcm_s16le $audio
        if ($LASTEXITCODE -ne 0) {
            throw "Audio extraction failed."
        }
    } else {
        Write-Host "Reusing existing audio: $audio"
    }

    $token = [Environment]::GetEnvironmentVariable("HF_TOKEN")
    if ([string]::IsNullOrWhiteSpace($token)) {
        $huggingFaceHome = [Environment]::GetEnvironmentVariable("HF_HOME")
        if ([string]::IsNullOrWhiteSpace($huggingFaceHome)) {
            $cacheHome = [Environment]::GetEnvironmentVariable("XDG_CACHE_HOME")
            if ([string]::IsNullOrWhiteSpace($cacheHome)) {
                $cacheHome = Join-Path $HOME ".cache"
            }
            $huggingFaceHome = Join-Path $cacheHome "huggingface"
        }
        $tokenPath = Join-Path $huggingFaceHome "token"
        if (Test-Path -LiteralPath $tokenPath) {
            $token = (Get-Content -Raw -LiteralPath $tokenPath).Trim()
        }
    }
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Hugging Face access is required for diarization. Log in with 'hf auth login' first."
    }

    $torchLibOutput = & $python -c "import os, torch; print(os.path.join(os.path.dirname(torch.__file__), 'lib'))"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not locate PyTorch CUDA libraries."
    }
    $torchLib = ($torchLibOutput | Select-Object -Last 1).Trim()

    $cudaBinCandidates = @()
    $cudaPath = [Environment]::GetEnvironmentVariable("CUDA_PATH")
    if (-not [string]::IsNullOrWhiteSpace($cudaPath)) {
        $cudaBinCandidates += Join-Path $cudaPath "bin"
    }

    $programFiles = [Environment]::GetEnvironmentVariable("ProgramFiles")
    if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
        $cudaRoot = Join-Path $programFiles "NVIDIA GPU Computing Toolkit\CUDA"
        if (Test-Path -LiteralPath $cudaRoot) {
            $cudaBinCandidates += Get-ChildItem -LiteralPath $cudaRoot `
                -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object { Join-Path $_.FullName "bin" }
        }
    }
    $cudaBinCandidates += "/usr/local/cuda/bin"
    $cudaBin = $cudaBinCandidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1

    $pathParts = @($torchLib)
    if ($cudaBin) {
        $pathParts += $cudaBin
    }
    $currentPath = [Environment]::GetEnvironmentVariable("PATH")
    if (-not [string]::IsNullOrWhiteSpace($currentPath)) {
        $pathParts += $currentPath
    }
    $log = Join-Path $rawDirectory "whisperx-full.log"
    $arguments = @(
        $audio,
        "--model", $Model,
        "--device", "cuda",
        "--compute_type", "float16",
        "--language", $Language,
        "--batch_size", $BatchSize,
        "--diarize",
        "--min_speakers", $MinSpeakers,
        "--max_speakers", $MaxSpeakers,
        "--output_dir", $rawDirectory,
        "--output_format", "all",
        "--verbose", "False",
        "--print_progress", "True"
    )

    $environment = @{
        PATH = $pathParts -join [IO.Path]::PathSeparator
        HF_TOKEN = $token
        HF_HUB_DISABLE_TELEMETRY = "1"
        PYANNOTE_METRICS_ENABLED = "0"
        DO_NOT_TRACK = "1"
    }
    $originalEnvironment = @{}
    foreach ($name in $environment.Keys) {
        $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable(
            $name,
            [EnvironmentVariableTarget]::Process
        )
    }

    $whisperxExitCode = $null
    try {
        foreach ($name in $environment.Keys) {
            [Environment]::SetEnvironmentVariable(
                $name,
                $environment[$name],
                [EnvironmentVariableTarget]::Process
            )
        }

        Write-Host "Running local transcription and speaker diarization..."
        & $whisperx @arguments 2>&1 | Tee-Object -FilePath $log
        $whisperxExitCode = $LASTEXITCODE
    } finally {
        foreach ($name in $originalEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable(
                $name,
                $originalEnvironment[$name],
                [EnvironmentVariableTarget]::Process
            )
        }
    }

    if ($whisperxExitCode -ne 0) {
        throw "WhisperX failed. See $log"
    }
} else {
    Write-Host "Reusing existing diarized transcript: $transcriptJson"
}

$reviewArguments = @(
    (Join-Path $PSScriptRoot "prepare_speaker_review.py"),
    "--video", $resolvedVideo,
    "--transcript", $transcriptJson,
    "--output-dir", $OutputDirectory
)
if ($ResetSpeakerMap) {
    $reviewArguments += "--reset-speaker-map"
}
if ($AcceptSpeakerMapForChangedTranscript) {
    $reviewArguments += "--accept-transcript-change"
}
& $python @reviewArguments
if ($LASTEXITCODE -ne 0) {
    throw "Speaker review preparation failed."
}

& $python (Join-Path $PSScriptRoot "render_transcript.py") `
    --transcript $transcriptJson `
    --config $speakerMap `
    --output-stem $outputStem
if ($LASTEXITCODE -ne 0) {
    throw "Transcript rendering failed."
}

Write-Host ""
Write-Host "Meeting artifacts are ready:"
Write-Host "  Review:     $(Join-Path $OutputDirectory 'speaker-review.md')"
Write-Host "  Map:        $speakerMap"
Write-Host "  Transcript: $outputStem.md"
Write-Host "  Raw data:   $rawDirectory"
