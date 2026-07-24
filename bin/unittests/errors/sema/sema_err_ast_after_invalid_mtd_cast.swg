#global private
using Swag

struct AstAfterInvalidCastStringBuilder
{
    buf: [512] u8
    len: s32
}

struct AstAfterInvalidCastString
{
    buffer: #null [*] u8
    length: u64
}

impl AstAfterInvalidCastString
{
    #[Swag.Implicit, Swag.Inline]
    mtd const opCast()->string
    {
        return @mkstring(.buffer, .length)
    }
}

impl AstAfterInvalidCastStringBuilder
{
    mtd append(val: string)
    {
        @memcpy(&.buf[.len], @dataof(val), cast(u64) @countof(val))
        .len += cast(s32) @countof(val)
    }

    mtd toString()->AstAfterInvalidCastString
    {
        var result: AstAfterInvalidCastString
        result.buffer = &.buf[0]
        result.length = cast(u64) .len
        return result
    }
}

struct AstAfterInvalidCastDialog {}

struct(T) AstAfterInvalidCastSignal
{
    arr: #null [..] T
}

impl AstAfterInvalidCastSignal
{
    mtd call(params: ...)
    {
        for fn in .arr
        {
            #ast
            {
                var sb: AstAfterInvalidCastStringBuilder
                let ts = #typeof(T)
                sb.append("fn(")
                for i in @countof(ts.parameters)
                {
                    if i do
                        sb.append(",")
                    sb.append("cast(")
                    let paramType = notnull ts.parameters[i].pointedType
                    sb.append(notnull paramType.fullname)
                    sb.append(") params[")
                    sb.append("0")
                    sb.append("]")
                }
                sb.append(")\n")
                return sb.toString()
            }
        }
    }
}

struct AstAfterInvalidCastOwner
{
    callback: #null func||(*AstAfterInvalidCastDialog, string)->bool
    signal:   AstAfterInvalidCastSignal'func||(*AstAfterInvalidCastOwner)
}

impl AstAfterInvalidCastOwner
{
    mtd validSignalCall()
    {
        .signal.call(me)
    }

    mtd install()
    {
        let captured: #null *AstAfterInvalidCastDialog = null
        .callback = mtd|captured|(dlg, id) { return captured == dlg }
        .signal.call(me)     // swc-expected-error {{sema_err_cannot_cast}}
    }
}

#run
{
    var owner: AstAfterInvalidCastOwner
    owner.validSignalCall()
    owner.install()
}
