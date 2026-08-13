#global private

// An rvalue struct receiver flowing through an #[Implicit, Inline] opCast into
// an #[Implicit] opSet: the inlined cast's elided members (`.buf`, `.len`) must
// read the TEMPORARY, not whatever local happens to sit nearby. Mirrors
// `g_StoreArgs = Utf8.fromUtf16(...)` in core's premain.
struct Fat
{
    buf: #null const [*] u8
    len: u64
}

impl Fat
{
    #[Swag.Implicit, Swag.Inline]
    mtd const opCast()->string
    {
        let buf = .buf!
        return @mkstring(buf, .len)
    }
}

struct Sink
{
    total: u64
    first: u8
}

impl Sink
{
    #[Swag.Implicit]
    mtd opSet(value: #null string)
    {
        .total = @countof(value)
        .first = @countof(value) ? value![0] : 0
    }
}

func makeFat(text: string)->Fat
{
    return Fat{buf: @dataof(text), len: @countof(text)}
}

#test
{
    // The decoy locals give a by-name symbol recovery something wrong to grab.
    let decoyPtr = "0123456789ABCDEF"
    var decoyLen = 999'u64
    decoyLen += 1

    var sink: Sink
    sink = makeFat("hello")
    @assert(sink.total == 5)
    @assert(sink.first == 'h'u8)
    @assert(@countof(decoyPtr) == 16)
}

var g_Sink: Sink

#test
{
    // Same shape through a GLOBAL assignment target, like g_StoreArgs.
    g_Sink = makeFat("worldly")
    @assert(g_Sink.total == 7)
    @assert(g_Sink.first == 'w'u8)
}
