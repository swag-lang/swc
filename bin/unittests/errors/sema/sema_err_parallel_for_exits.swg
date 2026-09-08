#global private

// A 'parallel for' partition runs every index it was handed. Leaving the body early would skip
// the rest of that partition while the other partitions keep going, so both exits are rejected.
#test
{
    var total = 0'u64

    parallel for |&total| index in 10
    {
        if index == 5 do
            break     // swc-expected-error {{sema_err_break_leaves_parallel_for}}
        total += index
    }
}

func earlyReturn()->u64
{
    var total = 0'u64

    parallel for |&total| index in 10
    {
        if index == 5 do
            return 0     // swc-expected-error {{sema_err_return_leaves_parallel_for}}
        total += index
    }

    return total
}

// A loop written inside the body owns its own 'break'.
#test
{
    var total = 0'u64

    parallel for |&total| index in 4
    {
        for inner in 10
        {
            if inner == 2 do
                break
            total += 1
        }
    }

    Swag.assert(total == 8)
}
