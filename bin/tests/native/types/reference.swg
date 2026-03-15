// swc-option suite-test

#global fileprivate
struct Vec2
{
    x: s32
    y: s32
}

#test
{
    func testRead(x: &Vec2)->s32 { return x.x + x.y; }
    var v: Vec2 = {x: 8, y: 13}
    var sum = testRead(&v)
    @assert(sum == 21)
}

#test
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

#test
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

#test
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
}

#test
{
    func choose(flag: bool, a: &Vec2, b: &Vec2)->*Vec2
    {
        if flag do
            return &a
        return &b
    }
    var left: Vec2 = {x: 100, y: 200}
    var right: Vec2 = {x: 300, y: 400}
    var p0 = choose(true, &left, &right)
    var p1 = choose(false, &left, &right)
    @assert(p0.x == 100)
    @assert(p0.y == 200)
    @assert(p1.x == 300)
    @assert(p1.y == 400)
}

struct A {}
var gRefTitiCalls: s32
var gRefTataCalls: s32
func titi(a: &A) { gRefTitiCalls += 1 }
#test
{
    var a: A
    gRefTitiCalls = 0
    titi(&a)
    @assert(gRefTitiCalls == 1)
}

func tata(a: const &A) { gRefTataCalls += 1 }
#test
{
    var a: A
    gRefTataCalls = 0
    tata(a)
    @assert(gRefTataCalls == 1)
}



