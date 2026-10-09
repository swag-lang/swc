#global private

// Code deferred to scope exit runs while that scope is already being left: it cannot return, nor
// break or continue a loop outside the deferred body. A loop of its own, a lambda's own 'return',
// and a deferred 'fail' (which has its own meaning) remain allowed.

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
