#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$Language = 'system'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

$DataFolder=Join-Path $Root 'Data'
$Downloads=Join-Path $DataFolder 'Downloads'
$ToolsRoot=Join-Path $Root 'Tools'
$BackupRoot=Join-Path $ToolsRoot 'ToolBackups'
$ProgramBackupRoot=Join-Path $DataFolder 'ProgramBackups'
$MediaPrepUpdateRequest=Join-Path $DataFolder 'mediaprep-update-request.json'
$PrefPath=Join-Path $DataFolder 'mediaprep.preferences.json'
$EncoderCapabilities=Join-Path $DataFolder 'encoder-capabilities.json'
$EncoderBenchmark=Join-Path $DataFolder 'encoder-benchmark.json'
$EncoderTestStatus=Join-Path $DataFolder 'encoder-test-status.json'
foreach($folder in @($DataFolder,$Downloads,$ToolsRoot,$BackupRoot,$ProgramBackupRoot)){if(-not(Test-Path -LiteralPath $folder)){New-Item -ItemType Directory -Force -Path $folder|Out-Null}}

function Is-Swedish {
    $languageValue=[string]$Language
    if($languageValue -match '^(?i:sv|sv-SE|swedish|svenska)$'){return $true}
    if($languageValue -match '^(?i:en|en-US|english)$'){return $false}
    return ([Globalization.CultureInfo]::CurrentUICulture.Name -like 'sv*')
}
$sv=Is-Swedish
function Msg([string]$en,[string]$svText){if($sv){return $svText};return $en}
function Read-Json($path){if(Test-Path -LiteralPath $path -PathType Leaf){try{return (Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json)}catch{return $null}};return $null}
function Write-Json($path,$value){$value|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $path -Encoding UTF8}
function Get-P($object,[string]$name,$default=$null){if($null-eq$object){return $default};$property=$object.PSObject.Properties[$name];if($null-eq$property){return $default};return $property.Value}
function Get-VersionText($exe){
    if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){return $null}
    try{
        $leaf=[IO.Path]::GetFileName([string]$exe)
        $args=if($leaf -ieq 'mkvmerge.exe'){@('--version')}else{@('-version')}
        return ((& $exe $args 2>&1|Select-Object -First 1)-as[string])
    }catch{return $null}
}

