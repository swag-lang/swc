#global private

struct JitOrelseNonNullItem
{
    value: u32
}

#[Swag.Strict]
alias JitOrelseNullablePointerAlias = #null *JitOrelseNonNullItem

func jitOrelseNonNullBranches()->bool
{
    var primaryItem  = JitOrelseNonNullItem{value: 11}
    var fallbackItem = JitOrelseNonNullItem{value: 22}
    var nullPointer: #null *JitOrelseNonNullItem = null
    var presentPointer: #null *JitOrelseNonNullItem = &primaryItem
    let fallbackPointer: #nonull *JitOrelseNonNullItem = &fallbackItem
    let selectedPointerFallback = nullPointer orelse fallbackPointer
    let selectedPointerPrimary  = presentPointer orelse fallbackPointer
    let aliasNullPointer         = cast(JitOrelseNullablePointerAlias) nullPointer
    let aliasPresentPointer      = cast(JitOrelseNullablePointerAlias) presentPointer
    let selectedAliasFallback    = aliasNullPointer orelse fallbackPointer
    let selectedAliasPrimary     = aliasPresentPointer orelse fallbackPointer

    #assert(#typeof(selectedPointerFallback) == #nonull *JitOrelseNonNullItem)
    #assert(#typeof(selectedPointerPrimary) == #nonull *JitOrelseNonNullItem)
    #assert(#typeof(selectedAliasFallback) == #nonull *JitOrelseNonNullItem)
    #assert(#typeof(selectedAliasPrimary) == #nonull *JitOrelseNonNullItem)
    if selectedPointerFallback != &fallbackItem or selectedPointerPrimary != &primaryItem do
        return false
    if selectedAliasFallback != &fallbackItem or selectedAliasPrimary != &primaryItem do
        return false

    var primaryValues: [2] u32 = [31, 32]
    var fallbackValues: [2] u32 = [41, 42]
    var nullSlice: #null [..] u32 = null
    var presentSlice: #null [..] u32 = primaryValues
    let fallbackSlice: #nonull [..] u32 = fallbackValues
    let selectedSliceFallback = nullSlice orelse fallbackSlice
    let selectedSlicePrimary  = presentSlice orelse fallbackSlice

    #assert(#typeof(selectedSliceFallback) == #nonull [..] u32)
    #assert(#typeof(selectedSlicePrimary) == #nonull [..] u32)
    if @countof(selectedSliceFallback) != 2 or selectedSliceFallback[0] != 41 or selectedSliceFallback[1] != 42 do
        return false
    if @countof(selectedSlicePrimary) != 2 or selectedSlicePrimary[0] != 31 or selectedSlicePrimary[1] != 32 do
        return false

    var nullAny: #null any = null
    var presentAny: #null any = 51'u32
    let fallbackAny: #nonull any = 61'u32
    let selectedAnyFallback = nullAny orelse fallbackAny
    let selectedAnyPrimary  = presentAny orelse fallbackAny

    #assert(#typeof(selectedAnyFallback) == #nonull any)
    #assert(#typeof(selectedAnyPrimary) == #nonull any)
    if cast(u32) selectedAnyFallback != 61 or cast(u32) selectedAnyPrimary != 51 do
        return false

    var nullType: #null typeinfo = null
    var presentType: #null typeinfo = s32
    let fallbackType: #nonull typeinfo = u64
    let selectedTypeFallback = nullType orelse fallbackType
    let selectedTypePrimary  = presentType orelse fallbackType

    #assert(#typeof(selectedTypeFallback) == #nonull typeinfo)
    #assert(#typeof(selectedTypePrimary) == #nonull typeinfo)
    return selectedTypeFallback == u64 and selectedTypePrimary == s32
}

#test
{
    @assert(jitOrelseNonNullBranches())
}
