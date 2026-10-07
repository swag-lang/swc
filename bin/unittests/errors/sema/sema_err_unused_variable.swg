#global private

func value()->s32 => 1

// A local nothing names is an error.
func unusedLocal()
{
    let a = value()     // swc-expected-error {{sema_err_unused_variable}}
    var b: s32          // swc-expected-error {{sema_err_unused_variable}}
}

// A counting loop that never reads its index names none.
func unusedIndex()->s32
{
    var total = 0
    for i in 3     // swc-expected-error {{sema_err_unused_variable}}
    {
        total += 1
    }

    for 3 do
        total += 1
    return total
}

// 'discard' is a use: it keeps a name the body otherwise leaves alone.
func discardedLocal()
{
    let a = value()
    discard a
}

// A local whose type has a drop is a guard: its lifetime is its use.
struct Guard
{
    count: *s32
}

impl Guard
{
    mtd opDrop()
    {
        .count[] += 1
    }
}

func guardLocal(count: *s32)
{
    let guard = Guard{count}
}

#test
{
    discard unusedIndex()
    discardedLocal()
    var drops = 0
    guardLocal(&drops)
    Swag.assert(drops == 1)
}
