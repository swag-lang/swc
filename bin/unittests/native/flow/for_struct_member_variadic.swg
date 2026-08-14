#global private

// A string MEMBER reached through a const-pointer loop binding, passed to an
// untyped variadic: the box must carry the member's address as its data, not
// the member's first field bits. Mirrors the IsSet #ast generator in core's
// commandline.swg (`for f in typeof.fields ... appendFormat("%", f.name)`).
struct Tagged
{
    name: string
    kind: u64
}

func firstByteOfArg(args: ...)->u8
{
    let arg  = args[0]
    let data = cast(const [*] u8) @dataof(arg)
    let str  = dref cast(const *string) data!
    return @countof(str) ? str[0] : 0
}

func argCount(args: ...)->u64
{
    let arg  = args[0]
    let data = cast(const [*] u8) @dataof(arg)
    let str  = dref cast(const *string) data!
    return @countof(str)
}

#test
{
    // Direct member.
    var items: [2] Tagged = [{name: "alpha", kind: 1}, {name: "beta", kind: 2}]
    @assert(argCount(items[0].name) == 5)
}

#test
{
    // Member through an explicit pointer.
    var items: [2] Tagged = [{name: "alpha", kind: 1}, {name: "beta", kind: 2}]
    let p                 = &items[1]
    @assert(argCount(p.name) == 4)
}

#test
{
    // Member through the loop binding.
    var items:  [2] Tagged = [{name: "alpha", kind: 1}, {name: "beta", kind: 2}]
    var total:  u64
    var firsts: u64
    for it in items
    {
        total  += argCount(it.name)
        firsts += firstByteOfArg(it.name)
    }

    @assert(total == 9)
    @assert(firsts == 'a'u8 + 'b'u8)
}
