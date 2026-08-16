# Registers a weekly Windows Task Scheduler job that retrains the Tier B
# model (prepare_tier_b_data.py + train_tier_b.py) so it stays fresh as
# more/better data becomes available.
#
# IMPORTANT: this only keeps ai/models/tier_b_regressor.tflite fresh on THIS
# machine (which is also what the backend serves for OTA download — see
# back-end/src/services/model.service.js). It does NOT rebuild or
# redistribute the Flutter app. Already-installed app copies pick up a new
# model via their own periodic OTA check
# (front-end/lib/services/tier_b_inference_service.dart), not an app update.
#
# Usage:
#   .\schedule_retrain.ps1            # registers the weekly scheduled task
#   .\schedule_retrain.ps1 -RunJob    # runs the retrain job immediately (also what the scheduled task itself calls)

param(
    [switch]$RunJob
)

$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath -Parent
# .venv lives in ai/ (shared with the receipt-NER notebooks), one level up
# from this script's own ai/tier_b/ location.
$aiDir = Split-Path $scriptDir -Parent
$pythonExe = Join-Path $aiDir ".venv\Scripts\python.exe"

if ($RunJob) {
    if (-not (Test-Path $pythonExe)) {
        Write-Error "Virtualenv not found at $pythonExe — run 'python -m venv .venv; pip install -r requirements.txt' in ai/ first."
        exit 1
    }

    Push-Location $scriptDir
    try {
        & $pythonExe prepare_tier_b_data.py
        & $pythonExe train_tier_b.py
    } finally {
        Pop-Location
    }
    exit 0
}

$taskName = "ExpenseTracker-TierB-Retrain"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -RunJob" `
    -WorkingDirectory $scriptDir
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
    -Description "Retrains the Tier B spend-forecast model weekly (ai/train_tier_b.py)." -Force

Write-Host "Registered scheduled task '$taskName' to run weekly (Sundays 3am)."
Write-Host "Run the retrain job immediately with: .\schedule_retrain.ps1 -RunJob"
