#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct ParseInner
{
    x, y: f32
    w, h: f32
}

struct ParseOuter
{
    rect:   ParseInner
    corner: f32
    keep    = true
}

// A struct decodes as a brace-enclosed field list in declaration order, nesting included.
#test
{
    var value: ParseOuter
    let rest = expect StrConv.parseValue(&value, #typeof(ParseOuter), "{{1 29 27 27} 13 false} tail")
    @assert(value.rect.x == 1)
    @assert(value.rect.y == 29)
    @assert(value.rect.w == 27)
    @assert(value.rect.h == 27)
    @assert(value.corner == 13)
    @assert(!value.keep)
    @assert(Tokenize.eatSpaces(rest orelse "") == "tail")
}

// Commas between field values are accepted, and an early '}' keeps the remaining defaults.
#test
{
    var value: ParseOuter
    discard expect StrConv.parseValue(&value, #typeof(ParseOuter), "{{1, 2, 3, 4} 5}")
    @assert(value.rect.h == 4)
    @assert(value.corner == 5)
    @assert(value.keep)
}

// A missing opening or closing brace is a decoding error.
#test
{
    var value: ParseOuter
    discard catch StrConv.parseValue(&value, #typeof(ParseOuter), "1 2 3") as err
    @assert(err != null)
    @assert(err is Errors.InvalidFormatError)

    discard catch StrConv.parseValue(&value, #typeof(ParseOuter), "{{1 2 3 4} 5") as err2
    @assert(err2 != null)
    @assert(err2 is Errors.InvalidFormatError)
}

// A struct field parses from a tweak line, which is what theme sheets rely on.
#test
{
    struct TweakRects
    {
        first:  ParseOuter
        second: ParseOuter
    }

    var rects: TweakRects
    var tweak: File.TweakFile
    tweak.registerFolder'TweakRects(&rects)

    discard expect tweak.parse("/TweakRects\nfirst {{1 29 27 27} 0}\nsecond $first\n")
    @assert(rects.first.rect.y == 29)
    @assert(rects.first.corner == 0)
    @assert(rects.second.rect.y == 29)
}
