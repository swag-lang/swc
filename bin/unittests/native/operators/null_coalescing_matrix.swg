#global private
using Swag

interface INullCoalescingProbe
{
    mtd write(value: *u64);
}

struct NullCoalescingProbe
{
    tag: u64
}

impl INullCoalescingProbe for NullCoalescingProbe
{
    mtd impl write(value: *u64)
    {
        dref value = .tag
    }
}

func probeObject(itf: INullCoalescingProbe)->*void
{
    let runtimeItf = cast(const *Swag.Interface) &itf
    return runtimeItf.obj
}

func probeITable(itf: INullCoalescingProbe)->const *void
{
    let runtimeItf = cast(const *Swag.Interface) &itf
    return runtimeItf.itable
}

func falseBoolFallback(value: bool)->bool
{
    return value orelse true
}

func nullStringFallback()->bool
{
    var value: string = null
    let fallback = "fallback"
    let resolved = value orelse fallback
    return resolved == fallback
}

func nonNullStringWins()->bool
{
    let value = "ok"
    let fallback = "fallback"
    let resolved = value orelse fallback
    return resolved == value
}

func nullSliceFallback()->bool
{
    var value: [..] u32 = null
    let fallbackValues: [2] u32 = [7, 9]
    let fallback: [..] u32 = fallbackValues
    let resolved = value orelse fallback
    return @countof(resolved) == 2 and resolved[0] == 7 and resolved[1] == 9
}

func nonNullSliceWins()->bool
{
    let primaryValues: [2] u32 = [1, 2]
    let fallbackValues: [2] u32 = [7, 9]
    let primary: [..] u32 = primaryValues
    let fallback: [..] u32 = fallbackValues
    let resolved = primary orelse fallback
    return @countof(resolved) == 2 and resolved[0] == 1 and resolved[1] == 2
}

func nullInterfaceFallbackWritesThroughSelectedReceiver()->bool
{
    var value: INullCoalescingProbe = null
    var fallbackProbe = NullCoalescingProbe{tag: 77}
    let fallback = @mkinterface(&fallbackProbe, #typeof(fallbackProbe), INullCoalescingProbe)
    let selected = value orelse fallback

    var written: u64 = 0
    selected.write(&written)
    return written == 77 and
           probeObject(selected) == probeObject(fallback) and
           probeITable(selected) == probeITable(fallback)
}

func nonNullInterfaceWinsAndKeepsRuntimeShape()->bool
{
    var primaryProbe = NullCoalescingProbe{tag: 11}
    var fallbackProbe = NullCoalescingProbe{tag: 22}
    let primary = @mkinterface(&primaryProbe, #typeof(primaryProbe), INullCoalescingProbe)
    let fallback = @mkinterface(&fallbackProbe, #typeof(fallbackProbe), INullCoalescingProbe)
    let selected = primary orelse fallback

    var written: u64 = 0
    selected.write(&written)
    return written == 11 and
           probeObject(selected) == probeObject(primary) and
           probeITable(selected) == probeITable(primary) and
           probeObject(selected) != probeObject(fallback)
}

#test
{
    @assert(falseBoolFallback(false))
    @assert(falseBoolFallback(true))
    @assert(nullStringFallback())
    @assert(nonNullStringWins())
}

#test
{
    @assert(nullSliceFallback())
    @assert(nonNullSliceWins())
}

#test
{
    @assert(nullInterfaceFallbackWritesThroughSelectedReceiver())
    @assert(nonNullInterfaceWinsAndKeepsRuntimeShape())
}
