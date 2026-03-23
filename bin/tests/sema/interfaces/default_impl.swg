#global fileprivate

struct Point2 {}
struct Point3 {}

interface ITest
{
    mtd isImplemented()->bool
    {
        return false
    }
}

impl ITest for Point2
{
    mtd impl isImplemented()->bool
    {
        return true
    }
}

impl ITest for Point3
{
}

#test
{
    var v2: Point2
    var v3: Point3

    let i2 = cast(ITest) v2
    @assert(i2.isImplemented())

    let i3 = cast(ITest) v3
    @assert(!i3.isImplemented())
}
