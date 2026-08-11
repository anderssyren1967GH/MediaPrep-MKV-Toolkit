<#
.SYNOPSIS
    MediaPrep MKV Toolkit 0.11.51 - muxar, analyserar och omkodar till MKV och analyserar färdiga filer.

.DESCRIPTION
    Kompatibel med Windows PowerShell 5.1.
    Söker rekursivt efter TS, MP4 och AVI, hittar SRT eller VTT med samma filnamn,
    konverterar VTT till en tillfällig SRT och muxar till MKV utan omkodning.
    Oförändrade och redan aktuella MKV-filer hoppas över.

.PARAMETER RebuildIndex
    Ignorerar tidigare index och bygger om det från början.

.PARAMETER Force
    Muxar om samtliga videofiler även om en aktuell MKV redan finns.

.PARAMETER NoConfirm
    Startar muxningen utan bekräftelsefråga.

.PARAMETER AnalyzeOnly
    Hoppar över skanning och muxning och analyserar endast befintliga MKV-filer.

.PARAMETER Reanalyze
    Tvingar ny ffprobe-analys även om filen är oförändrad och finns i analyscachen.

.PARAMETER EncodeOnly
    Hoppar över källskanning och muxning och arbetar direkt med MKV-mappen.

.PARAMETER EncodeRecommended
    Omkodar rekommenderade filer utan extra fråga.

.PARAMETER UncSourcePath
    UNC-mapp som innehåller TS/MP4/AVI/MPG/MPEG och eventuella matchande SRT/VTT-filer.

.PARAMETER ImportFromUnc
    Kopierar filer från UNC-mappen till den lokala UnProcessed-mappen före bearbetning.

.PARAMETER DeleteUncAfterSuccess
    Tar bort UNC-original först efter verifierad lokal behandling.

.PARAMETER NoPause
    Avslutar utan att vänta på tangenttryckning.
#>

[CmdletBinding()]
param(
    [switch]$RebuildIndex,
    [switch]$Force,
    [switch]$NoConfirm,
    [switch]$AnalyzeOnly,
    [switch]$Reanalyze,
    [switch]$EncodeOnly,
    [switch]$EncodeRecommended,
    [switch]$DisableEncoding,
    [switch]$IgnoreDecodeErrors,
    [switch]$ProcessErrorQueue,
    [string]$EncoderId = '',
    [string]$UncSourcePath = '',
    [switch]$ImportFromUnc,
    [switch]$DeleteUncAfterSuccess,
    [string]$IncludeListPath = '',
    [switch]$VerboseLogging,
    [switch]$NoPause
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

#region Grundinställningar
$Script:AppName = 'MediaPrep MKV Toolkit'
$Script:AppVersion = '0.11.51'
$Script:BuildDate = '2026-08-11'
$Script:AppFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:Root = Split-Path -Parent $Script:AppFolder
$Script:ConfigPath = Join-Path (Join-Path $Script:Root 'Data') 'config.json'
$Script:Config = $null
$Script:LogFile = $null
$Script:StartTime = Get-Date
$Script:FFmpegPath = $null
$Script:FFprobePath = $null
$Script:MKVMergePath = $null
$Script:TempFolder = $null
$Script:UncManifestPath = $null
$Script:RunId = [Guid]::NewGuid().ToString('N')
$Script:ResumeRemuxPaths = @{}
$Script:VerboseLogging = [bool]$VerboseLogging
$Script:IgnoreDecodeErrors = [bool]$IgnoreDecodeErrors
$Script:ProcessErrorQueue = [bool]$ProcessErrorQueue
$Script:EncoderId = [string]$EncoderId
$Script:EncoderCapabilitiesPath = $null
$Script:ErrorFolder = $null
$Script:ErrorQueuePath = $null
$Script:StatisticsCurrentPath = $null
#endregion

#region Hjälpfunktioner
function Write-ColorLine {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host $Text -ForegroundColor $Color
}

function Write-Status {
    param(
        [ValidateSet('OK','INFO','WARN','ERROR','SKIP','PROGRESS')][string]$Type,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $color = 'Gray'
    switch ($Type) {
        'OK'    { $color = 'Green' }
        'INFO'  { $color = 'Cyan' }
        'WARN'  { $color = 'Yellow' }
        'ERROR' { $color = 'Red' }
        'SKIP'  { $color = 'DarkYellow' }
        'PROGRESS' { $color = 'Magenta' }
    }

    $line = '[{0,-5}] {1}' -f $Type, $Message
    Write-Host $line -ForegroundColor $color

    if ($Script:LogFile) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -LiteralPath $Script:LogFile -Value ("{0} {1}" -f $timestamp, $line) -Encoding UTF8
    }
}

function Write-ProgressLogOnly {
    param([Parameter(Mandatory = $true)][string]$Message)
    if ($Script:LogFile) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -LiteralPath $Script:LogFile -Value ("{0} [PROGRESS] {1}" -f $timestamp,$Message) -Encoding UTF8
    }
}

function Write-VerboseDiagnostic {
    param([Parameter(Mandatory=$true)][string]$Message)
    if (-not $Script:VerboseLogging) { return }
    $line='[VERBOSE] '+$Message
    Write-Host $line -ForegroundColor DarkGray
    if($Script:LogFile){
        $timestamp=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -LiteralPath $Script:LogFile -Value ("{0} {1}" -f $timestamp,$line) -Encoding UTF8
    }
}

function Get-NvidiaDiagnosticSnapshot {
    if(-not $Script:VerboseLogging){return}
    try{
        $smi=Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
        if($null -eq $smi){Write-VerboseDiagnostic 'nvidia-smi.exe hittades inte.';return}
        $query='name,driver_version,pstate,temperature.gpu,utilization.gpu,utilization.encoder,clocks.current.graphics,clocks.current.memory,power.limit'
        $out=& $smi.Source --query-gpu=$query --format=csv,noheader 2>&1
        Write-VerboseDiagnostic ('GPU snapshot: {0}' -f (($out|ForEach-Object{[string]$_}) -join ' | '))
    }catch{Write-VerboseDiagnostic ('GPU snapshot misslyckades: {0}' -f $_.Exception.Message)}
}

function Get-FfmpegVersionDiagnostic {
    if(-not $Script:VerboseLogging -or [string]::IsNullOrWhiteSpace([string]$Script:FFmpegPath)){return}
    try{
        $v=& $Script:FFmpegPath -version 2>&1 | Select-Object -First 2
        Write-VerboseDiagnostic ('FFmpeg: {0}' -f (($v|ForEach-Object{[string]$_}) -join ' | '))
    }catch{Write-VerboseDiagnostic ('FFmpeg-version kunde inte läsas: {0}' -f $_.Exception.Message)}
}

function Join-CommandLineForDiagnostic {
    param([string]$Exe,[string[]]$Arguments)
    $parts=New-Object System.Collections.Generic.List[string]
    $parts.Add(('"{0}"' -f $Exe))
    foreach($a in $Arguments){
        $s=[string]$a
        if($s -match '[\s"]'){$parts.Add(('"{0}"' -f ($s.Replace('"','\"'))))}else{$parts.Add($s)}
    }
    return ($parts -join ' ')
}

function Show-Header {
    Clear-Host
    Write-ColorLine ('=' * 64) DarkCyan
    Write-ColorLine (' {0}' -f $Script:AppName) Cyan
    Write-ColorLine (' Version : {0}' -f $Script:AppVersion) Gray
    Write-ColorLine (' Byggd   : {0}' -f $Script:BuildDate) Gray
    Write-ColorLine (' PowerShell: {0}' -f $PSVersionTable.PSVersion) DarkGray
    Write-ColorLine ('=' * 64) DarkCyan
    Write-Host ''
}

function Get-FullPathFromConfig {
    param([Parameter(Mandatory = $true)][string]$ConfiguredPath)

    if ([System.IO.Path]::IsPathRooted($ConfiguredPath)) {
        return [System.IO.Path]::GetFullPath($ConfiguredPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $Script:Root $ConfiguredPath))
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $base = [System.IO.Path]::GetFullPath($BasePath)
    if (-not $base.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $base += [System.IO.Path]::DirectorySeparatorChar
    }

    $target = [System.IO.Path]::GetFullPath($FullPath)
    $baseUri = New-Object System.Uri($base)
    $targetUri = New-Object System.Uri($target)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    return [System.Uri]::UnescapeDataString($relativeUri.ToString()).Replace('/', '\')
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        Write-Status INFO ("Skapade mapp: {0}" -f $Path)
    }
    else {
        Write-Status OK ("Mapp finns: {0}" -f $Path)
    }
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$DefaultValue
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $DefaultValue
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $DefaultValue
    }

    try {
        return ($raw | ConvertFrom-Json)
    }
    catch {
        Write-Status WARN ("Kunde inte läsa JSON-filen: {0}. Standardvärde används." -f $Path)
        return $DefaultValue
    }
}

function Save-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object]$Value
    )

    if ($null -eq $Value) {
        $json = 'null'
    }
    elseif ($Value -is [System.Array] -and $Value.Count -eq 0) {
        $json = '[]'
    }
    else {
        $json = $Value | ConvertTo-Json -Depth 8
    }

    $dir=Split-Path -Parent $Path
    if($dir -and -not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -Path $dir -ItemType Directory -Force|Out-Null}
    $tmp=$Path+'.tmp.'+$PID
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
#endregion

