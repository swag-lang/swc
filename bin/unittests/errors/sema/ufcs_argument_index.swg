#global private

// A method call counts and numbers its arguments from the first one written between the
// parentheses: the receiver before the dot is not one of them.

struct Counter
{
    total: u32
}

impl Counter
{
    mtd add(amount: u32)
    {
        .total += amount
    }

    mtd addPair(first: u32, second: u32)
    {
        .total += first + second
    }
}

func scale(counter: *Counter, factor: u32) {}

#test
{
    var counter: Counter
    var wide     = 1'u64
    counter.add(wide)                // swc-expected-error {{argument 1 for call to 'add' has type 'u64', but parameter 'amount' needs 'u32'}}
}

#test
{
    var counter: Counter
    var wide     = 1'u64
    counter.addPair(1, wide)         // swc-expected-error {{argument 2 for call to 'addPair' has type 'u64', but parameter 'second' needs 'u32'}}
}

#test
{
    var counter: Counter
    var wide     = 1'u64
    counter.scale(wide)              // swc-expected-error {{argument 1 for call to 'scale' has type 'u64', but parameter 'factor' needs 'u32'}}
}

#test
{
    var counter: Counter
    var wide     = 1'u64
    scale(&counter, wide)            // swc-expected-error {{argument 2 for call to 'scale' has type 'u64', but parameter 'factor' needs 'u32'}}
}

#test
{
    var counter: Counter
    counter.add(1, 2)                // swc-expected-error {{call to 'add' accepts 1 arguments, found 2}}
}

#test
{
    var counter: Counter
    counter.addPair(1)               // swc-expected-error {{needs 2 arguments, found 1}}
}
