#global private

struct Sx
{
    x: u64
}

impl Sx
{
    mtd const opEquals(other: #null string)->bool
    {
        return other != null and .x == @countof(other!)
    }

    mtd const opCast()->string => "ab"
}

#test
{
    var a: Sx
    var b: Sx
    a.x = 2
    b.x = 9

    // The receiver binds by address for the string overload; equality between two values
    // of the struct itself stays the built-in memberwise comparison.
    @assert(a == "xy")
    @assert(!(a == b))
    b.x = 2
    @assert(a == b)
}
