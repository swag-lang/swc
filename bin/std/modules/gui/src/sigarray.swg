#global public

using Core

// Represents sig array.
struct(T) SigArray
{
    arr:      Array'T // Arr associated with this value.
    disabled: s32 // Disabled associated with this value.
}

impl SigArray
{
    mtd(op: Swag.Operator) opAssign(fn: T)
    {
        #assert(op == .AddAssign)
        .arr.add(fn)
    }

    // Disable the calls.
    mtd disable()
    {
        .disabled += 1
    }

    // Enable the calls.
    mtd enable()
    {
        Debug.assert(.disabled > 0)
        .disabled -= 1
    }

    // Returns 'true' if the array is empty.
    mtd const isEmpty()->bool => .arr.isEmpty()

    // Call all registered lambdas.
    mtd call(params: ...)
    {
        if .disabled do
            return

        // Be sure the call has the right number of arguments
        Debug.assert(@countof(params) == @countof(#typeof(T).parameters))

        for fn in .arr
        {
            #ast
            {
                var sb: StrConv.StringBuilder
                let ts = #typeof(T)

                sb.appendString("fn(")
                let tsParams = notnull ts.parameters
                for [i] in @countof(ts.parameters)
                {
                    if i do
                        sb.appendString(",")
                    sb.appendFormat("cast(%) params[%]", (notnull tsParams[i].pointedType).fullname, i)
                }

                sb.appendString(")\n")
                return sb.toString()
            }
        }
    }
}
