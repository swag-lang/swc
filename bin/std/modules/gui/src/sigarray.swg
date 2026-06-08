#global public
using Core

struct(T) SigArrayEntry
{
    fn:     T
}

struct(T) SigArray
{
    arr:          Array'SigArrayEntry'T
    disabled:     s32
}

impl SigArray
{
    mtd(op: string) opAssign(fn: T)
    {
        #assert(op == "+=")
        .arr.add({fn})
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
    mtd call()
    {
        if .disabled do
            return

        Debug.assert(@countof(#typeof(T).parameters) == 0)
        for i in .arr.count
        {
            .arr[i].fn()
        }
    }

    // Call all registered lambdas.
    mtd(P0) call(p0: P0)
    {
        if .disabled do
            return

        Debug.assert(@countof(#typeof(T).parameters) == 1)
        for i in .arr.count
        {
            .arr[i].fn(p0)
        }
    }

    // Call all registered lambdas.
    mtd(P0, P1) call(p0: P0, p1: P1)
    {
        if .disabled do
            return

        Debug.assert(@countof(#typeof(T).parameters) == 2)
        for i in .arr.count
        {
            .arr[i].fn(p0, p1)
        }
    }

    // Call all registered lambdas.
    mtd(P0, P1, P2) call(p0: P0, p1: P1, p2: P2)
    {
        if .disabled do
            return

        Debug.assert(@countof(#typeof(T).parameters) == 3)
        for i in .arr.count
        {
            .arr[i].fn(p0, p1, p2)
        }
    }
}
