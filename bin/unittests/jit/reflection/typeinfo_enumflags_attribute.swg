#global fileprivate
using Swag

// #[Swag.EnumFlags] is a built-in marker, but it must stay reflectable so user code can
// detect a flags enum through reflection (e.g. Reflection.hasAttribute). It is also kept
// as an rt-flag, so the enum still gets power-of-two flag values.
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

#test
{
    let te = cast(const *Swag.TypeInfoEnum) #typeof(FlagsProbe)
    @assert(@countof(te.attributes) == 1)
    @assert(te.attributes[0].type != null and te.attributes[0].type.name == "EnumFlags")

    // The flag semantics are preserved: values are powers of two.
    @assert(cast(s32) FlagsProbe.A == 1)
    @assert(cast(s32) FlagsProbe.B == 2)
    @assert(cast(s32) FlagsProbe.C == 4)

    // A plain enum gets no spurious attribute.
    let tp = cast(const *Swag.TypeInfoEnum) #typeof(PlainProbe)
    @assert(@countof(tp.attributes) == 0)
}
