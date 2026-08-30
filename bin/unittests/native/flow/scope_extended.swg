#global private

// Break to scope from deeply nested loop
#test
{
    var count = 0
    #scope(Outer)
    {
        for 5
        {
            for 5
            {
                count += 1
                if count == 3 do
                    break to Outer
            }
        }
        count = -1     // should not be reached
    }
    Swag.assert(count == 3)
}

// A scope inside a loop leaves 'continue' pointing at the loop
#test
{
    var sum  = 0
    var tail = 0
    for 10
    {
        #scope(Grouped)
        {
            sum += 1
            continue
        }

        tail += 1     // Not reached: 'continue' restarted the 'for'
    }
    Swag.assert(sum == 10)
    Swag.assert(tail == 0)
}

// Break to scope skipping intermediate code
#test
{
    var trace = 0
    #scope(A)
    {
        trace = 1
        {
            trace = 2
            {
                trace = 3
                break to A
            }
            trace = 4     // unreachable
        }
        trace = 5     // unreachable
    }
    Swag.assert(trace == 3)
}

// Multiple independent scopes in sequence
#test
{
    var a = 0
    #scope(First)
    {
        a = 1
        break to First
    }

    var b = 0
    #scope(Second)
    {
        b = 2
        break to Second
    }

    Swag.assert(a == 1)
    Swag.assert(b == 2)
}

// Scope with while loop inside
#test
{
    var count = 0
    #scope(Outer)
    {
        var i = 0
        while i < 100
        {
            i     += 1
            count += 1
            if i == 5 do
                break to Outer
        }
        count = -1     // unreachable
    }
    Swag.assert(count == 5)
}

// 'break to' reaches an outer scope from inside a nested scope and a loop
#test
{
    var i    = 0
    var sum  = 0
    var tail = 0
    #scope(Done)
    {
        var guard = 0
        while guard < 100
        {
            guard += 1
            #scope(Step)
            {
                i   += 1
                sum += i
                if i == 5 do
                    break to Done
            }
        }

        tail += 1     // Not reached: 'break to Done' left the whole scope
    }
    Swag.assert(sum == 15)     // 1+2+3+4+5
    Swag.assert(i == 5)
    Swag.assert(tail == 0)
}

// Nested scopes with same name - inner takes precedence
#test
{
    var outerExited = false
    var innerExited = false

    #scope(S)
    {
        #scope(S)
        {
            innerExited = true
            break to S     // breaks inner S
        }
        outerExited = true
        break to S     // breaks outer S
    }

    Swag.assert(innerExited == true)
    Swag.assert(outerExited == true)
}

// Scope with for loop break to outer
#test
{
    var total = 0
    #scope(Done)
    {
        for i in 10
        {
            for j in 10
            {
                total += 1
                if total == 15 do
                    break to Done
            }
        }
    }
    Swag.assert(total == 15)
}

// Scope break from switch
#test
{
    var hit = 0
    #scope(Out)
    {
        var v = 2
        switch v
        {
        case 2:
            hit = 1
            break to Out
        default:
            hit = 2
            break
        }
        hit = 3     // unreachable if case 2
    }
    Swag.assert(hit == 1)
}

// A bare break leaving through a scope still runs the defers the scope registered
#test
{
    var trace = 0
    for 10
    {
        #scope(Grouped)
        {
            defer trace += 1
            break
        }
    }
    Swag.assert(trace == 1)
}

// Two nested scopes unwind in order on the way to the loop
#test
{
    var trace = 0
    for 10
    {
        #scope(A)
        {
            defer trace += 1
            #scope(B)
            {
                defer trace += 10
                break
            }
        }
    }
    Swag.assert(trace == 11)
}

// 'continue' runs the scope defers on every iteration
#test
{
    var trace = 0
    for 3
    {
        #scope(Grouped)
        {
            defer trace += 1
            continue
        }
    }
    Swag.assert(trace == 3)
}

// A bare break inside a scope inside a switch case leaves the case
#test
{
    var trace = 0
    var value = 2

    switch value
    {
    case 2:
        #scope(Grouped)
        {
            defer trace += 10
            break
        }
        trace += 100     // Not reached: 'break' left the case
    }

    Swag.assert(trace == 10)
}
