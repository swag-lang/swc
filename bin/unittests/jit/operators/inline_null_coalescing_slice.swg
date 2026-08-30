#global private

#[Swag.Inline]
func inlineJitNullCoalescingSliceFallback()->bool
{
    var value:          #null [..] u32 = null
    let fallbackValues: [2] u32        = [7, 9]
    let fallback:       [..] u32       = fallbackValues
    let resolved                       = value orelse fallback
    return resolved.count == 2 and resolved[0] == 7 and resolved[1] == 9
}

#[Swag.Inline]
func inlineJitNullCoalescingStringFallback()->bool
{
    var value: #null string = null
    let fallback            = "fallback"
    let resolved            = value orelse fallback
    return resolved == fallback
}

#[Swag.Inline]
func inlineJitNonNullCoalescingSliceWins()->bool
{
    let primaryValues:  [2] u32  = [1, 2]
    let fallbackValues: [2] u32  = [7, 9]
    let primary:        [..] u32 = primaryValues
    let fallback:       [..] u32 = fallbackValues
    let resolved                 = primary orelse fallback
    return resolved.count == 2 and resolved[0] == 1 and resolved[1] == 2
}

#test
{
    const ok = #run inlineJitNullCoalescingSliceFallback() and
               inlineJitNonNullCoalescingSliceWins()
    #assert(ok)
}

// 'orelse' substitutes a MISSING value, not a zero one: an empty (but present) operand
// flows through untouched, and only a null one reaches the fallback.
#test
{
    var empty = ""
    Swag.assert((empty orelse "fallback") == "")

    var missing: #null string = null
    Swag.assert((missing orelse "fallback") == "fallback")

    // The result drops '#null': it is guaranteed present.
    #assert(#typeof(missing orelse "fallback") == string)
}
