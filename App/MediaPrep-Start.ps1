#requires -Version 5.1
[CmdletBinding()]param([switch]$SkipElevation)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'


# 0.11.53 startup diagnostics. This log is deliberately created before WinForms
# initialization so an early startup failure cannot disappear without a trace.
$script:StartupWatch=[Diagnostics.Stopwatch]::StartNew()
$script:StartScriptPath=$MyInvocation.MyCommand.Path
$script:AppFolder=Split-Path -Parent $script:StartScriptPath
$script:Root=Split-Path -Parent $script:AppFolder
$script:StartupTracePath=$null
$script:StartupVerboseTracePath=$null
$script:StartupVerbose=$false
$script:StartupTimingActive=$true
$script:StartupStageStarts=@{}
$script:SplashSignalPath=$null
$script:SplashProcess=$null
$script:SplashStopTimer=$null

function Initialize-StartupTrace {
    try{
        $folder=Join-Path $script:Root 'Loggar'
        if(-not(Test-Path -LiteralPath $folder -PathType Container)){New-Item -ItemType Directory -Path $folder -Force|Out-Null}
        $script:StartupTracePath=Join-Path $folder 'MediaPrep-Startup.log'
        $header="MediaPrep MKV Toolkit 0.11.53 startup trace`r`nStarted: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))`r`n"
        [IO.File]::WriteAllText($script:StartupTracePath,$header,(New-Object Text.UTF8Encoding($false)))
    }catch{$script:StartupTracePath=$null}
}
function Write-StartupTrace {
    param([string]$Stage,[string]$Details='')
    try{
        if([string]::IsNullOrWhiteSpace([string]$script:StartupTracePath)){return}
        $now=Get-Date
        $ms=[int][Math]::Round($script:StartupWatch.Elapsed.TotalMilliseconds)
        $line=('{0}  +{1,7} ms  {2}' -f $now.ToString('yyyy-MM-dd HH:mm:ss.fff'),$ms,$Stage)
        if(-not[string]::IsNullOrWhiteSpace($Details)){$line+='  '+$Details}
        $encoding=New-Object Text.UTF8Encoding($false)
        [IO.File]::AppendAllText($script:StartupTracePath,$line+[Environment]::NewLine,$encoding)
        if($script:StartupVerbose -and -not[string]::IsNullOrWhiteSpace([string]$script:StartupVerboseTracePath)){
            [IO.File]::AppendAllText($script:StartupVerboseTracePath,$line+[Environment]::NewLine,$encoding)
        }
    }catch{}
}
function Write-VerboseStartupTrace {
    param([string]$Stage,[string]$Details='')
    try{
        if(-not$script:StartupVerbose -or [string]::IsNullOrWhiteSpace([string]$script:StartupVerboseTracePath)){return}
        $now=Get-Date
        $ms=[int][Math]::Round($script:StartupWatch.Elapsed.TotalMilliseconds)
        $line=('{0}  +{1,7} ms  {2}' -f $now.ToString('yyyy-MM-dd HH:mm:ss.fff'),$ms,$Stage)
        if(-not[string]::IsNullOrWhiteSpace($Details)){$line+='  '+$Details}
        [IO.File]::AppendAllText($script:StartupVerboseTracePath,$line+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    }catch{}
}
function Enable-VerboseStartupTrace {
    try{
        if($script:StartupVerbose){return}
        $folder=Join-Path $script:Root 'Loggar'
        if(-not(Test-Path -LiteralPath $folder -PathType Container)){New-Item -ItemType Directory -Path $folder -Force|Out-Null}
        $script:StartupVerboseTracePath=Join-Path $folder ('MediaPrep-Startup_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
        if(Test-Path -LiteralPath $script:StartupTracePath -PathType Leaf){
            [IO.File]::Copy($script:StartupTracePath,$script:StartupVerboseTracePath,$true)
        }
        $script:StartupVerbose=$true
        Write-StartupTrace 'VerboseStartupTimingEnabled' ('Log='+$script:StartupVerboseTracePath)
    }catch{
        $script:StartupVerbose=$false
        $script:StartupVerboseTracePath=$null
    }
}
function Start-StartupTiming {
    param([Parameter(Mandatory=$true)][string]$Stage)
    if(-not$script:StartupVerbose -or -not$script:StartupTimingActive){return}
    try{
        $script:StartupStageStarts[$Stage]=[double]$script:StartupWatch.Elapsed.TotalMilliseconds
        Write-VerboseStartupTrace ($Stage+'-Start')
    }catch{}
}
function Stop-StartupTiming {
    param([Parameter(Mandatory=$true)][string]$Stage,[string]$Details='')
    if(-not$script:StartupVerbose -or -not$script:StartupTimingActive){return}
    try{
        $durationText=''
        if($script:StartupStageStarts.ContainsKey($Stage)){
            $duration=[int][Math]::Round(([double]$script:StartupWatch.Elapsed.TotalMilliseconds)-[double]$script:StartupStageStarts[$Stage])
            $script:StartupStageStarts.Remove($Stage)
            $durationText=('Duration={0} ms' -f $duration)
        }
        if(-not[string]::IsNullOrWhiteSpace($Details)){
            if(-not[string]::IsNullOrWhiteSpace($durationText)){$durationText+='  '}
            $durationText+=$Details
        }
        Write-VerboseStartupTrace ($Stage+'-End') $durationText
    }catch{}
}
function Start-MediaPrepSplash {
    try{
        $splashScript=Join-Path $script:AppFolder 'MediaPrep-Splash.ps1'
        $splashImage=Join-Path (Join-Path $script:Root 'Assets') 'Media-PrepMKV-Toolkit-Splash.png'
        if(-not(Test-Path -LiteralPath $splashScript -PathType Leaf) -or -not(Test-Path -LiteralPath $splashImage -PathType Leaf)){return}
        $script:SplashSignalPath=Join-Path $env:TEMP ('MediaPrep-Splash-'+[guid]::NewGuid().ToString('N')+'.stop')
        Remove-Item -LiteralPath $script:SplashSignalPath -Force -ErrorAction SilentlyContinue
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName='powershell.exe'
        $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -STA -File "'+$splashScript+'" -Root "'+$script:Root+'" -SignalPath "'+$script:SplashSignalPath+'" -ParentPid '+[string]$PID
        $psi.WorkingDirectory=$script:Root
        $psi.UseShellExecute=$false
        $psi.CreateNoWindow=$true
        $script:SplashProcess=[Diagnostics.Process]::Start($psi)
        Write-StartupTrace 'SplashProcessStarted' ('PID='+[string]$script:SplashProcess.Id)
    }catch{
        Write-StartupTrace 'SplashProcessFailed' $_.Exception.Message
        $script:SplashSignalPath=$null;$script:SplashProcess=$null
    }
}
function Stop-MediaPrepSplash {
    try{
        if(-not[string]::IsNullOrWhiteSpace([string]$script:SplashSignalPath)){
            [IO.File]::WriteAllText($script:SplashSignalPath,'close',(New-Object Text.UTF8Encoding($false)))
        }
    }catch{}
}

Initialize-StartupTrace
Write-StartupTrace 'ScriptStarted'

# MediaPrep's graphical interface requires FullLanguage. On systems where
# AppLocker/WDAC enforces ConstrainedLanguage, stop before loading WinForms so
# the user gets a clear explanation instead of a cascade of type/method errors.
if ([string]$ExecutionContext.SessionState.LanguageMode -eq 'ConstrainedLanguage') {
    $clmMessage = @'
MediaPrep MKV Toolkit cannot start.

This computer enforces PowerShell ConstrainedLanguage.
MediaPrep requires PowerShell FullLanguage for its graphical interface.

The MediaPrep scripts must be allowed/trusted by your organization's AppLocker or WDAC policy.

MediaPrep will now close.
'@
    $shown=$false
    try {
        $msgExe=Join-Path $env:SystemRoot 'System32\msg.exe'
        if(Test-Path -LiteralPath $msgExe -PathType Leaf){
            & $msgExe $env:USERNAME $clmMessage 2>$null | Out-Null
            $shown=$true
        }
    } catch {}
    Write-Host $clmMessage -ForegroundColor Yellow
    if(-not $shown){Write-Host 'The message could not be displayed as a Windows popup.' -ForegroundColor Yellow}
    exit 10
}

Start-MediaPrepSplash
Write-StartupTrace 'BeforeWinForms'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
Write-StartupTrace 'WinFormsReady'

# WinForms processes do not need their PowerShell console windows visible.
# The queue worker has its own optional detail console that can be toggled from the queue monitor.
if (-not ('MediaPrep.ConsoleWindow' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace MediaPrep {
    public static class ConsoleWindow {
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
}
"@
}
function Hide-MediaPrepOwnConsole {
    try {
        $hWnd=[MediaPrep.ConsoleWindow]::GetConsoleWindow()
        if($hWnd -ne [IntPtr]::Zero){[void][MediaPrep.ConsoleWindow]::ShowWindow($hWnd,0)}
    } catch {}
}


# SMB connections must be established in the same (possibly elevated) logon
# session that starts the MediaPrep queue process.
if (-not ('MediaPrep.NativeNetwork' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace MediaPrep {
    public static class NativeNetwork {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct NETRESOURCE {
            public int dwScope;
            public int dwType;
            public int dwDisplayType;
            public int dwUsage;
            public string lpLocalName;
            public string lpRemoteName;
            public string lpComment;
            public string lpProvider;
        }

        [DllImport("mpr.dll", CharSet = CharSet.Unicode)]
        public static extern int WNetAddConnection2(
            ref NETRESOURCE lpNetResource,
            string lpPassword,
            string lpUserName,
            int dwFlags);
    }
}
"@
}

function Get-UncServerRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not $Path.StartsWith('\\')) { return $null }
    $trimmed=$Path.Substring(2)
    $server=($trimmed -split '\\',2)[0]
    if ([string]::IsNullOrWhiteSpace($server)) { return $null }
    return ('\\'+$server)
}

function Show-UncCredentialDialog {
    param([string]$ServerRoot)
    $dialog=New-Object Windows.Forms.Form
    $dialog.Text=T 'UncAuthenticationTitle' 'Network authentication'
    $dialog.StartPosition='CenterParent'
    $dialog.FormBorderStyle='FixedDialog'
    $dialog.MaximizeBox=$false;$dialog.MinimizeBox=$false
    $dialog.ClientSize=New-Object Drawing.Size(430,205)

    $intro=New-Object Windows.Forms.Label
    $intro.Location=New-Object Drawing.Point(18,15);$intro.Size=New-Object Drawing.Size(394,42)
    $intro.Text=T 'UncAuthenticationPrompt' 'Enter credentials for {0}. The connection is created for the elevated MediaPrep session.' @($ServerRoot)
    $dialog.Controls.Add($intro)

    $userLabel=New-Object Windows.Forms.Label
    $userLabel.Location=New-Object Drawing.Point(18,66);$userLabel.Size=New-Object Drawing.Size(105,22)
    $userLabel.Text=T 'Username' 'Username'
    $dialog.Controls.Add($userLabel)
    $userBox=New-Object Windows.Forms.TextBox
    $userBox.Location=New-Object Drawing.Point(128,63);$userBox.Size=New-Object Drawing.Size(280,25)
    $dialog.Controls.Add($userBox)

    $passLabel=New-Object Windows.Forms.Label
    $passLabel.Location=New-Object Drawing.Point(18,101);$passLabel.Size=New-Object Drawing.Size(105,22)
    $passLabel.Text=T 'Password' 'Password'
    $dialog.Controls.Add($passLabel)
    $passBox=New-Object Windows.Forms.TextBox
    $passBox.Location=New-Object Drawing.Point(128,98);$passBox.Size=New-Object Drawing.Size(280,25)
    $passBox.UseSystemPasswordChar=$true
    $dialog.Controls.Add($passBox)

    $ok=New-Object Windows.Forms.Button
    $ok.Text=T 'Connect' 'Connect';$ok.Location=New-Object Drawing.Point(236,151);$ok.Size=New-Object Drawing.Size(82,32)
    $ok.DialogResult=[Windows.Forms.DialogResult]::OK
    $dialog.Controls.Add($ok)
    $cancel=New-Object Windows.Forms.Button
    $cancel.Text=T 'Cancel' 'Cancel';$cancel.Location=New-Object Drawing.Point(326,151);$cancel.Size=New-Object Drawing.Size(82,32)
    $cancel.DialogResult=[Windows.Forms.DialogResult]::Cancel
    $dialog.Controls.Add($cancel)
    $dialog.AcceptButton=$ok;$dialog.CancelButton=$cancel

    $result=$dialog.ShowDialog($form)
    if($result -ne [Windows.Forms.DialogResult]::OK){$dialog.Dispose();return $null}
    $answer=[pscustomobject]@{UserName=$userBox.Text.Trim();Password=$passBox.Text}
    $dialog.Dispose()
    return $answer
}

function Connect-UncServerForMediaPrep {
    param([string]$ServerRoot)
    $credentials=Show-UncCredentialDialog -ServerRoot $ServerRoot
    if($null -eq $credentials){return $false}
    if([string]::IsNullOrWhiteSpace([string]$credentials.UserName)){
        [Windows.Forms.MessageBox]::Show((T 'UsernameRequired' 'A username is required.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)|Out-Null
        return $false
    }
    $resource=New-Object MediaPrep.NativeNetwork+NETRESOURCE
    $resource.dwType=1 # RESOURCETYPE_DISK
    $resource.lpRemoteName=($ServerRoot+'\IPC$')
    $result=[MediaPrep.NativeNetwork]::WNetAddConnection2([ref]$resource,[string]$credentials.Password,[string]$credentials.UserName,0)
    $credentials.Password=$null
    if($result -eq 0){return $true}
    $message=switch($result){
        1219 { T 'UncCredentialConflict' 'Windows already has a connection to {0} using different credentials. Disconnect that SMB connection and try again.' @($ServerRoot) }
        1326 { T 'UncLogonFailure' 'The username or password was rejected by {0}.' @($ServerRoot) }
        53   { T 'UncServerNotFound' 'The network path {0} could not be reached.' @($ServerRoot) }
        default { T 'UncConnectionFailed' 'Could not authenticate to {0}. Windows error: {1}' @($ServerRoot,$result) }
    }
    [Windows.Forms.MessageBox]::Show($message,'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null
    return $false
}

function Test-UncQueueAccess {
    param([object[]]$Paths)
    $authenticated=@{}
    foreach($rawPath in @($Paths)){
        $path=[string]$rawPath
        if([string]::IsNullOrWhiteSpace($path) -or -not $path.StartsWith('\\')){
            throw(T 'InvalidUnc' 'Invalid or unavailable UNC path: {0}' @($path))
        }
        $serverRoot=Get-UncServerRoot $path
        $hasAccess=$false
        try{$hasAccess=Test-Path -LiteralPath $path -PathType Container}catch{$hasAccess=$false}
        if(-not $hasAccess){
            if(-not $authenticated.ContainsKey($serverRoot)){
                if(-not (Connect-UncServerForMediaPrep -ServerRoot $serverRoot)){return $false}
                $authenticated[$serverRoot]=$true
            }
            try{$hasAccess=Test-Path -LiteralPath $path -PathType Container}catch{$hasAccess=$false}
        }
        if(-not $hasAccess){
            [Windows.Forms.MessageBox]::Show((T 'InvalidUncAfterAuthentication' 'The UNC folder is still unavailable after authentication: {0}' @($path)),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null
            return $false
        }

        # Verify the permissions MediaPrep needs at the end of a long batch.
        $accessTest=Join-Path $path ('.mediaprep-access-test-'+[guid]::NewGuid().ToString('N')+'.tmp')
        try{
            [IO.File]::WriteAllText($accessTest,'MediaPrep access test',(New-Object Text.UTF8Encoding($false)))
            if(-not(Test-Path -LiteralPath $accessTest -PathType Leaf)){throw 'Write verification failed.'}
            Remove-Item -LiteralPath $accessTest -Force
            if(Test-Path -LiteralPath $accessTest -PathType Leaf){throw 'Delete verification failed.'}
        }catch{
            Remove-Item -LiteralPath $accessTest -Force -ErrorAction SilentlyContinue
            [Windows.Forms.MessageBox]::Show((T 'UncPermissionTestFailed' 'MediaPrep can read the folder but could not verify write/delete access: {0}`r`n`r`n{1}' @($path,$_.Exception.Message)),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null
            return $false
        }
    }
    return $true
}


# A startup failure must never disappear in a flashing elevated console.
$script:AppFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:BootstrapRoot = Split-Path -Parent $script:AppFolder
trap {
    Write-StartupTrace 'StartupTrap' $_.Exception.Message
    Stop-MediaPrepSplash
    try {
        $fallbackLogFolder = Join-Path $script:BootstrapRoot 'Loggar'
        if (-not (Test-Path -LiteralPath $fallbackLogFolder -PathType Container)) {
            New-Item -Path $fallbackLogFolder -ItemType Directory -Force | Out-Null
        }
        $startupLog = Join-Path $fallbackLogFolder ("MediaPrep-Start-error_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
        $details = @(
            'MediaPrep Start Center startup failure'
            ('Time: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
            ('PowerShell: {0}' -f $PSVersionTable.PSVersion)
            ('Script: {0}' -f $MyInvocation.MyCommand.Path)
            ('Message: {0}' -f $_.Exception.Message)
            ('Type: {0}' -f $_.Exception.GetType().FullName)
            ('Category: {0}' -f $_.CategoryInfo)
            ('FullyQualifiedErrorId: {0}' -f $_.FullyQualifiedErrorId)
            ('Position: {0}' -f $_.InvocationInfo.PositionMessage)
            ('Stack: {0}' -f $_.ScriptStackTrace)
        ) -join [Environment]::NewLine
        [IO.File]::WriteAllText($startupLog, $details, (New-Object Text.UTF8Encoding($true)))
        [Windows.Forms.MessageBox]::Show(
            "MediaPrep could not start.`r`n`r`n$($_.Exception.Message)`r`n`r`nStartup log:`r`n$startupLog",
            'MediaPrep startup error',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
        [Windows.Forms.MessageBox]::Show(
            "MediaPrep could not start.`r`n`r`n$($_.Exception.Message)",
            'MediaPrep startup error',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    break
}

# Resolve the application root before deciding whether elevation is needed.
$script:StartScriptPath = $MyInvocation.MyCommand.Path
$script:AppFolder = Split-Path -Parent $script:StartScriptPath
$script:Root = Split-Path -Parent $script:AppFolder
$script:PreferencesPath = Join-Path (Join-Path $script:Root 'Data') 'mediaprep.preferences.json'
$script:StartupSettingsPath = Join-Path (Join-Path $script:Root 'Data') 'start-installningar.json'

function Test-IsAdministrator {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    $p=New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-SavedPreventUpdateRestart {
    try {
        if(-not(Test-Path -LiteralPath $script:StartupSettingsPath -PathType Leaf)){return $false}
        $raw=[IO.File]::ReadAllText($script:StartupSettingsPath,[Text.Encoding]::UTF8)
        if([string]::IsNullOrWhiteSpace($raw)){return $false}
        $obj=$raw|ConvertFrom-Json
        if($obj.PSObject.Properties['PreventUpdateRestart']){return [bool]$obj.PreventUpdateRestart}
    } catch {}
    return $false
}
function Start-MediaPrepElevated {
    $si=New-Object Diagnostics.ProcessStartInfo
    $si.FileName='powershell.exe'
    $si.Arguments='-NoProfile -ExecutionPolicy Bypass -STA -File "'+$script:StartScriptPath+'" -SkipElevation'
    $si.WorkingDirectory=$script:Root
    $si.UseShellExecute=$true
    $si.Verb='runas'
    return [Diagnostics.Process]::Start($si)
}

$script:IsAdministrator=Test-IsAdministrator
$script:SavedPreventUpdateRestart=Get-SavedPreventUpdateRestart
# Normal startup is non-elevated. UAC is requested only after the user has
# explicitly saved Windows Update restart protection.
if(-not $script:IsAdministrator -and $script:SavedPreventUpdateRestart -and -not $SkipElevation){
    try{
        [void](Start-MediaPrepElevated)
        exit 0
    }catch [ComponentModel.Win32Exception]{
        if ($_.Exception.NativeErrorCode -ne 1223){throw}
    }
}

# Hide the Start Center PowerShell host; the WinForms window remains visible.
Hide-MediaPrepOwnConsole

# Layout migration from <=0.11.35. The new App folder keeps the install root clean.
# Legacy root scripts are preserved in Data\LegacyLayoutBackup instead of deleted.
function Invoke-LegacyLayoutMigration {
    try {
        $dataFolder = Join-Path $script:Root 'Data'
        if(-not(Test-Path -LiteralPath $dataFolder -PathType Container)){New-Item -Path $dataFolder -ItemType Directory -Force|Out-Null}
        foreach($name in @('config.json','mediaprep.preferences.json')){
            $old=Join-Path $script:Root $name
            $new=Join-Path $dataFolder $name
            if((Test-Path -LiteralPath $old -PathType Leaf) -and -not(Test-Path -LiteralPath $new -PathType Leaf)){
                Move-Item -LiteralPath $old -Destination $new -Force
            }
        }
        $legacy=@('MediaPrep-Start.ps1','MediaPrep.ps1','MediaPrep-Queue.ps1','MediaPrep-Queue-Host.ps1','MediaPrep-Queue-Dashboard.ps1','Manage-MediaPrepTools.ps1','Install-MediaPrep.ps1')
        $present=@($legacy|Where-Object{Test-Path -LiteralPath (Join-Path $script:Root $_) -PathType Leaf})
        if($present.Count -gt 0){
            $backup=Join-Path $dataFolder ('LegacyLayoutBackup_'+(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
            New-Item -Path $backup -ItemType Directory -Force|Out-Null
            foreach($name in $present){Move-Item -LiteralPath (Join-Path $script:Root $name) -Destination (Join-Path $backup $name) -Force}
        }
    } catch {
        # Layout migration must never prevent Start Center from starting.
    }
}
Invoke-LegacyLayoutMigration

$script:QueueProcess = $null
$script:QueueDashboardProcess = $null
$script:SuppressDashboardShutdownOnClose = $false
$script:QueueRunActive = $false
$script:UncItems = @()
$script:LocalItems = @()
$script:LastWorkMode = $null
$script:StatisticsCurrentPath = Join-Path (Join-Path $script:Root 'Data') 'statistics-run-current.json'
$script:StatisticsArchiveFolder = Join-Path (Join-Path $script:Root 'Data') 'Statistics'
$script:StatisticsSessionId = ''

function Read-Json {
    param([string]$Path, [object]$Default)
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
    }
    catch {
        # Invalid optional files must not prevent the Preferences tab from opening.
    }
    return $Default
}
function Write-Json {
    param([string]$Path, [object]$Object)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }
    $tmp=$Path+'.tmp.'+$PID
    [IO.File]::WriteAllText($tmp, ($Object | ConvertTo-Json -Depth 16), (New-Object Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Save-StatisticsSession {
    param([object]$Session)
    if($null -eq $Session){return}
    $now=(Get-Date).ToUniversalTime().ToString('o')
    $prop=$Session.PSObject.Properties['LastUpdatedUtc']
    if($prop){$prop.Value=$now}else{$Session|Add-Member -NotePropertyName LastUpdatedUtc -NotePropertyValue $now}
    Write-Json $script:StatisticsCurrentPath $Session
}
function New-StatisticsSessionObject {
    return [pscustomobject][ordered]@{
        Version=2
        SessionId=[Guid]::NewGuid().ToString('N')
        StartedLocal=''
        StartedUtc=''
        EndedLocal=''
        EndedUtc=''
        ActiveRunStartedLocal=''
        ActiveRunStartedUtc=''
        ActiveSeconds=0.0
        ElapsedSeconds=0.0
        Status='NotStarted'
        LastUpdatedUtc=(Get-Date).ToUniversalTime().ToString('o')
        Queues=@()
    }
}
function Get-StatisticsElapsedSeconds {
    param([object]$Session)
    if($null -eq $Session){return 0.0}
    [double]$seconds=0.0
    try{$seconds=[double](P $Session 'ActiveSeconds' (P $Session 'ElapsedSeconds' 0))}catch{}
    $status=[string](P $Session 'Status' '')
    $activeUtc=[string](P $Session 'ActiveRunStartedUtc' '')
    if($status -eq 'Running' -and -not[string]::IsNullOrWhiteSpace($activeUtc)){
        try{$seconds += ((Get-Date).ToUniversalTime()-[datetime]::Parse($activeUtc).ToUniversalTime()).TotalSeconds}catch{}
    }
    if($seconds -lt 0){$seconds=0}
    return [double]$seconds
}
function Save-SessionArchive {
    param([object]$Session,[string]$Prefix='statistics-run')
    if($null -eq $Session){return $null}
    if(-not(Test-Path -LiteralPath $script:StatisticsArchiveFolder -PathType Container)){New-Item -Path $script:StatisticsArchiveFolder -ItemType Directory -Force|Out-Null}
    $safeStart=[string](P $Session 'StartedLocal' '')
    if([string]::IsNullOrWhiteSpace($safeStart)){$safeStart=Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'}else{$safeStart=$safeStart.Replace(':','-').Replace(' ','_')}
    $archive=Join-Path $script:StatisticsArchiveFolder ("{0}-{1}.json" -f $Prefix,$safeStart)
    Write-Json $archive $Session
    return $archive
}
function Add-SessionQueuesFromInventory {
    param([object]$Session,[string[]]$QueueRoots)
    if($null -eq $Session){return}
    $queues=@(P $Session 'Queues' @())
    $inventory=Read-Json -Path (Join-Path (Join-Path $script:Root 'Data') 'queue-dashboard-inventory.json') -Default $null
    $inventoryItems=if($inventory -and $inventory.PSObject.Properties['items']){@($inventory.items)}else{@()}
    foreach($rootPath in @($QueueRoots)){
        if([string]::IsNullOrWhiteSpace([string]$rootPath)){continue}
        $existing=$null
        foreach($q in $queues){if([string]::Equals([string](P $q 'SourceRoot' ''),[string]$rootPath,[StringComparison]::OrdinalIgnoreCase)){$existing=$q;break}}
        if($null -eq $existing){
            $existing=[pscustomobject][ordered]@{QueueId=[Guid]::NewGuid().ToString('N');SourceRoot=[string]$rootPath;RegisteredLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');StartedLocal='';StartedUtc='';CompletedLocal='';CompletedUtc='';Status='Queued';LastUpdatedUtc=(Get-Date).ToUniversalTime().ToString('o');Files=@()}
            $queues += $existing
        }
        $files=@(P $existing 'Files' @())
        foreach($it in $inventoryItems){
            if(-not[string]::Equals([string](P $it 'Root' ''),[string]$rootPath,[StringComparison]::OrdinalIgnoreCase)){continue}
            $rel=[string](P $it 'RelativePath' '')
            $found=$null
            foreach($f in $files){
                $fr=[string](P $f 'RelativePath' '')
                try{if([string]::Equals([IO.Path]::ChangeExtension($fr,$null),[IO.Path]::ChangeExtension($rel,$null),[StringComparison]::OrdinalIgnoreCase)){$found=$f;break}}catch{}
            }
            if($null -eq $found){
                $files += [pscustomobject][ordered]@{SourcePath=[string](P $it 'SourcePath' '');RelativePath=$rel;SourceSize=[int64](P $it 'SourceSize' 0);MuxedSize=(P $it 'MuxedSize' $null);EncodedSize=(P $it 'EncodedSize' $null);FinalSize=(P $it 'FinalSize' $null);QueueStage=[int](P $it 'QueueStage' 0);QueueStatus=[string](P $it 'QueueStatus' 'Waiting');CopyInBytes=0;CopyInSeconds=0;CopyInMBps=0;CopyBackBytes=0;CopyBackSeconds=0;CopyBackMBps=0;CopyEvents=@();Result='Pending'}
            }
        }
        if($existing.PSObject.Properties['Files']){$existing.Files=@($files)}else{$existing|Add-Member -NotePropertyName Files -NotePropertyValue @($files)}
    }
    if($Session.PSObject.Properties['Queues']){$Session.Queues=@($queues)}else{$Session|Add-Member -NotePropertyName Queues -NotePropertyValue @($queues)}
}
function Start-StatisticsRun {
    param([string[]]$QueueRoots=@(),[datetime]$RunStart=(Get-Date))
    $session=Read-Json -Path $script:StatisticsCurrentPath -Default $null
    if($null -eq $session){$session=New-StatisticsSessionObject}
    $now=$RunStart
    if([string]::IsNullOrWhiteSpace([string](P $session 'StartedLocal' ''))){
        foreach($pair in @(@('StartedLocal',$now.ToString('yyyy-MM-dd HH:mm:ss')),@('StartedUtc',$now.ToUniversalTime().ToString('o')))){if($session.PSObject.Properties[$pair[0]]){$session.PSObject.Properties[$pair[0]].Value=$pair[1]}else{$session|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1]}}
    }
    foreach($pair in @(@('EndedLocal',''),@('EndedUtc',''),@('ActiveRunStartedLocal',$now.ToString('yyyy-MM-dd HH:mm:ss')),@('ActiveRunStartedUtc',$now.ToUniversalTime().ToString('o')),@('Status','Running'))){if($session.PSObject.Properties[$pair[0]]){$session.PSObject.Properties[$pair[0]].Value=$pair[1]}else{$session|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1]}}
    Add-SessionQueuesFromInventory -Session $session -QueueRoots $QueueRoots
    $script:StatisticsSessionId=[string](P $session 'SessionId' '')
    Save-StatisticsSession $session
}
function Pause-StatisticsRun {
    param([string]$Status='Idle')
    $session=Read-Json -Path $script:StatisticsCurrentPath -Default $null
    if($null -eq $session){return}
    $now=Get-Date
    [double]$active=[double](P $session 'ActiveSeconds' (P $session 'ElapsedSeconds' 0))
    $activeUtc=[string](P $session 'ActiveRunStartedUtc' '')
    if([string](P $session 'Status' '') -eq 'Running' -and -not[string]::IsNullOrWhiteSpace($activeUtc)){try{$active += ($now.ToUniversalTime()-[datetime]::Parse($activeUtc).ToUniversalTime()).TotalSeconds}catch{}}
    foreach($pair in @(@('ActiveSeconds',[Math]::Max(0.0,$active)),@('ElapsedSeconds',[Math]::Max(0.0,$active)),@('ActiveRunStartedLocal',''),@('ActiveRunStartedUtc',''),@('EndedLocal',$now.ToString('yyyy-MM-dd HH:mm:ss')),@('EndedUtc',$now.ToUniversalTime().ToString('o')),@('Status',$Status))){if($session.PSObject.Properties[$pair[0]]){$session.PSObject.Properties[$pair[0]].Value=$pair[1]}else{$session|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1]}}
    Save-StatisticsSession $session
}
function New-RecoveryChoiceDialog {
    $d=New-Object Windows.Forms.Form;$d.Text=T 'RecoverySessionTitle' 'MediaPrep - unfinished session';$d.StartPosition='CenterScreen';$d.FormBorderStyle='FixedDialog';$d.MaximizeBox=$false;$d.MinimizeBox=$false;$d.ClientSize=New-Object Drawing.Size(560,205)
    $l=New-Object Windows.Forms.Label;$l.Location=New-Object Drawing.Point(18,18);$l.Size=New-Object Drawing.Size(524,78);$l.Text=T 'RecoverySessionMessage' 'MediaPrep found a session file that did not close normally.';$d.Controls.Add($l)
    $continue=New-Object Windows.Forms.Button;$continue.Text=T 'RecoveryContinue' 'Continue';$continue.Location=New-Object Drawing.Point(78,132);$continue.Size=New-Object Drawing.Size(120,38);$continue.Tag='Continue';$d.Controls.Add($continue)
    $save=New-Object Windows.Forms.Button;$save.Text=T 'RecoverySaveLater' 'Save for later';$save.Location=New-Object Drawing.Point(210,132);$save.Size=New-Object Drawing.Size(140,38);$save.Tag='Save';$d.Controls.Add($save)
    $delete=New-Object Windows.Forms.Button;$delete.Text=T 'RecoveryDelete' 'Delete';$delete.Location=New-Object Drawing.Point(362,132);$delete.Size=New-Object Drawing.Size(120,38);$delete.Tag='Delete';$d.Controls.Add($delete)
    $script:RecoveryChoice='Continue'
    $continue.Add_Click({$script:RecoveryChoice='Continue';$d.Close()})
    $save.Add_Click({$script:RecoveryChoice='Save';$d.Close()})
    $delete.Add_Click({$script:RecoveryChoice='Delete';$d.Close()})
    [void]$d.ShowDialog();$d.Dispose();return $script:RecoveryChoice
}
function Get-QueueRuntimeJsonNames {
    return @('queue-dashboard-inventory.json','error-queue.json','statistics-run-current.json','unc-import-manifest.json','queue-copy-stats.json','queue-run-current.json','senaste-kojobb.json','start-installningar.json','all-in-one-files.json')
}
function Save-QueuePackageCore {
    param([string]$Destination,[string[]]$QueueItems=@(),[string]$WorkMode='Queue')
    $temp=Join-Path (Join-Path $script:Root 'Data\Temp') ('QueueSave_'+[Guid]::NewGuid().ToString('N'))
    New-Item -Path $temp -ItemType Directory -Force|Out-Null
    try{
        $meta=[pscustomobject][ordered]@{Version=1;SavedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');WorkMode=$WorkMode;QueueItems=@($QueueItems);Root=$script:Root}
        Write-Json (Join-Path $temp 'queue-package.json') $meta
        foreach($name in Get-QueueRuntimeJsonNames){$src=Join-Path (Join-Path $script:Root 'Data') $name;if(Test-Path -LiteralPath $src -PathType Leaf){Copy-Item -LiteralPath $src -Destination (Join-Path $temp $name) -Force}}
        if(Test-Path -LiteralPath $Destination){Remove-Item -LiteralPath $Destination -Force}
        Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $Destination -CompressionLevel Optimal -Force
        return $Destination
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
function Initialize-StatisticsState {
    if(-not(Test-Path -LiteralPath $script:StatisticsArchiveFolder -PathType Container)){New-Item -Path $script:StatisticsArchiveFolder -ItemType Directory -Force|Out-Null}
    if(-not(Test-Path -LiteralPath $script:StatisticsCurrentPath -PathType Leaf)){return}
    $old=Read-Json -Path $script:StatisticsCurrentPath -Default $null
    if($null -eq $old){Remove-Item -LiteralPath $script:StatisticsCurrentPath -Force -ErrorAction SilentlyContinue;return}
    $status=[string](P $old 'Status' '')
    if($status -eq 'Closed'){[void](Save-SessionArchive $old);Remove-Item -LiteralPath $script:StatisticsCurrentPath -Force -ErrorAction SilentlyContinue;return}
    # Stop the clock at the last known update so downtime is not counted.
    if($status -eq 'Running'){
        [double]$active=[double](P $old 'ActiveSeconds' (P $old 'ElapsedSeconds' 0));$a=[string](P $old 'ActiveRunStartedUtc' '');$last=[string](P $old 'LastUpdatedUtc' '')
        if(-not[string]::IsNullOrWhiteSpace($a) -and -not[string]::IsNullOrWhiteSpace($last)){try{$active += ([datetime]::Parse($last).ToUniversalTime()-[datetime]::Parse($a).ToUniversalTime()).TotalSeconds}catch{}}
        foreach($pair in @(@('ActiveSeconds',[Math]::Max(0.0,$active)),@('ElapsedSeconds',[Math]::Max(0.0,$active)),@('ActiveRunStartedLocal',''),@('ActiveRunStartedUtc',''),@('Status','Recovered'))){if($old.PSObject.Properties[$pair[0]]){$old.PSObject.Properties[$pair[0]].Value=$pair[1]}else{$old|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1]}}
        Save-StatisticsSession $old
    }
    $choice=New-RecoveryChoiceDialog
    if($choice -eq 'Continue'){return}
    if($choice -eq 'Save'){
        $folder=Join-Path (Join-Path $script:Root 'Data') 'SavedQueues';if(-not(Test-Path -LiteralPath $folder)){New-Item -Path $folder -ItemType Directory -Force|Out-Null}
        $dest=Join-Path $folder ('Recovered-Queue_'+(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')+'.zip')
        $recoverSettings=Read-Json -Path (Join-Path (Join-Path $script:Root 'Data') 'start-installningar.json') -Default $null
        $recoverItems=if($recoverSettings){@(P $recoverSettings 'UncQueue' @())}else{@()}
        $recoverMode=if($recoverSettings){[string](P $recoverSettings 'WorkMode' 'Queue')}else{'Queue'}
        [void](Save-QueuePackageCore -Destination $dest -QueueItems $recoverItems -WorkMode $recoverMode)
        [void](Save-SessionArchive $old 'statistics-run-saved')
    }
    foreach($name in Get-QueueRuntimeJsonNames){Remove-Item -LiteralPath (Join-Path (Join-Path $script:Root 'Data') $name) -Force -ErrorAction SilentlyContinue}
}
function Finalize-StatisticsSession {
    try{
        if($script:QueueRunActive){return}
        if(-not(Test-Path -LiteralPath $script:StatisticsCurrentPath -PathType Leaf)){return}
        $session=Read-Json -Path $script:StatisticsCurrentPath -Default $null
        if($null -eq $session){return}
        if([string](P $session 'Status' '') -eq 'Running'){
            Pause-StatisticsRun -Status 'Idle'
            $session=Read-Json -Path $script:StatisticsCurrentPath -Default $session
        }
        $ended=Get-Date
        $endedLocal=[string](P $session 'EndedLocal' '')
        $endedUtc=[string](P $session 'EndedUtc' '')
        if([string]::IsNullOrWhiteSpace($endedLocal)){$endedLocal=$ended.ToString('yyyy-MM-dd HH:mm:ss')}
        if([string]::IsNullOrWhiteSpace($endedUtc)){$endedUtc=$ended.ToUniversalTime().ToString('o')}
        $values=@{
            EndedLocal=$endedLocal
            EndedUtc=$endedUtc
            ElapsedSeconds=(Get-StatisticsElapsedSeconds $session)
            Status='Closed'
        }
        foreach($name in $values.Keys){
            if($session.PSObject.Properties[$name]){$session.PSObject.Properties[$name].Value=$values[$name]}
            else{$session|Add-Member -NotePropertyName $name -NotePropertyValue $values[$name]}
        }
        Save-StatisticsSession $session
        [void](Save-SessionArchive $session)
        Remove-Item -LiteralPath $script:StatisticsCurrentPath -Force -ErrorAction SilentlyContinue
    }catch{}
}

function P {
    param([object]$Object, [string]$Name, [object]$Default)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}
function Default-Prefs {
    return [pscustomobject][ordered]@{
        Version = '0.11.53'
        Language = 'system'
        ApplicationFolder = $script:Root
        SourceFolder = (Join-Path $script:Root 'UnProcessed')
        OutputFolder = (Join-Path $script:Root 'Processed')
        DataFolder = (Join-Path $script:Root 'Data')
        LogFolder = (Join-Path $script:Root 'Loggar')
        ReportFolder = (Join-Path $script:Root 'Rapporter')
        TempFolder = (Join-Path $script:Root 'Data\Temp')
        FFmpegPath = (Join-Path $script:Root 'Tools\FFmpeg\ffmpeg.exe')
        FFprobePath = (Join-Path $script:Root 'Tools\FFmpeg\ffprobe.exe')
        MkvmergePath = (Join-Path $script:Root 'Tools\MKVToolNix\mkvmerge.exe')
        TVTargetMBPerMinute = 15.0
        MovieTargetMBPerMinute = 17.0
        EncodeThresholdMultiplier = 1.25
        MinimumSavingPercent = 20.0
        Theme = 'Light'
        CustomThemeBanner = '#1A4775'
        CustomThemePanel = '#D7E7F6'
        CustomThemeBackground = '#F4F7FA'
        SelectedEncoderId = 'cpu-libx265'
        EncoderBenchmarkSeconds = 12
        # Hardware is populated after the first real hardware read and is reused on normal startup.
        Hardware = $null
    }
}
function Default-Settings {
    return [pscustomobject][ordered]@{
        Mode='Full'; WorkMode='Queue'; NoConfirm=$true; EnableEncoding=$true; EncodeRecommended=$true; Force=$false; IgnoreDecodeErrors=$false; ProcessErrorQueue=$false
        VideoFormats=@('.ts','.mp4','.avi','.mpg','.mpeg')
        Reanalyze=$false; RebuildIndex=$false; NoPause=$true; UncEnabled=$true
        UncQueue=@(); LocalFileQueue=@(); TemporarySourceFolder=''; TemporaryOutputFolder='';
        DeleteUncAfterSuccess=$true; ShutdownAfterSuccess=$false
        PreventSleep=$true; PreventUpdateRestart=$false; VerboseLogging=$false; EncoderId='cpu-libx265'
    }
}
function Merge-Defaults {
    param([object]$Loaded, [object]$Defaults)
    foreach ($name in $Defaults.PSObject.Properties.Name) {
        $Defaults.$name = P -Object $Loaded -Name $name -Default $Defaults.$name
    }
    return $Defaults
}
function Resolve-ConfiguredPath {
    param(
        [object]$Value,
        [string]$FallbackRelative,
        [switch]$Executable
    )
    $fallback = Join-Path $script:Root $FallbackRelative
    $candidate = [string]$Value
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $fallback }
    if (-not [IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $script:Root $candidate }
    try { $candidate = [IO.Path]::GetFullPath($candidate) } catch { return $fallback }
    if ($Executable -and -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        # Keep the expected root path so the GUI starts and the user can browse to the tool later.
        return $fallback
    }
    return $candidate
}
function Ensure-WorkingFolder {
    param([string]$Preferred, [string]$FallbackRelative)
    $fallback = Join-Path $script:Root $FallbackRelative
    foreach ($candidate in @($Preferred, $fallback)) {
        try {
            if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
                New-Item -Path $candidate -ItemType Directory -Force | Out-Null
            }
            if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
        }
        catch { }
    }
    return $script:Root
}

# Preferences are optional. Missing, partial or invalid values fall back to the script folder.
$script:Prefs = Merge-Defaults -Loaded (Read-Json -Path $script:PreferencesPath -Default $null) -Defaults (Default-Prefs)
$script:Prefs.Version = '0.11.53'
$script:Prefs.ApplicationFolder = Resolve-ConfiguredPath -Value $script:Prefs.ApplicationFolder -FallbackRelative '.'
if (-not (Test-Path -LiteralPath $script:Prefs.ApplicationFolder -PathType Container)) {
    $script:Prefs.ApplicationFolder = $script:Root
}
# New installations use UnProcessed. Existing explicit paths, including an older Filmer folder, remain valid.
$configuredSource = [string]$script:Prefs.SourceFolder
if ($configuredSource -eq 'Filmer' -and -not (Test-Path -LiteralPath (Join-Path $script:Root 'Filmer')) -and (Test-Path -LiteralPath (Join-Path $script:Root 'UnProcessed'))) {
    $configuredSource = 'UnProcessed'
}
$script:Prefs.SourceFolder = Ensure-WorkingFolder -Preferred (Resolve-ConfiguredPath $configuredSource 'UnProcessed') -FallbackRelative 'UnProcessed'
$script:Prefs.OutputFolder = Ensure-WorkingFolder -Preferred (Resolve-ConfiguredPath $script:Prefs.OutputFolder 'Processed') -FallbackRelative 'Processed'
$script:Prefs.DataFolder = Ensure-WorkingFolder -Preferred (Resolve-ConfiguredPath $script:Prefs.DataFolder 'Data') -FallbackRelative 'Data'
$script:Prefs.LogFolder = Ensure-WorkingFolder -Preferred (Resolve-ConfiguredPath $script:Prefs.LogFolder 'Loggar') -FallbackRelative 'Loggar'
$script:Prefs.ReportFolder = Ensure-WorkingFolder -Preferred (Resolve-ConfiguredPath $script:Prefs.ReportFolder 'Rapporter') -FallbackRelative 'Rapporter'
$script:Prefs.TempFolder = Ensure-WorkingFolder -Preferred (Resolve-ConfiguredPath $script:Prefs.TempFolder 'Data\Temp') -FallbackRelative 'Data\Temp'
$script:Prefs.FFmpegPath = Resolve-ConfiguredPath -Value $script:Prefs.FFmpegPath -FallbackRelative 'Tools\FFmpeg\ffmpeg.exe' -Executable
$script:Prefs.FFprobePath = Resolve-ConfiguredPath -Value $script:Prefs.FFprobePath -FallbackRelative 'Tools\FFmpeg\ffprobe.exe' -Executable
$script:Prefs.MkvmergePath = Resolve-ConfiguredPath -Value $script:Prefs.MkvmergePath -FallbackRelative 'Tools\MKVToolNix\mkvmerge.exe' -Executable
if ([string]::IsNullOrWhiteSpace([string]$script:Prefs.Language)) { $script:Prefs.Language = 'system' }
$script:Prefs.TVTargetMBPerMinute = [double](P $script:Prefs 'TVTargetMBPerMinute' 15.0)
$script:Prefs.MovieTargetMBPerMinute = [double](P $script:Prefs 'MovieTargetMBPerMinute' 17.0)
$script:Prefs.EncodeThresholdMultiplier = [double](P $script:Prefs 'EncodeThresholdMultiplier' 1.25)
$script:Prefs.MinimumSavingPercent = [double](P $script:Prefs 'MinimumSavingPercent' 20.0)
$script:Prefs.Theme = [string](P $script:Prefs 'Theme' 'Light')
$script:Prefs.CustomThemeBanner = [string](P $script:Prefs 'CustomThemeBanner' '#1A4775')
$script:Prefs.CustomThemePanel = [string](P $script:Prefs 'CustomThemePanel' '#D7E7F6')
$script:Prefs.CustomThemeBackground = [string](P $script:Prefs 'CustomThemeBackground' '#F4F7FA')
$script:Prefs.SelectedEncoderId = [string](P $script:Prefs 'SelectedEncoderId' 'cpu-libx265')
$script:Prefs.EncoderBenchmarkSeconds = [int](P $script:Prefs 'EncoderBenchmarkSeconds' 12)
if($script:Prefs.EncoderBenchmarkSeconds -lt 5 -or $script:Prefs.EncoderBenchmarkSeconds -gt 30){$script:Prefs.EncoderBenchmarkSeconds=12}

# Resolve the interface language before unfinished-session recovery so recovery dialogs use the same language.
# Language resources use BCP-47 culture names (for example en-US and sv-SE).
# en-US is the authoritative fallback. A same-schema older translation may still
# be used safely: missing keys and format errors fall back to en-US.
$script:LanguageSchemaVersion = 1
$script:RequiredLanguageFileVersion = '1.6.0'
$script:FallbackLanguageCulture = 'en-US'
$script:LanguageBase = [pscustomobject]@{}
$script:L = [pscustomobject]@{}
$script:LanguageDocument = $null
$script:LanguageFileIsCurrent = $false

function Normalize-LanguagePreference {
    param([string]$Code)
    if ([string]::IsNullOrWhiteSpace($Code)) { return 'system' }
    $value = $Code.Trim()
    switch ($value.ToLowerInvariant()) {
        'system'  { return 'system' }
        'default' { return 'system' }
        'en'      { return 'en-US' }
        'english' { return 'en-US' }
        'en-us'   { return 'en-US' }
        'sv'      { return 'sv-SE' }
        'swedish' { return 'sv-SE' }
        'svenska' { return 'sv-SE' }
        'sv-se'   { return 'sv-SE' }
    }
    try { return ([Globalization.CultureInfo]::GetCultureInfo($value)).Name } catch { return $value }
}
function Read-LanguageDocument {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $doc = Read-Json -Path $Path -Default $null
    if ($null -eq $doc) { return $null }
    try { $schema = [int](P $doc 'SchemaVersion' -1) } catch { return $null }
    if ($schema -ne $script:LanguageSchemaVersion) { return $null }
    $culture = [string](P $doc 'Culture' '')
    $version = [string](P $doc 'LanguageFileVersion' '')
    if ([string]::IsNullOrWhiteSpace($culture) -or [string]::IsNullOrWhiteSpace($version)) { return $null }
    return $doc
}
function Get-InstalledLanguageDocuments {
    $result = New-Object System.Collections.Generic.List[object]
    $folder = Join-Path $script:Root 'Languages'
    foreach ($file in @(Get-ChildItem -LiteralPath $folder -Filter 'mediaprep.*.json' -File -ErrorAction SilentlyContinue)) {
        $doc = Read-LanguageDocument $file.FullName
        if ($null -eq $doc) { continue }
        $culture = [string](P $doc 'Culture' '')
        if ([string]::IsNullOrWhiteSpace($culture)) { continue }
        $result.Add([pscustomobject]@{Path=$file.FullName;Culture=$culture;Document=$doc})
    }
    return @($result.ToArray())
}
function Get-SystemLanguageCode {
    $installed = @(Get-InstalledLanguageDocuments)
    $uiCulture = [Globalization.CultureInfo]::CurrentUICulture
    foreach ($entry in $installed) {
        if ([string]$entry.Culture -ieq $uiCulture.Name) { return [string]$entry.Culture }
    }
    # If an exact regional culture is not installed, use the installed variant
    # for the same language (for example en-GB -> en-US).
    foreach ($entry in $installed) {
        try {
            $entryCulture = [Globalization.CultureInfo]::GetCultureInfo([string]$entry.Culture)
            if ($entryCulture.TwoLetterISOLanguageName -ieq $uiCulture.TwoLetterISOLanguageName) { return [string]$entry.Culture }
        } catch { }
    }
    return $script:FallbackLanguageCulture
}
function Get-LanguagePath {
    param([string]$Culture)
    return (Join-Path (Join-Path $script:Root 'Languages') ("mediaprep.{0}.json" -f $Culture))
}
function Load-Language {
    param([string]$Code)
    $basePath = Get-LanguagePath $script:FallbackLanguageCulture
    $baseDoc = Read-LanguageDocument $basePath
    if ($null -eq $baseDoc) { $baseDoc = [pscustomobject]@{} }
    $script:LanguageBase = $baseDoc

    $requestedCode = Normalize-LanguagePreference $Code
    $resolvedCode = if ($requestedCode -eq 'system') { Get-SystemLanguageCode } else { $requestedCode }
    $selectedDoc = Read-LanguageDocument (Get-LanguagePath $resolvedCode)
    if ($null -eq $selectedDoc) {
        $resolvedCode = $script:FallbackLanguageCulture
        $selectedDoc = $baseDoc
    }
    if ($null -eq $selectedDoc) { $selectedDoc = [pscustomobject]@{} }
    $script:ResolvedLanguageCode = $resolvedCode
    $script:LanguageSource = if ($requestedCode -eq 'system') { 'WindowsUICulture' } else { 'Preference' }
    $script:LanguageDocument = $selectedDoc
    $script:L = $selectedDoc
    $script:LanguageFileIsCurrent = ([string](P $selectedDoc 'LanguageFileVersion' '') -eq $script:RequiredLanguageFileVersion)
}
function T {
    param(
        [string]$Key,
        [string]$Fallback,
        [object[]]$FormatArgs = @()
    )
    $baseProperty = if ($script:LanguageBase) { $script:LanguageBase.PSObject.Properties[$Key] } else { $null }
    $baseText = if ($baseProperty -and -not [string]::IsNullOrWhiteSpace([string]$baseProperty.Value)) { [string]$baseProperty.Value } else { $Fallback }
    $property = if ($script:L) { $script:L.PSObject.Properties[$Key] } else { $null }
    $text = if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) { [string]$property.Value } else { $baseText }
    $safeFormatArgs = @($FormatArgs)
    if ($safeFormatArgs.Count -gt 0) {
        try { return [string]::Format([Globalization.CultureInfo]::CurrentCulture, $text, $safeFormatArgs) } catch { }
        if ($text -ne $baseText) {
            try { return [string]::Format([Globalization.CultureInfo]::CurrentCulture, $baseText, $safeFormatArgs) } catch { }
        }
        try { return [string]::Format([Globalization.CultureInfo]::CurrentCulture, $Fallback, $safeFormatArgs) } catch { return $Fallback }
    }
    return $text
}
$script:Prefs.Language = Normalize-LanguagePreference ([string]$script:Prefs.Language)
Load-Language ([string]$script:Prefs.Language)
# Recovery UI must use the resolved language too, so initialize unfinished-session state only after T is available.
Initialize-StatisticsState

$script:ConfigPath = Join-Path (Join-Path $script:Root 'Data') 'config.json'
$script:QueueHost = Join-Path $script:AppFolder 'MediaPrep-Queue-Host.ps1'
$script:QueueDashboard = Join-Path $script:AppFolder 'MediaPrep-Queue-Dashboard.ps1'
$script:EncoderTestScript = Join-Path $script:AppFolder 'MediaPrep-Encoder-Test.ps1'
$script:EncoderCapabilitiesPath = Join-Path $script:Prefs.DataFolder 'encoder-capabilities.json'
$script:EncoderBenchmarkPath = Join-Path $script:Prefs.DataFolder 'encoder-benchmark.json'
$script:EncoderTestStatusPath = Join-Path $script:Prefs.DataFolder 'encoder-test-status.json'
$script:SettingsPath = Join-Path $script:Prefs.DataFolder 'start-installningar.json'
$script:MediaPrepUpdateResultPath = Join-Path $script:Prefs.DataFolder 'mediaprep-update-result.json'
$script:JobPath = Join-Path $script:Prefs.DataFolder 'senaste-kojobb.json'
$script:StopRequest = Join-Path $script:Prefs.DataFolder 'queue-stop.request'
$script:Settings = Merge-Defaults -Loaded (Read-Json -Path $script:SettingsPath -Default $null) -Defaults (Default-Settings)
if([bool](P $script:Settings 'VerboseLogging' $false)){Enable-VerboseStartupTrace}
Write-StartupTrace 'PreferencesAndSettingsLoaded'


function Show-MediaPrepUpdateResult {
    if(-not(Test-Path -LiteralPath $script:MediaPrepUpdateResultPath -PathType Leaf)){return}
    $result=Read-Json -Path $script:MediaPrepUpdateResultPath -Default $null
    if($null-eq$result){Remove-Item -LiteralPath $script:MediaPrepUpdateResultPath -Force -ErrorAction SilentlyContinue;return}
    $success=[bool](P $result 'Success' $false)
    $target=[string](P $result 'TargetVersion' '')
    $message=[string](P $result 'Message' '')
    $logPath=[string](P $result 'LogPath' '')
    if($success){
        $text=T 'MediaPrepUpdateCompleted' 'MediaPrep {0} was installed successfully.' @($target)
        if(-not[string]::IsNullOrWhiteSpace($message)){$text+="`r`n`r`n"+$message}
        if(-not[string]::IsNullOrWhiteSpace($logPath)){$text+="`r`n`r`n"+(T 'UpdateLogPath' 'Log: {0}' @($logPath))}
        [Windows.Forms.MessageBox]::Show($text,(T 'MediaPrepUpdateTitle' 'MediaPrep update'),[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null
    }else{
        $text=T 'MediaPrepUpdateFailed' 'MediaPrep update failed. The previous program files were restored when possible.'
        if(-not[string]::IsNullOrWhiteSpace($message)){$text+="`r`n`r`n"+$message}
        if(-not[string]::IsNullOrWhiteSpace($logPath)){$text+="`r`n`r`n"+(T 'UpdateLogPath' 'Log: {0}' @($logPath))}
        [Windows.Forms.MessageBox]::Show($text,(T 'MediaPrepUpdateTitle' 'MediaPrep update'),[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null
    }
    Remove-Item -LiteralPath $script:MediaPrepUpdateResultPath -Force -ErrorAction SilentlyContinue
}

function Get-ExecutableVersionShort {
    param([string]$Exe,[ValidateSet('FFmpeg','MKVToolNix')][string]$Tool)
    if([string]::IsNullOrWhiteSpace($Exe) -or -not(Test-Path -LiteralPath $Exe -PathType Leaf)){return '-'}
    try{
        $line=if($Tool -eq 'MKVToolNix'){(& $Exe --version 2>&1 | Select-Object -First 1)-as[string]}else{(& $Exe -version 2>&1 | Select-Object -First 1)-as[string]}
        if([string]::IsNullOrWhiteSpace($line)){return '-'}
        if($Tool -eq 'MKVToolNix'){
            $m=[regex]::Match($line,'mkvmerge\s+v([^\s]+)')
            if($m.Success){return $m.Groups[1].Value}
        }else{
            $m=[regex]::Match($line,'ffmpeg\s+version\s+([^\s]+)')
            if($m.Success){
                $v=$m.Groups[1].Value
                $v=$v -replace '[-_](?:full|essentials)_build.*$',''
                return $v
            }
        }
        return $line
    }catch{return '-'}
}
function Get-MediaPrepProcessRows {
    # Show the Start Center itself plus all currently living descendants.
    # This is diagnostic only; no processes are killed from this function.
    try{
        $all=@(Get-CimInstance Win32_Process -OperationTimeoutSec 2 -ErrorAction Stop | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine)
        $wanted=@{}
        $selfKey=[string]$PID
        $wanted[$selfKey]=$true
        $changed=$true
        while($changed){
            $changed=$false
            foreach($proc in $all){
                $pidText=[string][int]$proc.ProcessId
                $parentText=[string][int]$proc.ParentProcessId
                if(-not$wanted.ContainsKey($pidText) -and $wanted.ContainsKey($parentText)){
                    $wanted[$pidText]=$true
                    $changed=$true
                }
            }
        }
        # Also pick up a surviving worker from a previous Start Center instance.
        # PowerShell workers contain the MediaPrep root in their command line, while
        # ffmpeg/ffprobe/mkvmerge executables live below the MediaPrep Tools folder.
        $rootText=[string]$script:Root
        foreach($proc in $all){
            $pidText=[string][int]$proc.ProcessId
            if($wanted.ContainsKey($pidText)){continue}
            $name=[string]$proc.Name
            if($name -notmatch '^(powershell|pwsh|ffmpeg|ffprobe|mkvmerge)\.exe$'){continue}
            $cmd=[string]$proc.CommandLine
            $exe=[string]$proc.ExecutablePath
            $belongs=($cmd.IndexOf($rootText,[StringComparison]::OrdinalIgnoreCase)-ge0 -or $exe.IndexOf($rootText,[StringComparison]::OrdinalIgnoreCase)-ge0)
            if($belongs){$wanted[$pidText]=$true}
        }
        $rows=@()
        foreach($proc in $all){
            if($wanted.ContainsKey([string][int]$proc.ProcessId)){
                $rows += [pscustomobject]@{Name=[string]$proc.Name;PID=[int]$proc.ProcessId}
            }
        }
        return @($rows | Sort-Object PID)
    }catch{
        return @([pscustomobject]@{Name='powershell.exe';PID=[int]$PID})
    }
}
function Test-MediaPrepProcessingActive {
    # Update safety gate: do not replace program files while a queue/media worker is active.
    if($script:QueueRunActive){return $true}
    try{if($script:QueueProcess -and -not $script:QueueProcess.HasExited){return $true}}catch{return $true}

    # The queue host publishes its PID while it owns the optional detail console.
    try{
        $consoleStatePath=Join-Path $script:Prefs.DataFolder 'queue-console-window.json'
        if(Test-Path -LiteralPath $consoleStatePath -PathType Leaf){
            $consoleState=Read-Json -Path $consoleStatePath -Default $null
            if($null-ne$consoleState){
                $queuePid=[int](P $consoleState 'PID' 0)
                if($queuePid-gt0 -and $null-ne(Get-Process -Id $queuePid -ErrorAction SilentlyContinue)){return $true}
            }
        }
    }catch{}

    # Also detect workers that survived a previous Start Center instance, including
    # elevated Queue.ps1/MediaPrep.ps1 processes and MediaPrep-owned media tools.
    try{
        $rootText=[string]$script:Root
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
    }catch{
        # If process inspection is unavailable, fall back to the queue run marker.
        try{
            $runState=Read-Json -Path (Join-Path $script:Prefs.DataFolder 'queue-run-current.json') -Default $null
            if($null-ne$runState -and [string](P $runState 'Status' '') -eq 'Running'){return $true}
        }catch{}
    }
    return $false
}

$script:LastProcessBannerRefresh=[datetime]::MinValue
$script:BannerToolVersionsInitialized=$false
function Refresh-BannerRuntimeInfo {
    param([switch]$RefreshTools)
    if($null-ne$toolVersionLabel -and ($RefreshTools -or -not$script:BannerToolVersionsInitialized)){
        Start-StartupTiming 'BannerToolVersions'
        try{
            $ff=Get-ExecutableVersionShort -Exe ([string]$script:Prefs.FFmpegPath) -Tool FFmpeg
            $mk=Get-ExecutableVersionShort -Exe ([string]$script:Prefs.MkvmergePath) -Tool MKVToolNix
            $toolVersionLabel.Text=(T 'BannerToolVersions' 'FFmpeg {0}  |  MKVToolNix {1}' @($ff,$mk))
            $script:BannerToolVersionsInitialized=$true
        }finally{Stop-StartupTiming 'BannerToolVersions'}
    }
    if($null-ne$processLabel){
        if(((Get-Date)-$script:LastProcessBannerRefresh).TotalSeconds -lt 5){return}
        $script:LastProcessBannerRefresh=Get-Date
        Start-StartupTiming 'BannerProcessScan'
        try{$rows=@(Get-MediaPrepProcessRows)}finally{Stop-StartupTiming 'BannerProcessScan'}
        $parts=New-Object System.Collections.Generic.List[string]
        foreach($row in $rows){$parts.Add(('{0} [{1}]' -f $row.Name,$row.PID))}
        if($parts.Count -eq 0){$parts.Add('-')}
        $lines=New-Object System.Collections.Generic.List[string]
        $lines.Add((T 'BannerProcessesHeader' 'Processes:'))
        for($i=0;$i-lt$parts.Count;$i+=2){
            $left=[string]$parts[$i]
            $right=if(($i+1)-lt$parts.Count){[string]$parts[$i+1]}else{''}
            $lines.Add(('{0,-25} {1}' -f $left,$right))
        }
        $processLabel.Text=($lines -join [Environment]::NewLine)
    }
}


function Write-GuiErrorLog {
    param(
        [Parameter(Mandatory=$true)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$Context = 'GUI event'
    )
    try {
        $folder = [string]$script:Prefs.LogFolder
        if ([string]::IsNullOrWhiteSpace($folder)) { $folder = Join-Path $script:Root 'Loggar' }
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }
        $path = Join-Path $folder ('MediaPrep-GUI-error_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
        $lines = @(
            'MediaPrep Start Center GUI error',
            ('Time: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
            ('Context: {0}' -f $Context),
            ('PowerShell: {0}' -f $PSVersionTable.PSVersion),
            ('Message: {0}' -f $ErrorRecord.Exception.Message),
            ('Type: {0}' -f $ErrorRecord.Exception.GetType().FullName),
            ('Category: {0}' -f $ErrorRecord.CategoryInfo),
            ('FullyQualifiedErrorId: {0}' -f $ErrorRecord.FullyQualifiedErrorId),
            ('Position: {0}' -f $ErrorRecord.InvocationInfo.PositionMessage),
            ('Stack: {0}' -f $ErrorRecord.ScriptStackTrace)
        )
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        return $path
    }
    catch { return '' }
}
function Show-GuiError {
    param(
        [Parameter(Mandatory=$true)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$Context = 'GUI event'
    )
    $logPath = Write-GuiErrorLog -ErrorRecord $ErrorRecord -Context $Context
    $message = $ErrorRecord.Exception.Message
    if (-not [string]::IsNullOrWhiteSpace($logPath)) { $message += "`r`n`r`nLog: $logPath" }
    [Windows.Forms.MessageBox]::Show($message,'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}

function New-Label {
    param([string]$Text,[int]$X,[int]$Y,[int]$Width,[int]$Height,[float]$Size=9,[bool]$Bold=$false)
    $label=New-Object Windows.Forms.Label
    $label.Text=$Text
    $label.Location=New-Object Drawing.Point($X,$Y)
    $label.Size=New-Object Drawing.Size($Width,$Height)
    $style=if($Bold){[Drawing.FontStyle]::Bold}else{[Drawing.FontStyle]::Regular}
    $label.Font=New-Object Drawing.Font('Segoe UI',$Size,$style)
    return $label
}
function New-Check {
    param([string]$Text,[int]$X,[int]$Y,[int]$Width)
    $check=New-Object Windows.Forms.CheckBox
    $check.Text=$Text
    $check.Location=New-Object Drawing.Point($X,$Y)
    $check.Size=New-Object Drawing.Size($Width,30)
    $check.Font=New-Object Drawing.Font('Segoe UI',10)
    return $check
}
function Register-ChoiceTextState {
    param([Windows.Forms.Control[]]$Controls)
    foreach($control in @($Controls)){
        if($null -eq $control){continue}
        $updateColor={
            if($this.Checked){$this.ForeColor=$script:ThemePalette.Text}
            else{$this.ForeColor=$script:ThemePalette.Muted}
        }
        $control.Add_CheckedChanged($updateColor)
        if($control.Checked){$control.ForeColor=$script:ThemePalette.Text}else{$control.ForeColor=$script:ThemePalette.Muted}
    }
}
function Select-Folder {
    param([string]$Initial)
    $dialog=New-Object Windows.Forms.OpenFileDialog
    $dialog.CheckFileExists=$false
    $dialog.CheckPathExists=$true
    $dialog.ValidateNames=$false
    $dialog.FileName=(T 'SelectFolder' 'Select folder...')
    if($Initial -and (Test-Path -LiteralPath $Initial -PathType Container)){$dialog.InitialDirectory=$Initial}
    if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){return (Split-Path -Parent $dialog.FileName)}
    return $null
}
function Select-Exe {
    param([string]$Initial,[string]$Name)
    $dialog=New-Object Windows.Forms.OpenFileDialog
    $dialog.Filter=("{0}|{0}|Executable files (*.exe)|*.exe|All files (*.*)|*.*" -f $Name)
    $dialog.CheckFileExists=$true
    $dialog.CheckPathExists=$true

    $initialPath=[string]$Initial
    $initialDirectory=$null
    $initialFileName=[string]$Name
    if(-not [string]::IsNullOrWhiteSpace($initialPath)){
        try{
            $initialFileName=Split-Path -Leaf $initialPath
            $candidate=Split-Path -Parent $initialPath
            while(-not [string]::IsNullOrWhiteSpace($candidate) -and -not (Test-Path -LiteralPath $candidate -PathType Container)){
                $parent=Split-Path -Parent $candidate
                if($parent -eq $candidate){break}
                $candidate=$parent
            }
            if(-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Container)){
                $initialDirectory=$candidate
            }
        }catch{}
    }
    if($initialDirectory){$dialog.InitialDirectory=$initialDirectory}
    if($initialFileName){$dialog.FileName=$initialFileName}
    if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){return $dialog.FileName}
    return $null
}
function Get-ListItems {
    param([Windows.Forms.ListBox]$List)
    $values=New-Object Collections.Generic.List[string]
    foreach($item in $List.Items){$values.Add([string]$item)}
    return $values.ToArray()
}
function Apply-Prefs-ToConfig {
    $cfg=Read-Json $script:ConfigPath ([pscustomobject]@{})
    $map=[ordered]@{Version='0.11.53';Language=[string]$script:Prefs.Language;SourceFolder=[string]$script:Prefs.SourceFolder;OutputFolder=[string]$script:Prefs.OutputFolder;DataFolder=[string]$script:Prefs.DataFolder;LogFolder=[string]$script:Prefs.LogFolder;ReportFolder=[string]$script:Prefs.ReportFolder;TempFolder=[string]$script:Prefs.TempFolder;FFmpegPath=[string]$script:Prefs.FFmpegPath;FFprobePath=[string]$script:Prefs.FFprobePath;MkvmergePath=[string]$script:Prefs.MkvmergePath;TVTargetMBPerMinute=[double]$script:Prefs.TVTargetMBPerMinute;MovieTargetMBPerMinute=[double]$script:Prefs.MovieTargetMBPerMinute;EncodeThresholdMultiplier=[double]$script:Prefs.EncodeThresholdMultiplier;MinimumSavingPercent=[double]$script:Prefs.MinimumSavingPercent;SelectedEncoderId=[string]$script:Prefs.SelectedEncoderId}
    foreach($name in $map.Keys){$cfg|Add-Member -NotePropertyName $name -NotePropertyValue $map[$name] -Force}
    Write-Json $script:ConfigPath $cfg
}


function Convert-HexColor {
    param([string]$Hex,[Drawing.Color]$Fallback)
    try{
        $value=$Hex.Trim()
        if(-not $value.StartsWith('#')){$value='#'+$value}
        if($value -notmatch '^#[0-9A-Fa-f]{6}$'){return $Fallback}
        return [Drawing.ColorTranslator]::FromHtml($value)
    }catch{return $Fallback}
}
function Get-ContrastColor {
    param([Drawing.Color]$Color)
    $lum=(0.299*$Color.R)+(0.587*$Color.G)+(0.114*$Color.B)
    if($lum -gt 155){return [Drawing.Color]::FromArgb(25,25,25)}
    return [Drawing.Color]::White
}
function Get-ThemePalette {
    param([string]$Theme)
    $monthly=@{
        1=@('#02b6eb','#6ed0f7','#9feeff'); 2=@('#0187d0','#61b4d5','#9ee3ff'); 3=@('#1f4da2','#648edb','#9ec0ff')
        4=@('#00988b','#6ad5d2','#96fffc'); 5=@('#007d45','#62ce9e','#9ffad2'); 6=@('#1bb313','#61d35b','#97fc92')
        7=@('#ffd82b','#fff34f','#fff67f'); 8=@('#f15a25','#ee963b','#ffba72'); 9=@('#d54d07','#ea8856','#ffaf86')
        10=@('#ec1d25','#f27075','#ffa1a5'); 11=@('#d12086','#d961a6','#f694cc'); 12=@('#25227b','#6360ba','#9b98ea')
    }
    $name=if([string]::IsNullOrWhiteSpace($Theme)){'Light'}else{$Theme}
    if($name -eq 'Dark'){
        $banner=[Drawing.Color]::FromArgb(19,39,61);$panel=[Drawing.Color]::FromArgb(45,52,62);$background=[Drawing.Color]::FromArgb(30,34,40)
        $text=[Drawing.Color]::FromArgb(235,238,242);$muted=[Drawing.Color]::FromArgb(145,152,162);$input=[Drawing.Color]::FromArgb(38,44,52)
    }elseif($name -eq 'Monthly'){
        $colors=$monthly[(Get-Date).Month]
        $banner=Convert-HexColor $colors[0] ([Drawing.Color]::FromArgb(22,52,86))
        $panel=Convert-HexColor $colors[1] ([Drawing.Color]::FromArgb(220,232,244))
        $background=Convert-HexColor $colors[2] ([Drawing.Color]::FromArgb(244,247,250))
        $text=[Drawing.Color]::FromArgb(25,25,25);$muted=[Drawing.Color]::FromArgb(95,95,95);$input=[Drawing.Color]::White
    }elseif($name -eq 'Custom'){
        $banner=Convert-HexColor ([string]$script:Prefs.CustomThemeBanner) ([Drawing.Color]::FromArgb(22,52,86))
        $panel=Convert-HexColor ([string]$script:Prefs.CustomThemePanel) ([Drawing.Color]::FromArgb(220,232,244))
        $background=Convert-HexColor ([string]$script:Prefs.CustomThemeBackground) ([Drawing.Color]::FromArgb(244,247,250))
        $text=[Drawing.Color]::FromArgb(25,25,25);$muted=[Drawing.Color]::FromArgb(105,105,105);$input=[Drawing.Color]::White
    }else{
        $banner=[Drawing.Color]::FromArgb(22,52,86);$panel=[Drawing.Color]::FromArgb(230,238,246);$background=[Drawing.Color]::FromArgb(244,247,250)
        $text=[Drawing.Color]::FromArgb(25,25,25);$muted=[Drawing.Color]::FromArgb(145,145,145);$input=[Drawing.Color]::White
    }
    return [pscustomobject]@{Name=$name;Banner=$banner;Panel=$panel;Background=$background;Text=$text;Muted=$muted;Input=$input;BannerText=(Get-ContrastColor $banner)}
}
$script:ThemePalette=Get-ThemePalette ([string]$script:Prefs.Theme)
function Apply-ControlTheme {
    param([Windows.Forms.Control]$Control)
    if($null-eq$Control){return}
    $p=$script:ThemePalette
    if($Control -is [Windows.Forms.Form] -or $Control -is [Windows.Forms.TabPage]){$Control.BackColor=$p.Background;$Control.ForeColor=$p.Text}
    elseif($Control -is [Windows.Forms.GroupBox] -or $Control -is [Windows.Forms.Panel] -or $Control -is [Windows.Forms.FlowLayoutPanel]){$Control.BackColor=$p.Background;$Control.ForeColor=$p.Text}
    elseif($Control -is [Windows.Forms.TextBox] -or $Control -is [Windows.Forms.RichTextBox] -or $Control -is [Windows.Forms.ListBox] -or $Control -is [Windows.Forms.ComboBox] -or $Control -is [Windows.Forms.NumericUpDown]){$Control.BackColor=$p.Input;$Control.ForeColor=$p.Text}
    elseif($Control -is [Windows.Forms.DataGridView]){
        $Control.BackgroundColor=$p.Background;$Control.GridColor=$p.Panel;$Control.DefaultCellStyle.BackColor=$p.Input;$Control.DefaultCellStyle.ForeColor=$p.Text;$Control.DefaultCellStyle.SelectionBackColor=$p.Banner;$Control.DefaultCellStyle.SelectionForeColor=$p.BannerText;$Control.ColumnHeadersDefaultCellStyle.BackColor=$p.Panel;$Control.ColumnHeadersDefaultCellStyle.ForeColor=$p.Text;$Control.EnableHeadersVisualStyles=$false
    }elseif($Control -is [Windows.Forms.ListView]){$Control.BackColor=$p.Input;$Control.ForeColor=$p.Text}
    elseif($Control -is [Windows.Forms.Button]){$Control.UseVisualStyleBackColor=$false;$Control.BackColor=$p.Panel;$Control.ForeColor=$p.Text}
    elseif($Control -is [Windows.Forms.CheckBox] -or $Control -is [Windows.Forms.RadioButton]){
        if($Control.Checked){$Control.ForeColor=$p.Text}else{$Control.ForeColor=$p.Muted};$Control.BackColor=$p.Background
    }else{$Control.ForeColor=$p.Text}
    foreach($child in @($Control.Controls)){Apply-ControlTheme $child}
}


# CPU/GPU encoder verification. MediaPrep deliberately does not trust model names alone:
# the installed FFmpeg build and the actual driver/hardware combination must pass a real encode test.
$script:HardwareCacheVersion=1
$script:SessionHardwareSnapshot=$null
$script:SessionEncoderSignature=$null
$script:SessionFFmpegVersionLine=$null

function Set-ObjectProperty {
    param([object]$Object,[string]$Name,[object]$Value)
    if($null-eq$Object){return}
    $property=$Object.PSObject.Properties[$Name]
    if($property){$property.Value=$Value}else{$Object|Add-Member -NotePropertyName $Name -NotePropertyValue $Value}
}
function Clear-EncoderSessionSignature {
    $script:SessionEncoderSignature=$null
    $script:SessionFFmpegVersionLine=$null
}
function Test-SavedHardwareSnapshot {
    param([object]$Snapshot)
    if($null-eq$Snapshot){return $false}
    if([int](P $Snapshot 'CacheVersion' 0) -ne $script:HardwareCacheVersion){return $false}
    $computer=[string](P $Snapshot 'ComputerName' '')
    if([string]::IsNullOrWhiteSpace($computer)){return $false}
    if(-not[string]::Equals($computer,[string]$env:COMPUTERNAME,[StringComparison]::OrdinalIgnoreCase)){return $false}
    return ($null-ne(P $Snapshot 'CPU' $null))
}
function New-HardwareSnapshotFromSystem {
    $cpu=Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1 Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed
    $gpus=@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object Name,AdapterCompatibility,DriverVersion,PNPDeviceID,DeviceID,AdapterRAM | Sort-Object Name,PNPDeviceID)
    $cpuData=if($cpu){
        [pscustomobject][ordered]@{
            Name=[string]$cpu.Name
            Manufacturer=[string]$cpu.Manufacturer
            NumberOfCores=[int](P $cpu 'NumberOfCores' 0)
            NumberOfLogicalProcessors=[int](P $cpu 'NumberOfLogicalProcessors' 0)
            MaxClockSpeed=[int](P $cpu 'MaxClockSpeed' 0)
        }
    }else{
        [pscustomobject][ordered]@{Name='CPU unknown';Manufacturer='';NumberOfCores=0;NumberOfLogicalProcessors=0;MaxClockSpeed=0}
    }
    $gpuData=@($gpus | ForEach-Object {
        [pscustomobject][ordered]@{
            Name=[string]$_.Name
            Vendor=[string]$_.AdapterCompatibility
            DriverVersion=[string]$_.DriverVersion
            PNPDeviceID=[string]$_.PNPDeviceID
            DeviceID=[string]$_.DeviceID
            AdapterRAM=if($null-ne$_.AdapterRAM){[int64]$_.AdapterRAM}else{$null}
        }
    })
    return [pscustomobject][ordered]@{
        CacheVersion=$script:HardwareCacheVersion
        ComputerName=[string]$env:COMPUTERNAME
        LastCheckedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        LastCheckedUtc=(Get-Date).ToUniversalTime().ToString('o')
        CPU=$cpuData
        GPUs=$gpuData
    }
}
function Save-HardwareSnapshotToPreferences {
    param([object]$Snapshot)
    if($null-eq$Snapshot){return}
    Set-ObjectProperty -Object $script:Prefs -Name 'Hardware' -Value $Snapshot
    Write-Json $script:PreferencesPath $script:Prefs
}
function Convert-EncoderDocumentHardwareToSnapshot {
    param([object]$Document)
    if($null-eq$Document){return $null}
    $hardware=P $Document 'Hardware' $null
    if($null-eq$hardware){return $null}
    $cpu=P $hardware 'CPU' $null
    $gpus=@(P $hardware 'GPUs' @())
    return [pscustomobject][ordered]@{
        CacheVersion=$script:HardwareCacheVersion
        ComputerName=[string]$env:COMPUTERNAME
        LastCheckedLocal=[string](P $Document 'CheckedLocal' (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
        LastCheckedUtc=[string](P $Document 'CheckedUtc' (Get-Date).ToUniversalTime().ToString('o'))
        CPU=$cpu
        GPUs=$gpus
    }
}
function Set-SessionHardwareFromEncoderDocument {
    param([object]$Document,[switch]$Persist)
    $snapshot=Convert-EncoderDocumentHardwareToSnapshot $Document
    if($null-eq$snapshot){return $false}
    $script:SessionHardwareSnapshot=$snapshot
    $script:SessionEncoderSignature=[string](P $Document 'Signature' '')
    $script:SessionFFmpegVersionLine=[string](P $Document 'FFmpegVersion' '')
    if($Persist){Save-HardwareSnapshotToPreferences $snapshot}
    return $true
}
function Get-HardwareSnapshot {
    param([switch]$ForceRefresh,[switch]$Persist)
    if(-not$ForceRefresh -and $null-ne$script:SessionHardwareSnapshot){
        Write-VerboseStartupTrace 'HardwareSnapshotSource' 'Session memory'
        return $script:SessionHardwareSnapshot
    }
    if(-not$ForceRefresh){
        $saved=P $script:Prefs 'Hardware' $null
        if(Test-SavedHardwareSnapshot $saved){
            $script:SessionHardwareSnapshot=$saved
            Write-VerboseStartupTrace 'HardwareSnapshotSource' ('Preferences; LastChecked='+[string](P $saved 'LastCheckedLocal' ''))
            return $saved
        }
    }
    Write-VerboseStartupTrace 'HardwareSnapshotSource' $(if($ForceRefresh){'Windows CIM; forced refresh'}else{'Windows CIM; preferences missing or for another computer'})
    $snapshot=New-HardwareSnapshotFromSystem
    $script:SessionHardwareSnapshot=$snapshot
    Clear-EncoderSessionSignature
    # A missing/mismatched cache is repaired automatically. Explicit refreshes are persisted too.
    if($Persist -or -not(Test-SavedHardwareSnapshot (P $script:Prefs 'Hardware' $null))){Save-HardwareSnapshotToPreferences $snapshot}
    return $snapshot
}
function Get-FFmpegVersionLine {
    param([switch]$ForceRefresh)
    if(-not$ForceRefresh -and -not[string]::IsNullOrWhiteSpace([string]$script:SessionFFmpegVersionLine)){return [string]$script:SessionFFmpegVersionLine}
    $line=''
    try{
        if(Test-Path -LiteralPath ([string]$script:Prefs.FFmpegPath) -PathType Leaf){$line=[string](& ([string]$script:Prefs.FFmpegPath) -version 2>&1 | Select-Object -First 1)}
    }catch{$line=''}
    $script:SessionFFmpegVersionLine=$line
    return $line
}
function New-EncoderSignatureFromHardwareSnapshot {
    param([string]$FFmpegVersion,[object]$Snapshot)
    if($null-eq$Snapshot){return ''}
    $cpu=P $Snapshot 'CPU' $null
    $cpuName=if($cpu){[string](P $cpu 'Name' 'CPU unknown')}else{'CPU unknown'}
    $parts=New-Object System.Collections.Generic.List[string]
    foreach($gpu in @((P $Snapshot 'GPUs' @()) | Sort-Object Name,PNPDeviceID)){
        $parts.Add(('{0}|{1}|{2}' -f [string](P $gpu 'Name' ''),[string](P $gpu 'DriverVersion' ''),[string](P $gpu 'PNPDeviceID' '')))
    }
    return ('FFMPEG={0};CPU={1};GPU={2}' -f $FFmpegVersion,$cpuName,($parts -join ';'))
}
function Get-CurrentEncoderSignature {
    param([switch]$ForceRefresh)
    if(-not$ForceRefresh -and -not[string]::IsNullOrWhiteSpace([string]$script:SessionEncoderSignature)){return [string]$script:SessionEncoderSignature}
    $hardware=Get-HardwareSnapshot -ForceRefresh:$ForceRefresh -Persist:$ForceRefresh
    $ffmpegVersion=Get-FFmpegVersionLine -ForceRefresh:$ForceRefresh
    $signature=New-EncoderSignatureFromHardwareSnapshot -FFmpegVersion $ffmpegVersion -Snapshot $hardware
    $script:SessionEncoderSignature=$signature
    return $signature
}
function Get-EncoderCapabilitiesDocument {
    return (Read-Json -Path $script:EncoderCapabilitiesPath -Default $null)
}
function Test-EncoderCapabilitiesCurrent {
    param([object]$Document,[switch]$ForceRefresh)
    if($null-eq$Document){return $false}
    $saved=[string](P $Document 'Signature' '')
    if([string]::IsNullOrWhiteSpace($saved)){return $false}
    $current=Get-CurrentEncoderSignature -ForceRefresh:$ForceRefresh
    return (-not[string]::IsNullOrWhiteSpace($current) -and [string]::Equals($saved,$current,[StringComparison]::Ordinal))
}
function Get-EncoderById {
    param([object]$Document,[string]$Id)
    if($null-eq$Document -or [string]::IsNullOrWhiteSpace($Id)){return $null}
    foreach($encoder in @(P $Document 'Encoders' @())){if([string]$encoder.Id -eq $Id){return $encoder}}
    return $null
}
function Get-EncoderDisplayText {
    param([object]$Encoder,[switch]$UnverifiedCpu)
    if($UnverifiedCpu){
        $hardware=Get-HardwareSnapshot
        $cpu=P $hardware 'CPU' $null
        $name=if($cpu){[string](P $cpu 'Name' 'CPU')}else{'CPU'}
        return ($name+' — HEVC CPU — '+(T 'EncoderNotChecked' 'Not checked'))
    }
    if($null-eq$Encoder){return ''}
    $suffix=switch([string]$Encoder.Backend){'NVENC'{'HEVC NVENC'};'QSV'{'HEVC QSV'};'AMF'{'HEVC AMF'};default{'HEVC CPU'}}
    return ('{0} — {1}' -f [string]$Encoder.HardwareName,$suffix)
}

function Get-StableEncoderIdSuffix {
    param([string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        $bytes=[Text.Encoding]::UTF8.GetBytes([string]$Text)
        $hash=$sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0,10)
    }finally{$sha.Dispose()}
}
function Get-DetectedEncoderCandidates {
    # Discovery uses the latest saved hardware snapshot during normal startup.
    # A real Check CPU/GPU, Refresh hardware, or queue start refreshes the snapshot from Windows.
    $items=New-Object System.Collections.Generic.List[object]
    $hardware=Get-HardwareSnapshot
    $cpu=P $hardware 'CPU' $null
    $cpuName=if($cpu){[string](P $cpu 'Name' 'CPU')}else{'CPU'}
    $items.Add([pscustomobject]@{
        Id='cpu-libx265';HardwareName=$cpuName;Backend='CPU';Encoder='libx265';
        DriverVersion='';Verified=$false;DetectedOnly=$true
    })

    $gpus=@(P $hardware 'GPUs' @())
    foreach($gpu in @($gpus | Where-Object { [string](P $_ 'Name' '') -match 'NVIDIA' })){
        $suffix=Get-StableEncoderIdSuffix ([string](P $gpu 'PNPDeviceID' '')+[string](P $gpu 'Name' ''))
        $items.Add([pscustomobject]@{
            Id=('nvidia-'+$suffix+'-hevc_nvenc');HardwareName=[string](P $gpu 'Name' '');Backend='NVENC';
            Encoder='hevc_nvenc';DriverVersion=[string](P $gpu 'DriverVersion' '');Verified=$false;DetectedOnly=$true
        })
    }

    $intelGpus=@($gpus | Where-Object { [string](P $_ 'Name' '') -match 'Intel' })
    if($intelGpus.Count-gt0){
        $preferredIntel=@($intelGpus | Sort-Object @{Expression={if([string](P $_ 'Name' '') -match 'Arc'){0}else{1}}},@{Expression={[string](P $_ 'Name' '')}} | Select-Object -First 1)[0]
        $suffix=Get-StableEncoderIdSuffix ([string](P $preferredIntel 'PNPDeviceID' '')+[string](P $preferredIntel 'Name' ''))
        $items.Add([pscustomobject]@{
            Id=('intel-'+$suffix+'-hevc_qsv');HardwareName=[string](P $preferredIntel 'Name' '');Backend='QSV';
            Encoder='hevc_qsv';DriverVersion=[string](P $preferredIntel 'DriverVersion' '');Verified=$false;DetectedOnly=$true
        })
    }

    $amdGpus=@($gpus | Where-Object { [string](P $_ 'Name' '') -match 'AMD|Radeon' })
    if($amdGpus.Count-gt0){
        $preferredAmd=@($amdGpus | Select-Object -First 1)[0]
        $suffix=Get-StableEncoderIdSuffix ([string](P $preferredAmd 'PNPDeviceID' '')+[string](P $preferredAmd 'Name' ''))
        $items.Add([pscustomobject]@{
            Id=('amd-'+$suffix+'-hevc_amf');HardwareName=[string](P $preferredAmd 'Name' '');Backend='AMF';
            Encoder='hevc_amf';DriverVersion=[string](P $preferredAmd 'DriverVersion' '');Verified=$false;DetectedOnly=$true
        })
    }
    return $items.ToArray()
}
function Get-DetectedEncoderDisplayText {
    param([object]$Encoder)
    $suffix=switch([string]$Encoder.Backend){'NVENC'{'HEVC NVENC'};'QSV'{'HEVC QSV'};'AMF'{'HEVC AMF'};default{'HEVC CPU'}}
    return ('{0} — {1} — {2}' -f [string]$Encoder.HardwareName,$suffix,(T 'EncoderNotChecked' 'Not checked'))
}
function Get-SelectedEncoderObject {
    $doc=Get-EncoderCapabilitiesDocument
    if(-not(Test-EncoderCapabilitiesCurrent $doc)){return $null}
    $encoder=Get-EncoderById -Document $doc -Id ([string]$script:Prefs.SelectedEncoderId)
    if($encoder -and [bool](P $encoder 'Verified' $false)){return $encoder}
    return $null
}
function Get-EncoderBannerText {
    $encoder=Get-SelectedEncoderObject
    if($null-eq$encoder){return (T 'EncoderBannerUnchecked' 'CPU HEVC • check required')}
    switch([string]$encoder.Backend){
        'NVENC' { return 'NVIDIA HEVC NVENC' }
        'QSV'   { return 'Intel HEVC QSV' }
        'AMF'   { return 'AMD HEVC AMF' }
        default { return 'CPU HEVC' }
    }
}
function Update-EncoderBanner {
    if($null-ne$subtitle){$subtitle.Text=((T 'AppSubtitleBase' 'Queue • UNC import • Muxing')+' • '+(Get-EncoderBannerText))}
}
function Format-OptionalNumber {
    param([object]$Value,[string]$Format='0.0',[string]$Suffix='')
    if($null-eq$Value){return (T 'NotAvailable' 'Not available')}
    try{return (([double]$Value).ToString($Format,[Globalization.CultureInfo]::CurrentCulture)+$Suffix)}catch{return (T 'NotAvailable' 'Not available')}
}
function Get-HardwareSummaryText {
    $lines=New-Object System.Collections.Generic.List[string]
    $hardware=Get-HardwareSnapshot
    $cpu=P $hardware 'CPU' $null
    if($cpu){
        $lines.Add(('CPU: {0}' -f [string](P $cpu 'Name' 'CPU')))
        $lines.Add(('     {0} {1} / {2} {3}' -f [int](P $cpu 'NumberOfCores' 0),(T 'PhysicalCores' 'cores'),[int](P $cpu 'NumberOfLogicalProcessors' 0),(T 'LogicalProcessors' 'logical processors')))
    }
    $gpus=@(P $hardware 'GPUs' @())
    if($gpus.Count-eq0){$lines.Add('GPU: '+(T 'NoneDetected' 'None detected'))}
    foreach($g in $gpus){
        $ram=''
        try{$adapterRam=P $g 'AdapterRAM' $null;if($null-ne$adapterRam -and [int64]$adapterRam-gt0){$ram=' | '+(Format-QueueBytes ([int64]$adapterRam))}}catch{}
        $lines.Add(('GPU: {0} | driver {1}{2}' -f [string](P $g 'Name' ''),[string](P $g 'DriverVersion' ''),$ram))
    }
    return ($lines -join [Environment]::NewLine)
}
function Get-FriendlyEncoderFailureText {
    param([object]$Encoder)
    if($null-eq$Encoder){return ''}
    $reason=[string](P $Encoder 'Reason' '')
    if([string]::IsNullOrWhiteSpace($reason)){return ''}
    $backend=[string](P $Encoder 'Backend' '')
    $hardware=[string](P $Encoder 'HardwareName' '')
    if($backend -eq 'NVENC'){
        $requiredDriver=''
        if($reason -match '(?i)minimum required Nvidia driver for nvenc is\s+([0-9.]+)\s+or newer'){$requiredDriver=$Matches[1]}
        $requiredApi='';$foundApi=''
        if($reason -match '(?i)required nvenc API version\.\s*Required:\s*([0-9.]+)\s*Found:\s*([0-9.]+)'){$requiredApi=$Matches[1];$foundApi=$Matches[2]}
        if($requiredDriver -or $requiredApi){
            $extra=''
            if($requiredDriver){$extra+="`r`nRequired NVIDIA driver: $requiredDriver or newer."}
            if($requiredApi){$extra+="`r`nRequired NVENC API: $requiredApi. Available: $foundApi."}
            return (T 'NvencDriverTooOld' ("NVIDIA NVENC could not be activated for {0}. The installed NVIDIA graphics driver is too old for the installed FFmpeg version.{1}`r`n`r`nUpdate the NVIDIA graphics driver and run Check CPU/GPU again. Other verified encoders can still be used.") @($hardware,$extra))
        }
        if($reason -match '(?i)cannot load.*nvenc|no nvenc capable devices|nvenc.*not available'){
            return (T 'NvencUnavailable' 'NVIDIA NVENC could not be activated for {0}. Check that the NVIDIA driver is installed and current, then run Check CPU/GPU again.' @($hardware))
        }
    }
    if($backend -eq 'QSV' -and $reason -match '(?i)qsv|mfx|device|driver'){
        return (T 'QsvDriverProblem' 'Intel QSV could not be activated for {0}. Update the Intel graphics driver and run Check CPU/GPU again. Other verified encoders can still be used.' @($hardware))
    }
    if($backend -eq 'AMF' -and $reason -match '(?i)amf|device|driver'){
        return (T 'AmfDriverProblem' 'AMD AMF could not be activated for {0}. Update the AMD graphics driver and run Check CPU/GPU again. Other verified encoders can still be used.' @($hardware))
    }
    return (T 'EncoderFailureReason' 'Error: {0}' @($reason))
}

function Show-EncoderFailureSummary {
    $doc=Get-EncoderCapabilitiesDocument
    if($null-eq$doc){return}
    $failed=@((P $doc 'Encoders' @()) | Where-Object {-not [bool](P $_ 'Verified' $false)})
    if($failed.Count-eq0){return}
    $messages=New-Object System.Collections.Generic.List[string]
    foreach($enc in $failed){
        $friendly=Get-FriendlyEncoderFailureText -Encoder $enc
        if(-not[string]::IsNullOrWhiteSpace($friendly)){$messages.Add($friendly)}
    }
    if($messages.Count-gt0){
        [Windows.Forms.MessageBox]::Show(($messages -join "`r`n`r`n"),(T 'EncoderCheckAttentionTitle' 'CPU/GPU check - attention'),[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)|Out-Null
    }
}

function Get-EncoderCapabilitySummaryText {
    param([object]$Encoder)
    if($null-eq$Encoder){return (T 'EncoderRunCheckHelp' 'Run the check to verify CPU/GPU, HEVC encoders, compatible features and benchmark results.')}
    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add((T 'EncoderDetailsHardware' 'Hardware: {0}' @([string]$Encoder.HardwareName)))
    $lines.Add((T 'EncoderDetailsBackend' 'Backend: {0} / {1}' @([string]$Encoder.Backend,[string]$Encoder.Encoder)))
    if(-not [string]::IsNullOrWhiteSpace([string](P $Encoder 'DriverVersion' ''))){$lines.Add((T 'EncoderDetailsDriver' 'Driver: {0}' @([string]$Encoder.DriverVersion)))}
    $bench=P $Encoder 'Benchmark' $null
    if($bench){
        $lines.Add('')
        $lines.Add((T 'EncoderBenchmarkHeader' 'Benchmark (same 1080p test for every encoder)'))
        $lines.Add((T 'EncoderSpeedLine' 'Speed: {0}x' @((Format-OptionalNumber (P $bench 'SpeedX' $null) '0.00' ''))))
        $lines.Add((T 'EncoderOutputSizeLine' 'Test size: {0} MB' @((Format-OptionalNumber (P $bench 'OutputMB' $null) '0.00' ''))))
        $ssim=P $bench 'SSIM' $null
        if($null-ne$ssim){$lines.Add((T 'EncoderSsimLine' 'SSIM: {0}' @((Format-OptionalNumber $ssim '0.00000' ''))))}
        if([string]$Encoder.Backend -eq 'NVENC'){
            $lines.Add((T 'EncoderVramLine' 'VRAM used max: {0} MB (increase during test {1} MB)' @((Format-OptionalNumber (P $bench 'VramPeakMB' $null) '0' ''),(Format-OptionalNumber (P $bench 'VramDeltaMB' $null) '0' ''))))
            $lines.Add((T 'EncoderUtilLine' 'Encoder/GPU max: {0}% / {1}% | Max temperature: {2} °C' @((Format-OptionalNumber (P $bench 'EncoderUtilMax' $null) '0' ''),(Format-OptionalNumber (P $bench 'GpuUtilMax' $null) '0' ''),(Format-OptionalNumber (P $bench 'TemperatureMaxC' $null) '0' ''))))
        }else{$lines.Add((T 'EncoderVramUnavailable' 'GPU memory measurement: Not available for this backend in this version.'))}
    }
    $caps=P $Encoder 'Capabilities' $null
    if($caps){
        $lines.Add('')
        $lines.Add((T 'EncoderCapabilitiesHeader' 'Checked features'))
        foreach($p in $caps.PSObject.Properties){$lines.Add(('{0}: {1}' -f $p.Name,$(if([bool]$p.Value){'✓'}else{'✗'})))}
    }
    $reason=[string](P $Encoder 'Reason' '')
    if(-not [string]::IsNullOrWhiteSpace($reason)){$lines.Add('');$lines.Add((Get-FriendlyEncoderFailureText -Encoder $Encoder))}
    return ($lines -join [Environment]::NewLine)
}


function Get-EncoderCapabilityRows {
    param([object]$Encoder)
    $rows=New-Object System.Collections.Generic.List[object]
    if($null-eq$Encoder){return $rows.ToArray()}
    $caps=P $Encoder 'Capabilities' $null
    $backend=[string](P $Encoder 'Backend' '')
    if($null-eq$caps){return $rows.ToArray()}
    function Add-CapRow([string]$Name,[bool]$Passed){$rows.Add([pscustomobject]@{Name=$Name;Passed=$Passed})}
    switch($backend){
        'NVENC' {
            Add-CapRow 'CUDA decode' ([bool](P $caps 'CudaDecode' $false))
            Add-CapRow 'Preset P4' ([bool](P $caps 'PresetP4' $false))
            Add-CapRow 'VBR / CQ' (([bool](P $caps 'VBR' $false)) -and ([bool](P $caps 'CQ' $false)))
            Add-CapRow 'Spatial AQ' ([bool](P $caps 'SpatialAQ' $false))
            Add-CapRow 'Temporal AQ' ([bool](P $caps 'TemporalAQ' $false))
            Add-CapRow 'Lookahead 16' ([bool](P $caps 'Lookahead16' $false))
            Add-CapRow 'Surfaces 8' ([bool](P $caps 'Surfaces8' $false))
            Add-CapRow 'Multipass qres' ([bool](P $caps 'MultipassQres' $false))
        }
        'QSV' {
            Add-CapRow 'Preset medium' ([bool](P $caps 'PresetMedium' $false))
            Add-CapRow 'Async depth' ([bool](P $caps 'AsyncDepth' $false))
            Add-CapRow 'Low power' ([bool](P $caps 'LowPower' $false))
            Add-CapRow 'Global quality' ([bool](P $caps 'GlobalQuality' $false))
            Add-CapRow 'ExtBRC' ([bool](P $caps 'ExtBRC' $false))
            Add-CapRow 'RDO' ([bool](P $caps 'RDO' $false))
        }
        'AMF' {
            Add-CapRow 'Transcoding usage' ([bool](P $caps 'TranscodingUsage' $false))
            Add-CapRow 'Balanced quality' ([bool](P $caps 'BalancedQuality' $false))
            Add-CapRow 'VBR peak' ([bool](P $caps 'VbrPeak' $false))
            Add-CapRow 'Pre-analysis' ([bool](P $caps 'PreAnalysis' $false))
        }
        default {
            Add-CapRow 'Preset medium' ([bool](P $caps 'PresetMedium' $false))
            Add-CapRow 'Target bitrate' ([bool](P $caps 'TargetBitrate' $false))
        }
    }
    return $rows.ToArray()
}
function Show-EncoderDetailPanel {
    param([object]$Encoder,[string]$CheckedLocal='')
    if($null-eq$encoderCapabilityList){return}
    $encoderCapabilityList.Items.Clear()
    if($null-eq$Encoder){
        $encoderDetailsTitle.Text=T 'EncoderDetailsSelected' 'Selected video encoder details'
        $encoderBenchmarkLabel.Text=T 'EncoderRunCheckHelp' 'Run the check to verify CPU/GPU, HEVC encoders, compatible features and benchmark results.'
        return
    }
    $name=[string](P $Encoder 'HardwareName' '')
    $backend=[string](P $Encoder 'Backend' '')
    $encoderDetailsTitle.Text=('{0} — {1}' -f $name,$backend)
    $bench=P $Encoder 'Benchmark' $null
    $summary=New-Object System.Collections.Generic.List[string]
    if(-not [string]::IsNullOrWhiteSpace($CheckedLocal)){$summary.Add((T 'EncoderLastCheckShort' 'Last check: {0}' @($CheckedLocal)))}
    if($bench){
        $speed=Format-OptionalNumber (P $bench 'SpeedX' $null) '0.00' '-'
        $ssim=Format-OptionalNumber (P $bench 'SSIM' $null) '0.0000' '-'
        $summary.Add((T 'EncoderBenchShort' 'Speed: {0}x   SSIM: {1}' @($speed,$ssim)))
        if($backend-eq'NVENC'){
            $vram=Format-OptionalNumber (P $bench 'VramPeakMB' $null) '0' '-'
            $delta=Format-OptionalNumber (P $bench 'VramDeltaMB' $null) '0' '-'
            $summary.Add((T 'EncoderVramShort' 'VRAM max: {0} MB   Increase: {1} MB' @($vram,$delta)))
        }
    }else{$summary.Add((T 'EncoderBenchmarkPending' 'Benchmark: waiting / running'))}
    $encoderBenchmarkLabel.Text=($summary -join [Environment]::NewLine)
    foreach($row in @(Get-EncoderCapabilityRows $Encoder)){
        $item=New-Object Windows.Forms.ListViewItem
        $item.Text=[string]$row.Name
        $ok=[bool]$row.Passed
        [void]$item.SubItems.Add($(if($ok){'✓ '+(T 'Supported' 'Passed')}else{'✗ '+(T 'NotSupported' 'Not supported')}))
        $item.ForeColor=if($ok){[Drawing.Color]::FromArgb(0,145,80)}else{[Drawing.Color]::FromArgb(190,40,40)}
        [void]$encoderCapabilityList.Items.Add($item)
    }
    $reason=[string](P $Encoder 'Reason' '')
    if(-not [string]::IsNullOrWhiteSpace($reason)){
        $item=New-Object Windows.Forms.ListViewItem
        $item.Text=T 'EncoderFailure' 'Error'
        [void]$item.SubItems.Add($reason)
        $item.ForeColor=[Drawing.Color]::FromArgb(190,40,40)
        [void]$encoderCapabilityList.Items.Add($item)
    }
}

$form=New-Object Windows.Forms.Form
$form.Text=T 'WindowTitle' 'MediaPrep MKV Toolkit Start Center'
$form.StartPosition='CenterScreen'
$form.Size=New-Object Drawing.Size(1260,860)
# Start Center uses a fixed layout. Resizing it smaller hides anchored controls such as
# CPU/GPU verification buttons, so keep the designed size instead of allowing a broken compact view.
$form.FormBorderStyle=[Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox=$false
$form.MinimizeBox=$true
$form.MinimumSize=New-Object Drawing.Size(1260,860)
$form.MaximumSize=New-Object Drawing.Size(1260,860)
$form.BackColor=$script:ThemePalette.Background
$form.Font=New-Object Drawing.Font('Segoe UI',9.5)

$header=New-Object Windows.Forms.Panel
$header.Dock='Top';$header.Height=112;$header.BackColor=$script:ThemePalette.Banner
$form.Controls.Add($header)
$title=New-Label 'MediaPrep MKV Toolkit' 32 10 390 43 25 $true;$title.ForeColor=$script:ThemePalette.BannerText;$header.Controls.Add($title)
$subtitle=New-Label (T 'AppSubtitleBase' 'Queue • UNC import • Muxing') 35 53 385 48 10 $false;$subtitle.ForeColor=$script:ThemePalette.BannerText;$header.Controls.Add($subtitle)
# Process diagnostics are shown in two columns in the banner for better readability.
$processLabel=New-Label '' 430 10 390 94 8.2 $false;$processLabel.ForeColor=$script:ThemePalette.BannerText;$processLabel.Font=New-Object Drawing.Font('Consolas',8.2);$header.Controls.Add($processLabel)
$version=New-Label 'Start Center 3.3.53  |  MediaPrep MKV Toolkit 0.11.53' 820 18 390 22 9 $false;$version.TextAlign='MiddleRight';$version.ForeColor=$script:ThemePalette.BannerText;$version.Anchor='Top,Right';$header.Controls.Add($version)
$toolVersionLabel=New-Label '' 820 42 390 22 8.8 $false;$toolVersionLabel.TextAlign='MiddleRight';$toolVersionLabel.ForeColor=$script:ThemePalette.BannerText;$toolVersionLabel.Anchor='Top,Right';$header.Controls.Add($toolVersionLabel)
$author=New-Label (T 'AuthorCredit' 'Created by Anders Syrén') 820 66 390 22 9 $false;$author.TextAlign='MiddleRight';$author.ForeColor=$script:ThemePalette.BannerText;$author.Anchor='Top,Right';$header.Controls.Add($author)

$tabs=New-Object Windows.Forms.TabControl
$tabs.Location=New-Object Drawing.Point(20,125);$tabs.Size=New-Object Drawing.Size(1205,650);$tabs.Anchor='Top,Bottom,Left,Right';$tabs.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
$form.Controls.Add($tabs)
$tabDash=New-Object Windows.Forms.TabPage;$tabDash.Text=T 'TabDashboard' 'Dashboard'
$tabOptions=New-Object Windows.Forms.TabPage;$tabOptions.Text=T 'TabOptions' 'Options'
$tabHardware=New-Object Windows.Forms.TabPage;$tabHardware.Text=T 'TabHardware' 'CPU/GPU'
$tabPrefs=New-Object Windows.Forms.TabPage;$tabPrefs.Text=T 'TabPreferences' 'Preferences'
$tabs.TabPages.AddRange(@($tabDash,$tabOptions,$tabHardware,$tabPrefs))

# Dashboard: compact summary, work-mode controls and editable queue.
$summaryGroup=New-Object Windows.Forms.GroupBox
$summaryGroup.Text=T 'DashboardSummary' 'Selected settings';$summaryGroup.Location=New-Object Drawing.Point(15,15);$summaryGroup.Size=New-Object Drawing.Size(285,555);$summaryGroup.Anchor='Top,Bottom,Left';$tabDash.Controls.Add($summaryGroup)
$summaryBox=New-Object Windows.Forms.RichTextBox;$summaryBox.ReadOnly=$true;$summaryBox.BorderStyle='None';$summaryBox.BackColor=$tabDash.BackColor;$summaryBox.Location=New-Object Drawing.Point(14,28);$summaryBox.Size=New-Object Drawing.Size(255,510);$summaryBox.Font=New-Object Drawing.Font('Segoe UI',10.5);$summaryBox.Anchor='Top,Bottom,Left,Right';$summaryGroup.Controls.Add($summaryBox)

$workGroup=New-Object Windows.Forms.GroupBox
$workGroup.Text=T 'DashboardQueue' 'Work queue';$workGroup.Location=New-Object Drawing.Point(315,15);$workGroup.Size=New-Object Drawing.Size(845,555);$workGroup.Anchor='Top,Bottom,Left,Right';$tabDash.Controls.Add($workGroup)
$rQueue=New-Object Windows.Forms.RadioButton;$rQueue.Text=T 'QueueMode' 'Queue';$rQueue.Location=New-Object Drawing.Point(18,28);$rQueue.Size=New-Object Drawing.Size(110,26);$rQueue.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold);$workGroup.Controls.Add($rQueue)
$rAll=New-Object Windows.Forms.RadioButton;$rAll.Text=T 'AllInOneMode' 'All in one';$rAll.Location=New-Object Drawing.Point(135,28);$rAll.Size=New-Object Drawing.Size(140,26);$rAll.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold);$workGroup.Controls.Add($rAll)
$queueStatus=New-Label '' 300 27 510 30 10 $true;$queueStatus.Anchor='Top,Left,Right';$workGroup.Controls.Add($queueStatus)

$queueStatsPanel=New-Object Windows.Forms.GroupBox
$queueStatsPanel.Text=T 'QueueStatistics' 'Queue statistics'
# Dedicated statistics area in the upper-right part of Work queue.
# It deliberately does not overlap the queue ListBox (which starts at Y=150).
$queueStatsPanel.Location=New-Object Drawing.Point(470,55)
$queueStatsPanel.Size=New-Object Drawing.Size(355,92)
$queueStatsPanel.Anchor='Top,Right'
$queueStatsPanel.BackColor=$workGroup.BackColor
$queueStatsPanel.Font=New-Object Drawing.Font('Segoe UI',9.5,[Drawing.FontStyle]::Bold)
$workGroup.Controls.Add($queueStatsPanel)

# Initialize the texts immediately. The labels are always visible in Queue mode,
# even before the first inventory has completed.
$queueStatsLeft1=New-Label (T 'QueueStatsRemainingThisQueue' 'Remaining this queue: {0}' @(0)) 12 20 165 22 9.2 $false
$queueStatsRight1=New-Label (T 'QueueStatsProcessedEntireQueue' 'Processed entire queue: {0}/{1}' @(0,0)) 178 20 165 22 9.2 $false
$queueStatsLeft2=New-Label (T 'QueueStatsRemainingSize' 'Remaining size: {0}' @('0 MB')) 12 44 165 22 9.2 $false
$queueStatsRight2=New-Label (T 'QueueStatsReadyReturn' 'Ready to return: {0}' @(0)) 178 44 165 22 9.2 $false
$queueStatsLeft3=New-Label (T 'QueueStatsSubsRemaining' 'Subtitles remaining: {0}' @(0)) 12 66 320 20 9.0 $false
$queueStatsPanel.Controls.AddRange(@($queueStatsLeft1,$queueStatsRight1,$queueStatsLeft2,$queueStatsRight2,$queueStatsLeft3))
$queueStatsPanel.Visible=$true
$queueStatsPanel.BringToFront()

# Compatibility object is kept only so older helper code cannot fail if it references the name.
$queueStatsBox=New-Object Windows.Forms.RichTextBox
$queueStatsBox.Visible=$false
$script:QueueInventoryPath=Join-Path $script:Prefs.DataFolder 'queue-dashboard-inventory.json'
$script:StatsProcessedSeen=@{}
$script:LastStatsRefresh=[datetime]::MinValue

$sourceLabel=New-Object Windows.Forms.Button
$sourceLabel.Text=T 'TemporarySource' 'Temporary source folder'
$sourceLabel.Location=New-Object Drawing.Point(18,56)
$sourceLabel.Size=New-Object Drawing.Size(185,30)
$sourceLabel.TextAlign='MiddleLeft'
$workGroup.Controls.Add($sourceLabel)
$tempSource=New-Object Windows.Forms.TextBox;$tempSource.Location=New-Object Drawing.Point(210,58);$tempSource.Size=New-Object Drawing.Size(615,26);$tempSource.Anchor='Top,Left,Right';$workGroup.Controls.Add($tempSource)
$outputLabel=New-Object Windows.Forms.Button
$outputLabel.Text=T 'TemporaryOutput' 'Temporary output folder'
$outputLabel.Location=New-Object Drawing.Point(18,88)
$outputLabel.Size=New-Object Drawing.Size(185,30)
$outputLabel.TextAlign='MiddleLeft'
$workGroup.Controls.Add($outputLabel)
$tempOutput=New-Object Windows.Forms.TextBox;$tempOutput.Location=New-Object Drawing.Point(210,90);$tempOutput.Size=New-Object Drawing.Size(615,26);$tempOutput.Anchor='Top,Left,Right';$workGroup.Controls.Add($tempOutput)
$sourceBrowse=$sourceLabel
$outputBrowse=$outputLabel
$allHint=New-Label (T 'AllInOneHint' 'Temporary paths apply only to this run. Change permanent defaults in Preferences.') 210 118 610 23 8.5 $false;$allHint.ForeColor=[Drawing.Color]::FromArgb(85,95,108);$allHint.Anchor='Top,Left,Right';$workGroup.Controls.Add($allHint)

# One clean vertical command row for both Queue and All-in-one modes.
$buttonPanel=New-Object Windows.Forms.Panel;$buttonPanel.Location=New-Object Drawing.Point(18,150);$buttonPanel.Size=New-Object Drawing.Size(175,385);$buttonPanel.Anchor='Top,Bottom,Left';$workGroup.Controls.Add($buttonPanel)
$bLoad=New-Object Windows.Forms.Button;$bLoad.Text=T 'AddToQueue' 'Add to queue';$bLoad.Location=New-Object Drawing.Point(0,0);$bLoad.Size=New-Object Drawing.Size(155,38);$buttonPanel.Controls.Add($bLoad)
$bRemove=New-Object Windows.Forms.Button;$bRemove.Text=T 'Remove' 'Remove';$bRemove.Location=New-Object Drawing.Point(0,46);$bRemove.Size=New-Object Drawing.Size(155,38);$buttonPanel.Controls.Add($bRemove)
$bUp=New-Object Windows.Forms.Button;$bUp.Text=T 'MoveUp' 'Move up';$bUp.Location=New-Object Drawing.Point(0,92);$bUp.Size=New-Object Drawing.Size(155,38);$buttonPanel.Controls.Add($bUp)
$bDown=New-Object Windows.Forms.Button;$bDown.Text=T 'MoveDown' 'Move down';$bDown.Location=New-Object Drawing.Point(0,138);$bDown.Size=New-Object Drawing.Size(155,38);$buttonPanel.Controls.Add($bDown)
$bSaveQueue=New-Object Windows.Forms.Button;$bSaveQueue.Text=T 'SaveQueue' 'Save queue';$bSaveQueue.Location=New-Object Drawing.Point(0,184);$bSaveQueue.Size=New-Object Drawing.Size(155,38);$buttonPanel.Controls.Add($bSaveQueue)
$bOpenQueue=New-Object Windows.Forms.Button;$bOpenQueue.Text=T 'OpenQueue' 'Open queue';$bOpenQueue.Location=New-Object Drawing.Point(0,230);$bOpenQueue.Size=New-Object Drawing.Size(155,38);$buttonPanel.Controls.Add($bOpenQueue)
$bOpenLog=New-Object Windows.Forms.Button;$bOpenLog.Text=T 'LogsButton' 'Logs';$bOpenLog.Visible=$false
$bOpenOutput=New-Object Windows.Forms.Button;$bOpenOutput.Text=T 'OpenOutputFolder' 'Processed videos';$bOpenOutput.Location=New-Object Drawing.Point(0,276);$bOpenOutput.Size=New-Object Drawing.Size(155,38);$buttonPanel.Controls.Add($bOpenOutput)
$bOrganize=New-Object Windows.Forms.Button;$bOrganize.Text=T 'OrganizeFolders' 'Sort into folders';$bOrganize.Location=New-Object Drawing.Point(0,322);$bOrganize.Size=New-Object Drawing.Size(155,48);$buttonPanel.Controls.Add($bOrganize)

$queueList=New-Object Windows.Forms.ListBox;$queueList.Location=New-Object Drawing.Point(200,150);$queueList.Size=New-Object Drawing.Size(625,335);$queueList.Font=New-Object Drawing.Font('Consolas',9.5);$queueList.Anchor='Top,Bottom,Left,Right';$queueList.HorizontalScrollbar=$true;$workGroup.Controls.Add($queueList)
$cDelete=New-Check (T 'DeleteSources' 'Delete old TS/MP4/AVI/MPG/MPEG files and used subtitles only after verified MKV return') 200 495 610;$cDelete.Anchor='Bottom,Left,Right';$workGroup.Controls.Add($cDelete)

# Options tab: run mode and encoding criteria at the top, operational
# choices below, matching the cleaner overview-style layout.
$modeGroup=New-Object Windows.Forms.GroupBox
$modeGroup.Text=T 'Mode' 'Run mode'
$modeGroup.Location=New-Object Drawing.Point(18,18)
$modeGroup.Size=New-Object Drawing.Size(330,190)
$tabOptions.Controls.Add($modeGroup)
$rFull=New-Object Windows.Forms.RadioButton;$rFull.Text=T 'ModeFull' 'Full workflow';$rFull.Location=New-Object Drawing.Point(18,35);$rFull.Size=New-Object Drawing.Size(295,28)
$rAnalyze=New-Object Windows.Forms.RadioButton;$rAnalyze.Text=T 'ModeAnalyze' 'Analysis only';$rAnalyze.Location=New-Object Drawing.Point(18,82);$rAnalyze.Size=New-Object Drawing.Size(295,28)
$rEncode=New-Object Windows.Forms.RadioButton;$rEncode.Text=T 'ModeEncode' 'Analyze and encode MKV';$rEncode.Location=New-Object Drawing.Point(18,129);$rEncode.Size=New-Object Drawing.Size(295,38)
$modeGroup.Controls.AddRange(@($rFull,$rAnalyze,$rEncode))

$criteriaGroup=New-Object Windows.Forms.GroupBox
$criteriaGroup.Text=T 'EncodingCriteria' 'Encoding recommendation criteria'
$criteriaGroup.Location=New-Object Drawing.Point(365,18)
$criteriaGroup.Size=New-Object Drawing.Size(815,190)
$criteriaGroup.Anchor='Top,Left,Right'
$tabOptions.Controls.Add($criteriaGroup)

function New-OptionRatioNumeric {
    param([string]$LabelKey,[string]$Fallback,[double]$Value,[double]$Minimum,[double]$Maximum,[int]$Decimals,[double]$Increment,[int]$Y)
    $label=New-Label (T $LabelKey $Fallback) 15 $Y 285 27 9.5 $false
    $criteriaGroup.Controls.Add($label)
    $numeric=New-Object Windows.Forms.NumericUpDown
    $numeric.Location=New-Object Drawing.Point(300,$Y)
    $numeric.Size=New-Object Drawing.Size(115,27)
    $numeric.DecimalPlaces=$Decimals;$numeric.Minimum=[decimal]$Minimum;$numeric.Maximum=[decimal]$Maximum;$numeric.Increment=[decimal]$Increment;$numeric.Value=[decimal]$Value
    $criteriaGroup.Controls.Add($numeric)
    return $numeric
}
$tvRatio=New-OptionRatioNumeric 'TVTargetMBPerMinute' 'TV target MB per minute' ([double]$script:Prefs.TVTargetMBPerMinute) 1 100 1 0.5 28
$tvExample=New-Label '' 435 28 360 28 9 $false;$tvExample.Anchor='Top,Left,Right';$criteriaGroup.Controls.Add($tvExample)
$movieRatio=New-OptionRatioNumeric 'MovieTargetMBPerMinute' 'Movie target MB per minute' ([double]$script:Prefs.MovieTargetMBPerMinute) 1 100 1 0.5 64
$movieExample=New-Label '' 435 64 360 28 9 $false;$movieExample.Anchor='Top,Left,Right';$criteriaGroup.Controls.Add($movieExample)
$thresholdRatio=New-OptionRatioNumeric 'EncodeThresholdMultiplier' 'Encoding threshold multiplier' ([double]$script:Prefs.EncodeThresholdMultiplier) 1 5 2 0.05 100
$minimumSaving=New-OptionRatioNumeric 'MinimumSavingPercent' 'Minimum estimated saving percent' ([double]$script:Prefs.MinimumSavingPercent) 0 95 0 1 136

$optionsGroup=New-Object Windows.Forms.GroupBox
$optionsGroup.Text=T 'TabOptions' 'Options'
$optionsGroup.Location=New-Object Drawing.Point(18,220)
$optionsGroup.Size=New-Object Drawing.Size(1162,313)
$optionsGroup.Anchor='Top,Left,Right'
$tabOptions.Controls.Add($optionsGroup)
$cMux=New-Check (T 'AutoMux' 'Start muxing automatically') 15 30 535
$cEncode=New-Check (T 'EnableEncoding' 'Reduce file size by encoding recommended MKV files') 15 70 535
$cForce=New-Check (T 'ForceRemux' 'Force remuxing') 15 110 535
$cReanalyze=New-Check (T 'Reanalyze' 'Analyze all MKV files again') 15 150 535
$cRebuild=New-Check (T 'RebuildIndex' 'Rebuild scan and analysis indexes') 15 190 535
$cIgnoreDecodeErrors=New-Check (T 'IgnoreDecodeErrors' 'Ignore decode errors') 15 230 535
$cProcessErrorQueue=New-Check (T 'ProcessErrorQueue' 'Process error queue') 590 30 545
$cCloseConsole=New-Check (T 'CloseConsole' 'Close command window when queue finishes') 590 70 545
$cSleep=New-Check (T 'PreventSleep' 'Keep computer awake for the entire queue') 590 110 545
$cShutdown=New-Check (T 'Shutdown' 'Shut down computer when the entire queue completes without errors') 590 150 545
$uacShield=New-Object Windows.Forms.PictureBox
$uacShield.Location=New-Object Drawing.Point(590,194)
$uacShield.Size=New-Object Drawing.Size(22,22)
$uacShield.SizeMode=[Windows.Forms.PictureBoxSizeMode]::StretchImage
try{$uacShield.Image=[Drawing.SystemIcons]::Shield.ToBitmap()}catch{}
$uacShield.TabStop=$false
$cUpdates=New-Check (T 'PreventUpdates' 'Prevent automatic Windows Update restart during the queue (administrator required)') 618 190 517
$cVerbose=New-Check (T 'Verbose' 'Verbose logging – capture startup errors and detailed diagnostics') 590 230 545
$optionsGroup.Controls.AddRange(@($cMux,$cEncode,$cForce,$cReanalyze,$cRebuild,$cIgnoreDecodeErrors,$cProcessErrorQueue,$cCloseConsole,$cSleep,$cShutdown,$uacShield,$cUpdates,$cVerbose))

# Source formats are selectable per installation/run. Legacy formats remain on by default;
# MKV is opt-in because an MKV source skips remuxing and goes directly to analysis/encoding.
$formatTitle=New-Label (T 'VideoFormatsToInclude' 'File formats to include') 15 274 190 26 9.5 $true
$cFormatTs=New-Check 'TS' 215 270 70
$cFormatMp4=New-Check 'MP4' 290 270 78
$cFormatAvi=New-Check 'AVI' 375 270 72
$cFormatMpg=New-Check 'MPG' 455 270 78
$cFormatMpeg=New-Check 'MPEG' 540 270 90
$cFormatMkv=New-Check 'MKV' 640 270 80
$optionsGroup.Controls.AddRange(@($formatTitle,$cFormatTs,$cFormatMp4,$cFormatAvi,$cFormatMpg,$cFormatMpeg,$cFormatMkv))

function Get-SelectedVideoFormatsFromUi {
    $formats=New-Object System.Collections.Generic.List[string]
    if($cFormatTs.Checked){$formats.Add('.ts')}
    if($cFormatMp4.Checked){$formats.Add('.mp4')}
    if($cFormatAvi.Checked){$formats.Add('.avi')}
    if($cFormatMpg.Checked){$formats.Add('.mpg')}
    if($cFormatMpeg.Checked){$formats.Add('.mpeg')}
    if($cFormatMkv.Checked){$formats.Add('.mkv')}
    return $formats.ToArray()
}

function Update-RatioExamples {
    $culture=[Globalization.CultureInfo]::CurrentCulture
    $tvValue=[double]$tvRatio.Value
    $movieValue=[double]$movieRatio.Value
    $tvSize=$tvValue*60.0
    $movieGb=($movieValue*120.0)/1000.0
    $tvArgs=[object[]]@($tvValue.ToString('0.0',$culture),$tvSize.ToString('0',$culture))
    $movieArgs=[object[]]@($movieValue.ToString('0.0',$culture),$movieGb.ToString('0.00',$culture))
    $tvExample.Text=T 'TVRatioExample' '{0} MB/min → 60 minutes is approximately {1} MB' $tvArgs
    $movieExample.Text=T 'MovieRatioExample' '{0} MB/min → 120 minutes is approximately {1} GB' $movieArgs
}
$tvRatio.Add_ValueChanged({Update-RatioExamples})
$movieRatio.Add_ValueChanged({Update-RatioExamples})
Update-RatioExamples
$optionsFooter=New-Object Windows.Forms.Panel
$optionsFooter.Dock='Bottom'
$optionsFooter.Height=58
$optionsFooter.BackColor=$tabOptions.BackColor
$tabOptions.Controls.Add($optionsFooter)
$optionsFooter.BringToFront()
$bSaveOptions=New-Object Windows.Forms.Button
$bSaveOptions.Text=T 'SaveSettings' 'Save settings'
$bSaveOptions.Size=New-Object Drawing.Size(175,40)
$bSaveOptions.Location=New-Object Drawing.Point(($optionsFooter.ClientSize.Width-190),9)
$bSaveOptions.Anchor='Top,Right'
$bSaveOptions.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
$optionsFooter.Controls.Add($bSaveOptions)

# CPU/GPU tab: detected hardware, verified HEVC encoders and reproducible benchmark results.
$hardwareInfoGroup=New-Object Windows.Forms.GroupBox
$hardwareInfoGroup.Text=T 'HardwareDetected' 'Detected hardware'
$hardwareInfoGroup.Location=New-Object Drawing.Point(18,18)
$hardwareInfoGroup.Size=New-Object Drawing.Size(1125,118)
$hardwareInfoGroup.Anchor='Top,Left,Right'
$tabHardware.Controls.Add($hardwareInfoGroup)
$hardwareInfoBox=New-Object Windows.Forms.RichTextBox
$hardwareInfoBox.ReadOnly=$true;$hardwareInfoBox.BorderStyle='None';$hardwareInfoBox.Location=New-Object Drawing.Point(14,25);$hardwareInfoBox.Size=New-Object Drawing.Size(1095,80);$hardwareInfoBox.Anchor='Top,Bottom,Left,Right';$hardwareInfoBox.Font=New-Object Drawing.Font('Consolas',9.2);$hardwareInfoGroup.Controls.Add($hardwareInfoBox)

$encoderGroup=New-Object Windows.Forms.GroupBox
$encoderGroup.Text=T 'VideoEncoder' 'Video encoder'
$encoderGroup.Location=New-Object Drawing.Point(18,148)
$encoderGroup.Size=New-Object Drawing.Size(1125,410)
$encoderGroup.Anchor='Top,Bottom,Left,Right'
$tabHardware.Controls.Add($encoderGroup)
$encoderSelectLabel=New-Label (T 'SelectedVideoEncoder' 'Selected video encoder') 18 28 170 24 9.5 $true;$encoderGroup.Controls.Add($encoderSelectLabel)
# The dropdown and left summary share the same right edge.
$encoderCombo=New-Object Windows.Forms.ComboBox;$encoderCombo.DropDownStyle='DropDownList';$encoderCombo.Location=New-Object Drawing.Point(190,25);$encoderCombo.Size=New-Object Drawing.Size(478,29);$encoderCombo.Anchor='Top,Left';$encoderGroup.Controls.Add($encoderCombo)
$encoderStatusLabel=New-Label '' 18 62 650 24 9.2 $false;$encoderStatusLabel.Anchor='Top,Left';$encoderGroup.Controls.Add($encoderStatusLabel)

# The check button exists only on the CPU/GPU tab, above the details panel.
$encoderCheckButton=New-Object Windows.Forms.Button
$encoderCheckButton.Text=T 'CheckAllEncoders' 'Check CPU/GPU'
$encoderCheckButton.Location=New-Object Drawing.Point(682,23)
$encoderCheckButton.Size=New-Object Drawing.Size(210,34)
$encoderCheckButton.Anchor='Top,Left'
$encoderCheckButton.Font=New-Object Drawing.Font('Segoe UI',9.2,[Drawing.FontStyle]::Bold)
$encoderCheckButton.UseVisualStyleBackColor=$false
$encoderGroup.Controls.Add($encoderCheckButton)
$encoderRefreshButton=New-Object Windows.Forms.Button
$encoderRefreshButton.Text=T 'RefreshHardware' 'Refresh hardware'
$encoderRefreshButton.Location=New-Object Drawing.Point(900,23)
$encoderRefreshButton.Size=New-Object Drawing.Size(208,34)
$encoderRefreshButton.Anchor='Top,Left'
$encoderRefreshButton.UseVisualStyleBackColor=$false
$encoderGroup.Controls.Add($encoderRefreshButton)
$encoderProgress=New-Object Windows.Forms.ProgressBar;$encoderProgress.Location=New-Object Drawing.Point(682,64);$encoderProgress.Size=New-Object Drawing.Size(426,18);$encoderProgress.Anchor='Top,Left';$encoderProgress.Minimum=0;$encoderProgress.Maximum=100;$encoderProgress.Value=0;$encoderGroup.Controls.Add($encoderProgress)

# Left: compact overview of all detected encoders.
$encoderList=New-Object Windows.Forms.ListView
$encoderList.Location=New-Object Drawing.Point(18,94);$encoderList.Size=New-Object Drawing.Size(650,292);$encoderList.Anchor='Top,Bottom,Left';$encoderList.View=[Windows.Forms.View]::Details;$encoderList.FullRowSelect=$true;$encoderList.GridLines=$true;$encoderList.HideSelection=$false
[void]$encoderList.Columns.Add((T 'EncoderColumnHardware' 'Hardware'),245)
[void]$encoderList.Columns.Add((T 'EncoderColumnBackend' 'Backend'),70)
[void]$encoderList.Columns.Add((T 'EncoderColumnStatus' 'Status'),110)
[void]$encoderList.Columns.Add((T 'EncoderColumnSpeed' 'Speed'),65)
[void]$encoderList.Columns.Add((T 'EncoderColumnSsim' 'SSIM'),65)
[void]$encoderList.Columns.Add((T 'EncoderColumnVram' 'VRAM max'),85)
$encoderGroup.Controls.Add($encoderList)

# Right: dedicated visible group so test results cannot disappear into the background.
$encoderDetailGroup=New-Object Windows.Forms.GroupBox
$encoderDetailGroup.Text=T 'EncoderDetailsSelected' 'Selected video encoder details'
$encoderDetailGroup.Location=New-Object Drawing.Point(682,94)
$encoderDetailGroup.Size=New-Object Drawing.Size(426,292)
$encoderDetailGroup.Anchor='Top,Bottom,Left'
$encoderGroup.Controls.Add($encoderDetailGroup)
$encoderDetailsTitle=New-Label '' 12 22 398 24 9.5 $true;$encoderDetailsTitle.Anchor='Top,Left,Right';$encoderDetailGroup.Controls.Add($encoderDetailsTitle)
$encoderBenchmarkLabel=New-Label '' 12 48 398 64 9.0 $false;$encoderBenchmarkLabel.Anchor='Top,Left,Right';$encoderDetailGroup.Controls.Add($encoderBenchmarkLabel)
$encoderCapabilityList=New-Object Windows.Forms.ListView
$encoderCapabilityList.Location=New-Object Drawing.Point(12,116);$encoderCapabilityList.Size=New-Object Drawing.Size(398,158);$encoderCapabilityList.Anchor='Top,Bottom,Left,Right';$encoderCapabilityList.View=[Windows.Forms.View]::Details;$encoderCapabilityList.FullRowSelect=$true;$encoderCapabilityList.GridLines=$true;$encoderCapabilityList.HideSelection=$false
[void]$encoderCapabilityList.Columns.Add((T 'EncoderCapabilityColumn' 'Test'),225)
[void]$encoderCapabilityList.Columns.Add((T 'EncoderResultColumn' 'Result'),150)
$encoderDetailGroup.Controls.Add($encoderCapabilityList)

$encoderFoot=New-Label (T 'EncoderCheckFootnote' 'The queue can start only after the selected encoder has been verified. Recheck after FFmpeg, GPU or graphics-driver changes.') 18 562 1120 38 8.8 $false;$encoderFoot.ForeColor=[Drawing.Color]::FromArgb(95,95,95);$encoderFoot.Anchor='Bottom,Left,Right';$tabHardware.Controls.Add($encoderFoot)

$script:RefreshingEncoderUi=$false
function Refresh-EncoderTab {
    $script:RefreshingEncoderUi=$true
    try{
        Start-StartupTiming 'EncoderHardwareSummary'
        try{$hardwareInfoBox.Text=Get-HardwareSummaryText}finally{Stop-StartupTiming 'EncoderHardwareSummary'}
        Start-StartupTiming 'EncoderCapabilitiesRead'
        try{$doc=Get-EncoderCapabilitiesDocument}finally{Stop-StartupTiming 'EncoderCapabilitiesRead'}
        Start-StartupTiming 'EncoderSignatureValidation'
        try{$current=Test-EncoderCapabilitiesCurrent $doc}finally{Stop-StartupTiming 'EncoderSignatureValidation'}
        Start-StartupTiming 'EncoderUiReset'
        try{$encoderList.Items.Clear();$encoderCombo.Items.Clear();$encoderCapabilityList.Items.Clear();$encoderBenchmarkLabel.Text='';$encoderDetailsTitle.Text=T 'EncoderDetailsSelected' 'Selected video encoder details'}finally{Stop-StartupTiming 'EncoderUiReset'}
        if(-not$current){
            # Show every detected candidate immediately, but clearly mark it as unverified.
            # This avoids the misleading impression that only CPU is supported before the first test.
            Start-StartupTiming 'DetectedEncoderCandidates'
            try{$detected=@(Get-DetectedEncoderCandidates)}finally{Stop-StartupTiming 'DetectedEncoderCandidates'}
            foreach($enc in $detected){
                $display=Get-DetectedEncoderDisplayText $enc
                [void]$encoderCombo.Items.Add([pscustomobject]@{Id=[string]$enc.Id;Display=$display;Encoder=$enc;Verified=$false})
                $item=New-Object Windows.Forms.ListViewItem
                $item.Text=[string]$enc.HardwareName
                [void]$item.SubItems.Add([string]$enc.Backend)
                [void]$item.SubItems.Add(('○ '+(T 'EncoderNotChecked' 'Not checked')))
                [void]$item.SubItems.Add('-')
                [void]$item.SubItems.Add('-')
                [void]$item.SubItems.Add('-')
                $item.Tag=$enc
                [void]$encoderList.Items.Add($item)
            }
            $encoderCombo.DisplayMember='Display'
            $selectedIndex=0
            for($i=0;$i-lt$encoderCombo.Items.Count;$i++){
                if([string]$encoderCombo.Items[$i].Id -eq [string]$script:Prefs.SelectedEncoderId){$selectedIndex=$i;break}
            }
            if($encoderCombo.Items.Count-gt0){$encoderCombo.SelectedIndex=$selectedIndex}
            $encoderStatusLabel.Text=if($null-eq$doc){T 'EncoderCheckRequired' 'A CPU/GPU check is required before the queue can start.'}else{T 'EncoderCheckStale' 'The previous check is no longer valid. FFmpeg, GPU or graphics driver changed.'}
            $encoderStatusLabel.ForeColor=[Drawing.Color]::FromArgb(170,95,20)
            Show-EncoderDetailPanel -Encoder $null
            return
        }
        $encoders=@(P $doc 'Encoders' @())
        $fastestId=[string](P $doc 'FastestEncoderId' '')
        Start-StartupTiming 'EncoderVerifiedListBuild'
        try{
            foreach($enc in $encoders){
                $verified=[bool](P $enc 'Verified' $false)
                $bench=P $enc 'Benchmark' $null
                $statusText=if($verified){'✓ '+(T 'EncoderVerified' 'Verified')}else{'✗ '+(T 'EncoderFailed' 'Failed')}
                if($verified -and [string]$enc.Id -eq $fastestId){$statusText+=' / '+(T 'EncoderFastest' 'Fastest')}
                $speed=if($bench -and $null -ne (P $bench 'SpeedX' $null)){('{0:N2}x' -f [double](P $bench 'SpeedX' 0))}else{'-'}
                $ssim=if($bench -and $null -ne (P $bench 'SSIM' $null)){('{0:N4}' -f [double](P $bench 'SSIM' 0))}else{'-'}
                $vram=if($bench -and $null -ne (P $bench 'VramPeakMB' $null)){('{0:N0} MB' -f [double](P $bench 'VramPeakMB' 0))}else{'-'}
                $item=New-Object Windows.Forms.ListViewItem
                $item.Text=[string]$enc.HardwareName
                [void]$item.SubItems.Add([string]$enc.Backend)
                [void]$item.SubItems.Add($statusText)
                [void]$item.SubItems.Add($speed)
                [void]$item.SubItems.Add($ssim)
                [void]$item.SubItems.Add($vram)
                $item.Tag=$enc
                [void]$encoderList.Items.Add($item)
                if($verified){[void]$encoderCombo.Items.Add([pscustomobject]@{Id=[string]$enc.Id;Display=(Get-EncoderDisplayText $enc);Encoder=$enc})}
            }
        }finally{Stop-StartupTiming 'EncoderVerifiedListBuild'}
        Start-StartupTiming 'EncoderSelectionApply'
        try{
            $encoderCombo.DisplayMember='Display'
            $selectedIndex=-1
            for($i=0;$i-lt$encoderCombo.Items.Count;$i++){if([string]$encoderCombo.Items[$i].Id -eq [string]$script:Prefs.SelectedEncoderId){$selectedIndex=$i;break}}
            if($selectedIndex-lt0 -and $encoderCombo.Items.Count-gt0){
                # Never overwrite the user's saved encoder merely because it is temporarily
                # unavailable or not present in the current verified list. CPU is the first-run
                # default only. A later encoder change must always be an explicit user choice.
                for($i=0;$i-lt$encoderCombo.Items.Count;$i++){if([string]$encoderCombo.Items[$i].Id -eq 'cpu-libx265'){$selectedIndex=$i;break}}
                if($selectedIndex-lt0){$selectedIndex=0}
            }
            if($selectedIndex-ge0){$encoderCombo.SelectedIndex=$selectedIndex;Show-EncoderDetailPanel -Encoder $encoderCombo.Items[$selectedIndex].Encoder -CheckedLocal ([string](P $doc 'CheckedLocal' ''))}
        }finally{Stop-StartupTiming 'EncoderSelectionApply'}
        Start-StartupTiming 'EncoderStatusSummary'
        try{
            $checked=[string](P $doc 'CheckedLocal' '')
            $verifiedCount=@($encoders | Where-Object {[bool](P $_ 'Verified' $false)}).Count
            $encoderStatusLabel.Text=(T 'EncoderCheckSummary' 'Last check: {0} | Result: {1}/{2} verified' @($checked,$verifiedCount,$encoders.Count))
            $encoderStatusLabel.ForeColor=[Drawing.Color]::FromArgb(23,112,77)
        }finally{Stop-StartupTiming 'EncoderStatusSummary'}
    }finally{
        $script:RefreshingEncoderUi=$false
        Start-StartupTiming 'EncoderBannerRefreshInsideTab'
        try{Update-EncoderBanner}finally{Stop-StartupTiming 'EncoderBannerRefreshInsideTab'}
        Start-StartupTiming 'EncoderStartGateInsideTab'
        try{Update-EncoderStartGate}finally{Stop-StartupTiming 'EncoderStartGateInsideTab'}
    }
}
function Test-EncoderToolPreflight {
    $missing=New-Object System.Collections.Generic.List[string]
    if(-not(Test-Path -LiteralPath ([string]$script:Prefs.FFmpegPath) -PathType Leaf)){$missing.Add('FFmpeg (ffmpeg.exe)')}
    if(-not(Test-Path -LiteralPath ([string]$script:Prefs.FFprobePath) -PathType Leaf)){$missing.Add('FFprobe (ffprobe.exe)')}
    if(-not(Test-Path -LiteralPath ([string]$script:Prefs.MkvmergePath) -PathType Leaf)){$missing.Add('MKVToolNix (mkvmerge.exe)')}
    if($missing.Count-eq0){return $true}
    $toolText=($missing -join "`r`n - ")
    $message=T 'EncoderToolsMissingDetailed' ("CPU/GPU verification cannot continue because the MediaPrep external tools are not fully configured:`r`n`r`n - {0}`r`n`r`nOpen Settings → External tools. Download the missing tools there, or select the folder where FFmpeg/FFprobe/MKVToolNix are already installed.") @($toolText)
    $tabs.SelectedTab=$tabPrefs
    [Windows.Forms.MessageBox]::Show($message,'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)|Out-Null
    return $false
}

function Invoke-EncoderCheck {
    if(-not(Test-EncoderToolPreflight)){return}
    if($script:QueueRunActive){[Windows.Forms.MessageBox]::Show((T 'EncoderCannotCheckWhileRunning' 'The CPU/GPU check cannot run while the queue is active.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null;return}
    if(-not(Test-Path -LiteralPath $script:EncoderTestScript -PathType Leaf)){throw ('MediaPrep-Encoder-Test.ps1 saknas: '+$script:EncoderTestScript)}
    Save-VisibleWorkList
    foreach($key in $script:PrefBoxes.Keys){$script:Prefs.$key=$script:PrefBoxes[$key].Text.Trim()}
    Write-Json $script:PreferencesPath $script:Prefs;Apply-Prefs-ToConfig
    Remove-Item -LiteralPath $script:EncoderTestStatusPath -Force -ErrorAction SilentlyContinue
    Clear-EncoderSessionSignature
    $encoderCheckButton.Enabled=$false;$encoderRefreshButton.Enabled=$false;if($null-ne$bEncoderCheckFooter){$bEncoderCheckFooter.Enabled=$false};$encoderProgress.Value=0
    $encoderStatusLabel.Text=T 'EncoderChecking' 'Checking CPU/GPU and running benchmark...';$encoderStatusLabel.ForeColor=[Drawing.Color]::FromArgb(55,95,135)
    [Windows.Forms.Application]::DoEvents()
    try{
        $argString='-NoProfile -ExecutionPolicy Bypass -File "{0}" -Root "{1}" -BenchmarkSeconds {2}' -f $script:EncoderTestScript,$script:Root,[int]$script:Prefs.EncoderBenchmarkSeconds
        $proc=Start-Process -FilePath 'powershell.exe' -ArgumentList $argString -WindowStyle Hidden -PassThru
        while(-not$proc.HasExited){
            $st=Read-Json -Path $script:EncoderTestStatusPath -Default $null
            if($st){
                $pct=[int](P $st 'Percent' 0);if($pct-lt0){$pct=0};if($pct-gt100){$pct=100};$encoderProgress.Value=$pct
                $current=[string](P $st 'Current' '');$message=[string](P $st 'Message' '')
                $encoderStatusLabel.Text=if([string]::IsNullOrWhiteSpace($current)){$message}else{('{0}: {1}' -f $current,$message)}
                $live=P $st 'Details' $null
                if($live){
                    Show-EncoderDetailPanel -Encoder $live
                    $liveId=[string](P $live 'Id' '')
                    foreach($li in $encoderList.Items){
                        if([string](P $li.Tag 'Id' '') -eq $liveId){$li.Selected=$true;$li.EnsureVisible();break}
                    }
                }
            }
            [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 250
        }
        $proc.WaitForExit();$exitCode=$proc.ExitCode;$proc.Dispose();$encoderProgress.Value=100
        $freshDoc=Get-EncoderCapabilitiesDocument
        if($exitCode-eq0 -and $null-ne$freshDoc){[void](Set-SessionHardwareFromEncoderDocument -Document $freshDoc -Persist)}else{[void](Get-HardwareSnapshot -ForceRefresh -Persist)}
        Refresh-EncoderTab
        if($exitCode-eq0){Show-EncoderFailureSummary}
        if($exitCode-ne0){[Windows.Forms.MessageBox]::Show((T 'EncoderCheckFailedMessage' 'The encoder check failed. See the encoder test log in the Loggar folder.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)|Out-Null}
    }finally{$encoderCheckButton.Enabled=$true;$encoderRefreshButton.Enabled=$true;if($null-ne$bEncoderCheckFooter){$bEncoderCheckFooter.Enabled=$true};Update-EncoderStartGate}
}
function Test-EncoderReadyForQueueSilent {
    $doc=Get-EncoderCapabilitiesDocument
    if(-not(Test-EncoderCapabilitiesCurrent $doc)){return $false}
    $enc=Get-EncoderById -Document $doc -Id ([string]$script:Prefs.SelectedEncoderId)
    return ($null-ne$enc -and [bool](P $enc 'Verified' $false))
}
function Update-EncoderStartGate {
    # Fail-safe UI gate.  The queue process must never be startable until the selected
    # encoder has passed the real MediaPrep capability test.  While a queue is running,
    # the same button remains enabled because it is the Stop button.
    if($null-eq$bStart){return}
    if($script:QueueRunActive){
        $bStart.Enabled=$true
        if($null-ne$bEncoderCheckFooter){$bEncoderCheckFooter.Enabled=$false}
        return
    }
    $ready=Test-EncoderReadyForQueueSilent
    $bStart.Enabled=[bool]$ready
    if($null-ne$bEncoderCheckFooter){$bEncoderCheckFooter.Enabled=$true}
}
function Test-EncoderReadyForQueue {
    # Queue start is a safety boundary: refresh Windows hardware/driver data and FFmpeg before accepting cached verification.
    $doc=Get-EncoderCapabilitiesDocument
    if(-not(Test-EncoderCapabilitiesCurrent -Document $doc -ForceRefresh)){
        $tabs.SelectedTab=$tabHardware;Refresh-EncoderTab
        [Windows.Forms.MessageBox]::Show((T 'EncoderRequiredBeforeQueue' 'CPU/GPU must be checked before the queue can start. Run "Check CPU/GPU" on the CPU/GPU tab.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null
        $encoderCheckButton.Select()
        $encoderCheckButton.Focus()
        Update-EncoderStartGate
        return $false
    }
    $enc=Get-EncoderById -Document $doc -Id ([string]$script:Prefs.SelectedEncoderId)
    if($null-eq$enc -or -not[bool](P $enc 'Verified' $false)){
        $tabs.SelectedTab=$tabHardware;Refresh-EncoderTab
        [Windows.Forms.MessageBox]::Show((T 'SelectedEncoderNotVerified' 'The selected video encoder is not verified. Select an encoder that passed the check.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)|Out-Null
        Update-EncoderStartGate
        return $false
    }
    return $true
}
$encoderCheckButton.Add_Click({try{Invoke-EncoderCheck}catch{Show-GuiError -ErrorRecord $_ -Context 'Encoder check'}})
$encoderRefreshButton.Add_Click({try{[void](Get-HardwareSnapshot -ForceRefresh -Persist);Refresh-EncoderTab}catch{Show-GuiError -ErrorRecord $_ -Context 'Refresh hardware'}})
$encoderCombo.Add_SelectedIndexChanged({
    if($script:RefreshingEncoderUi -or $null-eq$encoderCombo.SelectedItem){return}
    if($script:QueueRunActive){Refresh-EncoderTab;[Windows.Forms.MessageBox]::Show((T 'EncoderCannotChangeWhileRunning' 'The video encoder cannot be changed while the queue is running.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null;return}
    $selected=$encoderCombo.SelectedItem
    if($null-ne$selected.Encoder -and [bool](P $selected.Encoder 'Verified' $false)){
        $script:Prefs.SelectedEncoderId=[string]$selected.Id
        Write-Json $script:PreferencesPath $script:Prefs;Apply-Prefs-ToConfig
        Show-EncoderDetailPanel -Encoder $selected.Encoder -CheckedLocal ([string](P (Get-EncoderCapabilitiesDocument) 'CheckedLocal' ''))
        Update-EncoderBanner;Update-Dashboard
    }elseif($null-ne$selected.Encoder){
        Show-EncoderDetailPanel -Encoder $selected.Encoder
    }
})
# The overview list is read-only for comparison. The detail pane follows the selected dropdown encoder only.

# Preferences are split into a compact path panel and a program-options panel.
$prefPanel=New-Object Windows.Forms.Panel
$prefPanel.Location=New-Object Drawing.Point(10,12)
$prefPanel.Size=New-Object Drawing.Size(1140,560)
$prefPanel.Anchor='Top,Bottom,Left,Right'
$prefPanel.AutoScroll=$false
$tabPrefs.Controls.Add($prefPanel)

$preferencesFooter=New-Object Windows.Forms.Panel
$preferencesFooter.Dock='Bottom'
$preferencesFooter.Height=58
$preferencesFooter.BackColor=$tabPrefs.BackColor
$tabPrefs.Controls.Add($preferencesFooter)
$preferencesFooter.BringToFront()

$leftPrefs=New-Object Windows.Forms.GroupBox
$leftPrefs.Text=T 'PathsAndTools' 'Paths and tools'
$leftPrefs.Location=New-Object Drawing.Point(8,6)
$leftPrefs.Size=New-Object Drawing.Size(700,540)
$leftPrefs.Anchor='Top,Bottom,Left'
$prefPanel.Controls.Add($leftPrefs)

$rightPrefs=New-Object Windows.Forms.GroupBox
$rightPrefs.Text=T 'ProgramPreferences' 'Program preferences'
$rightPrefs.Location=New-Object Drawing.Point(720,6)
$rightPrefs.Size=New-Object Drawing.Size(405,540)
$rightPrefs.Anchor='Top,Bottom,Left,Right'
$prefPanel.Controls.Add($rightPrefs)

$script:PrefBoxes=@{}
$script:PrefBrowseButtons=New-Object System.Collections.Generic.List[object]
$script:PrefRowControls=New-Object System.Collections.Generic.List[object]
$script:PrefStatusLabels=@{}
$folderRows=@(
 @('ApplicationFolder','InstallFolder','Application folder'),@('SourceFolder','SourceFolder','Input folder'),@('OutputFolder','OutputFolder','Processed video folder'),
 @('DataFolder','DataFolder','Data folder'),@('LogFolder','LogFolder','Log folder'),@('ReportFolder','ReportFolder','Reports folder'),@('TempFolder','TempFolder','Temporary folder'))
$rowY=24
foreach($row in $folderRows){
    $property=[string]$row[0]
    $browse=New-Object Windows.Forms.Button
    $browse.Text=T ([string]$row[1]) ([string]$row[2])
    $browse.Location=New-Object Drawing.Point(14,($rowY - 2))
    $browse.Size=New-Object Drawing.Size(195,31)
    $browse.TextAlign='MiddleLeft'
    $leftPrefs.Controls.Add($browse)

    $box=New-Object Windows.Forms.TextBox
    $box.Location=New-Object Drawing.Point(220,$rowY)
    $box.Size=New-Object Drawing.Size(425,27)
    $box.Anchor='Top,Left,Right'
    $box.Text=[string]$script:Prefs.$property
    $leftPrefs.Controls.Add($box)

    $pathStatus=New-Object Windows.Forms.Label
    $pathStatus.Location=New-Object Drawing.Point(652,($rowY - 1))
    $pathStatus.Size=New-Object Drawing.Size(28,28)
    $pathStatus.TextAlign='MiddleCenter'
    $pathStatus.Font=New-Object Drawing.Font('Segoe UI Symbol',15,[Drawing.FontStyle]::Bold)
    $pathStatus.Anchor='Top,Right'
    $pathStatus.Tag=$property
    $leftPrefs.Controls.Add($pathStatus)

    $browse.BringToFront()
    $script:PrefBoxes[$property]=$box
    $script:PrefStatusLabels[$property]=$pathStatus
    $script:PrefBrowseButtons.Add($browse)
    $script:PrefRowControls.Add([pscustomobject]@{ Box=$box; Button=$browse; Status=$pathStatus; Kind='Folder'; Property=$property })
    $browse.Tag=$property
    $browse.Add_Click({
        $key=[string]$this.Tag
        $value=Select-Folder $script:PrefBoxes[$key].Text
        if($value){$script:PrefBoxes[$key].Text=$value;Update-PathAndProgramStatus}
    })
    $rowY+=45
}
$toolRows=@(@('FFmpegPath','FFmpegPath','ffmpeg.exe'),@('FFprobePath','FFprobePath','ffprobe.exe'),@('MkvmergePath','MkvmergePath','mkvmerge.exe'))
$rowY+=6
$leftToolsTitle=New-Label (T 'ExternalTools' 'External tools') 18 ($rowY+2) 220 24 10 $true
$leftPrefs.Controls.Add($leftToolsTitle)
$rowY+=30
foreach($row in $toolRows){
    $property=[string]$row[0]
    $browse=New-Object Windows.Forms.Button
    $browse.Text=T ([string]$row[1]) ([string]$row[2])
    $browse.Location=New-Object Drawing.Point(14,($rowY - 2))
    $browse.Size=New-Object Drawing.Size(195,31)
    $browse.TextAlign='MiddleLeft'
    $leftPrefs.Controls.Add($browse)

    $box=New-Object Windows.Forms.TextBox
    $box.Location=New-Object Drawing.Point(220,$rowY)
    $box.Size=New-Object Drawing.Size(425,27)
    $box.Anchor='Top,Left,Right'
    $box.Text=[string]$script:Prefs.$property
    $leftPrefs.Controls.Add($box)

    $pathStatus=New-Object Windows.Forms.Label
    $pathStatus.Location=New-Object Drawing.Point(652,($rowY - 1))
    $pathStatus.Size=New-Object Drawing.Size(28,28)
    $pathStatus.TextAlign='MiddleCenter'
    $pathStatus.Font=New-Object Drawing.Font('Segoe UI Symbol',15,[Drawing.FontStyle]::Bold)
    $pathStatus.Anchor='Top,Right'
    $pathStatus.Tag=$property
    $leftPrefs.Controls.Add($pathStatus)

    $browse.BringToFront()
    $script:PrefBoxes[$property]=$box
    $script:PrefStatusLabels[$property]=$pathStatus
    $script:PrefBrowseButtons.Add($browse)
    $script:PrefRowControls.Add([pscustomobject]@{ Box=$box; Button=$browse; Status=$pathStatus; Kind='File'; Property=$property })
    $browse.Tag=$property
    $browse.Add_Click({
        $key=[string]$this.Tag
        $name=switch($key){'FFmpegPath'{'ffmpeg.exe'}'FFprobePath'{'ffprobe.exe'}'MkvmergePath'{'mkvmerge.exe'}default{Split-Path -Leaf $script:PrefBoxes[$key].Text}}
        $value=Select-Exe $script:PrefBoxes[$key].Text $name
        if($value){$script:PrefBoxes[$key].Text=$value;Update-PathAndProgramStatus}
    })
    $rowY+=45
}

# Program settings on the right.
$languageTitle=New-Label (T 'PreferencesLanguage' 'Language') 18 32 375 26 10 $true
$rightPrefs.Controls.Add($languageTitle)
$langCombo=New-Object Windows.Forms.ComboBox
$langCombo.DropDownStyle='DropDownList'
$langCombo.Location=New-Object Drawing.Point(18,62)
$langCombo.Size=New-Object Drawing.Size(375,29)
$langCombo.Anchor='Top,Left'
$rightPrefs.Controls.Add($langCombo)
$languageVersion=New-Label '' 18 98 375 28 9 $false
$languageVersion.Anchor='Top,Left'
$rightPrefs.Controls.Add($languageVersion)

$systemCulture = [Globalization.CultureInfo]::CurrentUICulture
$systemLanguageName = $systemCulture.NativeName
$systemDisplay = (T 'SystemDefaultLanguage' 'System default — {0} ({1})' @($systemLanguageName,$systemCulture.Name))
$resolvedSystemCode = Get-SystemLanguageCode
$resolvedSystemObject = Read-LanguageDocument (Get-LanguagePath $resolvedSystemCode)
$resolvedSystemVersion = if($resolvedSystemObject){[string](P $resolvedSystemObject 'LanguageFileVersion' 'unknown')}else{'unknown'}
[void]$langCombo.Items.Add([pscustomobject]@{Code='system';Display=$systemDisplay;Version=$resolvedSystemVersion;IsCurrent=($resolvedSystemVersion-eq$script:RequiredLanguageFileVersion)})
foreach($entry in @(Get-InstalledLanguageDocuments | Sort-Object {[string](P -Object $_.Document -Name 'NativeName' -Default $_.Culture)})){
    $obj=$entry.Document
    $code=[string]$entry.Culture
    $display=[string](P $obj 'NativeName' (P $obj 'LanguageName' $code))
    $localVersion=[string](P $obj 'LanguageFileVersion' 'unknown')
    [void]$langCombo.Items.Add([pscustomobject]@{Code=$code;Display=$display;Version=$localVersion;IsCurrent=($localVersion-eq$script:RequiredLanguageFileVersion)})
}
$langCombo.DisplayMember='Display'
$normalizedPreference=Normalize-LanguagePreference ([string]$script:Prefs.Language)
for($languageIndex=0;$languageIndex -lt @($langCombo.Items).Count;$languageIndex++){
    if([string]$langCombo.Items[$languageIndex].Code -ieq $normalizedPreference){$langCombo.SelectedIndex=$languageIndex;break}
}
if($langCombo.SelectedIndex -lt 0 -and @($langCombo.Items).Count -gt 0){$langCombo.SelectedIndex=0}
$updateLanguageVersionLabel={
    if(-not $langCombo.SelectedItem){$languageVersion.Text='';return}
    $version=[string]$langCombo.SelectedItem.Version
    $languageVersion.Text=(T 'LanguageFileVersionLabel' 'Language file version')+': '+$version
    if(-not[bool]$langCombo.SelectedItem.IsCurrent){
        $languageVersion.Text+=' ('+(T 'LanguageFileExpected' 'expected {0}' @($script:RequiredLanguageFileVersion))+')'
    }
}
$langCombo.Add_SelectedIndexChanged($updateLanguageVersionLabel)
& $updateLanguageVersionLabel

$themeTitle=New-Label (T 'ThemeLabel' 'Theme') 18 130 120 24 10 $true
$rightPrefs.Controls.Add($themeTitle)
$themeCombo=New-Object Windows.Forms.ComboBox
$themeCombo.DropDownStyle='DropDownList'
$themeCombo.Location=New-Object Drawing.Point(140,127)
$themeCombo.Size=New-Object Drawing.Size(253,29)
$themeCombo.Anchor='Top,Left'
$rightPrefs.Controls.Add($themeCombo)
$themeItems=@(
    [pscustomobject]@{Code='Light';Display=(T 'ThemeLight' 'Light')},
    [pscustomobject]@{Code='Dark';Display=(T 'ThemeDark' 'Dark')},
    [pscustomobject]@{Code='Monthly';Display=(T 'ThemeMonthly' 'By month')},
    [pscustomobject]@{Code='Custom';Display=(T 'ThemeCustom' 'Custom')}
)
foreach($themeItem in $themeItems){[void]$themeCombo.Items.Add($themeItem)}
$themeCombo.DisplayMember='Display'
for($themeIndex=0;$themeIndex -lt $themeCombo.Items.Count;$themeIndex++){if([string]$themeCombo.Items[$themeIndex].Code -eq [string]$script:Prefs.Theme){$themeCombo.SelectedIndex=$themeIndex}}
if($themeCombo.SelectedIndex -lt 0){$themeCombo.SelectedIndex=0}
$customThemePanel=New-Object Windows.Forms.Panel
$customThemePanel.Location=New-Object Drawing.Point(18,162)
$customThemePanel.Size=New-Object Drawing.Size(375,52)
$rightPrefs.Controls.Add($customThemePanel)
$customBannerLabel=New-Label (T 'ThemeBanner' 'Banner') 0 0 112 18 8 $false;$customThemePanel.Controls.Add($customBannerLabel)
$customPanelLabel=New-Label (T 'ThemePanel' 'Panel') 127 0 112 18 8 $false;$customThemePanel.Controls.Add($customPanelLabel)
$customBackgroundLabel=New-Label (T 'ThemeBackground' 'Background') 254 0 112 18 8 $false;$customThemePanel.Controls.Add($customBackgroundLabel)
$customBanner=New-Object Windows.Forms.TextBox;$customBanner.Location=New-Object Drawing.Point(0,20);$customBanner.Size=New-Object Drawing.Size(94,27);$customBanner.Text=[string]$script:Prefs.CustomThemeBanner;$customThemePanel.Controls.Add($customBanner)
$customBannerSwatch=New-Object Windows.Forms.Panel;$customBannerSwatch.Location=New-Object Drawing.Point(97,20);$customBannerSwatch.Size=New-Object Drawing.Size(18,27);$customBannerSwatch.BorderStyle='FixedSingle';$customThemePanel.Controls.Add($customBannerSwatch)
$customPanel=New-Object Windows.Forms.TextBox;$customPanel.Location=New-Object Drawing.Point(127,20);$customPanel.Size=New-Object Drawing.Size(94,27);$customPanel.Text=[string]$script:Prefs.CustomThemePanel;$customThemePanel.Controls.Add($customPanel)
$customPanelSwatch=New-Object Windows.Forms.Panel;$customPanelSwatch.Location=New-Object Drawing.Point(224,20);$customPanelSwatch.Size=New-Object Drawing.Size(18,27);$customPanelSwatch.BorderStyle='FixedSingle';$customThemePanel.Controls.Add($customPanelSwatch)
$customBackground=New-Object Windows.Forms.TextBox;$customBackground.Location=New-Object Drawing.Point(254,20);$customBackground.Size=New-Object Drawing.Size(94,27);$customBackground.Text=[string]$script:Prefs.CustomThemeBackground;$customThemePanel.Controls.Add($customBackground)
$customBackgroundSwatch=New-Object Windows.Forms.Panel;$customBackgroundSwatch.Location=New-Object Drawing.Point(351,20);$customBackgroundSwatch.Size=New-Object Drawing.Size(18,27);$customBackgroundSwatch.BorderStyle='FixedSingle';$customThemePanel.Controls.Add($customBackgroundSwatch)
function Update-CustomThemeSwatch {
    param([Windows.Forms.TextBox]$Box,[Windows.Forms.Panel]$Swatch)
    $value=$Box.Text.Trim();if(-not$value.StartsWith('#')){$value='#'+$value}
    if($value-match'^#[0-9A-Fa-f]{6}$'){$Swatch.BackColor=[Drawing.ColorTranslator]::FromHtml($value)}else{$Swatch.BackColor=[Drawing.SystemColors]::Control}
}
function Update-AllCustomThemeSwatches {
    Update-CustomThemeSwatch $customBanner $customBannerSwatch;Update-CustomThemeSwatch $customPanel $customPanelSwatch;Update-CustomThemeSwatch $customBackground $customBackgroundSwatch
}
$customBanner.Add_TextChanged({Update-CustomThemeSwatch $customBanner $customBannerSwatch})
$customPanel.Add_TextChanged({Update-CustomThemeSwatch $customPanel $customPanelSwatch})
$customBackground.Add_TextChanged({Update-CustomThemeSwatch $customBackground $customBackgroundSwatch})
Update-AllCustomThemeSwatches
$customThemePanel.Visible=($themeCombo.SelectedItem -and [string]$themeCombo.SelectedItem.Code -eq 'Custom')
$themeCombo.Add_SelectedIndexChanged({$customThemePanel.Visible=($themeCombo.SelectedItem -and [string]$themeCombo.SelectedItem.Code -eq 'Custom')})

function Update-PathAndProgramStatus {
    $validCount=0
    $totalCount=[int]$script:PrefRowControls.Count
    foreach($rowControl in $script:PrefRowControls){
        $path=[string]$rowControl.Box.Text
        $exists=$false
        if(-not [string]::IsNullOrWhiteSpace($path)){
            if([string]$rowControl.Kind -eq 'File'){
                $exists=Test-Path -LiteralPath $path -PathType Leaf
            } else {
                $exists=Test-Path -LiteralPath $path -PathType Container
            }
        }
        if($exists){
            $rowControl.Status.Text=[char]0x2714
            $rowControl.Status.ForeColor=[Drawing.Color]::FromArgb(24,142,75)
            $rowControl.Status.AccessibleDescription=T 'PathExists' 'Path exists'
            $validCount++
        } else {
            $rowControl.Status.Text=[char]0x2716
            $rowControl.Status.ForeColor=[Drawing.Color]::FromArgb(198,40,40)
            $rowControl.Status.AccessibleDescription=T 'PathMissing' 'Path or program is missing'
        }
    }
    $statusVariable=Get-Variable -Name status -Scope Script -ErrorAction SilentlyContinue
    if($statusVariable -and $statusVariable.Value){
        $statusVariable.Value.Text=(T 'PathProgramStatus' 'Paths / programs')+': '+$validCount+'/'+$totalCount
        if($validCount -eq $totalCount){
            $statusVariable.Value.ForeColor=[Drawing.Color]::FromArgb(23,112,77)
        } else {
            $statusVariable.Value.ForeColor=[Drawing.Color]::FromArgb(198,40,40)
        }
    }
}

function Update-ExternalToolStatus {
    Update-PathAndProgramStatus
}


$toolManagerButton=New-Object Windows.Forms.Button
$toolManagerButton.Text=T 'ManageExternalTools' 'Versions / external tools'
$toolManagerButton.Location=New-Object Drawing.Point(18,220)
$toolManagerButton.Size=New-Object Drawing.Size(375,40)
$toolManagerButton.Anchor='Top,Left'
$toolManagerButton.Font=New-Object Drawing.Font('Segoe UI',9.5,[Drawing.FontStyle]::Bold)
$rightPrefs.Controls.Add($toolManagerButton)
function Reload-ToolPathsFromPreferences {
    $updated=Read-Json $script:PreferencesPath $null
    if($updated){
        foreach($key in @('FFmpegPath','FFprobePath','MkvmergePath')){
            $value=[string](P $updated $key '')
            if(-not [string]::IsNullOrWhiteSpace($value)){
                $fallback=switch($key){
                    'FFmpegPath'{'Tools\FFmpeg\ffmpeg.exe'}
                    'FFprobePath'{'Tools\FFmpeg\ffprobe.exe'}
                    default{'Tools\MKVToolNix\mkvmerge.exe'}
                }
                $script:PrefBoxes[$key].Text=Resolve-ConfiguredPath -Value $value -FallbackRelative $fallback -Executable
            }
        }
    }
    Update-ExternalToolStatus
}
$toolManagerButton.Add_Click({
    if(Test-MediaPrepProcessingActive){
        [Windows.Forms.MessageBox]::Show((T 'ToolsBlockedWhileQueueRuns' 'External tools and MediaPrep versions cannot be changed while the queue is running. Stop the queue first.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null
        return
    }
    $scriptPath=Join-Path $script:AppFolder 'Manage-MediaPrepTools.ps1'
    if(-not(Test-Path -LiteralPath $scriptPath)){[Windows.Forms.MessageBox]::Show('Manage-MediaPrepTools.ps1 is missing.')|Out-Null;return}
    $language=[string]$script:Prefs.Language
    $toolProc=Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$scriptPath+'"'),'-Root',('"'+$script:Root+'"'),'-Language',$language) -Wait -PassThru
    $requestPath=Join-Path $script:Prefs.DataFolder 'mediaprep-update-request.json'
    if(Test-Path -LiteralPath $requestPath -PathType Leaf){
        # Re-check immediately before activation. A surviving/external queue worker must
        # never be updated underneath, even if the tool manager was opened while idle.
        if(Test-MediaPrepProcessingActive){
            [Windows.Forms.MessageBox]::Show((T 'ToolsBlockedWhileQueueRuns' 'External tools and MediaPrep versions cannot be changed while the queue is running. Stop the queue first.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null
            $status.Text=T 'ToolsBlockedWhileQueueRuns' 'External tools and MediaPrep versions cannot be changed while the queue is running. Stop the queue first.'
            $status.ForeColor=[Drawing.Color]::FromArgb(155,90,20)
            return
        }
        $updater=Join-Path $script:AppFolder 'MediaPrep-Updater.ps1'
        if(-not(Test-Path -LiteralPath $updater -PathType Leaf)){
            [Windows.Forms.MessageBox]::Show((T 'UpdaterMissing' 'MediaPrep-Updater.ps1 is missing. The update was not started.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null
            return
        }
        # Run the updater from Data\Temp rather than App. The updater can then replace
        # the entire App directory without depending on its own source file remaining there.
        $updaterTemp=Join-Path $script:Prefs.TempFolder ('MediaPrep-Updater-'+[guid]::NewGuid().ToString('N')+'.ps1')
        Copy-Item -LiteralPath $updater -Destination $updaterTemp -Force
        # A deliberate update owns the UI cleanup. Close both the current dashboard
        # and any orphaned dashboard from an earlier Start Center before activation.
        Stop-QueueDashboardForUserExit -IncludeOrphaned
        $args='-NoProfile -ExecutionPolicy Bypass -File "'+$updaterTemp+'" -Root "'+$script:Root+'" -RequestFile "'+$requestPath+'" -ParentPid '+[string]$PID+' -DeleteSelf'
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WindowStyle Hidden | Out-Null
        $status.Text=T 'MediaPrepUpdateStarting' 'MediaPrep updater is starting. Start Center will close and reopen after the update.'
        $status.ForeColor=[Drawing.Color]::FromArgb(55,95,135)
        [Windows.Forms.Application]::DoEvents()
        $script:SuppressDashboardShutdownOnClose=$true
        $form.Close()
        return
    }
    Reload-ToolPathsFromPreferences
    Refresh-BannerRuntimeInfo -RefreshTools
})

$bRefreshTools=New-Object Windows.Forms.Button
$bRefreshTools.Text=T 'CheckPathsPrograms' 'Check paths / programs'
$bRefreshTools.Location=New-Object Drawing.Point(18,270)
$bRefreshTools.Size=New-Object Drawing.Size(375,36)
$bRefreshTools.Anchor='Top,Left'
$rightPrefs.Controls.Add($bRefreshTools)
$bRefreshTools.Add_Click({Update-PathAndProgramStatus})

# Dedicated queue-monitor button in Preferences (requested location in the right-hand program settings area).
$bStats=New-Object Windows.Forms.Button
$bStats.Text=T 'ShowStatistics' 'Show statistics'
$bStats.Location=New-Object Drawing.Point(18,320)
$bStats.Size=New-Object Drawing.Size(375,40)
$bStats.Anchor='Top,Left'
$bStats.Font=New-Object Drawing.Font('Segoe UI',9.5,[Drawing.FontStyle]::Bold)
$rightPrefs.Controls.Add($bStats)

$bPrefsLogs=New-Object Windows.Forms.Button
$bPrefsLogs.Text=T 'LogsButton' 'Logs'
$bPrefsLogs.Location=New-Object Drawing.Point(18,368)
$bPrefsLogs.Size=New-Object Drawing.Size(375,40)
$bPrefsLogs.Anchor='Top,Left'
$rightPrefs.Controls.Add($bPrefsLogs)

$bSavePrefs=New-Object Windows.Forms.Button
$bSavePrefs.Text=T 'SavePreferences' 'Save preferences'
$bSavePrefs.Size=New-Object Drawing.Size(175,40)
$bSavePrefs.Location=New-Object Drawing.Point(($preferencesFooter.ClientSize.Width-190),9)
$bSavePrefs.Anchor='Top,Right'
$bSavePrefs.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
$preferencesFooter.Controls.Add($bSavePrefs)
$status=New-Label '' 24 790 680 28 9 $false;$status.Anchor='Bottom,Left';$form.Controls.Add($status);Update-ExternalToolStatus
# CPU/GPU verification belongs only on the CPU/GPU tab; keep no global footer button.
$bEncoderCheckFooter=$null
$bStart=New-Object Windows.Forms.Button;$bStart.Text=T 'StartQueue' 'Start entire queue';$bStart.Location=New-Object Drawing.Point(925,780);$bStart.Size=New-Object Drawing.Size(190,42);$bStart.Anchor='Bottom,Right';$bStart.BackColor=[Drawing.Color]::FromArgb(23,112,77);$bStart.ForeColor=[Drawing.Color]::White;$bStart.Font=New-Object Drawing.Font('Segoe UI',10.5,[Drawing.FontStyle]::Bold);$bStart.Enabled=$false;$form.Controls.Add($bStart)
$bClose=New-Object Windows.Forms.Button;$bClose.Text=T 'Close' 'Close';$bClose.Location=New-Object Drawing.Point(1130,780);$bClose.Size=New-Object Drawing.Size(95,42);$bClose.Anchor='Bottom,Right';$form.Controls.Add($bClose)

function Get-CurrentSettings {
    $mode='Full';if($rAnalyze.Checked){$mode='AnalyzeOnly'}elseif($rEncode.Checked){$mode='EncodeOnly'}
    $workMode=if($rAll.Checked){'AllInOne'}else{'Queue'}
    $selectedVideoFormats=@(Get-SelectedVideoFormatsFromUi)
    $localQueueItems=if($workMode -eq 'AllInOne'){@(Get-ListItems $queueList)}else{@($script:LocalItems)}
    if($workMode -eq 'AllInOne'){
        $localQueueItems=@($localQueueItems | Where-Object {
            $ext=[IO.Path]::GetExtension([string]$_)
            -not[string]::IsNullOrWhiteSpace($ext) -and ($selectedVideoFormats -contains $ext.ToLowerInvariant())
        })
    }
    return [pscustomobject][ordered]@{
        Mode=$mode;WorkMode=$workMode;NoConfirm=[bool]$cMux.Checked;EnableEncoding=[bool]$cEncode.Checked;EncodeRecommended=[bool]$cEncode.Checked;Force=[bool]$cForce.Checked;
        Reanalyze=[bool]$cReanalyze.Checked;RebuildIndex=[bool]$cRebuild.Checked;NoPause=[bool]$cCloseConsole.Checked;
        UncEnabled=($workMode -eq 'Queue');UncQueue=if($workMode -eq 'Queue'){@(Get-ListItems $queueList)}else{@($script:UncItems)};
        LocalFileQueue=@($localQueueItems);TemporarySourceFolder=$tempSource.Text.Trim();TemporaryOutputFolder=$tempOutput.Text.Trim();
        DeleteUncAfterSuccess=[bool]$cDelete.Checked;ShutdownAfterSuccess=[bool]$cShutdown.Checked;PreventSleep=[bool]$cSleep.Checked;
        PreventUpdateRestart=[bool]$cUpdates.Checked;VerboseLogging=[bool]$cVerbose.Checked;IgnoreDecodeErrors=[bool]$cIgnoreDecodeErrors.Checked;ProcessErrorQueue=[bool]$cProcessErrorQueue.Checked;EncoderId=[string]$script:Prefs.SelectedEncoderId;VideoFormats=@($selectedVideoFormats)
    }
}
function Apply-Settings {
    param([object]$Settings)
    $rFull.Checked=([string](P $Settings 'Mode' 'Full') -eq 'Full');$rAnalyze.Checked=([string](P $Settings 'Mode' 'Full') -eq 'AnalyzeOnly');$rEncode.Checked=([string](P $Settings 'Mode' 'Full') -eq 'EncodeOnly')
    $rAll.Checked=([string](P $Settings 'WorkMode' 'Queue') -eq 'AllInOne');$rQueue.Checked=-not $rAll.Checked
    $cMux.Checked=[bool](P $Settings 'NoConfirm' $true);$cEncode.Checked=[bool](P $Settings 'EnableEncoding' (P $Settings 'EncodeRecommended' $true));$cForce.Checked=[bool](P $Settings 'Force' $false);$cReanalyze.Checked=[bool](P $Settings 'Reanalyze' $false);$cRebuild.Checked=[bool](P $Settings 'RebuildIndex' $false);$cCloseConsole.Checked=[bool](P $Settings 'NoPause' $true);$cDelete.Checked=[bool](P $Settings 'DeleteUncAfterSuccess' $true);$cShutdown.Checked=[bool](P $Settings 'ShutdownAfterSuccess' $false);$cSleep.Checked=[bool](P $Settings 'PreventSleep' $true);$cUpdates.Checked=[bool](P $Settings 'PreventUpdateRestart' $false);$cVerbose.Checked=[bool](P $Settings 'VerboseLogging' $false);$cIgnoreDecodeErrors.Checked=[bool](P $Settings 'IgnoreDecodeErrors' $false);$cProcessErrorQueue.Checked=[bool](P $Settings 'ProcessErrorQueue' $false)
    $savedFormats=@((P $Settings 'VideoFormats' @('.ts','.mp4','.avi','.mpg','.mpeg')) | ForEach-Object {[string]$_})
    $cFormatTs.Checked=($savedFormats -contains '.ts');$cFormatMp4.Checked=($savedFormats -contains '.mp4');$cFormatAvi.Checked=($savedFormats -contains '.avi');$cFormatMpg.Checked=($savedFormats -contains '.mpg');$cFormatMpeg.Checked=($savedFormats -contains '.mpeg');$cFormatMkv.Checked=($savedFormats -contains '.mkv')
    $savedTempSource=[string](P $Settings 'TemporarySourceFolder' '')
    $savedTempOutput=[string](P $Settings 'TemporaryOutputFolder' '')
    if([string]::IsNullOrWhiteSpace($savedTempSource)){$savedTempSource=[string]$script:Prefs.SourceFolder}
    if([string]::IsNullOrWhiteSpace($savedTempOutput)){$savedTempOutput=[string]$script:Prefs.OutputFolder}
    $tempSource.Text=$savedTempSource
    $tempOutput.Text=$savedTempOutput
    $script:UncItems=@(P $Settings 'UncQueue' @());$script:LocalItems=@(P $Settings 'LocalFileQueue' @())
    $script:LastWorkMode=$null
}
function Get-PersistedPreventUpdateRestart {
    $saved=Read-Json $script:SettingsPath $null
    if($null -eq $saved){return $false}
    return [bool](P $saved 'PreventUpdateRestart' $false)
}
function Request-ElevatedRestartAfterSave {
    Save-VisibleWorkList
    try{
        [void](Start-MediaPrepElevated)
        $status.Text=T 'RestartingElevated' 'MediaPrep is restarting with administrator privileges...'
        $status.ForeColor=[Drawing.Color]::FromArgb(55,95,135)
        [Windows.Forms.Application]::DoEvents()
        $script:SuppressDashboardShutdownOnClose=$true
        $form.Close()
        return $true
    }catch [ComponentModel.Win32Exception]{
        if($_.Exception.NativeErrorCode -eq 1223){
            [Windows.Forms.MessageBox]::Show((T 'ElevationCancelled' 'The UAC request was cancelled. The setting is saved, but Windows Update restart protection cannot be used until MediaPrep is running as administrator.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)|Out-Null
            return $false
        }
        throw
    }
}

function Save-Options {
    $script:Settings=Get-CurrentSettings
    Write-Json $script:SettingsPath $script:Settings
    $script:Prefs.TVTargetMBPerMinute=[double]$tvRatio.Value
    $script:Prefs.MovieTargetMBPerMinute=[double]$movieRatio.Value
    $script:Prefs.EncodeThresholdMultiplier=[double]$thresholdRatio.Value
    $script:Prefs.MinimumSavingPercent=[double]$minimumSaving.Value
    Write-Json $script:PreferencesPath $script:Prefs
    Apply-Prefs-ToConfig
    Update-Dashboard
}

function Get-OrganizeFileInfo {
    param([System.IO.FileInfo]$File)

    $baseName = [string]$File.BaseName
    $seriesMatch = [regex]::Match($baseName, '^(?<Title>.+?)[\s._-]+[sS](?<Season>\d{1,2})[eE](?<Episode>\d{1,3})(?:[\s._-].*)?$')
    if (-not $seriesMatch.Success) {
        $seriesMatch = [regex]::Match($baseName, '^(?<Title>.+?)[\s._-]+(?<Season>\d{1,2})[xX](?<Episode>\d{1,3})(?:[\s._-].*)?$')
    }
    if ($seriesMatch.Success) {
        $title = $seriesMatch.Groups['Title'].Value.Trim().TrimEnd('.', '-', '_', ' ')
        return [PSCustomObject]@{
            File = $File
            Kind = 'Series'
            Title = $title
            Season = [int]$seriesMatch.Groups['Season'].Value
            Episode = [int]$seriesMatch.Groups['Episode'].Value
        }
    }

    # Movies: remove a trailing year. Parentheses may also contain a small tag,
    # for example "Movie (2015 5.1).mkv".
    $movieMatch = [regex]::Match($baseName, '^(?<Title>.+?)\s*(?:\((?:19|20)\d{2}(?:[^)]*)?\)|(?:19|20)\d{2})\s*$')
    if ($movieMatch.Success) {
        $title = $movieMatch.Groups['Title'].Value.Trim().TrimEnd('.', '-', '_', ' ')
        return [PSCustomObject]@{
            File = $File
            Kind = 'Movie'
            Title = $title
            Season = 0
            Episode = 0
        }
    }

    return [PSCustomObject]@{
        File = $File
        Kind = 'Unknown'
        Title = ''
        Season = 0
        Episode = 0
    }
}

function Invoke-OrganizeOutputFolder {
    if (-not $rAll.Checked) { return }
    if ($script:QueueRunActive) {
        throw (T 'OrganizeWhileRunning' 'Files cannot be organized while the queue is running.')
    }

    $outputFolder = $tempOutput.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($outputFolder) -or -not (Test-Path -LiteralPath $outputFolder -PathType Container)) {
        throw (T 'InvalidOutputFolder' 'The processed video folder does not exist: {0}' @($outputFolder))
    }

    $files = @(Get-ChildItem -LiteralPath $outputFolder -File -Filter '*.mkv' -ErrorAction Stop | Sort-Object Name)
    if ($files.Count -eq 0) {
        [Windows.Forms.MessageBox]::Show(
            (T 'NoMkvToOrganize' 'No MKV files were found directly in the processed video folder.'),
            'MediaPrep',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    $answer = [Windows.Forms.MessageBox]::Show(
        (T 'ConfirmOrganize' 'Analyze {0} MKV files and sort recognized movies and TV episodes into folders?' @($files.Count)),
        (T 'OrganizeFolders' 'Sort into folders'),
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }

    $items = @($files | ForEach-Object { Get-OrganizeFileInfo -File $_ })
    $moved = 0
    $skipped = 0
    $messages = New-Object Collections.Generic.List[string]

    # Movies always get a folder. The trailing year is not included in the folder name.
    foreach ($item in @($items | Where-Object { $_.Kind -eq 'Movie' })) {
        if ([string]::IsNullOrWhiteSpace($item.Title)) { $skipped++; continue }
        $targetFolder = Join-Path $outputFolder $item.Title
        $targetFile = Join-Path $targetFolder $item.File.Name
        if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
            $skipped++
            $messages.Add((T 'OrganizeDestinationExists' 'Already exists, skipped: {0}' @($targetFile)))
            continue
        }
        if (-not (Test-Path -LiteralPath $targetFolder -PathType Container)) {
            New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
        }
        Move-Item -LiteralPath $item.File.FullName -Destination $targetFile -ErrorAction Stop
        $moved++
    }

    # Analyze each series as a group. A missing series folder is created only
    # when season 1 episode 1 is among the files. If S01E01 is absent, the files
    # are left untouched because that usually means the existing series folder
    # is located elsewhere or has already been created.
    $seriesGroups = @($items | Where-Object { $_.Kind -eq 'Series' } | Group-Object Title)
    foreach ($group in $seriesGroups) {
        $title = [string]$group.Name
        if ([string]::IsNullOrWhiteSpace($title)) { $skipped += @($group.Group).Count; continue }
        $targetFolder = Join-Path $outputFolder $title
        $folderExists = Test-Path -LiteralPath $targetFolder -PathType Container
        $hasPilot = @($group.Group | Where-Object { $_.Season -eq 1 -and $_.Episode -eq 1 }).Count -gt 0

        if (-not $folderExists -and -not $hasPilot) {
            $count = @($group.Group).Count
            $skipped += $count
            $messages.Add((T 'SeriesFolderNotCreated' "Series folder '{0}' was not created because S01E01/1x01 was not among the files. {1} file(s) were left in place." @($title,$count)))
            continue
        }
        if (-not $folderExists) {
            New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
        }

        foreach ($item in @($group.Group | Sort-Object Season,Episode,@{Expression={$_.File.Name}})) {
            $targetFile = Join-Path $targetFolder $item.File.Name
            if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
                $skipped++
                $messages.Add((T 'OrganizeDestinationExists' 'Already exists, skipped: {0}' @($targetFile)))
                continue
            }
            Move-Item -LiteralPath $item.File.FullName -Destination $targetFile -ErrorAction Stop
            $moved++
        }
    }

    $unknown = @($items | Where-Object { $_.Kind -eq 'Unknown' })
    $skipped += $unknown.Count
    foreach ($item in $unknown) {
        $messages.Add((T 'UnknownNameSkipped' 'Unrecognized filename, left in place: {0}' @($item.File.Name)))
    }

    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $reportPath = Join-Path $script:Prefs.LogFolder ("MediaPrep-Organize_{0}.log" -f $stamp)
    $reportLines = @(
        (T 'OrganizeReportFolder' 'Folder: {0}' @($outputFolder)),
        (T 'OrganizeReportMoved' 'Moved: {0}' @($moved)),
        (T 'OrganizeReportSkipped' 'Skipped: {0}' @($skipped)),
        ''
    ) + @($messages)
    [IO.File]::WriteAllLines($reportPath, $reportLines, (New-Object Text.UTF8Encoding($true)))

    [Windows.Forms.MessageBox]::Show(
        (T 'OrganizeComplete' 'Folder organization is complete. Moved: {0}. Skipped: {1}.`r`nLog: {2}' @($moved,$skipped,$reportPath)),
        (T 'OrganizeFolders' 'Sort into folders'),
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}


function Format-QueueBytes {
    param([double]$Bytes)
    if($Bytes -ge 1GB){return ('{0:N1} GB' -f ($Bytes/1GB))}
    if($Bytes -ge 1MB){return ('{0:N0} MB' -f ($Bytes/1MB))}
    if($Bytes -ge 1KB){return ('{0:N0} KB' -f ($Bytes/1KB))}
    return ('{0:N0} B' -f $Bytes)
}

function Get-QueueRelativePath {
    param([string]$RootPath,[string]$FullName)
    $rootValue=$RootPath.TrimEnd('\\')
    if($FullName.Length -le $rootValue.Length){return [IO.Path]::GetFileName($FullName)}
    return $FullName.Substring($rootValue.Length).TrimStart('\\')
}

function Set-QueueStatisticsDisplay {
    param(
        [int]$Remaining=0,
        [int]$Processed=0,
        [int]$Total=0,
        [double]$RemainingBytes=0,
        [int]$Ready=0,
        [int]$Subtitles=0,
        [switch]$AllInOne
    )
    $queueStatsLeft1.Text=T 'QueueStatsRemainingThisQueue' 'Remaining this queue: {0}' @($Remaining)
    $queueStatsRight1.Text=T 'QueueStatsProcessedEntireQueue' 'Processed entire queue: {0}/{1}' @($Processed,$Total)
    $queueStatsLeft2.Text=T 'QueueStatsRemainingSize' 'Remaining size: {0}' @((Format-QueueBytes $RemainingBytes))
    if($AllInOne){
        $queueStatsRight2.Text=T 'QueueStatsReady' 'Ready: {0}' @($Ready)
        $queueStatsLeft3.Text=T 'QueueStatsSubsRemaining' 'Subtitles remaining: {0}' @($Subtitles)
        $queueStatsLeft3.Visible=$true
    }else{
        $queueStatsRight2.Text=T 'QueueStatsReadyReturn' 'Ready to return: {0}' @($Ready)
        $queueStatsLeft3.Text=''
        $queueStatsLeft3.Visible=$false
    }
    $queueStatsPanel.Visible=$true
    $queueStatsPanel.BringToFront()
    foreach($c in $queueStatsPanel.Controls){$c.BringToFront()}
    [Windows.Forms.Application]::DoEvents()
}

function Update-AllInOneStatistics {
    $queueStatsPanel.Visible=$true
    $files=@(Get-ListItems $queueList)
    $total=[int]$files.Count
    [double]$bytes=0
    $subs=0
    foreach($filePath in $files){
        if([string]::IsNullOrWhiteSpace([string]$filePath)){continue}
        try{
            if(Test-Path -LiteralPath ([string]$filePath) -PathType Leaf){
                $fi=Get-Item -LiteralPath ([string]$filePath) -ErrorAction Stop
                $bytes += [double]$fi.Length
                $base=[IO.Path]::GetFileNameWithoutExtension($fi.Name)
                $subs += @(Get-ChildItem -LiteralPath $fi.DirectoryName -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq $base -and $_.Extension.ToLowerInvariant() -in @('.srt','.vtt') }).Count
            }
        }catch{}
    }
    $ready=0
    try{
        $out=[string]$tempOutput.Text
        if([string]::IsNullOrWhiteSpace($out)){$out=[string]$script:Prefs.OutputFolder}
        if(Test-Path -LiteralPath $out -PathType Container){$ready=@(Get-ChildItem -LiteralPath $out -File -Recurse -Filter '*.mkv' -ErrorAction SilentlyContinue).Count}
    }catch{}
    Set-QueueStatisticsDisplay -Remaining $total -Processed 0 -Total $total -RemainingBytes $bytes -Ready $ready -Subtitles $subs -AllInOne
}

function Build-QueueStatisticsInventory {
    if($rAll.Checked){Update-AllInOneStatistics;return}
    $roots=@(Get-ListItems $queueList)
    $inventory=New-Object System.Collections.Generic.List[object]
    $found=0
    [double]$foundBytes=0
    $foundSubs=0
    $foundProcessed=0
    $foundReady=0
    Set-QueueStatisticsDisplay -Remaining 0 -Processed 0 -Total 0 -RemainingBytes 0 -Ready 0
    foreach($rootPath in $roots){
        $rootValue=[string]$rootPath
        if([string]::IsNullOrWhiteSpace($rootValue) -or -not(Test-Path -LiteralPath $rootValue -PathType Container)){continue}
        try{
            $selectedFormats=@(Get-SelectedVideoFormatsFromUi)
            Get-ChildItem -LiteralPath $rootValue -File -Recurse -ErrorAction Stop |
                Where-Object { $selectedFormats -contains $_.Extension.ToLowerInvariant() } |
                ForEach-Object {
                    $video=$_
                    $relative=Get-QueueRelativePath -RootPath $rootValue -FullName $video.FullName
                    $relativeMkv=[IO.Path]::ChangeExtension($relative,'.mkv')
                    $localSource=Join-Path ([string]$script:Prefs.SourceFolder) $relative
                    $localOutput=Join-Path ([string]$script:Prefs.OutputFolder) $relativeMkv
                    $subtitleCount=0
                    try{
                        $base=[IO.Path]::GetFileNameWithoutExtension($video.Name)
                        $subtitleCount=@(Get-ChildItem -LiteralPath $video.DirectoryName -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq $base -and $_.Extension.ToLowerInvariant() -in @('.srt','.vtt') }).Count
                    }catch{}
                    $inventory.Add([pscustomobject][ordered]@{
                        Root=$rootValue
                        RelativePath=$relative
                        SourcePath=$video.FullName
                        SourceSize=[int64]$video.Length
                        MuxedSize=$null
                        EncodedSize=$null
                        FinalSize=$null
                        LocalSource=$localSource
                        LocalOutput=$localOutput
                        SubtitleCount=[int]$subtitleCount
                        QueueStage=0
                        QueueStatus='Waiting'
                        CopyInStarted=$null
                        CopyInCompleted=$null
                        MuxStarted=$null
                        MuxCompleted=$null
                        AnalysisCompleted=$null
                        EncodeStarted=$null
                        EncodeCompleted=$null
                        CopyBackStarted=$null
                        CopyBackCompleted=$null
                        CompletedUtc=$null
                        ErrorMessage=$null
                        UpdatedUtc=(Get-Date).ToUniversalTime().ToString('o')
                    })
                    $found++
                    $foundBytes += [double]$video.Length
                    $foundSubs += [int]$subtitleCount
                    $hasSource=(-not[string]::IsNullOrWhiteSpace($localSource) -and (Test-Path -LiteralPath $localSource -PathType Leaf))
                    $hasOutput=(-not[string]::IsNullOrWhiteSpace($localOutput) -and (Test-Path -LiteralPath $localOutput -PathType Leaf))
                    if($hasOutput -and -not $hasSource){$foundProcessed++;$foundReady++}
                    $remaining=[Math]::Max(0,$found-$foundProcessed)
                    $remainingBytes=$foundBytes
                    Set-QueueStatisticsDisplay -Remaining $remaining -Processed $foundProcessed -Total $found -RemainingBytes $remainingBytes -Ready $foundReady
                }
        }catch{}
    }
    $errorQueuePath=Join-Path $script:Prefs.DataFolder 'error-queue.json'
    $errorCount=0
    try{if(Test-Path -LiteralPath $errorQueuePath -PathType Leaf){$errorCount=@(Read-Json $errorQueuePath @()).Count}}catch{}
    Write-Json $script:QueueInventoryPath ([pscustomobject][ordered]@{
        version=3
        stageMap=[ordered]@{
            '0'='Waiting';'1'='CopyingFromUNC';'2'='LocalSourceReady';'3'='Muxing';'4'='Muxed';'5'='Analyzed';'6'='Encoding';'7'='Encoded';'8'='WaitingForReturn';'9'='CopyingToUNC';'10'='Completed';'90'='Error';'91'='ProcessingErrorQueue';'92'='ErrorQueueFailed'
        }
        updatedUtc=(Get-Date).ToUniversalTime().ToString('o')
        errors=[int]$errorCount
        items=@($inventory.ToArray())
    })
    $script:StatsProcessedSeen=@{}
    Update-QueueStatistics -Force
}

function Update-QueueStatistics {
    param([switch]$Force)
    $queueStatsPanel.Visible=$true
    if($rAll.Checked){Update-AllInOneStatistics;return}
    if(-not $Force -and ((Get-Date)-$script:LastStatsRefresh).TotalSeconds -lt 1.2){return}
    $script:LastStatsRefresh=Get-Date
    if(-not(Test-Path -LiteralPath $script:QueueInventoryPath -PathType Leaf)){
        Set-QueueStatisticsDisplay -Remaining 0 -Processed 0 -Total 0 -RemainingBytes 0 -Ready 0
        return
    }
    $inventoryDoc=Read-Json $script:QueueInventoryPath $null
    if($null -eq $inventoryDoc -or -not $inventoryDoc.PSObject.Properties['items']){
        Set-QueueStatisticsDisplay -Remaining 0 -Processed 0 -Total 0 -RemainingBytes 0 -Ready 0
        return
    }
    $items=@($inventoryDoc.items)
    $total=$items.Count;$remaining=0;$processed=0;$ready=0;[double]$remainingBytes=0;$subs=0
    foreach($item in $items){
        $stage=0;try{$stage=[int]$item.QueueStage}catch{}
        if($stage -eq 10){$processed++;$ready++;continue}
        if($stage -ge 90){continue}
        $remaining++
        if($item.PSObject.Properties['FinalSize'] -and $null-ne$item.FinalSize){$remainingBytes += [double]$item.FinalSize}
        elseif($item.PSObject.Properties['EncodedSize'] -and $null-ne$item.EncodedSize){$remainingBytes += [double]$item.EncodedSize}
        elseif($item.PSObject.Properties['MuxedSize'] -and $null-ne$item.MuxedSize){$remainingBytes += [double]$item.MuxedSize}
        else{$remainingBytes += [double]$item.SourceSize}
        $subs += [int]$item.SubtitleCount
    }
    Set-QueueStatisticsDisplay -Remaining $remaining -Processed $processed -Total $total -RemainingBytes $remainingBytes -Ready $ready -Subtitles $subs
}

function Update-Dashboard {
    $settings=Get-CurrentSettings
    $modeName=switch($settings.Mode){'AnalyzeOnly'{T 'ModeAnalyze' 'Analysis only'}'EncodeOnly'{T 'ModeEncode' 'Analyze and encode MKV'}default{T 'ModeFull' 'Full workflow'}}
    $workName=if($settings.WorkMode -eq 'AllInOne'){T 'AllInOneMode' 'All in one'}else{T 'QueueMode' 'Queue'}
    $options=New-Object Collections.Generic.List[string]
    if($settings.NoConfirm){$options.Add((T 'AutoMux' 'Start muxing automatically'))};if($settings.EncodeRecommended){$options.Add((T 'AutoEncode' 'Automatically encode recommended files to HEVC'))};if($settings.ShutdownAfterSuccess){$options.Add((T 'Shutdown' 'Shut down computer when the entire queue completes without errors'))};if($settings.PreventSleep){$options.Add((T 'PreventSleep' 'Keep computer awake for the entire queue'))};if($settings.PreventUpdateRestart){$options.Add((T 'PreventUpdates' 'Prevent automatic Windows Update restart during the queue (administrator required)'))};if($settings.VerboseLogging){$options.Add((T 'Verbose' 'Verbose logging – capture startup errors and detailed diagnostics'))};if($settings.IgnoreDecodeErrors){$options.Add((T 'IgnoreDecodeErrors' 'Ignore decode errors'))};if($settings.ProcessErrorQueue){$options.Add((T 'ProcessErrorQueue' 'Process error queue'))}
    $optionText=if(@($options).Count -gt 0){'• '+($options -join "`r`n• ")}else{T 'None' 'None'}
    $summaryBox.Text=(T 'SummaryMode' 'Run mode: {0}' @($modeName))+"`r`n`r`n"+(T 'SummaryWorkMode' 'Work mode: {0}' @($workName))+"`r`n`r`n"+(T 'SummaryQueue' 'Items in queue: {0}' @($queueList.Items.Count))+"`r`n`r`n"+(T 'SummaryOptions' 'Enabled options: {0}' @("`r`n"+$optionText))
    if($script:QueueRunActive){$queueStatus.Text=T 'QueueRunning' 'Queue is running.'}else{$queueStatus.Text=T 'QueueIdle' 'Queue is not running.'}
    Update-QueueStatistics
}
function Refresh-WorkMode {
    $newMode=if($rAll.Checked){'AllInOne'}else{'Queue'}
    if($null -ne $script:LastWorkMode){
        if($script:LastWorkMode -eq 'Queue'){$script:UncItems=@(Get-ListItems $queueList)}else{$script:LocalItems=@(Get-ListItems $queueList)}
    }
    $script:LastWorkMode=$newMode
    $all=($newMode -eq 'AllInOne')
    if($all){
        if([string]::IsNullOrWhiteSpace($tempSource.Text)){$tempSource.Text=[string]$script:Prefs.SourceFolder}
        if([string]::IsNullOrWhiteSpace($tempOutput.Text)){$tempOutput.Text=[string]$script:Prefs.OutputFolder}
    }
    foreach($control in @($sourceLabel,$tempSource,$sourceBrowse,$outputLabel,$tempOutput,$outputBrowse,$allHint)){$control.Visible=$all}
    $queueStatsPanel.Visible=$true
    $queueStatsPanel.BringToFront()
    $bOpenLog.Visible=$false
    $bSaveQueue.Visible=$true
    $bOpenQueue.Visible=$true
    $bOpenOutput.Visible=$all
    $bOrganize.Visible=$all
    $cDelete.Visible=-not $all
    $queueList.Items.Clear()
    $items=if($all){@($script:LocalItems)}else{@($script:UncItems)}
    foreach($item in $items){if($item){[void]$queueList.Items.Add([string]$item)}}
    Update-Dashboard
}
function Save-VisibleWorkList {
    [string[]]$items = @((Get-ListItems $queueList))
    if ($rAll.Checked) {
        $script:LocalItems = @($items)
        $saved = Read-Json $script:SettingsPath $null
        if ($null -ne $saved) {
            $saved.LocalFileQueue = @($items)
            Write-Json $script:SettingsPath $saved
        }
        # Before a run starts, the visible list is authoritative. During a run,
        # MediaPrep updates the include file after each completed source file.
        if (-not $script:QueueRunActive) {
            $includePath = Join-Path $script:Prefs.DataFolder 'all-in-one-files.json'
            Write-Json $includePath @($items)
        }
    }
    else {
        $script:UncItems = @($items)
        $saved = Read-Json $script:SettingsPath $null
        if ($null -ne $saved) {
            $saved.UncQueue = @($items)
            Write-Json $script:SettingsPath $saved
        }
        if(-not $script:QueueRunActive){Build-QueueStatisticsInventory}
    }
    if($rAll.Checked -and -not $script:QueueRunActive){Update-AllInOneStatistics}
    Update-Dashboard
}

function Save-QueuePackageInteractive {
    if($script:QueueRunActive){[Windows.Forms.MessageBox]::Show((T 'QueueSaveBlocked' 'Stop the queue before saving it.'),'MediaPrep')|Out-Null;return}
    $folder=Join-Path $script:Prefs.DataFolder 'SavedQueues';if(-not(Test-Path -LiteralPath $folder)){New-Item -Path $folder -ItemType Directory -Force|Out-Null}
    $dlg=New-Object Windows.Forms.SaveFileDialog;$dlg.Title=T 'QueueSaveDialogTitle' 'Save MediaPrep queue';$dlg.Filter=T 'QueuePackageFilter' 'MediaPrep queue package (*.zip)|*.zip';$dlg.InitialDirectory=$folder;$dlg.FileName=('MediaPrep-Queue_'+(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')+'.zip');$dlg.OverwritePrompt=$true
    if($dlg.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK){$dlg.Dispose();return}
    try{
        Save-VisibleWorkList
        $mode=if($rAll.Checked){'AllInOne'}else{'Queue'}
        [void](Save-QueuePackageCore -Destination $dlg.FileName -QueueItems @((Get-ListItems $queueList)) -WorkMode $mode)
        $status.Text=T 'QueueSaveSuccess' 'The queue and related JSON/statistics were saved: {0}' @($dlg.FileName);$status.ForeColor=[Drawing.Color]::FromArgb(23,112,77)
    }finally{$dlg.Dispose()}
}
function Load-QueuePackageInteractive {
    if($script:QueueRunActive){[Windows.Forms.MessageBox]::Show((T 'QueueLoadBlocked' 'Stop the active queue before opening a saved queue.'),'MediaPrep')|Out-Null;return}
    $folder=Join-Path $script:Prefs.DataFolder 'SavedQueues';if(-not(Test-Path -LiteralPath $folder)){New-Item -Path $folder -ItemType Directory -Force|Out-Null}
    $dlg=New-Object Windows.Forms.OpenFileDialog;$dlg.Title=T 'QueueLoadDialogTitle' 'Open saved MediaPrep queue';$dlg.Filter=T 'QueuePackageFilter' 'MediaPrep queue package (*.zip)|*.zip';$dlg.InitialDirectory=$folder;$dlg.Multiselect=$false
    if($dlg.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK){$dlg.Dispose();return}
    $temp=Join-Path $script:Prefs.TempFolder ('QueueLoad_'+[Guid]::NewGuid().ToString('N'));New-Item -Path $temp -ItemType Directory -Force|Out-Null
    try{
        Expand-Archive -LiteralPath $dlg.FileName -DestinationPath $temp -Force
        $meta=Read-Json -Path (Join-Path $temp 'queue-package.json') -Default $null;if($null -eq $meta){throw (T 'QueuePackageMissingMetadata' 'The package does not contain queue-package.json.')}
        # Preserve any current completed/paused session before replacing it.
        if(Test-Path -LiteralPath $script:StatisticsCurrentPath -PathType Leaf){$cur=Read-Json $script:StatisticsCurrentPath $null;if($cur){[void](Save-SessionArchive $cur 'statistics-run-before-load')}}
        foreach($name in Get-QueueRuntimeJsonNames){$src=Join-Path $temp $name;if(Test-Path -LiteralPath $src -PathType Leaf){Copy-Item -LiteralPath $src -Destination (Join-Path $script:Prefs.DataFolder $name) -Force}}
        if(Test-Path -LiteralPath $script:StatisticsCurrentPath -PathType Leaf){
            $restored=Read-Json $script:StatisticsCurrentPath $null
            if($restored){
                foreach($pair in @(@('Status','Paused'),@('ActiveRunStartedLocal',''),@('ActiveRunStartedUtc',''))){if($restored.PSObject.Properties[$pair[0]]){$restored.PSObject.Properties[$pair[0]].Value=$pair[1]}else{$restored|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1]}}
                Save-StatisticsSession $restored
            }
        }
        $savedSettings=Read-Json $script:SettingsPath $null;if($savedSettings){Apply-Settings $savedSettings}
        $mode=[string](P $meta 'WorkMode' 'Queue');if($mode -eq 'AllInOne'){$rAll.Checked=$true}else{$rQueue.Checked=$true};Refresh-WorkMode
        $restoredItems=@(P $meta 'QueueItems' @())
        if($mode -eq 'AllInOne'){$script:LocalItems=@($restoredItems)}else{$script:UncItems=@($restoredItems)}
        $queueList.Items.Clear();foreach($item in $restoredItems){if($item){[void]$queueList.Items.Add([string]$item)}}
        Update-Dashboard
        $status.Text=T 'QueueLoadSuccess' 'Saved queue opened: {0}' @($dlg.FileName);$status.ForeColor=[Drawing.Color]::FromArgb(23,112,77)
    }catch{[Windows.Forms.MessageBox]::Show((T 'QueueLoadFailed' 'Could not open the queue package: {0}' @($_.Exception.Message)),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null}
    finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue;$dlg.Dispose()}
}

function Load-WorkItems {
    if($rAll.Checked){
        $folder=$tempSource.Text.Trim();if([string]::IsNullOrWhiteSpace($folder) -or -not(Test-Path -LiteralPath $folder -PathType Container)){throw(T 'TemporarySource' 'Temporary source folder')}
        $selectedFormats=@(Get-SelectedVideoFormatsFromUi)
        if($selectedFormats.Count-eq0){throw(T 'NoVideoFormatsSelected' 'No file formats are selected. Select at least one file format on the Options tab.')}
        $files=@(Get-ChildItem -LiteralPath $folder -File -Recurse -ErrorAction Stop|Where-Object{$selectedFormats -contains $_.Extension.ToLowerInvariant()}|Sort-Object FullName)
        $queueList.Items.Clear();foreach($file in $files){[void]$queueList.Items.Add($file.FullName)};Save-VisibleWorkList
        $status.Text=T 'LocalFilesLoadedSelectedFormats' 'Loaded {0} local file(s) matching the selected file formats.' @(@($files).Count);$status.ForeColor=[Drawing.Color]::FromArgb(23,112,77)
    }else{
        $folder=Select-Folder ''
        if($folder){
            $folder=$folder.TrimEnd('\')
            if(-not $queueList.Items.Contains($folder)){
                [void]$queueList.Items.Add($folder)
                $queueList.SelectedIndex=$queueList.Items.Count-1
            }
            # Save immediately. Otherwise the refresh timer reads the old
            # queue from settings.json and the newly added folder disappears.
            Save-VisibleWorkList
        }
    }
    Update-Dashboard
}
function Refresh-QueueFromDisk {
    if($rAll.Checked){
        if(-not $script:QueueRunActive){return}
        $includePath=Join-Path $script:Prefs.DataFolder 'all-in-one-files.json'
        if(-not(Test-Path -LiteralPath $includePath -PathType Leaf)){return}
        $disk=@((Read-Json $includePath @()))
        $current=@(Get-ListItems $queueList)
        if(($disk -join "`n") -ne ($current -join "`n")){
            $queueList.Items.Clear()
            foreach($item in $disk){if($item){[void]$queueList.Items.Add([string]$item)}}
            $script:LocalItems=@($disk)
            $saved=Read-Json $script:SettingsPath $null
            if($null -ne $saved){$saved.LocalFileQueue=@($disk);Write-Json $script:SettingsPath $saved}
            Update-Dashboard
        }
        return
    }
    $saved=Read-Json $script:SettingsPath $null;if($null -eq $saved){return};$disk=@(P $saved 'UncQueue' @());$script:UncItems=@($disk);$current=@(Get-ListItems $queueList)
    if(($disk -join "`n") -ne ($current -join "`n")){$queueList.Items.Clear();foreach($item in $disk){if($item){[void]$queueList.Items.Add([string]$item)}};Update-Dashboard}
}
function Set-RunState {
    param([bool]$Running,[switch]$SkipEncoderGateRefresh)
    $script:QueueRunActive=$Running
    if($Running){$bStart.Text=T 'StopQueue' 'Stop queue';$bStart.BackColor=[Drawing.Color]::FromArgb(185,45,45);$bStart.Enabled=$true;if($null-ne$bEncoderCheckFooter){$bEncoderCheckFooter.Enabled=$false}}else{$bStart.Text=T 'StartQueue' 'Start entire queue';$bStart.BackColor=[Drawing.Color]::FromArgb(23,112,77);if($null-ne$bEncoderCheckFooter){$bEncoderCheckFooter.Enabled=$true};if(-not$SkipEncoderGateRefresh){Update-EncoderStartGate}}
    $bOrganize.Enabled = -not $Running
    Update-Dashboard
}
function Stop-Queue {
    $answer=[Windows.Forms.MessageBox]::Show((T 'ConfirmStop' 'Stop the running queue? The active ffmpeg/MediaPrep process will be terminated.'),(T 'StopQueue' 'Stop queue'),[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning);if($answer -ne [Windows.Forms.DialogResult]::Yes){return}
    New-Item -Path $script:StopRequest -ItemType File -Force|Out-Null
    if($script:QueueProcess -and -not $script:QueueProcess.HasExited){Start-Process taskkill.exe -ArgumentList "/PID $($script:QueueProcess.Id) /T /F" -WindowStyle Hidden -Wait}
    Pause-StatisticsRun -Status 'Interrupted'
    Set-RunState $false;$status.Text=T 'QueueStopped' 'Queue was stopped by the user.';$status.ForeColor=[Drawing.Color]::FromArgb(170,40,35)
}
function Show-QueueDashboard {
    if(-not(Test-Path -LiteralPath $script:QueueDashboard -PathType Leaf)){
        $msg=T 'QueueDashboardMissing' 'Queue dashboard script is missing: {0}.' @($script:QueueDashboard)
        $status.Text=$msg;$status.ForeColor=[Drawing.Color]::FromArgb(170,40,35)
        [Windows.Forms.MessageBox]::Show($msg,'MediaPrep')|Out-Null
        return $false
    }
    try{
        # Pass the arguments as one correctly quoted string. This is more reliable in
        # Windows PowerShell 5.1 when Root and the script path contain spaces.
        $dashboardArgs='-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -Root "{1}"' -f $script:QueueDashboard,$script:Root
        if([bool]$script:Settings.VerboseLogging){$dashboardArgs += ' -VerboseLogging'}
        if([bool]$script:Settings.VerboseLogging){
            try{Add-Content -LiteralPath (Join-Path $script:Prefs.LogFolder 'MediaPrep-Queue-Dashboard-Launcher.log') -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' [INFO] '+$dashboardArgs) -Encoding UTF8}catch{}
        }
        $proc=Start-Process -FilePath 'powershell.exe' -ArgumentList $dashboardArgs -WorkingDirectory $script:Root -PassThru -ErrorAction Stop
        if($null -eq $proc){throw 'The queue statistics process could not be started.'}
        $script:QueueDashboardProcess=$proc
        $status.Text=T 'QueueDashboardOpened' 'Queue statistics opened (PID {0}).' @($proc.Id)
        $status.ForeColor=[Drawing.Color]::FromArgb(23,112,77)
        return $true
    }catch{
        $msg=T 'QueueDashboardOpenFailed' 'Could not open queue statistics: {0}' @($_.Exception.Message)
        if([bool]$script:Settings.VerboseLogging){try{Add-Content -LiteralPath (Join-Path $script:Prefs.LogFolder 'MediaPrep-Queue-Dashboard-Launcher.log') -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' [ERROR] '+$msg) -Encoding UTF8}catch{}}
        $status.Text=$msg;$status.ForeColor=[Drawing.Color]::FromArgb(170,40,35)
        [Windows.Forms.MessageBox]::Show($msg,(T 'QueueStatistics' 'Queue statistics'))|Out-Null
        return $false
    }
}


function Hide-QueueDetailWindow {
    try{
        $statePath=Join-Path $script:Prefs.DataFolder 'queue-console-window.json'
        if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){return}
        $state=Read-Json -Path $statePath -Default $null
        if($null-eq$state){return}
        $handleValue=P $state 'Handle' 0
        if($null-eq$handleValue){return}
        $hWnd=[IntPtr]([int64]$handleValue)
        if($hWnd -ne [IntPtr]::Zero){[void][MediaPrep.ConsoleWindow]::ShowWindow($hWnd,0)}
    }catch{}
}
function Stop-QueueDashboardForUserExit {
    param([switch]$IncludeOrphaned)
    # A deliberate Start Center close owns the UI cleanup. The queue process itself
    # remains independent and is never terminated here.
    Hide-QueueDetailWindow
    $targets=@{}
    $proc=$script:QueueDashboardProcess
    if($null-ne$proc){
        try{if(-not$proc.HasExited){$targets[[int]$proc.Id]=$proc}}catch{}
    }
    if($IncludeOrphaned){
        try{
            $rootText=[string]$script:Root
            foreach($row in @(Get-CimInstance Win32_Process -OperationTimeoutSec 3 -ErrorAction Stop | Select-Object ProcessId,Name,CommandLine)){
                if([int]$row.ProcessId -eq [int]$PID){continue}
                if([string]$row.Name -notmatch '^(powershell|pwsh)\.exe$'){continue}
                $cmd=[string]$row.CommandLine
                if($cmd.IndexOf($rootText,[StringComparison]::OrdinalIgnoreCase)-lt0){continue}
                if($cmd -notmatch 'MediaPrep-Queue-Dashboard\.ps1'){continue}
                $found=Get-Process -Id ([int]$row.ProcessId) -ErrorAction SilentlyContinue
                if($null-ne$found){$targets[[int]$row.ProcessId]=$found}
            }
        }catch{}
    }
    foreach($dashboardPid in @($targets.Keys)){
        $target=$targets[$dashboardPid]
        try{
            if($target.HasExited){continue}
            if([bool]$script:Settings.VerboseLogging){
                try{Add-Content -LiteralPath (Join-Path $script:Prefs.LogFolder 'MediaPrep-Queue-Dashboard-Launcher.log') -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')+' [INFO] Start Center requested dashboard close. PID='+$dashboardPid) -Encoding UTF8}catch{}
            }
            $closeRequested=$false
            try{$closeRequested=[bool]$target.CloseMainWindow()}catch{}
            if($closeRequested){try{[void]$target.WaitForExit(1500)}catch{}}
            try{if(-not$target.HasExited){Stop-Process -Id $dashboardPid -Force -ErrorAction SilentlyContinue}}catch{}
        }catch{}
        finally{try{$target.Dispose()}catch{}}
    }
    $script:QueueDashboardProcess=$null
}

function Start-Queue {
    $runRequestedAt=Get-Date
    if($cUpdates.Checked -and -not $script:IsAdministrator){
        [Windows.Forms.MessageBox]::Show((T 'NeedElevationForUpdates' 'Windows Update restart protection is selected but MediaPrep is not running as administrator. Save the option while no queue is running to restart MediaPrep through UAC.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)|Out-Null
        return
    }
    $selectedFormats=@(Get-SelectedVideoFormatsFromUi)
    if($selectedFormats.Count-eq0){
        $tabs.SelectedTab=$tabOptions
        [Windows.Forms.MessageBox]::Show((T 'NoVideoFormatsSelected' 'No file formats are selected. Select at least one file format on the Options tab.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)|Out-Null
        return
    }
    if(-not $rAll.Checked){Build-QueueStatisticsInventory;Update-QueueStatistics -Force}
    $missingTools=@()
    foreach($toolPath in @([string]$script:Prefs.FFmpegPath,[string]$script:Prefs.FFprobePath,[string]$script:Prefs.MkvmergePath)){if([string]::IsNullOrWhiteSpace($toolPath) -or -not(Test-Path -LiteralPath $toolPath)){$missingTools += $toolPath}}
    if($missingTools.Count -gt 0){
        $missingNames=New-Object System.Collections.Generic.List[string]
        if(-not(Test-Path -LiteralPath ([string]$script:Prefs.FFmpegPath) -PathType Leaf)){$missingNames.Add('FFmpeg (ffmpeg.exe)')}
        if(-not(Test-Path -LiteralPath ([string]$script:Prefs.FFprobePath) -PathType Leaf)){$missingNames.Add('FFprobe (ffprobe.exe)')}
        if(-not(Test-Path -LiteralPath ([string]$script:Prefs.MkvmergePath) -PathType Leaf)){$missingNames.Add('MKVToolNix (mkvmerge.exe)')}
        $toolText=($missingNames -join "`r`n - ")
        $message=T 'MissingToolsDetailed' 'MediaPrep is missing required external tools:`r`n`r`n - {0}`r`n`r`nOpen the Settings tab. Under External tools you can download the tools or select the folder where they are already installed.' @($toolText)
        $tabs.SelectedTab=$tabPrefs
        [Windows.Forms.MessageBox]::Show($message,(T 'WindowTitle' 'MediaPrep MKV Toolkit Start Center'),[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)|Out-Null
        return
    }
    if(-not(Test-EncoderReadyForQueue)){return}
    Save-Options
    $job=Get-CurrentSettings
    $job|Add-Member SettingsFile $script:SettingsPath -Force
    if($job.WorkMode -eq 'Queue'){
        if(@($job.UncQueue).Count -eq 0){throw(T 'NeedQueue' 'Add at least one UNC folder to the queue.')}
        $status.Text=T 'CheckingUncQueueAccess' 'Checking access and permissions for all UNC queue folders...'
        $status.ForeColor=[Drawing.Color]::FromArgb(55,95,135)
        [Windows.Forms.Application]::DoEvents()
        if(-not (Test-UncQueueAccess -Paths @($job.UncQueue))){return}
        $status.Text=T 'UncQueueAccessOk' 'All UNC queue folders are accessible with read/write/delete permissions.'
        $status.ForeColor=[Drawing.Color]::FromArgb(23,112,77)
        Build-QueueStatisticsInventory;Update-QueueStatistics -Force
    }else{
        if(@($job.LocalFileQueue).Count -eq 0){throw(T 'NeedFilesSelectedFormats' 'No files matching the selected file formats were found.')}
        if(-not(Test-Path -LiteralPath $job.TemporarySourceFolder -PathType Container)){throw(T 'TemporarySource' 'Temporary source folder')}
        if(-not(Test-Path -LiteralPath $job.TemporaryOutputFolder -PathType Container)){New-Item -Path $job.TemporaryOutputFolder -ItemType Directory -Force|Out-Null}
        $includePath=Join-Path $script:Prefs.DataFolder 'all-in-one-files.json';Write-Json $includePath @($job.LocalFileQueue);$job|Add-Member IncludeListPath $includePath -Force
    }
    if($job.ShutdownAfterSuccess){$answer=[Windows.Forms.MessageBox]::Show((T 'ConfirmShutdown' 'The computer will shut down after the entire queue completes without errors. Continue?'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning);if($answer -ne [Windows.Forms.DialogResult]::Yes){return}}
    Start-StatisticsRun -QueueRoots $(if($job.WorkMode -eq 'Queue'){@($job.UncQueue)}else{@('Local / All in one')}) -RunStart $runRequestedAt
    Remove-Item $script:StopRequest -Force -ErrorAction SilentlyContinue;$job|Add-Member StopRequestFile $script:StopRequest -Force
    $stamp=Get-Date -Format 'yyyy-MM-dd_HH-mm-ss';$queueLog=Join-Path $script:Prefs.LogFolder ("MediaPrep-Queue_{0}.log" -f $stamp);$job|Add-Member QueueLogPath $queueLog -Force
    Write-Json $script:SettingsPath $job;Write-Json $script:JobPath $job
    $startInfo=New-Object Diagnostics.ProcessStartInfo;$startInfo.FileName='powershell.exe';$startInfo.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$script:QueueHost+'" -JobFile "'+$script:JobPath+'" -LogFile "'+$queueLog+'"';$startInfo.WorkingDirectory=$script:Root;$startInfo.UseShellExecute=$true
    $script:QueueProcess=[Diagnostics.Process]::Start($startInfo);if($null -eq $script:QueueProcess){throw 'Queue process could not be started.'};Set-RunState $true;$tabs.SelectedTab=$tabDash
    [Windows.Forms.Application]::DoEvents()
    [void](Show-QueueDashboard)
}

$bStats.Add_Click({Show-QueueDashboard})
$bSaveQueue.Add_Click({try{Save-QueuePackageInteractive}catch{Show-GuiError -ErrorRecord $_ -Context 'Save queue package'}})
$bOpenQueue.Add_Click({try{Load-QueuePackageInteractive}catch{Show-GuiError -ErrorRecord $_ -Context 'Open queue package'}})
$bLoad.Add_Click({try{Load-WorkItems}catch{Show-GuiError -ErrorRecord $_ -Context 'Load work items'}})
$bRemove.Add_Click({
    try {
        $selectedIndex = [int]$queueList.SelectedIndex
        if ($selectedIndex -ge 0) {
            $queueList.Items.RemoveAt($selectedIndex)
            $remainingCount = @($queueList.Items).Count
            if ($remainingCount -gt 0) {
                $queueList.SelectedIndex = [Math]::Min($selectedIndex, $remainingCount - 1)
            }
            Save-VisibleWorkList
        }
    }
    catch { Show-GuiError -ErrorRecord $_ -Context 'Remove work item' }
})
$bUp.Add_Click({
    try {
        $index=[int]$queueList.SelectedIndex
        if($index -gt 0){$value=$queueList.Items[$index];$queueList.Items.RemoveAt($index);$queueList.Items.Insert($index-1,$value);$queueList.SelectedIndex=$index-1;Save-VisibleWorkList}
    }
    catch { Show-GuiError -ErrorRecord $_ -Context 'Move work item up' }
})
$bDown.Add_Click({
    try {
        $index=[int]$queueList.SelectedIndex
        $count=@($queueList.Items).Count
        if($index -ge 0 -and $index -lt ($count-1)){$value=$queueList.Items[$index];$queueList.Items.RemoveAt($index);$queueList.Items.Insert($index+1,$value);$queueList.SelectedIndex=$index+1;Save-VisibleWorkList}
    }
    catch { Show-GuiError -ErrorRecord $_ -Context 'Move work item down' }
})
$sourceBrowse.Add_Click({$value=Select-Folder $tempSource.Text;if($value){$tempSource.Text=$value}})
$outputBrowse.Add_Click({$value=Select-Folder $tempOutput.Text;if($value){$tempOutput.Text=$value}})
$bOpenLog.Add_Click({if(Test-Path $script:Prefs.LogFolder){Start-Process explorer.exe -ArgumentList ('"'+$script:Prefs.LogFolder+'"')}})
$bPrefsLogs.Add_Click({if(Test-Path $script:Prefs.LogFolder){Start-Process explorer.exe -ArgumentList ('"'+$script:Prefs.LogFolder+'"')}})
$bOpenOutput.Add_Click({$folder=if($rAll.Checked){$tempOutput.Text}else{$script:Prefs.OutputFolder};if(Test-Path $folder){Start-Process explorer.exe -ArgumentList ('"'+$folder+'"')}})
$bOrganize.Add_Click({try{Invoke-OrganizeOutputFolder}catch{Show-GuiError -ErrorRecord $_ -Context 'Organize output folder'}})
$bSaveOptions.Add_Click({
    try{
        $oldPrevent=[bool](Get-PersistedPreventUpdateRestart)
        $newPrevent=[bool]$cUpdates.Checked
        if($script:QueueRunActive -and ($oldPrevent -ne $newPrevent)){
            $cUpdates.Checked=$oldPrevent
            [Windows.Forms.MessageBox]::Show((T 'CannotChangeUpdateProtectionWhileRunning' 'Windows Update restart protection cannot be changed while a queue is running. Change and save this option after the queue has stopped or completed.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null
            return
        }
        Save-VisibleWorkList
        Save-Options
        $status.Text=T 'SettingsSaved' 'Options were saved.'
        $status.ForeColor=[Drawing.Color]::FromArgb(23,112,77)
        if($newPrevent -and -not $script:IsAdministrator){[void](Request-ElevatedRestartAfterSave)}
    }catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'MediaPrep')|Out-Null}
})

$optionsFooter.Add_Resize({
    $bSaveOptions.Left = [Math]::Max(10, $optionsFooter.ClientSize.Width - $bSaveOptions.Width - 15)
})
$preferencesFooter.Add_Resize({
    $bSavePrefs.Left = [Math]::Max(10, $preferencesFooter.ClientSize.Width - $bSavePrefs.Width - 15)
})
$prefPanel.Add_Resize({
    $gap=12
    $leftWidth=[Math]::Max(610,[Math]::Min(690,[int]($prefPanel.ClientSize.Width*0.60)))
    $leftPrefs.Width=$leftWidth
    $rightPrefs.Left=$leftPrefs.Right+$gap
    $rightPrefs.Width=[Math]::Max(420,$prefPanel.ClientSize.Width-$rightPrefs.Left-8)
    foreach($rowControl in $script:PrefRowControls){
        $rowControl.Button.Left=14
        $rowControl.Button.Width=195
        $rowControl.Box.Left=220
        $rowControl.Box.Width=[Math]::Max(265,$leftPrefs.ClientSize.Width-273)
        $rowControl.Status.Left=$leftPrefs.ClientSize.Width-48
    }
    $langCombo.Width=375
    $languageVersion.Width=375
    $toolManagerButton.Width=375
    $bRefreshTools.Width=375
    $bStats.Width=375
    $bPrefsLogs.Width=375
})


$bSavePrefs.Add_Click({
    try{
        $oldFFmpegPath=[string]$script:Prefs.FFmpegPath;$oldFFprobePath=[string]$script:Prefs.FFprobePath;$oldMkvmergePath=[string]$script:Prefs.MkvmergePath
        foreach($key in $script:PrefBoxes.Keys){$script:Prefs.$key=$script:PrefBoxes[$key].Text.Trim()}
        if($oldFFmpegPath-ne[string]$script:Prefs.FFmpegPath -or $oldFFprobePath-ne[string]$script:Prefs.FFprobePath -or $oldMkvmergePath-ne[string]$script:Prefs.MkvmergePath){Clear-EncoderSessionSignature}
        $oldLanguage=[string]$script:Prefs.Language;$oldTheme=[string]$script:Prefs.Theme;$oldCustomBanner=[string]$script:Prefs.CustomThemeBanner;$oldCustomPanel=[string]$script:Prefs.CustomThemePanel;$oldCustomBackground=[string]$script:Prefs.CustomThemeBackground
        if($langCombo.SelectedItem){$script:Prefs.Language=[string]$langCombo.SelectedItem.Code}
        if($themeCombo.SelectedItem){$script:Prefs.Theme=[string]$themeCombo.SelectedItem.Code}
        $script:Prefs.CustomThemeBanner=$customBanner.Text.Trim();$script:Prefs.CustomThemePanel=$customPanel.Text.Trim();$script:Prefs.CustomThemeBackground=$customBackground.Text.Trim()
        Write-Json $script:PreferencesPath $script:Prefs;Apply-Prefs-ToConfig;Update-PathAndProgramStatus
        $themeColorsChanged=($oldCustomBanner-ne[string]$script:Prefs.CustomThemeBanner -or $oldCustomPanel-ne[string]$script:Prefs.CustomThemePanel -or $oldCustomBackground-ne[string]$script:Prefs.CustomThemeBackground)
        $restartNeeded=($oldLanguage-ne[string]$script:Prefs.Language -or $oldTheme-ne[string]$script:Prefs.Theme -or ([string]$script:Prefs.Theme-eq'Custom' -and $themeColorsChanged))
        if($restartNeeded){
            if($script:QueueRunActive){$status.Text=T 'ThemeSavedRestartLater' 'The setting was saved. Theme/language will apply after the next restart because the queue is running.';$status.ForeColor=[Drawing.Color]::FromArgb(155,90,20);return}
            Save-VisibleWorkList
            $startInfo=New-Object Diagnostics.ProcessStartInfo;$startInfo.FileName='powershell.exe';$startInfo.Arguments='-NoProfile -ExecutionPolicy Bypass -STA -File "'+(Join-Path $script:AppFolder 'MediaPrep-Start.ps1')+'"';$startInfo.WorkingDirectory=$script:Root;$startInfo.UseShellExecute=$true;[Diagnostics.Process]::Start($startInfo)|Out-Null;$script:SuppressDashboardShutdownOnClose=$true;$form.Close();return
        }
        $status.Text=T 'PreferencesSaved' 'Preferences were saved. The interface language is being reloaded.';$status.ForeColor=[Drawing.Color]::FromArgb(23,112,77)
    }catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'MediaPrep')|Out-Null}
})
$bStart.Add_Click({try{if($script:QueueRunActive){Stop-Queue}else{Start-Queue}}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null}})
$bClose.Add_Click({$form.Close()})
$rQueue.Add_CheckedChanged({if($rQueue.Checked){Refresh-WorkMode}});$rAll.Add_CheckedChanged({if($rAll.Checked){Refresh-WorkMode}})
foreach($control in @($rFull,$rAnalyze,$rEncode,$cMux,$cEncode,$cForce,$cReanalyze,$cRebuild,$cCloseConsole,$cDelete,$cShutdown,$cSleep,$cUpdates,$cVerbose,$cIgnoreDecodeErrors,$cProcessErrorQueue)){$control.Add_CheckedChanged({Update-Dashboard})}
$cUpdates.Enabled=$true

$form.Add_Shown({
    $queueStatsPanel.Visible=$true;$queueStatsPanel.BringToFront();Set-QueueStatisticsDisplay;Update-QueueStatistics -Force
    Write-StartupTrace 'StartCenterShown'
    $script:StartupTimingActive=$false
    if(-not[string]::IsNullOrWhiteSpace([string]$script:SplashSignalPath)){
        $script:SplashStopTimer=New-Object Windows.Forms.Timer
        $script:SplashStopTimer.Interval=1000
        $script:SplashStopTimer.Add_Tick({
            try{$script:SplashStopTimer.Stop();$script:SplashStopTimer.Dispose()}catch{}
            $script:SplashStopTimer=$null
            Stop-MediaPrepSplash
            Write-StartupTrace 'SplashStopSignaled' '1 second after Start Center Shown'
            Show-MediaPrepUpdateResult
        })
        $script:SplashStopTimer.Start()
    }else{Show-MediaPrepUpdateResult}
})
$timer=New-Object Windows.Forms.Timer;$timer.Interval=1500;$timer.Add_Tick({Refresh-BannerRuntimeInfo;Refresh-QueueFromDisk;Update-QueueStatistics;if($script:QueueRunActive -and $script:QueueProcess){try{if($script:QueueProcess.HasExited){$exitCode=$script:QueueProcess.ExitCode;$script:QueueProcess.Dispose();$script:QueueProcess=$null;Pause-StatisticsRun -Status 'Idle';Set-RunState $false;Refresh-QueueFromDisk;if($exitCode -eq 0){$status.Text=T 'QueueComplete' 'Queue completed successfully.';$status.ForeColor=[Drawing.Color]::FromArgb(23,112,77)}elseif($exitCode -eq 2){$status.Text=T 'QueueStopped' 'Queue was stopped by the user.';$status.ForeColor=[Drawing.Color]::FromArgb(155,90,20)}else{$status.Text=T 'QueueFailed' 'Queue ended with exit code {0}. Check the queue log.' @($exitCode);$status.ForeColor=[Drawing.Color]::FromArgb(170,40,35)}}}catch{}}});$timer.Start();$form.Add_FormClosing({param($sender,$e);if($e.CloseReason -eq [Windows.Forms.CloseReason]::UserClosing -and -not$script:SuppressDashboardShutdownOnClose){Stop-QueueDashboardForUserExit}});$form.Add_FormClosed({$timer.Stop();$timer.Dispose();try{if($script:SplashStopTimer){$script:SplashStopTimer.Stop();$script:SplashStopTimer.Dispose()}}catch{};Stop-MediaPrepSplash;Write-StartupTrace 'FormClosed';Finalize-StatisticsSession})

Start-StartupTiming 'ApplySettings'
try{Apply-Settings $script:Settings}finally{Stop-StartupTiming 'ApplySettings'}
Start-StartupTiming 'ApplyControlTheme'
try{Apply-ControlTheme $form}finally{Stop-StartupTiming 'ApplyControlTheme'}
# Restore status colors that are semantic rather than theme colors.
Start-StartupTiming 'UpdatePathAndProgramStatus'
try{Update-PathAndProgramStatus}finally{Stop-StartupTiming 'UpdatePathAndProgramStatus'}
Start-StartupTiming 'UpdateCustomThemeSwatches'
try{Update-AllCustomThemeSwatches}finally{Stop-StartupTiming 'UpdateCustomThemeSwatches'}
Start-StartupTiming 'RefreshEncoderTab'
try{Refresh-EncoderTab}finally{Stop-StartupTiming 'RefreshEncoderTab'}
# Ensure that the CPU/GPU controls stay above themed panels. The proven 0.11.51 layout is unchanged.
Start-StartupTiming 'RestoreEncoderControlZOrder'
try{$encoderCheckButton.Visible=$true;$encoderCheckButton.BringToFront();$encoderRefreshButton.Visible=$true;$encoderRefreshButton.BringToFront();$encoderDetailGroup.Visible=$true;$encoderDetailGroup.BringToFront()}finally{Stop-StartupTiming 'RestoreEncoderControlZOrder'}
# Restore the banner after recursive theming.
Start-StartupTiming 'RestoreBannerTheme'
try{$header.BackColor=$script:ThemePalette.Banner;$title.ForeColor=$script:ThemePalette.BannerText;$subtitle.ForeColor=$script:ThemePalette.BannerText;$processLabel.ForeColor=$script:ThemePalette.BannerText;$version.ForeColor=$script:ThemePalette.BannerText;$toolVersionLabel.ForeColor=$script:ThemePalette.BannerText;$author.ForeColor=$script:ThemePalette.BannerText}finally{Stop-StartupTiming 'RestoreBannerTheme'}
Start-StartupTiming 'RefreshBannerRuntimeInfo'
try{Refresh-BannerRuntimeInfo -RefreshTools}finally{Stop-StartupTiming 'RefreshBannerRuntimeInfo'}
$bStart.BackColor=[Drawing.Color]::FromArgb(23,112,77);$bStart.ForeColor=[Drawing.Color]::White
Start-StartupTiming 'RegisterChoiceTextState'
try{Register-ChoiceTextState @($rQueue,$rAll,$rFull,$rAnalyze,$rEncode,$cMux,$cEncode,$cForce,$cReanalyze,$cRebuild,$cIgnoreDecodeErrors,$cProcessErrorQueue,$cCloseConsole,$cSleep,$cShutdown,$cUpdates,$cVerbose,$cDelete,$cFormatTs,$cFormatMp4,$cFormatAvi,$cFormatMpg,$cFormatMpeg,$cFormatMkv)}finally{Stop-StartupTiming 'RegisterChoiceTextState'}
Start-StartupTiming 'RefreshWorkMode'
try{Refresh-WorkMode}finally{Stop-StartupTiming 'RefreshWorkMode'}
# Synchronize package version metadata while preserving all user preferences.
Start-StartupTiming 'WritePreferences'
try{Write-Json $script:PreferencesPath $script:Prefs}finally{Stop-StartupTiming 'WritePreferences'}
Start-StartupTiming 'ApplyPrefsToConfig'
try{Apply-Prefs-ToConfig}finally{Stop-StartupTiming 'ApplyPrefsToConfig'}
Start-StartupTiming 'SetRunState'
try{Set-RunState $false -SkipEncoderGateRefresh}finally{Stop-StartupTiming 'SetRunState'}
$status.Text=if($script:IsAdministrator){T 'AdminAvailable' 'Start Center is running as administrator. All protection options are available.'}else{T 'AdminUnavailable' 'Start Center is not elevated. Windows Update restart protection is disabled.'}
$status.ForeColor=if($script:IsAdministrator){[Drawing.Color]::FromArgb(23,112,77)}else{[Drawing.Color]::FromArgb(155,90,20)}
$form.AcceptButton=$bStart;$form.CancelButton=$bClose
Write-StartupTrace 'BeforeShowDialog'
[void]$form.ShowDialog()
