#global private

struct AstGeneratedString
{
    buffer: #null [*] u8
    length: u64
}

impl AstGeneratedString
{
    #[Implicit]
    mtd const opCast()->string
    {
        return @mkstring(.buffer, .length)
    }
}

struct AstGeneratedBuilder
{
    buffer:   #null [*] u8
    length:   u64
    capacity: u64
}

impl AstGeneratedBuilder
{
    mtd opDrop()
    {
        if !.buffer do
            return

        for [i] in .length do
            .buffer[i] = 0
        @free(.buffer)
    }

    mtd append(value: string)
    {
        if !.buffer
        {
            .capacity = 128
            .buffer   = cast(#null [*] u8) @alloc(.capacity)
        }

        @assert(.length + cast(u64) @countof(value) <= .capacity)
        @memcpy(.buffer + .length, @dataof(value), cast(u64) @countof(value))
        .length += cast(u64) @countof(value)
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

    @assert(compilerAstImplicitStringTotal == 17)
}
