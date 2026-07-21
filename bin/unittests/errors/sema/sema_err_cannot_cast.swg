#global private

const CannotCastSwitchPointerValues = [11, 22]
const CannotCastSwitchPointerBytes  = ['x''u8, 'y''u8]

#test
{
    let c   = @compiler
    let msg = c.getMessage()
    let cfg = c.getBuildCfg()
    c.compileString("")
    #assert(#typeof(msg) == #null const *Swag.CompilerMessage)
    #assert(#typeof(cfg) == #null *Swag.BuildCfg)
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
    let value: #null any = null
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

#test
{
    // A '#move' parameter only binds a move reference formed with '#move': a plain address must not match.
    struct MoveBindVec { x: s32 }
    func takeMoveBind(v: #move MoveBindVec) {}
    var value: MoveBindVec
    takeMoveBind(&value) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // An invalid scalar fill of an array must report the element cast failure
    // (it used to be silently swallowed by the runtime-array-fill setup).
    var values: [2] *s32 = 12 // swc-expected-error {{sema_err_cannot_cast}}
}

// ----------------------------------------------------------------------------
// Limits of nullable flow narrowing: outside a proven-non-null region, binding a
// nullable pointer to a non-null parameter stays a cast error.

struct NarrowLimitNode { value: s32 }
func narrowLimitTakes(p: *NarrowLimitNode) {}

#test
{
    // The else branch of a truthiness guard is exactly where the value IS null.
    var p: #null *NarrowLimitNode
    if p {}
    else do
        narrowLimitTakes(p) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // A guard whose branch does not terminate proves nothing afterwards.
    var p: #null *NarrowLimitNode
    if p {}
    narrowLimitTakes(p) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // Reassigning from a nullable source re-nullifies inside the guarded block.
    var storage: NarrowLimitNode
    var p: #null *NarrowLimitNode = &storage
    if p
    {
        p = null
        narrowLimitTakes(p) // swc-expected-error {{sema_err_cannot_cast}}
    }
}

#test
{
    // Taking the address of the guarded variable drops its narrowing.
    var storage: NarrowLimitNode
    var p: #null *NarrowLimitNode = &storage
    if p
    {
        let pp = &p
        dref pp = null
        narrowLimitTakes(p) // swc-expected-error {{sema_err_cannot_cast}}
    }
}

#test
{
    // A loop body that reassigns the variable cannot rely on an outer guard: the
    // reassignment flows back through the loop's back edge.
    var storage: NarrowLimitNode
    var p: #null *NarrowLimitNode = &storage
    var i = 0
    if p
    {
        while i < 2
        {
            narrowLimitTakes(p) // swc-expected-error {{sema_err_cannot_cast}}
            p = null
            i += 1
        }
    }
}

#test
{
    // A defer body runs at scope exit: narrowing at the declaration point does not hold.
    var storage: NarrowLimitNode
    var p: #null *NarrowLimitNode = &storage
    if p
    {
        defer narrowLimitTakes(p) // swc-expected-error {{sema_err_cannot_cast}}
    }
}

#test
{
    // `a or b` proves nothing about either operand when taken.
    var p, q: #null *NarrowLimitNode
    if p or q do
        narrowLimitTakes(p) // swc-expected-error {{sema_err_cannot_cast}}
}