#region Konfiguration och miljö
function Initialize-MediaPrep {
    if (-not (Test-Path -LiteralPath $Script:ConfigPath -PathType Leaf)) {
        throw "config.json saknas: $Script:ConfigPath"
    }

    $Script:Config = Read-JsonFile -Path $Script:ConfigPath -DefaultValue $null
    if ($null -eq $Script:Config) {
        throw 'config.json kunde inte läsas.'
    }

    $Script:SourceFolder = Get-FullPathFromConfig $Script:Config.SourceFolder
    $Script:OutputFolder = Get-FullPathFromConfig $Script:Config.OutputFolder
    $Script:LogFolder = Get-FullPathFromConfig $Script:Config.LogFolder
    $Script:ReportFolder = Get-FullPathFromConfig $Script:Config.ReportFolder
    $Script:DataFolder = Get-FullPathFromConfig $Script:Config.DataFolder

    Ensure-Directory $Script:SourceFolder
    Ensure-Directory $Script:OutputFolder
    Ensure-Directory $Script:LogFolder
    Ensure-Directory $Script:ReportFolder
    Ensure-Directory $Script:DataFolder

    $Script:LogFile = Join-Path $Script:LogFolder ("MediaPrep_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    New-Item -Path $Script:LogFile -ItemType File -Force | Out-Null

    Write-Status OK 'Konfigurationen är inläst.'
    Write-Status INFO ("Källmapp: {0}" -f $Script:SourceFolder)
    Write-Status INFO ("Målmapp : {0}" -f $Script:OutputFolder)

    $ffmpegConfigured = if ($Script:Config.PSObject.Properties['FFmpegPath']) { [string]$Script:Config.FFmpegPath } else { 'ffmpeg.exe' }
    $ffprobeConfigured = if ($Script:Config.PSObject.Properties['FFprobePath']) { [string]$Script:Config.FFprobePath } else { 'ffprobe.exe' }
    $mkvmergeConfigured = if ($Script:Config.PSObject.Properties['MkvmergePath']) { [string]$Script:Config.MkvmergePath } else { 'mkvmerge.exe' }
    $tempConfigured = if ($Script:Config.PSObject.Properties['TempFolder']) { [string]$Script:Config.TempFolder } else { (Join-Path $Script:DataFolder 'Temp') }
    $Script:FFmpegPath = Get-FullPathFromConfig $ffmpegConfigured
    $Script:FFprobePath = Get-FullPathFromConfig $ffprobeConfigured
    $Script:MKVMergePath = Get-FullPathFromConfig $mkvmergeConfigured
    $Script:TempFolder = Get-FullPathFromConfig $tempConfigured
    $Script:UncManifestPath = Join-Path $Script:DataFolder 'unc-import-manifest.json'
    $Script:ErrorFolder = Join-Path $Script:Root 'Error'
    $Script:ErrorQueuePath = Join-Path $Script:DataFolder 'error-queue.json'
    $Script:CopyStatsPath = Join-Path $Script:DataFolder 'queue-copy-stats.json'
    $Script:StatisticsCurrentPath = Join-Path $Script:DataFolder 'statistics-run-current.json'
    $Script:EncoderCapabilitiesPath = Join-Path $Script:DataFolder 'encoder-capabilities.json'
    if([string]::IsNullOrWhiteSpace($Script:EncoderId)){
        $Script:EncoderId=[string](Get-OptionalPropertyValue -Object $Script:Config -Name 'SelectedEncoderId' -DefaultValue 'cpu-libx265')
    }
    if([string]::IsNullOrWhiteSpace($Script:EncoderId)){$Script:EncoderId='cpu-libx265'}
    Ensure-Directory $Script:TempFolder
    Ensure-Directory $Script:ErrorFolder
    $errorBatch = Join-Path $Script:ErrorFolder 'Bearbeta felko.cmd'
    $batchLines = @(
        '@echo off',
        'set "ROOT=%~dp0.."',
        'PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\App\MediaPrep.ps1" -EncodeOnly -ProcessErrorQueue -IgnoreDecodeErrors -NoConfirm -NoPause',
        'pause'
    )
    [IO.File]::WriteAllLines($errorBatch,$batchLines,[Text.Encoding]::ASCII)

    $requiredTools = @(
        [PSCustomObject]@{ Name = 'ffmpeg.exe'; Path = $Script:FFmpegPath },
        [PSCustomObject]@{ Name = 'ffprobe.exe'; Path = $Script:FFprobePath },
        [PSCustomObject]@{ Name = 'mkvmerge.exe'; Path = $Script:MKVMergePath }
    )

    foreach ($tool in $requiredTools) {
        if (Test-Path -LiteralPath $tool.Path -PathType Leaf) {
            Write-Status OK ("Verktyg hittades: {0}" -f $tool.Name)
        }
        else {
            Write-Status ERROR ("Verktyg saknas: {0}" -f $tool.Path)
            throw "Nödvändigt verktyg saknas: $($tool.Name)"
        }
    }
}
#endregion

#region UNC-import och säker källrensning
function Test-UncPath {
    param([string]$Path)
    return (-not [string]::IsNullOrWhiteSpace($Path) -and $Path.StartsWith('\\'))
}

function Get-MediaDurationSeconds {
    param([Parameter(Mandatory = $true)][string]$Path)
    $value = (& $Script:FFprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $Path 2>$null | Select-Object -First 1)
    return (Convert-ToDoubleInvariant -Value $value)
}

function Set-ObjectPropertySafe {
    param([object]$Object,[string]$Name,[object]$Value)
    if($null -eq $Object){return}
    $p=$Object.PSObject.Properties[$Name]
    if($p){$p.Value=$Value}else{$Object|Add-Member -NotePropertyName $Name -NotePropertyValue $Value}
}
function Update-StatisticsSessionFile {
    param(
        [string]$SourcePath='',
        [string]$RelativePath='',
        [string]$QueueRoot='',
        [hashtable]$Values=$null,
        [object]$CopyEvent=$null
    )
    try{
        if([string]::IsNullOrWhiteSpace($Script:StatisticsCurrentPath) -or -not(Test-Path -LiteralPath $Script:StatisticsCurrentPath -PathType Leaf)){return}
        $doc=Get-Content -LiteralPath $Script:StatisticsCurrentPath -Raw -Encoding UTF8|ConvertFrom-Json
        if($null -eq $doc){return}
        if(-not $doc.PSObject.Properties['Queues']){$doc|Add-Member -NotePropertyName Queues -NotePropertyValue @()}
        $queues=@($doc.Queues)
        $q=$null
        foreach($candidate in $queues){if([string]::Equals([string](Get-OptionalPropertyValue $candidate 'SourceRoot' ''),$QueueRoot,[StringComparison]::OrdinalIgnoreCase)){$q=$candidate;break}}
        if($null -eq $q){
            $now=Get-Date
            $q=[pscustomobject][ordered]@{QueueId=[Guid]::NewGuid().ToString('N');SourceRoot=$QueueRoot;StartedLocal=$now.ToString('yyyy-MM-dd HH:mm:ss');StartedUtc=$now.ToUniversalTime().ToString('o');LastUpdatedUtc=$now.ToUniversalTime().ToString('o');Files=@()}
            $queues += $q
            Set-ObjectPropertySafe $doc 'Queues' $queues
        }
        if(-not $q.PSObject.Properties['Files']){$q|Add-Member -NotePropertyName Files -NotePropertyValue @()}
        $files=@($q.Files);$f=$null
        $sourceKey=[string]$SourcePath
        $relativeKey=[string]$RelativePath
        foreach($candidate in $files){
            $cSource=[string](Get-OptionalPropertyValue $candidate 'SourcePath' '')
            $cRel=[string](Get-OptionalPropertyValue $candidate 'RelativePath' '')
            if(-not[string]::IsNullOrWhiteSpace($sourceKey) -and [string]::Equals($cSource,$sourceKey,[StringComparison]::OrdinalIgnoreCase)){$f=$candidate;break}
            if(-not[string]::IsNullOrWhiteSpace($relativeKey)){
                try{if([string]::Equals([IO.Path]::ChangeExtension($cRel,$null),[IO.Path]::ChangeExtension($relativeKey,$null),[StringComparison]::OrdinalIgnoreCase)){$f=$candidate;break}}catch{}
            }
        }
        if($null -eq $f){
            $f=[pscustomobject][ordered]@{SourcePath=$SourcePath;RelativePath=$RelativePath;SourceSize=0;MuxedSize=$null;EncodedSize=$null;FinalSize=$null;QueueStage=0;QueueStatus='Waiting';CopyInBytes=0;CopyInSeconds=0;CopyInMBps=0;CopyBackBytes=0;CopyBackSeconds=0;CopyBackMBps=0;CopyEvents=@();Result='Pending'}
            $files += $f
            Set-ObjectPropertySafe $q 'Files' $files
        }
        if(-not[string]::IsNullOrWhiteSpace($SourcePath)){Set-ObjectPropertySafe $f 'SourcePath' $SourcePath}
        if(-not[string]::IsNullOrWhiteSpace($RelativePath)){Set-ObjectPropertySafe $f 'RelativePath' $RelativePath}
        if($Values){foreach($k in $Values.Keys){Set-ObjectPropertySafe $f ([string]$k) $Values[$k]}}
        if($null -ne $CopyEvent){
            $events=@()
            $ep=$f.PSObject.Properties['CopyEvents']
            if($ep -and $null -ne $ep.Value){$events=@($ep.Value)}
            $events += $CopyEvent
            Set-ObjectPropertySafe $f 'CopyEvents' @($events)
        }
        Set-ObjectPropertySafe $q 'LastUpdatedUtc' ((Get-Date).ToUniversalTime().ToString('o'))
        Save-JsonFile -Path $Script:StatisticsCurrentPath -Value $doc
    }catch{
        if($Script:VerboseLogging){Write-VerboseDiagnostic ('Sessionsstatistik kunde inte uppdateras: {0}' -f $_.Exception.Message)}
    }
}

function Update-QueueDashboardItem {
    param(
        [string]$SourcePath='',
        [string]$RelativePath='',
        [Nullable[int]]$QueueStage=$null,
        [string]$QueueStatus='',
        [hashtable]$Values=$null
    )
    try {
        $dashboardPath=Join-Path $Script:DataFolder 'queue-dashboard-inventory.json'
        if(-not(Test-Path -LiteralPath $dashboardPath -PathType Leaf)){return}
        $doc=Get-Content -LiteralPath $dashboardPath -Raw -Encoding UTF8|ConvertFrom-Json
        if($null -eq $doc -or -not $doc.PSObject.Properties['items']){return}
        $target=$null
        foreach($candidate in @($doc.items)){
            if(-not [string]::IsNullOrWhiteSpace($SourcePath) -and [string]::Equals([string]$candidate.SourcePath,$SourcePath,[System.StringComparison]::OrdinalIgnoreCase)){$target=$candidate;break}
            if(-not [string]::IsNullOrWhiteSpace($RelativePath)){
                $candidateRelative=[string]$candidate.RelativePath
                if([string]::Equals($candidateRelative,$RelativePath,[System.StringComparison]::OrdinalIgnoreCase)){$target=$candidate;break}
                # Efter muxning arbetar MediaPrep med .mkv medan inventeringen behåller
                # den ursprungliga .ts/.mp4/.avi/.mpg/.mpeg-sökvägen. Matcha därför
                # även samma relativa sökväg utan filändelse.
                try{
                    $candidateKey=[IO.Path]::ChangeExtension($candidateRelative,$null)
                    $relativeKey=[IO.Path]::ChangeExtension([string]$RelativePath,$null)
                    if([string]::Equals($candidateKey,$relativeKey,[System.StringComparison]::OrdinalIgnoreCase)){$target=$candidate;break}
                }catch{}
            }
        }
        if($null -eq $target){return}
        if($null -ne $QueueStage){
            if($target.PSObject.Properties['QueueStage']){$target.QueueStage=[int]$QueueStage}else{$target|Add-Member -NotePropertyName QueueStage -NotePropertyValue ([int]$QueueStage)}
        }
        if(-not [string]::IsNullOrWhiteSpace($QueueStatus)){
            if($target.PSObject.Properties['QueueStatus']){$target.QueueStatus=$QueueStatus}else{$target|Add-Member -NotePropertyName QueueStatus -NotePropertyValue $QueueStatus}
        }
        if($null -ne $Values){
            foreach($name in $Values.Keys){
                if($target.PSObject.Properties[$name]){$target.$name=$Values[$name]}else{$target|Add-Member -NotePropertyName $name -NotePropertyValue $Values[$name]}
            }
        }
        $now=(Get-Date).ToUniversalTime().ToString('o')
        if($target.PSObject.Properties['UpdatedUtc']){$target.UpdatedUtc=$now}else{$target|Add-Member -NotePropertyName UpdatedUtc -NotePropertyValue $now}
        $doc.updatedUtc=$now
        $doc.errors=[int]@($doc.items|Where-Object{[int]$_.QueueStage -ge 90}).Count
        Save-JsonFile -Path $dashboardPath -Value $doc
        # Spegla köpostens aktuella tillstånd till sessionsstatistiken.
        $sessionValues=@{}
        foreach($name in @('SourceSize','MuxedSize','EncodedSize','FinalSize','QueueStage','QueueStatus','SubtitleCount','ErrorMessage','CopyInStarted','CopyInCompleted','CopyBackStarted','CopyBackCompleted','MuxStarted','MuxCompleted','AnalysisCompleted','EncodeStarted','EncodeCompleted','CompletedUtc')){
            $prop=$target.PSObject.Properties[$name]
            if($prop){$sessionValues[$name]=$prop.Value}
        }
        $sessionValues['Result']=if([int](Get-OptionalPropertyValue $target 'QueueStage' 0) -eq 10){'Completed'}elseif([int](Get-OptionalPropertyValue $target 'QueueStage' 0) -ge 90){'Error'}else{'Pending'}
        Update-StatisticsSessionFile -SourcePath ([string](Get-OptionalPropertyValue $target 'SourcePath' $SourcePath)) -RelativePath ([string](Get-OptionalPropertyValue $target 'RelativePath' $RelativePath)) -QueueRoot ([string](Get-OptionalPropertyValue $target 'Root' $UncSourcePath)) -Values $sessionValues
    } catch {
        if($Script:VerboseLogging){Write-VerboseDiagnostic ('Ködashboard kunde inte uppdateras: {0}' -f $_.Exception.Message)}
    }
}

function Add-CopyStatistic {
    param(
        [Parameter(Mandatory=$true)][string]$File,
        [Parameter(Mandatory=$true)][ValidateSet('In','Out')][string]$Direction,
        [Parameter(Mandatory=$true)][int64]$Bytes,
        [Parameter(Mandatory=$true)][datetime]$Started,
        [Parameter(Mandatory=$true)][datetime]$Ended
    )
    try {
        $seconds=[Math]::Max(0.001,($Ended-$Started).TotalSeconds)
        $record=[pscustomobject][ordered]@{
            File=$File
            Direction=$Direction
            Bytes=$Bytes
            Seconds=[Math]::Round($seconds,3)
            MBps=[Math]::Round(($Bytes/1MB)/$seconds,2)
            StartedLocal=$Started.ToString('yyyy-MM-dd HH:mm:ss')
            EndedLocal=$Ended.ToString('yyyy-MM-dd HH:mm:ss')
            StartedUtc=$Started.ToUniversalTime().ToString('o')
            EndedUtc=$Ended.ToUniversalTime().ToString('o')
            QueueRoot=$UncSourcePath
        }
        $current=@()
        if(Test-Path -LiteralPath $Script:CopyStatsPath -PathType Leaf){
            try{$current=@(Get-Content -LiteralPath $Script:CopyStatsPath -Raw -Encoding UTF8|ConvertFrom-Json)}catch{$current=@()}
        }
        $list=New-Object System.Collections.Generic.List[object]
        foreach($x in $current){$list.Add($x)}
        $list.Add($record)
        Save-JsonFile -Path $Script:CopyStatsPath -Value @($list.ToArray())
        $relative=''
        try{if(-not[string]::IsNullOrWhiteSpace($UncSourcePath) -and $File.StartsWith($UncSourcePath,[StringComparison]::OrdinalIgnoreCase)){$relative=$File.Substring($UncSourcePath.TrimEnd('\').Length).TrimStart('\')}}catch{}
        if([string]::IsNullOrWhiteSpace($relative)){$relative=[IO.Path]::GetFileName($File)}
        $sv=@{}
        if($Direction -eq 'In'){
            $sv['SourceSize']=$Bytes;$sv['CopyInBytes']=$Bytes;$sv['CopyInSeconds']=[Math]::Round($seconds,3);$sv['CopyInMBps']=$record.MBps;$sv['CopyInStarted']=$record.StartedUtc;$sv['CopyInCompleted']=$record.EndedUtc
        }else{
            $sv['FinalSize']=$Bytes;$sv['CopyBackBytes']=$Bytes;$sv['CopyBackSeconds']=[Math]::Round($seconds,3);$sv['CopyBackMBps']=$record.MBps;$sv['CopyBackStarted']=$record.StartedUtc;$sv['CopyBackCompleted']=$record.EndedUtc
        }
        Update-StatisticsSessionFile -SourcePath $(if($Direction -eq 'In'){$File}else{''}) -RelativePath $relative -QueueRoot $UncSourcePath -Values $sv -CopyEvent $record
        if($Script:VerboseLogging){Write-VerboseDiagnostic ('COPY {0}: fil={1}; bytes={2}; sek={3:N2}; snitt={4:N2} MB/s' -f $Direction,$File,$Bytes,$seconds,[double]$record.MBps)}
    } catch {
        if($Script:VerboseLogging){Write-VerboseDiagnostic ('COPY-statistik kunde inte sparas: {0}' -f $_.Exception.Message)}
    }
}

function Copy-VerifiedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $sourceInfo = Get-Item -LiteralPath $Source -ErrorAction Stop
    $destinationFolder = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destinationFolder -PathType Container)) {
        New-Item -Path $destinationFolder -ItemType Directory -Force | Out-Null
    }

    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $existing = Get-Item -LiteralPath $Destination -ErrorAction Stop
        if ($existing.Length -eq $sourceInfo.Length) { return $existing }
        Write-Status WARN ("Den lokala kopian är ofullständig eller har fel storlek och kopieras om: {0}" -f $Destination)
        Remove-Item -LiteralPath $Destination -Force -ErrorAction Stop
    }

    $temporary = $Destination + '.mediaprep-copying'
    if (Test-Path -LiteralPath $temporary -PathType Leaf) {
        $temporaryInfo = Get-Item -LiteralPath $temporary -ErrorAction SilentlyContinue
        if ($null -ne $temporaryInfo) {
            Write-Status WARN ("Tar bort tidigare ofullständig kopieringsfil ({0:N0} byte): {1}" -f $temporaryInfo.Length,$temporary)
        }
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
    try {
        Copy-Item -LiteralPath $Source -Destination $temporary -Force -ErrorAction Stop
        $copied = Get-Item -LiteralPath $temporary -ErrorAction Stop
        if ($copied.Length -ne $sourceInfo.Length) {
            throw "Storlekskontrollen misslyckades vid kopiering: $Source"
        }
        Move-Item -LiteralPath $temporary -Destination $Destination -Force
        return (Get-Item -LiteralPath $Destination -ErrorAction Stop)
    }
    finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Import-UncMediaFiles {
    param([Parameter(Mandatory = $true)][string]$SourcePath)

    if (-not (Test-UncPath -Path $SourcePath)) { throw 'UNC-sökvägen måste börja med \\.' }
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) { throw "UNC-mappen kunde inte nås: $SourcePath" }

    Write-Host ''
    Write-Status INFO ("Söker rekursivt efter TS/MP4/AVI/MPG/MPEG i UNC-mappen: {0}" -f $SourcePath)
    $videos = @(Get-ChildItem -LiteralPath $SourcePath -File -Recurse -ErrorAction Stop | Where-Object { $_.Extension -match '^\.(ts|mp4|avi|mpg|mpeg)$' } | Sort-Object FullName)
    $records = New-Object System.Collections.Generic.List[object]
    $total = $videos.Count

    for ($i=0; $i -lt $total; $i++) {
        $video = $videos[$i]
        $relative = Get-RelativePath -BasePath $SourcePath -FullPath $video.FullName
        $importPercent=[int](($i+1)*100/[Math]::Max(1,$total)); Write-Progress -Id 1 -Activity 'MediaPrep kontrollerar och kopierar från UNC' -Status ("{0} av {1} | {2} % | {3}" -f ($i+1),$total,$importPercent,$relative) -PercentComplete $importPercent
        try {
            $localVideo = Join-Path $Script:SourceFolder $relative
            $outputRelative = [IO.Path]::ChangeExtension($relative,'.mkv')
            $expectedOutput = Join-Path $Script:OutputFolder $outputRelative
            $localExists = Test-Path -LiteralPath $localVideo -PathType Leaf
            $outputExistedBefore = Test-Path -LiteralPath $expectedOutput -PathType Leaf
            $resumeExistingOutput = ($outputExistedBefore -and -not $localExists)
            $resumeNeedsRemux = ($outputExistedBefore -and $localExists)
            $copyDisposition = ''

            $outputSizeBefore=0L
            $outputModifiedBefore=''
            if ($outputExistedBefore) {
                $existingOutput=Get-Item -LiteralPath $expectedOutput -ErrorAction Stop
                $outputSizeBefore=[int64]$existingOutput.Length
                $outputModifiedBefore=$existingOutput.LastWriteTimeUtc.ToString('o')
            }

            if ($resumeExistingOutput) {
                Update-QueueDashboardItem -SourcePath $video.FullName -RelativePath $relative -QueueStage 4 -QueueStatus 'Muxed' -Values @{MuxedSize=[int64]$outputSizeBefore;FinalSize=[int64]$outputSizeBefore;MuxCompleted=(Get-Date).ToUniversalTime().ToString('o')}
                $copyDisposition='MKV finns i Processed och lokal källa saknas; UNC-kopiering hoppas över'
                Write-Status SKIP ("MKV finns redan i Processed; kopierar inte källfilen igen: {0}" -f $relative)
                $localVideoForRecord=''
            }
            else {
                $hadCompleteLocalCopy=$false
                if ($localExists) {
                    $localInfo=Get-Item -LiteralPath $localVideo -ErrorAction Stop
                    $hadCompleteLocalCopy=($localInfo.Length -eq $video.Length)
                }
                $copyInStarted=Get-Date
                Update-QueueDashboardItem -SourcePath $video.FullName -RelativePath $relative -QueueStage 1 -QueueStatus 'CopyingFromUNC' -Values @{CopyInStarted=$copyInStarted.ToUniversalTime().ToString('o')}
                $copiedVideo = Copy-VerifiedFile -Source $video.FullName -Destination $localVideo
                $copyInEnded=Get-Date
                Update-QueueDashboardItem -SourcePath $video.FullName -RelativePath $relative -QueueStage 2 -QueueStatus 'LocalSourceReady' -Values @{CopyInCompleted=$copyInEnded.ToUniversalTime().ToString('o')}
                if(-not $hadCompleteLocalCopy){Add-CopyStatistic -File $video.FullName -Direction In -Bytes ([int64]$video.Length) -Started $copyInStarted -Ended $copyInEnded}
                $localVideoForRecord=$localVideo
                if ($hadCompleteLocalCopy) {
                    $copyDisposition='Komplett lokal källa med samma storlek återanvändes'
                    Write-Status SKIP ("Komplett fil finns redan i UnProcessed; kopieringen hoppas över: {0}" -f $relative)
                }
                else {
                    $copyDisposition='Kopierad och storleksverifierad'
                    Write-Status OK ("UNC-import klar: {0}" -f $relative)
                }
                if ($resumeNeedsRemux) {
                    $Script:ResumeRemuxPaths[$localVideo.ToLowerInvariant()]=$true
                    $copyDisposition += '; befintlig MKV ska muxas om eftersom lokal källa finns kvar'
                    Write-Status WARN ("Både källfil och MKV finns; posten behandlas på nytt: {0}" -f $relative)
                }
            }

            $base = [IO.Path]::Combine($video.DirectoryName,[IO.Path]::GetFileNameWithoutExtension($video.Name))
            $subtitle = $null
            if (Test-Path -LiteralPath ($base + '.srt') -PathType Leaf) { $subtitle = Get-Item -LiteralPath ($base + '.srt') }
            elseif (Test-Path -LiteralPath ($base + '.vtt') -PathType Leaf) { $subtitle = Get-Item -LiteralPath ($base + '.vtt') }

            $remoteSubtitle=''; $localSubtitle=''; $subtitleSize=0L; $subtitleModified=''
            if ($null -ne $subtitle) {
                $remoteSubtitle=$subtitle.FullName
                $subtitleSize=[int64]$subtitle.Length
                $subtitleModified=$subtitle.LastWriteTimeUtc.ToString('o')
                if (-not $resumeExistingOutput) {
                    $localSubtitle=[IO.Path]::ChangeExtension($localVideo,$subtitle.Extension)
                    [void](Copy-VerifiedFile -Source $remoteSubtitle -Destination $localSubtitle)
                }
            }

            # Vid återstart med färdig lokal MKV läses längden direkt från UNC-källan.
            $durationSource = if ($resumeExistingOutput) { $video.FullName } else { $localVideo }
            $records.Add([PSCustomObject][ordered]@{
                RelativePath=$relative
                RemoteVideo=$video.FullName
                RemoteVideoSizeBytes=[int64]$video.Length
                RemoteVideoModifiedUtc=$video.LastWriteTimeUtc.ToString('o')
                RemoteSubtitle=$remoteSubtitle
                RemoteSubtitleSizeBytes=$subtitleSize
                RemoteSubtitleModifiedUtc=$subtitleModified
                LocalVideo=$localVideoForRecord
                LocalSubtitle=$localSubtitle
                ExpectedOutput=$expectedOutput
                RemoteOutput=(Join-Path $SourcePath $outputRelative)
                RunId=$Script:RunId
                OutputExistedBefore=[bool]$outputExistedBefore
                OutputSizeBeforeBytes=[int64]$outputSizeBefore
                OutputModifiedBeforeUtc=$outputModifiedBefore
                ResumeExistingOutput=[bool]$resumeExistingOutput
                ResumeNeedsRemux=[bool]$resumeNeedsRemux
                SourceDurationSeconds=[Math]::Round((Get-MediaDurationSeconds -Path $durationSource),3)
                ImportedUtc=(Get-Date).ToUniversalTime().ToString('o')
                ImportSuccess=$true
                Message=$copyDisposition
            })
        }
        catch {
            Update-QueueDashboardItem -SourcePath $video.FullName -RelativePath $relative -QueueStage 90 -QueueStatus 'Error' -Values @{ErrorMessage=$_.Exception.Message}
            Write-Status ERROR ("UNC-import misslyckades: {0} - {1}" -f $relative,$_.Exception.Message)
            $records.Add([PSCustomObject][ordered]@{
                RelativePath=$relative;RemoteVideo=$video.FullName;RemoteVideoSizeBytes=[int64]$video.Length;RemoteVideoModifiedUtc=$video.LastWriteTimeUtc.ToString('o')
                RemoteSubtitle='';RemoteSubtitleSizeBytes=0;RemoteSubtitleModifiedUtc='';LocalVideo='';LocalSubtitle='';ExpectedOutput='';RemoteOutput='';RunId=$Script:RunId
                OutputExistedBefore=$false;OutputSizeBeforeBytes=0;OutputModifiedBeforeUtc='';ResumeExistingOutput=$false;ResumeNeedsRemux=$false;SourceDurationSeconds=0
                ImportedUtc=(Get-Date).ToUniversalTime().ToString('o');ImportSuccess=$false;Message=$_.Exception.Message
            })
        }
    }
    Write-Progress -Id 1 -Activity 'MediaPrep kontrollerar och kopierar från UNC' -Completed
    Save-JsonFile -Path $Script:UncManifestPath -Value $records.ToArray()
    $report=Join-Path $Script:ReportFolder 'MediaPrep-UNC-import.csv'
    $records.ToArray() | Export-Csv -LiteralPath $report -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Status OK ("UNC-importmanifest sparat: {0}" -f $Script:UncManifestPath)
    return $records.ToArray()
}

function Test-FinalOutputForUncCleanup {
    param([Parameter(Mandatory = $true)][object]$Record)
    $localVideo=[string](Get-OptionalPropertyValue -Object $Record -Name 'LocalVideo' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($localVideo) -and (Test-Path -LiteralPath $localVideo -PathType Leaf)) {
        return [PSCustomObject]@{Valid=$false;Reason='Lokal källfil finns kvar; behandlingen blev inte färdig.'}
    }
    $output=[string](Get-OptionalPropertyValue -Object $Record -Name 'ExpectedOutput' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($output)) { return [PSCustomObject]@{Valid=$false;Reason='Sökvägen till slutlig MKV saknas i importposten.'} }
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { return [PSCustomObject]@{Valid=$false;Reason='Slutlig MKV saknas.'} }
    $outInfo=Get-Item -LiteralPath $output -ErrorAction Stop

    $recordRunId=[string](Get-OptionalPropertyValue -Object $Record -Name 'RunId' -DefaultValue '')
    if ($recordRunId -ne $Script:RunId) {
        return [PSCustomObject]@{Valid=$false;Reason='Importposten tillhör inte den aktuella körningen.'}
    }

    $existedBefore=[bool](Get-OptionalPropertyValue -Object $Record -Name 'OutputExistedBefore' -DefaultValue $false)
    if ($existedBefore) {
        $sizeBefore=[int64](Get-OptionalPropertyValue -Object $Record -Name 'OutputSizeBeforeBytes' -DefaultValue 0)
        $modifiedBefore=[string](Get-OptionalPropertyValue -Object $Record -Name 'OutputModifiedBeforeUtc' -DefaultValue '')
        $resumeExisting=[bool](Get-OptionalPropertyValue -Object $Record -Name 'ResumeExistingOutput' -DefaultValue $false)
        if (-not $resumeExisting -and $outInfo.Length -eq $sizeBefore -and $outInfo.LastWriteTimeUtc.ToString('o') -eq $modifiedBefore) {
            return [PSCustomObject]@{Valid=$false;Reason='En äldre lokal MKV med samma namn fanns redan och ändrades inte under denna körning.'}
        }
    }

    $sourceSize=[double]$Record.RemoteVideoSizeBytes
    $minRatio=[double]$Script:Config.UncMinimumFinalSizeRatio
    $maxRatio=[double]$Script:Config.UncMaximumFinalSizeRatio
    if ($outInfo.Length -lt [int64]$Script:Config.MinimumOutputSizeBytes) { return [PSCustomObject]@{Valid=$false;Reason='Slutlig MKV är mindre än minimigränsen.'} }
    if ($sourceSize -gt 0 -and (($outInfo.Length/$sourceSize) -lt $minRatio -or ($outInfo.Length/$sourceSize) -gt $maxRatio)) {
        return [PSCustomObject]@{Valid=$false;Reason=("Storleksförhållandet är orimligt: {0:N1} %." -f (($outInfo.Length/$sourceSize)*100))}
    }
    $sourceDuration=[double]$Record.SourceDurationSeconds
    $outputDuration=Get-MediaDurationSeconds -Path $output
    if ($sourceDuration -le 0 -or $outputDuration -le 0) { return [PSCustomObject]@{Valid=$false;Reason='Speltiden kunde inte verifieras.'} }
    $allowed=[Math]::Max([double]$Script:Config.UncDurationToleranceSeconds,$sourceDuration*([double]$Script:Config.UncDurationTolerancePercent/100.0))
    if ([Math]::Abs($sourceDuration-$outputDuration) -gt $allowed) { return [PSCustomObject]@{Valid=$false;Reason=("Speltiden avviker för mycket: källa {0:N1}s, mål {1:N1}s." -f $sourceDuration,$outputDuration)} }
    return [PSCustomObject]@{Valid=$true;Reason='Storlek och speltid verifierade.'}
}

function Copy-FileWithProgress {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][string]$Activity,
        [Parameter(Mandatory=$true)][string]$StatusPrefix
    )
    $sourceInfo=Get-Item -LiteralPath $Source -ErrorAction Stop
    $totalBytes=[double]$sourceInfo.Length
    $buffer=New-Object byte[] (4MB)
    $input=$null;$output=$null
    try {
        $input=[IO.File]::Open($Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $output=[IO.File]::Open($Destination,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $copied=0L
        $started=Get-Date
        while(($read=$input.Read($buffer,0,$buffer.Length)) -gt 0){
            $output.Write($buffer,0,$read)
            $copied += $read
            $percent=if($totalBytes -gt 0){[Math]::Min(100,[int](($copied/$totalBytes)*100))}else{0}
            $elapsed=((Get-Date)-$started).TotalSeconds
            $rate=if($elapsed -gt 0){$copied/$elapsed}else{0}
            $remaining=if($rate -gt 0){($totalBytes-$copied)/$rate}else{0}
            $status=("{0} | {1:N1} / {2:N1} MB | {3} % | kvar cirka {4}" -f $StatusPrefix,($copied/1MB),($totalBytes/1MB),$percent,(Format-MediaTime $remaining))
            Write-Progress -Activity $Activity -Status $status -PercentComplete $percent
        }
        $output.Flush()
    }
    finally {
        if($null -ne $output){$output.Dispose()}
        if($null -ne $input){$input.Dispose()}
    }
}

function Remove-EmptyLocalQueueFolders {
    param([object[]]$Records)
    foreach($root in @($Script:SourceFolder,$Script:OutputFolder)){
        if([string]::IsNullOrWhiteSpace([string]$root) -or -not(Test-Path -LiteralPath $root -PathType Container)){continue}
        $folders=@(Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)
        foreach($folder in $folders){
            if(@(Get-ChildItem -LiteralPath $folder.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0){
                Remove-Item -LiteralPath $folder.FullName -Force -ErrorAction SilentlyContinue
                if(-not(Test-Path -LiteralPath $folder.FullName)){Write-Status INFO ("Tog bort tom lokal kömapp: {0}" -f $folder.FullName)}
            }
        }
    }
}

function Get-MediaStreamProbeSummary {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [PSCustomObject]@{Success=$false;HasVideo=$false;HasAudio=$false;StreamTypes=@();Error='Filen saknas.'}
    }
    try {
        $jsonText=& $Script:FFprobePath -v error -show_entries stream=codec_type -of json -- $Path 2>&1
        $exit=$LASTEXITCODE
        $raw=(@($jsonText) -join "`n").Trim()
        if ($exit -ne 0) {
            return [PSCustomObject]@{Success=$false;HasVideo=$false;HasAudio=$false;StreamTypes=@();Error=("ffprobe exitkod {0}: {1}" -f $exit,$raw)}
        }
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [PSCustomObject]@{Success=$false;HasVideo=$false;HasAudio=$false;StreamTypes=@();Error='ffprobe returnerade inget resultat.'}
        }
        $doc=$raw | ConvertFrom-Json
        $types=@()
        if ($null -ne $doc -and $doc.PSObject.Properties['streams']) {
            foreach($st in @($doc.streams)) {
                if($null -ne $st -and $st.PSObject.Properties['codec_type']) {
                    $t=([string]$st.codec_type).Trim().ToLowerInvariant()
                    if(-not [string]::IsNullOrWhiteSpace($t)){$types += $t}
                }
            }
        }
        return [PSCustomObject]@{
            Success=$true
            HasVideo=(@($types | Where-Object { $_ -eq 'video' }).Count -gt 0)
            HasAudio=(@($types | Where-Object { $_ -eq 'audio' }).Count -gt 0)
            StreamTypes=@($types)
            Error=''
        }
    }
    catch {
        return [PSCustomObject]@{Success=$false;HasVideo=$false;HasAudio=$false;StreamTypes=@();Error=$_.Exception.Message}
    }
}

function Copy-FinalOutputBackToUnc {
    param([Parameter(Mandatory = $true)][object]$Record)

    $localOutput=[string]$Record.ExpectedOutput
    $remoteOutput=[string](Get-OptionalPropertyValue -Object $Record -Name 'RemoteOutput' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($remoteOutput)) {
        $remoteFolder=Split-Path -Parent ([string]$Record.RemoteVideo)
        $remoteOutput=Join-Path $remoteFolder ([IO.Path]::GetFileNameWithoutExtension([string]$Record.RemoteVideo)+'.mkv')
    }

    if (-not (Test-Path -LiteralPath $localOutput -PathType Leaf)) { throw 'Den lokala slutliga MKV-filen saknas.' }
    $localInfo=Get-Item -LiteralPath $localOutput -ErrorAction Stop
    $remoteFolder=Split-Path -Parent $remoteOutput
    if (-not (Test-Path -LiteralPath $remoteFolder -PathType Container)) {
        New-Item -Path $remoteFolder -ItemType Directory -Force | Out-Null
    }

    $temporary=$remoteOutput+'.mediaprep-copying'
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    try {
        $copyOutStarted=Get-Date
        Copy-FileWithProgress -Source $localOutput -Destination $temporary -Activity 'MediaPrep återför MKV till UNC' -StatusPrefix ([string]$Record.RelativePath)
        $copyOutEnded=Get-Date
        Add-CopyStatistic -File $remoteOutput -Direction Out -Bytes ([int64]$localInfo.Length) -Started $copyOutStarted -Ended $copyOutEnded
        $tempInfo=Get-Item -LiteralPath $temporary -ErrorAction Stop
        if ($tempInfo.Length -ne $localInfo.Length) { throw 'Storleken på UNC-kopian stämmer inte med den lokala MKV-filen.' }

        $localDuration=Get-MediaDurationSeconds -Path $localOutput
        $remoteDuration=Get-MediaDurationSeconds -Path $temporary
        if ($localDuration -le 0 -or $remoteDuration -le 0) { throw 'Speltiden på UNC-kopian kunde inte läsas.' }
        $allowed=[Math]::Max([double]$Script:Config.UncDurationToleranceSeconds,$localDuration*([double]$Script:Config.UncDurationTolerancePercent/100.0))
        if ([Math]::Abs($localDuration-$remoteDuration) -gt $allowed) { throw 'Speltiden på UNC-kopian avviker från den lokala MKV-filen.' }

        # Verifiera strömmarna med ffprobe JSON. Den äldre csv/textkontrollen kunde
        # feltolka giltiga MPEG/MPG -> MKV-filer som om videospår saknades.
        $streamProbe=Get-MediaStreamProbeSummary -Path $temporary
        if(-not $streamProbe.Success){throw ("ffprobe kunde inte verifiera UNC-kopian: {0}" -f $streamProbe.Error)}
        if(-not $streamProbe.HasVideo){throw 'UNC-kopian verifierades men innehåller inget videospår.'}
        if(-not $streamProbe.HasAudio){throw 'UNC-kopian verifierades men innehåller inget ljudspår.'}
        if($Script:VerboseLogging){Write-VerboseDiagnostic ("UNC verifierad med ffprobe: {0} | streams={1}" -f $temporary,(@($streamProbe.StreamTypes)-join ','))}

        if (Test-Path -LiteralPath $remoteOutput -PathType Leaf) {
            $existing=Get-Item -LiteralPath $remoteOutput -ErrorAction Stop
            if ($existing.Length -eq $localInfo.Length) {
                Remove-Item -LiteralPath $temporary -Force
            }
            else {
                $backup=$remoteOutput+'.mediaprep-backup'
                Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
                Move-Item -LiteralPath $remoteOutput -Destination $backup -Force
                try { Move-Item -LiteralPath $temporary -Destination $remoteOutput -Force; Remove-Item -LiteralPath $backup -Force }
                catch { if(Test-Path $remoteOutput){Remove-Item $remoteOutput -Force -ErrorAction SilentlyContinue}; Move-Item $backup $remoteOutput -Force; throw }
            }
        }
        else { Move-Item -LiteralPath $temporary -Destination $remoteOutput -Force }

        $published=Get-Item -LiteralPath $remoteOutput -ErrorAction Stop
        if ($published.Length -ne $localInfo.Length) { throw 'Slutkontrollen av UNC-filstorleken misslyckades.' }
        return [PSCustomObject]@{Success=$true;LocalOutput=$localOutput;RemoteOutput=$remoteOutput;SizeBytes=[int64]$published.Length;DurationSeconds=[Math]::Round($remoteDuration,3);Message='MKV återkopierad och verifierad'}
    }
    finally { Write-Progress -Activity 'MediaPrep återför MKV till UNC' -Completed; Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Publish-UncResultsAndCleanup {
    param(
        [Parameter(Mandatory = $true)][object[]]$Records,
        [bool]$DeleteOriginals
    )
    $results=New-Object System.Collections.Generic.List[object]
    $publishQueue=@($Records | Where-Object { $_.ImportSuccess })
    for($publishIndex=0;$publishIndex -lt $publishQueue.Count;$publishIndex++) {
        $record=$publishQueue[$publishIndex]
        $publishPercent=[int](($publishIndex+1)*100/[Math]::Max(1,$publishQueue.Count)); Write-Progress -Id 2 -Activity 'MediaPrep återför köresultat till UNC' -Status ("{0} av {1} | {2} % | {3}" -f ($publishIndex+1),$publishQueue.Count,$publishPercent,$record.RelativePath) -PercentComplete $publishPercent
        $success=$false;$deleted=0;$localRemoved=$false;$remoteOutput='';$message=''
        try {
            $check=Test-FinalOutputForUncCleanup -Record $record
            if (-not $check.Valid) { throw [string]$check.Reason }

            Update-QueueDashboardItem -SourcePath ([string]$record.RemoteVideo) -RelativePath ([string]$record.RelativePath) -QueueStage 9 -QueueStatus 'CopyingToUNC' -Values @{CopyBackStarted=(Get-Date).ToUniversalTime().ToString('o')}
            $published=Copy-FinalOutputBackToUnc -Record $record
            $remoteOutput=[string]$published.RemoteOutput
            Write-Status OK ("Färdig MKV återförd till UNC: {0}" -f $remoteOutput)

            if ($DeleteOriginals) {
                $remote=[string]$record.RemoteVideo
                if (-not (Test-Path -LiteralPath $remote -PathType Leaf)) { throw 'UNC-videofilen finns inte längre.' }
                $remoteInfo=Get-Item -LiteralPath $remote -ErrorAction Stop
                if ($remoteInfo.Length -ne [int64]$record.RemoteVideoSizeBytes -or $remoteInfo.LastWriteTimeUtc.ToString('o') -ne [string]$record.RemoteVideoModifiedUtc) { throw 'UNC-videofilen har ändrats sedan importen och raderas därför inte.' }
                Remove-Item -LiteralPath $remote -Force -ErrorAction Stop;$deleted++

                $remoteSubtitle=[string]$record.RemoteSubtitle
                if (-not [string]::IsNullOrWhiteSpace($remoteSubtitle) -and (Test-Path -LiteralPath $remoteSubtitle -PathType Leaf)) {
                    $subInfo=Get-Item -LiteralPath $remoteSubtitle -ErrorAction Stop
                    if ($subInfo.Length -eq [int64]$record.RemoteSubtitleSizeBytes -and $subInfo.LastWriteTimeUtc.ToString('o') -eq [string]$record.RemoteSubtitleModifiedUtc) {
                        Remove-Item -LiteralPath $remoteSubtitle -Force -ErrorAction Stop;$deleted++
                    } else { Write-Status WARN ("UNC-undertexten ändrades och behölls: {0}" -f $remoteSubtitle) }
                }
                Write-Status OK ("Tog bort gammal UNC-källa: {0}" -f $record.RelativePath)
            }

            $localOutput=[string]$record.ExpectedOutput
            if ($localOutput -ne [string]$published.LocalOutput) {
                throw 'Säkerhetskontrollen stoppade lokal borttagning: sökvägen matchar inte den publicerade filen.'
            }
            if (Test-Path -LiteralPath $localOutput -PathType Leaf) {
                $localDeleteInfo=Get-Item -LiteralPath $localOutput -ErrorAction Stop
                if ($localDeleteInfo.Length -ne [int64]$published.SizeBytes) {
                    throw 'Säkerhetskontrollen stoppade lokal borttagning: filstorleken har ändrats efter återföringen.'
                }
                Remove-Item -LiteralPath $localOutput -Force -ErrorAction Stop
                $localRemoved=$true
                Write-Status OK ("Tog bort lokal MKV efter verifierad återkopiering: {0}" -f $localOutput)
            }
            $success=$true;$message='MKV återkopierad och verifierad.'
            Update-QueueDashboardItem -SourcePath ([string]$record.RemoteVideo) -RelativePath ([string]$record.RelativePath) -QueueStage 10 -QueueStatus 'Completed' -Values @{FinalSize=[int64]$published.SizeBytes;CopyBackCompleted=(Get-Date).ToUniversalTime().ToString('o');CompletedUtc=(Get-Date).ToUniversalTime().ToString('o');ErrorMessage=$null}
            if ($DeleteOriginals) {$message+=' UNC-original borttaget.'} else {$message+=' UNC-original behållet enligt inställning.'}
        }
        catch {
            $message=$_.Exception.Message
            Update-QueueDashboardItem -SourcePath ([string]$record.RemoteVideo) -RelativePath ([string]$record.RelativePath) -QueueStage 90 -QueueStatus 'Error' -Values @{ErrorMessage=$message;ErrorKind='Publish';ErrorPreviousStage=8;ErrorLocalPath=[string]$record.ExpectedOutput}
            Write-Status WARN ("UNC-resultatet kunde inte slutföras: {0} - {1}" -f $record.RelativePath,$message)
        }
        $results.Add([PSCustomObject][ordered]@{RelativePath=$record.RelativePath;Success=$success;RemoteOutput=$remoteOutput;OriginalsDeleted=$deleted;LocalMkvRemoved=$localRemoved;Message=$message;CompletedUtc=(Get-Date).ToUniversalTime().ToString('o')})
    }
    Write-Progress -Id 2 -Activity 'MediaPrep återför köresultat till UNC' -Completed
    Remove-EmptyLocalQueueFolders -Records $Records
    $report=Join-Path $Script:ReportFolder 'MediaPrep-UNC-aterforing.csv'
    $results.ToArray() | Export-Csv -LiteralPath $report -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Status OK ("UNC-återföringsrapport sparad: {0}" -f $report)
    return $results.ToArray()
}

#endregion

#region Skanning
function Find-SubtitleForVideo {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$VideoFile)

    $baseName = $VideoFile.BaseName
    $folder = $VideoFile.DirectoryName

    # SRT prioriteras om både SRT och VTT finns.
    foreach ($extension in @('.srt', '.vtt')) {
        $candidate = Join-Path $folder ($baseName + $extension)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return Get-Item -LiteralPath $candidate
        }
    }

    # Fångar även filändelser med annan versalisering, t.ex. .SRT.
    $matches = Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | Where-Object {
        $_.BaseName -ieq $baseName -and $_.Extension.ToLowerInvariant() -in @('.srt', '.vtt')
    } | Sort-Object @{ Expression = { if ($_.Extension -ieq '.srt') { 0 } else { 1 } } }, Name

    return $matches | Select-Object -First 1
}

function Get-ActionState {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$VideoFile,
        [System.IO.FileInfo]$SubtitleFile,
        [Parameter(Mandatory = $true)][string]$OutputFile
    )

    if ($Force) {
        return [PSCustomObject]@{ NeedsProcessing = $true; Reason = 'Tvingad ommuxning' }
    }

    $resumeKey = $VideoFile.FullName.ToLowerInvariant()
    if ($Script:ResumeRemuxPaths.ContainsKey($resumeKey)) {
        return [PSCustomObject]@{ NeedsProcessing = $true; Reason = 'Tidigare körning blev inte färdig; muxas om' }
    }

    if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
        return [PSCustomObject]@{ NeedsProcessing = $true; Reason = 'MKV saknas' }
    }

    if (-not [bool]$Script:Config.SkipIfOutputExists) {
        return [PSCustomObject]@{ NeedsProcessing = $true; Reason = 'SkipIfOutputExists är avstängt' }
    }

    if (-not [bool]$Script:Config.UseFileDateCheck) {
        return [PSCustomObject]@{ NeedsProcessing = $false; Reason = 'MKV finns' }
    }

    $outputInfo = Get-Item -LiteralPath $OutputFile
    if ($VideoFile.LastWriteTimeUtc -gt $outputInfo.LastWriteTimeUtc) {
        return [PSCustomObject]@{ NeedsProcessing = $true; Reason = 'Videofilen är nyare än MKV' }
    }

    if ($null -ne $SubtitleFile -and $SubtitleFile.LastWriteTimeUtc -gt $outputInfo.LastWriteTimeUtc) {
        return [PSCustomObject]@{ NeedsProcessing = $true; Reason = 'Undertexten är nyare än MKV' }
    }

    return [PSCustomObject]@{ NeedsProcessing = $false; Reason = 'MKV är aktuell' }
}

