#global fileprivate
#global skip

#[Swag.Inline]
func addOne(value: s32)->s32
{
    return value + 1
}

#[Swag.Inline]
func double(value: s32)->s32
{
    return value * 2
}

#test
{
    var s = 10
    @assert(double(addOne(5)) == 12)
    @assert(double(addOne(s)) == 22)
}
