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
var GInitLines: CacheLineFields = {head: 1, hot: 2, tail: 3}

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
