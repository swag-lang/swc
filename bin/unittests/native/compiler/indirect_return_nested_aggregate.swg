struct DefaultedNestedValue
{
    a: u64 = 10
    b: u64 = 20
    c: u64 = 30
    d: u64 = 40
}

struct NestedReturnValue
{
    a: u64
    b: u64
    c: u64
    d: u64
}

struct NestedReturnContainer
{
    defaulted: DefaultedNestedValue
    nested:    NestedReturnValue
}

struct NestedReturnFactory
{
    seed: u64
}

private func makeNestedReturnValue(seed: u64)->NestedReturnValue
{
    var result: retval
    result.a = seed
    result.b = 2
    result.c = 3
    result.d = 4
    return result
}

private impl NestedReturnFactory
{
    mtd const make()->NestedReturnValue => makeNestedReturnValue(.seed)
}

private var nestedReturnFactory = NestedReturnFactory{1}

#test
{
    let result = NestedReturnContainer{
        defaulted: {},
        nested: nestedReturnFactory.make()
        }

    @assert(result.defaulted.a == 10)
    @assert(result.defaulted.b == 20)
    @assert(result.defaulted.c == 30)
    @assert(result.defaulted.d == 40)
    @assert(result.nested.a == 1)
    @assert(result.nested.b == 2)
    @assert(result.nested.c == 3)
    @assert(result.nested.d == 4)
}
