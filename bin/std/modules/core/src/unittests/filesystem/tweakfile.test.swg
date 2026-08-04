#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct TweakAlpha
{
    foo: s32
    bar: s32
}

struct TweakBeta
{
    bar: s32
    foo: s32
}

#test
{
    var alpha: TweakAlpha
    var beta:  TweakBeta
    var tweak: File.TweakFile

    tweak.registerFolder'TweakAlpha(&alpha)
    tweak.registerFolder'TweakBeta(&beta)

    discard expect tweak.parse("/TweakAlpha\nfoo 1\nbar $foo\n/TweakBeta\nbar 2\nfoo $bar\n")
    @assert(alpha.foo == 1)
    @assert(alpha.bar == 1)
    @assert(beta.bar == 2)
    @assert(beta.foo == 2)
}

#test
{
    struct TweakCycle
    {
        foo: s32
        bar: s32
    }

    var cycle: TweakCycle
    var tweak: File.TweakFile

    tweak.registerFolder'TweakCycle(&cycle)

    discard catch tweak.parse("/TweakCycle\nfoo $bar\nbar $foo\n") as err2
    @assert(err2 != null)
    @assert(err2 is Errors.SyntaxError)
}

namespace TweakDeep
{
    public struct Sheet
    {
        width:  f32 = 1
        height: f32 = 2
    }

    public struct Palette
    {
        main: s32
    }
}

// A folder line names the struct without its namespace, and floats parse from integers.
#test
{
    var sheet:   TweakDeep.Sheet
    var palette: TweakDeep.Palette
    var tweak:   File.TweakFile

    tweak.registerFolder'TweakDeep.Sheet(&sheet)
    tweak.registerFolder'TweakDeep.Palette(&palette)

    discard expect tweak.parse("/Sheet\nwidth 44\nheight 27.5\n/Palette\nmain 3\n")
    @assert(sheet.width == 44)
    @assert(sheet.height == 27.5)
    @assert(palette.main == 3)
}
