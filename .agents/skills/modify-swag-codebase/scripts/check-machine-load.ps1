[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int] $MaxCpuPercent = 65,

    [ValidateRange(1, 100)]
    [int] $MinAvailableMemoryPercent = 25,

    [ValidateRange(1, 1024)]
    [double] $MinAvailableMemoryGiB = 8,

    [ValidateRange(1, 100)]
    [int] $MinCommitHeadroomPercent = 20,

    [ValidateRange(1, 1024)]
    [double] $MinCommitHeadroomGiB = 8,

    [ValidateRange(1, 10)]
    [int] $CpuSampleSeconds = 5
)

$ErrorActionPreference = 'Stop'
$gib = 1GB

try {
    $cpuBefore = Get-CimInstance Win32_PerfRawData_PerfOS_Processor -Filter "Name='_Total'"
    Start-Sleep -Seconds $CpuSampleSeconds
    $cpuAfter = Get-CimInstance Win32_PerfRawData_PerfOS_Processor -Filter "Name='_Total'"

    $computer = Get-CimInstance Win32_ComputerSystem
    $memory = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory

    $elapsedTime = [double] $cpuAfter.Timestamp_Sys100NS - [double] $cpuBefore.Timestamp_Sys100NS
    $idleTime = [double] $cpuAfter.PercentProcessorTime - [double] $cpuBefore.PercentProcessorTime
    if ($elapsedTime -le 0) {
        throw 'The CPU performance counter did not advance.'
    }

    $averageCpu = 100 * (1 - $idleTime / $elapsedTime)
    $averageCpu = [math]::Max(0, [math]::Min(100, $averageCpu))
    $totalPhysical = [double] $computer.TotalPhysicalMemory
    $availablePhysical = [double] $memory.AvailableBytes
    $commitLimit = [double] $memory.CommitLimit
    $commitHeadroom = $commitLimit - [double] $memory.CommittedBytes

    $requiredPhysical = [math]::Max(
        $MinAvailableMemoryGiB * $gib,
        $totalPhysical * $MinAvailableMemoryPercent / 100
    )
    $requiredCommitHeadroom = [math]::Max(
        $MinCommitHeadroomGiB * $gib,
        $commitLimit * $MinCommitHeadroomPercent / 100
    )

    $cpuReady = $averageCpu -le $MaxCpuPercent
    $physicalReady = $availablePhysical -ge $requiredPhysical
    $commitReady = $commitHeadroom -ge $requiredCommitHeadroom
    $ready = $cpuReady -and $physicalReady -and $commitReady

    [pscustomobject] @{
        Status                     = if ($ready) { 'ready' } else { 'wait' }
        AverageCpuPercent          = [math]::Round($averageCpu, 1)
        MaximumCpuPercent          = $MaxCpuPercent
        AvailablePhysicalGiB       = [math]::Round($availablePhysical / $gib, 1)
        RequiredPhysicalGiB        = [math]::Round($requiredPhysical / $gib, 1)
        CommitHeadroomGiB          = [math]::Round($commitHeadroom / $gib, 1)
        RequiredCommitHeadroomGiB  = [math]::Round($requiredCommitHeadroom / $gib, 1)
    } | Format-List

    if ($ready) {
        exit 0
    }

    exit 2
}
catch {
    Write-Error "Cannot measure machine load: $($_.Exception.Message)"
    exit 1
}