function Invoke-SourceFFprobe {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File)

    # Starta ffprobe via System.Diagnostics.Process. I Windows PowerShell 5.1 kan
    # native stderr annars omvandlas till NativeCommandError när ErrorActionPreference
    # är Stop, vilket tidigare kunde avbryta hela kön på en enda trasig fil.
    $arguments = @(
        '-v','error',
        '-print_format','json',
        '-show_format',
        '-show_streams',
        $File.FullName
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Script:FFprobePath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Arguments = (($arguments | ForEach-Object {
        $a = [string]$_
        if ($a -match '[\s"]') { '"' + $a.Replace('"','\"') + '"' } else { $a }
    }) -join ' ')

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        if (-not $process.Start()) { throw 'ffprobe kunde inte startas.' }
        $raw = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    }
    finally {
        if ($null -ne $process) { $process.Dispose() }
    }

    if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        $detail = if (-not [string]::IsNullOrWhiteSpace($stderr)) { $stderr.Trim() } else { 'Ingen ffprobe-detalj.' }
        throw ("ffprobe kunde inte analysera källfilen. Exitkod: {0}. {1}" -f $exitCode,$detail)
    }

    $doc = $raw | ConvertFrom-Json
    $videoStreams = @($doc.streams | Where-Object { $_.codec_type -eq 'video' })
    $audioStreams = @($doc.streams | Where-Object { $_.codec_type -eq 'audio' })
    $subtitleStreams = @($doc.streams | Where-Object { $_.codec_type -eq 'subtitle' })
    if ($videoStreams.Count -eq 0) { throw 'ffprobe hittade ingen videoström i källfilen.' }

    $video = $videoStreams[0]
    $duration = Convert-ToDoubleInvariant (Get-OptionalPropertyValue -Object $doc.format -Name 'duration' -DefaultValue 0)
    if ($duration -le 0) { $duration = Convert-ToDoubleInvariant (Get-OptionalPropertyValue -Object $video -Name 'duration' -DefaultValue 0) }
    $bitrate = Convert-ToDoubleInvariant (Get-OptionalPropertyValue -Object $doc.format -Name 'bit_rate' -DefaultValue 0)
    if ($bitrate -le 0 -and $duration -gt 0 -and $File.Length -gt 0) { $bitrate = ($File.Length * 8.0) / $duration }
    $fpsValue = [string](Get-OptionalPropertyValue -Object $video -Name 'avg_frame_rate' -DefaultValue '0/0')
    if ($fpsValue -eq '0/0') { $fpsValue = [string](Get-OptionalPropertyValue -Object $video -Name 'r_frame_rate' -DefaultValue '0/0') }

    $audioCodecs = @($audioStreams | ForEach-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'codec_name' -DefaultValue 'unknown') } | Select-Object -Unique)
    $container = [string](Get-OptionalPropertyValue -Object $doc.format -Name 'format_name' -DefaultValue '')

    $result = [PSCustomObject][ordered]@{
        Container = $container
        VideoCodec = [string](Get-OptionalPropertyValue -Object $video -Name 'codec_name' -DefaultValue 'unknown')
        VideoProfile = [string](Get-OptionalPropertyValue -Object $video -Name 'profile' -DefaultValue '')
        PixelFormat = [string](Get-OptionalPropertyValue -Object $video -Name 'pix_fmt' -DefaultValue '')
        Width = [int](Get-OptionalPropertyValue -Object $video -Name 'width' -DefaultValue 0)
        Height = [int](Get-OptionalPropertyValue -Object $video -Name 'height' -DefaultValue 0)
        FPS = [Math]::Round((Get-FrameRate $fpsValue),3)
        DurationSeconds = [Math]::Round($duration,3)
        Bitrate = [int64][Math]::Round($bitrate,0)
        VideoStreams = [int]$videoStreams.Count
        AudioTracks = [int]$audioStreams.Count
        AudioCodecs = ($audioCodecs -join ', ')
        SubtitleTracks = [int]$subtitleStreams.Count
        ProbedUtc = (Get-Date).ToUniversalTime().ToString('o')
    }

    Write-Status INFO ("ffprobe källa: {0} | container={1} | video={2} | audio={3} | {4}x{5} | {6:N3} fps | {7:N1} min" -f $File.Name,$result.Container,$result.VideoCodec,$result.AudioCodecs,$result.Width,$result.Height,$result.FPS,($result.DurationSeconds/60.0))
    if ($Script:VerboseLogging) {
        Write-VerboseDiagnostic ("SOURCE PROBE: fil={0}; container={1}; video={2}; profile={3}; pixfmt={4}; resolution={5}x{6}; fps={7}; duration={8}; bitrate={9}; videoStreams={10}; audioTracks={11}; audio={12}; subtitleTracks={13}" -f $File.FullName,$result.Container,$result.VideoCodec,$result.VideoProfile,$result.PixelFormat,$result.Width,$result.Height,$result.FPS,$result.DurationSeconds,$result.Bitrate,$result.VideoStreams,$result.AudioTracks,$result.AudioCodecs,$result.SubtitleTracks)
    }
    return $result
}

