#global fileprivate

#[Swag.Safety(.BoundCheck, false)]
func boundCheckDisabled()->bool
{
    return #safety(Swag.SafetyWhat.BoundCheck)
}

#[Swag.Safety(.BoundCheck, true)]
func boundCheckEnabled()->bool
{
    return #safety(Swag.SafetyWhat.BoundCheck)
}

#test
{
    const cfg      = #run dref @compiler.getBuildCfg()
    const expected = cfg.safetyGuards & Swag.SafetyWhat.BoundCheck ? true : false
    #assert(#safety(Swag.SafetyWhat.BoundCheck) == expected)
}

#test
{
    const value = #run boundCheckDisabled()
    #assert(value == false)
}

#test
{
    const value = #run boundCheckEnabled()
    #assert(value == true)
}

#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func arrayBoundCheck()->s32
    {
        var values: [2] s32
        values[0] = 1
        values[1] = 2
        return values[2] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run arrayBoundCheck()
    @assert(value == 0)
}

#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func sliceBoundCheck()->s32
    {
        var values: [2] s32
        values[0] = 1
        values[1] = 2
        var slice: [..] s32 = values
        return slice[2] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run sliceBoundCheck()
    @assert(value == 0)
}

#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func stringBoundCheck()->u8
    {
        var text: string = "ab"
        return text[2] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run stringBoundCheck()
    @assert(value == 0)
}

#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func multiArrayBoundCheck()->s32
    {
        var values: [2, 2] s32
        values[0, 0] = 1
        values[0, 1] = 2
        values[1, 0] = 3
        values[1, 1] = 4
        return values[1, 2] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run multiArrayBoundCheck()
    @assert(value == 0)
}

// Dynamic index: index value known only at runtime
#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func arrayDynamicBoundCheck(idx: u64)->s32
    {
        var values: [2] s32
        values[0] = 10
        values[1] = 20
        return values[idx] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run arrayDynamicBoundCheck(2)
    @assert(value == 0)
}

#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func sliceDynamicBoundCheck(idx: u64)->s32
    {
        var values: [3] s32
        values[0] = 1
        values[1] = 2
        values[2] = 3
        var slice: [..] s32 = values
        return slice[idx] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run sliceDynamicBoundCheck(5)
    @assert(value == 0)
}

#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func stringDynamicBoundCheck(idx: u64)->u8
    {
        var text: string = "hello"
        return text[idx] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run stringDynamicBoundCheck(10)
    @assert(value == 0)
}

#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func multiArrayDynamicBoundCheck(i: u64, j: u64)->s32
    {
        var values: [2, 2] s32
        values[0, 0] = 1
        values[0, 1] = 2
        values[1, 0] = 3
        values[1, 1] = 4
        return values[i, j] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run multiArrayDynamicBoundCheck(2, 0)
    @assert(value == 0)
}

// Empty slice: any index is out of bounds at runtime
#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func emptySliceBoundCheck()->s32
    {
        var slice: [..] s32
        return slice[0] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run emptySliceBoundCheck()
    @assert(value == 0)
}

// In-bound accesses (constant and dynamic) must not panic
#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func arrayInBounds(idx: u64)->s32
    {
        var values: [3] s32
        values[0] = 1
        values[1] = 2
        values[2] = 3
        return values[0] + values[2] + values[idx]
    }

    const value = #run arrayInBounds(1)
    @assert(value == 6)
}

#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func sliceInBounds(idx: u64)->s32
    {
        var values: [3] s32
        values[0] = 7
        values[1] = 8
        values[2] = 9
        var slice: [..] s32 = values
        return slice[idx]
    }

    const value = #run sliceInBounds(2)
    @assert(value == 9)
}

// Variadic argument bound check
#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func variadicBoundCheck(args: s32...)->s32
    {
        return args[3] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run variadicBoundCheck(10, 20, 30)
}

// Exact boundary: index == count is out of bounds
#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func arrayExactBoundary(idx: u64)->s32
    {
        var values: [3] s32
        values[0] = 1
        values[1] = 2
        values[2] = 3
        return values[idx] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run arrayExactBoundary(3)
}

#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func sliceExactBoundary(idx: u64)->s32
    {
        var values: [2] s32
        values[0] = 5
        values[1] = 6
        var slice: [..] s32 = values
        return slice[idx] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run sliceExactBoundary(2)
}

#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func stringExactBoundary(idx: u64)->u8
    {
        var text: string = "abc"
        return text[idx] // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run stringExactBoundary(3)
}

// When bound check is disabled, out-of-bounds access must not call the safety panic
#test
{
    #[Swag.Safety(.BoundCheck, false)]
    func arrayBoundCheckDisabled()->s32
    {
        var values: [2] s32
        values[0] = 1
        values[1] = 2
        var idx: u64 = 1
        return values[idx]
    }

    const value = #run arrayBoundCheckDisabled()
    @assert(value == 2)
}
