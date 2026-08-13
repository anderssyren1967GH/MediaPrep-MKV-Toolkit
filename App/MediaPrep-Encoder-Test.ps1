#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [int]$BenchmarkSeconds = 12
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$DataFolder       = Join-Path $Root 'Data'
$TempFolder       = Join-Path $DataFolder 'Temp\EncoderBenchmark'
$PreferencesPath  = Join-Path $DataFolder 'mediaprep.preferences.json'
$CapabilitiesPath = Join-Path $DataFolder 'encoder-capabilities.json'
$BenchmarkPath    = Join-Path $DataFolder 'encoder-benchmark.json'
$StatusPath       = Join-Path $DataFolder 'encoder-test-status.json'
$LogFolder        = Join-Path $Root 'Loggar'
$LogPath          = Join-Path $LogFolder ("MediaPrep-Encoder-Test_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))

foreach ($folder in @($DataFolder,$TempFolder,$LogFolder)) {
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
}

function Get-P {
    param([object]$Object,[string]$Name,[object]$Default=$null)
    if ($null -eq $Object) { return $Default }
    $property=$Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

function Write-JsonAtomic {
    param([string]$Path,[object]$Value,[int]$Depth=12)
    $dir=Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    $tmp=$Path+'.tmp-'+[guid]::NewGuid().ToString('N')
    try {
        $json=$Value | ConvertTo-Json -Depth $Depth
        [IO.File]::WriteAllText($tmp,$json,(New-Object Text.UTF8Encoding($true)))
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Write-Log {
    param([string]$Level,[string]$Message)
    $line='{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$Level,$Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Set-TestStatus {
    param([string]$Stage,[string]$Current,[int]$Percent,[string]$Message='',[AllowNull()][object]$Details=$null)
    if ($Percent -lt 0) { $Percent=0 }
    if ($Percent -gt 100) { $Percent=100 }
    Write-JsonAtomic -Path $StatusPath -Value ([pscustomobject][ordered]@{
        Stage=$Stage
        Current=$Current
        Percent=$Percent
        Message=$Message
        Details=$Details
        UpdatedUtc=(Get-Date).ToUniversalTime().ToString('o')
    }) -Depth 12
}
function New-LiveEncoderDetails {
    param([object]$Candidate,[object]$Benchmark,[System.Collections.IDictionary]$Capabilities,[bool]$Verified=$false,[string]$Reason='')
    return [pscustomobject][ordered]@{
        Id=[string]$Candidate.Id
        HardwareName=[string]$Candidate.HardwareName
        Backend=[string]$Candidate.Backend
        Encoder=[string]$Candidate.Encoder
        DriverVersion=[string]$Candidate.DriverVersion
        Verified=$Verified
        Benchmark=$Benchmark
        Capabilities=[pscustomobject]$Capabilities
        Reason=$Reason
    }
}

function Resolve-ToolPath {
    param([object]$Value,[string]$Fallback)
    $path=[string]$Value
    if ([string]::IsNullOrWhiteSpace($path)) { $path=$Fallback }
    if (-not [IO.Path]::IsPathRooted($path)) { $path=Join-Path $Root $path }
    try { return [IO.Path]::GetFullPath($path) }
    catch { return (Join-Path $Root $Fallback) }
}

function ConvertTo-NativeArgument {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"','$1$1\\"' -replace '(\\+)$','$1$1') + '"'
}

function Join-NativeArguments {
    param([string[]]$Arguments)
    return (($Arguments | ForEach-Object { ConvertTo-NativeArgument ([string]$_) }) -join ' ')
}

function Invoke-NativeCapture {
    param([string]$FilePath,[string[]]$Arguments)
    $process=$null
    try {
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=$FilePath
        $psi.Arguments=Join-NativeArguments $Arguments
        $psi.UseShellExecute=$false
        $psi.CreateNoWindow=$true
        $psi.RedirectStandardOutput=$true
        $psi.RedirectStandardError=$true
        $psi.StandardOutputEncoding=[Text.Encoding]::UTF8
        $psi.StandardErrorEncoding=[Text.Encoding]::UTF8
        $process=New-Object Diagnostics.Process
        $process.StartInfo=$psi
        if (-not $process.Start()) { throw "Could not start: $FilePath" }
        $outTask=$process.StandardOutput.ReadToEndAsync()
        $errTask=$process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode=[int]$process.ExitCode
            StdOut=[string]$outTask.Result
            StdErr=[string]$errTask.Result
            Text=([string]$outTask.Result+[string]$errTask.Result)
        }
    }
    catch {
        return [pscustomobject]@{ExitCode=999;StdOut='';StdErr=$_.Exception.Message;Text=$_.Exception.Message}
    }
    finally {
        if ($process) { $process.Dispose() }
    }
}

function Get-FirstLine {
    param([string]$Exe,[string[]]$Arguments)
    $result=Invoke-NativeCapture -FilePath $Exe -Arguments $Arguments
    $lines=@(([string]$result.Text -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -gt 0) { return [string]$lines[0] }
    return ''
}

function Get-HardwareSignature {
    param([string]$FFmpegVersion,[object]$Cpu,[object[]]$Gpus)
    $cpuName=if ($Cpu) {[string]$Cpu.Name} else {'CPU unknown'}
    $parts=New-Object System.Collections.Generic.List[string]
    foreach ($gpu in @($Gpus | Sort-Object Name,PNPDeviceID)) {
        $parts.Add(('{0}|{1}|{2}' -f [string]$gpu.Name,[string]$gpu.DriverVersion,[string]$gpu.PNPDeviceID))
    }
    return ('FFMPEG={0};CPU={1};GPU={2}' -f $FFmpegVersion,$cpuName,($parts -join ';'))
}

function Get-StableIdSuffix {
    param([string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $bytes=[Text.Encoding]::UTF8.GetBytes([string]$Text)
        $hash=$sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0,10)
    }
    finally { $sha.Dispose() }
}

function Get-NvidiaDevices {
    $command=Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if ($null -eq $command) { return @() }
    $result=Invoke-NativeCapture -FilePath $command.Source -Arguments @('--query-gpu=index,name,driver_version','--format=csv,noheader,nounits')
    if ($result.ExitCode -ne 0) { return @() }
    $items=New-Object System.Collections.Generic.List[object]
    foreach ($line in @([string]$result.StdOut -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts=@($line -split ',' | ForEach-Object { $_.Trim() })
        if ($parts.Count -lt 2) { continue }
        $index=0
        if (-not [int]::TryParse($parts[0],[ref]$index)) { continue }
        $items.Add([pscustomobject]@{Index=$index;Name=[string]$parts[1];DriverVersion=if($parts.Count -ge 3){[string]$parts[2]}else{''}})
    }
    return $items.ToArray()
}

function Get-NvidiaSnapshot {
    param([int]$GpuIndex=0)
    $command=Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if ($null -eq $command) { return $null }
    $result=Invoke-NativeCapture -FilePath $command.Source -Arguments @('--query-gpu=index,memory.used,utilization.gpu,utilization.encoder,temperature.gpu','--format=csv,noheader,nounits')
    if ($result.ExitCode -ne 0) { return $null }
    foreach ($line in @([string]$result.StdOut -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts=@($line -split ',' | ForEach-Object { $_.Trim() })
        if ($parts.Count -lt 5) { continue }
        $index=0
        if (-not [int]::TryParse($parts[0],[ref]$index)) { continue }
        if ($index -ne $GpuIndex) { continue }
        try {
            return [pscustomobject]@{
                MemoryMB=[double]$parts[1]
                GpuUtil=[double]$parts[2]
                EncoderUtil=[double]$parts[3]
                TemperatureC=[double]$parts[4]
            }
        }
        catch { return $null }
    }
    return $null
}

function Invoke-EncodeBenchmark {
    param(
        [string]$FFmpeg,
        [string[]]$Arguments,
        [string]$OutputPath,
        [double]$MediaSeconds,
        [string]$Backend,
        [int]$NvidiaIndex=0
    )
    $process=$null
    $beforeMemory=$null
    $peakMemory=$null
    $peakGpuUtil=$null
    $peakEncoderUtil=$null
    $peakTemp=$null
    if ($Backend -eq 'NVENC') {
        $snapshot=Get-NvidiaSnapshot -GpuIndex $NvidiaIndex
        if ($snapshot) {
            $beforeMemory=[double]$snapshot.MemoryMB
            $peakMemory=[double]$snapshot.MemoryMB
            $peakGpuUtil=[double]$snapshot.GpuUtil
            $peakEncoderUtil=[double]$snapshot.EncoderUtil
            $peakTemp=[double]$snapshot.TemperatureC
        }
    }
    $stopwatch=[Diagnostics.Stopwatch]::StartNew()
    try {
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=$FFmpeg
        $psi.Arguments=Join-NativeArguments $Arguments
        $psi.UseShellExecute=$false
        $psi.CreateNoWindow=$true
        $psi.RedirectStandardOutput=$true
        $psi.RedirectStandardError=$true
        $psi.StandardOutputEncoding=[Text.Encoding]::UTF8
        $psi.StandardErrorEncoding=[Text.Encoding]::UTF8
        $process=New-Object Diagnostics.Process
        $process.StartInfo=$psi
        if (-not $process.Start()) { throw 'FFmpeg benchmark could not be started.' }
        $outTask=$process.StandardOutput.ReadToEndAsync()
        $errTask=$process.StandardError.ReadToEndAsync()
        while (-not $process.HasExited) {
            if ($Backend -eq 'NVENC') {
                $snapshot=Get-NvidiaSnapshot -GpuIndex $NvidiaIndex
                if ($snapshot) {
                    if ($null -eq $peakMemory -or [double]$snapshot.MemoryMB -gt [double]$peakMemory) { $peakMemory=[double]$snapshot.MemoryMB }
                    if ($null -eq $peakGpuUtil -or [double]$snapshot.GpuUtil -gt [double]$peakGpuUtil) { $peakGpuUtil=[double]$snapshot.GpuUtil }
                    if ($null -eq $peakEncoderUtil -or [double]$snapshot.EncoderUtil -gt [double]$peakEncoderUtil) { $peakEncoderUtil=[double]$snapshot.EncoderUtil }
                    if ($null -eq $peakTemp -or [double]$snapshot.TemperatureC -gt [double]$peakTemp) { $peakTemp=[double]$snapshot.TemperatureC }
                }
            }
            Start-Sleep -Milliseconds 300
        }
        $process.WaitForExit()
        $stopwatch.Stop()
        $errorText=[string]$errTask.Result
        [void]$outTask.Result
        $success=($process.ExitCode -eq 0 -and (Test-Path -LiteralPath $OutputPath -PathType Leaf) -and (Get-Item -LiteralPath $OutputPath).Length -gt 1024)
        $speed=if ($stopwatch.Elapsed.TotalSeconds -gt 0) {[Math]::Round($MediaSeconds/$stopwatch.Elapsed.TotalSeconds,2)} else {0}
        $size=if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {[Math]::Round((Get-Item -LiteralPath $OutputPath).Length/1MB,2)} else {0}
        $vramDelta=$null
        if ($null -ne $beforeMemory -and $null -ne $peakMemory) {
            $vramDelta=[Math]::Round(([double]$peakMemory-[double]$beforeMemory),0)
            if ($vramDelta -lt 0) { $vramDelta=0 }
        }
        return [pscustomobject][ordered]@{
            Success=$success
            ExitCode=[int]$process.ExitCode
            ElapsedSeconds=[Math]::Round($stopwatch.Elapsed.TotalSeconds,2)
            SpeedX=$speed
            OutputMB=$size
            VramBeforeMB=if($null -ne $beforeMemory){[Math]::Round($beforeMemory,0)}else{$null}
            VramPeakMB=if($null -ne $peakMemory){[Math]::Round($peakMemory,0)}else{$null}
            VramDeltaMB=$vramDelta
            GpuUtilMax=if($null -ne $peakGpuUtil){[Math]::Round($peakGpuUtil,0)}else{$null}
            EncoderUtilMax=if($null -ne $peakEncoderUtil){[Math]::Round($peakEncoderUtil,0)}else{$null}
            TemperatureMaxC=if($null -ne $peakTemp){[Math]::Round($peakTemp,0)}else{$null}
            ErrorText=if($success){''}else{$errorText.Trim()}
        }
    }
    catch {
        $stopwatch.Stop()
        return [pscustomobject][ordered]@{
            Success=$false;ExitCode=999;ElapsedSeconds=[Math]::Round($stopwatch.Elapsed.TotalSeconds,2);SpeedX=0;OutputMB=0
            VramBeforeMB=$null;VramPeakMB=$null;VramDeltaMB=$null;GpuUtilMax=$null;EncoderUtilMax=$null;TemperatureMaxC=$null
            ErrorText=$_.Exception.Message
        }
    }
    finally {
        if ($process) { $process.Dispose() }
    }
}

function Measure-SSIM {
    param([string]$FFmpeg,[string]$Source,[string]$Encoded)
    if (-not (Test-Path -LiteralPath $Encoded -PathType Leaf)) { return $null }
    $result=Invoke-NativeCapture -FilePath $FFmpeg -Arguments @('-hide_banner','-loglevel','info','-i',$Source,'-i',$Encoded,'-lavfi','[0:v][1:v]ssim','-an','-f','null','NUL')
    $match=[regex]::Match([string]$result.Text,'All:([0-9]+(?:\.[0-9]+)?)')
    if ($match.Success) {
        return [Math]::Round([double]::Parse($match.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture),5)
    }
    return $null
}

function Test-NvencOption {
    param([string]$FFmpeg,[string]$Source,[string[]]$Extra,[int]$NvidiaIndex=0)
    $output=Join-Path $TempFolder ('nvopt-'+[guid]::NewGuid().ToString('N')+'.mkv')
    try {
        $arguments=@('-hide_banner','-loglevel','error','-y','-hwaccel','cuda')
        if ($NvidiaIndex -gt 0) { $arguments+=@('-hwaccel_device',[string]$NvidiaIndex) }
        $arguments+=@('-i',$Source,'-t','2','-map','0:v:0','-an','-c:v','hevc_nvenc','-gpu',[string]$NvidiaIndex,'-preset','p4','-rc','vbr','-cq','24','-b:v','2500k','-maxrate','2750k','-bufsize','3750k')
        $arguments+=@($Extra)
        $arguments+=@($output)
        $result=Invoke-NativeCapture -FilePath $FFmpeg -Arguments $arguments
        return ($result.ExitCode -eq 0 -and (Test-Path -LiteralPath $output -PathType Leaf) -and (Get-Item -LiteralPath $output).Length -gt 1024)
    }
    finally {
        Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
    }
}

try {
    Set-TestStatus -Stage 'Starting' -Current '' -Percent 0 -Message 'Detecting hardware and FFmpeg.'
    Write-Log INFO 'Encoder verification started.'

    if ($BenchmarkSeconds -lt 5) { $BenchmarkSeconds=5 }
    if ($BenchmarkSeconds -gt 30) { $BenchmarkSeconds=30 }

    $preferences=Read-JsonFile $PreferencesPath
    $ffmpeg=Resolve-ToolPath (Get-P $preferences 'FFmpegPath' '') 'Tools\FFmpeg\ffmpeg.exe'
    if (-not (Test-Path -LiteralPath $ffmpeg -PathType Leaf)) { throw "ffmpeg.exe is missing: $ffmpeg" }

    $ffmpegVersion=Get-FirstLine -Exe $ffmpeg -Arguments @('-version')
    $encoderResult=Invoke-NativeCapture -FilePath $ffmpeg -Arguments @('-hide_banner','-encoders')
    $encoderText=[string]$encoderResult.Text
    $cpu=Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed
    $gpus=@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object Name,AdapterCompatibility,DriverVersion,PNPDeviceID,DeviceID,AdapterRAM | Sort-Object Name)
    $signature=Get-HardwareSignature -FFmpegVersion $ffmpegVersion -Cpu $cpu -Gpus $gpus

    $source=Join-Path $TempFolder 'mediaprep-encoder-benchmark-source.mkv'
    Remove-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue
    Set-TestStatus -Stage 'Preparing' -Current 'Benchmark source' -Percent 4 -Message 'Creating a reproducible 1080p H.264 test sequence.'
    $sourceArgs=@('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=1920x1080:rate=30','-f','lavfi','-i','sine=frequency=1000:sample_rate=48000','-t',[string]$BenchmarkSeconds,'-c:v','libx264','-preset','ultrafast','-crf','18','-pix_fmt','yuv420p','-c:a','aac','-b:a','128k',$source)
    $sourceResult=Invoke-NativeCapture -FilePath $ffmpeg -Arguments $sourceArgs
    if ($sourceResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Write-Log WARN 'The libx264 test source could not be created; trying MPEG-4.'
        $sourceResult=Invoke-NativeCapture -FilePath $ffmpeg -Arguments @('-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=1920x1080:rate=30','-t',[string]$BenchmarkSeconds,'-c:v','mpeg4','-q:v','2','-pix_fmt','yuv420p',$source)
    }
    if ($sourceResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Could not create the benchmark source file with FFmpeg.' }

    $candidates=New-Object System.Collections.Generic.List[object]
    $candidates.Add([pscustomobject][ordered]@{
        Id='cpu-libx265';HardwareType='CPU';HardwareName=[string]$cpu.Name;Vendor=[string]$cpu.Manufacturer;Backend='CPU';Encoder='libx265';GpuIndex=$null;DriverVersion='';Detected=($encoderText -match '\blibx265\b')
    })

    $nvidiaDevices=@(Get-NvidiaDevices)
    $nvidiaOrdinal=0
    foreach ($gpu in @($gpus | Where-Object { $_.Name -match 'NVIDIA' })) {
        $nvidiaIndex=$nvidiaOrdinal
        $match=@($nvidiaDevices | Where-Object { [string]$_.Name -eq [string]$gpu.Name } | Select-Object -First 1)
        if ($match.Count -gt 0) { $nvidiaIndex=[int]$match[0].Index }
        $suffix=Get-StableIdSuffix ([string]$gpu.PNPDeviceID+[string]$gpu.Name)
        $nvidiaDriver=[string]$gpu.DriverVersion
        if($match.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$match[0].DriverVersion)){$nvidiaDriver=[string]$match[0].DriverVersion}
        $candidates.Add([pscustomobject][ordered]@{
            Id=('nvidia-'+$suffix+'-hevc_nvenc');HardwareType='GPU';HardwareName=[string]$gpu.Name;Vendor='NVIDIA';Backend='NVENC';Encoder='hevc_nvenc';GpuIndex=$nvidiaIndex;DriverVersion=$nvidiaDriver;Detected=($encoderText -match '\bhevc_nvenc\b')
        })
        $nvidiaOrdinal++
    }

    # QSV and AMF are added only when corresponding hardware exists. MediaPrep currently
    # verifies one Intel and one AMD adapter per backend; cross-vendor choices (for example
    # Intel iGPU + NVIDIA dGPU) are all retained and may be switched after verification.
    $intelGpus=@($gpus | Where-Object { $_.Name -match 'Intel' })
    if ($intelGpus.Count -gt 0) {
        $preferredIntel=@($intelGpus | Sort-Object @{Expression={if($_.Name -match 'Arc'){0}else{1}}},Name | Select-Object -First 1)[0]
        $suffix=Get-StableIdSuffix ([string]$preferredIntel.PNPDeviceID+[string]$preferredIntel.Name)
        $candidates.Add([pscustomobject][ordered]@{
            Id=('intel-'+$suffix+'-hevc_qsv');HardwareType='GPU';HardwareName=[string]$preferredIntel.Name;Vendor='Intel';Backend='QSV';Encoder='hevc_qsv';GpuIndex=$null;DriverVersion=[string]$preferredIntel.DriverVersion;Detected=($encoderText -match '\bhevc_qsv\b')
        })
    }

    $amdGpus=@($gpus | Where-Object { $_.Name -match 'AMD|Radeon' })
    if ($amdGpus.Count -gt 0) {
        $preferredAmd=@($amdGpus | Select-Object -First 1)[0]
        $suffix=Get-StableIdSuffix ([string]$preferredAmd.PNPDeviceID+[string]$preferredAmd.Name)
        $candidates.Add([pscustomobject][ordered]@{
            Id=('amd-'+$suffix+'-hevc_amf');HardwareType='GPU';HardwareName=[string]$preferredAmd.Name;Vendor='AMD';Backend='AMF';Encoder='hevc_amf';GpuIndex=$null;DriverVersion=[string]$preferredAmd.DriverVersion;Detected=($encoderText -match '\bhevc_amf\b')
        })
    }

    $results=New-Object System.Collections.Generic.List[object]
    $candidateCount=$candidates.Count
    if ($candidateCount -lt 1) { $candidateCount=1 }

    for ($index=0; $index -lt $candidates.Count; $index++) {
        $candidate=$candidates[$index]
        $percent=8+[int](($index/[double]$candidateCount)*84)
        Set-TestStatus -Stage 'Benchmarking' -Current ([string]$candidate.HardwareName) -Percent $percent -Message ("Testar {0} / {1}" -f $candidate.Backend,$candidate.Encoder) -Details (New-LiveEncoderDetails -Candidate $candidate -Benchmark $null -Capabilities ([ordered]@{}))
        Write-Log INFO ("Testar {0}: {1} ({2})" -f $candidate.Backend,$candidate.HardwareName,$candidate.Encoder)

        $capabilities=[ordered]@{}
        $benchmark=$null
        $verified=$false
        $reason=''

        if (-not [bool]$candidate.Detected) {
            $reason="FFmpeg-builden saknar $($candidate.Encoder)."
        }
        else {
            $output=Join-Path $TempFolder ((Get-StableIdSuffix $candidate.Id)+'-benchmark.mkv')
            Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
            $arguments=@('-hide_banner','-loglevel','error','-y')

            switch ([string]$candidate.Backend) {
                'NVENC' {
                    $arguments+=@('-hwaccel','cuda')
                    if ([int]$candidate.GpuIndex -gt 0) { $arguments+=@('-hwaccel_device',[string]$candidate.GpuIndex) }
                    $arguments+=@('-i',$source,'-t',[string]$BenchmarkSeconds,'-map','0:v:0','-an','-c:v','hevc_nvenc','-gpu',[string]$candidate.GpuIndex,'-preset','p4','-rc','vbr','-cq','24','-b:v','2500k','-maxrate','2750k','-bufsize','3750k',$output)
                }
                'QSV' {
                    $arguments+=@('-i',$source,'-t',[string]$BenchmarkSeconds,'-map','0:v:0','-an','-c:v','hevc_qsv','-preset','medium','-b:v','2500k','-maxrate','2750k','-bufsize','3750k',$output)
                }
                'AMF' {
                    $arguments+=@('-i',$source,'-t',[string]$BenchmarkSeconds,'-map','0:v:0','-an','-c:v','hevc_amf','-usage','transcoding','-quality','balanced','-rc','vbr_peak','-b:v','2500k','-maxrate','2750k','-bufsize','3750k',$output)
                }
                default {
                    $arguments+=@('-i',$source,'-t',[string]$BenchmarkSeconds,'-map','0:v:0','-an','-c:v','libx265','-preset','medium','-b:v','2500k','-maxrate','2750k','-bufsize','3750k',$output)
                }
            }

            $nvidiaIndex=0
            if ($null -ne $candidate.GpuIndex) { $nvidiaIndex=[int]$candidate.GpuIndex }
            $benchmark=Invoke-EncodeBenchmark -FFmpeg $ffmpeg -Arguments $arguments -OutputPath $output -MediaSeconds $BenchmarkSeconds -Backend ([string]$candidate.Backend) -NvidiaIndex $nvidiaIndex

            if ($benchmark.Success) {
                $verified=$true
                $ssim=Measure-SSIM -FFmpeg $ffmpeg -Source $source -Encoded $output
                $benchmark | Add-Member -NotePropertyName SSIM -NotePropertyValue $ssim -Force
                Set-TestStatus -Stage 'Capabilities' -Current ([string]$candidate.HardwareName) -Percent ($percent+3) -Message 'Benchmark complete. Checking encoder capabilities.' -Details (New-LiveEncoderDetails -Candidate $candidate -Benchmark $benchmark -Capabilities $capabilities -Verified $true)

                switch ([string]$candidate.Backend) {
                    'NVENC' {
                        $helpResult=Invoke-NativeCapture -FilePath $ffmpeg -Arguments @('-hide_banner','-h','encoder=hevc_nvenc')
                        $help=[string]$helpResult.Text
                        $capabilities['CudaDecode']=$true
                        Set-TestStatus -Stage 'Capabilities' -Current ([string]$candidate.HardwareName) -Percent ($percent+4) -Message 'CUDA decode' -Details (New-LiveEncoderDetails -Candidate $candidate -Benchmark $benchmark -Capabilities $capabilities -Verified $true)
                        $capabilities['PresetP4']=($help -match '\bp4\b')
                        Set-TestStatus -Stage 'Capabilities' -Current ([string]$candidate.HardwareName) -Percent ($percent+5) -Message 'Preset P4' -Details (New-LiveEncoderDetails -Candidate $candidate -Benchmark $benchmark -Capabilities $capabilities -Verified $true)
                        $capabilities['VBR']=($help -match '\bvbr\b')
                        $capabilities['CQ']=($help -match '(?m)^\s*-cq\s|\bcq\b')
                        Set-TestStatus -Stage 'Capabilities' -Current ([string]$candidate.HardwareName) -Percent ($percent+6) -Message 'VBR / CQ' -Details (New-LiveEncoderDetails -Candidate $candidate -Benchmark $benchmark -Capabilities $capabilities -Verified $true)
                        $capabilities['SpatialAQ']=if($help -match 'spatial[-_]aq'){Test-NvencOption -FFmpeg $ffmpeg -Source $source -Extra @('-spatial-aq','1') -NvidiaIndex $nvidiaIndex}else{$false}
                        Set-TestStatus -Stage 'Capabilities' -Current ([string]$candidate.HardwareName) -Percent ($percent+7) -Message 'Spatial AQ' -Details (New-LiveEncoderDetails -Candidate $candidate -Benchmark $benchmark -Capabilities $capabilities -Verified $true)
                        $capabilities['TemporalAQ']=if($help -match 'temporal[-_]aq'){Test-NvencOption -FFmpeg $ffmpeg -Source $source -Extra @('-temporal-aq','1') -NvidiaIndex $nvidiaIndex}else{$false}
                        Set-TestStatus -Stage 'Capabilities' -Current ([string]$candidate.HardwareName) -Percent ($percent+8) -Message 'Temporal AQ' -Details (New-LiveEncoderDetails -Candidate $candidate -Benchmark $benchmark -Capabilities $capabilities -Verified $true)
                        $capabilities['Lookahead16']=if($help -match 'rc-lookahead'){Test-NvencOption -FFmpeg $ffmpeg -Source $source -Extra @('-rc-lookahead','16') -NvidiaIndex $nvidiaIndex}else{$false}
                        Set-TestStatus -Stage 'Capabilities' -Current ([string]$candidate.HardwareName) -Percent ($percent+9) -Message 'Lookahead 16' -Details (New-LiveEncoderDetails -Candidate $candidate -Benchmark $benchmark -Capabilities $capabilities -Verified $true)
                        $capabilities['Surfaces8']=if($help -match '\bsurfaces\b'){Test-NvencOption -FFmpeg $ffmpeg -Source $source -Extra @('-surfaces','8') -NvidiaIndex $nvidiaIndex}else{$false}
                        Set-TestStatus -Stage 'Capabilities' -Current ([string]$candidate.HardwareName) -Percent ($percent+10) -Message 'Surfaces 8' -Details (New-LiveEncoderDetails -Candidate $candidate -Benchmark $benchmark -Capabilities $capabilities -Verified $true)
                        $capabilities['MultipassQres']=if($help -match '\bmultipass\b'){Test-NvencOption -FFmpeg $ffmpeg -Source $source -Extra @('-multipass','qres') -NvidiaIndex $nvidiaIndex}else{$false}
                        Set-TestStatus -Stage 'Capabilities' -Current ([string]$candidate.HardwareName) -Percent ($percent+11) -Message 'Multipass qres' -Details (New-LiveEncoderDetails -Candidate $candidate -Benchmark $benchmark -Capabilities $capabilities -Verified $true)
                    }
                    'QSV' {
                        $helpResult=Invoke-NativeCapture -FilePath $ffmpeg -Arguments @('-hide_banner','-h','encoder=hevc_qsv')
                        $help=[string]$helpResult.Text
                        $capabilities['PresetMedium']=($help -match '\bmedium\b')
                        $capabilities['AsyncDepth']=($help -match 'async_depth')
                        $capabilities['LowPower']=($help -match 'low_power')
                        $capabilities['GlobalQuality']=($help -match 'global_quality')
                        $capabilities['ExtBRC']=($help -match '\bextbrc\b')
                        $capabilities['RDO']=($help -match '(?m)^\s*-rdo\s')
                    }
                    'AMF' {
                        $helpResult=Invoke-NativeCapture -FilePath $ffmpeg -Arguments @('-hide_banner','-h','encoder=hevc_amf')
                        $help=[string]$helpResult.Text
                        $capabilities['TranscodingUsage']=($help -match '\btranscoding\b')
                        $capabilities['BalancedQuality']=($help -match '\bbalanced\b')
                        $capabilities['VbrPeak']=($help -match 'vbr_peak')
                        $capabilities['PreAnalysis']=($help -match 'preanalysis')
                    }
                    default {
                        $helpResult=Invoke-NativeCapture -FilePath $ffmpeg -Arguments @('-hide_banner','-h','encoder=libx265')
                        $help=[string]$helpResult.Text
                        $capabilities['PresetMedium']=($help -match 'preset')
                        $capabilities['TargetBitrate']=$true
                    }
                }
                Set-TestStatus -Stage 'Capabilities' -Current ([string]$candidate.HardwareName) -Percent ($percent+11) -Message 'Encoder verification complete for this device.' -Details (New-LiveEncoderDetails -Candidate $candidate -Benchmark $benchmark -Capabilities $capabilities -Verified $true)
            }
            else {
                $reason=[string]$benchmark.ErrorText
            }
            Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
        }

        $results.Add([pscustomobject][ordered]@{
            Id=[string]$candidate.Id
            HardwareType=[string]$candidate.HardwareType
            HardwareName=[string]$candidate.HardwareName
            Vendor=[string]$candidate.Vendor
            Backend=[string]$candidate.Backend
            Encoder=[string]$candidate.Encoder
            GpuIndex=$candidate.GpuIndex
            DriverVersion=[string]$candidate.DriverVersion
            Detected=[bool]$candidate.Detected
            Verified=[bool]$verified
            Reason=[string]$reason
            Capabilities=[pscustomobject]$capabilities
            Benchmark=$benchmark
        })
        $speed=if($benchmark){[double]$benchmark.SpeedX}else{0}
        Write-Log $(if($verified){'OK'}else{'WARN'}) ("{0}: verified={1}; speed={2}; reason={3}" -f $candidate.HardwareName,$verified,$speed,$reason)
    }

    $verifiedResults=@($results | Where-Object { $_.Verified })
    $fastestId=''
    if ($verifiedResults.Count -gt 0) {
        $fastest=@($verifiedResults | Sort-Object @{Expression={if($_.Benchmark){[double]$_.Benchmark.SpeedX}else{0}};Descending=$true} | Select-Object -First 1)[0]
        $fastestId=[string]$fastest.Id
    }

    $hardware=[pscustomobject][ordered]@{
        CPU=$cpu
        GPUs=@($gpus | ForEach-Object {
            [pscustomobject][ordered]@{
                Name=[string]$_.Name
                Vendor=[string]$_.AdapterCompatibility
                DriverVersion=[string]$_.DriverVersion
                PNPDeviceID=[string]$_.PNPDeviceID
                DeviceID=[string]$_.DeviceID
                AdapterRAM=if($null -ne $_.AdapterRAM){[int64]$_.AdapterRAM}else{$null}
            }
        })
    }

    $document=[pscustomobject][ordered]@{
        Version=2
        CheckedLocal=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        CheckedUtc=(Get-Date).ToUniversalTime().ToString('o')
        BenchmarkSeconds=$BenchmarkSeconds
        BenchmarkSource='FFmpeg testsrc2 1920x1080 30fps H.264'
        FFmpegPath=$ffmpeg
        FFmpegVersion=$ffmpegVersion
        Signature=$signature
        Hardware=$hardware
        FastestEncoderId=$fastestId
        Encoders=@($results.ToArray())
        LogPath=$LogPath
    }
    Write-JsonAtomic -Path $CapabilitiesPath -Value $document -Depth 14

    $benchmarkSummary=[pscustomobject][ordered]@{
        Version=2
        CheckedUtc=$document.CheckedUtc
        Signature=$signature
        FastestEncoderId=$fastestId
        Results=@($results | ForEach-Object {
            [pscustomobject][ordered]@{Id=$_.Id;HardwareName=$_.HardwareName;Backend=$_.Backend;Encoder=$_.Encoder;Verified=$_.Verified;Benchmark=$_.Benchmark}
        })
    }
    Write-JsonAtomic -Path $BenchmarkPath -Value $benchmarkSummary -Depth 10

    Set-TestStatus -Stage 'Completed' -Current '' -Percent 100 -Message ("Complete. {0} encoder(s) verified." -f $verifiedResults.Count)
    Write-Log INFO ("Encoder verification complete. Verified: {0}/{1}." -f $verifiedResults.Count,$results.Count)
    exit 0
}
catch {
    Write-Log ERROR $_.Exception.Message
    Set-TestStatus -Stage 'Failed' -Current '' -Percent 100 -Message $_.Exception.Message
    exit 1
}
finally {
    Remove-Item -LiteralPath (Join-Path $TempFolder 'mediaprep-encoder-benchmark-source.mkv') -Force -ErrorAction SilentlyContinue
}
