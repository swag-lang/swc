#global fileprivate

const LocalAstValue = #run
{
    var value = 2
    #ast "value += 5"
    #ast
    {
        return "value += 7"
    }
    return value
}

#assert(LocalAstValue == 14)

struct GeneratedFields
{
    #ast
    {
        return "x, y: s32 = 42"
    }
}

struct(T) GenericFields
{
    #ast
    {
        return "first, second: " ++ #typeof(T).name
    }

    label: string
}

enum GeneratedEnum
{
    #ast
    {
        return "One = 1,\nTwo = 2"
    }
}

#[Swag.Compiler]
func appendAst(buf: [*] u8, start: s32, val: string)->s32
{
    @memcpy(buf + start, @dataof(val), cast(u64) @countof(val))
    return start + cast(s32) @countof(val)
}

struct Vector3
{
    #ast
    {
        var buf: [256] u8
        var len = 0
        len = appendAst(buf, len, "x: f32 = 1\n")
        len = appendAst(buf, len, "y: f32 = 2\n")
        len = appendAst(buf, len, "z: f32 = 3\n")
        return cast(string) @mkslice(&buf[0], cast(u64) len)
    }
}

#ast "const GlobalGenerated = 123"
#assert(GlobalGenerated == 123)

#run
{
    let fields: GeneratedFields
    #assert(fields.x == 42)
    #assert(fields.y == 42)

    let genericBool: GenericFields'bool
    #assert(#typeof(genericBool.first) == bool)
    #assert(#typeof(genericBool.second) == bool)
    #assert(#typeof(genericBool.label) == string)

    let genericFloat: GenericFields'f64
    #assert(#typeof(genericFloat.first) == f64)
    #assert(#typeof(genericFloat.second) == f64)

    let vec: Vector3
    #assert(vec.x == 1)
    #assert(vec.y == 2)
    #assert(vec.z == 3)

    #assert(cast(s32) GeneratedEnum.One == 1)
    #assert(cast(s32) GeneratedEnum.Two == 2)
}
