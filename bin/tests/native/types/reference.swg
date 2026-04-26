// 

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

func writeScalarRef(target: &s32, value: s32)
{
    target = value
}

#test
{
    var value: s32 = 10
    var valueRef: &s32 = &value

    valueRef = 42
    @assert(valueRef == 42)
    @assert(value == 42)

    valueRef += 8
    @assert(valueRef == 50)
    @assert(value == 50)

    writeScalarRef(&value, 99)
    @assert(valueRef == 99)
    @assert(value == 99)
}

#test
{
    var left: s32 = 10
    var right: s32 = 20
    var valueRef: &s32 = &left

    valueRef = #ref &right
    @assert(valueRef == 20)

    valueRef = 77
    @assert(left == 10)
    @assert(right == 77)
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

func writeVecRef(target: &Vec2, value: Vec2)
{
    target = value
}

#test
{
    var value: Vec2 = {x: 1, y: 2}
    var valueRef: &Vec2 = &value
    let other: Vec2 = {x: 30, y: 40}

    valueRef = other
    @assert(valueRef.x == 30)
    @assert(valueRef.y == 40)
    @assert(value.x == 30)
    @assert(value.y == 40)

    writeVecRef(&value, {x: -5, y: 12})
    @assert(valueRef.x == -5)
    @assert(valueRef.y == 12)
    @assert(value.x == -5)
    @assert(value.y == 12)
}

#test
{
    var left: Vec2 = {x: 1, y: 2}
    var right: Vec2 = {x: 10, y: 20}
    var valueRef: &Vec2 = &left

    valueRef = #ref &right
    @assert(valueRef.x == 10)
    @assert(valueRef.y == 20)

    valueRef.x = -7
    valueRef.y = 99
    @assert(left.x == 1)
    @assert(left.y == 2)
    @assert(right.x == -7)
    @assert(right.y == 99)
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

#test
{
    func nextDigit(bytes: const [..] u8, index: &u64)->u8
    {
        if index < @countof(bytes)
        {
            let value = bytes[index]
            index += 1
            return value
        }

        return 0'u8
    }

    let bytes = cast(const [..] u8) "42"
    var index: u64
    @assert(nextDigit(bytes, &index) == '4''u8)
    @assert(nextDigit(bytes, &index) == '2''u8)
    @assert(index == 2'u64)
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

struct ConstAddrValue
{
    x: s32
}

struct ConstAddrHolder
{
    value: ConstAddrValue
}

func readConstAddr(value: const &ConstAddrValue)->s32 { return value.x }

#test
{
    let holder: ConstAddrHolder = {value: {x: 123}}
    var valueRef: const &ConstAddrValue = &holder.value

    @assert(valueRef.x == 123)
    @assert(readConstAddr(&holder.value) == 123)
}

func inspectConstScalar(value: const &s32, expected: s32)
{
    let ptr = &value
    #assert(#typeof(ptr) == const *s32)
    @assert(value == expected)
    @assert(dref ptr == expected)
}

func sumConstAnon(value: const &{ x: s32, y: s32 })->s32
{
    return value.x + value.y
}

struct RefPair
{
    x: s32
    y: s32
}

struct RefFloatBox
{
    value: f32
}

func sumConstPair(value: const &RefPair)->s32 { return value.x + value.y }
func(T) addRefValue(value: &T, rhs: T)->T { return value + rhs }
func(T) dampRefValue(currentVelocity: &T, omega, clampedChange, deltaTime: T)->T
{
    let temp = (currentVelocity + omega * clampedChange) * deltaTime
    return temp
}

func(T) dampRefValueWithLiterals(current, target: T, currentVelocity: &T, smoothTime, deltaTime: T)->T
{
    let omega = 2.0 / smoothTime
    let change = current - target
    let temp = (currentVelocity + omega * change) * deltaTime
    return temp
}

#test
{
    var value: s32 = 41
    inspectConstScalar(value, 41)
    inspectConstScalar(4, 4)
    inspectConstScalar(value + 1, 42)
}

#test
{
    @assert(sumConstAnon({1, 2}) == 3)
    @assert(sumConstPair({x: 3, y: 4}) == 7)
}

#test
{
    var value: f32 = 1.5
    let valueRef: const &f32 = &value
    let copied = cast(f32) valueRef
    let sum = valueRef + 2.5'f32

    #assert(#typeof(copied) == f32)
    #assert(#typeof(sum) == f32)

    @assert(copied == 1.5'f32)
    @assert(sum == 4.0'f32)
}

#test
{
    var value: f32 = 1.5
    let sum = addRefValue(&value, 2.5'f32)

    #assert(#typeof(sum) == f32)
    @assert(sum == 4.0'f32)
}

#test
{
    var value: f32 = 1.5
    let temp = dampRefValue(&value, 2.0'f32, 3.0'f32, 0.5'f32)

    #assert(#typeof(temp) == f32)
    @assert(temp == 3.75'f32)
}

#test
{
    var box: RefFloatBox = {value: 1.5}
    let sum = addRefValue(&box.value, 2.5'f32)
    let temp = dampRefValue(&box.value, 2.0'f32, 3.0'f32, 0.5'f32)

    #assert(#typeof(sum) == f32)
    #assert(#typeof(temp) == f32)
    @assert(sum == 4.0'f32)
    @assert(temp == 3.75'f32)
}

#test
{
    var value: f32 = 1.5
    let temp = dampRefValueWithLiterals(4.0'f32, 1.0'f32, &value, 0.5'f32, 0.25'f32)

    #assert(#typeof(temp) == f32)
    @assert(temp == 3.375'f32)
}