function Scan-MediaLibrary {
    param(
        [switch]$AllowEmptyIncludeList
    )

    $extensions = @($Script:Config.SupportedVideoFormats | ForEach-Object { $_.ToString().ToLowerInvariant() })

    $scanParameters = @{
        LiteralPath = $Script:SourceFolder
        File = $true
        ErrorAction = 'Stop'
    }
    if ([bool]$Script:Config.Recursive) {
        $scanParameters.Recurse = $true
    }

    $videoFiles = @(Get-ChildItem @scanParameters | Where-Object {
        $extensions -contains $_.Extension.ToLowerInvariant()
    } | Sort-Object FullName)

    # Optional ordered include list used by Start Center's All in one mode.
    # Use the selected absolute paths directly instead of scanning and matching them again.
    if (-not [string]::IsNullOrWhiteSpace($IncludeListPath)) {
        if (-not (Test-Path -LiteralPath $IncludeListPath -PathType Leaf)) {
            throw ("Include list was not found: {0}" -f $IncludeListPath)
        }

        $includePaths = @((Get-Content -LiteralPath $IncludeListPath -Raw -Encoding UTF8 | ConvertFrom-Json))
        $selectedFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
        $missingFiles = New-Object System.Collections.Generic.List[string]
        $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($includeEntry in $includePaths) {
            $includePath = [string]$includeEntry
            if ([string]::IsNullOrWhiteSpace($includePath)) { continue }

            try {
                $fullPath = [System.IO.Path]::GetFullPath($includePath)
            }
            catch {
                $missingFiles.Add($includePath)
                continue
            }

            if (-not $seenPaths.Add($fullPath)) { continue }

            if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
                $selectedFile = Get-Item -LiteralPath $fullPath -ErrorAction Stop
                if ($extensions -contains $selectedFile.Extension.ToLowerInvariant()) {
                    $selectedFiles.Add($selectedFile)
                }
            }
            else {
                $missingFiles.Add($fullPath)
            }
        }

        $videoFiles = @($selectedFiles.ToArray())
        Write-Status INFO ("All in one file list active. Selected files: {0}" -f $videoFiles.Count)

        if ($missingFiles.Count -gt 0) {
            foreach ($missingFile in $missingFiles) {
                Write-Status WARN ("Selected file was not found and will be skipped: {0}" -f $missingFile)
            }
        }

        if ($videoFiles.Count -eq 0) {
            if ($AllowEmptyIncludeList) {
                Write-Status INFO 'All in one source files have already been processed. The empty source list is expected during the post-mux check.'
            }
            else {
                throw 'All in one contains no existing TS, MP4, AVI, MPG or MPEG files to process.'
            }
        }
    }

    $results = New-Object System.Collections.Generic.List[object]
    $total = $videoFiles.Count
    $started = Get-Date

    for ($i = 0; $i -lt $total; $i++) {
        $video = $videoFiles[$i]
        $percent = if ($total -gt 0) { [int](($i + 1) * 100 / $total) } else { 100 }
        $elapsed = (Get-Date) - $started
        $etaText = 'Beräknar...'
        if ($i -ge 1) {
            $secondsPerItem = $elapsed.TotalSeconds / ($i + 1)
            $remainingSeconds = [Math]::Max(0, $secondsPerItem * ($total - ($i + 1)))
            $etaText = ([TimeSpan]::FromSeconds($remainingSeconds)).ToString('hh\:mm\:ss')
        }

        $relativeVideo = Get-RelativePath -BasePath $Script:SourceFolder -FullPath $video.FullName
        Write-Progress -Activity 'MediaPrep skannar biblioteket' -Status ("{0} av {1}: {2} | ETA {3}" -f ($i + 1), $total, $relativeVideo, $etaText) -PercentComplete $percent

        try {
            $sourceProbe = Invoke-SourceFFprobe -File $video
        }
        catch {
            $probeReason = "Källfil kunde inte analyseras med ffprobe: {0}" -f $_.Exception.Message
            Write-Status ERROR ("{0}: {1}" -f $video.FullName,$probeReason)

            # En trasig eller icke-läsbar lokal källfil får inte stoppa hela kön.
            # Flytta den lokala arbetskopian till Error och fortsätt med nästa fil.
            try {
                $errorRelative = $relativeVideo
                $errorPath = Join-Path $Script:ErrorFolder $errorRelative
                $errorDir = Split-Path -Parent $errorPath
                Ensure-Directory $errorDir
                if (Test-Path -LiteralPath $errorPath -PathType Leaf) { Remove-Item -LiteralPath $errorPath -Force }
                Move-Item -LiteralPath $video.FullName -Destination $errorPath -Force

                Update-QueueDashboardItem -RelativePath $errorRelative -QueueStage 90 -QueueStatus 'Error' -Values @{
                    ErrorMessage = $probeReason
                    ErrorKind = 'SourceProbe'
                    ErrorPreviousStage = 2
                    ErrorLocalPath = $errorPath
                }

                $existingErrorRecords = @(Get-ErrorQueueRecords | Where-Object { [string]$_.ErrorPath -ne $errorPath })
                $existingErrorRecords += [PSCustomObject]@{
                    AddedUtc = (Get-Date).ToUniversalTime().ToString('o')
                    RelativePath = $errorRelative
                    OriginalPath = $video.FullName
                    ErrorPath = $errorPath
                    Reason = $probeReason
                    ErrorKind = 'SourceProbe'
                    DurationSeconds = 0
                    TargetSizeMB = 0
                    TargetVideoBitrateKbps = 0
                }
                Save-ErrorQueueRecords -Records $existingErrorRecords
                Write-Status WARN ("Flyttad till felkö efter ffprobe-fel: {0}" -f $errorRelative)
            }
            catch {
                Write-Status ERROR ("Kunde inte flytta den felaktiga källfilen till felkön: {0}" -f $_.Exception.Message)
            }

            continue
        }
        $subtitle = Find-SubtitleForVideo -VideoFile $video
        $relativeDirectory = Split-Path -Parent $relativeVideo
        $outputDirectory = if ([string]::IsNullOrWhiteSpace($relativeDirectory)) {
            $Script:OutputFolder
        }
        else {
            Join-Path $Script:OutputFolder $relativeDirectory
        }
        $outputFile = Join-Path $outputDirectory ($video.BaseName + '.mkv')
        $action = Get-ActionState -VideoFile $video -SubtitleFile $subtitle -OutputFile $outputFile

        $subtitlePath = $null
        $subtitleType = 'Ingen'
        $subtitleModifiedUtc = $null
        if ($null -ne $subtitle) {
            $subtitlePath = $subtitle.FullName
            $subtitleType = $subtitle.Extension.TrimStart('.').ToUpperInvariant()
            $subtitleModifiedUtc = $subtitle.LastWriteTimeUtc.ToString('o')
        }

        $results.Add([PSCustomObject][ordered]@{
            RelativePath = $relativeVideo
            VideoFile = $video.FullName
            VideoExtension = $video.Extension.ToLowerInvariant()
            VideoSizeBytes = [Int64]$video.Length
            VideoModifiedUtc = $video.LastWriteTimeUtc.ToString('o')
            Probe = $sourceProbe
            ProbeContainer = [string]$sourceProbe.Container
            ProbeVideoCodec = [string]$sourceProbe.VideoCodec
            ProbeAudioCodecs = [string]$sourceProbe.AudioCodecs
            ProbeDurationSeconds = [double]$sourceProbe.DurationSeconds
            SubtitleFile = $subtitlePath
            SubtitleType = $subtitleType
            SubtitleModifiedUtc = $subtitleModifiedUtc
            OutputFile = $outputFile
            NeedsProcessing = [bool]$action.NeedsProcessing
            Reason = $action.Reason
            Status = if ($action.NeedsProcessing) { 'Pending' } else { 'Current' }
            LastScannedUtc = (Get-Date).ToUniversalTime().ToString('o')
        })
    }

    Write-Progress -Activity 'MediaPrep skannar biblioteket' -Completed
    return $results.ToArray()
}
#endregion


#region Muxning
function Convert-VttToTemporarySrt {
    param(
        [Parameter(Mandatory = $true)][string]$VttFile
    )

    $temporarySrt = Join-Path $Script:TempFolder ("{0}.srt" -f ([Guid]::NewGuid().ToString('N')))
    Write-Status INFO ("Konverterar VTT till tillfällig SRT: {0}" -f (Split-Path -Leaf $VttFile))

    & $Script:FFmpegPath -hide_banner -loglevel error -y -i $VttFile $temporarySrt 2>&1 | Out-Null
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $temporarySrt -PathType Leaf)) {
        Remove-Item -LiteralPath $temporarySrt -Force -ErrorAction SilentlyContinue
        throw "VTT-konverteringen misslyckades med exitkod $exitCode."
    }

    return $temporarySrt
}


function Test-ValidMuxOutput {
    param(
        [Parameter(Mandatory = $true)][string]$OutputFile
    )

    if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
        return $false
    }

    $minimumSize = 1
    if ($null -ne $Script:Config.MinimumOutputSizeBytes) {
        $minimumSize = [int64]$Script:Config.MinimumOutputSizeBytes
    }

    $outputInfo = Get-Item -LiteralPath $OutputFile -ErrorAction Stop
    return ($outputInfo.Length -ge $minimumSize)
}

function Remove-SourceFilesAfterMux {
    param(
        [Parameter(Mandatory = $true)][object]$Item
    )

    $deletedFiles = New-Object System.Collections.Generic.List[string]

    if (-not [bool]$Script:Config.DeleteSourceAfterSuccessfulMux) {
        return $deletedFiles.ToArray()
    }

    if (-not (Test-ValidMuxOutput -OutputFile $Item.OutputFile)) {
        throw 'Källfilerna behölls eftersom den skapade MKV-filen saknas eller är för liten.'
    }

    $filesToDelete = New-Object System.Collections.Generic.List[string]
    $filesToDelete.Add([string]$Item.VideoFile)

    if (-not [string]::IsNullOrWhiteSpace([string]$Item.SubtitleFile)) {
        $filesToDelete.Add([string]$Item.SubtitleFile)
    }

    foreach ($filePath in $filesToDelete.ToArray() | Select-Object -Unique) {
        if (Test-Path -LiteralPath $filePath -PathType Leaf) {
            Remove-Item -LiteralPath $filePath -Force -ErrorAction Stop
            $deletedFiles.Add($filePath)
            Write-Status OK ("Tog bort källfil: {0}" -f $filePath)
        }
    }

    return $deletedFiles.ToArray()
}

function Remove-EmptySourceFolders {
    if (-not [bool]$Script:Config.RemoveEmptySourceFolders) {
        return
    }

    $folders = @(Get-ChildItem -LiteralPath $Script:SourceFolder -Directory -Recurse -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending)

    foreach ($folder in $folders) {
        $remaining = @(Get-ChildItem -LiteralPath $folder.FullName -Force -ErrorAction SilentlyContinue)
        if ($remaining.Count -eq 0) {
            Remove-Item -LiteralPath $folder.FullName -Force -ErrorAction SilentlyContinue
            Write-Status INFO ("Tog bort tom mapp: {0}" -f $folder.FullName)
        }
    }
}

function Invoke-MuxItem {
    param(
        [Parameter(Mandatory = $true)][object]$Item
    )

    $outputDirectory = Split-Path -Parent $Item.OutputFile
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    }

    $temporarySubtitle = $null
    $subtitleToMux = $Item.SubtitleFile

    try {
        if ($Item.SubtitleType -eq 'VTT') {
            $temporarySubtitle = Convert-VttToTemporarySrt -VttFile $Item.SubtitleFile
            $subtitleToMux = $temporarySubtitle
        }

        $arguments = New-Object System.Collections.Generic.List[string]
        $arguments.Add('--output')
        $arguments.Add($Item.OutputFile)
        $arguments.Add($Item.VideoFile)

        if (-not [string]::IsNullOrWhiteSpace($subtitleToMux)) {
            $language = [string]$Script:Config.SubtitleLanguage
            $trackName = [string]$Script:Config.SubtitleTrackName

            if ([string]::IsNullOrWhiteSpace($language)) { $language = 'swe' }
            if ([string]::IsNullOrWhiteSpace($trackName)) { $trackName = 'Svenska' }

            $arguments.Add('--language')
            $arguments.Add(("0:{0}" -f $language))
            $arguments.Add('--track-name')
            $arguments.Add(("0:{0}" -f $trackName))
            $arguments.Add($subtitleToMux)
        }

        if (Test-Path -LiteralPath $Item.OutputFile -PathType Leaf) {
            Remove-Item -LiteralPath $Item.OutputFile -Force
        }

        & $Script:MKVMergePath $arguments.ToArray() 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE

        # mkvmerge: 0 = klart, 1 = klart med varningar, 2+ = fel.
        if ($exitCode -gt 1 -or -not (Test-ValidMuxOutput -OutputFile $Item.OutputFile)) {
            Remove-Item -LiteralPath $Item.OutputFile -Force -ErrorAction SilentlyContinue
            throw "mkvmerge misslyckades eller skapade en ogiltig MKV-fil. Exitkod: $exitCode."
        }

        $deletedFiles = @(Remove-SourceFilesAfterMux -Item $Item)

        return [PSCustomObject]@{
            Success = $true
            Message = 'MKV skapad och verifierad'
            DeletedFiles = ($deletedFiles -join ' | ')
            DeletedCount = $deletedFiles.Count
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
            DeletedFiles = ''
            DeletedCount = 0
        }
    }
    finally {
        if ($temporarySubtitle -and (Test-Path -LiteralPath $temporarySubtitle -PathType Leaf)) {
            Remove-Item -LiteralPath $temporarySubtitle -Force -ErrorAction SilentlyContinue
        }
    }
}

