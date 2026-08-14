#requires -Version 5.1
# Copyright (C) 2026 Anders Syrén
# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param(
    [string]$Root = '',
    [string]$RequiredLanguageFileVersion = '1.7.5'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

# Windows PowerShell 5.1 can bind param() default expressions before $PSScriptRoot
# is populated. Resolve the script/root path after parameter binding instead.
if([string]::IsNullOrWhiteSpace($Root)){
    $scriptDir=[string]$PSScriptRoot
    if([string]::IsNullOrWhiteSpace($scriptDir) -and -not[string]::IsNullOrWhiteSpace([string]$MyInvocation.MyCommand.Path)){
        $scriptDir=Split-Path -Parent ([string]$MyInvocation.MyCommand.Path)
    }
    if([string]::IsNullOrWhiteSpace($scriptDir)){throw 'Could not determine the MediaPrep script folder.'}
    $Root=Split-Path -Parent $scriptDir
}
$languageFolder=Join-Path $Root 'Languages'
$masterPath=Join-Path $languageFolder 'mediaprep.en-US.json'
$errors=New-Object System.Collections.Generic.List[string]
$warnings=New-Object System.Collections.Generic.List[string]

function Add-Error([string]$Text){$errors.Add($Text)}
function Add-Warning([string]$Text){$warnings.Add($Text)}
function Read-OrderedJson([string]$Path){
    try{return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json)}catch{Add-Error ("Invalid JSON: {0} - {1}" -f $Path,$_.Exception.Message);return $null}
}
function Get-Names([object]$Doc){if($null-eq$Doc){return @()};return @($Doc.PSObject.Properties|ForEach-Object{$_.Name})}
function Get-Value([object]$Doc,[string]$Name){$p=$Doc.PSObject.Properties[$Name];if($null-eq$p){return $null};return $p.Value}
function Get-Placeholders([string]$Text){
    if($null-eq$Text){return @()}
    $m=[regex]::Matches([string]$Text,'(?<!\{)\{(\d+)(?:[^}]*)\}(?!\})')
    return @($m|ForEach-Object{$_.Groups[1].Value}|Sort-Object)
}
function Test-Bom([string]$Path){
    try{
        $bytes=[IO.File]::ReadAllBytes($Path)
        return ($bytes.Length-ge3 -and $bytes[0]-eq0xEF -and $bytes[1]-eq0xBB -and $bytes[2]-eq0xBF)
    }catch{return $false}
}

if(-not(Test-Path -LiteralPath $masterPath -PathType Leaf)){throw "Master language file is missing: $masterPath"}
$master=Read-OrderedJson $masterPath
if($null-eq$master){throw 'The en-US master language file could not be parsed.'}
$masterNames=Get-Names $master
$metaNames=@('SchemaVersion','LanguageFileVersion','CompatibleMediaPrepVersion','Culture','LanguageCode','LanguageName','NativeName','AuthorCredit')
if((@($masterNames|Select-Object -First $metaNames.Count) -join '|') -cne ($metaNames -join '|')){Add-Error 'The en-US master metadata keys are missing or not in the required order.'}

