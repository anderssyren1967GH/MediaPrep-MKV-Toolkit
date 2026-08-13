#requires -Version 5.1
param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    [switch]$VerboseLogging
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if (-not ('MediaPrep.DashboardNative' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace MediaPrep {
    public static class DashboardNative {
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    }
}
"@
}
# Hide the dashboard PowerShell host. Only the WinForms queue monitor should be visible.
try {
    $ownConsole=[MediaPrep.DashboardNative]::GetConsoleWindow()
    if($ownConsole -ne [IntPtr]::Zero){[void][MediaPrep.DashboardNative]::ShowWindow($ownConsole,0)}
}catch{}
Set-StrictMode -Version 2.0
$ErrorActionPreference='SilentlyContinue'

$data=Join-Path $Root 'Data'
$inventoryPath=Join-Path $data 'queue-dashboard-inventory.json'
$errorPath=Join-Path $data 'error-queue.json'
$copyStatsPath=Join-Path $data 'queue-copy-stats.json'
$runPath=Join-Path $data 'queue-run-current.json'
$statisticsSessionPath=Join-Path $data 'statistics-run-current.json'
$statisticsArchiveFolder=Join-Path $data 'Statistics'
$script:StatisticsViewPath=$statisticsSessionPath
$script:ArchiveView=$false
$errorFolder=Join-Path $Root 'Error'
$queueConsoleStatePath=Join-Path $data 'queue-console-window.json'
$ffprobePath=Join-Path $Root 'Tools\FFmpeg\ffprobe.exe'
$processedFolder=Join-Path $Root 'Processed'
$unprocessedFolder=Join-Path $Root 'UnProcessed'
$tempFolder=Join-Path $data 'Temp'
$script:QueueConsoleVisible=$false
$script:MissingJsonLogged=@{}
$script:LanguageSchemaVersion=1
$script:RequiredLanguageFileVersion='1.6.0'
$script:FallbackLanguageCulture='en-US'
$script:LanguageBase=[pscustomobject]@{}
$script:L=[pscustomobject]@{}
$script:ResolvedLanguageCode='en-US'
$script:LanguageFileIsCurrent=$false
function Get-LanguageProperty([object]$Object,[string]$Name,$Default=$null){
    if($null-eq$Object){return $Default};$p=$Object.PSObject.Properties[$Name];if($null-eq$p){return $Default};return $p.Value
}
function Normalize-LanguagePreference([string]$Code){
    if([string]::IsNullOrWhiteSpace($Code)){return 'system'};$value=$Code.Trim()
    switch($value.ToLowerInvariant()){
        'system'{return 'system'}
        'default'{return 'system'}
        'en'{return 'en-US'}
        'english'{return 'en-US'}
        'en-us'{return 'en-US'}
        'sv'{return 'sv-SE'}
        'swedish'{return 'sv-SE'}
        'svenska'{return 'sv-SE'}
        'sv-se'{return 'sv-SE'}
    }
    try{return ([Globalization.CultureInfo]::GetCultureInfo($value)).Name}catch{return $value}
}
function Get-LanguagePath([string]$Culture){return(Join-Path (Join-Path $Root 'Languages') ("mediaprep.{0}.json" -f $Culture))}
function Read-LanguageDocument([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
    try{$doc=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
    if($null-eq$doc){return $null}
    try{$schema=[int](Get-LanguageProperty $doc 'SchemaVersion' -1)}catch{return $null}
    if($schema-ne$script:LanguageSchemaVersion){return $null}
    if([string]::IsNullOrWhiteSpace([string](Get-LanguageProperty $doc 'Culture' '')) -or [string]::IsNullOrWhiteSpace([string](Get-LanguageProperty $doc 'LanguageFileVersion' ''))){return $null}
    return $doc
}
function Get-InstalledLanguageDocuments{
    $result=New-Object System.Collections.Generic.List[object];$folder=Join-Path $Root 'Languages'
    foreach($file in @(Get-ChildItem -LiteralPath $folder -Filter 'mediaprep.*.json' -File -ErrorAction SilentlyContinue)){
        $doc=Read-LanguageDocument $file.FullName;if($null-eq$doc){continue}
        $culture=[string](Get-LanguageProperty $doc 'Culture' '');if([string]::IsNullOrWhiteSpace($culture)){continue}
        $result.Add([pscustomobject]@{Path=$file.FullName;Culture=$culture;Document=$doc})
    }
    return @($result.ToArray())
}
function Get-SystemLanguageCode{
    $installed=@(Get-InstalledLanguageDocuments);$culture=[Globalization.CultureInfo]::CurrentUICulture
    foreach($entry in $installed){if([string]$entry.Culture -ieq $culture.Name){return [string]$entry.Culture}}
    foreach($entry in $installed){
        try{$c=[Globalization.CultureInfo]::GetCultureInfo([string]$entry.Culture);if($c.TwoLetterISOLanguageName -ieq $culture.TwoLetterISOLanguageName){return [string]$entry.Culture}}catch{}
    }
    return $script:FallbackLanguageCulture
}
function Initialize-DashboardLanguage{
    $requested='system'
    foreach($prefPath in @((Join-Path $data 'mediaprep.preferences.json'),(Join-Path $data 'config.json'))){
        if(-not(Test-Path -LiteralPath $prefPath -PathType Leaf)){continue}
        try{$o=Get-Content -LiteralPath $prefPath -Raw -Encoding UTF8|ConvertFrom-Json;if($o.PSObject.Properties['Language'] -and $o.Language){$requested=[string]$o.Language;break}}catch{}
    }
    $requested=Normalize-LanguagePreference $requested
    $baseDoc=Read-LanguageDocument (Get-LanguagePath $script:FallbackLanguageCulture)
    if($null-eq$baseDoc){$baseDoc=[pscustomobject]@{}}
    $script:LanguageBase=$baseDoc
    $resolved=if($requested-eq'system'){Get-SystemLanguageCode}else{$requested}
    $selected=Read-LanguageDocument (Get-LanguagePath $resolved)
    if($null-eq$selected){$resolved=$script:FallbackLanguageCulture;$selected=$baseDoc}
    if($null-eq$selected){$selected=[pscustomobject]@{}}
    $script:L=$selected;$script:ResolvedLanguageCode=$resolved
    $script:LanguageFileIsCurrent=([string](Get-LanguageProperty $selected 'LanguageFileVersion' '') -eq $script:RequiredLanguageFileVersion)
}
function T {
    param([string]$Key,[string]$Fallback,[object[]]$FormatArgs=@())
    $bp = if($script:LanguageBase){$script:LanguageBase.PSObject.Properties[$Key]}else{$null}
    $base = if($bp -and -not [string]::IsNullOrWhiteSpace([string]$bp.Value)){[string]$bp.Value}else{$Fallback}
    $p = if($script:L){$script:L.PSObject.Properties[$Key]}else{$null}
    $v = if($p -and -not [string]::IsNullOrWhiteSpace([string]$p.Value)){[string]$p.Value}else{$base}
    $a = @($FormatArgs)
    if($a.Count -gt 0){
        try { return [string]::Format([Globalization.CultureInfo]::CurrentCulture,$v,$a) } catch {}
        if($v -ne $base){
            try { return [string]::Format([Globalization.CultureInfo]::CurrentCulture,$base,$a) } catch {}
        }
        try { return [string]::Format([Globalization.CultureInfo]::CurrentCulture,$Fallback,$a) } catch { return $Fallback }
    }
    return $v
}
Initialize-DashboardLanguage

$logFolder=Join-Path $Root 'Loggar'
$dashboardLogPath=$null
try{
    if(-not(Test-Path -LiteralPath $logFolder -PathType Container)){New-Item -Path $logFolder -ItemType Directory -Force|Out-Null}
    $dashboardLogPath=Join-Path $logFolder ("MediaPrep-Queue-Dashboard_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
}catch{}
function Write-DashboardLog([string]$Level,[string]$Message){
    if([string]::IsNullOrWhiteSpace($dashboardLogPath)){return}
    if($Level -eq 'VERBOSE' -and -not $VerboseLogging){return}
    try{
        $line='{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$Level,$Message
        Add-Content -LiteralPath $dashboardLogPath -Value $line -Encoding UTF8
    }catch{}
}
Write-DashboardLog 'INFO' ("Dashboard start. Root='{0}' PID={1}" -f $Root,$PID)

function Read-Json([string]$p,[object]$fallback){
    if(-not(Test-Path -LiteralPath $p -PathType Leaf)){
        # Some statistics files do not exist yet during startup. Log this only
        # once per file instead of once per second.
        if(-not $script:MissingJsonLogged.ContainsKey($p)){
            Write-DashboardLog 'VERBOSE' ("JSON does not exist yet: {0}" -f $p)
            $script:MissingJsonLogged[$p]=$true
        }
        return $fallback
    }
    elseif($script:MissingJsonLogged.ContainsKey($p)){
        $script:MissingJsonLogged.Remove($p)
        Write-DashboardLog 'VERBOSE' ("JSON is now available: {0}" -f $p)
    }
    try{return (Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json)}
    catch{
        Write-DashboardLog 'ERROR' ("Could not read JSON '{0}': {1}" -f $p,$_.Exception.Message)
        return $fallback
    }
}
function Save-JsonAtomic([string]$Path,[object]$Value){
    try{
        $dir=Split-Path -Parent $Path
        if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -Path $dir -ItemType Directory -Force|Out-Null}
        $tmp=$Path+'.tmp'
        $json=$Value|ConvertTo-Json -Depth 16
        [IO.File]::WriteAllText($tmp,$json,(New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $Path -Force
        return $true
    }catch{
        Write-DashboardLog 'ERROR' ("Could not save JSON '{0}': {1}" -f $Path,$_.Exception.Message)
        return $false
    }
}
function Find-InventoryItem([object]$Doc,[string]$RelativePath){
    if($null-eq$Doc -or -not$Doc.PSObject.Properties['items']){return $null}
    $key=Get-RelativeKey $RelativePath
    foreach($it in @($Doc.items)){
        if((Get-RelativeKey ([string](Get-ObjectProperty $it 'RelativePath' ''))) -eq $key){return $it}
    }
    return $null
}
function Set-ObjectProperty($Object,[string]$Name,$Value){
    if($null-eq$Object){return}
    if($Object.PSObject.Properties[$Name]){$Object.$Name=$Value}else{$Object|Add-Member -NotePropertyName $Name -NotePropertyValue $Value}
}
function Remove-ErrorRecord([string]$RelativePath){
    $records=@(Read-Json $errorPath @())
    $key=Get-RelativeKey $RelativePath
    $kept=@($records|Where-Object{(Get-RelativeKey ([string](Get-ObjectProperty $_ 'RelativePath' ''))) -ne $key})
    [void](Save-JsonAtomic $errorPath @($kept))
}
function Get-VideoCodec([string]$Path){
    if(-not(Test-Path -LiteralPath $ffprobePath -PathType Leaf) -or -not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''}
    try{
        $v=& $ffprobePath -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 -- $Path 2>$null|Select-Object -First 1
        return ([string]$v).Trim().ToLowerInvariant()
    }catch{return ''}
}
function Get-SelectedErrorContext{
    if($egrid.SelectedRows.Count -lt 1){return $null}
    $row=$egrid.SelectedRows[0]
    if($null-ne$row.Tag){return $row.Tag}
    return $null
}
function Get-ReviewPath($Context){
    $it=$Context.InventoryItem
    $err=$Context.ErrorRecord
    $candidates=New-Object System.Collections.Generic.List[string]
    if($null-ne$it){
        $lo=[string](Get-ObjectProperty $it 'LocalOutput' '')
        if(-not[string]::IsNullOrWhiteSpace($lo)){$candidates.Add($lo)}
    }
    if($null-ne$err){
        $ep=[string](Get-ObjectProperty $err 'ErrorPath' '')
        if(-not[string]::IsNullOrWhiteSpace($ep) -and [IO.Path]::GetExtension($ep) -ieq '.mkv'){$candidates.Add($ep)}
    }
    $rel=[string]$Context.RelativePath
    if(-not[string]::IsNullOrWhiteSpace($rel)){
        $mkvRel=[IO.Path]::ChangeExtension($rel,'.mkv')
        $candidates.Add((Join-Path $processedFolder $mkvRel))
        $candidates.Add((Join-Path $errorFolder $mkvRel))
    }
    foreach($c in $candidates){if(Test-Path -LiteralPath $c -PathType Leaf){return $c}}
    return ''
}
function Review-SelectedError{
    $ctx=Get-SelectedErrorContext
    if($null-eq$ctx){[Windows.Forms.MessageBox]::Show((T 'DashboardNoErrorSelection' 'Select a file in the error queue first.'),'MediaPrep')|Out-Null;return}
    $path=Get-ReviewPath $ctx
    if([string]::IsNullOrWhiteSpace($path)){
        [Windows.Forms.MessageBox]::Show('Ingen lokal MKV hittades att granska.','MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null
        return
    }
    try{Start-Process -FilePath $path;Write-DashboardLog 'INFO' ("Review: {0}" -f $path)}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'MediaPrep')|Out-Null}
}
function Continue-SelectedError{
    $ctx=Get-SelectedErrorContext
    if($null-eq$ctx){[Windows.Forms.MessageBox]::Show((T 'DashboardNoErrorSelection' 'Select a file in the error queue first.'),'MediaPrep')|Out-Null;return}
    $rel=[string]$ctx.RelativePath
    $doc=Read-Json $inventoryPath $null
    $it=Find-InventoryItem $doc $rel
    if($null-eq$it){[Windows.Forms.MessageBox]::Show((T 'DashboardInventoryItemMissing' 'The queue item could not be found in the inventory.'),'MediaPrep')|Out-Null;return}
    $err=$ctx.ErrorRecord
    $localOut=[string](Get-ObjectProperty $it 'LocalOutput' '')
    $localSrc=[string](Get-ObjectProperty $it 'LocalSource' '')
    $errorFile=if($null-ne$err){[string](Get-ObjectProperty $err 'ErrorPath' '')}else{''}

    # If the error queue actually contains the file, restore it to its normal local path first.
    if(-not[string]::IsNullOrWhiteSpace($errorFile) -and (Test-Path -LiteralPath $errorFile -PathType Leaf)){
        $ext=[IO.Path]::GetExtension($errorFile)
        $dest=if($ext -ieq '.mkv'){$localOut}else{$localSrc}
        if(-not[string]::IsNullOrWhiteSpace($dest) -and -not[string]::Equals($errorFile,$dest,[StringComparison]::OrdinalIgnoreCase)){
            $dd=Split-Path -Parent $dest
            if(-not(Test-Path -LiteralPath $dd -PathType Container)){New-Item -Path $dd -ItemType Directory -Force|Out-Null}
            if(Test-Path -LiteralPath $dest -PathType Leaf){Remove-Item -LiteralPath $dest -Force}
            Move-Item -LiteralPath $errorFile -Destination $dest -Force
        }
    }

    $stage=0;$qstatus='Waiting';$final=$null
    $errorKind=[string](Get-ObjectProperty $it 'ErrorKind' '')
    $previousStage=0
    try{$previousStage=[int](Get-ObjectProperty $it 'ErrorPreviousStage' 0)}catch{$previousStage=0}
    if(-not[string]::IsNullOrWhiteSpace($localOut) -and (Test-Path -LiteralPath $localOut -PathType Leaf)){
        $codec=Get-VideoCodec $localOut
        if([string]::IsNullOrWhiteSpace($codec)){
            [Windows.Forms.MessageBox]::Show((T 'DashboardMkvVerifyFailed' 'The local MKV could not be verified with ffprobe. The file remains in the error queue.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)|Out-Null
            return
        }
        $fi=Get-Item -LiteralPath $localOut -ErrorAction SilentlyContinue
        if($null-ne$fi){$final=[int64]$fi.Length}
        if($errorKind -eq 'Publish' -or $previousStage -ge 8){
            # The file is already complete locally; only the return copy failed.
            $stage=8;$qstatus='WaitingForReturn'
        }elseif($codec -eq 'hevc'){
            $stage=7;$qstatus='Encoded';Set-ObjectProperty $it 'EncodedSize' $final
        }else{
            $stage=4;$qstatus='Muxed';Set-ObjectProperty $it 'MuxedSize' $final
        }
        if($null-ne$final){Set-ObjectProperty $it 'FinalSize' $final}
    }elseif(-not[string]::IsNullOrWhiteSpace($localSrc) -and (Test-Path -LiteralPath $localSrc -PathType Leaf)){
        $stage=2;$qstatus='LocalSourceReady'
    }
    Set-ObjectProperty $it 'QueueStage' $stage
    Set-ObjectProperty $it 'QueueStatus' $qstatus
    Set-ObjectProperty $it 'ErrorMessage' $null
    Set-ObjectProperty $it 'ErrorKind' $null
    Set-ObjectProperty $it 'ErrorPreviousStage' $null
    Set-ObjectProperty $it 'ErrorLocalPath' $null
    Set-ObjectProperty $it 'ManualOverride' 'Continue'
    Set-ObjectProperty $it 'ManualOverrideUtc' ((Get-Date).ToUniversalTime().ToString('o'))
    Set-ObjectProperty $it 'UpdatedUtc' ((Get-Date).ToUniversalTime().ToString('o'))
    if($doc.PSObject.Properties['errors']){$doc.errors=[int]@($doc.items|Where-Object{[int](Get-ObjectProperty $_ 'QueueStage' 0)-ge90}).Count}
    if($doc.PSObject.Properties['updatedUtc']){$doc.updatedUtc=(Get-Date).ToUniversalTime().ToString('o')}
    if(-not(Save-JsonAtomic $inventoryPath $doc)){return}
    Remove-ErrorRecord $rel
    Write-DashboardLog 'INFO' ("Manual continue: {0}; new stage={1} {2}" -f $rel,$stage,$qstatus)
    Refresh-Dashboard
}
function Test-IsSafeLocalPath([string]$Path){
    if([string]::IsNullOrWhiteSpace($Path)){return $false}
    if($Path.StartsWith('\\')){return $false}
    try{return ([IO.Path]::GetFullPath($Path)).StartsWith([IO.Path]::GetFullPath($Root),[StringComparison]::OrdinalIgnoreCase)}catch{return $false}
}
function Remove-SelectedError{
    $ctx=Get-SelectedErrorContext
    if($null-eq$ctx){[Windows.Forms.MessageBox]::Show((T 'DashboardNoErrorSelection' 'Select a file in the error queue first.'),'MediaPrep')|Out-Null;return}
    $rel=[string]$ctx.RelativePath
    if([Windows.Forms.MessageBox]::Show((T 'DashboardConfirmRemove' "Remove '{0}' from the error queue and the entire MediaPrep queue?`r`n`r`nLocal work/temp files are removed. The UNC original is left untouched." @($rel)),'MediaPrep',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning) -ne [Windows.Forms.DialogResult]::Yes){return}
    $doc=Read-Json $inventoryPath $null
    $it=Find-InventoryItem $doc $rel
    $paths=New-Object System.Collections.Generic.List[string]
    if($null-ne$it){
        foreach($n in @('LocalSource','LocalOutput')){$v=[string](Get-ObjectProperty $it $n '');if(-not[string]::IsNullOrWhiteSpace($v)){$paths.Add($v)}}
    }
    if($null-ne$ctx.ErrorRecord){$v=[string](Get-ObjectProperty $ctx.ErrorRecord 'ErrorPath' '');if(-not[string]::IsNullOrWhiteSpace($v)){$paths.Add($v)}}
    foreach($fp in $paths){
        if((Test-IsSafeLocalPath $fp) -and (Test-Path -LiteralPath $fp -PathType Leaf)){try{Remove-Item -LiteralPath $fp -Force;Write-DashboardLog 'INFO' ("Removed local file: {0}" -f $fp)}catch{Write-DashboardLog 'ERROR' $_.Exception.Message}}
    }
    # Remove known temporary files/folders with the same base name.
    $stem=[IO.Path]::GetFileNameWithoutExtension($rel)
    if(Test-Path -LiteralPath $tempFolder -PathType Container){
        try{
            Get-ChildItem -LiteralPath $tempFolder -Force -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Name -like ($stem+'*')}|Sort-Object FullName -Descending|ForEach-Object{if(Test-IsSafeLocalPath $_.FullName){Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue}}
        }catch{}
    }
    if($null-ne$doc -and $doc.PSObject.Properties['items']){
        $key=Get-RelativeKey $rel
        $doc.items=@($doc.items|Where-Object{(Get-RelativeKey ([string](Get-ObjectProperty $_ 'RelativePath' ''))) -ne $key})
        if($doc.PSObject.Properties['errors']){$doc.errors=[int]@($doc.items|Where-Object{[int](Get-ObjectProperty $_ 'QueueStage' 0)-ge90}).Count}
        if($doc.PSObject.Properties['updatedUtc']){$doc.updatedUtc=(Get-Date).ToUniversalTime().ToString('o')}
        [void](Save-JsonAtomic $inventoryPath $doc)
    }
    Remove-ErrorRecord $rel
    Write-DashboardLog 'WARN' ("Manually removed from the complete queue: {0}. The UNC original was not changed." -f $rel)
    Refresh-Dashboard
}

function SizeText([double]$b){
    if($b-ge 1TB){return('{0:N2} TB'-f($b/1TB))}
    if($b-ge 1GB){return('{0:N2} GB'-f($b/1GB))}
    if($b-ge 1MB){return('{0:N1} MB'-f($b/1MB))}
    return('{0:N0} B'-f$b)
}
function Add-Col($g,$name,$header,$w){
    [void]$g.Columns.Add($name,$header);$g.Columns[$name].Width=$w
}
function Get-Status($it,$errors){
    $src=[string]$it.SourcePath
    foreach($e in @($errors)){
        if([string]$e.OriginalPath -eq [string]$it.LocalOutput -or [string]$e.RelativePath -eq [string]$it.RelativePath){return 'error'}
    }
    $ls=[string]$it.LocalSource;$lo=[string]$it.LocalOutput
    if($lo -and (Test-Path -LiteralPath $lo -PathType Leaf) -and (-not $ls -or -not(Test-Path -LiteralPath $ls -PathType Leaf))){return 'ready'}
    if($ls -and (Test-Path -LiteralPath $ls -PathType Leaf)){return 'processing'}
    return 'waiting'
}

function Get-RelativeKey([string]$Path){
    if([string]::IsNullOrWhiteSpace($Path)){return ''}
    try{return [IO.Path]::ChangeExtension($Path,$null).ToLowerInvariant()}catch{return $Path.ToLowerInvariant()}
}
function Get-ObjectProperty($Object,[string]$Name,$Default=$null){
    if($null -eq $Object){return $Default}
    try{
        if($Object.PSObject.Properties[$Name]){return $Object.$Name}
    }catch{}
    return $Default
}


$preferencesPath=Join-Path $data 'mediaprep.preferences.json'
function Convert-HexColor([string]$Hex,[Drawing.Color]$Fallback){try{$v=$Hex.Trim();if(-not$v.StartsWith('#')){$v='#'+$v};if($v-notmatch'^#[0-9A-Fa-f]{6}$'){return $Fallback};return [Drawing.ColorTranslator]::FromHtml($v)}catch{return $Fallback}}
function Get-ContrastColor([Drawing.Color]$c){$lum=(0.299*$c.R)+(0.587*$c.G)+(0.114*$c.B);if($lum-gt155){return [Drawing.Color]::FromArgb(25,25,25)};return [Drawing.Color]::White}
function Get-DashboardTheme {
    $prefs=Read-Json $preferencesPath $null;$theme=if($prefs -and $prefs.PSObject.Properties['Theme']){[string]$prefs.Theme}else{'Light'}
    $monthly=@{1=@('#02b6eb','#6ed0f7','#9feeff');2=@('#0187d0','#61b4d5','#9ee3ff');3=@('#1f4da2','#648edb','#9ec0ff');4=@('#00988b','#6ad5d2','#96fffc');5=@('#007d45','#62ce9e','#9ffad2');6=@('#1bb313','#61d35b','#97fc92');7=@('#ffd82b','#fff34f','#fff67f');8=@('#f15a25','#ee963b','#ffba72');9=@('#d54d07','#ea8856','#ffaf86');10=@('#ec1d25','#f27075','#ffa1a5');11=@('#d12086','#d961a6','#f694cc');12=@('#25227b','#6360ba','#9b98ea')}
    if($theme-eq'Dark'){$b=[Drawing.Color]::FromArgb(19,39,61);$p=[Drawing.Color]::FromArgb(45,52,62);$bg=[Drawing.Color]::FromArgb(30,34,40);$t=[Drawing.Color]::FromArgb(235,238,242);$i=[Drawing.Color]::FromArgb(38,44,52)}
    elseif($theme-eq'Monthly'){$x=$monthly[(Get-Date).Month];$b=Convert-HexColor $x[0] ([Drawing.Color]::Navy);$p=Convert-HexColor $x[1] ([Drawing.Color]::LightBlue);$bg=Convert-HexColor $x[2] ([Drawing.Color]::White);$t=[Drawing.Color]::FromArgb(25,25,25);$i=[Drawing.Color]::White}
    elseif($theme-eq'Custom'){$b=Convert-HexColor ([string]$prefs.CustomThemeBanner) ([Drawing.Color]::Navy);$p=Convert-HexColor ([string]$prefs.CustomThemePanel) ([Drawing.Color]::LightBlue);$bg=Convert-HexColor ([string]$prefs.CustomThemeBackground) ([Drawing.Color]::White);$t=[Drawing.Color]::FromArgb(25,25,25);$i=[Drawing.Color]::White}
    else{$b=[Drawing.Color]::FromArgb(22,52,86);$p=[Drawing.Color]::FromArgb(230,238,246);$bg=[Drawing.Color]::FromArgb(244,247,250);$t=[Drawing.Color]::FromArgb(25,25,25);$i=[Drawing.Color]::White}
    return [pscustomobject]@{Banner=$b;Panel=$p;Background=$bg;Text=$t;Input=$i;BannerText=(Get-ContrastColor $b)}
}
function Apply-DashboardTheme([Windows.Forms.Control]$Control){if($null-eq$Control){return};$p=$script:DashboardTheme;if($Control-is[Windows.Forms.Form]-or$Control-is[Windows.Forms.TabPage]-or$Control-is[Windows.Forms.GroupBox]-or$Control-is[Windows.Forms.Panel]-or$Control-is[Windows.Forms.FlowLayoutPanel]){$Control.BackColor=$p.Background;$Control.ForeColor=$p.Text}elseif($Control-is[Windows.Forms.DataGridView]){$Control.BackgroundColor=$p.Background;$Control.GridColor=$p.Panel;$Control.DefaultCellStyle.BackColor=$p.Input;$Control.DefaultCellStyle.ForeColor=$p.Text;$Control.DefaultCellStyle.SelectionBackColor=$p.Banner;$Control.DefaultCellStyle.SelectionForeColor=$p.BannerText;$Control.ColumnHeadersDefaultCellStyle.BackColor=$p.Panel;$Control.ColumnHeadersDefaultCellStyle.ForeColor=$p.Text;$Control.EnableHeadersVisualStyles=$false}elseif($Control-is[Windows.Forms.RichTextBox]-or$Control-is[Windows.Forms.TextBox]-or$Control-is[Windows.Forms.ListBox]){$Control.BackColor=$p.Input;$Control.ForeColor=$p.Text}elseif($Control-is[Windows.Forms.Button]){$Control.UseVisualStyleBackColor=$false;$Control.BackColor=$p.Panel;$Control.ForeColor=$p.Text}else{$Control.ForeColor=$p.Text};foreach($c in @($Control.Controls)){Apply-DashboardTheme $c}}

$script:DashboardTheme=Get-DashboardTheme
$form=New-Object Windows.Forms.Form
$form.Text=(T 'DashboardWindowTitle' 'MediaPrep - Queue statistics')
$form.StartPosition='CenterScreen'
$form.Size=New-Object Drawing.Size(1080,700)
$form.MinimumSize=New-Object Drawing.Size(900,600)
$form.Font=New-Object Drawing.Font('Segoe UI',9)
$form.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi

$title=New-Object Windows.Forms.Label
$title.Text=(T 'DashboardMonitorTitle' 'MediaPrep queue monitor')
$title.Font=New-Object Drawing.Font('Segoe UI',15,[Drawing.FontStyle]::Bold)
$title.AutoSize=$true;$title.Location=New-Object Drawing.Point(18,14);$form.Controls.Add($title)

$stats=New-Object Windows.Forms.GroupBox
$stats.Text=(T 'DashboardCurrentStatistics' 'Current statistics');$stats.Location=New-Object Drawing.Point(18,52);$stats.Size=New-Object Drawing.Size(1025,105);$stats.Anchor='Top,Left,Right';$form.Controls.Add($stats)
$labels=@{}
$defs=@(
    @('remaining',(T 'DashboardRemaining' 'Remaining in queue'),15),
    @('processed',(T 'DashboardProcessed' 'Processed'),155),
    @('size',(T 'DashboardRemainingSize' 'Size remaining'),305),
    @('subs',(T 'DashboardSubtitlesRemaining' 'Subtitles remaining'),455),
    @('readyReturn',(T 'DashboardReadyMove' 'Ready to move'),610),
    @('completed',(T 'DashboardCompleted' 'Completed'),770),
    @('errors',(T 'DashboardErrors' 'Errors'),900)
)
foreach($d in $defs){
    $l=New-Object Windows.Forms.Label;$l.Text=$d[1];$l.AutoSize=$true;$l.Location=New-Object Drawing.Point($d[2],24);$stats.Controls.Add($l)
    $v=New-Object Windows.Forms.Label;$v.Text='0';$v.AutoSize=$true;$v.Font=New-Object Drawing.Font('Segoe UI',12,[Drawing.FontStyle]::Bold);$v.Location=New-Object Drawing.Point($d[2],49);$stats.Controls.Add($v);$labels[$d[0]]=$v
}
$progress=New-Object Windows.Forms.ProgressBar;$progress.Location=New-Object Drawing.Point(15,78);$progress.Size=New-Object Drawing.Size(990,18);$progress.Anchor='Top,Left,Right';$stats.Controls.Add($progress)

$tabs=New-Object Windows.Forms.TabControl
$tabs.Location=New-Object Drawing.Point(18,170);$tabs.Size=New-Object Drawing.Size(1025,430);$tabs.Anchor='Top,Bottom,Left,Right';$form.Controls.Add($tabs)

$tabQueue=New-Object Windows.Forms.TabPage;$tabQueue.Text=(T 'DashboardTabRemaining' 'Remaining in queue')
$tabErr=New-Object Windows.Forms.TabPage;$tabErr.Text=(T 'DashboardTabError' 'Error queue')
$tabRun=New-Object Windows.Forms.TabPage;$tabRun.Text=(T 'DashboardTabRun' 'Run statistics')
$tabSlow=New-Object Windows.Forms.TabPage;$tabSlow.Text=(T 'DashboardTabSlow' 'Slow copies')
$tabs.TabPages.AddRange(@($tabQueue,$tabErr,$tabRun,$tabSlow))

$qgrid=New-Object Windows.Forms.DataGridView;$qgrid.Dock='Fill';$qgrid.ReadOnly=$true;$qgrid.AllowUserToAddRows=$false;$qgrid.RowHeadersVisible=$false;$qgrid.SelectionMode='FullRowSelect';$qgrid.AutoSizeColumnsMode=[Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
Add-Col $qgrid 'File' (T 'DashboardColumnFile' 'File') 310;Add-Col $qgrid 'Size' (T 'DashboardColumnSize' 'Size') 95;Add-Col $qgrid 'Subs' (T 'DashboardColumnSubs' 'Subs') 60;Add-Col $qgrid 'Status' (T 'DashboardColumnStatus' 'Status') 150;Add-Col $qgrid 'Path' (T 'DashboardColumnPath' 'Path') 360
$tabQueue.Controls.Add($qgrid)

$ePanel=New-Object Windows.Forms.Panel;$ePanel.Dock='Fill';$tabErr.Controls.Add($ePanel)
$errorButtons=New-Object Windows.Forms.FlowLayoutPanel;$errorButtons.Dock='Bottom';$errorButtons.Height=52;$errorButtons.Padding=New-Object Windows.Forms.Padding(8,8,8,6);$errorButtons.WrapContents=$false;$ePanel.Controls.Add($errorButtons)
$egrid=New-Object Windows.Forms.DataGridView;$egrid.Dock='Fill';$egrid.ReadOnly=$true;$egrid.AllowUserToAddRows=$false;$egrid.RowHeadersVisible=$false;$egrid.SelectionMode='FullRowSelect';$egrid.AutoSizeColumnsMode=[Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
Add-Col $egrid 'File' (T 'DashboardColumnFile' 'File') 270;Add-Col $egrid 'Reason' (T 'DashboardColumnReason' 'Error reason') 360;Add-Col $egrid 'Path' (T 'DashboardColumnErrorPath' 'Error path') 370;$ePanel.Controls.Add($egrid);$egrid.BringToFront();$errorButtons.BringToFront()
$bReview=New-Object Windows.Forms.Button;$bReview.Text=(T 'DashboardReview' 'Review');$bReview.Size=New-Object Drawing.Size(120,32);$errorButtons.Controls.Add($bReview)
$bContinue=New-Object Windows.Forms.Button;$bContinue.Text=(T 'DashboardContinue' 'Continue');$bContinue.Size=New-Object Drawing.Size(120,32);$errorButtons.Controls.Add($bContinue)
$bRemoveError=New-Object Windows.Forms.Button;$bRemoveError.Text=(T 'DashboardRemove' 'Remove');$bRemoveError.Size=New-Object Drawing.Size(120,32);$errorButtons.Controls.Add($bRemoveError)
$bProcess=New-Object Windows.Forms.Button;$bProcess.Text=(T 'DashboardProcessErrorQueue' 'Process error queue');$bProcess.Size=New-Object Drawing.Size(170,32);$errorButtons.Controls.Add($bProcess)

$runBox=New-Object Windows.Forms.RichTextBox;$runBox.Dock='Fill';$runBox.ReadOnly=$true;$runBox.Font=New-Object Drawing.Font('Consolas',10);$tabRun.Controls.Add($runBox)
$sgrid=New-Object Windows.Forms.DataGridView;$sgrid.Dock='Fill';$sgrid.ReadOnly=$true;$sgrid.AllowUserToAddRows=$false;$sgrid.RowHeadersVisible=$false;$sgrid.SelectionMode='FullRowSelect';$sgrid.AutoSizeColumnsMode=[Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
Add-Col $sgrid 'File' (T 'DashboardColumnFile' 'File') 320;Add-Col $sgrid 'Dir' (T 'DashboardDirection' 'Direction') 105;Add-Col $sgrid 'Size' (T 'DashboardColumnSize' 'Size') 95;Add-Col $sgrid 'Rate' 'MB/s' 80;Add-Col $sgrid 'Time' (T 'DashboardTime' 'Time') 90;Add-Col $sgrid 'Started' (T 'DashboardStarted' 'Start') 160;$tabSlow.Controls.Add($sgrid)

$status=New-Object Windows.Forms.Label;$status.Location=New-Object Drawing.Point(18,612);$status.Size=New-Object Drawing.Size(620,26);$status.Anchor='Bottom,Left';$form.Controls.Add($status)
$bDetails=New-Object Windows.Forms.Button;$bDetails.Text=(T 'DashboardShowDetails' 'Show details');$bDetails.Location=New-Object Drawing.Point(650,610);$bDetails.Size=New-Object Drawing.Size(105,30);$bDetails.Anchor='Bottom,Right';$form.Controls.Add($bDetails)
$bLoadStats=New-Object Windows.Forms.Button;$bLoadStats.Text=(T 'DashboardLoadStatistics' 'Load statistics...');$bLoadStats.Location=New-Object Drawing.Point(762,610);$bLoadStats.Size=New-Object Drawing.Size(125,30);$bLoadStats.Anchor='Bottom,Right';$form.Controls.Add($bLoadStats)
$bCurrentStats=New-Object Windows.Forms.Button;$bCurrentStats.Text=(T 'DashboardCurrent' 'Current');$bCurrentStats.Location=New-Object Drawing.Point(894,610);$bCurrentStats.Size=New-Object Drawing.Size(70,30);$bCurrentStats.Anchor='Bottom,Right';$form.Controls.Add($bCurrentStats)
$bClose=New-Object Windows.Forms.Button;$bClose.Text=(T 'DashboardClose' 'Close');$bClose.Location=New-Object Drawing.Point(971,610);$bClose.Size=New-Object Drawing.Size(70,30);$bClose.Anchor='Bottom,Right';$form.Controls.Add($bClose)

function Set-BottomButtonLayout {
    $gap=7
    $right= $form.ClientSize.Width - 18
    $bClose.Left=$right-$bClose.Width
    $bCurrentStats.Left=$bClose.Left-$gap-$bCurrentStats.Width
    $bLoadStats.Left=$bCurrentStats.Left-$gap-$bLoadStats.Width
    $bDetails.Left=$bLoadStats.Left-$gap-$bDetails.Width
    $status.Width=[Math]::Max(180,$bDetails.Left-$status.Left-10)
}
$form.Add_Resize({Set-BottomButtonLayout})
Set-BottomButtonLayout
Apply-DashboardTheme $form

function Get-QueueConsoleHandle {
    try {
        if(-not(Test-Path -LiteralPath $queueConsoleStatePath -PathType Leaf)){return [IntPtr]::Zero}
        $state=Get-Content -LiteralPath $queueConsoleStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($null-eq $state -or -not $state.PSObject.Properties['Handle']){return [IntPtr]::Zero}
        $hWnd=[IntPtr]([int64]$state.Handle)
        if($hWnd -eq [IntPtr]::Zero -or -not [MediaPrep.DashboardNative]::IsWindow($hWnd)){return [IntPtr]::Zero}
        return $hWnd
    }catch{return [IntPtr]::Zero}
}
function Toggle-QueueConsole {
    $hWnd=Get-QueueConsoleHandle
    if($hWnd -eq [IntPtr]::Zero){
        [Windows.Forms.MessageBox]::Show((T 'DashboardDetailsNotActive' 'The detailed queue window is not active yet.'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null
        return
    }
    if($script:QueueConsoleVisible){
        [void][MediaPrep.DashboardNative]::ShowWindow($hWnd,0)
        $script:QueueConsoleVisible=$false
        $bDetails.Text=(T 'DashboardShowDetails' 'Show details')
        Write-DashboardLog 'INFO' 'Detailed queue window hidden.'
    }else{
        [void][MediaPrep.DashboardNative]::ShowWindow($hWnd,5)
        $script:QueueConsoleVisible=$true
        $bDetails.Text=(T 'DashboardHideDetails' 'Hide details')
        Write-DashboardLog 'INFO' 'Detailed queue window shown.'
    }
}

function Get-StageText([int]$stage,[string]$fallback){
    switch($stage){
        0{T 'DashboardStageWaiting' 'Waiting'} 1{T 'DashboardStageCopyIn' 'Copying from UNC'} 2{T 'DashboardStageLocalReady' 'Local source ready'} 3{T 'DashboardStageMuxing' 'Muxing'} 4{T 'DashboardStageMuxed' 'Muxed'}
        5{T 'DashboardStageAnalyzed' 'Analyzed'} 6{T 'DashboardStageEncoding' 'Encoding'} 7{T 'DashboardStageEncoded' 'Encoded'} 8{T 'DashboardStageWaitingReturn' 'Waiting to return'} 9{T 'DashboardStageCopyOut' 'Copying to UNC'}
        10{T 'DashboardStageCompleted' 'Completed'} 90{T 'DashboardStageError' 'Error'} 91{T 'DashboardStageErrorQueue' 'Processing error queue'} 92{T 'DashboardStageErrorQueueFailed' 'Error queue failed'}
        default{if($fallback){$fallback}else{T 'DashboardStageUnknown' 'Stage {0}' @($stage)}}
    }
}
function Set-GridLayout{
    # AutoSizeColumnsMode=Fill can gradually change FillWeight/column widths when
    # Rows.Clear()/Rows.Add() runs every second. Keep fixed widths and allow only
    # the final path column to consume the remaining space.
    try{
        $qFixed=310+95+60+150
        $qAvail=[Math]::Max(300,$qgrid.ClientSize.Width-$qFixed-25)
        $qgrid.Columns['File'].Width=310
        $qgrid.Columns['Size'].Width=95
        $qgrid.Columns['Subs'].Width=60
        $qgrid.Columns['Status'].Width=150
        $qgrid.Columns['Path'].Width=$qAvail

        $eFixed=270+360
        $eAvail=[Math]::Max(300,$egrid.ClientSize.Width-$eFixed-25)
        $egrid.Columns['File'].Width=270
        $egrid.Columns['Reason'].Width=360
        $egrid.Columns['Path'].Width=$eAvail

        $sFixed=320+105+95+80+90
        $sAvail=[Math]::Max(160,$sgrid.ClientSize.Width-$sFixed-25)
        $sgrid.Columns['File'].Width=320
        $sgrid.Columns['Dir'].Width=105
        $sgrid.Columns['Size'].Width=95
        $sgrid.Columns['Rate'].Width=80
        $sgrid.Columns['Time'].Width=90
        $sgrid.Columns['Started'].Width=$sAvail
    }catch{Write-DashboardLog 'ERROR' ('Set-GridLayout: '+$_.Exception.Message)}
}

function Refresh-Dashboard{
    try{
    $session=Read-Json $script:StatisticsViewPath $null
    if($script:ArchiveView -and $session){
        $archiveItems=New-Object System.Collections.Generic.List[object]
        foreach($aq in @(Get-ObjectProperty $session 'Queues' @())){
            foreach($af in @(Get-ObjectProperty $aq 'Files' @())){
                $archiveStage=[int](Get-ObjectProperty $af 'QueueStage' 0)
                $archiveStatus=[string](Get-ObjectProperty $af 'QueueStatus' '')
                $archiveResult=[string](Get-ObjectProperty $af 'Result' '')
                $archiveCopyBackCompleted=[string](Get-ObjectProperty $af 'CopyBackCompleted' '')
                $archiveCopyBackBytes=[double](Get-ObjectProperty $af 'CopyBackBytes' 0)
                # Archived sessions are reconstructed from durable result/copy data.
                # This corrects stale stage 8/9 values left by older writers after a
                # return copy had in fact completed successfully.
                if($archiveResult -eq 'Completed' -and ((-not [string]::IsNullOrWhiteSpace($archiveCopyBackCompleted)) -or $archiveCopyBackBytes -gt 0)){
                    $archiveStage=10
                    $archiveStatus='Completed'
                }
                $archiveItems.Add([pscustomobject][ordered]@{Root=[string](Get-ObjectProperty $aq 'SourceRoot' '');RelativePath=[string](Get-ObjectProperty $af 'RelativePath' '');SourcePath=[string](Get-ObjectProperty $af 'SourcePath' (Get-ObjectProperty $af 'RelativePath' ''));SourceSize=[int64](Get-ObjectProperty $af 'SourceSize' 0);MuxedSize=(Get-ObjectProperty $af 'MuxedSize' $null);EncodedSize=(Get-ObjectProperty $af 'EncodedSize' $null);FinalSize=(Get-ObjectProperty $af 'FinalSize' $null);SubtitleCount=[int](Get-ObjectProperty $af 'SubtitleCount' 0);QueueStage=$archiveStage;QueueStatus=$archiveStatus;ErrorMessage=[string](Get-ObjectProperty $af 'ErrorMessage' '');LocalOutput=[string](Get-ObjectProperty $af 'LocalOutput' '');ErrorLocalPath=[string](Get-ObjectProperty $af 'ErrorLocalPath' '')})
            }
        }
        $inventoryDoc=[pscustomobject]@{version='archive';items=@($archiveItems.ToArray())}
        $items=@($inventoryDoc.items);$errs=@();$copy=@();$run=$null
    } else {
        $inventoryDoc=Read-Json $inventoryPath $null
        if($null -ne $inventoryDoc -and $inventoryDoc.PSObject.Properties['items']){$items=@($inventoryDoc.items)}else{$items=@()}
        $errs=@(Read-Json $errorPath @());$copy=@(Read-Json $copyStatsPath @());$run=Read-Json $runPath $null
    }

    $qgrid.Rows.Clear();$egrid.Rows.Clear();$sgrid.Rows.Clear()
    foreach($btn in @($bReview,$bContinue,$bRemoveError,$bProcess)){$btn.Enabled=-not $script:ArchiveView}
    $remaining=0;$processed=0;$readyReturn=0;$completed=0;$bytes=0.0;$subs=0
    $inventoryErrors=New-Object System.Collections.Generic.List[object]
    foreach($it in $items){
        $stage=0
        try{$stage=[int](Get-ObjectProperty $it 'QueueStage' 0)}catch{$stage=0}
        $statusText=Get-StageText $stage ([string](Get-ObjectProperty $it 'QueueStatus' ''))
        $isError=($stage -ge 90)
        $isComplete=($stage -eq 10)
        if($isError){
            $inventoryErrors.Add($it)
        }
        elseif($isComplete){
            $processed++
            $completed++
        }
        else{
            $remaining++
            if($stage -eq 8){$readyReturn++}
            $sizeValue=0.0
            $finalValue=Get-ObjectProperty $it 'FinalSize' $null
            $encodedValue=Get-ObjectProperty $it 'EncodedSize' $null
            $muxedValue=Get-ObjectProperty $it 'MuxedSize' $null
            if($null-ne$finalValue){$sizeValue=[double]$finalValue}
            elseif($null-ne$encodedValue){$sizeValue=[double]$encodedValue}
            elseif($null-ne$muxedValue){$sizeValue=[double]$muxedValue}
            else{$sizeValue=[double](Get-ObjectProperty $it 'SourceSize' 0)}
            $bytes += $sizeValue
            $subs += [int](Get-ObjectProperty $it 'SubtitleCount' 0)
            [void]$qgrid.Rows.Add([IO.Path]::GetFileName([string](Get-ObjectProperty $it 'SourcePath' '')),(SizeText $sizeValue),[int](Get-ObjectProperty $it 'SubtitleCount' 0),$statusText,[string](Get-ObjectProperty $it 'SourcePath' ''))
        }
    }

    # Build the error view from both inventory status and error-queue.json. This keeps
    # the error queue visible even if an older/external status update missed QueueStage.
    $errorKeys=@{}
    foreach($e in $errs){
        $rel=[string](Get-ObjectProperty $e 'RelativePath' '')
        $key=Get-RelativeKey $rel
        if(-not [string]::IsNullOrWhiteSpace($key)){$errorKeys[$key]=$true}
        $inv=Find-InventoryItem $inventoryDoc $rel
        $idx=$egrid.Rows.Add(
            [IO.Path]::GetFileName($rel),
            [string](Get-ObjectProperty $e 'Reason' ''),
            [string](Get-ObjectProperty $e 'ErrorPath' '')
        )
        $egrid.Rows[$idx].Tag=[PSCustomObject]@{RelativePath=$rel;ErrorRecord=$e;InventoryItem=$inv}
    }
    foreach($it in @($inventoryErrors.ToArray())){
        $rel=[string](Get-ObjectProperty $it 'RelativePath' '')
        $key=Get-RelativeKey $rel
        if(-not [string]::IsNullOrWhiteSpace($key) -and $errorKeys.ContainsKey($key)){continue}
        $displayErrorPath=[string](Get-ObjectProperty $it 'ErrorLocalPath' '')
        if([string]::IsNullOrWhiteSpace($displayErrorPath)){$displayErrorPath=[string](Get-ObjectProperty $it 'LocalOutput' '')}
        $idx=$egrid.Rows.Add(
            [IO.Path]::GetFileName([string](Get-ObjectProperty $it 'SourcePath' $rel)),
            [string](Get-ObjectProperty $it 'ErrorMessage' ''),
            $displayErrorPath
        )
        $egrid.Rows[$idx].Tag=[PSCustomObject]@{RelativePath=$rel;ErrorRecord=$null;InventoryItem=$it}
        if(-not [string]::IsNullOrWhiteSpace($key)){$errorKeys[$key]=$true}
    }
    $errorCount=$egrid.Rows.Count

    $total=$items.Count
    $labels.remaining.Text=[string]$remaining
    $labels.processed.Text=('{0}/{1}'-f($processed),$total)
    $labels.size.Text=SizeText $bytes
    $labels.subs.Text=[string]$subs
    $labels.readyReturn.Text=[string]$readyReturn
    $labels.completed.Text=[string]$completed
    $labels.errors.Text=[string]$errorCount
    $doneForProgress=$processed+$errorCount
    $progress.Value=if($total-gt 0){[Math]::Min(100,[int](100*$doneForProgress/$total))}else{0}

    # Run statistics are based on the complete Start Center session, not a single UNC queue.
    $sessionFiles=New-Object System.Collections.Generic.List[object]
    $sessionQueueCount=0
    if($session -and $session.PSObject.Properties['Queues']){
        foreach($q in @($session.Queues)){
            $sessionQueueCount++
            foreach($sf in @((Get-ObjectProperty $q 'Files' @()))){$sessionFiles.Add($sf)}
        }
    }
    [double]$inBytes=0;[double]$outBytes=0;[double]$inSec=0;[double]$outSec=0
    [double]$sourceCompleted=0.0;[double]$finalCompleted=0.0;$savingsFiles=0;$sessionCompleted=0;$sessionErrors=0
    $allRates=New-Object System.Collections.Generic.List[object]
    foreach($sf in @($sessionFiles.ToArray())){
        $events=@((Get-ObjectProperty $sf 'CopyEvents' @()))
        if($events.Count -gt 0){
            foreach($ev in $events){
                $dir=[string](Get-ObjectProperty $ev 'Direction' '')
                $evBytes=[double](Get-ObjectProperty $ev 'Bytes' 0);$evSec=[double](Get-ObjectProperty $ev 'Seconds' 0);$evRate=[double](Get-ObjectProperty $ev 'MBps' 0)
                if($dir -eq 'In'){$inBytes+=$evBytes;$inSec+=$evSec}else{if($dir -eq 'Out'){$outBytes+=$evBytes;$outSec+=$evSec}}
                if($evRate -gt 0){$allRates.Add([pscustomobject]@{File=(Get-ObjectProperty $ev 'File' (Get-ObjectProperty $sf 'RelativePath' ''));Direction=$dir;Bytes=$evBytes;Seconds=$evSec;MBps=$evRate;StartedLocal=(Get-ObjectProperty $ev 'StartedLocal' '')})}
            }
        } else {
            # Backward compatibility with sessions created before CopyEvents existed.
            $ciBytes=[double](Get-ObjectProperty $sf 'CopyInBytes' 0);$ciSec=[double](Get-ObjectProperty $sf 'CopyInSeconds' 0);$ciRate=[double](Get-ObjectProperty $sf 'CopyInMBps' 0)
            $coBytes=[double](Get-ObjectProperty $sf 'CopyBackBytes' 0);$coSec=[double](Get-ObjectProperty $sf 'CopyBackSeconds' 0);$coRate=[double](Get-ObjectProperty $sf 'CopyBackMBps' 0)
            $inBytes+=$ciBytes;$inSec+=$ciSec;$outBytes+=$coBytes;$outSec+=$coSec
            if($ciRate -gt 0){$allRates.Add([pscustomobject]@{File=(Get-ObjectProperty $sf 'SourcePath' (Get-ObjectProperty $sf 'RelativePath' ''));Direction='In';Bytes=$ciBytes;Seconds=$ciSec;MBps=$ciRate;StartedLocal=(Get-ObjectProperty $sf 'CopyInStarted' '')})}
            if($coRate -gt 0){$allRates.Add([pscustomobject]@{File=(Get-ObjectProperty $sf 'RelativePath' '');Direction='Out';Bytes=$coBytes;Seconds=$coSec;MBps=$coRate;StartedLocal=(Get-ObjectProperty $sf 'CopyBackStarted' '')})}
        }
        $src=[double](Get-ObjectProperty $sf 'SourceSize' 0);$final=[double](Get-ObjectProperty $sf 'FinalSize' 0)
        if($src -gt 0 -and $final -gt 0){$sourceCompleted+=$src;$finalCompleted+=$final;$savingsFiles++}
        $result=[string](Get-ObjectProperty $sf 'Result' '')
        if($result -eq 'Completed'){$sessionCompleted++}elseif($result -eq 'Error'){$sessionErrors++}
    }
    # The main progress bar shows the complete MediaPrep session: completed files / registered files.
    # When new queues are added during the same session, the percentage naturally drops until they finish.
    if($sessionFiles.Count -gt 0){$progress.Value=[Math]::Min(100,[Math]::Max(0,[int](100*$sessionCompleted/[double]$sessionFiles.Count)))}
    else{$progress.Value=0}
    $avgIn=if($inSec-gt 0){($inBytes/1MB)/$inSec}else{0};$avgOut=if($outSec-gt 0){($outBytes/1MB)/$outSec}else{0}
    [double]$saved=$sourceCompleted-$finalCompleted
    if($saved -lt 0){$saved=0.0}
    [double]$savedPct=if($sourceCompleted-gt 0){100.0*$saved/$sourceCompleted}else{0.0}
    $started='-';$ended='-';$elapsed='00:00:00';$sessionStatus='NotStarted'
    if($session){
        $started=[string](Get-ObjectProperty $session 'StartedLocal' '');if([string]::IsNullOrWhiteSpace($started)){$started='-'}
        $sessionStatus=[string](Get-ObjectProperty $session 'Status' '')
        # Older archived statistics did not always store a root Status value.
        # Reconstruct a useful status from the durable file results instead of
        # showing "Not started" for a completed archive.
        if([string]::IsNullOrWhiteSpace($sessionStatus)){
            if($sessionFiles.Count -gt 0 -and $sessionCompleted -ge $sessionFiles.Count){$sessionStatus='Completed'}
            elseif($sessionErrors -gt 0){$sessionStatus='Error'}
            elseif($sessionFiles.Count -gt 0){$sessionStatus='Stopped'}
            else{$sessionStatus='NotStarted'}
        }
        [double]$elapsedSeconds=[double](Get-ObjectProperty $session 'ActiveSeconds' (Get-ObjectProperty $session 'ElapsedSeconds' 0))
        if($sessionStatus -eq 'Running'){
            $activeUtc=[string](Get-ObjectProperty $session 'ActiveRunStartedUtc' '')
            if(-not[string]::IsNullOrWhiteSpace($activeUtc)){try{$elapsedSeconds += ((Get-Date).ToUniversalTime()-[datetime]::Parse($activeUtc).ToUniversalTime()).TotalSeconds}catch{}}
            $ended=(T 'DashboardInProgress' 'In progress')
        } else {
            $ended=[string](Get-ObjectProperty $session 'EndedLocal' '');if([string]::IsNullOrWhiteSpace($ended)){$ended='-'}
        }
        if($elapsedSeconds -lt 0){$elapsedSeconds=0};$elapsed=[TimeSpan]::FromSeconds($elapsedSeconds).ToString('hh\:mm\:ss')
    }
    $sessionStatusDisplay = switch ($sessionStatus) {
        'Running'   { T 'DashboardSessionRunning' 'Running' }
        'Completed' { T 'DashboardSessionCompleted' 'Completed' }
        'Stopped'   { T 'DashboardSessionStopped' 'Stopped' }
        'Error'     { T 'DashboardSessionError' 'Error' }
        default     { T 'DashboardNotStarted' 'Not started' }
    }
    $runSummaryFallback="SESSION`r`nStatus:                  {0}`r`nStarted:                 {1}`r`nEnded:                   {2}`r`nRuntime:                 {3}`r`nQueues registered:       {4}`r`nFiles registered:        {5}`r`nFiles completed:         {6}`r`nSession errors:          {7}`r`n`r`nCopied from UNC:         {8}`r`nCopied back:             {9}`r`n`r`nOriginal size counted:   {10}`r`nFinal size counted:      {11}`r`nSpace saved:             {12} ({13:N1} %)`r`nFiles in calculation:    {14}`r`n`r`nCopy-in time:            {15}`r`nAverage in:              {16:N1} MB/s`r`nCopy-back time:          {17}`r`nAverage back:            {18:N1} MB/s"
    $runBox.Text=(T 'DashboardSessionSummary' $runSummaryFallback @($sessionStatusDisplay,$started,$ended,$elapsed,$sessionQueueCount,$sessionFiles.Count,$sessionCompleted,$sessionErrors,(SizeText $inBytes),(SizeText $outBytes),(SizeText $sourceCompleted),(SizeText $finalCompleted),(SizeText $saved),$savedPct,$savingsFiles,([TimeSpan]::FromSeconds($inSec).ToString('hh\:mm\:ss')),$avgIn,([TimeSpan]::FromSeconds($outSec).ToString('hh\:mm\:ss')),$avgOut))

    $allRates=@($allRates.ToArray())
    [double]$avg=0
    if($allRates.Count -gt 0){
        [double]$rateSum=0
        foreach($r in $allRates){$rateSum += [double](Get-ObjectProperty $r 'MBps' 0)}
        $avg=$rateSum/[double]$allRates.Count
    }
    foreach($c in ($allRates|Sort-Object {[double](Get-ObjectProperty $_ 'MBps' 0)})){
        $rate=[double](Get-ObjectProperty $c 'MBps' 0)
        $slow=($rate -lt 30) -or ($avg -gt 0 -and $rate -lt ($avg*0.5))
        if($slow){
            [void]$sgrid.Rows.Add([IO.Path]::GetFileName([string](Get-ObjectProperty $c 'File' '')),[string](Get-ObjectProperty $c 'Direction' ''),(SizeText([double](Get-ObjectProperty $c 'Bytes' 0))),('{0:N1}'-f$rate),([TimeSpan]::FromSeconds([double](Get-ObjectProperty $c 'Seconds' 0)).ToString('hh\:mm\:ss')),[string](Get-ObjectProperty $c 'StartedLocal' ''))
        }
    }
    $viewName=if($script:ArchiveView){T 'DashboardArchive' 'ARCHIVE: {0}' @([IO.Path]::GetFileName($script:StatisticsViewPath))}else{T 'DashboardCurrentSession' 'CURRENT SESSION'};$status.Text=(T 'DashboardLastUpdated' 'Last updated: {0:HH:mm:ss} | {1} | Inventory v{2}: {3} items | Error queue: {4}' @((Get-Date),$viewName,$(if($inventoryDoc){$inventoryDoc.version}else{'-'}),$total,$errorCount))
    Write-DashboardLog 'VERBOSE' ("Refresh: total={0}; remaining={1}; processed={2}; readyReturn={3}; completed={4}; errors={5}; bytesRemaining={6}" -f $total,$remaining,$processed,$readyReturn,$completed,$errorCount,[int64]$bytes)
    }catch{
        Write-DashboardLog 'ERROR' ('Refresh-Dashboard: '+$_.Exception.Message)
        $status.Text=(T 'DashboardRefreshError' 'Error refreshing queue statistics. See dashboard log.')
    }
}
$form.Add_Shown({
    Write-DashboardLog 'INFO' 'Dashboard window shown.'
    Set-GridLayout
})
$form.Add_Resize({Set-GridLayout})
$bReview.Add_Click({Review-SelectedError})
$bContinue.Add_Click({Continue-SelectedError})
$bRemoveError.Add_Click({Remove-SelectedError})
$bDetails.Add_Click({Toggle-QueueConsole})
$bLoadStats.Add_Click({
    $dlg=New-Object Windows.Forms.OpenFileDialog;$dlg.Title=(T 'DashboardOpenStatistics' 'Open saved MediaPrep statistics');$dlg.Filter=(T 'DashboardStatisticsFilter' 'MediaPrep statistics (*.json)|*.json');if(Test-Path -LiteralPath $statisticsArchiveFolder -PathType Container){$dlg.InitialDirectory=$statisticsArchiveFolder};$dlg.Multiselect=$false
    if($dlg.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK){$script:StatisticsViewPath=$dlg.FileName;$script:ArchiveView=$true;Write-DashboardLog 'INFO' ('Archived statistics opened: '+$dlg.FileName);Refresh-Dashboard};$dlg.Dispose()
})
$bCurrentStats.Add_Click({$script:StatisticsViewPath=$statisticsSessionPath;$script:ArchiveView=$false;Write-DashboardLog 'INFO' 'Showing current session.';Refresh-Dashboard})
$bClose.Add_Click({$form.Close()})
$bProcess.Add_Click({
    if([Windows.Forms.MessageBox]::Show((T 'DashboardConfirmProcessErrorQueue' 'Process the entire error queue with "Ignore decode errors"?'),'MediaPrep',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question) -eq [Windows.Forms.DialogResult]::Yes){
        Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path (Join-Path $Root 'App') 'MediaPrep.ps1')+'"'),'-EncodeOnly','-ProcessErrorQueue','-IgnoreDecodeErrors','-NoConfirm','-NoPause')
    }
})
$timer=New-Object Windows.Forms.Timer;$timer.Interval=1000;$timer.Add_Tick({Refresh-Dashboard});$timer.Start()
$form.Add_FormClosed({
    # Closing the dashboard must never terminate the queue host. If the detailed
    # queue console is currently visible, hide that window as part of UI cleanup.
    try{
        $hWnd=Get-QueueConsoleHandle
        if($hWnd -ne [IntPtr]::Zero){[void][MediaPrep.DashboardNative]::ShowWindow($hWnd,0)}
        $script:QueueConsoleVisible=$false
    }catch{}
    Write-DashboardLog 'INFO' 'Dashboard window closing.'
    $timer.Stop();$timer.Dispose()
})
Refresh-Dashboard
[void]$form.ShowDialog()
