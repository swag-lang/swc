#global fileprivate

struct AmbiguousBinaryLeft
{
    value: s32
}

struct AmbiguousBinaryRight
{
    value: s32
}

impl AmbiguousBinaryLeft
{
    mtd(op: string) const opBinary(other: const &AmbiguousBinaryRight)->AmbiguousBinaryLeft
    {
        return {value: .value + other.value}
    }
}

impl AmbiguousBinaryRight
{
    mtd(op: string) const opBinaryRight(other: const &AmbiguousBinaryLeft)->AmbiguousBinaryRight
    {
        return {value: other.value + .value}
    }
}

#test
{
    var left = AmbiguousBinaryLeft{value: 1}
    var right = AmbiguousBinaryRight{value: 2}
    let result = left + right // swc-expected-error {{sema_err_ambiguous_symbol}}
}
