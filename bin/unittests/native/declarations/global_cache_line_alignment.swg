#global private

// A global whose fields sit on their own cache lines must itself start on one, both when it
// is zero-initialized and when it carries initial values.
struct CacheLineFields
{
    head: u64
    #[Swag.Align(64)]
    hot: u64
    #[Swag.Align(64)]
    tail: u32
}

var GZeroLines: CacheLineFields
var GInitLines: CacheLineFields = CacheLineFields{head: 1, hot: 2, tail: 3}

#test
{
    #assert(#offsetof(CacheLineFields.hot) == 64)
    #assert(#offsetof(CacheLineFields.tail) == 128)
    #assert(#alignof(CacheLineFields) == 64)

    Swag.assert(cast(u64, &GZeroLines) % 64 == 0)
    Swag.assert(cast(u64, &GInitLines) % 64 == 0)
    Swag.assert(cast(u64, &GInitLines.hot) % 64 == 0)

    Swag.assert(GZeroLines.head == 0 and GZeroLines.hot == 0 and GZeroLines.tail == 0)
    Swag.assert(GInitLines.head == 1 and GInitLines.hot == 2 and GInitLines.tail == 3)

    GZeroLines.hot  = 7
    GInitLines.tail += 4
    Swag.assert(GZeroLines.hot == 7)
    Swag.assert(GInitLines.tail == 7)
}

struct WideAlignedFields
{
    head: u64
    #[Swag.Align(128)]
    hot: u64
}

var GZeroWide: WideAlignedFields
var GInitWide: WideAlignedFields = WideAlignedFields{head: 11, hot: 13}

#test
{
    #assert(#alignof(WideAlignedFields) == 128)
    #assert(#offsetof(WideAlignedFields.hot) == 128)
    Swag.assert(cast(u64, &GZeroWide) % 128 == 0)
    Swag.assert(cast(u64, &GInitWide) % 128 == 0)
    Swag.assert(cast(u64, &GInitWide.hot) % 128 == 0)
    Swag.assert(GZeroWide.head == 0 and GZeroWide.hot == 0)
    Swag.assert(GInitWide.head == 11 and GInitWide.hot == 13)
    GZeroWide.hot = 17
    GInitWide.hot += 2
    Swag.assert(GZeroWide.hot == 17 and GInitWide.hot == 15)
}

// Cross the compiler's paged-storage boundary, including initialized data produced by #run.
var GZeroLarge: [129]WideAlignedFields
var GInitLarge: [129]WideAlignedFields

#run
{
    Swag.assert(cast(u64, &GInitLarge) % 128 == 0)
    GInitLarge[128].hot = 19
}

#test
{
    Swag.assert(cast(u64, &GZeroLarge) % 128 == 0)
    Swag.assert(cast(u64, &GInitLarge) % 128 == 0)
    Swag.assert(cast(u64, &GInitLarge[128].hot) % 128 == 0)
    Swag.assert(GZeroLarge[128].hot == 0)
    Swag.assert(GInitLarge[128].hot == 19)
    GZeroLarge[128].hot = 23
    Swag.assert(GZeroLarge[128].hot == 23)
}
