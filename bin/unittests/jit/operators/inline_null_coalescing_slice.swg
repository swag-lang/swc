#global private

#[Swag.Inline]
func inlineJitNullCoalescingSliceFallback()->bool
{
    var value: [..] u32 = null
    let fallbackValues: [2] u32 = [7, 9]
    let fallback: [..] u32 = fallbackValues
    let resolved = value orelse fallback
    return @countof(resolved) == 2 and resolved[0] == 7 and resolved[1] == 9
}

#[Swag.Inline]
func inlineJitNullCoalescingBoolFallback(value: bool)->bool
{
    return value orelse true
}

#[Swag.Inline]
func inlineJitNullCoalescingStringFallback()->bool
{
    var value: string = null
    let fallback = "fallback"
    let resolved = value orelse fallback
    return resolved == fallback
}

#[Swag.Inline]
func inlineJitNonNullCoalescingSliceWins()->bool
{
    let primaryValues: [2] u32 = [1, 2]
    let fallbackValues: [2] u32 = [7, 9]
    let primary: [..] u32 = primaryValues
    let fallback: [..] u32 = fallbackValues
    let resolved = primary orelse fallback
    return @countof(resolved) == 2 and resolved[0] == 1 and resolved[1] == 2
}

#test
{
    const ok = #run inlineJitNullCoalescingSliceFallback() and
                    inlineJitNonNullCoalescingSliceWins()
    #assert(ok)
}
