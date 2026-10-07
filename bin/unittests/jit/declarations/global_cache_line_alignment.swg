#global private

// Compile-time code reads globals from the compiler's own storage: a global whose fields sit
// on their own cache lines must start on one there too.
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
