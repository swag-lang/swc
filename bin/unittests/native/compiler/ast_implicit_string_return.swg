#global private

struct AstGeneratedString
{
    buffer: [*] u8?
    length: u64
}

impl AstGeneratedString
{
    #[Implicit]
    mtd const opCast()->string
    {
        return Swag.makeString(.buffer, .length)
    }
}

struct AstGeneratedBuilder
{
    buffer:   [*] u8?
    length:   u64
    capacity: u64
}

impl AstGeneratedBuilder
{
    mtd opDrop()
    {
        if !.buffer do
            return

        for i in .length do
            .buffer[i] = 0
        testFree(.buffer)
    }

    mtd append(value: string)
    {
        if !.buffer
        {
            .capacity = 128
            .buffer   = cast([*] u8?) testAlloc(.capacity)
        }

        Swag.assert(.length + cast(u64) value.count <= .capacity)
        Swag.memcpy(.buffer + .length, value.buffer, cast(u64) value.count)
        .length += cast(u64) value.count
    }

    mtd const toString()->AstGeneratedString
    {
        return {.buffer, .length}
    }
}

var compilerAstImplicitStringTotal: s32

#test
{
    #ast
    {
        var sb: AstGeneratedBuilder
        sb.append("compilerAstImplicitStringTotal += 17\n")
        return sb.toString()
    }

    Swag.assert(compilerAstImplicitStringTotal == 17)
}
