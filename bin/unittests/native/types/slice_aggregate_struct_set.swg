#global private

// An array literal passed as a slice of a struct that converts through its set
// operator. When every element is a literal the aggregate is folded to a constant,
// yet no element has a constant form of the destination type: the literal must lower
// as a runtime value built element by element through 'opSet'. Before the fix the
// all-literal shapes died in code generation ('cannot materialize an aggregate
// constant payload', or an assertion in constant lowering), while one runtime element
// in the same literal made everything work.

struct Wrapped
{
    length: u64
    ptr:    const *u8?
}

impl Wrapped
{
    #[Swag.Implicit]
    mtd opSet(value: string)
    {
        .length = value.count
        .ptr    = value.buffer
    }
}

func totalLength(values: const [..] Wrapped)->u64
{
    var total: u64
    for v in values do
        total += v.length
    return total
}

// Answers what a wrong total should write, which is nothing at all when the total is right.
// The comparison is ordinary code rather than an assertion alone, so the call still runs in a
// configuration that drops assertions.
func totalLengthReport(values: const [..] Wrapped, expected: u64)->string
{
    let total = totalLength(values)
    Swag.assert(total == expected)
    return total == expected ? "" : "unexpected total length\n"
}

// All-literal aggregate as a call argument.
#test
{
    Swag.assert(totalLength(["ab", "cde"]) == 5)
}

// A single literal element.
#test
{
    Swag.assert(totalLength(["--publish"]) == 9)
}

// The same call as an argument of another call: the aggregate must not be treated as
// a constant-call argument. 'Swag.print' stays the outer call because an intrinsic is what keeps
// the inner one at run time, and what it writes is empty unless the total is wrong, so a
// passing suite says nothing.
#test
{
    Swag.print(totalLengthReport(["ab", "c"], 3), "")
}

// All-literal aggregate initializing a slice binding.
#test
{
    let values: const [..] Wrapped = ["a", "bc", "def"]
    Swag.assert(totalLength(values) == 6)
}

// One runtime element mixed with literals: the shape that already worked.
#test
{
    var runtime: Wrapped
    runtime = "wxyz"
    Swag.assert(totalLength(["ab", runtime]) == 6)
}

// Elements built through 'opSet' point at real payloads, not at stale constants.
#test
{
    func firstByte(values: const [..] Wrapped)->u8
    {
        Swag.assert(values.count == 2)
        Swag.assert(values[1].length == 1)
        return values[0].ptr![]
    }

    Swag.assert(firstByte(["qr", "s"]) == 'q')
}
