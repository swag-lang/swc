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
        return Swag.makeString(.buffer, .length)
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
        Swag.memcpy(&.buffer[.length], value.buffer, cast(u64) value.count)
        .length += cast(u64) value.count
    }

    mtd const toString()->RegressionAstString
    {
        return {cast([*] u8) &.buffer[0], .length}
    }
}

struct(T) RegressionArray
{
    values: [2] T = undefined
    count:  u64
}

impl RegressionArray
{
    mtd add(value: T)
    {
        .values[.count] = value
        .count          += 1
    }

    #[Macro]
    func(ptr: bool) opVisit(const me, stmt: #code(item, index: u64))
    {

        if !.count do
            return

        var scan = cast([*] T) &.values[0] - 1
        for idx in .count
        {
            scan += 1

            #static if ptr do
                #inject(stmt, item = scan, index = idx)
            else do
                #inject(stmt, item = scan[0], index = idx)
        }
    }
}

struct(T) RegressionSignal
{
    arr: RegressionArray'T
}

impl RegressionSignal
{
    mtd(op: Swag.Operator) opAssign(fn: T)
    {
        #assert(op == .AddAssign)
        .arr.add(fn)
    }

    mtd call(params: ...)
    {
        for fn in .arr
        {
            #ast
            {
                var sb: RegressionAstBuilder
                let ts = #typeof(T)
                sb.append("fn(cast(")
                sb.append(ts.parameters[0].pointedType.fullname!)
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

    Swag.assert(callbackTotal == 11)
}
