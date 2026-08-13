#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$RequestFile,
    [int]$ParentPid = 0,
    [switch]$DeleteSelf
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$dataFolder=Join-Path $Root 'Data'
$backupRoot=Join-Path $dataFolder 'ProgramBackups'
$logFolder=Join-Path $Root 'Loggar'
$resultPath=Join-Path $dataFolder 'mediaprep-update-result.json'
$logPath=Join-Path $logFolder ("MediaPrep-Updater_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
foreach($folder in @($dataFolder,$backupRoot,$logFolder)){if(-not(Test-Path -LiteralPath $folder -PathType Container)){New-Item -ItemType Directory -Path $folder -Force|Out-Null}}

function Write-UpdateLog([string]$Level,[string]$Message){
    $line='{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$Level,$Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}
function Read-Json([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null};return(Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json)}
function Write-Json([string]$Path,[object]$Value){$Value|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Path -Encoding UTF8}
function P([object]$Object,[string]$Name,$Default=$null){
    if($null -eq $Object){return $Default}
    $p=$Object.PSObject.Properties[$Name]
    if($null -eq $p){return $Default}
    return $p.Value
}
function Test-MediaPrepWorkerActive {
    # Defense in depth: activation must never replace App/Tools-facing program files
    # while a MediaPrep queue, engine, or media tool belonging to this root is alive.
    try{
        $rootText=[string]$Root
        $all=@(Get-CimInstance Win32_Process -OperationTimeoutSec 3 -ErrorAction Stop | Select-Object ProcessId,Name,ExecutablePath,CommandLine)
        foreach($proc in $all){
            if([int]$proc.ProcessId -eq [int]$PID){continue}
            $name=[string]$proc.Name
            $cmd=[string]$proc.CommandLine
            $exe=[string]$proc.ExecutablePath
            $belongs=($cmd.IndexOf($rootText,[StringComparison]::OrdinalIgnoreCase)-ge0 -or $exe.IndexOf($rootText,[StringComparison]::OrdinalIgnoreCase)-ge0)
            if(-not$belongs){continue}
            if($name -match '^(powershell|pwsh)\.exe$' -and $cmd -match 'MediaPrep-(Queue-Host|Queue)\.ps1|[\\/]MediaPrep\.ps1'){return $true}
            if($name -match '^(ffmpeg|ffprobe|mkvmerge)\.exe$'){return $true}
        }
        return $false
    }catch{
        # If process inspection is unavailable, use the queue run marker conservatively.
        try{
            $run=Read-Json (Join-Path $dataFolder 'queue-run-current.json')
            if($null-ne$run -and [string](P $run 'Status' '') -eq 'Running'){return $true}
        }catch{}
        return $false
    }
}

function Copy-ProgramPayload([string]$Source,[string]$Destination,[switch]$ClearProgramDirectories){
    foreach($dirName in @('App','Languages','Installer','Assets')){
        $src=Join-Path $Source $dirName
        if(-not(Test-Path -LiteralPath $src -PathType Container)){continue}
        $dst=Join-Path $Destination $dirName
        if($ClearProgramDirectories -and (Test-Path -LiteralPath $dst -PathType Container)){Remove-Item -LiteralPath $dst -Recurse -Force}
        if(-not(Test-Path -LiteralPath $dst -PathType Container)){New-Item -ItemType Directory -Path $dst -Force|Out-Null}
        Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force
    }
    foreach($fileName in @('Start MediaPrep.cmd','README.md','CHANGELOG.md','LICENSE.md','THIRD-PARTY-NOTICES.md')){
        $src=Join-Path $Source $fileName
        if(Test-Path -LiteralPath $src -PathType Leaf){Copy-Item -LiteralPath $src -Destination (Join-Path $Destination $fileName) -Force}
    }
    $errorHelper=Join-Path $Source 'Error\Bearbeta felko.cmd'
    if(Test-Path -LiteralPath $errorHelper -PathType Leaf){
        $errorDestination=Join-Path $Destination 'Error'
        if(-not(Test-Path -LiteralPath $errorDestination -PathType Container)){New-Item -ItemType Directory -Path $errorDestination -Force|Out-Null}
        Copy-Item -LiteralPath $errorHelper -Destination (Join-Path $errorDestination 'Bearbeta felko.cmd') -Force
    }
}
function Unblock-ProgramPayload([string]$Destination){
    try{
        foreach($dirName in @('App','Languages','Installer','Assets','Error')){
            $dir=Join-Path $Destination $dirName
            if(Test-Path -LiteralPath $dir -PathType Container){Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue|Unblock-File -ErrorAction SilentlyContinue}
        }
        foreach($fileName in @('Start MediaPrep.cmd','README.md','CHANGELOG.md','LICENSE.md','THIRD-PARTY-NOTICES.md')){
            $file=Join-Path $Destination $fileName
            if(Test-Path -LiteralPath $file -PathType Leaf){Unblock-File -LiteralPath $file -ErrorAction SilentlyContinue}
        }
    }catch{Write-UpdateLog WARN ('Could not remove Internet-zone markers from program files: '+$_.Exception.Message)}
}
function Normalize-CmdFile([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return}
    try{
        $text=Get-Content -LiteralPath $Path -Raw
        Set-Content -LiteralPath $Path -Value $text -Encoding ASCII
    }catch{Write-UpdateLog WARN ('Could not normalize CMD file '+$Path+': '+$_.Exception.Message)}
}
function Update-VersionMetadata([string]$Version){
    foreach($name in @('config.json','mediaprep.preferences.json')){
        $path=Join-Path $dataFolder $name
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){continue}
        try{
            $doc=Read-Json $path
            if($null-ne$doc){$doc|Add-Member -NotePropertyName Version -NotePropertyValue $Version -Force;Write-Json $path $doc}
        }catch{Write-UpdateLog WARN ("Could not update version metadata in {0}: {1}" -f $name,$_.Exception.Message)}
    }
}

$request=$null
$backupPath=''
$stageRoot=''
$isBackupRestore=$false
try{
    Write-UpdateLog INFO 'Updater started.'
    $request=Read-Json $RequestFile
    if($null-eq$request){throw 'Update request could not be read.'}
    $stageRoot=[string](P $request 'StageRoot' '')
    $targetVersion=[string](P $request 'TargetVersion' '')
    $currentVersion=[string](P $request 'CurrentVersion' 'unknown')
    $isBackupRestore=[bool](P $request 'IsBackupRestore' $false)
    if([string]::IsNullOrWhiteSpace($stageRoot) -or -not(Test-Path -LiteralPath $stageRoot -PathType Container)){throw ('Staged program files are missing: '+$stageRoot)}
    if(-not(Test-Path -LiteralPath (Join-Path $stageRoot 'App\MediaPrep-Start.ps1') -PathType Leaf)){throw 'Staged package is incomplete: App\MediaPrep-Start.ps1 is missing.'}

    if($ParentPid -gt0){
        Write-UpdateLog INFO ("Waiting for Start Center PID {0} to exit." -f $ParentPid)
        $deadline=(Get-Date).AddSeconds(60)
        while((Get-Date)-lt$deadline){
            if($null-eq(Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)){break}
            Start-Sleep -Milliseconds 250
        }
        if($null-ne(Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)){throw 'Start Center did not close within 60 seconds.'}
    }

    if(Test-MediaPrepWorkerActive){
        throw 'MediaPrep update was cancelled because a queue or media worker is still running.'
    }
    Write-UpdateLog INFO 'Queue/media worker safety check passed.'

    # Always protect the currently running program version before any activation,
    # including a manual rollback. This gives failed update/restore operations a
    # safe recovery source.
    $stamp=Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $safeVersion=($currentVersion -replace '[^0-9A-Za-z._-]','_')
    $backupPath=Join-Path $backupRoot ($safeVersion+'_'+$stamp)
    New-Item -ItemType Directory -Path $backupPath -Force|Out-Null
    Copy-ProgramPayload -Source $Root -Destination $backupPath
    Write-Json (Join-Path $backupPath 'mediaprep-program-version.json') ([pscustomobject][ordered]@{Version=$currentVersion;BackedUpLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');SourceRoot=$Root})
    Write-UpdateLog INFO ('Program backup created: '+$backupPath)

    Write-UpdateLog INFO ("Activating MediaPrep {0} from {1}" -f $targetVersion,$stageRoot)
    Copy-ProgramPayload -Source $stageRoot -Destination $Root -ClearProgramDirectories
    Unblock-ProgramPayload -Destination $Root
    Normalize-CmdFile -Path (Join-Path $Root 'Start MediaPrep.cmd')
    Normalize-CmdFile -Path (Join-Path $Root 'Error\Bearbeta felko.cmd')
    if(-not(Test-Path -LiteralPath (Join-Path $Root 'App\MediaPrep-Start.ps1') -PathType Leaf)){throw 'Activation verification failed: MediaPrep-Start.ps1 is missing.'}
    if(-not(Test-Path -LiteralPath (Join-Path $Root 'Start MediaPrep.cmd') -PathType Leaf)){throw 'Activation verification failed: Start MediaPrep.cmd is missing.'}
    Update-VersionMetadata -Version $targetVersion
    $targetSupportsResult=$false
    try{$targetSupportsResult=([version]$targetVersion -ge [version]'0.11.52')}catch{}
    if($targetSupportsResult){
        Write-Json $resultPath ([pscustomobject][ordered]@{Success=$true;TargetVersion=$targetVersion;PreviousVersion=$currentVersion;BackupPath=$backupPath;CompletedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');Message=('MediaPrep '+$targetVersion+' was installed successfully.');LogPath=$logPath})
    }else{
        Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $RequestFile -Force -ErrorAction SilentlyContinue
    Write-UpdateLog INFO 'Update completed successfully.'

    if(-not$isBackupRestore -and $stageRoot -like (Join-Path (Join-Path $dataFolder 'Downloads') '*')){Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
catch{
    $message=$_.Exception.Message
    Write-UpdateLog ERROR $message
    if(-not[string]::IsNullOrWhiteSpace($backupPath) -and (Test-Path -LiteralPath $backupPath -PathType Container)){
        try{Copy-ProgramPayload -Source $backupPath -Destination $Root -ClearProgramDirectories;Write-UpdateLog WARN 'Previous MediaPrep program files were restored after the failed update.'}catch{Write-UpdateLog ERROR ('Automatic rollback also failed: '+$_.Exception.Message)}
    }
    $failedTarget=''
    $failedPrevious=''
    if($request){
        $failedTarget=[string](P $request 'TargetVersion' '')
        $failedPrevious=[string](P $request 'CurrentVersion' '')
    }
    Write-Json $resultPath ([pscustomobject][ordered]@{Success=$false;TargetVersion=$failedTarget;PreviousVersion=$failedPrevious;BackupPath=$backupPath;CompletedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');Message=$message;LogPath=$logPath})
    Remove-Item -LiteralPath $RequestFile -Force -ErrorAction SilentlyContinue
}
finally{
    try{
        $launcher=Join-Path $Root 'Start MediaPrep.cmd'
        if(Test-Path -LiteralPath $launcher -PathType Leaf){Start-Process -FilePath $launcher -WorkingDirectory $Root|Out-Null}
    }catch{Write-UpdateLog ERROR ('Could not restart MediaPrep: '+$_.Exception.Message)}
    if($DeleteSelf){
        try{Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue}catch{}
    }
}
