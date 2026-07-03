#global private

#test
{
    var a = InlineRegressionBug13.Vector3{1, 2, 3}
    var b: InlineRegressionBug13.Vector3

    InlineRegressionBug13.assign(&b, moveref &a)

    @assert(b.x == 3 and b.y == 4 and b.z == 5)
    @assert(a.x == 666 and a.y == 666 and a.z == 666)
}
