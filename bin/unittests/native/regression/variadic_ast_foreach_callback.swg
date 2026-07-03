#global private

struct RegressionAstString
{
    buffer: [*] u8
    length: u64
}

impl RegressionAstString
{
    #[Implicit]
    mtd const opCast()->string
    {
        return @mkstring(.buffer, .length)
    }
}

struct RegressionAstBuilder
{
    buffer: [64] u8
    length: u64
}

impl RegressionAstBuilder
{
    mtd append(value: string)
    {
        @memcpy(&.buffer[.length], @dataof(value), cast(u64) @countof(value))
        .length += cast(u64) @countof(value)
    }

    mtd const toString()->RegressionAstString
    {
        return {cast([*] u8) &.buffer[0], .length}
    }
}

struct(T) RegressionArray
{
    values: [2] T
    count:  u64
}

impl RegressionArray
{
    mtd add(value: T)
    {
        .values[.count] = value
        .count += 1
    }

    #[Macro]
    func(ptr: bool, back: bool) opVisit(const me, stmt: #code void)
    {
        discard back

        if !.count do
            return

        var scan = cast([*] T) &.values[0] - 1
        for .count
        {
            scan += 1

            #macro
            {
                #if #up ptr do
                    let #alias0 = #up scan
                #else do
                    let #alias0 = #up scan[0]
                let #alias1 = @index
                #inject(#up stmt)
            }
        }
    }
}

struct(T) RegressionSignal
{
    arr: RegressionArray'T
}

impl RegressionSignal
{
    mtd(op: string) opAssign(fn: T)
    {
        #assert(op == "+=")
        .arr.add(fn)
    }

    mtd call(params: ...)
    {
        foreach fn in .arr
        {
            #ast
            {
                var sb: RegressionAstBuilder
                let ts = #typeof(T)
                sb.append("fn(cast(")
                sb.append(ts.parameters[0].pointedType.fullname)
                sb.append(") params[0])\n")
                return sb.toString()
            }
        }
    }
}

var callbackTotal: s32

func addOne(value: *s32)
{
    discard value
    callbackTotal += 1
}

#test
{
    var signal: RegressionSignal'func||(*s32)
    signal += &addOne
    signal += func(value: *s32) { discard value; callbackTotal += 10 }

    var value = 123
    callbackTotal = 0
    signal.call(&value)

    @assert(callbackTotal == 11)
}
