#global private

struct(T) Container
{
    value: T
    count: s32
}

struct(T) Box
{
    value: T
}

struct(A, B) Pair
{
    first:  A
    second: B
}

struct(T) Accumulator
{
    value: T
}

struct Counter
{
    count: s32
}

impl Container
{
    mtd const toBox()->Box'T
    {
        return {value: .value}
    }

    mtd const pairWith(other: T)->Pair'(T, T)
    {
        return {first: .value, second: other}
    }
}

impl Accumulator
{
    mtd get()->T => .value
}

impl Accumulator
{
    mtd set(v: T)
    {
        .value = v
    }
}

impl Counter
{
    func(T) staticIdentity(value: T)->T => value
}

#test
{
    let c: Container's32 = {value: 42, count: 1}
    let b                = c.toBox()
    Swag.assert(b.value == 42)

    let c2: Container'string = {value: "boxed", count: 1}
    let b2 = c2.toBox()
    Swag.assert(b2.value == "boxed")

    let c3: Container'bool = {value: true, count: 0}
    let b3                 = c3.toBox()
    Swag.assert(b3.value == true)
}

#test
{
    let c: Container's32 = {value: 5, count: 1}
    let p                = c.pairWith(10)
    Swag.assert(p.first == 5)
    Swag.assert(p.second == 10)

    let words: Container'string = {value: "alpha", count: 2}
    let pair = words.pairWith("beta")
    Swag.assert(pair.first == "alpha")
    Swag.assert(pair.second == "beta")
}

#test
{
    var acc: Accumulator's32 = {value: 0}
    Swag.assert(acc.get() == 0)
    acc.set(100)
    Swag.assert(acc.get() == 100)

    var accBool: Accumulator'bool = {value: false}
    Swag.assert(accBool.get() == false)
    accBool.set(true)
    Swag.assert(accBool.get() == true)
}

#test
{
    Swag.assert(Counter.staticIdentity(42) == 42)
    Swag.assert(Counter.staticIdentity(true) == true)
    Swag.assert(Counter.staticIdentity("hi") == "hi")
    Swag.assert(Counter.staticIdentity(255'u8) == 255'u8)
}