function Remove-CompletedFileFromIncludeList {
    param(
        [Parameter(Mandatory = $true)][string]$CompletedFile
    )

    if ([string]::IsNullOrWhiteSpace($IncludeListPath)) { return }
    if (-not (Test-Path -LiteralPath $IncludeListPath -PathType Leaf)) { return }

    try {
        $completedFullPath = [System.IO.Path]::GetFullPath($CompletedFile)
        $currentEntries = @((Get-Content -LiteralPath $IncludeListPath -Raw -Encoding UTF8 | ConvertFrom-Json))
        $remaining = New-Object System.Collections.Generic.List[string]

        foreach ($entry in $currentEntries) {
            $entryText = [string]$entry
            if ([string]::IsNullOrWhiteSpace($entryText)) { continue }

            $entryFullPath = $entryText
            try { $entryFullPath = [System.IO.Path]::GetFullPath($entryText) } catch { }

            if (-not [string]::Equals($entryFullPath, $completedFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $remaining.Add($entryText)
            }
        }

        $json = ConvertTo-Json -InputObject @($remaining.ToArray()) -Depth 5
        [System.IO.File]::WriteAllText($IncludeListPath, $json, (New-Object System.Text.UTF8Encoding($true)))
        Write-Status INFO ("All in one-kön uppdaterad. Återstår: {0} filer." -f $remaining.Count)
    }
    catch {
        Write-Status WARN ("Kunde inte uppdatera All in one-kön efter färdig fil: {0}" -f $_.Exception.Message)
    }
}

function Invoke-MuxQueue {
    param(
        [Parameter(Mandatory = $true)][object[]]$Items
    )

    $queue = @($Items | Where-Object { $_.NeedsProcessing })
    $results = New-Object System.Collections.Generic.List[object]
    $total = $queue.Count
    $started = Get-Date

    if ($total -eq 0) {
        Write-Status OK 'Alla MKV-filer är redan aktuella. Ingen muxning behövs.'
        return $results.ToArray()
    }

    for ($i = 0; $i -lt $total; $i++) {
        $item = $queue[$i]
        $percent = [int](($i + 1) * 100 / $total)
        $elapsed = (Get-Date) - $started
        $etaText = 'Beräknar...'

        if ($i -ge 1) {
            $secondsPerItem = $elapsed.TotalSeconds / ($i + 1)
            $remainingSeconds = [Math]::Max(0, $secondsPerItem * ($total - ($i + 1)))
            $etaText = ([TimeSpan]::FromSeconds($remainingSeconds)).ToString('hh\:mm\:ss')
        }

        Write-Progress -Activity 'MediaPrep muxar till MKV' -Status ("{0} av {1}: {2} | ETA {3}" -f ($i + 1), $total, $item.RelativePath, $etaText) -PercentComplete $percent
        Write-Status INFO ("Muxar: {0}" -f $item.RelativePath)
        $muxValues=@{MuxStarted=(Get-Date).ToUniversalTime().ToString('o')}
        if($item.PSObject.Properties['Probe'] -and $null -ne $item.Probe){$muxValues['Probe']=$item.Probe}
        Update-QueueDashboardItem -RelativePath ([string]$item.RelativePath) -QueueStage 3 -QueueStatus 'Muxing' -Values $muxValues

        $result = @(Invoke-MuxItem -Item $item) |
            Where-Object { $_ -and ($_.PSObject.Properties.Name -contains 'Success') } |
            Select-Object -Last 1

        if ($null -eq $result) {
            $result = [PSCustomObject]@{
                Success = $false
                Message = 'Muxfunktionen returnerade inget giltigt resultat.'
                DeletedFiles = ''
                DeletedCount = 0
            }
        }

        if ($result.Success) {
            $muxInfo=Get-Item -LiteralPath ([string]$item.OutputFile) -ErrorAction SilentlyContinue
            $muxBytes=if($null -ne $muxInfo){[int64]$muxInfo.Length}else{$null}
            Update-QueueDashboardItem -RelativePath ([string]$item.RelativePath) -QueueStage 4 -QueueStatus 'Muxed' -Values @{MuxedSize=$muxBytes;FinalSize=$muxBytes;MuxCompleted=(Get-Date).ToUniversalTime().ToString('o');ErrorMessage=$null}
            Write-Status OK ("Klar: {0}" -f $item.OutputFile)
            Remove-CompletedFileFromIncludeList -CompletedFile ([string]$item.VideoFile)
        }
        else {
            Update-QueueDashboardItem -RelativePath ([string]$item.RelativePath) -QueueStage 90 -QueueStatus 'Error' -Values @{ErrorMessage=[string]$result.Message}
            Write-Status ERROR ("Misslyckades: {0} - {1}" -f $item.RelativePath, $result.Message)
        }

        $results.Add([PSCustomObject][ordered]@{
            RelativePath = $item.RelativePath
            OutputFile = $item.OutputFile
            SubtitleType = $item.SubtitleType
            Success = [bool]$result.Success
            Message = $result.Message
            DeletedCount = [int]$result.DeletedCount
            DeletedFiles = [string]$result.DeletedFiles
            CompletedUtc = (Get-Date).ToUniversalTime().ToString('o')
        })
    }

    Write-Progress -Activity 'MediaPrep muxar till MKV' -Completed
    Remove-EmptySourceFolders
    return $results.ToArray()
}
#endregion


#region Analys och rekommendationer

function Get-OptionalPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$DefaultValue = $null
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

function Convert-ToDoubleInvariant {
    param([object]$Value)

    if ($null -eq $Value) { return 0.0 }

    $number = 0.0
    if ([double]::TryParse(
        [string]$Value,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$number
    )) {
        return $number
    }

    return 0.0
}

function Get-FrameRate {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -eq '0/0') {
        return 0.0
    }

    if ($Value -match '^(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)$') {
        $numerator = Convert-ToDoubleInvariant $matches[1]
        $denominator = Convert-ToDoubleInvariant $matches[2]
        if ($denominator -ne 0) {
            return [Math]::Round(($numerator / $denominator), 3)
        }
    }

    return [Math]::Round((Convert-ToDoubleInvariant $Value), 3)
}

function Get-MediaClassification {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][double]$DurationMinutes
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $episodePatterns = @(
        '(?i)(?:^|[\s._-])S\s*\d{1,2}\s*E\s*\d{1,3}(?:$|[\s._-])',
        '(?i)(?:^|[\s._-])\d{1,2}\s*[xX]\s*\d{1,3}(?:$|[\s._-])'
    )

    foreach ($pattern in $episodePatterns) {
        if ($baseName -match $pattern) {
            return [PSCustomObject]@{ MediaType = 'TV'; Reason = 'EpisodePattern' }
        }
    }

    if ($baseName -match '(?<!\d)(?:19|20)\d{2}(?!\d)') {
        return [PSCustomObject]@{ MediaType = 'Film'; Reason = 'YearPattern' }
    }

    if ($DurationMinutes -gt 0 -and $DurationMinutes -le [double]$Script:Config.TvDurationThresholdMinutes) {
        return [PSCustomObject]@{ MediaType = 'TV'; Reason = 'DurationFallback' }
    }

    return [PSCustomObject]@{ MediaType = 'Film'; Reason = 'DefaultFallback' }
}

function Get-VideoRecommendation {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$Codec,
        [Parameter(Mandatory = $true)][double]$FileSizeMB,
        [Parameter(Mandatory = $true)][double]$DurationMinutes
    )

    $classification = Get-MediaClassification -FileName $FileName -DurationMinutes $DurationMinutes
    $mediaType = [string]$classification.MediaType
    $codecLower = $Codec.ToLowerInvariant()

    $targetMBPerMinute = if ($mediaType -eq 'TV') {
        [double]$Script:Config.TVTargetMBPerMinute
    }
    else {
        [double]$Script:Config.MovieTargetMBPerMinute
    }

    $thresholdMultiplier = [double]$Script:Config.EncodeThresholdMultiplier
    $minimumSavingPercent = [double]$Script:Config.MinimumSavingPercent
    $currentMBPerMinute = if ($DurationMinutes -gt 0) { $FileSizeMB / $DurationMinutes } else { 0 }
    $targetSizeMB = if ($DurationMinutes -gt 0) { $DurationMinutes * $targetMBPerMinute } else { 0 }
    $thresholdMBPerMinute = $targetMBPerMinute * $thresholdMultiplier
    $estimatedSavingPercent = if ($FileSizeMB -gt 0 -and $targetSizeMB -gt 0) {
        [Math]::Max(0, (($FileSizeMB - $targetSizeMB) / $FileSizeMB) * 100.0)
    }
    else { 0 }

    $alreadyEfficient = ($codecLower -match 'hevc|h265|av1')
    $ratioExceeded = ($currentMBPerMinute -gt $thresholdMBPerMinute)
    $savingEnough = ($estimatedSavingPercent -ge $minimumSavingPercent)
    $recommended = (-not $alreadyEfficient -and $ratioExceeded -and $savingEnough)

    if ($alreadyEfficient) {
        $level = 'Ingen'
        $reason = 'Videon använder redan HEVC/H.265 eller AV1.'
    }
    elseif (-not $ratioExceeded) {
        $level = 'Låg'
        $reason = ('{0:N1} MB/min ligger inte över tröskeln {1:N1} MB/min.' -f $currentMBPerMinute,$thresholdMBPerMinute)
    }
    elseif (-not $savingEnough) {
        $level = 'Låg'
        $reason = ('Uppskattad besparing {0:N1} % är lägre än minimikravet {1:N1} %.' -f $estimatedSavingPercent,$minimumSavingPercent)
    }
    else {
        $level = 'Hög'
        $reason = ('{0}: {1:N1} MB/min överstiger tröskeln {2:N1} MB/min. Uppskattad besparing {3:N1} %.' -f $mediaType,$currentMBPerMinute,$thresholdMBPerMinute,$estimatedSavingPercent)
    }

    return [PSCustomObject]@{
        Level = $level
        Recommended = [bool]$recommended
        EstimatedSaving = ('{0:N1} %' -f $estimatedSavingPercent)
        EstimatedSavingPercent = [Math]::Round($estimatedSavingPercent,1)
        Reason = $reason
        MediaType = $mediaType
        MediaDetectionReason = [string]$classification.Reason
        CurrentMBPerMinute = [Math]::Round($currentMBPerMinute,2)
        TargetMBPerMinute = [Math]::Round($targetMBPerMinute,2)
        ThresholdMBPerMinute = [Math]::Round($thresholdMBPerMinute,2)
        TargetSizeMB = [int][Math]::Round($targetSizeMB,0)
    }
}

function Read-AnalysisCache {
    $cachePath = Join-Path $Script:DataFolder 'analysis-index.json'
    $entries = @(Read-JsonFile -Path $cachePath -DefaultValue @())
    $cache = @{}

    foreach ($entry in $entries) {
        if ($null -ne $entry -and -not [string]::IsNullOrWhiteSpace([string]$entry.FullPath)) {
            $cache[[string]$entry.FullPath] = $entry
        }
    }

    return $cache
}

function Invoke-FFprobeAnalysis {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File
    )

    $arguments = @(
        '-v', 'error',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        $File.FullName
    )

    $probeOutput = (& $Script:FFprobePath $arguments 2>$null | Out-String)
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($probeOutput)) {
        throw "ffprobe misslyckades med exitkod $exitCode."
    }

    $probe = $probeOutput | ConvertFrom-Json
    $videoStream = @($probe.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1)
    $audioStreams = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' })
    $subtitleStreams = @($probe.streams | Where-Object { $_.codec_type -eq 'subtitle' })

    if ($videoStream.Count -eq 0) {
        throw 'Ingen videoström hittades.'
    }

    $video = $videoStream[0]
    $formatBitrate = Convert-ToDoubleInvariant (Get-OptionalPropertyValue -Object $probe.format -Name 'bit_rate' -DefaultValue 0)
    $streamBitrate = Convert-ToDoubleInvariant (Get-OptionalPropertyValue -Object $video -Name 'bit_rate' -DefaultValue 0)

    $duration = Convert-ToDoubleInvariant (Get-OptionalPropertyValue -Object $probe.format -Name 'duration' -DefaultValue 0)
    if ($duration -le 0) {
        $duration = Convert-ToDoubleInvariant (Get-OptionalPropertyValue -Object $video -Name 'duration' -DefaultValue 0)
    }

    $bitrate = if ($streamBitrate -gt 0) {
        $streamBitrate
    }
    elseif ($formatBitrate -gt 0) {
        $formatBitrate
    }
    elseif ($duration -gt 0 -and $File.Length -gt 0) {
        # Beräkna ungefärlig total bitrate från filstorlek och speltid.
        ($File.Length * 8.0) / $duration
    }
    else {
        0
    }

    $codec = [string](Get-OptionalPropertyValue -Object $video -Name 'codec_name' -DefaultValue 'unknown')
    $width = [int](Get-OptionalPropertyValue -Object $video -Name 'width' -DefaultValue 0)
    $height = [int](Get-OptionalPropertyValue -Object $video -Name 'height' -DefaultValue 0)
    $fpsValue = Get-OptionalPropertyValue -Object $video -Name 'avg_frame_rate' -DefaultValue '0/0'
    if ([string]$fpsValue -eq '0/0') {
        $fpsValue = Get-OptionalPropertyValue -Object $video -Name 'r_frame_rate' -DefaultValue '0/0'
    }
    $fps = Get-FrameRate ([string]$fpsValue)
    $bitrateMbps = [Math]::Round(($bitrate / 1000000.0), 2)
    $script:CurrentFileSizeMB = [Math]::Round(($File.Length / 1MB), 2)
    $script:CurrentDurationMinutes = if ($duration -gt 0) { $duration / 60.0 } else { 0 }
    $recommendation = Get-VideoRecommendation -FileName $File.Name -Codec $codec -FileSizeMB $script:CurrentFileSizeMB -DurationMinutes $script:CurrentDurationMinutes

    $audioCodecs = @($audioStreams | ForEach-Object { [string]$_.codec_name } | Where-Object { $_ } | Select-Object -Unique)
    $sizeGB = [Math]::Round(($File.Length / 1GB), 3)

    return [PSCustomObject][ordered]@{
        FullPath = $File.FullName
        RelativePath = Get-RelativePath -BasePath $Script:OutputFolder -FullPath $File.FullName
        FileName = $File.Name
        FileSizeBytes = [int64]$File.Length
        FileSizeGB = $sizeGB
        FileSizeMB = $script:CurrentFileSizeMB
        LastWriteTimeUtc = $File.LastWriteTimeUtc.ToString('o')
        Codec = $codec
        Profile = [string](Get-OptionalPropertyValue -Object $video -Name 'profile' -DefaultValue '')
        PixelFormat = [string](Get-OptionalPropertyValue -Object $video -Name 'pix_fmt' -DefaultValue '')
        Width = $width
        Height = $height
        Resolution = ('{0}x{1}' -f $width, $height)
        FPS = $fps
        BitrateMbps = $bitrateMbps
        DurationSeconds = [Math]::Round($duration, 2)
        Duration = ([TimeSpan]::FromSeconds([Math]::Max(0, $duration))).ToString('hh\:mm\:ss')
        AudioCodecs = ($audioCodecs -join ', ')
        AudioTracks = $audioStreams.Count
        SubtitleTracks = $subtitleStreams.Count
        Recommended = [bool]$recommendation.Recommended
        RecommendationLevel = [string]$recommendation.Level
        EstimatedSaving = [string]$recommendation.EstimatedSaving
        RecommendationReason = [string]$recommendation.Reason
        MediaType = [string]$recommendation.MediaType
        MediaDetectionReason = [string]$recommendation.MediaDetectionReason
        CurrentMBPerMinute = [double]$recommendation.CurrentMBPerMinute
        TargetMBPerMinute = [double]$recommendation.TargetMBPerMinute
        ThresholdMBPerMinute = [double]$recommendation.ThresholdMBPerMinute
        EstimatedSavingPercent = [double]$recommendation.EstimatedSavingPercent
        TargetSizeMB = [int]$recommendation.TargetSizeMB
        AnalysisVersion = $Script:AppVersion
        AnalyzedUtc = (Get-Date).ToUniversalTime().ToString('o')
        AnalysisError = ''
    }
}

function Analyze-MkvLibrary {
    param(
        [AllowEmptyCollection()][string[]]$OnlyPaths = @()
    )
    Write-Host ''
    Write-Status INFO 'Analyserar färdiga MKV-filer med ffprobe...'

    if ($null -ne $OnlyPaths -and @($OnlyPaths).Count -gt 0) {
        $wanted = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($onlyPath in @($OnlyPaths)) {
            if ([string]::IsNullOrWhiteSpace([string]$onlyPath)) { continue }
            try { [void]$wanted.Add([System.IO.Path]::GetFullPath([string]$onlyPath)) } catch {}
        }
        $mkvList = New-Object System.Collections.Generic.List[System.IO.FileInfo]
        foreach ($wantedPath in $wanted) {
            if (Test-Path -LiteralPath $wantedPath -PathType Leaf) {
                $fi = Get-Item -LiteralPath $wantedPath -ErrorAction SilentlyContinue
                if ($null -ne $fi -and $fi.Extension -ieq '.mkv') { $mkvList.Add($fi) }
            }
        }
        $mkvFiles = @($mkvList.ToArray() | Sort-Object FullName)
        Write-Status INFO ("Köisolering aktiv: analyserar endast {0} MKV-fil(er) från aktuell UNC-kö." -f $mkvFiles.Count)
    }
    else {
        $mkvFiles = @(Get-ChildItem -LiteralPath $Script:OutputFolder -Filter '*.mkv' -File -Recurse -ErrorAction Stop |
            Sort-Object FullName)
    }

    $cache = Read-AnalysisCache
    $results = New-Object System.Collections.Generic.List[object]
    $total = $mkvFiles.Count
    $started = Get-Date
    $cachedCount = 0

    for ($i = 0; $i -lt $total; $i++) {
        $file = $mkvFiles[$i]
        $percent = if ($total -gt 0) { [int](($i + 1) * 100 / $total) } else { 100 }
        $relative = Get-RelativePath -BasePath $Script:OutputFolder -FullPath $file.FullName
        $elapsed = (Get-Date) - $started
        $etaText = 'Beräknar...'

        if ($i -ge 1) {
            $secondsPerItem = $elapsed.TotalSeconds / ($i + 1)
            $remainingSeconds = [Math]::Max(0, $secondsPerItem * ($total - ($i + 1)))
            $etaText = ([TimeSpan]::FromSeconds($remainingSeconds)).ToString('hh\:mm\:ss')
        }

        Write-Progress -Activity 'MediaPrep analyserar MKV-filer' -Status ("{0} av {1}: {2} | ETA {3}" -f ($i + 1), $total, $relative, $etaText) -PercentComplete $percent

        $cacheKey = $file.FullName
        $cached = $null
        if ($cache.ContainsKey($cacheKey)) {
            $candidate = $cache[$cacheKey]
            $candidateError = [string](Get-OptionalPropertyValue -Object $candidate -Name 'AnalysisError' -DefaultValue '')
            if (
                -not $Reanalyze -and
                [string]::IsNullOrWhiteSpace($candidateError) -and
                [string](Get-OptionalPropertyValue -Object $candidate -Name 'AnalysisVersion' -DefaultValue '') -eq $Script:AppVersion -and
                [int64]$candidate.FileSizeBytes -eq [int64]$file.Length -and
                [string]$candidate.LastWriteTimeUtc -eq $file.LastWriteTimeUtc.ToString('o')
            ) {
                $cached = $candidate
            }
        }

        if ($null -ne $cached) {
            $results.Add($cached)
            $cachedCount++
            continue
        }

        try {
            Write-Status INFO ("Analyserar: {0}" -f $relative)
            $results.Add((Invoke-FFprobeAnalysis -File $file))
        }
        catch {
            Write-Status ERROR ("Analys misslyckades: {0} - {1}" -f $relative, $_.Exception.Message)
            $results.Add([PSCustomObject][ordered]@{
                FullPath = $file.FullName
                RelativePath = $relative
                FileName = $file.Name
                FileSizeBytes = [int64]$file.Length
                FileSizeGB = [Math]::Round(($file.Length / 1GB), 3)
                FileSizeMB = [Math]::Round(($file.Length / 1MB), 2)
                LastWriteTimeUtc = $file.LastWriteTimeUtc.ToString('o')
                Codec = ''
                Profile = ''
                PixelFormat = ''
                Width = 0
                Height = 0
                Resolution = ''
                FPS = 0
                BitrateMbps = 0
                DurationSeconds = 0
                Duration = ''
                AudioCodecs = ''
                AudioTracks = 0
                SubtitleTracks = 0
                Recommended = $false
                RecommendationLevel = 'Fel'
                EstimatedSaving = ''
                RecommendationReason = ''
                MediaType = ''
                MediaDetectionReason = ''
                CurrentMBPerMinute = 0
                TargetMBPerMinute = 0
                ThresholdMBPerMinute = 0
                EstimatedSavingPercent = 0
                TargetSizeMB = 0
                AnalysisVersion = $Script:AppVersion
                AnalyzedUtc = (Get-Date).ToUniversalTime().ToString('o')
                AnalysisError = $_.Exception.Message
            })
        }
    }

    Write-Progress -Activity 'MediaPrep analyserar MKV-filer' -Completed
    Write-Status OK ("Analys klar. Återanvända cacheposter: {0}" -f $cachedCount)
    return $results.ToArray()
}

