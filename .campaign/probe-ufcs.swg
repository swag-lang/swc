#global private

#[Swag.EnumFlags]
enum ProbeFlags
{
    Zero = 0
    One  = 1
    Two  = 2
    Four = 4
}

func paddc(flags: *ProbeFlags, value: ProbeFlags)
{
    dref flags |= value
}

func(T) padd(flags: *T, value: T)
{
    dref flags |= value
}

struct Holder
{
    flags: ProbeFlags = .Zero
}

#test
{
    var local = ProbeFlags.Zero
    local.paddc(.One)
    @assert(local == .One)

    var holder: Holder
    holder.flags.paddc(.Two)
    @assert(holder.flags == .Two)
}

#test
{
    var local = ProbeFlags.Zero
    local.padd(.One)
    @assert(local == .One)
}

func bumpBy(value: *u32, amount: u32)
{
    dref value += amount
}

#test
{
    var counter: u32 = 3
    let probeAddr = &counter
    @assert(probeAddr != null)
    counter.bumpBy(4)
    @assert(counter == 7)
}
