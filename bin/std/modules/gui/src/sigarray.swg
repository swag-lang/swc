#global public

using Core

private struct(First: u64, Count: u64) SignalArgumentSource
{
    #static if Count == 0
    {
        const Text = ""
    }
    else if Count == 1
    {
        const Text = #stringof("assume cast(#decltype(cast(typeinfo, #typeof(fn).parameters![", First,
                               "].pointedType)), params[", First, "])")
    }
    else
    {
        const Half = Count / 2
        const Text = #stringof(SignalArgumentSource!{First, Half}.Text, ", ",
                               SignalArgumentSource!{First + Half, Count - Half}.Text)
    }
}

// Ordered collection of callbacks that can be suspended as a nested scope.
//
// A callback connected through `owner.signal` receives `owner` with its own type, so a handler
// of a derived widget reads its fields without a cast. The owner emits with itself as the
// first argument.
#[Swag.Signal]
struct(T) SigArray
{
    callbacks:    Array!{T}     // Registered callbacks in invocation order.
    suspendDepth: u32           // Number of unmatched `disable` calls.
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
        Swag.assert(.suspendDepth > 0, "signal is not disabled")
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
        Swag.drop(me, 1)
        Swag.init(me, 1)
    }

    // Invokes all registered callbacks in registration order unless disabled.
    mtd call(params: ...)
    {
        if .suspendDepth
        {
            return
        }

        // The arguments are forwarded by position, so their count must match the signature.
        const SignatureParameters = #typeof(#type T).parameters
        const ParameterCount      = SignatureParameters ? SignatureParameters!.count : 0
        Swag.assert(params.count == ParameterCount)

        for fn in .callbacks
        {
            #ast("fn(", SignalArgumentSource!{0, ParameterCount}.Text, ")")
        }
    }
}