function Save-AnalysisReports {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    $Results = @($Results)
    $cachePath = Join-Path $Script:DataFolder 'analysis-index.json'
    Save-JsonFile -Path $cachePath -Value $Results
    Write-Status OK ("Analyscache sparad: {0}" -f $cachePath)

    $allCsv = Join-Path $Script:ReportFolder 'MediaPrep-analys-alla.csv'
    $recommendedCsv = Join-Path $Script:ReportFolder 'Rekommenderad-omkodning.csv'
    $recommendedTxt = Join-Path $Script:ReportFolder 'Rekommenderad-omkodning.txt'

    $columns = @(
        'RelativePath','Codec','Profile','Resolution','FPS','BitrateMbps',
        'FileSizeGB','FileSizeMB','Duration','AudioCodecs','AudioTracks','SubtitleTracks',
        'MediaType','MediaDetectionReason','CurrentMBPerMinute','TargetMBPerMinute','ThresholdMBPerMinute','EstimatedSavingPercent','TargetSizeMB','Recommended','RecommendationLevel','EstimatedSaving',
        'RecommendationReason','AnalysisError'
    )

    if ($Results.Count -gt 0) {
        $Results | Select-Object $columns |
            Export-Csv -LiteralPath $allCsv -NoTypeInformation -Encoding UTF8 -Delimiter ';'

        @($Results | Where-Object { $_.Recommended -or $_.AnalysisError } |
            Select-Object $columns) |
            Export-Csv -LiteralPath $recommendedCsv -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }
    else {
        $header = '"' + ($columns -join '";"') + '"'
        [System.IO.File]::WriteAllText($allCsv, $header + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($true)))
        [System.IO.File]::WriteAllText($recommendedCsv, $header + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($true)))
    }

    $recommended = @($Results | Where-Object { $_.Recommended })
    $errors = @($Results | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.AnalysisError) })

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('================================================================')
    $lines.Add(' MediaPrep - Rekommenderad omkodning')
    $lines.Add((' Skapad: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    $lines.Add('================================================================')
    $lines.Add(('Analyserade MKV-filer: {0}' -f $Results.Count))
    $lines.Add(('Rekommenderade:        {0}' -f $recommended.Count))
    $lines.Add(('Analysfel:              {0}' -f $errors.Count))
    $lines.Add('')

    foreach ($item in $recommended | Sort-Object RecommendationLevel, RelativePath) {
        $lines.Add(('Fil: {0}' -f $item.RelativePath))
        $lines.Add(('Codec: {0} | Upplösning: {1} | Bitrate: {2} Mbps' -f $item.Codec, $item.Resolution, $item.BitrateMbps))
        $lines.Add(('Storlek: {0} GB | Längd: {1}' -f $item.FileSizeGB, $item.Duration))
        $lines.Add(('Rekommendation: {0} | Uppskattad besparing: {1}' -f $item.RecommendationLevel, $item.EstimatedSaving))
        $lines.Add(('Orsak: {0}' -f $item.RecommendationReason))
        $lines.Add('----------------------------------------------------------------')
    }

    if ($recommended.Count -eq 0) {
        $lines.Add('Ingen fil rekommenderas för omkodning enligt nuvarande regler.')
    }

    if ($errors.Count -gt 0) {
        $lines.Add('')
        $lines.Add('Analysfel:')
        foreach ($item in $errors) {
            $lines.Add(('- {0}: {1}' -f $item.RelativePath, $item.AnalysisError))
        }
    }

    [System.IO.File]::WriteAllLines($recommendedTxt, $lines.ToArray(), (New-Object System.Text.UTF8Encoding($true)))

    Write-Status OK ("Analysrapport sparad: {0}" -f $allCsv)
    Write-Status OK ("Rekommendationsrapport sparad: {0}" -f $recommendedCsv)
    Write-Status OK ("Text rapport sparad: {0}" -f $recommendedTxt)
}

function Show-AnalysisSummary {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    $Results = @($Results)
    $recommended = @($Results | Where-Object { $_.Recommended }).Count
    $errors = @($Results | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.AnalysisError) }).Count
    $mpeg2 = @($Results | Where-Object { $_.Codec -eq 'mpeg2video' }).Count
    $h264 = @($Results | Where-Object { $_.Codec -eq 'h264' }).Count
    $hevc = @($Results | Where-Object { $_.Codec -eq 'hevc' }).Count

    Write-Host ''
    Write-ColorLine ('=' * 64) DarkCyan
    Write-ColorLine ' Analysresultat' Cyan
    Write-ColorLine ('=' * 64) DarkCyan
    Write-Host (' MKV-filer analyserade.......: {0}' -f $Results.Count)
    Write-Host (' MPEG-2......................: {0}' -f $mpeg2)
    Write-Host (' H.264........................: {0}' -f $h264)
    Write-Host (' HEVC........................: {0}' -f $hevc)
    Write-ColorLine (' Rekommenderad omkodning.....: {0}' -f $recommended) Yellow
    Write-ColorLine (' Analysfel....................: {0}' -f $errors) $(if ($errors -gt 0) { 'Red' } else { 'Green' })
    Write-ColorLine ('=' * 64) DarkCyan
}
#endregion


#region HEVC-omkodning (CPU / NVENC / QSV / AMF)
function Get-CurrentEncoderSignatureWorker {
    try {
        $ffmpegVersion=[string](& $Script:FFmpegPath -version 2>&1 | Select-Object -First 1)
        $cpu=Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $cpuName=if($cpu){[string]$cpu.Name}else{'CPU unknown'}
        $parts=New-Object System.Collections.Generic.List[string]
        $gpus=@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Sort-Object Name,PNPDeviceID)
        foreach($gpu in $gpus){$parts.Add(('{0}|{1}|{2}' -f [string]$gpu.Name,[string]$gpu.DriverVersion,[string]$gpu.PNPDeviceID))}
        return ('FFMPEG={0};CPU={1};GPU={2}' -f $ffmpegVersion,$cpuName,($parts -join ';'))
    } catch { return '' }
}
function Get-SelectedEncoderProfile {
    if(-not(Test-Path -LiteralPath $Script:EncoderCapabilitiesPath -PathType Leaf)){
        throw 'CPU/GPU-kontrollen saknas. Kör kontrollen från Start Center innan omkodning.'
    }
    $doc=Read-JsonFile -Path $Script:EncoderCapabilitiesPath -DefaultValue $null
    if($null-eq$doc){throw 'encoder-capabilities.json kunde inte läsas.'}
    $savedSignature=[string](Get-OptionalPropertyValue -Object $doc -Name 'Signature' -DefaultValue '')
    $currentSignature=Get-CurrentEncoderSignatureWorker
    if([string]::IsNullOrWhiteSpace($savedSignature) -or [string]::IsNullOrWhiteSpace($currentSignature) -or -not [string]::Equals($savedSignature,$currentSignature,[StringComparison]::Ordinal)){
        throw 'CPU/GPU-kontrollen är inaktuell. FFmpeg, GPU eller grafikdrivrutin har ändrats. Kör kontrollen på nytt.'
    }
    $selected=$null
    foreach($enc in @(Get-OptionalPropertyValue -Object $doc -Name 'Encoders' -DefaultValue @())){
        if([string]$enc.Id -eq [string]$Script:EncoderId){$selected=$enc;break}
    }
    if($null-eq$selected){throw ("Vald encoder finns inte i verifieringsfilen: {0}" -f $Script:EncoderId)}
    if(-not [bool](Get-OptionalPropertyValue -Object $selected -Name 'Verified' -DefaultValue $false)){
        throw ("Vald encoder är inte verifierad: {0}" -f [string]$selected.HardwareName)
    }
    $backend=[string]$selected.Backend
    $encoder=[string]$selected.Encoder
    $label=switch($backend){'NVENC'{'NVIDIA HEVC NVENC'};'QSV'{'Intel HEVC QSV'};'AMF'{'AMD HEVC AMF'};default{'CPU HEVC'}}
    return [pscustomobject]@{
        Id=[string]$selected.Id
        HardwareName=[string]$selected.HardwareName
        Backend=$backend
        Encoder=$encoder
        Label=$label
        GpuIndex=Get-OptionalPropertyValue -Object $selected -Name 'GpuIndex' -DefaultValue $null
        Capabilities=Get-OptionalPropertyValue -Object $selected -Name 'Capabilities' -DefaultValue $null
        Benchmark=Get-OptionalPropertyValue -Object $selected -Name 'Benchmark' -DefaultValue $null
    }
}
function Test-SelectedHevcEncoderAvailable {
    try{
        $profile=Get-SelectedEncoderProfile
        $encoderOutput=(& $Script:FFmpegPath -hide_banner -encoders 2>$null | Out-String)
        return ($encoderOutput -match ('\b'+[regex]::Escape([string]$profile.Encoder)+'\b'))
    }catch{
        Write-Status ERROR $_.Exception.Message
        return $false
    }
}
function Add-SelectedEncoderArguments {
    param(
        [Parameter(Mandatory=$true)][System.Collections.Generic.List[string]]$Arguments,
        [Parameter(Mandatory=$true)][object]$Profile,
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][int]$TargetVideoKbps,
        [Parameter(Mandatory=$true)][int]$MaxRateKbps,
        [Parameter(Mandatory=$true)][int]$BufferKbps,
        [Parameter(Mandatory=$true)][int]$QualityCQ
    )
    if([string]$Profile.Backend -eq 'NVENC'){
        $Arguments.Add('-hwaccel');$Arguments.Add('cuda')
        $gpuIndex=Get-OptionalPropertyValue -Object $Profile -Name 'GpuIndex' -DefaultValue $null
        if($null-ne$gpuIndex -and [int]$gpuIndex -gt 0){$Arguments.Add('-hwaccel_device');$Arguments.Add([string][int]$gpuIndex)}
    }
    $Arguments.Add('-i');$Arguments.Add($Source)
    foreach($arg in @('-map','0','-map_metadata','0','-map_chapters','0')){$Arguments.Add([string]$arg)}
    switch([string]$Profile.Backend){
        'NVENC' {
            foreach($arg in @('-c:v','hevc_nvenc')){$Arguments.Add([string]$arg)}
            $gpuIndex=Get-OptionalPropertyValue -Object $Profile -Name 'GpuIndex' -DefaultValue $null
            if($null-ne$gpuIndex){$Arguments.Add('-gpu');$Arguments.Add([string][int]$gpuIndex)}
            foreach($arg in @('-preset',[string]$Script:Config.NvencPreset,'-rc','vbr','-cq',[string]$QualityCQ,'-b:v',("{0}k" -f $TargetVideoKbps),'-maxrate',("{0}k" -f $MaxRateKbps),'-bufsize',("{0}k" -f $BufferKbps))){$Arguments.Add([string]$arg)}
        }
        'QSV' {
            foreach($arg in @('-c:v','hevc_qsv','-preset','medium','-b:v',("{0}k" -f $TargetVideoKbps),'-maxrate',("{0}k" -f $MaxRateKbps),'-bufsize',("{0}k" -f $BufferKbps))){$Arguments.Add([string]$arg)}
        }
        'AMF' {
            foreach($arg in @('-c:v','hevc_amf','-usage','transcoding','-quality','balanced','-rc','vbr_peak','-b:v',("{0}k" -f $TargetVideoKbps),'-maxrate',("{0}k" -f $MaxRateKbps),'-bufsize',("{0}k" -f $BufferKbps))){$Arguments.Add([string]$arg)}
        }
        default {
            foreach($arg in @('-c:v','libx265','-preset','medium','-b:v',("{0}k" -f $TargetVideoKbps),'-maxrate',("{0}k" -f $MaxRateKbps),'-bufsize',("{0}k" -f $BufferKbps))){$Arguments.Add([string]$arg)}
        }
    }
}

function Get-TargetVideoBitrateKbps {
    param([Parameter(Mandatory=$true)][object]$Item)
    if ([double]$Item.DurationSeconds -le 0) { throw 'Speltiden saknas.' }

    # TargetSizeMB is the desired total container size, including copied audio.
    # NVENC constrained-quality mode can overshoot its nominal average bitrate,
    # so reserve a configurable safety margin before calculating video bitrate.
    $safetyFactor = [double](Get-OptionalPropertyValue -Object $Script:Config -Name 'EncodingTargetSafetyFactor' -DefaultValue 0.90)
    if ($safetyFactor -le 0 -or $safetyFactor -gt 1) { $safetyFactor = 0.90 }

    $audioReserve = [Math]::Max(1,[int]$Item.AudioTracks) * [double]$Script:Config.AudioReserveKbpsPerTrack
    $safeTargetSizeMB = [double]$Item.TargetSizeMB * $safetyFactor
    $totalKbps = ($safeTargetSizeMB * 8192.0) / [double]$Item.DurationSeconds
    return [int][Math]::Max([int]$Script:Config.MinimumVideoBitrateKbps,[Math]::Floor($totalKbps-$audioReserve))
}

function Test-EncodedFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -lt [int64]$Script:Config.MinimumOutputSizeBytes) { return $false }
    $codec = (& $Script:FFprobePath -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $Path 2>$null | Select-Object -First 1)
    return (([string]$codec).Trim() -eq 'hevc')
}

function Format-MediaTime {
    param([double]$Seconds)
    if ($Seconds -lt 0 -or [double]::IsNaN($Seconds) -or [double]::IsInfinity($Seconds)) { $Seconds=0 }
    $span=[TimeSpan]::FromSeconds([Math]::Floor($Seconds))
    if ($span.TotalHours -ge 1) { return $span.ToString('hh\:mm\:ss') }
    return $span.ToString('mm\:ss')
}

function ConvertTo-NativeArgument {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"','$1$1\\"' -replace '(\\+)$','$1$1') + '"'
}

function Get-FfmpegProgressSnapshot {
    param(
        [Parameter(Mandatory=$true)][string]$ProgressPath,
        [Parameter(Mandatory=$true)][double]$DurationSeconds
    )
    if (-not (Test-Path -LiteralPath $ProgressPath -PathType Leaf)) { return $null }
    try { $lines=@([IO.File]::ReadAllLines($ProgressPath)) } catch { return $null }
    if ($lines.Count -eq 0) { return $null }
    $values=@{}
    foreach($line in $lines) {
        $index=$line.IndexOf('=')
        if ($index -gt 0) { $values[$line.Substring(0,$index)]=$line.Substring($index+1) }
    }
    $processed=0.0
    if ($values.ContainsKey('out_time_us')) {
        [void][double]::TryParse([string]$values['out_time_us'],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$processed)
        $processed=$processed/1000000.0
    }
    elseif ($values.ContainsKey('out_time_ms')) {
        [void][double]::TryParse([string]$values['out_time_ms'],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$processed)
        $processed=$processed/1000000.0
    }
    elseif ($values.ContainsKey('out_time')) {
        $span=[TimeSpan]::Zero
        if ([TimeSpan]::TryParse([string]$values['out_time'],[Globalization.CultureInfo]::InvariantCulture,[ref]$span)) { $processed=$span.TotalSeconds }
    }
    $speed=0.0
    $speedText=if($values.ContainsKey('speed')){([string]$values['speed']).Trim().TrimEnd('x')}else{''}
    [void][double]::TryParse($speedText,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$speed)
    $percent=if($DurationSeconds -gt 0){[Math]::Min(100,[Math]::Max(0,($processed/$DurationSeconds)*100))}else{0}
    $eta=if($speed -gt 0 -and $DurationSeconds -gt $processed){($DurationSeconds-$processed)/$speed}else{0}
    return [PSCustomObject]@{ProcessedSeconds=$processed;Percent=$percent;Speed=$speed;EtaSeconds=$eta}
}

