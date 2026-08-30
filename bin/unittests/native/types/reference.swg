// 

#global private
struct Vec2
{
    x: s32
    y: s32
}

struct RefIndexBuffer
{
    values: [1] s32
}

impl RefIndexBuffer
{
    mtd ref1(index: u64)->*s32 { return &me.values[index] }
}

#test
{
    func testRead(x: *Vec2)->s32 { return x.x + x.y; }
    var v: Vec2 = {x: 8, y: 13}
    var sum     = testRead(&v)
    Swag.assert(sum == 21)
}

#test
{
    func testWrite(x: *Vec2)
    {
        x.x = x.x * 2
        x.y = x.y + 7
    }
    var v: Vec2 = {x: 9, y: 4}
    testWrite(&v)
    Swag.assert(v.x == 18)
    Swag.assert(v.y == 11)
}

#test
{
    func getPtr(x: *s32)->*s32 { return x; }
    func writeThrough(p: *s32)
    {
        p[] = 42
    }
    var v: s32 = 10
    var p      = getPtr(&v)
    Swag.assert(p[] == 10)
    writeThrough(p)
    Swag.assert(v == 42)
}

func writeScalarRef(target: *s32, value: s32)
{
    target[] = value
}

#test
{
    var value:    s32  = 10
    var valueRef: *s32 = &value

    valueRef[] = 42
    Swag.assert(valueRef[] == 42)
    Swag.assert(value == 42)

    valueRef[] += 8
    Swag.assert(valueRef[] == 50)
    Swag.assert(value == 50)

    writeScalarRef(&value, 99)
    Swag.assert(valueRef[] == 99)
    Swag.assert(value == 99)
}

#test
{
    func getPtr(x: *Vec2)->*Vec2 { return x; }
    func writeThrough(p: *Vec2)
    {
        p.x = -3
        p.y = 99
    }
    var v: Vec2 = {x: 1, y: 2}
    var p       = getPtr(&v)
    writeThrough(p)
    Swag.assert(v.x == -3)
    Swag.assert(v.y == 99)
}

func writeVecRef(target: *Vec2, value: Vec2)
{
    target[] = value
}

#test
{
    var value:    Vec2  = {x: 1, y: 2}
    var valueRef: *Vec2 = &value
    let other:    Vec2  = {x: 30, y: 40}

    valueRef[] = other
    Swag.assert(valueRef.x == 30)
    Swag.assert(valueRef.y == 40)
    Swag.assert(value.x == 30)
    Swag.assert(value.y == 40)

    writeVecRef(&value, {x: -5, y: 12})
    Swag.assert(valueRef.x == -5)
    Swag.assert(valueRef.y == 12)
    Swag.assert(value.x == -5)
    Swag.assert(value.y == 12)
}

#test
{
    func choose(flag: bool, a: *Vec2, b: *Vec2)->*Vec2
    {
        if flag do
            return a
        return b
    }
    var left:  Vec2 = {x: 100, y: 200}
    var right: Vec2 = {x: 300, y: 400}
    var p0          = choose(true, &left, &right)
    var p1          = choose(false, &left, &right)
    Swag.assert(p0.x == 100)
    Swag.assert(p0.y == 200)
    Swag.assert(p1.x == 300)
    Swag.assert(p1.y == 400)
}

