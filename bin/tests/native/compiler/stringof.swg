#global fileprivate // 

const GlobalZero = 0

enum Mode
{
    A = 1,
    B = 2,
}

const Folded = 2 + 3
const Negative = -10

#assert(#stringof(GlobalZero) == "0")
#assert(#stringof(cast(u32) Mode.A) == "1")
#assert(#stringof(5 * 5) == "25")
#assert(#stringof(1 + 2 * 3) == "7")
#assert(#stringof("foo" ++ "bar") == "foobar")
#assert(#stringof(bool) == "bool")
#assert(#stringof(Folded) == "5")
#assert(#stringof(Negative) == "-10")
#assert(#stringof(true) == "true")
#assert(#stringof(false) == "false")

#test
{
    const folded = #stringof(Folded)
    var localValue: s32 = 42

    @assert(folded == "5")
    @assert(#stringof(GlobalZero + 6) == "6")
    @assert(#stringof(localValue) == "localValue")
}