function Get-ShortToolVersion([string]$text,[string]$tool){
    if([string]::IsNullOrWhiteSpace($text)){return '-'}
    if($tool -eq 'FFmpeg'){
        $m=[regex]::Match($text,'ffmpeg\s+version\s+([^\s]+)')
        if($m.Success){
            $v=$m.Groups[1].Value
            return ($v -replace '[-_](?:full|essentials)_build.*$','')
        }
    }else{
        $m=[regex]::Match($text,'mkvmerge\s+v([^\s]+)')
        if($m.Success){return $m.Groups[1].Value}
    }
    return $text
}
function Test-FFmpegFeatures($exe){
    $result=[ordered]@{Nvenc=$false;Amf=$false;Qsv=$false;CpuHevc=$false;Cuda=$false}
    if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){return [pscustomobject]$result}
    try{$enc=(& $exe -hide_banner -encoders 2>&1|Out-String);$hw=(& $exe -hide_banner -hwaccels 2>&1|Out-String)}catch{return [pscustomobject]$result}
    $result.Nvenc=($enc -match '\bhevc_nvenc\b');$result.Amf=($enc -match '\bhevc_amf\b');$result.Qsv=($enc -match '\bhevc_qsv\b');$result.CpuHevc=($enc -match '\blibx265\b');$result.Cuda=($hw -match '\bcuda\b')
    return [pscustomobject]$result
}
function Download-File($url,$path){Write-Host (Msg "Downloading: $url" "Hämtar: $url") -ForegroundColor Cyan;Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $path}
function ConvertTo-NativeArgument {
    param([AllowNull()][string]$Value)
    if($null-eq$Value){return '""'}
    if($Value -notmatch '[\s"]'){return $Value}
    return '"'+($Value -replace '(\\*)"','$1$1\\"' -replace '(\\+)$','$1$1')+'"'
}
function Invoke-NativeExit {
    param([string]$Exe,[string[]]$Arguments)
    $p=$null
    try{
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=$Exe
        $psi.Arguments=(($Arguments|ForEach-Object{ConvertTo-NativeArgument ([string]$_)})-join' ')
        $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
        $p=New-Object Diagnostics.Process;$p.StartInfo=$psi
        if(-not$p.Start()){return 999}
        $outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync();$p.WaitForExit();[void]$outTask.Result;[void]$errTask.Result
        return [int]$p.ExitCode
    }catch{return 999}finally{if($p){$p.Dispose()}}
}
function Get-SelectedEncoderForCompatibilityTest {
    $caps=Read-Json $EncoderCapabilities
    if($null-eq$caps){return $null}
    $selectedId=[string](Get-P $prefs 'SelectedEncoderId' '')
    if([string]::IsNullOrWhiteSpace($selectedId)){return $null}
    foreach($enc in @(Get-P $caps 'Encoders' @())){
        if([string](Get-P $enc 'Id' '') -eq $selectedId -and [bool](Get-P $enc 'Verified' $false)){return $enc}
    }
    return $null
}
function Test-StagedFfmpegCompatibility {
    param([string]$Exe)
    $tests=New-Object System.Collections.Generic.List[object]
    $tests.Add([pscustomobject]@{Backend='CPU';Encoder='libx265';GpuIndex=$null})
    $selected=Get-SelectedEncoderForCompatibilityTest
    if($selected -and [string](Get-P $selected 'Backend' 'CPU') -ne 'CPU'){
        $tests.Add([pscustomobject]@{Backend=[string](Get-P $selected 'Backend' '');Encoder=[string](Get-P $selected 'Encoder' '');GpuIndex=(Get-P $selected 'GpuIndex' $null)})
    }
    foreach($test in $tests){
        $output=Join-Path $Downloads ('ffmpeg-compat-'+[guid]::NewGuid().ToString('N')+'.mkv')
        try{
            $a=@('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=640x360:rate=30','-t','1','-an')
            switch([string]$test.Backend){
                'NVENC'{$a+=@('-c:v','hevc_nvenc');if($null-ne$test.GpuIndex){$a+=@('-gpu',[string][int]$test.GpuIndex)};$a+=@('-preset','p4','-rc','vbr','-cq','24','-b:v','1200k')}
                'QSV'{$a+=@('-c:v','hevc_qsv','-preset','medium','-b:v','1200k')}
                'AMF'{$a+=@('-c:v','hevc_amf','-usage','transcoding','-quality','balanced','-rc','vbr_peak','-b:v','1200k')}
                default{$a+=@('-c:v','libx265','-preset','ultrafast','-b:v','1200k')}
            }
            $a+=@($output)
            $exit=Invoke-NativeExit -Exe $Exe -Arguments $a
            if($exit-ne0 -or -not(Test-Path -LiteralPath $output -PathType Leaf) -or (Get-Item -LiteralPath $output).Length-lt1024){
                throw (Msg ("Staged FFmpeg failed the {0} compatibility test." -f $test.Backend) ("Den nya FFmpeg-versionen klarade inte kompatibilitetstestet för {0}." -f $test.Backend))
            }
        }finally{Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue}
    }
    return $true
}
function Sanitize-Name([string]$text){if([string]::IsNullOrWhiteSpace($text)){return 'unknown'};$v=$text -replace '[^A-Za-z0-9._-]','_';if($v.Length -gt 80){$v=$v.Substring(0,80)};return $v.Trim('_')}
function Invalidate-EncoderCheck {
    Remove-Item -LiteralPath $EncoderCapabilities,$EncoderBenchmark,$EncoderTestStatus -Force -ErrorAction SilentlyContinue
    Write-Host (Msg 'The CPU/GPU verification was invalidated because FFmpeg changed.' 'CPU/GPU-kontrollen har ogiltigförklarats eftersom FFmpeg ändrades.') -ForegroundColor Yellow
}
function Write-ToolMetadata {
    param([string]$Folder,[string]$Tool,[string]$Version)
    $meta=[pscustomobject][ordered]@{Tool=$Tool;Version=$Version;ArchivedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');SourceFolder=$Folder}
    Write-Json (Join-Path $Folder 'mediaprep-tool-version.json') $meta
}
function Backup-ToolFolder {
    param([string]$Tool,[string]$CurrentFolder,[string]$VersionExe)
    if(-not(Test-Path -LiteralPath $CurrentFolder -PathType Container)){return $null}
    $files=@(Get-ChildItem -LiteralPath $CurrentFolder -Force -ErrorAction SilentlyContinue)
    if($files.Count -eq 0){return $null}
    $version=Get-VersionText $VersionExe
    $stamp=Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $name=$stamp+'__'+(Sanitize-Name $version)
    $toolBackups=Join-Path $BackupRoot $Tool;New-Item -ItemType Directory -Force -Path $toolBackups|Out-Null
    $destination=Join-Path $toolBackups $name
    Copy-Item -LiteralPath $CurrentFolder -Destination $destination -Recurse -Force
    Write-ToolMetadata -Folder $destination -Tool $Tool -Version $version
    Write-Host (Msg "Backup created: $destination" "Säkerhetskopia skapad: $destination") -ForegroundColor DarkCyan
    return $destination
}
function Restore-ToolBackup {
    param([string]$Tool,[string]$BackupFolder,[string]$TargetFolder,[string]$RequiredExe)
    $backupExe=Join-Path $BackupFolder $RequiredExe
    if(-not(Test-Path -LiteralPath $backupExe -PathType Leaf)){throw (Msg 'The selected backup is incomplete.' 'Den valda säkerhetskopian är ofullständig.')}
    $emergency=$null
    if(Test-Path -LiteralPath $TargetFolder -PathType Container){$emergency=Backup-ToolFolder -Tool ($Tool+'-before-restore') -CurrentFolder $TargetFolder -VersionExe (Join-Path $TargetFolder $RequiredExe)}
    try{
        Remove-Item -LiteralPath $TargetFolder -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath $BackupFolder -Destination $TargetFolder -Recurse -Force
        $restoredExe=Join-Path $TargetFolder $RequiredExe
        if(-not(Test-Path -LiteralPath $restoredExe -PathType Leaf)){throw 'Executable missing after restore.'}
        Write-Host (Msg "Restored $Tool successfully." "$Tool återställdes.") -ForegroundColor Green
        if($Tool -eq 'FFmpeg'){Invalidate-EncoderCheck}
    }catch{
        if($emergency -and (Test-Path -LiteralPath $emergency)){
            Remove-Item -LiteralPath $TargetFolder -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item -LiteralPath $emergency -Destination $TargetFolder -Recurse -Force
        }
        throw
    }
}
function Select-Backup {
    param([string]$Tool)
    $folder=Join-Path $BackupRoot $Tool
    $items=@(Get-ChildItem -LiteralPath $folder -Directory -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending)
    if($items.Count -eq 0){Write-Host (Msg "No saved $Tool versions." "Inga sparade $Tool-versioner finns.") -ForegroundColor Yellow;return $null}
    Write-Host ''
    Write-Host (Msg "Saved $Tool versions:" "Sparade $Tool-versioner:") -ForegroundColor Cyan
    for($i=0;$i -lt $items.Count;$i++){
        $meta=Read-Json (Join-Path $items[$i].FullName 'mediaprep-tool-version.json')
        $version=if($meta){[string]$meta.Version}else{$items[$i].Name}
        Write-Host ('[{0}] {1}' -f ($i+1),$version)
    }
    $answer=Read-Host (Msg 'Choose number or Enter to cancel' 'Välj nummer eller Enter för att avbryta')
    if([string]::IsNullOrWhiteSpace($answer)){return $null}
    $number=0;if (-not [int]::TryParse($answer,[ref]$number) -or $number -lt 1 -or $number -gt $items.Count){return $null}
    return $items[$number-1].FullName
}
function Get-CurrentMediaPrepVersion {
    # The program source is authoritative. Preferences can intentionally survive an
    # update package and may still contain the previous version until Start Center
    # synchronizes metadata.
    $core=Join-Path $Root 'App\MediaPrep.ps1'
    if(Test-Path -LiteralPath $core -PathType Leaf){
        try{
            $match=Select-String -LiteralPath $core -Pattern '\$Script:AppVersion\s*=\s*''([^'']+)''' | Select-Object -First 1
            if($match -and $match.Matches.Count-gt0){return [string]$match.Matches[0].Groups[1].Value}
        }catch{}
    }
    $doc=Read-Json $PrefPath
    $version=[string](Get-P $doc 'Version' '')
    if(-not[string]::IsNullOrWhiteSpace($version)){return $version}
    return 'unknown'
}
function Get-OnlineMediaPrepReleases {
    $items=@()
    try{
        $releases=Invoke-RestMethod -UseBasicParsing -Headers @{'User-Agent'='MediaPrep-MKV-Toolkit'} -Uri 'https://api.github.com/repos/anderssyren1967GH/MediaPrep-MKV-Toolkit/releases?per_page=20'
        foreach($release in @($releases)){
            if([bool](Get-P $release 'draft' $false) -or [bool](Get-P $release 'prerelease' $false)){continue}
            $tag=[string](Get-P $release 'tag_name' '')
            if($tag -notmatch '^v?(\d+\.\d+\.\d+)$'){continue}
            $version=$Matches[1]
            $asset=$null
            $wanted='MediaPrep-MKV-Toolkit-'+$version+'.zip'
            foreach($candidate in @(Get-P $release 'assets' @())){
                if([string](Get-P $candidate 'name' '') -eq $wanted){$asset=$candidate;break}
            }
            if($null-eq$asset){continue}
            $items += [pscustomobject][ordered]@{
                Version=$version;Tag=$tag;AssetName=[string](Get-P $asset 'name' '');Url=[string](Get-P $asset 'browser_download_url' '');Digest=[string](Get-P $asset 'digest' '');Published=[string](Get-P $release 'published_at' '')
            }
        }
    }catch{}
    return @($items | Sort-Object @{Expression={[version]$_.Version};Descending=$true} | Select-Object -First 5)
}
function Select-OnlineMediaPrepRelease {
    $items=@(Get-OnlineMediaPrepReleases)
    if($items.Count-eq0){throw (Msg 'Could not retrieve MediaPrep releases from GitHub.' 'Kunde inte hämta MediaPrep-versioner från GitHub.')}
    $current=Get-CurrentMediaPrepVersion
    Write-Host '';Write-Host (Msg 'MediaPrep versions available on GitHub:' 'MediaPrep-versioner tillgängliga på GitHub:') -ForegroundColor Cyan
    for($i=0;$i-lt$items.Count;$i++){
        $labels=New-Object System.Collections.Generic.List[string]
        if($i-eq0){$labels.Add((Msg 'latest' 'senaste'))}
        if([string]$items[$i].Version -eq $current){$labels.Add((Msg 'installed' 'installerad'))}
        $suffix=if($labels.Count-gt0){'  ['+($labels -join ', ')+']'}else{''}
        Write-Host ('[{0}] {1}{2}' -f ($i+1),$items[$i].Version,$suffix)
    }
    $answer=Read-Host (Msg 'Choose version number or Enter to cancel' 'Välj versionsnummer eller Enter för att avbryta')
    if([string]::IsNullOrWhiteSpace($answer)){return $null}
    $number=0;if(-not[int]::TryParse($answer,[ref]$number) -or $number-lt1 -or $number-gt$items.Count){return $null}
    return $items[$number-1]
}
function Stage-MediaPrepRelease {
    param([Parameter(Mandatory=$true)][object]$Release)
    $current=Get-CurrentMediaPrepVersion
    $target=[string](Get-P $Release 'Version' '')
    if([string]::IsNullOrWhiteSpace($target)){throw 'Invalid MediaPrep version selection.'}
    if($target -eq $current){Write-Host (Msg 'That MediaPrep version is already installed.' 'Den MediaPrep-versionen är redan installerad.') -ForegroundColor Yellow;return $false}
    try{
        if([version]$target -lt [version]$current){
            Write-Host (Msg ("You are about to install an older MediaPrep version. Installed: {0}; selected: {1}." -f $current,$target) ("Du håller på att installera en äldre MediaPrep-version. Installerad: {0}; vald: {1}." -f $current,$target)) -ForegroundColor Yellow
            $confirm=Read-Host (Msg 'Continue downgrade? [Y/N]' 'Fortsätt nedgradering? [J/N]')
            if($confirm -notmatch '^(?i:y|yes|j|ja)$'){return $false}
        }
    }catch{}
    $url=[string](Get-P $Release 'Url' '')
    $assetName=[string](Get-P $Release 'AssetName' '')
    if([string]::IsNullOrWhiteSpace($url)-or[string]::IsNullOrWhiteSpace($assetName)){throw 'The selected release has no downloadable package.'}
    $zip=Join-Path $Downloads $assetName
    $extract=Join-Path $Downloads ('mediaprep-release-'+$target+'-'+[guid]::NewGuid().ToString('N'))
    try{
        Download-File $url $zip
        $digest=[string](Get-P $Release 'Digest' '')
        if($digest -match '^sha256:([0-9A-Fa-f]{64})$'){
            $expected=$Matches[1];$actual=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
            if($actual-ne$expected){throw 'MediaPrep release SHA-256 verification failed.'}
            Write-Host 'SHA-256: OK' -ForegroundColor Green
        }
        New-Item -ItemType Directory -Path $extract -Force|Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $launcher=Get-ChildItem -LiteralPath $extract -Filter 'Start MediaPrep.cmd' -File -Recurse|Select-Object -First 1
        if($null-eq$launcher){throw 'The MediaPrep release does not contain Start MediaPrep.cmd.'}
        $stageRoot=$launcher.Directory.FullName
        if(-not(Test-Path -LiteralPath (Join-Path $stageRoot 'App\MediaPrep-Start.ps1') -PathType Leaf)){throw 'The MediaPrep release is incomplete.'}
        Write-Json $MediaPrepUpdateRequest ([pscustomobject][ordered]@{TargetVersion=$target;CurrentVersion=$current;StageRoot=$stageRoot;IsBackupRestore=$false;RequestedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')})
        Write-Host (Msg ("MediaPrep {0} is downloaded and verified. Start Center will close, install it, and restart." -f $target) ("MediaPrep {0} är hämtad och verifierad. Start Center stängs, installerar versionen och startar om." -f $target)) -ForegroundColor Green
        return $true
    }finally{Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue}
}
function Select-ProgramBackup {
    $items=@(Get-ChildItem -LiteralPath $ProgramBackupRoot -Directory -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending)
    if($items.Count-eq0){Write-Host (Msg 'No saved MediaPrep program versions.' 'Inga sparade MediaPrep-programversioner finns.') -ForegroundColor Yellow;return $null}
    Write-Host '';Write-Host (Msg 'Saved MediaPrep program versions:' 'Sparade MediaPrep-programversioner:') -ForegroundColor Cyan
    for($i=0;$i-lt$items.Count;$i++){
        $meta=Read-Json (Join-Path $items[$i].FullName 'mediaprep-program-version.json')
        $version=if($meta){[string](Get-P $meta 'Version' $items[$i].Name)}else{$items[$i].Name}
        Write-Host ('[{0}] {1}' -f ($i+1),$version)
    }
    $answer=Read-Host (Msg 'Choose number or Enter to cancel' 'Välj nummer eller Enter för att avbryta')
    if([string]::IsNullOrWhiteSpace($answer)){return $null}
    $number=0;if(-not[int]::TryParse($answer,[ref]$number)-or$number-lt1-or$number-gt$items.Count){return $null}
    return $items[$number-1]
}
function Request-MediaPrepBackupRestore {
    $backup=Select-ProgramBackup
    if($null-eq$backup){return $false}
    $meta=Read-Json (Join-Path $backup.FullName 'mediaprep-program-version.json')
    $target=if($meta){[string](Get-P $meta 'Version' $backup.Name)}else{$backup.Name}
    Write-Json $MediaPrepUpdateRequest ([pscustomobject][ordered]@{TargetVersion=$target;CurrentVersion=(Get-CurrentMediaPrepVersion);StageRoot=$backup.FullName;IsBackupRestore=$true;RequestedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')})
    Write-Host (Msg ("MediaPrep {0} will be restored when this window closes." -f $target) ("MediaPrep {0} återställs när detta fönster stängs." -f $target)) -ForegroundColor Green
    return $true
}

function Show-RestoreMenu {
    Write-Host ''
    Write-Host (Msg '[P] Restore MediaPrep, [F] FFmpeg, [M] MKVToolNix, [Q] back' '[P] Återställ MediaPrep, [F] FFmpeg, [M] MKVToolNix, [Q] tillbaka') -ForegroundColor White
    $choice=Read-Host '>'
    if ($choice -match '^[Pp]$'){return (Request-MediaPrepBackupRestore)}
    elseif ($choice -match '^[Ff]$'){$backup=Select-Backup -Tool 'FFmpeg';if($backup){Restore-ToolBackup -Tool 'FFmpeg' -BackupFolder $backup -TargetFolder (Join-Path $ToolsRoot 'FFmpeg') -RequiredExe 'ffmpeg.exe'}}
    elseif ($choice -match '^[Mm]$'){$backup=Select-Backup -Tool 'MKVToolNix';if($backup){Restore-ToolBackup -Tool 'MKVToolNix' -BackupFolder $backup -TargetFolder (Join-Path $ToolsRoot 'MKVToolNix') -RequiredExe 'mkvmerge.exe'}}
    return $false
}
function Get-OnlineFfmpegReleases {
    $items=@()
    try{
        $releases=Invoke-RestMethod -UseBasicParsing -Headers @{'User-Agent'='MediaPrep-MKV-Toolkit'} -Uri 'https://api.github.com/repos/GyanD/codexffmpeg/releases?per_page=30'
        foreach($release in @($releases)){
            $tag=[string](Get-P $release 'tag_name' '')
            if($tag -notmatch '^\d+\.\d+(?:\.\d+)?$'){continue}
            $asset=$null
            foreach($candidate in @(Get-P $release 'assets' @())){
                $name=[string](Get-P $candidate 'name' '')
                if($name -match '(?:release-essentials|essentials_build)\.zip$'){
                    $asset=$candidate;break
                }
            }
            if($null-ne$asset){
                $items += [pscustomobject]@{
                    Version=$tag
                    AssetName=[string](Get-P $asset 'name' '')
                    Url=[string](Get-P $asset 'browser_download_url' '')
                    Published=[string](Get-P $release 'published_at' '')
                }
            }
        }
        $items=@($items | Sort-Object @{Expression={[version]$_.Version};Descending=$true})
    }catch{}
    if($items.Count -lt 5){
        # Fallback: Gyan's build page exposes the current and archived release links.
        try{
            $html=(Invoke-WebRequest -UseBasicParsing -Uri 'https://www.gyan.dev/ffmpeg/builds/').Content
            $latestMatch=[regex]::Match($html,'latest release[\s\S]{0,1200}?version:\s*</?[^>]*>\s*([0-9]+\.[0-9]+(?:\.[0-9]+)?)','IgnoreCase')
            if($latestMatch.Success){
                $v=$latestMatch.Groups[1].Value
                if(-not(@($items|Where-Object{$_.Version -eq $v}).Count)){
                    $items += [pscustomobject]@{Version=$v;AssetName='ffmpeg-release-essentials.zip';Url='https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip';Published=''}
                }
            }
            $matches=[regex]::Matches($html,'ffmpeg-([0-9]+\.[0-9]+(?:\.[0-9]+)?)-essentials_build\.zip','IgnoreCase')
            foreach($m in $matches){
                $v=$m.Groups[1].Value
                if(@($items|Where-Object{$_.Version -eq $v}).Count){continue}
                $name=$m.Value
                $items += [pscustomobject]@{Version=$v;AssetName=$name;Url=('https://www.gyan.dev/ffmpeg/builds/packages/'+$name);Published=''}
            }
        }catch{}
    }
    $items=@($items | Sort-Object @{Expression={[version]$_.Version};Descending=$true})
    return @($items | Select-Object -First 5)
}
function Select-OnlineFfmpegRelease {
    $items=@(Get-OnlineFfmpegReleases)
    if($items.Count-eq0){throw (Msg 'Could not retrieve online FFmpeg releases.' 'Kunde inte hämta FFmpeg-versioner online.')}
    $current=Get-ShortToolVersion (Get-VersionText (Join-Path $ToolsRoot 'FFmpeg\ffmpeg.exe')) 'FFmpeg'
    Write-Host '';Write-Host (Msg 'FFmpeg versions available online:' 'FFmpeg-versioner tillgängliga online:') -ForegroundColor Cyan
    for($i=0;$i-lt$items.Count;$i++){
        $suffix=if([string]$items[$i].Version -eq $current){'  '+(Msg '[installed]' '[installerad]')}else{''}
        Write-Host ('[{0}] {1}{2}' -f ($i+1),$items[$i].Version,$suffix)
    }
    $answer=Read-Host (Msg 'Choose version number or Enter to cancel' 'Välj versionsnummer eller Enter för att avbryta')
    if([string]::IsNullOrWhiteSpace($answer)){return $null}
    $number=0;if(-not [int]::TryParse($answer,[ref]$number) -or $number -lt 1 -or $number -gt $items.Count){return $null}
    return $items[$number-1]
}
function Install-FFmpeg {
    param([object]$Release)
    $target=Join-Path $ToolsRoot 'FFmpeg'
    if($null-eq$Release){$Release=Select-OnlineFfmpegRelease;if($null-eq$Release){return $null}}
    $assetName=[string](Get-P $Release 'AssetName' '')
    $url=[string](Get-P $Release 'Url' '')
    $requestedVersion=[string](Get-P $Release 'Version' '')
    if([string]::IsNullOrWhiteSpace($assetName)-or[string]::IsNullOrWhiteSpace($url)){throw 'Invalid FFmpeg release selection.'}
    $zip=Join-Path $Downloads $assetName;Download-File $url $zip
    $extract=Join-Path $Downloads ('ffmpeg-stage-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $extract|Out-Null
    $newFolder=Join-Path $Downloads ('ffmpeg-ready-'+[guid]::NewGuid().ToString('N'))
    try{
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $bin=Get-ChildItem $extract -Directory|Select-Object -First 1|ForEach-Object{Join-Path $_.FullName 'bin'}
        $newFfmpeg=Join-Path $bin 'ffmpeg.exe';$newFfprobe=Join-Path $bin 'ffprobe.exe'
        if (-not (Test-Path $newFfmpeg) -or -not (Test-Path $newFfprobe)){throw 'ffmpeg.exe/ffprobe.exe missing after extraction.'}
        $version=Get-VersionText $newFfmpeg;if([string]::IsNullOrWhiteSpace($version)){throw 'The downloaded FFmpeg build could not be executed.'}
        $features=Test-FFmpegFeatures $newFfmpeg;if(-not$features.CpuHevc){throw 'The downloaded FFmpeg build does not contain libx265.'}
        [void](Test-StagedFfmpegCompatibility -Exe $newFfmpeg)
        New-Item -ItemType Directory -Force -Path $newFolder|Out-Null;Copy-Item (Join-Path $bin '*') $newFolder -Recurse -Force
        $backup=Backup-ToolFolder -Tool 'FFmpeg' -CurrentFolder $target -VersionExe (Join-Path $target 'ffmpeg.exe')
        try{
            Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue;Move-Item -LiteralPath $newFolder -Destination $target
            if([string]::IsNullOrWhiteSpace((Get-VersionText (Join-Path $target 'ffmpeg.exe')))){throw 'FFmpeg failed verification after activation.'}
        }catch{
            Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
            if($backup){Copy-Item -LiteralPath $backup -Destination $target -Recurse -Force}
            throw
        }
        Invalidate-EncoderCheck
        Write-Host (Msg ("Activated FFmpeg {0}." -f $requestedVersion) ("Aktiverade FFmpeg {0}." -f $requestedVersion)) -ForegroundColor Green
        return [pscustomobject]@{FFmpeg=(Join-Path $target 'ffmpeg.exe');FFprobe=(Join-Path $target 'ffprobe.exe');Version=$version}
    }finally{Remove-Item $extract,$newFolder -Recurse -Force -ErrorAction SilentlyContinue}
}
function Get-OnlineMkvVersions {
    $versions=@()
    # The official Windows release archive contains every published version.
    # Reading the archive index is more reliable than the news page when the
    # user wants several older versions instead of only the newest release.
    try{
        $html=(Invoke-WebRequest -UseBasicParsing -Uri 'https://mkvtoolnix.download/windows/releases/').Content
        $matches=[regex]::Matches($html,'href=[\"''](\d+(?:\.\d+){1,2})/[\"'']','IgnoreCase')
        foreach($m in $matches){
            $v=$m.Groups[1].Value
            if($versions -notcontains $v){$versions += $v}
        }
    }catch{}
    # Fallback to the official news page if directory listing parsing ever changes.
    if($versions.Count -eq 0){
        try{
            $html=(Invoke-WebRequest -UseBasicParsing -Uri 'https://mkvtoolnix.download/').Content
            $matches=[regex]::Matches($html,'Released v(\d+(?:\.\d+){1,2})','IgnoreCase')
            foreach($m in $matches){
                $v=$m.Groups[1].Value
                if($versions -notcontains $v){$versions += $v}
            }
        }catch{}
    }
    $versions=@($versions | Sort-Object {[version]$_} -Descending | Select-Object -First 5)
    return @($versions)
}
function Select-OnlineMkvVersion {
    $items=@(Get-OnlineMkvVersions)
    if($items.Count-eq0){throw (Msg 'Could not retrieve online MKVToolNix releases.' 'Kunde inte hämta MKVToolNix-versioner online.')}
    $current=Get-ShortToolVersion (Get-VersionText (Join-Path $ToolsRoot 'MKVToolNix\mkvmerge.exe')) 'MKVToolNix'
    Write-Host '';Write-Host (Msg 'MKVToolNix versions available online:' 'MKVToolNix-versioner tillgängliga online:') -ForegroundColor Cyan
    for($i=0;$i-lt$items.Count;$i++){
        $suffix=if([string]$items[$i] -eq $current){'  '+(Msg '[installed]' '[installerad]')}else{''}
        Write-Host ('[{0}] {1}{2}' -f ($i+1),$items[$i],$suffix)
    }
    $answer=Read-Host (Msg 'Choose version number or Enter to cancel' 'Välj versionsnummer eller Enter för att avbryta')
    if([string]::IsNullOrWhiteSpace($answer)){return $null}
    $number=0;if(-not [int]::TryParse($answer,[ref]$number) -or $number -lt 1 -or $number -gt $items.Count){return $null}
    return [string]$items[$number-1]
}
function Install-MKVToolNix {
    param([string]$Version)
    $target=Join-Path $ToolsRoot 'MKVToolNix'
    if([string]::IsNullOrWhiteSpace($Version)){$Version=Select-OnlineMkvVersion;if([string]::IsNullOrWhiteSpace($Version)){return $null}}
    $name="mkvtoolnix-64-bit-$Version-setup.exe";$url="https://mkvtoolnix.download/windows/releases/$Version/$name";$setup=Join-Path $Downloads $name;Download-File $url $setup
    $stage=Join-Path $Downloads ('mkvtoolnix-stage-'+[guid]::NewGuid().ToString('N'))
    try{
        New-Item -ItemType Directory -Force -Path $stage|Out-Null
        $p=Start-Process -FilePath $setup -ArgumentList @('/S',('/D='+$stage)) -Wait -PassThru
        if($p.ExitCode -ne 0){throw "MKVToolNix installer exit code $($p.ExitCode)"}
        $newExe=Join-Path $stage 'mkvmerge.exe';if(-not(Test-Path $newExe)){throw 'mkvmerge.exe missing after staged installation.'}
        $versionText=Get-VersionText $newExe;if([string]::IsNullOrWhiteSpace($versionText)){throw 'The staged MKVToolNix build could not be executed.'}
        $backup=Backup-ToolFolder -Tool 'MKVToolNix' -CurrentFolder $target -VersionExe (Join-Path $target 'mkvmerge.exe')
        try{
            Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue;Move-Item -LiteralPath $stage -Destination $target
            if([string]::IsNullOrWhiteSpace((Get-VersionText (Join-Path $target 'mkvmerge.exe')))){throw 'MKVToolNix failed verification after activation.'}
        }catch{
            Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
            if($backup){Copy-Item -LiteralPath $backup -Destination $target -Recurse -Force}
            throw
        }
        Write-Host (Msg ("Activated MKVToolNix {0}." -f $Version) ("Aktiverade MKVToolNix {0}." -f $Version)) -ForegroundColor Green
        return (Join-Path $target 'mkvmerge.exe')
    }finally{Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue}
}

$prefs=Read-Json $PrefPath;if(-not$prefs){$prefs=[pscustomobject]@{}}
$ffmpeg=[string](Get-P $prefs 'FFmpegPath' '');$ffprobe=[string](Get-P $prefs 'FFprobePath' '');$mkv=[string](Get-P $prefs 'MkvmergePath' '')
if ($ffmpeg -and -not [IO.Path]::IsPathRooted($ffmpeg)){$ffmpeg=Join-Path $Root $ffmpeg};if ($ffprobe -and -not [IO.Path]::IsPathRooted($ffprobe)){$ffprobe=Join-Path $Root $ffprobe};if ($mkv -and -not [IO.Path]::IsPathRooted($mkv)){$mkv=Join-Path $Root $mkv}
Write-Host '';Write-Host 'MediaPrep MKV Toolkit - Versions / external tools' -ForegroundColor White;Write-Host ('='*72)
$gpus=@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Name);Write-Host ((Msg 'Detected graphics:' 'Identifierad grafik:')+' '+($gpus-join', '))
Write-Host ("MediaPrep : {0}" -f (Get-CurrentMediaPrepVersion));Write-Host "FFmpeg    : $(if($ffmpeg){Get-VersionText $ffmpeg}else{'Missing'})";Write-Host "MKVToolNix: $(if($mkv){Get-VersionText $mkv}else{'Missing'})"
if(Test-Path $ffmpeg){$features=Test-FFmpegFeatures $ffmpeg;Write-Host "CPU HEVC=$($features.CpuHevc)  NVENC=$($features.Nvenc)  QSV=$($features.Qsv)  AMF=$($features.Amf)  CUDA=$($features.Cuda)"}
Write-Host '';Write-Host (Msg '[P] MediaPrep version, [F] FFmpeg version, [M] MKVToolNix version, [A] latest external tools, [R] rollback, [Q] quit' '[P] MediaPrep-version, [F] FFmpeg-version, [M] MKVToolNix-version, [A] senaste externa verktygen, [R] återställ, [Q] avsluta') -ForegroundColor White
$choice=Read-Host '>'
$updateRequested=$false
try{
    if ($choice -match '^[Rr]$'){$updateRequested=[bool](Show-RestoreMenu)}
    if ($choice -match '^[Pp]$'){
        $selected=Select-OnlineMediaPrepRelease
        if($selected){$updateRequested=[bool](Stage-MediaPrepRelease -Release $selected)}
    }
    if ($choice -match '^[Ff]$'){
        $selected=Select-OnlineFfmpegRelease
        if($selected){$result=Install-FFmpeg -Release $selected;$prefs|Add-Member -NotePropertyName FFmpegPath -NotePropertyValue 'Tools\FFmpeg\ffmpeg.exe' -Force;$prefs|Add-Member -NotePropertyName FFprobePath -NotePropertyValue 'Tools\FFmpeg\ffprobe.exe' -Force}
    }
    if ($choice -match '^[Mm]$'){
        $selected=Select-OnlineMkvVersion
        if($selected){$result=Install-MKVToolNix -Version $selected;$prefs|Add-Member -NotePropertyName MkvmergePath -NotePropertyValue 'Tools\MKVToolNix\mkvmerge.exe' -Force}
    }
    if ($choice -match '^[Aa]$'){
        $ff=@(Get-OnlineFfmpegReleases|Select-Object -First 1)
        if($ff.Count-gt0){$result=Install-FFmpeg -Release $ff[0];$prefs|Add-Member -NotePropertyName FFmpegPath -NotePropertyValue 'Tools\FFmpeg\ffmpeg.exe' -Force;$prefs|Add-Member -NotePropertyName FFprobePath -NotePropertyValue 'Tools\FFmpeg\ffprobe.exe' -Force}
        $mv=@(Get-OnlineMkvVersions|Select-Object -First 1)
        if($mv.Count-gt0){$result=Install-MKVToolNix -Version ([string]$mv[0]);$prefs|Add-Member -NotePropertyName MkvmergePath -NotePropertyValue 'Tools\MKVToolNix\mkvmerge.exe' -Force}
    }
    if (-not$updateRequested -and $choice -notmatch '^[QqRrPp]$'){Write-Json $PrefPath $prefs;Write-Host (Msg 'Preferences updated. Previous active versions are kept for local rollback.' 'Inställningarna har uppdaterats. Föregående aktiva versioner sparas för lokal återställning.') -ForegroundColor Green}
}catch{Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red}
if(-not$updateRequested){Write-Host '';Read-Host (Msg 'Press Enter to close' 'Tryck Enter för att stänga')|Out-Null}