foreach($file in @(Get-ChildItem -LiteralPath $languageFolder -Filter 'mediaprep.*.json' -File|Sort-Object Name)){
    if(-not(Test-Bom $file.FullName)){Add-Error ("UTF-8 BOM missing: {0}" -f $file.Name)}
    $doc=Read-OrderedJson $file.FullName
    if($null-eq$doc){continue}
    $names=Get-Names $doc
    if([string](Get-Value $doc 'SchemaVersion') -ne '1'){Add-Error ("SchemaVersion must be 1: {0}" -f $file.Name)}
    if([string](Get-Value $doc 'LanguageFileVersion') -ne $RequiredLanguageFileVersion){Add-Error ("LanguageFileVersion mismatch in {0}: found {1}, expected {2}" -f $file.Name,(Get-Value $doc 'LanguageFileVersion'),$RequiredLanguageFileVersion)}
    $culture=[string](Get-Value $doc 'Culture')
    if([string]::IsNullOrWhiteSpace($culture)){Add-Error ("Culture is empty: {0}" -f $file.Name)}
    elseif($file.Name -ne ('mediaprep.'+$culture+'.json')){Add-Error ("Culture/filename mismatch: {0} -> {1}" -f $file.Name,$culture)}
    if([string](Get-Value $doc 'LanguageCode') -cne $culture){Add-Error ("LanguageCode/Culture mismatch in {0}: LanguageCode={1}, Culture={2}" -f $file.Name,(Get-Value $doc 'LanguageCode'),$culture)}
    if($names.Count-ne$masterNames.Count){Add-Error ("Key count differs from en-US: {0} has {1}, master has {2}" -f $file.Name,$names.Count,$masterNames.Count)}
    $max=[Math]::Min($names.Count,$masterNames.Count)
    for($i=0;$i-lt$max;$i++){
        if($names[$i]-cne$masterNames[$i]){Add-Error ("Key order/name mismatch in {0} at position {1}: '{2}' vs master '{3}'" -f $file.Name,($i+1),$names[$i],$masterNames[$i]);break}
    }
    foreach($key in $masterNames){
        $p=$doc.PSObject.Properties[$key]
        if($null-eq$p){Add-Error ("Missing key in {0}: {1}" -f $file.Name,$key);continue}
        if($metaNames -notcontains $key -and [string]::IsNullOrWhiteSpace([string]$p.Value)){Add-Error ("Empty translation in {0}: {1}" -f $file.Name,$key)}
        if($metaNames -contains $key){continue}
        $masterText=[string](Get-Value $master $key)
        $localText=[string]$p.Value
        $a=Get-Placeholders $masterText
        $b=Get-Placeholders $localText
        if(($a -join ',')-cne($b -join ',')){Add-Error ("Placeholder mismatch in {0}: {1} master=[{2}] local=[{3}]" -f $file.Name,$key,($a-join','),($b-join','))}
        if($localText -cmatch '�|Ã.|Â.|â€|ðŸ'){Add-Error ("Possible mojibake in {0}: {1}" -f $file.Name,$key)}
    }
}


# Every literal language-resource reference in the shipped PowerShell files must
# exist in the en-US master. This prevents a new UI string from silently relying
# on its inline fallback and then being missed when the full translation set is built.
$sourceFiles=@()
foreach($sourceFolder in @((Join-Path $Root 'App'),(Join-Path $Root 'Installer'))){
    if(Test-Path -LiteralPath $sourceFolder -PathType Container){$sourceFiles+=@(Get-ChildItem -LiteralPath $sourceFolder -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue)}
}
$sourceKeyRegex=[regex]"\bT\s+'([^']+)'"
$earlyKeyRegex=[regex]"Get-EarlyLanguageValue\s+\$[^\s]+\s+'([^']+)'"
foreach($sourceFile in $sourceFiles){
    $sourceText=Get-Content -LiteralPath $sourceFile.FullName -Raw -Encoding UTF8
    foreach($match in $sourceKeyRegex.Matches($sourceText)){
        $key=$match.Groups[1].Value
        if($masterNames -notcontains $key){Add-Error ("Language key referenced by {0} is missing from en-US: {1}" -f $sourceFile.Name,$key)}
    }
    foreach($match in $earlyKeyRegex.Matches($sourceText)){
        $key=$match.Groups[1].Value
        if($masterNames -notcontains $key){Add-Error ("Early-start language key referenced by {0} is missing from en-US: {1}" -f $sourceFile.Name,$key)}
    }
    $isValidator=([IO.Path]::GetFullPath($sourceFile.FullName) -eq [IO.Path]::GetFullPath([string]$MyInvocation.MyCommand.Path))
    if(-not$isValidator -and $sourceText -match '\bMsg\s*\('){Add-Error ("Legacy Msg(...) localization remains in: {0}" -f $sourceFile.FullName)}
}

if($warnings.Count-gt0){foreach($w in $warnings){Write-Host ('[WARN ] '+$w) -ForegroundColor Yellow}}
if($errors.Count-gt0){foreach($e in $errors){Write-Host ('[ERROR] '+$e) -ForegroundColor Red};Write-Host ("Language validation FAILED: {0} error(s)." -f $errors.Count) -ForegroundColor Red;exit 1}
Write-Host ("Language validation OK: {0} language file(s), {1} keys, version {2}." -f @(Get-ChildItem -LiteralPath $languageFolder -Filter 'mediaprep.*.json' -File).Count,$masterNames.Count,$RequiredLanguageFileVersion) -ForegroundColor Green
exit 0
