#global private

// An rvalue struct receiver flowing through an #[Implicit, Inline] opCast into
// an #[Implicit] opSet: the synthesized opCast call must pass the temporary's
// ADDRESS as its pointer receiver, never the temporary's first bytes as the
// pointer value. Mirrors `g_StoreArgs = Utf8.fromUtf16(...)` in core's premain.
struct CastFat
{
    buf: #null const [*] u8
    len: u64
}

impl CastFat
{
    #[Swag.Implicit, Swag.Inline]
    mtd const opCast()->string
    {
        let buf = .buf!
        return @mkstring(buf, .len)
    }
}

struct CastSink
{
    total: u64
    first: u8
}

impl CastSink
{
    #[Swag.Implicit]
    mtd opSet(value: #null string)
    {
        .total = @countof(value)
        .first = @countof(value) ? value![0] : 0
    }
}

func makeCastFat(text: string)->CastFat
{
    return CastFat{buf: @dataof(text), len: @countof(text)}
}

var g_CastSink: CastSink

#test
{
    // The decoy locals give a by-name symbol recovery something wrong to grab.
    let decoyPtr = "0123456789ABCDEF"
    var decoyLen = 999'u64
    decoyLen += 1

    var sink: CastSink
    sink = makeCastFat("hello")
    @assert(sink.total == 5)
    @assert(sink.first == 'h'u8)
    @assert(@countof(decoyPtr) == 16)

    // Same shape through a GLOBAL assignment target, like g_StoreArgs.
    g_CastSink = makeCastFat("worldly")
    @assert(g_CastSink.total == 7)
    @assert(g_CastSink.first == 'w'u8)
}
