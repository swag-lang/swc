#global fileprivate // swc-option suite-test

enum A { R, G, B }

struct Holder
{
    value: A
}

func pickA(flag: bool)->A
{
    if flag
    {
        return .R
    }

    return .B
}

func isGreen(value: A)->bool
{
    return value == .G
}

#test
{
    let value: A = .G
    let holder: Holder = {value: A.B}
    // @BUG native cannot compute auto scope in typed array literals yet: let values: [3] A = [.R, .G, .B]
    let values: [3] A = [A.R, A.G, A.B]

    @assert(value == A.G)
    @assert(isGreen(value))
    @assert(holder.value == A.B)
    @assert(values[0] == .R)
    @assert(values[1] == .G)
    @assert(values[2] == .B)
    @assert(pickA(true) == .R)
    @assert(pickA(false) == .B)
}

#test
{
    var value: A = .R
    var total: s32 = 0

    if value == .R
    {
        total += 1
        value = .G
    }

    if value != .B
    {
        total += 10
    }

    value = .B
    if value == .B
    {
        total += 100
    }

    @assert(total == 111)
    @assert(value == .B)
}

