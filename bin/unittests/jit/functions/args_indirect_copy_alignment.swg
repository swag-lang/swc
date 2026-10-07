#global private

struct SmallPayload
{
    a: u8
    b: u8
    c: u8
}

struct WidePayload
{
    a: u64
    b: u64
    c: u64
}

#[Swag.CallingConvention(.C)]
func combineCopies(small: SmallPayload, extra: u64, wide: WidePayload, scale: f64)->WidePayload
{
    return {wide.a + small.a + extra, wide.b + small.b + cast(u64, (scale * 2)), wide.c + small.c}
}

#test
{
    // The three-byte copy is followed by an eight-byte-aligned copy; the return also uses storage.
    const FIRST = #run combineCopies({1, 2, 3}, 7, {10, 20, 30}, 1.5)
    #assert(FIRST.a == 18)
    #assert(FIRST.b == 25)
    #assert(FIRST.c == 33)

    const SECOND = #run combineCopies({4, 5, 6}, 8, {100, 200, 300}, 2.5)
    #assert(SECOND.a == 112)
    #assert(SECOND.b == 210)
    #assert(SECOND.c == 306)
}
