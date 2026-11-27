# Records one measured session of the title and sums it up, so that two runs can be compared.
# It changes nothing in the engine. By default it runs Play-VIctory.cmd measure (what you play with:
# release build, the same settings, info log appended to debugs\victory-measure.log), takes the part of
# that log written by this run, and samples the machine every few seconds while the title runs.
#
#   scripts\bench.ps1 -Label baseline                                   # Play-VIctory.cmd measure
#   scripts\bench.ps1 -Label join4 -Set VICTORY_JOIN_PARTS=4            # one setting at a time
#   scripts\bench.ps1 -Exe <your copy's executable> -Label x            # through scripts\play.ps1 instead
#   scripts\bench.ps1 -Analyze debugs\victory-measure.log               # last session of an existing log
#   scripts\bench.ps1 -Analyze debugs\victory-measure.log -AllSessions
#
# -Set           settings for this run as NAME=VALUE (several: -Set A=1,B=2), also fine with powershell -File;
# -More          the same as a hashtable, @{NAME='VALUE'}, inside a PowerShell window
#                (Play-VIctory.cmd keeps any VICTORY_* that is already set)
# -Build, -Safe  only with -Exe (passed to play.ps1)
# -SkipSeconds   seconds of the log left out of the "steady" figures (loading, cold caches); default 60
#
# Play the same scene each time, then close the title; the sum-up is written when it exits.
# Results go to bench-results\<date>-<label>\ (log.txt, system.csv, summary.txt).
# Run it from a normal window, not as administrator (see play.ps1).
# If scripts are blocked: powershell -ExecutionPolicy Bypass -File scripts\bench.ps1 ...
[CmdletBinding(DefaultParameterSetName = 'Cmd')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Play')][string]$Exe,
    [Parameter(Mandatory = $true, ParameterSetName = 'Analyze')][string]$Analyze,
    [Parameter(ParameterSetName = 'Analyze')][switch]$AllSessions,
    [string]$Label = 'baseline',
    [ValidateSet('diag', 'release')][string]$Build = 'release',
    [switch]$Safe,
    [hashtable]$More = @{},
    [string[]]$Set = @(),
    [int]$SampleSeconds = 2,
    [int]$SkipSeconds = 60
)

$inv = [System.Globalization.CultureInfo]::InvariantCulture

