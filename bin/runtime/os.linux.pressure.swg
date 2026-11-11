#global if #os == Swag.TargetOs.Linux

namespace __LinuxRT
{
    #[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
    func sysconf(name: s32)->s64
}

private func __linuxReadProc(path: string, buffer: [..] u8, firstLine: bool = false)->u64
{
    let descriptor = __LinuxRT.open(path.buffer, __LinuxRT.CloseOnExec)
    if descriptor < 0 do
        return 0
    defer discard __LinuxRT.close(descriptor)
    var count = 0'u64
    while count < buffer.count
    {
        let amount = __LinuxRT.read(descriptor, &buffer[count], buffer.count - count)
        if amount == 0 do
            return count
        if amount < 0
        {
            if __LinuxRT.__errno_location()[] != __LinuxRT.Interrupted do
                return 0
            continue
        }
        let end = count + cast(u64, amount)
        if firstLine
        {
            for index in count until end where buffer[index] == 10 do
                return index
        }
        count = end
    }
    // A truncated snapshot is unavailable, not a low-pressure sample.
    return 0
}

private func __linuxUnsigned(bytes: const [..] u8, offset: *u64)->(u64, bool)
{
    while offset[] < bytes.count and (bytes[offset[]] == 32 or bytes[offset[]] == 9) do
        offset[] += 1
    let start = offset[]
    var value = 0'u64
    while offset[] < bytes.count
    {
        let digit = bytes[offset[]]
        if digit < 48 or digit > 57 do
            break
        let number = cast(u64, digit - 48)
        if value > (Swag.U64.Max - number) / 10 do
            return (0, false)
        value = value * 10 + number
        offset[] += 1
    }
    return (value, offset[] != start)
}

// System and process CPU counters use USER_HZ ticks. Memory has an independent validity bit:
// inaccessible procfs never turns into fabricated free capacity or an idle CPU.
func __hostWorkPressure()->Swag.WorkPressure
{
    var result: Swag.WorkPressure
    var buffer: [8192] u8
    let cpuLength = __linuxReadProc("/proc/stat", buffer, firstLine: true)
    if cpuLength >= 4 and Swag.memcmp(&buffer[0], "cpu ".buffer, 4) == 0
    {
        let line = Swag.makeSlice(&buffer[0], cpuLength)
        var offset = 4'u64
        var valid = true
        // Guest counters are already included in user/nice; add only the first eight fields.
        for index in 8'u32
        {
            let (value, present) = __linuxUnsigned(line, &offset)
            if not present
            {
                valid = false
                break
            }
            result.totalTicks += value
            if index == 3 or index == 4 do
                result.idleTicks += value
        }
        var process: __LinuxRT.Timespec
        let frequency = __LinuxRT.sysconf(2)     // _SC_CLK_TCK
        if valid and frequency > 0 and __LinuxRT.clock_gettime(2, &process) == 0
        {
            let ticksPerSecond    = cast(u64, frequency)
            let wholeSecondsTicks = cast(u64, process.seconds) * ticksPerSecond
            let subsecondTicks    = cast(u64, process.nanoseconds) * ticksPerSecond / 1_000_000_000
            result.processTicks = wholeSecondsTicks + subsecondTicks
            result.cpuValid = true
        }
    }

    let memoryLength = __linuxReadProc("/proc/meminfo", buffer)
    let memory = Swag.makeSlice(&buffer[0], memoryLength)
    var lineStart = 0'u64
    var fields = 0'u32
    var committed = 0'u64
    while lineStart < memoryLength
    {
        var lineEnd = lineStart
        while lineEnd < memoryLength and buffer[lineEnd] != 10 do
            lineEnd += 1
        let lineLength = lineEnd - lineStart
        const Names = ["MemTotal:", "MemAvailable:", "CommitLimit:", "Committed_AS:"]
        for name, index in Names
        {
            if lineLength < name.count or Swag.memcmp(&buffer[lineStart], name.buffer, name.count) != 0 do
                continue
            var offset = lineStart + name.count
            let (value, valid) = __linuxUnsigned(memory, &offset)
            if not valid or value > Swag.U64.Max / 1024 do
                break
            fields |= 1'u32 << cast(u32, index)
            switch index
            {
            case 0: result.physicalBytes = value * 1024
            case 1: result.availableBytes = value * 1024
            case 2: result.commitBytes = value * 1024
            case 3: committed = value * 1024
            }
            break
        }
        lineStart = lineEnd + 1
    }
    result.memoryValid = fields == 15
    result.availableCommitBytes = committed < result.commitBytes ? result.commitBytes - committed : 0
    return result
}
