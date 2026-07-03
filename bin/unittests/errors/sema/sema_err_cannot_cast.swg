#global private

const CannotCastSwitchPointerValues = [11, 22]
const CannotCastSwitchPointerBytes  = ['x''u8, 'y''u8]

#test
{
    let c   = @compiler
    let msg = c.getMessage()
    let cfg = c.getBuildCfg()
    c.compileString("")
    #assert(#typeof(msg) == const *Swag.CompilerMessage)
    #assert(#typeof(cfg) == *Swag.BuildCfg)
}

#test
{
    let c = @compiler
    c.compileString(1) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    const bad: [2] u16 = [
        0'u16,
        true // swc-expected-error {{sema_err_cannot_cast}}
    ]
}

#test
{
    const bad: [1, 2] u16 = [
        [
            0'u16,
            true // swc-expected-error {{sema_err_cannot_cast}}
        ]
    ]
}

#test
{
    var value: s64 = 0
    var data: [2] s32 = [10, 20]
    let ptr = cast([*] s32) &data[0]
    value += ptr // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var data: [2] s32 = [10, 20]
    var ptr = cast([*] s32) &data[0]
    let other = ptr + 1
    ptr -= other // swc-expected-error {{sema_err_cannot_cast}}
}

#[Swag.Strict]
alias CannotCastOpCastStrictS32 = s32

struct CannotCastOpCastBox
{
}

impl CannotCastOpCastBox
{
    #[Swag.Implicit]
    mtd const opCast() -> CannotCastOpCastStrictS32
    {
        return cast(CannotCastOpCastStrictS32) 12
    }
}

func consumeCannotCastRawS32(value: s32)
{
}

#test
{
    var box: CannotCastOpCastBox
    consumeCannotCastRawS32(box) // swc-expected-error {{sema_err_cannot_cast}}
}

alias CannotCastExactDigest = [16] u8

func consumeCannotCastExact4(values: [4] s32)
{
}

func consumeCannotCastExactDigest(digest: CannotCastExactDigest)
{
}

func consumeCannotCastExactGrid(grid: [2, 3] s16)
{
}

#test
{
    var values: [4] s32 = [1, 2, 3, 4]
    let view: const [..] s32 = cast(const [..] s32) values
    consumeCannotCastExact4(view) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    let value: any = null
    let fallback: any = true
    let resolved = value orelse fallback // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    switch &CannotCastSwitchPointerValues[0]
    {
        case &CannotCastSwitchPointerBytes[0]: // swc-expected-error {{sema_err_cannot_cast}}
            break
        default:
            break
    }
}