# -More and -Set, as one table of settings.
$extra = @{}
foreach ($k in $More.Keys) { $extra[[string]$k] = [string]$More[$k] }
foreach ($item in $Set) {
    foreach ($pair in ($item -split '[,;]')) {
        if ($pair -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { $extra[$Matches[1]] = $Matches[2] }
        elseif ($pair.Trim()) { Write-Host "Ignored -Set item '$pair' (expected NAME=VALUE)." }
    }
}

function Fmt($x, $format = '0.0') {
    if ($null -eq $x) { return 'n/a' }
    return ([double]$x).ToString($format, $inv)
}

function Get-Percentile([double[]]$values, [double]$p) {
    $sorted = @($values | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    $i = [int][math]::Ceiling($p * $sorted.Count) - 1
    if ($i -lt 0) { $i = 0 }
    return $sorted[$i]
}

function Get-Median([double[]]$values) { return Get-Percentile $values 0.5 }

function Get-Mean([double[]]$values) {
    if ($values.Count -eq 0) { return $null }
    return ($values | Measure-Object -Average).Average
}

# One line per fact about the frame-rate lines of a log (stderr of the title, VICTORY_LOG=info).
function Get-LogSummary([string]$LogPath, [int]$Skip, [bool]$All = $false) {
    $LogPath = (Resolve-Path $LogPath).Path
    $ansi = '\x1b\[[0-9;]*m'
    $stamp = '^(\d{4}-\d{2}-\d{2}T[\d:.]+)Z'
    $stampTrail = $stamp + '\s*'
    $frameRx = '(?<fps>[\d.]+) fps, (?<ms>[\d.]+) ms/frame \((?<cpu>[\d.]+) preparing:[^;]*; (?<gpu>[\d.]+) on the GPU;[^)]*\), (?<draws>[\d.]+) draws/frame, dropped (?<dropped>[\d.]+) without a host pipeline \((?<making>\d+) being made\)'
    $busyRx = 'the card about (\d+)% busy'
    $frames = New-Object System.Collections.Generic.List[object]
    $busy = New-Object System.Collections.Generic.List[object]
    $pressure = 0
    $cleared = 0
    $workers = $null
    $mesh = $null
    $lanes = $null
    $warnCount = 0
    $errorCount = 0
    $heads = @{}
    $first = $null
    $index = 0
    # Play-VIctory.cmd appends every run to one log, each after a '===== date time =====' line.
    $lines = [System.IO.File]::ReadAllLines($LogPath)
    $startAt = 0
    $marker = $null
    if (-not $All) {
        for ($n = $lines.Length - 1; $n -ge 0; $n--) {
            if ($lines[$n] -match '^=====.*=====\s*$') { $startAt = $n + 1; $marker = $lines[$n].Trim(); break }
        }
    }
    for ($n = $startAt; $n -lt $lines.Length; $n++) {
        $raw = $lines[$n]
        $line = [regex]::Replace($raw, $ansi, '')
        $t = $index
        if ($line -match $stamp) {
            try {
                $when = [datetime]::Parse($Matches[1] + 'Z', $inv, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                if ($null -eq $first) { $first = $when }
                $t = ($when - $first).TotalSeconds
            } catch { }
        }
        $index++
        if ($line -match $frameRx) {
            $frames.Add([pscustomobject]@{
                T = $t; Fps = [double]$Matches['fps']; Ms = [double]$Matches['ms']; Cpu = [double]$Matches['cpu']
                Gpu = [double]$Matches['gpu']; Draws = [double]$Matches['draws']
                Dropped = [double]$Matches['dropped']; Making = [int]$Matches['making']
            })
            continue
        }
        if ($line -match $busyRx) { $busy.Add([pscustomobject]@{ T = $t; Pct = [double]$Matches[1] }); continue }
        if ($line -match 'host memory pressure: limiting') { $pressure++ }
        elseif ($line -match 'host memory pressure cleared') { $cleared++ }
        if ($null -eq $workers -and $line -match 'pipeline workers\W+workers=(\d+)') { $workers = $Matches[1] }
        if ($null -eq $mesh -and $line -match 'host mesh shader support') { $mesh = ($line -replace $stampTrail, '').Trim() }
        if ($null -eq $lanes -and $line -match 'host wave lanes') { $lanes = ($line -replace $stampTrail, '').Trim() }
        if ($line -match '^\S+\s+(WARN|ERROR)\s+(.*)$') {
            if ($Matches[1] -eq 'WARN') { $warnCount++ } else { $errorCount++ }
            $head = $Matches[2]
            if ($head.Length -gt 110) { $head = $head.Substring(0, 110) }
            if ($heads.ContainsKey($head)) { $heads[$head]++ } else { $heads[$head] = 1 }
        }
    }

    $out = New-Object System.Collections.Generic.List[string]
    $out.Add("Log: $LogPath")
    if ($marker) { $out.Add("Session: the lines after the last marker $marker (use -AllSessions for the whole file)") }
    $out.Add("Frame-rate lines in the log: $($frames.Count) (the first $Skip s are left out of the steady figures)")
    $out.Add('')
    foreach ($view in @(@('all', 0), @('steady', $Skip))) {
        $name = $view[0]
        $from = $view[1]
        $set = @($frames | Where-Object { $_.T -ge $from })
        if ($set.Count -eq 0) { $out.Add("[$name] no frame-rate line."); continue }
        $ms = [double[]]@($set | ForEach-Object { $_.Ms })
        $cpu = [double[]]@($set | ForEach-Object { $_.Cpu })
        $gpu = [double[]]@($set | ForEach-Object { $_.Gpu })
        $fps = [double[]]@($set | ForEach-Object { $_.Fps })
        $drop = [double[]]@($set | ForEach-Object { $_.Dropped })
        $mk = [double[]]@($set | ForEach-Object { $_.Making })
        $over200 = @($set | Where-Object { $_.Ms -gt 200 }).Count
        $over1000 = @($set | Where-Object { $_.Ms -gt 1000 }).Count
        $b = @($busy | Where-Object { $_.T -ge $from } | ForEach-Object { $_.Pct })
        $out.Add("[$name] $($set.Count) samples")
        $out.Add("  ms/frame: median $(Fmt (Get-Median $ms))  p95 $(Fmt (Get-Percentile $ms 0.95))  p99 $(Fmt (Get-Percentile $ms 0.99))  max $(Fmt ($ms | Measure-Object -Maximum).Maximum)")
        $out.Add("  fps: mean of samples $(Fmt (Get-Mean $fps))  lowest sample $(Fmt ($fps | Measure-Object -Minimum).Minimum)  (p99 of ms/frame is a coarse '1% low': every sample already averages a stretch of frames)")
        $out.Add("  preparing (CPU) ms/frame: mean $(Fmt (Get-Mean $cpu))   field 'on the GPU' ms/frame: mean $(Fmt (Get-Mean $gpu))")
        $out.Add("  samples over 200 ms/frame: $over200 of $($set.Count)   over 1000 ms: $over1000")
        $out.Add("  draws dropped without a host pipeline: mean $(Fmt (Get-Mean $drop))  max $(Fmt ($drop | Measure-Object -Maximum).Maximum)   pipelines being made: max $(Fmt ($mk | Measure-Object -Maximum).Maximum) last $(Fmt $mk[$mk.Count - 1] '0')")
        if ($b.Count -gt 0) { $out.Add("  card busy by the log's own count: mean $(Fmt (Get-Mean ([double[]]$b)))%") }
        $out.Add('')
    }
    $out.Add("Memory pressure: $pressure times limiting, $cleared times cleared")
    $out.Add("Pipeline workers: $(if ($workers) { $workers } else { 'not in the log' })")
    $out.Add("Mesh shaders: $(if ($mesh) { $mesh } else { 'line not in the log' })")
    $out.Add("Wave lanes: $(if ($lanes) { $lanes } else { 'line not in the log' })")
    $out.Add("WARN lines: $warnCount   ERROR lines: $errorCount")
    foreach ($h in ($heads.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8)) {
        $out.Add("  x$($h.Value)  $($h.Key)")
    }

    # Hints, not proofs: what the figures above point to.
    $steady = @($frames | Where-Object { $_.T -ge $Skip })
    if ($steady.Count -gt 0) {
        $msM = Get-Median ([double[]]@($steady | ForEach-Object { $_.Ms }))
        $cpuM = Get-Median ([double[]]@($steady | ForEach-Object { $_.Cpu }))
        $gpuM = Get-Median ([double[]]@($steady | ForEach-Object { $_.Gpu }))
        $dropM = Get-Mean ([double[]]@($steady | ForEach-Object { $_.Dropped }))
        $out.Add('')
        $out.Add('Hints (read with the figures above; none of this is proof):')
        if ($msM -gt 0 -and ($cpuM / $msM) -gt 0.6) { $out.Add('  - most of each frame is the title-side preparing (CPU): the submitting thread is the first suspect.') }
        if ($msM -gt 0 -and ($gpuM / $msM) -gt 0.5) { $out.Add("  - most of each frame is the 'on the GPU' field: look at the waiting for the card.") }
        if ($dropM -gt 0) { $out.Add("  - draws are dropped for want of a host pipeline (mean $(Fmt $dropM)/frame): pipelines may still be made; warm the caches and measure again.") }
        if ($pressure -gt 0) { $out.Add('  - the memory-pressure guard fired: check the commit and the page file.') }
        if ($null -ne $mesh -and $mesh -match 'mesh=false') { $out.Add('  - the host reports no mesh shaders: pipelines using them are refused.') }
    }
    return $out
}

if ($PSCmdlet.ParameterSetName -eq 'Analyze') {
    Get-LogSummary -LogPath $Analyze -Skip $SkipSeconds -All $AllSessions.IsPresent | ForEach-Object { Write-Host $_ }
    return
}

# ---- Run mode ----
$viaCmd = ($PSCmdlet.ParameterSetName -eq 'Cmd')
$play = Join-Path $PSScriptRoot 'play.ps1'
$launcher = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Play-VIctory.cmd'))
$measureLog = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\debugs\victory-measure.log'))
if ($viaCmd) {
    if (-not (Test-Path $launcher)) { Write-Host "No $launcher."; return }
} else {
    if (-not (Test-Path $play)) { Write-Host "No $play."; return }
    if (-not (Test-Path $Exe)) { Write-Host "No $Exe."; return }
    $exeFull = (Resolve-Path $Exe).Path
}
$root = Join-Path $PSScriptRoot '..\bench-results'
$dir = Join-Path $root ('{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Label)
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$dir = (Resolve-Path $dir).Path
$logFile = Join-Path $dir 'log.txt'
$outFile = Join-Path $dir 'stdout.txt'

$settings = @{}
if (-not $viaCmd) { $settings['VICTORY_LOG'] = 'info' }
foreach ($k in $extra.Keys) { $settings[$k] = $extra[$k] }
$moreText = (($settings.Keys | Sort-Object) | ForEach-Object { "'$_'='$($settings[$_])'" }) -join ';'

$info = New-Object System.Collections.Generic.List[string]
$info.Add("Run: $Label   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
if ($viaCmd) {
    $info.Add("Through: $launcher measure")
} else {
    $info.Add("Through: $play   exe: $exeFull   build: $Build   Safe: $($Safe.IsPresent)")
}
$info.Add("Settings given to this run: $(if ($moreText) { $moreText } else { 'none' })")
try { $info.Add("Commit: $((git -C (Join-Path $PSScriptRoot '..') rev-parse --short HEAD 2>$null))") } catch { }
try { $info.Add("CPU: $((Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim())") } catch { }
try { $info.Add("GPU: $((Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name + ' (driver ' + $_.DriverVersion + ')' }) -join ' ; ')") } catch { }
try { $info.Add("RAM: $(Fmt ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)) GB") } catch { }
try { $info.Add("Page file: $((Get-CimInstance Win32_PageFileUsage | ForEach-Object { $_.Name + ' ' + $_.AllocatedBaseSize + ' MB' }) -join ' ; ')") } catch { }
$info | ForEach-Object { Write-Host $_ }
Write-Host "Starting. Play the scene you compare, then close the title; the sum-up comes after."

$p = $null
$saved = @{}
try {
    if ($viaCmd) {
        # The launcher keeps any VICTORY_* already set in the window, so -More reaches it through the environment.
        foreach ($k in $settings.Keys) {
            $saved[$k] = [Environment]::GetEnvironmentVariable($k)
            [Environment]::SetEnvironmentVariable($k, [string]$settings[$k])
        }
        $before = 0
        if (Test-Path $measureLog) { $before = (Get-Item $measureLog).Length }
        $p = Start-Process -FilePath $launcher -ArgumentList 'measure' -NoNewWindow -PassThru
    } else {
        $command = "& '$play' -Exe '$exeFull' -Build $Build -More @{$moreText}"
        if ($Safe) { $command += ' -Safe' }
        $argText = '"' + $command + '"'
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $argText) `
            -RedirectStandardError $logFile -RedirectStandardOutput $outFile -NoNewWindow -PassThru
    }
} finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
}
if ($null -eq $p) { Write-Host 'The title did not start.'; return }

$samples = New-Object System.Collections.Generic.List[object]
$start = Get-Date
while (-not $p.HasExited) {
    Start-Sleep -Seconds $SampleSeconds
    $row = [ordered]@{
        Seconds = [int]((Get-Date) - $start).TotalSeconds
        PrivateMB = $null; WorkingSetMB = $null; CpuSeconds = $null
        FreePhysicalMB = $null; FreeCommitMB = $null; PagesPerSec = $null; GpuDedicatedMB = $null
    }
    try {
        # The biggest victory* process: the launcher may run a short 'warm' step before the title itself.
        $v = Get-Process -Name 'victory*' -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 1
        if ($v) {
            $row.PrivateMB = [int]($v.PrivateMemorySize64 / 1MB)
            $row.WorkingSetMB = [int]($v.WorkingSet64 / 1MB)
            $row.CpuSeconds = [math]::Round($v.CPU, 1)
        }
    } catch { }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $row.FreePhysicalMB = [int]($os.FreePhysicalMemory / 1024)
        $row.FreeCommitMB = [int]($os.FreeVirtualMemory / 1024)
    } catch { }
    try { $row.PagesPerSec = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).PagesPersec } catch { }
    try {
        $g = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory
        $row.GpuDedicatedMB = [int](($g | Measure-Object DedicatedUsage -Sum).Sum / 1MB)
    } catch { }
    $samples.Add([pscustomobject]$row)
}
$wall = ((Get-Date) - $start).TotalSeconds
$samples | Export-Csv -Path (Join-Path $dir 'system.csv') -NoTypeInformation

if ($viaCmd) {
    # Keep only what this run appended to the shared log.
    if (Test-Path $measureLog) {
        $source = [System.IO.File]::Open($measureLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            if ($before -le $source.Length) { [void]$source.Seek($before, [System.IO.SeekOrigin]::Begin) }
            $target = [System.IO.File]::Create($logFile)
            try { $source.CopyTo($target) } finally { $target.Dispose() }
        } finally { $source.Dispose() }
    }
}

$summary = New-Object System.Collections.Generic.List[string]
$info | ForEach-Object { $summary.Add($_) }
$summary.Add('')
if (Test-Path $logFile) {
    Get-LogSummary -LogPath $logFile -Skip $SkipSeconds -All $true | ForEach-Object { $summary.Add($_) }
} else {
    $summary.Add('No log file was written.')
}
$summary.Add('')
$summary.Add("System samples (every $SampleSeconds s, $($samples.Count) rows, $(Fmt $wall '0') s in all):")
function Peak($name, $minimum) {
    $values = @($samples | Where-Object { $null -ne $_.$name } | ForEach-Object { [double]$_.$name })
    if ($values.Count -eq 0) { return 'n/a' }
    if ($minimum) { return Fmt ($values | Measure-Object -Minimum).Minimum '0' }
    return Fmt ($values | Measure-Object -Maximum).Maximum '0'
}
$summary.Add("  title private memory, peak: $(Peak 'PrivateMB' $false) MB   working set, peak: $(Peak 'WorkingSetMB' $false) MB")
$summary.Add("  free physical memory, lowest: $(Peak 'FreePhysicalMB' $true) MB   free commit, lowest: $(Peak 'FreeCommitMB' $true) MB")
$summary.Add("  pages/s, peak: $(Peak 'PagesPerSec' $false)   GPU dedicated memory (all adapters), peak: $(Peak 'GpuDedicatedMB' $false) MB")
$cpuRows = @($samples | Where-Object { $null -ne $_.CpuSeconds })
if ($cpuRows.Count -ge 2 -and $wall -gt 0) {
    $used = [double]$cpuRows[$cpuRows.Count - 1].CpuSeconds - [double]$cpuRows[0].CpuSeconds
    $span = [double]$cpuRows[$cpuRows.Count - 1].Seconds - [double]$cpuRows[0].Seconds
    if ($span -gt 0 -and $used -ge 0) {
        $cores = $used / $span
        $summary.Add("  title CPU use: $(Fmt $cores '0.00') cores on average of $([Environment]::ProcessorCount) logical (about 1 = a single thread saturated)")
    }
}
$summary | Set-Content -Path (Join-Path $dir 'summary.txt') -Encoding UTF8
$summary | Select-Object -Skip $info.Count | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host "Saved in $dir"
