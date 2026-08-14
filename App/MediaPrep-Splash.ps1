#requires -Version 5.1
# Copyright (C) 2026 Anders Syrén
# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$SignalPath,
    [int]$ParentPid = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

# The splash is intentionally isolated from Start Center. If it cannot run, it exits
# silently and must never affect MediaPrep startup.
if ([string]$ExecutionContext.SessionState.LanguageMode -eq 'ConstrainedLanguage') { exit 0 }

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()

    $imagePath=Join-Path (Join-Path $Root 'Assets') 'Media-PrepMKV-Toolkit-Splash.png'
    if(-not(Test-Path -LiteralPath $imagePath -PathType Leaf)){exit 0}

    $script:SplashImage=[Drawing.Image]::FromFile($imagePath)
    $targetWidth=760
    $targetHeight=[int][Math]::Round($targetWidth*([double]$script:SplashImage.Height/[double]$script:SplashImage.Width))
    if($targetHeight-lt240){$targetHeight=240}
    if($targetHeight-gt520){$targetHeight=520}

    $script:SplashForm=New-Object Windows.Forms.Form
    $script:SplashForm.FormBorderStyle=[Windows.Forms.FormBorderStyle]::None
    $script:SplashForm.StartPosition='CenterScreen'
    $script:SplashForm.ShowInTaskbar=$false
    $script:SplashForm.TopMost=$true
    $script:SplashForm.ClientSize=New-Object Drawing.Size($targetWidth,$targetHeight)

    $picture=New-Object Windows.Forms.PictureBox
    $picture.Dock=[Windows.Forms.DockStyle]::Fill
    $picture.SizeMode=[Windows.Forms.PictureBoxSizeMode]::Zoom
    $picture.Image=$script:SplashImage
    $script:SplashForm.Controls.Add($picture)

    $script:StartedUtc=[DateTime]::UtcNow
    $script:Timer=New-Object Windows.Forms.Timer
    $script:Timer.Interval=100
    $script:Timer.Add_Tick({
        try{
            if(Test-Path -LiteralPath $SignalPath -PathType Leaf){$script:SplashForm.Close();return}
            if(([DateTime]::UtcNow-$script:StartedUtc).TotalSeconds-ge60){$script:SplashForm.Close();return}
            if($ParentPid-gt0 -and ([DateTime]::UtcNow-$script:StartedUtc).TotalMilliseconds-ge1000){
                try{[void](Get-Process -Id $ParentPid -ErrorAction Stop)}catch{$script:SplashForm.Close();return}
            }
        }catch{}
    })
    $script:SplashForm.Add_FormClosed({
        try{$script:Timer.Stop();$script:Timer.Dispose()}catch{}
        try{$picture.Image=$null;$picture.Dispose()}catch{}
        try{$script:SplashImage.Dispose()}catch{}
        try{Remove-Item -LiteralPath $SignalPath -Force -ErrorAction SilentlyContinue}catch{}
    })
    $script:Timer.Start()
    [void]$script:SplashForm.ShowDialog()
}
catch {
    try{Remove-Item -LiteralPath $SignalPath -Force -ErrorAction SilentlyContinue}catch{}
    exit 0
}