function Invoke-FfmpegWithProgress {
    param(
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][double]$DurationSeconds,
        [string]$RelativePath='',
        [int]$QueueIndex=1,
        [int]$QueueTotal=1,
        [string]$ActivityLabel='MediaPrep omkodar HEVC',
        [string]$EncoderBackend=''
    )

    $process=$null
    try {
        # Start-Process -RedirectStandardOutput kan buffra progressutdata i
        # Windows PowerShell 5.1. Diagnostics.Process låter oss läsa varje
        # key=value-rad direkt medan FFmpeg fortfarande arbetar.
        $fullArgs=@('-hide_banner','-loglevel','error','-nostats','-stats_period','1','-progress','pipe:1')+$Arguments
        $argumentLine=($fullArgs | ForEach-Object { ConvertTo-NativeArgument ([string]$_) }) -join ' '

        $startInfo=New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName=$Script:FFmpegPath
        $startInfo.Arguments=$argumentLine
        $startInfo.UseShellExecute=$false
        $startInfo.CreateNoWindow=$true
        $startInfo.RedirectStandardOutput=$true
        $startInfo.RedirectStandardError=$true
        $startInfo.StandardOutputEncoding=[Text.Encoding]::UTF8
        $startInfo.StandardErrorEncoding=[Text.Encoding]::UTF8

        $process=New-Object System.Diagnostics.Process
        $process.StartInfo=$startInfo
        if($Script:VerboseLogging){Write-VerboseDiagnostic ('FFmpeg actual command: {0}' -f (Join-CommandLineForDiagnostic -Exe $Script:FFmpegPath -Arguments $fullArgs))}
        if(-not $process.Start()){ throw 'FFmpeg-processen kunde inte startas.' }
        if($Script:VerboseLogging){
            Write-VerboseDiagnostic ('FFmpeg PID={0}; PriorityClass={1}; Duration={2:N2}s; Queue={3}/{4}' -f $process.Id,$process.PriorityClass,$DurationSeconds,$QueueIndex,$QueueTotal)
        }

        $values=@{}
        $lastReport=[DateTime]::UtcNow.AddSeconds(-5)
        $lastUiUpdate=[DateTime]::UtcNow.AddSeconds(-1)
        $lastProcessed=-1.0
        $finalSnapshot=$null
        $lastVerboseSnapshot=[DateTime]::UtcNow.AddSeconds(-30)
        $lastAdvanceUtc=[DateTime]::UtcNow
        $lastAdvanceProcessed=-1.0
        $lastDiagCpu=$process.TotalProcessorTime.TotalSeconds
        $lastDiagUtc=[DateTime]::UtcNow
        $stallWarned=$false
        $stallAborted=$false

        while(-not $process.StandardOutput.EndOfStream){
            $line=$process.StandardOutput.ReadLine()
            if($null -eq $line){ continue }
            $separator=$line.IndexOf('=')
            if($separator -le 0){ continue }

            $key=$line.Substring(0,$separator)
            $value=$line.Substring($separator+1)
            $values[$key]=$value

            # Ett progressblock är komplett först när FFmpeg skriver progress=.
            if($key -ne 'progress'){ continue }

            $processed=0.0
            if($values.ContainsKey('out_time_us')){
                [void][double]::TryParse([string]$values['out_time_us'],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$processed)
                $processed=$processed/1000000.0
            }
            elseif($values.ContainsKey('out_time_ms')){
                [void][double]::TryParse([string]$values['out_time_ms'],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$processed)
                $processed=$processed/1000000.0
            }
            elseif($values.ContainsKey('out_time')){
                $span=[TimeSpan]::Zero
                if([TimeSpan]::TryParse([string]$values['out_time'],[Globalization.CultureInfo]::InvariantCulture,[ref]$span)){$processed=$span.TotalSeconds}
            }

            $speed=0.0
            $speedTextRaw=if($values.ContainsKey('speed')){([string]$values['speed']).Trim().TrimEnd('x')}else{''}
            [void][double]::TryParse($speedTextRaw,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$speed)
            $percent=if($DurationSeconds -gt 0){[Math]::Min(100,[Math]::Max(0,($processed/$DurationSeconds)*100))}else{0}
            $eta=if($speed -gt 0 -and $DurationSeconds -gt $processed){($DurationSeconds-$processed)/$speed}else{0}
            $snapshot=[PSCustomObject]@{ProcessedSeconds=$processed;Percent=$percent;Speed=$speed;EtaSeconds=$eta}
            $finalSnapshot=$snapshot

            $now=[DateTime]::UtcNow
            if($processed -gt ($lastAdvanceProcessed+0.05)){
                $lastAdvanceProcessed=$processed
                $lastAdvanceUtc=$now
                $stallWarned=$false
            }
            if(($now-$lastUiUpdate).TotalMilliseconds -ge 750 -or $value -eq 'end'){
                $displaySpeed=if($speed -gt 0){('{0:N2}x' -f $speed)}else{'väntar'}
                $etaText=if($speed -gt 0){Format-MediaTime $eta}else{'beräknas'}
                $progressText=("{0} av {1}: {2}`n{3} / {4} | {5:N1} % | hastighet {6} | kvar cirka {7}" -f $QueueIndex,$QueueTotal,$RelativePath,(Format-MediaTime $processed),(Format-MediaTime $DurationSeconds),$percent,$displaySpeed,$etaText)
                Write-Progress -Id 3 -Activity $ActivityLabel -Status $progressText -PercentComplete ([int][Math]::Round($percent))
                $lastUiUpdate=$now
            }

            if(($now-$lastReport).TotalSeconds -ge 5 -and $processed -ne $lastProcessed){
                $displaySpeed=if($speed -gt 0){('{0:N2}x' -f $speed)}else{'väntar'}
                $etaText=if($speed -gt 0){Format-MediaTime $eta}else{'beräknas'}
                Write-ProgressLogOnly ("{0} | {1} / {2} | {3:N1} % | hastighet {4} | kvar cirka {5}" -f $RelativePath,(Format-MediaTime $processed),(Format-MediaTime $DurationSeconds),$percent,$displaySpeed,$etaText)
                $lastReport=$now
                $lastProcessed=$processed
            }
            if($Script:VerboseLogging -and ($now-$lastVerboseSnapshot).TotalSeconds -ge 30){
                $cpuNow=$process.TotalProcessorTime.TotalSeconds
                $wallDelta=[Math]::Max(0.001,($now-$lastDiagUtc).TotalSeconds)
                $cpuDelta=[Math]::Max(0,$cpuNow-$lastDiagCpu)
                $cpuEquivalent=($cpuDelta/$wallDelta)*100.0
                $stallSeconds=[Math]::Max(0,($now-$lastAdvanceUtc).TotalSeconds)
                Write-VerboseDiagnostic ('FFmpeg live: PID={0}; fil={1}; media={2}/{3}; percent={4:N1}; speed={5:N2}x; ETA={6}; CPUdelta={7:N2}s/{8:N1}s ({9:N1}% av en kärna); WorkingSet={10:N1} MB; Threads={11}; progress-still={12:N1}s' -f $process.Id,$RelativePath,(Format-MediaTime $processed),(Format-MediaTime $DurationSeconds),$percent,$speed,(Format-MediaTime $eta),$cpuDelta,$wallDelta,$cpuEquivalent,($process.WorkingSet64/1MB),$process.Threads.Count,$stallSeconds)
                if($EncoderBackend -eq 'NVENC'){ Get-NvidiaDiagnosticSnapshot }
                if($stallSeconds -ge 20 -and -not $stallWarned){
                    $backendHint=if($EncoderBackend -eq 'NVENC'){' Om CPUdelta också är 0 och NVENC=0/P8 väntar FFmpeg sannolikt i input/demux/decode/driver-pipelinen.'}else{''}
                    Write-VerboseDiagnostic ('STALL WARNING: FFmpeg media progress har inte flyttats på {0:N1}s.{1}' -f $stallSeconds,$backendHint)
                    $stallWarned=$true
                }
                $lastDiagCpu=$cpuNow
                $lastDiagUtc=$now
                $lastVerboseSnapshot=$now
            }
            $hardStallSeconds=[Math]::Max(0,($now-$lastAdvanceUtc).TotalSeconds)
            if($hardStallSeconds -ge 60 -and -not $process.HasExited){
                Write-Status ERROR ("FFmpeg har stått still i {0:N0} sekunder vid {1}. Avbryter filen så kön kan fortsätta." -f $hardStallSeconds,(Format-MediaTime $processed))
                if($Script:VerboseLogging){Write-VerboseDiagnostic ('STALL ABORT: PID={0}; fil={1}; media={2}; still={3:N1}s' -f $process.Id,$RelativePath,(Format-MediaTime $processed),$hardStallSeconds)}
                $stallAborted=$true
                try{$process.Kill()}catch{}
                break
            }

            $values=@{}
        }

        # StandardError läses efter stdout. Med -loglevel error är mängden liten,
        # vilket undviker blockering men behåller användbara felmeddelanden.
        $errors=$process.StandardError.ReadToEnd()
        $process.WaitForExit()

        if($null -ne $finalSnapshot -and $process.ExitCode -eq 0){
            $finalSpeed=if($finalSnapshot.Speed -gt 0){('{0:N2}x' -f $finalSnapshot.Speed)}else{'okänd'}
            Write-Progress -Id 3 -Activity $ActivityLabel -Status ("{0} av {1}: {2}`n{3} / {4} | 100,0 % | hastighet {5} | klar" -f $QueueIndex,$QueueTotal,$RelativePath,(Format-MediaTime $DurationSeconds),(Format-MediaTime $DurationSeconds),$finalSpeed) -PercentComplete 100
        }

        $returnExitCode=if($stallAborted){408}else{[int]$process.ExitCode}
        $returnErrorText=if($stallAborted){'FFmpeg stall: ingen mediaprogress på 60 sekunder.'}else{[string]$errors}
        return [PSCustomObject]@{ExitCode=$returnExitCode;ErrorText=$returnErrorText;Stalled=$stallAborted}
    }
    finally {
        Write-Progress -Id 3 -Activity $ActivityLabel -Completed
        if($null -ne $process){$process.Dispose()}
    }
}


function Get-ErrorQueueRecords {
    if ([string]::IsNullOrWhiteSpace($Script:ErrorQueuePath) -or -not (Test-Path -LiteralPath $Script:ErrorQueuePath -PathType Leaf)) { return @() }
    try {
        $raw=Get-Content -LiteralPath $Script:ErrorQueuePath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        return @($raw | ConvertFrom-Json)
    } catch { Write-Status WARN ("Kunde inte läsa felkön: {0}" -f $_.Exception.Message); return @() }
}

function Save-ErrorQueueRecords {
    param([AllowEmptyCollection()][object[]]$Records)
    Save-JsonFile -Path $Script:ErrorQueuePath -Value @($Records)
    try {
        $dashboardPath=Join-Path $Script:DataFolder 'queue-dashboard-inventory.json'
        if(Test-Path -LiteralPath $dashboardPath -PathType Leaf){
            $doc=Get-Content -LiteralPath $dashboardPath -Raw -Encoding UTF8|ConvertFrom-Json
            if($doc.PSObject.Properties['items']){
                $doc.errors=[int]@($Records).Count
                $doc.updatedUtc=(Get-Date).ToUniversalTime().ToString('o')
                Save-JsonFile -Path $dashboardPath -Value $doc
            }
        }
    } catch {
        if($Script:VerboseLogging){Write-VerboseDiagnostic ('Kunde inte uppdatera errors i queue-dashboard-inventory.json: {0}' -f $_.Exception.Message)}
    }
}

function Add-ItemToErrorQueue {
    param([Parameter(Mandatory=$true)][object]$Item,[Parameter(Mandatory=$true)][string]$Reason)
    $original=[string]$Item.FullPath
    if (-not (Test-Path -LiteralPath $original -PathType Leaf)) { return $null }
    $relative=[string]$Item.RelativePath
    if ([string]::IsNullOrWhiteSpace($relative)) { $relative=[IO.Path]::GetFileName($original) }
    $errorPath=Join-Path $Script:ErrorFolder $relative
    $errorDir=Split-Path -Parent $errorPath
    Ensure-Directory $errorDir
    if (Test-Path -LiteralPath $errorPath -PathType Leaf) { Remove-Item -LiteralPath $errorPath -Force }
    Move-Item -LiteralPath $original -Destination $errorPath -Force
    Update-QueueDashboardItem -RelativePath $relative -QueueStage 90 -QueueStatus 'Error' -Values @{ErrorMessage=$Reason;ErrorKind='Encode';ErrorPreviousStage=6;ErrorLocalPath=$errorPath}
    $records=@(Get-ErrorQueueRecords | Where-Object { [string]$_.OriginalPath -ne $original })
    $records += [PSCustomObject]@{
        AddedUtc=(Get-Date).ToUniversalTime().ToString('o');RelativePath=$relative;OriginalPath=$original;ErrorPath=$errorPath;Reason=$Reason
        DurationSeconds=[double]$Item.DurationSeconds;TargetSizeMB=[int]$Item.TargetSizeMB;TargetVideoBitrateKbps=[int](Get-TargetVideoBitrateKbps -Item $Item)
    }
    Save-ErrorQueueRecords -Records $records
    Write-Status WARN ("Flyttad till felkö: {0}" -f $relative)
    return $errorPath
}

function Invoke-ErrorQueueProcessing {
    $records=@(Get-ErrorQueueRecords)
    if ($records.Count -eq 0) { Write-Status INFO 'Felkön är tom.'; return @() }
    Write-Status INFO ("Bearbetar felkön: {0} fil(er). Avkodningsfel ignoreras." -f $records.Count)
    $remaining=New-Object System.Collections.Generic.List[object]
    $results=New-Object System.Collections.Generic.List[object]
    for($i=0;$i -lt $records.Count;$i++){
        $r=$records[$i]
        $errorPath=[string]$r.ErrorPath
        if(-not(Test-Path -LiteralPath $errorPath -PathType Leaf)){Write-Status WARN ("Felkösfil saknas: {0}" -f $errorPath);continue}
        $item=[PSCustomObject]@{
            FullPath=$errorPath;RelativePath=[string]$r.RelativePath;DurationSeconds=[double]$r.DurationSeconds;TargetSizeMB=[int]$r.TargetSizeMB
        }
        Update-QueueDashboardItem -RelativePath ([string]$r.RelativePath) -QueueStage 91 -QueueStatus 'ProcessingErrorQueue' -Values @{ErrorMessage=[string]$r.Reason}
        $res=Invoke-HevcEncodeItem -Item $item -QueueIndex ($i+1) -QueueTotal $records.Count -ForceIgnoreDecodeErrors
        if($res.Success){
            $dest=[string]$r.OriginalPath
            Ensure-Directory (Split-Path -Parent $dest)
            if(Test-Path -LiteralPath $dest -PathType Leaf){Remove-Item -LiteralPath $dest -Force}
            Move-Item -LiteralPath $errorPath -Destination $dest -Force
            $fixedInfo=Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue
            $fixedBytes=if($null-ne$fixedInfo){[int64]$fixedInfo.Length}else{$null}
            Update-QueueDashboardItem -RelativePath ([string]$r.RelativePath) -QueueStage 7 -QueueStatus 'Encoded' -Values @{EncodedSize=$fixedBytes;FinalSize=$fixedBytes;EncodeCompleted=(Get-Date).ToUniversalTime().ToString('o');ErrorMessage=$null}
            Write-Status OK ("Felkön klar: {0} -> återställd till Processed." -f [string]$r.RelativePath)
            $results.Add($res)
        } else {
            $remaining.Add($r)
            Update-QueueDashboardItem -RelativePath ([string]$r.RelativePath) -QueueStage 92 -QueueStatus 'ErrorQueueFailed' -Values @{ErrorMessage=[string]$res.Message}
            Write-Status ERROR ("Felkön misslyckades igen: {0} - {1}" -f [string]$r.RelativePath,$res.Message)
        }
    }
    Save-ErrorQueueRecords -Records @($remaining.ToArray())
    return $results.ToArray()
}

function Invoke-HevcEncodeItem {
    param([Parameter(Mandatory=$true)][object]$Item,[int]$QueueIndex=1,[int]$QueueTotal=1,[switch]$ForceIgnoreDecodeErrors)
    $profile=Get-SelectedEncoderProfile
    $source=[string]$Item.FullPath
    $sourceInfo=Get-Item -LiteralPath $source -ErrorAction Stop
    $tempFile=Join-Path $Script:TempFolder (([IO.Path]::GetFileNameWithoutExtension($sourceInfo.Name))+'_'+[guid]::NewGuid().ToString('N')+'.mkv')
    $backupFile=$source+'.mediaprep-backup'
    $qualityCQ=[int](Get-OptionalPropertyValue -Object $Script:Config -Name 'NvencCQ' -DefaultValue 24)
    $targetVideoKbps=Get-TargetVideoBitrateKbps -Item $Item
    $maxRateMultiplier=[double](Get-OptionalPropertyValue -Object $Script:Config -Name 'NvencMaxRateMultiplier' -DefaultValue 1.10)
    if($maxRateMultiplier-lt1.0 -or $maxRateMultiplier-gt1.5){$maxRateMultiplier=1.10}
    $maxRateKbps=[int][Math]::Ceiling($targetVideoKbps*$maxRateMultiplier)
    $bufferKbps=[int][Math]::Ceiling($targetVideoKbps*1.5)
    $minimumSavingPercent=[double]$Script:Config.MinimumSavingPercent

    try{
        if([bool]$ForceIgnoreDecodeErrors){
            Update-QueueDashboardItem -RelativePath ([string]$Item.RelativePath) -QueueStage 91 -QueueStatus 'ProcessingErrorQueue' -Values @{EncodeStarted=(Get-Date).ToUniversalTime().ToString('o')}
        }else{
            Update-QueueDashboardItem -RelativePath ([string]$Item.RelativePath) -QueueStage 6 -QueueStatus 'Encoding' -Values @{EncodeStarted=(Get-Date).ToUniversalTime().ToString('o');ErrorMessage=$null}
        }
        Write-Status INFO ("{0}: {1} | målvideo cirka {2} kbps | totalmål {3} MB | säkerhetsmarginal {4:P0}" -f $profile.Label,$Item.RelativePath,$targetVideoKbps,$Item.TargetSizeMB,[double]$Script:Config.EncodingTargetSafetyFactor)
        $args=New-Object System.Collections.Generic.List[string]
        foreach($arg in @('-hide_banner','-loglevel','warning','-y')){$args.Add([string]$arg)}
        $useDecodeTolerance=$Script:IgnoreDecodeErrors -or [bool]$ForceIgnoreDecodeErrors
        if($useDecodeTolerance){
            foreach($arg in @('-fflags','+discardcorrupt+genpts','-err_detect','ignore_err')){$args.Add([string]$arg)}
            Write-Status WARN ("Ignorera avkodningsfel är aktivt för: {0}" -f $Item.RelativePath)
        }
        Add-SelectedEncoderArguments -Arguments $args -Profile $profile -Source $source -TargetVideoKbps $targetVideoKbps -MaxRateKbps $maxRateKbps -BufferKbps $bufferKbps -QualityCQ $qualityCQ
        foreach($arg in @('-c:a','copy','-c:s','copy','-c:d','copy',$tempFile)){$args.Add([string]$arg)}
        $argsArray=$args.ToArray()
        if($Script:VerboseLogging){
            Write-VerboseDiagnostic ('Encoder start: backend={0}; encoder={1}; hårdvara={2}; fil={3}; längd={4:N2}s; original={5:N1} MB; target={6} MB; video={7} kbps; maxrate={8} kbps; bufsize={9} kbps' -f $profile.Backend,$profile.Encoder,$profile.HardwareName,$Item.RelativePath,[double]$Item.DurationSeconds,($sourceInfo.Length/1MB),$Item.TargetSizeMB,$targetVideoKbps,$maxRateKbps,$bufferKbps)
            Get-FfmpegVersionDiagnostic
            if([string]$profile.Backend-eq'NVENC'){Get-NvidiaDiagnosticSnapshot}
            Write-VerboseDiagnostic ('FFmpeg command: {0}' -f (Join-CommandLineForDiagnostic -Exe $Script:FFmpegPath -Arguments $argsArray))
        }
        $encodeStarted=Get-Date
        $encodeRun=Invoke-FfmpegWithProgress -Arguments $argsArray -DurationSeconds ([double]$Item.DurationSeconds) -RelativePath ([string]$Item.RelativePath) -QueueIndex $QueueIndex -QueueTotal $QueueTotal -ActivityLabel ("MediaPrep omkodar med {0}" -f $profile.Label) -EncoderBackend ([string]$profile.Backend)
        if($Script:VerboseLogging){
            $encodeElapsed=(Get-Date)-$encodeStarted
            $averageSpeed=0.0;if($encodeElapsed.TotalSeconds-gt0){$averageSpeed=[double]$Item.DurationSeconds/$encodeElapsed.TotalSeconds}
            Write-VerboseDiagnostic ('Encoder slut: backend={0}; fil={1}; exitkod={2}; verklig tid={3}; genomsnittlig media/realtid cirka {4:N2}x' -f $profile.Backend,$Item.RelativePath,[int]$encodeRun.ExitCode,$encodeElapsed.ToString('hh\:mm\:ss'),$averageSpeed)
            if([string]$profile.Backend-eq'NVENC'){Get-NvidiaDiagnosticSnapshot}
        }
        $exitCode=[int]$encodeRun.ExitCode
        if($exitCode-ne0 -or -not(Test-EncodedFile -Path $tempFile)){
            $detail=([string]$encodeRun.ErrorText).Trim();if(-not[string]::IsNullOrWhiteSpace($detail)){Write-Status ERROR $detail}
            throw ("FFmpeg/{0} misslyckades. Exitkod: {1}" -f $profile.Backend,$exitCode)
        }

        $newInfo=Get-Item -LiteralPath $tempFile
        $savedBytes=$sourceInfo.Length-$newInfo.Length
        $actualSavingPercent=[Math]::Round(($savedBytes/[double]$sourceInfo.Length)*100,1)
        if($savedBytes-le0 -or $actualSavingPercent-lt$minimumSavingPercent){
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            $reason=if($savedBytes-le0){'Den kvalitetsstyrda HEVC-filen blev inte mindre än originalet.'}else{("Faktisk besparing {0} % understiger minimikravet {1} %." -f $actualSavingPercent,$minimumSavingPercent)}
            Update-QueueDashboardItem -RelativePath ([string]$Item.RelativePath) -QueueStage 7 -QueueStatus 'Encoded' -Values @{EncodedSize=$null;FinalSize=[int64]$sourceInfo.Length;EncodeCompleted=(Get-Date).ToUniversalTime().ToString('o')}
            return [PSCustomObject]@{RelativePath=$Item.RelativePath;Success=$true;Replaced=$false;OriginalSizeMB=[Math]::Round($sourceInfo.Length/1MB,1);NewSizeMB=[Math]::Round($newInfo.Length/1MB,1);SavedMB=[Math]::Round($savedBytes/1MB,1);SavedPercent=$actualSavingPercent;TargetSizeMB=[int]$Item.TargetSizeMB;TargetVideoBitrateKbps=$targetVideoKbps;QualityCQ=$qualityCQ;EncoderBackend=$profile.Backend;EncoderName=$profile.Encoder;Message=("Originalet behölls. {0}" -f $reason);CompletedUtc=(Get-Date).ToUniversalTime().ToString('o')}
        }

        if(Test-Path -LiteralPath $backupFile){Remove-Item -LiteralPath $backupFile -Force}
        Move-Item -LiteralPath $source -Destination $backupFile -Force
        try{Move-Item -LiteralPath $tempFile -Destination $source -Force;Remove-Item -LiteralPath $backupFile -Force}
        catch{if(Test-Path -LiteralPath $source){Remove-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue};Move-Item -LiteralPath $backupFile -Destination $source -Force;throw}
        $finalInfo=Get-Item -LiteralPath $source
        $saved=$sourceInfo.Length-$finalInfo.Length
        Update-QueueDashboardItem -RelativePath ([string]$Item.RelativePath) -QueueStage 7 -QueueStatus 'Encoded' -Values @{EncodedSize=[int64]$finalInfo.Length;FinalSize=[int64]$finalInfo.Length;EncodeCompleted=(Get-Date).ToUniversalTime().ToString('o');ErrorMessage=$null}
        return [PSCustomObject]@{RelativePath=$Item.RelativePath;Success=$true;Replaced=$true;OriginalSizeMB=[Math]::Round($sourceInfo.Length/1MB,1);NewSizeMB=[Math]::Round($finalInfo.Length/1MB,1);SavedMB=[Math]::Round($saved/1MB,1);SavedPercent=[Math]::Round(($saved/[double]$sourceInfo.Length)*100,1);TargetSizeMB=[int]$Item.TargetSizeMB;TargetVideoBitrateKbps=$targetVideoKbps;QualityCQ=$qualityCQ;EncoderBackend=$profile.Backend;EncoderName=$profile.Encoder;Message=("Omkodad till HEVC med {0}" -f $profile.Backend);CompletedUtc=(Get-Date).ToUniversalTime().ToString('o')}
    }catch{
        Update-QueueDashboardItem -RelativePath ([string]$Item.RelativePath) -QueueStage 90 -QueueStatus 'Error' -Values @{ErrorMessage=$_.Exception.Message}
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{RelativePath=$Item.RelativePath;Success=$false;Replaced=$false;OriginalSizeMB=[Math]::Round($sourceInfo.Length/1MB,1);NewSizeMB=0;SavedMB=0;SavedPercent=0;TargetSizeMB=[int]$Item.TargetSizeMB;TargetVideoBitrateKbps=$targetVideoKbps;QualityCQ=$qualityCQ;EncoderBackend=$profile.Backend;EncoderName=$profile.Encoder;Message=$_.Exception.Message;CompletedUtc=(Get-Date).ToUniversalTime().ToString('o')}
    }
}

