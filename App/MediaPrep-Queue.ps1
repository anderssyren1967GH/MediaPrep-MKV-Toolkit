#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobFile
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:QueueScriptPath=$MyInvocation.MyCommand.Path
$scriptDir=Split-Path -Parent $script:QueueScriptPath
$root=Split-Path -Parent $scriptDir
$mediaPrep=Join-Path $scriptDir 'MediaPrep.ps1'
$script:SettingsFile=Join-Path (Join-Path $root 'Data') 'start-installningar.json'
$script:OriginalConfigText=$null
$script:ConfigWasOverridden=$false
$script:SleepProtectionActive=$false
$script:UpdateProtectionBackup=$null
$script:ElevationAttempted=$false
$script:VerboseLogging=$false
$script:ShutdownRequested=$false
$script:FinalExitCode=1
$script:StopRequestFile=$null
$script:RunStatsPath=Join-Path (Join-Path $root 'Data') 'queue-run-current.json'
$script:CopyStatsPath=Join-Path (Join-Path $root 'Data') 'queue-copy-stats.json'

function Get-P {
    param(
        [object]$Object,
        [string]$Name,
        [object]$DefaultValue
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Test-IsAdministrator {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-ElevatedIfRequired {
    param([object]$Job)

    $requiresAdministrator = [bool](Get-P $Job 'PreventUpdateRestart' $false)
    if (-not $requiresAdministrator -or (Test-IsAdministrator)) {
        return $false
    }

    Write-Host '[INFO ] Valda inställningar kräver administratörsrättigheter.' -ForegroundColor Cyan
    Write-Host '[INFO ] Windows visar nu en UAC-fråga. Godkänn den för att starta nattkön.' -ForegroundColor Cyan

    $quotedScript = '"' + $script:QueueScriptPath.Replace('"','\"') + '"'
    $quotedJob = '"' + $JobFile.Replace('"','\"') + '"'
    $argumentLine = '-NoProfile -ExecutionPolicy Bypass -File ' + $quotedScript + ' -JobFile ' + $quotedJob

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'powershell.exe'
    $startInfo.Arguments = $argumentLine
    $startInfo.WorkingDirectory = $root
    $startInfo.UseShellExecute = $true
    $startInfo.Verb = 'runas'

    try {
        [System.Diagnostics.Process]::Start($startInfo) | Out-Null
        return $true
    }
    catch [System.ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 1223) {
            throw 'UAC-frågan avbröts. Kön startades inte eftersom administratörsskyddet inte kunde aktiveras.'
        }
        throw
    }
}

function Enable-SleepProtection {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MediaPrepPower {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
'@ -ErrorAction SilentlyContinue
    $ES_CONTINUOUS = [Convert]::ToUInt32('80000000', 16)
    $ES_SYSTEM_REQUIRED = [uint32]1
    $flags = [uint32]($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED)
    $result = [MediaPrepPower]::SetThreadExecutionState($flags)
    if($result -eq 0){throw 'Windows kunde inte aktivera skyddet mot strömsparläge.'}
    $script:SleepProtectionActive=$true
    Write-Host '[OK   ] Strömsparläge förhindras så länge MediaPrep-kön körs.' -ForegroundColor Green
}

function Disable-SleepProtection {
    if(-not $script:SleepProtectionActive){return}
    try{
        $ES_CONTINUOUS = [Convert]::ToUInt32('80000000', 16)
        [void][MediaPrepPower]::SetThreadExecutionState([uint32]$ES_CONTINUOUS)
        Write-Host '[INFO ] Normala strömsparinställningar är återaktiverade.' -ForegroundColor Cyan
    }finally{$script:SleepProtectionActive=$false}
}

function Get-RegistryValueState([string]$Path,[string]$Name){
    if(-not(Test-Path -LiteralPath $Path)){return [pscustomobject]@{PathExists=$false;ValueExists=$false;Value=$null;Kind=$null}}
    $key=Get-Item -LiteralPath $Path
    try{
        $value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $names=@($key.GetValueNames())
        if($names -notcontains $Name){return [pscustomobject]@{PathExists=$true;ValueExists=$false;Value=$null;Kind=$null}}
        return [pscustomobject]@{PathExists=$true;ValueExists=$true;Value=$value;Kind=$key.GetValueKind($Name).ToString()}
    }finally{$key.Close()}
}

function Enable-UpdateRestartProtection {
    if(-not(Test-IsAdministrator)){throw 'Windows Update-skyddet kräver att nattkön startas som administratör.'}
    $path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $script:UpdateProtectionBackup=[pscustomobject]@{
        Path=$path
        NoAutoReboot=Get-RegistryValueState $path 'NoAutoRebootWithLoggedOnUsers'
        AUOptions=Get-RegistryValueState $path 'AUOptions'
    }
    if(-not(Test-Path -LiteralPath $path)){New-Item -Path $path -Force|Out-Null}
    New-ItemProperty -Path $path -Name 'NoAutoRebootWithLoggedOnUsers' -PropertyType DWord -Value 1 -Force|Out-Null
    New-ItemProperty -Path $path -Name 'AUOptions' -PropertyType DWord -Value 4 -Force|Out-Null
    Write-Host '[OK   ] Tillfälligt skydd mot automatisk Windows Update-omstart är aktiverat.' -ForegroundColor Green
    Write-Host '[INFO ] Inga Windows Update-tjänster har stoppats eller pausats.' -ForegroundColor Cyan
}

function Restore-RegistryValueState([string]$Path,[string]$Name,[object]$State){
    if($State.ValueExists){
        $kind=[Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$State.Kind)
        $key=[Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($Path.Substring(6))
        try{$key.SetValue($Name,$State.Value,$kind)}finally{$key.Close()}
    }else{
        if(Test-Path -LiteralPath $Path){Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue}
    }
}

function Disable-UpdateRestartProtection {
    if($null-eq$script:UpdateProtectionBackup){return}
    try{
        $b=$script:UpdateProtectionBackup
        Restore-RegistryValueState $b.Path 'NoAutoRebootWithLoggedOnUsers' $b.NoAutoReboot
        Restore-RegistryValueState $b.Path 'AUOptions' $b.AUOptions
        if(-not$b.NoAutoReboot.PathExists -and -not$b.AUOptions.PathExists){
            try{if((Get-ChildItem -LiteralPath $b.Path -ErrorAction SilentlyContinue).Count-eq0 -and (Get-Item -LiteralPath $b.Path).Property.Count-eq0){Remove-Item -LiteralPath $b.Path -Force}}catch{}
        }
        Write-Host '[INFO ] Tidigare Windows Update-inställningar har återställts.' -ForegroundColor Cyan
    }
    finally {
        $script:UpdateProtectionBackup = $null
    }
}

function Build-Args([object]$job,[string]$unc){
    $a=New-Object System.Collections.Generic.List[string]
    switch([string](Get-P $job 'Mode' 'Full')){'AnalyzeOnly'{$a.Add('-AnalyzeOnly')};'EncodeOnly'{$a.Add('-EncodeOnly')}}
    if([bool](Get-P $job 'NoConfirm' $false)){$a.Add('-NoConfirm')}
    $encodingEnabled = [bool](Get-P $job 'EnableEncoding' (Get-P $job 'EncodeRecommended' $true))
    if($encodingEnabled){$a.Add('-EncodeRecommended')}else{$a.Add('-DisableEncoding')}
    if([bool](Get-P $job 'Force' $false)){$a.Add('-Force')}
    if([bool](Get-P $job 'Reanalyze' $false)){$a.Add('-Reanalyze')}
    if([bool](Get-P $job 'RebuildIndex' $false)){$a.Add('-RebuildIndex')}
    if([bool](Get-P $job 'VerboseLogging' $false)){$a.Add('-VerboseLogging')}
    if([bool](Get-P $job 'IgnoreDecodeErrors' $false)){$a.Add('-IgnoreDecodeErrors')}
    if([bool](Get-P $job 'ProcessErrorQueue' $false)){$a.Add('-ProcessErrorQueue')}
    $encoderId=[string](Get-P $job 'EncoderId' 'cpu-libx265')
    if(-not[string]::IsNullOrWhiteSpace($encoderId)){$a.Add('-EncoderId');$a.Add($encoderId)}
    if(-not[string]::IsNullOrWhiteSpace($unc)){
        $a.Add('-ImportFromUnc');$a.Add('-UncSourcePath');$a.Add($unc)
        if([bool](Get-P $job 'DeleteUncAfterSuccess' $true)){$a.Add('-DeleteUncAfterSuccess')}
    }
    $includeList = [string](Get-P $job 'IncludeListPath' '')
    if (-not [string]::IsNullOrWhiteSpace($includeList)) {
        $a.Add('-IncludeListPath')
        $a.Add($includeList)
    }
    $a.Add('-NoPause')
    return $a.ToArray()
}

function ConvertTo-CommandLineArgument {
    param([string]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    return '"' + $Value.Replace('"','\"') + '"'
}

function Invoke-MediaPrepChildProcess {
    param(
        [Parameter(Mandatory=$true)][string[]]$Arguments
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('-NoProfile')
    $parts.Add('-ExecutionPolicy')
    $parts.Add('Bypass')
    $parts.Add('-File')
    $parts.Add((ConvertTo-CommandLineArgument -Value $mediaPrep))

    foreach ($argument in $Arguments) {
        if ($argument -match '^-[A-Za-z]') {
            $parts.Add($argument)
        }
        else {
            $parts.Add((ConvertTo-CommandLineArgument -Value $argument))
        }
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'powershell.exe'
    $startInfo.Arguments = ($parts -join ' ')
    $startInfo.WorkingDirectory = $root
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false

    if ($script:VerboseLogging) {
        Write-Host ('[VERBOSE] Barnprocess: {0} {1}' -f $startInfo.FileName,$startInfo.Arguments) -ForegroundColor DarkGray
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'MediaPrep-processen kunde inte startas.'
    }

    $process.WaitForExit()
    $exitCode = [int]$process.ExitCode
    $process.Dispose()
    return $exitCode
}


function Save-JsonUtf8Bom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText(
        $Path,
        $json,
        (New-Object System.Text.UTF8Encoding($true))
    )
}

function Save-RemainingQueue {
    param(
        [Parameter(Mandatory=$true)][object]$Job,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$RemainingQueue
    )

    $Job.UncQueue = @($RemainingQueue)
    if ($null -eq $Job.UncQueue) { $Job.UncQueue = @() }
    Save-JsonUtf8Bom -Path $JobFile -Value $Job
    Save-JsonUtf8Bom -Path $script:SettingsFile -Value $Job

    Write-Host ("[INFO ] Kölistan uppdaterad. Återstår: {0} mappar." -f @($RemainingQueue).Count) -ForegroundColor Cyan
    if (@($RemainingQueue).Count -eq 0) {
        Write-Host '[OK   ] Kölistan är nu tom.' -ForegroundColor Green
    }
    if ($script:VerboseLogging) {
        foreach ($remaining in $RemainingQueue) {
            Write-Host ("[VERBOSE] Kvar i kön: {0}" -f $remaining) -ForegroundColor DarkGray
        }
    }
}


function Enable-AllInOneConfiguration {
    param([object]$Job)

    $source = [string](Get-P $Job 'TemporarySourceFolder' '')
    $output = [string](Get-P $Job 'TemporaryOutputFolder' '')
    if ([string]::IsNullOrWhiteSpace($source) -or -not (Test-Path -LiteralPath $source -PathType Container)) {
        throw ("All in one source folder is invalid: {0}" -f $source)
    }
    if ([string]::IsNullOrWhiteSpace($output)) {
        throw 'All in one output folder is empty.'
    }
    if (-not (Test-Path -LiteralPath $output -PathType Container)) {
        New-Item -Path $output -ItemType Directory -Force | Out-Null
    }

    $configPath = Join-Path (Join-Path $root 'Data') 'config.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw ("Configuration file is missing: {0}" -f $configPath)
    }

    $script:OriginalConfigText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    $config = $script:OriginalConfigText | ConvertFrom-Json
    $config | Add-Member -NotePropertyName SourceFolder -NotePropertyValue $source -Force
    $config | Add-Member -NotePropertyName OutputFolder -NotePropertyValue $output -Force
    [IO.File]::WriteAllText($configPath,($config | ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($true)))
    $script:ConfigWasOverridden = $true
    Write-Host ("[INFO ] All in one source: {0}" -f $source) -ForegroundColor Cyan
    Write-Host ("[INFO ] All in one output: {0}" -f $output) -ForegroundColor Cyan
}

function Restore-AllInOneConfiguration {
    if (-not $script:ConfigWasOverridden) { return }
    try {
        $configPath = Join-Path (Join-Path $root 'Data') 'config.json'
        [IO.File]::WriteAllText($configPath,$script:OriginalConfigText,(New-Object Text.UTF8Encoding($true)))
        Write-Host '[INFO ] Permanent folder preferences were restored after All in one.' -ForegroundColor Cyan
    }
    finally {
        $script:ConfigWasOverridden = $false
        $script:OriginalConfigText = $null
    }
}

function Remove-EmptySubdirectories {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath
    )

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        return 0
    }

    $removed = 0
    $directories = @(Get-ChildItem -LiteralPath $RootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending)

    foreach ($directory in $directories) {
        try {
            $hasContent = @(Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction Stop).Count -gt 0
            if (-not $hasContent) {
                Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction Stop
                $removed++
                Write-Host ("[INFO ] Tog bort tom lokal mapp: {0}" -f $directory.FullName) -ForegroundColor DarkCyan
            }
        }
        catch {
            if ($script:VerboseLogging) {
                Write-Host ("[VERBOSE] Kunde inte kontrollera/radera mappen {0}: {1}" -f $directory.FullName,$_.Exception.Message) -ForegroundColor DarkGray
            }
        }
    }

    return $removed
}

function Invoke-LocalEmptyFolderCleanup {
    $total = 0
    $total += Remove-EmptySubdirectories -RootPath (Join-Path $root 'UnProcessed')
    $total += Remove-EmptySubdirectories -RootPath (Join-Path $root 'Processed')
    $total += Remove-EmptySubdirectories -RootPath (Join-Path $root 'Filmer')
    $total += Remove-EmptySubdirectories -RootPath (Join-Path $root 'MKV')

    if ($total -gt 0) {
        Write-Host ("[OK   ] Tomma lokala undermappar borttagna: {0}" -f $total) -ForegroundColor Green
    }
    elseif ($script:VerboseLogging) {
        Write-Host '[VERBOSE] Inga tomma lokala undermappar behövde tas bort.' -ForegroundColor DarkGray
    }
}

try{
    if(-not(Test-Path -LiteralPath $mediaPrep -PathType Leaf)){throw "MediaPrep.ps1 hittades inte: $mediaPrep"}
    if(-not(Test-Path -LiteralPath $JobFile -PathType Leaf)){throw "Köfilen hittades inte: $JobFile"}
    $job=Get-Content -LiteralPath $JobFile -Raw -Encoding UTF8|ConvertFrom-Json
    $configuredSettingsFile=[string](Get-P $job 'SettingsFile' '')
    if (-not [string]::IsNullOrWhiteSpace($configuredSettingsFile)) { $script:SettingsFile=$configuredSettingsFile }
    $workMode=[string](Get-P $job 'WorkMode' 'Queue')
    if ($workMode -eq 'AllInOne') { Enable-AllInOneConfiguration -Job $job }
    $script:VerboseLogging=[bool](Get-P $job 'VerboseLogging' $false)
    $script:StopRequestFile=[string](Get-P $job 'StopRequestFile' '')
    if(-not [string]::IsNullOrWhiteSpace($script:StopRequestFile)){Remove-Item -LiteralPath $script:StopRequestFile -Force -ErrorAction SilentlyContinue}
    if($script:VerboseLogging){
        Write-Host ('[VERBOSE] Köskript: {0}' -f $script:QueueScriptPath) -ForegroundColor DarkGray
        Write-Host ('[VERBOSE] Jobbfil: {0}' -f $JobFile) -ForegroundColor DarkGray
        Write-Host ('[VERBOSE] Administratör: {0}' -f (Test-IsAdministrator)) -ForegroundColor DarkGray
        Write-Host ('[VERBOSE] UNC-kö aktiverad: {0}' -f [bool](Get-P $job 'UncEnabled' $false)) -ForegroundColor DarkGray
        Write-Host ('[VERBOSE] Antal köposter: {0}' -f @((Get-P $job 'UncQueue' @())).Count) -ForegroundColor DarkGray
    }
    if (Restart-ElevatedIfRequired -Job $job) {
        return [int]0
    }
    if([bool](Get-P $job 'PreventSleep' $true)){Enable-SleepProtection}
    if([bool](Get-P $job 'PreventUpdateRestart' $false)){Enable-UpdateRestartProtection}
    $queue = @((Get-P $job 'UncQueue' @()))
    $localFileQueue = @((Get-P $job 'LocalFileQueue' @()))
    $useQueue = ([bool](Get-P $job 'UncEnabled' $false) -and $workMode -ne 'AllInOne')

    if ($useQueue -and $queue.Count -eq 0) {
        throw 'UNC-kön är aktiverad men innehåller inga mappar.'
    }

    if ($workMode -eq 'AllInOne' -and $localFileQueue.Count -eq 0) {
        throw 'All in one är valt men fillistan är tom.'
    }

    if ($useQueue) {
        $items = @($queue)
    }
    else {
        $items = @('')
    }
    $remainingQueue = New-Object System.Collections.Generic.List[string]
    if ($useQueue) { foreach ($queueItem in $queue) { $remainingQueue.Add([string]$queueItem) } }
    $allOk=$true;$failed=New-Object System.Collections.Generic.List[string]
    $start=Get-Date
    Remove-Item -LiteralPath $script:CopyStatsPath -Force -ErrorAction SilentlyContinue
    Save-JsonUtf8Bom -Path $script:RunStatsPath -Value ([pscustomobject][ordered]@{
        StartedLocal=$start.ToString('yyyy-MM-dd HH:mm:ss')
        StartedUtc=$start.ToUniversalTime().ToString('o')
        EndedLocal=''
        EndedUtc=''
        ElapsedSeconds=0
        Status='Running'
    })
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host ' MediaPrep MKV Toolkit nattkö' -ForegroundColor Cyan
    Write-Host (" Köposter: {0}" -f @($items).Count) -ForegroundColor Cyan
    Write-Host '================================================================' -ForegroundColor Cyan
    if($script:VerboseLogging){
        Write-Host ('[VERBOSE] Köstart UTC: {0}' -f (Get-Date).ToUniversalTime().ToString('o')) -ForegroundColor DarkGray
        Write-Host ('[VERBOSE] Arbetsläge: {0}; använd UNC-kö: {1}; poster: {2}' -f $workMode,$useQueue,@($items).Count) -ForegroundColor DarkGray
        for($vi=0;$vi -lt @($items).Count;$vi++){Write-Host ('[VERBOSE] Köpost {0}/{1}: {2}' -f ($vi+1),@($items).Count,[string]$items[$vi]) -ForegroundColor DarkGray}
    }
    for($i=0;$i-lt@($items).Count;$i++){
        $unc=[string]$items[$i]
        Write-Host ''
        Write-Host ('='*64) -ForegroundColor DarkCyan
        if($useQueue){Write-Host (" Kö {0}/{1}: {2}" -f ($i+1),@($items).Count,$unc) -ForegroundColor Yellow}
        else{Write-Host ' Lokal körning utan UNC-kö' -ForegroundColor Yellow}
        Write-Host ('='*64) -ForegroundColor DarkCyan
        if($useQueue -and (-not(Test-Path -LiteralPath $unc -PathType Container))){
            Write-Host ("[ERROR] UNC-mappen kan inte nås: {0}" -f $unc) -ForegroundColor Red
            $allOk=$false;$failed.Add($unc);continue
        }
        $args=Build-Args $job $unc
        if($script:VerboseLogging){Write-Host ('[VERBOSE] MediaPrep-argument: {0}' -f ($args -join ' | ')) -ForegroundColor DarkGray}
        $code = Invoke-MediaPrepChildProcess -Arguments $args
        Write-Host ("[INFO ] MediaPrep-processen avslutades med exitkod {0}." -f $code) -ForegroundColor Cyan
        if($code-ne 0){
            $allOk=$false
            $failedName = if ([string]::IsNullOrWhiteSpace($unc)) { 'Lokal körning' } else { $unc }
            $failed.Add($failedName)
            Write-Host ("[ERROR] Köposten slutade med exitkod {0}. Nästa post fortsätter." -f $code) -ForegroundColor Red
        }
        else {
            Write-Host '[OK   ] Köposten är klar.' -ForegroundColor Green

            if ($useQueue) {
                $removeIndex = -1
                for ($queueIndex = 0; $queueIndex -lt $remainingQueue.Count; $queueIndex++) {
                    if ([string]::Equals([string]$remainingQueue[$queueIndex],$unc,[System.StringComparison]::OrdinalIgnoreCase)) {
                        $removeIndex = $queueIndex
                        break
                    }
                }

                if ($removeIndex -ge 0) {
                    $remainingQueue.RemoveAt($removeIndex)
                }
                else {
                    Write-Host ("[WARN ] Den färdiga köposten hittades inte i återstående kö: {0}" -f $unc) -ForegroundColor Yellow
                }

                Save-RemainingQueue -Job $job -RemainingQueue @($remainingQueue.ToArray())
            }

            Invoke-LocalEmptyFolderCleanup
        }
    }

    # En sista kontroll tar bort mappar som blev tomma under den sista återföringen.
    Invoke-LocalEmptyFolderCleanup

    if ($useQueue) {
        if ($allOk) {
            Save-RemainingQueue -Job $job -RemainingQueue @()
        }
        else {
            Save-RemainingQueue -Job $job -RemainingQueue @($remainingQueue.ToArray())
        }
    }

    $elapsed=(Get-Date)-$start
    $ended=Get-Date
    Save-JsonUtf8Bom -Path $script:RunStatsPath -Value ([pscustomobject][ordered]@{
        StartedLocal=$start.ToString('yyyy-MM-dd HH:mm:ss')
        StartedUtc=$start.ToUniversalTime().ToString('o')
        EndedLocal=$ended.ToString('yyyy-MM-dd HH:mm:ss')
        EndedUtc=$ended.ToUniversalTime().ToString('o')
        ElapsedSeconds=[Math]::Round($elapsed.TotalSeconds,1)
        Status=if($allOk){'Completed'}else{'CompletedWithErrors'}
    })
    Write-Host ''
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host (" Kön är klar. Tid: {0}" -f $elapsed.ToString('hh\:mm\:ss')) -ForegroundColor Cyan
    if($allOk){Write-Host '[OK   ] Alla köposter slutfördes utan fel.' -ForegroundColor Green}
    else{Write-Host ("[ERROR] Misslyckade köposter: {0}" -f $failed.Count) -ForegroundColor Red;foreach($f in $failed){Write-Host ("  - {0}" -f $f) -ForegroundColor Red}}
    Write-Host '================================================================' -ForegroundColor Cyan

    $shutdown=[bool](Get-P $job 'ShutdownAfterSuccess' $false)
    if($shutdown -and $allOk){
        $script:ShutdownRequested=$true
        Write-Host '[INFO ] Automatisk avstängning kommer att planeras efter att skyddsinställningarna har återställts.' -ForegroundColor Cyan
    }elseif($shutdown -and -not$allOk){
        Write-Host '[WARN ] Datorn stängs inte av eftersom minst en köpost misslyckades.' -ForegroundColor Yellow
    }
    if(-not[bool](Get-P $job 'NoPause' $false)){
        Write-Host '';[void](Read-Host 'Tryck Enter för att avsluta')
    }
    if ($allOk) {
        $script:FinalExitCode = 0
    }
    else {
        $script:FinalExitCode = 1
    }
}catch{
    Write-Host ("[ERROR] {0}" -f $_.Exception.Message) -ForegroundColor Red
    if($script:VerboseLogging){
        Write-Host ('[VERBOSE] Feltyp: {0}' -f $_.Exception.GetType().FullName) -ForegroundColor DarkRed
        Write-Host ('[VERBOSE] Kategori: {0}' -f $_.CategoryInfo) -ForegroundColor DarkRed
        Write-Host ('[VERBOSE] FullyQualifiedErrorId: {0}' -f $_.FullyQualifiedErrorId) -ForegroundColor DarkRed
        if($_.InvocationInfo){Write-Host ('[VERBOSE] Position: {0}' -f $_.InvocationInfo.PositionMessage) -ForegroundColor DarkRed}
        if($_.ScriptStackTrace){Write-Host ('[VERBOSE] Stack: {0}' -f $_.ScriptStackTrace) -ForegroundColor DarkRed}
    }
    $script:FinalExitCode = 1
    if(-not(Test-Path variable:job) -or -not[bool](Get-P $job 'NoPause' $false)){[void](Read-Host 'Tryck Enter för att avsluta')}
}
finally {
    if ($script:VerboseLogging) {
        Write-Host ('[VERBOSE] Före återställning: FinalExitCode={0}, ShutdownRequested={1}' -f $script:FinalExitCode,$script:ShutdownRequested) -ForegroundColor DarkGray
    }
    Restore-AllInOneConfiguration
    Disable-UpdateRestartProtection
    Disable-SleepProtection
    if ($script:VerboseLogging) {
        Write-Host ('[VERBOSE] Efter återställning: FinalExitCode={0}, ShutdownRequested={1}' -f $script:FinalExitCode,$script:ShutdownRequested) -ForegroundColor DarkGray
    }
}

if ($script:VerboseLogging) {
    Write-Host ''
    Write-Host '================ VERBOSE FELSÖKNINGSPAUS ================' -ForegroundColor Yellow
    Write-Host (' Slutlig exitkod........: {0}' -f $script:FinalExitCode) -ForegroundColor Yellow
    Write-Host (' Avstängning väntar.....: {0}' -f $script:ShutdownRequested) -ForegroundColor Yellow
    Write-Host ' Läs igenom eventuell röd text ovan innan du fortsätter.' -ForegroundColor Yellow
    Write-Host '==========================================================' -ForegroundColor Yellow
    [void](Read-Host 'Tryck Enter för att avsluta felsökningsläget')
}

if ($script:ShutdownRequested -and $script:FinalExitCode -eq 0) {
    Write-Host '[WARN ] Datorn stängs av om 60 sekunder. Kör shutdown /a i ett annat fönster för att avbryta.' -ForegroundColor Yellow
    & shutdown.exe /s /t 60 /c "MediaPrep MKV Toolkit-kön är färdig och alla köposter lyckades."
    $shutdownExitCode = $LASTEXITCODE
    if ($shutdownExitCode -eq 0) {
        Write-Host '[OK   ] Windows har accepterat avstängningsbegäran.' -ForegroundColor Green
    }
    else {
        Write-Host ("[ERROR] Windows avvisade avstängningsbegäran. Exitkod: {0}" -f $shutdownExitCode) -ForegroundColor Red
        $script:FinalExitCode = 1
    }
}

return [int]$script:FinalExitCode
