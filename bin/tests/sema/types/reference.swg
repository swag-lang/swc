#global fileprivate

struct A {}
func titi(a: &A) {}

func tata(a: const &A) {}
#test
{
    var a: A
    tata(a)
}

#test
{
    var a: A
    var b: &A = &a
    var c: const &A = &a
    var d: const &A = a
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
    let result = readConstAddr(&holder.value)

    #assert(#typeof(valueRef) == const &ConstAddrValue)
    #assert(#typeof(result) == s32)
}

func inspectConstScalar(value: const &s32)
{
    let ptr = &value
    #assert(#typeof(ptr) == *s32)
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
    inspectConstScalar(value)
    inspectConstScalar(4)
    inspectConstScalar(value + 1)
}

#test
{
    let tupleSum = sumConstAnon({1, 2})
    let pairSum = sumConstPair({x: 3, y: 4})

    #assert(#typeof(tupleSum) == s32)
    #assert(#typeof(pairSum) == s32)
}

#test
{
    var value: f32 = 1.5
    let valueRef: const &f32 = &value
    let copied = cast(f32) valueRef
    let sum = valueRef + 2.5'f32

    #assert(#typeof(copied) == f32)
    #assert(#typeof(sum) == f32)
}

#test
{
    var value: f32 = 1.5
    let sum = addRefValue(&value, 2.5'f32)

    #assert(#typeof(sum) == f32)
}

#test
{
    var value: f32 = 1.5
    let temp = dampRefValue(&value, 2.0'f32, 3.0'f32, 0.5'f32)

    #assert(#typeof(temp) == f32)
}

#test
{
    var box: RefFloatBox = {value: 1.5}
    let sum = addRefValue(&box.value, 2.5'f32)
    let temp = dampRefValue(&box.value, 2.0'f32, 3.0'f32, 0.5'f32)

    #assert(#typeof(sum) == f32)
    #assert(#typeof(temp) == f32)
}

#test
{
    var value: f32 = 1.5
    let temp = dampRefValueWithLiterals(4.0'f32, 1.0'f32, &value, 0.5'f32, 0.25'f32)

    #assert(#typeof(temp) == f32)
}