function Invoke-RecommendedEncoding {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$AnalysisResults)
    if (-not (Test-SelectedHevcEncoderAvailable)) {
        throw 'Vald HEVC-encoder kunde inte startas. Kör CPU/GPU-kontrollen på nytt och välj en verifierad encoder.'
    }
    $profile=Get-SelectedEncoderProfile
    $queue=@($AnalysisResults | Where-Object { $_.Recommended -and $_.TargetSizeMB -gt 0 })
    $results=New-Object System.Collections.Generic.List[object]
    for ($i=0;$i -lt $queue.Count;$i++) {
        $item=$queue[$i]
        Write-Progress -Id 3 -Activity ("MediaPrep omkodar med {0}" -f $profile.Label) -Status ("{0} av {1}: {2}`nStartar FFmpeg och väntar på progressdata..." -f ($i+1),$queue.Count,$item.RelativePath) -PercentComplete 0
        $result=Invoke-HevcEncodeItem -Item $item -QueueIndex ($i+1) -QueueTotal $queue.Count
        $results.Add($result)
        if (-not $result.Success) {
            Write-Status ERROR ("Omkodning misslyckades: {0} - {1}" -f $result.RelativePath,$result.Message)
            try{[void](Add-ItemToErrorQueue -Item $item -Reason ([string]$result.Message))}catch{Write-Status ERROR ("Kunde inte lägga filen i felkön: {0}" -f $_.Exception.Message)}
        }
        elseif ($result.Replaced) {
            Write-Status OK ("Omkodad: {0} | {1} MB -> {2} MB | sparade {3} % | {4}" -f $result.RelativePath,$result.OriginalSizeMB,$result.NewSizeMB,$result.SavedPercent,$profile.Label)
        }
        else {
            Write-Status WARN ("Ingen användbar besparing: {0} - {1}" -f $result.RelativePath,$result.Message)
        }
    }
    Write-Progress -Id 3 -Activity ("MediaPrep omkodar med {0}" -f $profile.Label) -Completed
    $reportPath=Join-Path $Script:ReportFolder 'MediaPrep-omkodning.csv'
    $results.ToArray() | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Status OK ("Omkodningsrapport sparad: {0}" -f $reportPath)
    return $results.ToArray()
}
#endregion

#region Rapport och index
function Save-ScanResults {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Items
    )

    $itemsArray = @($Items)

    $indexPath = Join-Path $Script:DataFolder 'index.json'
    Save-JsonFile -Path $indexPath -Value $itemsArray
    Write-Status OK ("Index sparat: {0}" -f $indexPath)

    $csvPath = Join-Path $Script:ReportFolder 'MediaPrep-skanning.csv'
    if ($itemsArray.Count -gt 0) {
        $itemsArray |
            Select-Object RelativePath, VideoExtension, VideoSizeBytes, SubtitleType, OutputFile, NeedsProcessing, Reason, Status, LastScannedUtc |
            Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    }
    else {
        $header = '"RelativePath";"VideoExtension";"VideoSizeBytes";"SubtitleType";"OutputFile";"NeedsProcessing";"Reason";"Status";"LastScannedUtc"'
        [System.IO.File]::WriteAllText(
            $csvPath,
            $header + [Environment]::NewLine,
            (New-Object System.Text.UTF8Encoding($true))
        )
    }

    Write-Status OK ("Skanningsrapport sparad: {0}" -f $csvPath)
}

function Save-MuxResults {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    $Results = @($Results)
    $csvPath = Join-Path $Script:ReportFolder 'MediaPrep-muxning.csv'
    $Results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Status OK ("Muxningsrapport sparad: {0}" -f $csvPath)
}

function Show-MuxSummary {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    $Results = @($Results)
    $successCount = @($Results | Where-Object { $_.Success }).Count
    $failedCount = @($Results | Where-Object { -not $_.Success }).Count
    $deletedCount = ($Results | Measure-Object -Property DeletedCount -Sum).Sum
    if ($null -eq $deletedCount) { $deletedCount = 0 }

    Write-Host ''
    Write-ColorLine ('=' * 64) DarkCyan
    Write-ColorLine ' Muxningsresultat' Cyan
    Write-ColorLine ('=' * 64) DarkCyan
    Write-ColorLine (' MKV skapade...............: {0}' -f $successCount) Green
    Write-ColorLine (' Misslyckade................: {0}' -f $failedCount) $(if ($failedCount -gt 0) { 'Red' } else { 'Green' })
    Write-ColorLine (' Källfiler borttagna........: {0}' -f $deletedCount) Yellow
    Write-ColorLine ('=' * 64) DarkCyan
}

function Show-Summary {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Items
    )

    $Items = @($Items)
    $tsCount = @($Items | Where-Object { $_.VideoExtension -eq '.ts' }).Count
    $mp4Count = @($Items | Where-Object { $_.VideoExtension -eq '.mp4' }).Count
    $aviCount = @($Items | Where-Object { $_.VideoExtension -eq '.avi' }).Count
    $mpgCount = @($Items | Where-Object { $_.VideoExtension -eq '.mpg' }).Count
    $mpegCount = @($Items | Where-Object { $_.VideoExtension -eq '.mpeg' }).Count
    $srtCount = @($Items | Where-Object { $_.SubtitleType -eq 'SRT' }).Count
    $vttCount = @($Items | Where-Object { $_.SubtitleType -eq 'VTT' }).Count
    $noSubtitle = @($Items | Where-Object { $_.SubtitleType -eq 'Ingen' }).Count
    $pending = @($Items | Where-Object { $_.NeedsProcessing }).Count
    $current = @($Items | Where-Object { -not $_.NeedsProcessing }).Count

    Write-Host ''
    Write-ColorLine ('=' * 64) DarkCyan
    Write-ColorLine ' Skanningsresultat' Cyan
    Write-ColorLine ('=' * 64) DarkCyan
    Write-Host (' Videofiler totalt........: {0}' -f $Items.Count)
    Write-Host (' TS.......................: {0}' -f $tsCount)
    Write-Host (' MP4......................: {0}' -f $mp4Count)
    Write-Host (' AVI......................: {0}' -f $aviCount)
    Write-Host (' MPG......................: {0}' -f $mpgCount)
    Write-Host (' MPEG.....................: {0}' -f $mpegCount)
    Write-Host ''
    Write-Host (' Med SRT..................: {0}' -f $srtCount)
    Write-Host (' Med VTT..................: {0}' -f $vttCount)
    Write-Host (' Utan undertext............: {0}' -f $noSubtitle)
    Write-Host ''
    Write-ColorLine (' Behöver bearbetas.........: {0}' -f $pending) Yellow
    Write-ColorLine (' Redan aktuella............: {0}' -f $current) Green
    Write-ColorLine ('=' * 64) DarkCyan

    if ($pending -gt 0) {
        Write-Host ''
        Write-ColorLine ' Filer som behöver bearbetas:' Yellow
        foreach ($item in ($Items | Where-Object { $_.NeedsProcessing } | Select-Object -First 20)) {
            Write-Host ('  - {0} [{1}]' -f $item.RelativePath, $item.Reason)
        }
        if ($pending -gt 20) {
            Write-Host ('  ... och ytterligare {0} filer. Se CSV-rapporten.' -f ($pending - 20))
        }
    }

    Write-Host ''
    Write-Status INFO ('Version {0} muxar, analyserar, omkodar och återför UNC-resultat.' -f $Script:AppVersion)
}
#endregion

#region Huvudprogram
try {
    Show-Header
if($Script:VerboseLogging){Write-VerboseDiagnostic ('Verbose logging aktiv. PID={0}; PowerShell={1}; RunId={2}' -f $PID,$PSVersionTable.PSVersion,$Script:RunId)}
    Initialize-MediaPrep
    if ($RebuildIndex) {
        Save-JsonFile -Path (Join-Path $Script:DataFolder 'index.json') -Value @()
        Save-JsonFile -Path (Join-Path $Script:DataFolder 'analysis-index.json') -Value @()
        Write-Status WARN 'Tidigare index har återställts.'
    }
    $uncRecords=@()
    $currentQueueSourcePaths=@()
    $currentQueueOutputPaths=@()
    $queueIncludeListPath=''
    if ($ImportFromUnc) {
        if ($AnalyzeOnly -or $EncodeOnly) { throw 'UNC-import kan endast användas med Hela arbetsflödet.' }
        $uncRecords=@(Import-UncMediaFiles -SourcePath $UncSourcePath)

        $sourceList = New-Object System.Collections.Generic.List[string]
        $outputList = New-Object System.Collections.Generic.List[string]
        foreach ($queueRecord in @($uncRecords | Where-Object { $_.ImportSuccess })) {
            $lv=[string](Get-OptionalPropertyValue -Object $queueRecord -Name 'LocalVideo' -DefaultValue '')
            $eo=[string](Get-OptionalPropertyValue -Object $queueRecord -Name 'ExpectedOutput' -DefaultValue '')
            if (-not [string]::IsNullOrWhiteSpace($lv) -and (Test-Path -LiteralPath $lv -PathType Leaf)) { $sourceList.Add($lv) }
            if (-not [string]::IsNullOrWhiteSpace($eo)) { $outputList.Add($eo) }
        }
        $currentQueueSourcePaths=@($sourceList.ToArray())
        $currentQueueOutputPaths=@($outputList.ToArray())

        # Scan-MediaLibrary har redan stöd för en absolut include-lista.
        # I köläge använder vi en temporär lista så filer från andra köposter
        # aldrig dras in i muxningen för den aktuella UNC-mappen.
        $queueIncludeListPath=Join-Path $Script:TempFolder ('queue-current-sources_{0}.json' -f $Script:RunId)
        Save-JsonFile -Path $queueIncludeListPath -Value @($currentQueueSourcePaths)
        $IncludeListPath=$queueIncludeListPath
        Write-Status INFO ("Köisolering: aktuell UNC-kö innehåller {0} lokal(a) källfil(er) och {1} förväntad(e) MKV-resultat." -f @($currentQueueSourcePaths).Count,@($currentQueueOutputPaths).Count)
    }
    if (-not $AnalyzeOnly -and -not $EncodeOnly) {
        Write-Host ''
        Write-Status INFO 'Söker rekursivt efter .ts, .mp4, .avi, .mpg och .mpeg...'
        if ($ImportFromUnc -and @($currentQueueSourcePaths).Count -eq 0) {
            Write-Status INFO 'Aktuell UNC-kö har inga lokala källfiler att muxa. Fortsätter med befintliga MKV-resultat för just denna kö.'
            $items=@()
        }
        else {
            $items=@(Scan-MediaLibrary)
        }
        if (-not ($ImportFromUnc -and @($currentQueueSourcePaths).Count -eq 0)) {
            Save-ScanResults -Items $items
            Show-Summary -Items $items
        }
        $pending=@($items | Where-Object { $_.NeedsProcessing }).Count
        if ($pending -gt 0) {
            $start=$NoConfirm
            if (-not $NoConfirm) { $start=((Read-Host ("Starta muxning av {0} filer? (J/N)" -f $pending)) -match '^(j|ja|y|yes)$') }
            if ($start) {
                Write-Status INFO 'Muxningen startar. Video och ljud kopieras utan omkodning.'
                $mux=@(Invoke-MuxQueue -Items $items)
                Save-MuxResults -Results $mux
                Show-MuxSummary -Results $mux
                $items=@(Scan-MediaLibrary -AllowEmptyIncludeList)
                Save-ScanResults -Items $items
                if ($items.Count -eq 0) { Write-Status OK 'Källmappen är nu tom efter lyckad muxning och rensning.' }
            }
        }
    }
    else { Write-Status INFO 'Källskanning och muxning hoppas över.' }

    $analysis = if ($ImportFromUnc) { @(Analyze-MkvLibrary -OnlyPaths @($currentQueueOutputPaths)) } else { @(Analyze-MkvLibrary) }
    Save-AnalysisReports -Results $analysis
    Show-AnalysisSummary -Results $analysis
    foreach($analysisItem in $analysis){
        Update-QueueDashboardItem -RelativePath ([string]$analysisItem.RelativePath) -QueueStage 5 -QueueStatus 'Analyzed' -Values @{AnalysisCompleted=(Get-Date).ToUniversalTime().ToString('o')}
    }
    $encodeCount=@($analysis | Where-Object { $_.Recommended -and $_.TargetSizeMB -gt 0 }).Count
    if ($DisableEncoding) {
        Write-Status INFO 'MKV-omkodning är avstängd. Ingen rekommenderad fil kommer att omkodas.'
    }
    elseif ($encodeCount -gt 0) {
        $startEncode=$EncodeRecommended
        if (-not $EncodeRecommended) { $startEncode=((Read-Host ("Starta HEVC-omkodning med vald encoder av {0} rekommenderade filer? (J/N)" -f $encodeCount)) -match '^(j|ja|y|yes)$') }
        if ($startEncode) {
            $enc=@(Invoke-RecommendedEncoding -AnalysisResults $analysis)
            if (@($enc | Where-Object { $_.Success -and $_.Replaced }).Count -gt 0) {
                Write-Status INFO 'Analyserar om de färdiga HEVC-filerna...'
                $analysis = if ($ImportFromUnc) { @(Analyze-MkvLibrary -OnlyPaths @($currentQueueOutputPaths)) } else { @(Analyze-MkvLibrary) }
                Save-AnalysisReports -Results $analysis
                Show-AnalysisSummary -Results $analysis
            }
        }
    }
    if ($Script:ProcessErrorQueue) {
        Write-Host ''
        [void](Invoke-ErrorQueueProcessing)
    }
    if ($uncRecords.Count -gt 0) {
        $errorRelative=@{}
        foreach($er in @(Get-ErrorQueueRecords)){if($er.RelativePath){$errorRelative[[string]$er.RelativePath]=$true}}
        foreach($recordForReturn in $uncRecords){
            if(-not $errorRelative.ContainsKey([string]$recordForReturn.RelativePath)){
                Update-QueueDashboardItem -SourcePath ([string]$recordForReturn.RemoteVideo) -RelativePath ([string]$recordForReturn.RelativePath) -QueueStage 8 -QueueStatus 'WaitingForReturn'
            }
        }
        Write-Host ''
        Write-Status INFO ("Återför endast de {0} MKV-filer som hör till den aktuella UNC-importen." -f @($uncRecords | Where-Object { $_.ImportSuccess }).Count)
        [void](Publish-UncResultsAndCleanup -Records $uncRecords -DeleteOriginals ([bool]$DeleteUncAfterSuccess))
    }
    Remove-EmptyLocalQueueFolders -Records $uncRecords
    if (-not [string]::IsNullOrWhiteSpace($queueIncludeListPath)) { Remove-Item -LiteralPath $queueIncludeListPath -Force -ErrorAction SilentlyContinue }
    $duration=(Get-Date)-$Script:StartTime
    Write-Status OK ("Körningen är klar. Tid: {0}" -f $duration.ToString('hh\:mm\:ss'))
    Write-Status INFO ("Loggfil: {0}" -f $Script:LogFile)
}
catch { Write-Host ''; Write-Status ERROR $_.Exception.Message; Write-Status ERROR ("Rad: {0}" -f $_.InvocationInfo.ScriptLineNumber); exit 1 }
finally { if (-not $NoPause -and $Host.Name -eq 'ConsoleHost') { Write-Host ''; Write-Host 'Tryck Enter för att avsluta...' -ForegroundColor DarkGray; [void](Read-Host) } }
#endregion
