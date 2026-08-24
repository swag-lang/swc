#global public

using Core

// Ordered collection of callbacks that can be suspended as a nested scope.
struct(T) SigArray
{
    internal
    {
        callbacks:    Array'T     // Registered callbacks in invocation order.
        suspendDepth: u32         // Number of unmatched `disable` calls.
    }
}

impl SigArray
{
    // Registers a callback through the `+=` operator.
    mtd(op: Swag.Operator) opAssign(fn: T)
    {
        #assert(op == .AddAssign)
        .add(fn)
    }

    // Registers a callback at the end of the invocation order.
    mtd add(fn: T)
    {
        .callbacks.add(fn)
    }

    // Suspends callback invocation until every nested disable is matched by `enable`.
    mtd disable()
    {
        .suspendDepth += 1
    }

    // Ends one nested callback suspension.
    mtd enable()
    {
        Debug.assert(.suspendDepth > 0, "signal is not disabled")
        .suspendDepth -= 1
    }

    // Returns the number of registered callbacks.
    mtd const count()->u64 => .callbacks.count

    // Reports whether no callback is registered.
    mtd const isEmpty()->bool => .callbacks.isEmpty()

    // Reports whether callback invocation is currently suspended.
    mtd const isDisabled()->bool => .suspendDepth != 0

    // Removes every callback and restores the enabled state.
    mtd clear()
    {
        @drop(me, 1)
        @init(me, 1)
    }

    // Invokes all registered callbacks in registration order unless disabled.
    mtd call(params: ...)
    {
        if .suspendDepth do
            return

        // Be sure the call has the right number of arguments
        Debug.assert(@countof(params) == @countof(#typeof(T).parameters))

        for fn in .callbacks
        {
            #ast
            {
                var sb: StrConv.StringBuilder
                let ts = #typeof(T)

                sb.appendString("fn(")
                let tsParams = ts.parameters!
                for i in @countof(ts.parameters)
                {
                    if i do
                        sb.appendString(",")
                    sb.appendFormat("cast(%) params[%]", tsParams[i].pointedType!.fullname, i)
                }

                sb.appendString(")\n")
                return sb.toString()
            }
        }
    }
}
