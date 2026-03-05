#global fileprivate
struct Vec2
{
    x: s32
    y: s32
}

#run
{
    func testRead(x: &Vec2)->s32 { return x.x + x.y; }
    var v: Vec2 = {x: 8, y: 13}
    var sum = testRead(&v)
    @assert(sum == 21)
}

#run
{
    func testWrite(x: &Vec2)
    {
        x.x = x.x * 2
        x.y = x.y + 7
    }
    var v: Vec2 = {x: 9, y: 4}
    testWrite(&v)
    @assert(v.x == 18)
    @assert(v.y == 11)
}

#run
{
    func getPtr(x: &s32)->*s32 { return &x; }
    func writeThrough(p: *s32)
    {
        dref p = 42
    }
    var v: s32 = 10
    var p = getPtr(&v)
    @assert(dref p == 10)
    writeThrough(p)
    @assert(v == 42)
}

/*
#run
{
    func getPtr(x: &Vec2)->*Vec2 { return &x; }
    func writeThrough(p: *Vec2)
    {
        p.x = -3
        p.y = 99
    }
    var v: Vec2 = {x: 1, y: 2}
    var p = getPtr(&v)
    writeThrough(p)
    @assert(v.x == -3)
    @assert(v.y == 99)
}*/

//#run
//{
//    func choose(flag: bool, a: &Vec2, b: &Vec2)->*Vec2
//    {
//        if flag
//            return &a
//        return &b
//    }
//    var left: Vec2 = {x: 100, y: 200}
//    var right: Vec2 = {x: 300, y: 400}
//    var p0 = choose(true, &left, &right)
//    var p1 = choose(false, &left, &right)
//    @assert(p0.x == 100)
//    @assert(p0.y == 200)
//    @assert(p1.x == 300)
//    @assert(p1.y == 400)
//}
