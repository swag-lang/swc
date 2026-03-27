#global fileprivate

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
        count = -1 // should not be reached
    }
    @assert(count == 3)
}

// Continue in scope loop
#test
{
    var sum = 0
    #scope(Loop)
    {
        sum += 1
        if sum < 10 do
            continue
    }
    @assert(sum == 10)
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
            trace = 4 // unreachable
        }
        trace = 5 // unreachable
    }
    @assert(trace == 3)
}

// Multiple independent scopes in sequence
#test
{
    var a = 0
    #scope(First)
    {
        a = 1
        break
    }

    var b = 0
    #scope(Second)
    {
        b = 2
        break
    }

    @assert(a == 1)
    @assert(b == 2)
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
            i += 1
            count += 1
            if i == 5 do
                break to Outer
        }
        count = -1 // unreachable
    }
    @assert(count == 5)
}

// Scope continue counting up
#test
{
    var i = 0
    var sum = 0
    #scope(Loop)
    {
        i += 1
        sum += i
        if i < 5 do
            continue
    }
    @assert(sum == 15) // 1+2+3+4+5
    @assert(i == 5)
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
            break to S // breaks inner S
        }
        outerExited = true
        break to S // breaks outer S
    }

    @assert(innerExited == true)
    @assert(outerExited == true)
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
    @assert(total == 15)
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
        hit = 3 // unreachable if case 2
    }
    @assert(hit == 1)
}
