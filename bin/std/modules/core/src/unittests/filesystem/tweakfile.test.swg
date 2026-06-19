#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
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

    discard catch tweak.parse("/TweakAlpha\nfoo 1\nbar $foo\n/TweakBeta\nbar 2\nfoo $bar\n")
    @assert(@err == null)

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

    discard catch tweak.parse("/TweakCycle\nfoo $bar\nbar $foo\n")
    @assert(@err != null)
    @assert(@err is Errors.SyntaxError)
}
