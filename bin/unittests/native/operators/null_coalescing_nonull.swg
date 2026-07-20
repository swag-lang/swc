#global private

struct NativeOrelseNonNullItem
{
    value: u32
}

#[Swag.Strict]
alias NativeOrelseNullablePointerAlias = #null *NativeOrelseNonNullItem

func nativeOrelseNonNullBranches()->bool
{
    var primaryItem  = NativeOrelseNonNullItem{value: 11}
    var fallbackItem = NativeOrelseNonNullItem{value: 22}
    var nullPointer: #null *NativeOrelseNonNullItem = null
    var presentPointer: #null *NativeOrelseNonNullItem = &primaryItem
    let fallbackPointer: *NativeOrelseNonNullItem = &fallbackItem
    let selectedPointerFallback = nullPointer orelse fallbackPointer
    let selectedPointerPrimary  = presentPointer orelse fallbackPointer
    let aliasNullPointer         = cast(NativeOrelseNullablePointerAlias) nullPointer
    let aliasPresentPointer      = cast(NativeOrelseNullablePointerAlias) presentPointer
    let selectedAliasFallback    = aliasNullPointer orelse fallbackPointer
    let selectedAliasPrimary     = aliasPresentPointer orelse fallbackPointer

    #assert(#typeof(selectedPointerFallback) == *NativeOrelseNonNullItem)
    #assert(#typeof(selectedPointerPrimary) == *NativeOrelseNonNullItem)
    #assert(#typeof(selectedAliasFallback) == *NativeOrelseNonNullItem)
    #assert(#typeof(selectedAliasPrimary) == *NativeOrelseNonNullItem)
    if selectedPointerFallback != &fallbackItem or selectedPointerPrimary != &primaryItem do
        return false
    if selectedAliasFallback != &fallbackItem or selectedAliasPrimary != &primaryItem do
        return false

    var primaryValues: [2] u32 = [31, 32]
    var fallbackValues: [2] u32 = [41, 42]
    var nullSlice: #null [..] u32 = null
    var presentSlice: #null [..] u32 = primaryValues
    let fallbackSlice: [..] u32 = fallbackValues
    let selectedSliceFallback = nullSlice orelse fallbackSlice
    let selectedSlicePrimary  = presentSlice orelse fallbackSlice

    #assert(#typeof(selectedSliceFallback) == [..] u32)
    #assert(#typeof(selectedSlicePrimary) == [..] u32)
    if @countof(selectedSliceFallback) != 2 or selectedSliceFallback[0] != 41 or selectedSliceFallback[1] != 42 do
        return false
    if @countof(selectedSlicePrimary) != 2 or selectedSlicePrimary[0] != 31 or selectedSlicePrimary[1] != 32 do
        return false

    var nullAny: #null any = null
    var presentAny: #null any = 51'u32
    let fallbackAny: any = 61'u32
    let selectedAnyFallback = nullAny orelse fallbackAny
    let selectedAnyPrimary  = presentAny orelse fallbackAny

    #assert(#typeof(selectedAnyFallback) == any)
    #assert(#typeof(selectedAnyPrimary) == any)
    if cast(u32) selectedAnyFallback != 61 or cast(u32) selectedAnyPrimary != 51 do
        return false

    var nullType: #null typeinfo = null
    var presentType: #null typeinfo = s32
    let fallbackType: typeinfo = u64
    let selectedTypeFallback = nullType orelse fallbackType
    let selectedTypePrimary  = presentType orelse fallbackType

    #assert(#typeof(selectedTypeFallback) == typeinfo)
    #assert(#typeof(selectedTypePrimary) == typeinfo)
    return selectedTypeFallback == u64 and selectedTypePrimary == s32
}

#test
{
    @assert(nativeOrelseNonNullBranches())
}
