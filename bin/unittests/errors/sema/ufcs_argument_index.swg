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
    var wide = 1'u64
    counter.add(wide)     // swc-expected-error {{argument 1 for call to 'add' has type 'u64', but parameter 'amount' needs 'u32'}}
}

#test
{
    var counter: Counter
    var wide = 1'u64
    counter.addPair(1, wide)     // swc-expected-error {{argument 2 for call to 'addPair' has type 'u64', but parameter 'second' needs 'u32'}}
}

#test
{
    var counter: Counter
    var wide = 1'u64
    counter.scale(wide)     // swc-expected-error {{argument 1 for call to 'scale' has type 'u64', but parameter 'factor' needs 'u32'}}
}

#test
{
    var counter: Counter
    var wide = 1'u64
    scale(&counter, wide)     // swc-expected-error {{argument 2 for call to 'scale' has type 'u64', but parameter 'factor' needs 'u32'}}
}

#test
{
    var counter: Counter
    counter.add(1, 2)     // swc-expected-error {{call to 'add' accepts 1 argument, found 2}}
}

#test
{
    var counter: Counter
    counter.addPair(1)     // swc-expected-error {{needs 2 arguments, found 1}}
}

// Detailed cast failures and plain type failures use the same written argument index.
struct CandidateArgumentCounter {}

impl CandidateArgumentCounter
{
    mtd take(values: [..] u32) {}
    mtd take(values: *u32) {}
    mtd takeAfter(first: u32, values: [..] u32) {}
    mtd takeAfter(first: u32, values: *u32) {}
    mtd change() {}
    mtd change(value: u32 = 0) {}
}

#test
{
    var counter: CandidateArgumentCounter
    // swc-expected-note@+2 {{parameter 'values' cannot accept argument 1: cannot cast}}
    // swc-expected-note@+1 {{but argument 1 has type 'array literal'}}
    counter.take([1'u32, 2])     // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    var counter: CandidateArgumentCounter
    // swc-expected-note@+1 {{parameter 'values' cannot accept argument 2: cannot cast}}
    counter.takeAfter(7, [1'u32, 2])     // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    var counter: CandidateArgumentCounter
    // Named arguments are numbered by their written order, not their parameter position.
    // swc-expected-note@+1 {{parameter 'values' cannot accept argument 1: cannot cast}}
    counter.takeAfter(values: [1'u32, 2], first: 7)     // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    var counter: CandidateArgumentCounter
    // The explicit receiver in a qualified call is an ordinary written argument.
    // swc-expected-note@+1 {{parameter 'values' cannot accept argument 2: cannot cast}}
    CandidateArgumentCounter.take(&counter, [1'u32, 2])     // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    const counter = CandidateArgumentCounter{}
    // There are no written arguments: the rejected receiver has no argument number.
    // swc-expected-note@+1 {{cannot accept the receiver: cannot cast}}
    counter.change()     // swc-expected-error {{sema_err_no_overload_match}}
}

func candidateNumberReceiver(receiver: *u32) {}
func candidateNumberReceiver(receiver: *f32) {}

#test
{
    var counter: CandidateArgumentCounter
    // A plain receiver type failure also avoids the numbered-argument note variant.
    // swc-expected-note@+1 {{parameter 'receiver' cannot accept the receiver: cannot cast}}
    counter.candidateNumberReceiver()     // swc-expected-error {{sema_err_no_overload_match}}
}
