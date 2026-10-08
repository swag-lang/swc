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
    Swag.assert(alpha.foo == 1)
    Swag.assert(alpha.bar == 1)
    Swag.assert(beta.bar == 2)
    Swag.assert(beta.foo == 2)
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
    Swag.assert(err2 != null)
    Swag.assert(err2 is Errors.SyntaxError)
}

// A reference cycle that does not pass through the first reference is reported too.
#test
{
    struct TweakLoop
    {
        first:  s32
        second: s32
        third:  s32
    }

    var loop:  TweakLoop
    var tweak: File.TweakFile
    tweak.registerFolder'TweakLoop(&loop)

    discard catch tweak.parse("/TweakLoop\nfirst $second\nsecond $third\nthird $second\n") as err
    Swag.assert(err is Errors.SyntaxError)
}

namespace TweakDeep
{
    public struct Sheet
    {
        public
        {
            width:  f32 = 1
            height: f32 = 2
        }
    }

    public struct Palette
    {
        public main: s32
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
    Swag.assert(sheet.width == 44)
    Swag.assert(sheet.height == 27.5)
    Swag.assert(palette.main == 3)
}

// Captured parser failures retain the domain message and one-based input line.
#test
{
    struct InvalidLine
    {
        source:  string
        message: string
    }

    let cases: [4] InvalidLine = [
        {"\n/\n",        "invalid folder name"},
        {"\n@\n",        "invalid value name"},
        {"\nfoo $\n",    "invalid reference name"},
        {"\n/Missing\n", "unknown folder [[Missing]]"}]

    for invalid in cases
    {
        var alpha: TweakAlpha
        var tweak: File.TweakFile
        tweak.registerFolder(&alpha)

        discard catch tweak.parse(invalid.source) as error
        Swag.assert(error is Errors.SyntaxError)
        Swag.assert(Errors.message(error) == invalid.message)
        let syntax = assume cast(const *Errors.SyntaxError, error)
        Swag.assert(syntax.line == 2)
        Swag.assert(alpha.foo == 0 and alpha.bar == 0)
    }
}

// An unknown folder after a known one is reported on its own line; it neither keeps the earlier
// selection nor undoes the assignments made under it.
#test
{
    var alpha: TweakAlpha
    var beta:  TweakBeta
    var tweak: File.TweakFile
    tweak.registerFolder(&alpha)
    tweak.registerFolder(&beta)

    discard catch tweak.parse("/TweakAlpha\nfoo 1\n/Missing\nbar 2\n") as error
    Swag.assert(error is Errors.SyntaxError)
    Swag.assert(Errors.message(error) == "unknown folder [[Missing]]")
    let syntax = assume cast(const *Errors.SyntaxError, error)
    Swag.assert(syntax.line == 3)
    Swag.assert(alpha.foo == 1 and alpha.bar == 0)
    Swag.assert(beta.foo == 0 and beta.bar == 0)
}
