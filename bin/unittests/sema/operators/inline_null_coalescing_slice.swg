#global fileprivate

#[Swag.Inline]
func inlineNullCoalescingSliceFallback()->bool
{
    var value: [..] u32 = null
    let fallbackValues: [2] u32 = [7, 9]
    let fallback: [..] u32 = fallbackValues
    let resolved = value orelse fallback
    return @countof(resolved) == 2 and resolved[0] == 7 and resolved[1] == 9
}

func semaTest001()
{
    const V = #run true and inlineNullCoalescingSliceFallback()
    #assert(V)
}
