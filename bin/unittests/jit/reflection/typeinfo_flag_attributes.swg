#global fileprivate
using Swag

// Built-in attributes that the compiler turns into fast-lookup rt-flags must also stay
// visible in reflection, so user code can query them (Reflection.hasAttribute, ...). This
// holds for every such attribute, not just EnumFlags.

#[Swag.EnumFlags]
enum FlagsProbe
{
    A
    B
    C
}

enum PlainProbe
{
    X
    Y
}

#[Swag.Opaque]
struct OpaqueProbe
{
    v: s32
}

struct PlainStructProbe
{
    v: s32
}

#[Swag.ConstExpr]
func constExprProbe()->s32
{
    return 1
}

#test
{
    // EnumFlags is reflected, and the flag semantics (power-of-two values) are preserved.
    let te = cast(const *Swag.TypeInfoEnum) #typeof(FlagsProbe)
    @assert(@countof(te.attributes) == 1)
    @assert(te.attributes[0].type != null and te.attributes[0].type.name == "EnumFlags")
    @assert(cast(s32) FlagsProbe.A == 1 and cast(s32) FlagsProbe.B == 2 and cast(s32) FlagsProbe.C == 4)

    // Other built-in flag attributes are reflected too: Opaque (struct), ConstExpr (func).
    let ts = cast(const *Swag.TypeInfoStruct) #typeof(OpaqueProbe)
    @assert(@countof(ts.attributes) == 1 and ts.attributes[0].type.name == "Opaque")

    let tf = cast(const *Swag.TypeInfoFunc) #typeof(constExprProbe)
    @assert(@countof(tf.attributes) == 1 and tf.attributes[0].type.name == "ConstExpr")

    // Entities without such attributes stay empty.
    let tp = cast(const *Swag.TypeInfoEnum) #typeof(PlainProbe)
    @assert(@countof(tp.attributes) == 0)
    let tsp = cast(const *Swag.TypeInfoStruct) #typeof(PlainStructProbe)
    @assert(@countof(tsp.attributes) == 0)
}
