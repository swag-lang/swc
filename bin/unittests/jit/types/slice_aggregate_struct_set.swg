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
    ptr:    #null const *u8
}

impl Wrapped
{
    #[Swag.Implicit]
    mtd opSet(value: string)
    {
        .length = @countof(value)
        .ptr    = @dataof(value)
    }
}

func totalLength(values: const [..] Wrapped)->u64
{
    var total: u64
    for v in values do
        total += v.length
    return total
}

// All-literal aggregate as a call argument.
#test
{
    @assert(totalLength(["ab", "cde"]) == 5)
}

// A single literal element.
#test
{
    @assert(totalLength(["--publish"]) == 9)
}

// The same call as an argument of another call: the aggregate must not be treated as
// a constant-call argument.
#test
{
    @print(totalLength(["ab", "c"]), "")
}

// All-literal aggregate initializing a slice binding.
#test
{
    let values: const [..] Wrapped = ["a", "bc", "def"]
    @assert(totalLength(values) == 6)
}

// One runtime element mixed with literals: the shape that already worked.
#test
{
    var runtime: Wrapped
    runtime = "wxyz"
    @assert(totalLength(["ab", runtime]) == 6)
}

// Elements built through 'opSet' point at real payloads, not at stale constants.
#test
{
    func firstByte(values: const [..] Wrapped)->u8
    {
        @assert(@countof(values) == 2)
        @assert(values[1].length == 1)
        return dref values[0].ptr!
    }

    @assert(firstByte(["qr", "s"]) == 'q')
}