#test
{
    func nextDigit(bytes: const [..] u8, index: *u64)->u8
    {
        if index[] < bytes.count
        {
            let value = bytes[index[]]
            index[] += 1
            return value
        }

        return 0'u8
    }

    let bytes = cast(const [..] u8) "42"
    var index: u64
    Swag.assert(nextDigit(bytes, &index) == '4'u8)
    Swag.assert(nextDigit(bytes, &index) == '2'u8)
    Swag.assert(index == 2'u64)
}

#test
{
    var values: RefIndexBuffer = {values: [12]}
    var total = 1's32
    var index = 0's64

    let valueRef: *s32 = values.ref1(index)
    total      += valueRef[]
    valueRef[] += 5

    Swag.assert(total == 13)
    Swag.assert(valueRef[] == 17)
    Swag.assert(values.values[0] == 17)
}

struct A {}
var gRefTitiCalls: s32
var gRefTataCalls: s32
func titi(a: *A) { gRefTitiCalls += 1 }
#test
{
    var a: A
    gRefTitiCalls = 0
    titi(&a)
    Swag.assert(gRefTitiCalls == 1)
}

func tata(a: A) { gRefTataCalls += 1 }
#test
{
    var a: A
    gRefTataCalls = 0
    tata(a)
    Swag.assert(gRefTataCalls == 1)
}

struct ConstAddrValue
{
    x: s32
}

struct ConstAddrHolder
{
    value: ConstAddrValue
}

func readConstAddr(value: ConstAddrValue)->s32 { return value.x }

#test
{
    let holder:   ConstAddrHolder       = {value: {x: 123}}
    var valueRef: const *ConstAddrValue = &holder.value

    Swag.assert(valueRef.x == 123)
    Swag.assert(readConstAddr(&holder.value) == 123)
}

func inspectConstScalar(value: s32, expected: s32)
{
    let ptr = &value
    #assert(#typeof(ptr) == *s32)
    Swag.assert(value == expected)
    Swag.assert(ptr[] == expected)
}

func sumConstAnon(value: { x: s32, y: s32 })->s32
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

func sumConstPair(value: const *RefPair)->s32 { return value.x + value.y }
func(T) addRefValue(value: *T, rhs: T)->T { return value[] + rhs }
func(T) dampRefValue(currentVelocity: *T, omega, clampedChange, deltaTime: T)->T
{
    let temp = (currentVelocity[] + omega * clampedChange) * deltaTime
    return temp
}

func(T) dampRefValueWithLiterals(current, target: T, currentVelocity: *T, smoothTime, deltaTime: T)->T
{
    let omega  = 2.0 / smoothTime
    let change = current - target
    let temp   = (currentVelocity[] + omega * change) * deltaTime
    return temp
}

#test
{
    var value: s32 = 41
    inspectConstScalar(value, 41)
}

#test
{
    let tupleValue = {x: 1, y: 2}
    let pairValue  = RefPair{x: 3, y: 4}
    Swag.assert(sumConstAnon(tupleValue) == 3)
    Swag.assert(sumConstPair(&pairValue) == 7)
}

#test
{
    var value:    f32        = 1.5
    let valueRef: const *f32 = &value
    let copied               = cast(f32) valueRef[]
    let sum                  = valueRef[] + 2.5'f32

    #assert(#typeof(copied) == f32)
    #assert(#typeof(sum) == f32)

    Swag.assert(copied == 1.5'f32)
    Swag.assert(sum == 4.0'f32)
}

#test
{
    var value: f32 = 1.5
    let sum        = addRefValue(&value, 2.5'f32)

    #assert(#typeof(sum) == f32)
    Swag.assert(sum == 4.0'f32)
}

#test
{
    var value: f32 = 1.5
    let temp       = dampRefValue(&value, 2.0'f32, 3.0'f32, 0.5'f32)

    #assert(#typeof(temp) == f32)
    Swag.assert(temp == 3.75'f32)
}

#test
{
    var box: RefFloatBox = {value: 1.5}
    let sum              = addRefValue(&box.value, 2.5'f32)
    let temp             = dampRefValue(&box.value, 2.0'f32, 3.0'f32, 0.5'f32)

    #assert(#typeof(sum) == f32)
    #assert(#typeof(temp) == f32)
    Swag.assert(sum == 4.0'f32)
    Swag.assert(temp == 3.75'f32)
}

#test
{
    var value: f32 = 1.5
    let temp       = dampRefValueWithLiterals(4.0'f32, 1.0'f32, &value, 0.5'f32, 0.25'f32)

    #assert(#typeof(temp) == f32)
    Swag.assert(temp == 3.375'f32)
}

#test
{
    var grid:     [2, 3] u32
    var valueRef: *u32 = &grid[1, 2]

    valueRef[] += 1'u32
    Swag.assert(grid[1, 2] == 1'u32)

    valueRef[] = 7'u32
    Swag.assert(grid[1, 2] == 7'u32)
}
