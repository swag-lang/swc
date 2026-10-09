#global private

// Code deferred to scope exit runs while that scope is already being left: it cannot return, raise
// or propagate an error, nor break or continue a loop outside the deferred body. A loop of its own,
// a lambda's own 'return', a 'catch' opened inside the body, and a 'try' in a '#nofail' body (which
// runs once the scope has succeeded) remain allowed.

struct DeferFlowError
{
    using base: Swag.BaseError
}

func deferMayFail() fail {}

func deferReturn()->s32
{
    defer return 1     // swc-expected-error {{sema_err_control_flow_leaves_defer}}
    return 0
}

func deferBreak()
{
    for 3
    {
        defer break     // swc-expected-error {{sema_err_control_flow_leaves_defer}}
    }
}

func deferContinue()
{
    for 3
    {
        defer { continue }     // swc-expected-error {{sema_err_control_flow_leaves_defer}}
    }
}

func deferFail() fail
{
    defer fail DeferFlowError{}     // swc-expected-error {{sema_err_control_flow_leaves_defer}}
}

func deferTry() fail
{
    defer try deferMayFail()     // swc-expected-error {{sema_err_control_flow_leaves_defer}}
}

func deferHandlerReturn()
{
    defer catch deferMayFail() else
    {
        return     // swc-expected-error {{sema_err_control_flow_leaves_defer}}
    }
}

func deferInnerLoop()->s32
{
    var count = 0
    defer
    {
        for 3
        {
            if count > 1 do break
            count += 1
        }
    }

    return count
}

func deferLambda()->s32
{
    var result = 0
    defer
    {
        let compute = func()->s32 { return 2 }
        result = compute()
    }

    return result
}

func deferLocalCatch()
{
    defer
    {
        catch
        {
            try deferMayFail()
        }
    }
}

func deferNoFailTry() fail
{
    defer #nofail try deferMayFail()
}
