#global namespace Swag

// Host counters share one time unit. Memory values are bytes; validity is independent.
#[Swag.NoDoc]
struct WorkPressure
{
    cpuValid:             bool
    memoryValid:          bool
    totalTicks:           u64
    idleTicks:            u64
    processTicks:         u64
    physicalBytes:        u64
    availableBytes:       u64
    commitBytes:          u64
    availableCommitBytes: u64
}

// Stateful admission policy, separated from host sampling so pressure transitions are testable.
#[Swag.NoDoc]
struct BackgroundBudget
{
    limit:    u32 = 1
    previous: WorkPressure
}

impl BackgroundBudget
{
    // Running bodies keep their slots. Contraction affects the next admission, never preempts work.
    mtd update(sample: WorkPressure, workers, running: u32)
    {
        var target = workers == 0 ? 1'u32 : workers
        if sample.cpuValid and
           .previous.cpuValid and
           sample.totalTicks > .previous.totalTicks and
           sample.idleTicks >= .previous.idleTicks and
           sample.processTicks >= .previous.processTicks
        {
            let elapsed  = sample.totalTicks - .previous.totalTicks
            let idle     = sample.idleTicks - .previous.idleTicks
            let own      = sample.processTicks - .previous.processTicks
            let busy     = idle < elapsed ? elapsed - idle : 0
            let external = own < busy ? busy - own : 0

            // Exclude this process so productive background work does not throttle itself.
            // Leave one worker's worth of CPU for interactive work when there is room.
            target = cast(u32, (cast(f64, elapsed - external) / cast(f64, elapsed)) * cast(f64, target))
            if target > 1 do
                target -= 1
        }
        else
        {
            target = .limit
        }

        if sample.memoryValid
        {
            // Keep an eighth of physical/commit capacity free. One additional body needs
            // 256 MiB of headroom; this is admission guidance, not an allocation guarantee.
            const PerBodyBytes = 256'u64 * 1024 * 1024
            let physicalReserve = sample.physicalBytes / 8
            let commitReserve   = sample.commitBytes / 8
            let physical        = sample.availableBytes > physicalReserve ? sample.availableBytes - physicalReserve : 0
            let commit          = sample.availableCommitBytes > commitReserve ? sample.availableCommitBytes - commitReserve : 0
            let headroom        = physical < commit ? physical : commit
            var memoryTarget    = cast(u64, running) + headroom / PerBodyBytes
            if sample.availableBytes <= physicalReserve or sample.availableCommitBytes <= commitReserve do
                memoryTarget = 1
            if memoryTarget < target do
                target = cast(u32, memoryTarget)
        }
        else
        {
            target = target < .limit ? target : .limit
        }

        if target == 0 do
            target = 1

        // Recover gradually; a single idle sample must not release the entire backlog at once.
        if target > .limit + 2 do
            target = .limit + 2
        if target > workers and workers != 0 do
            target = workers
        .limit    = target
        .previous = sample
    }
}
