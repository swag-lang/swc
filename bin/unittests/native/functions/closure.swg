#global private

struct Boundary64
{
    a, b, c, d, e, f, g, h: u64
}

struct Pair
{
    base: s32
    step: s32
}

func addOne(value: s32)->s32 => value + 1

func makeCounter(start: s32)->func||()->s32
{
    var counter = start
    return func|var counter|()->s32
    {
        counter += 1
        return counter
    }
}

func runParamRefCapture(seed: s32)->s32
{
    let cb: func||()->s32 = func|&seed|()->s32
    {
        seed += 2
        return seed
    }

    let first  = cb()
    let second = cb()
    return first * 10 + second
}

func runLocalRefCapture()->s32
{
    var total                = 5
    let cb: func||(s32)->s32 = func|&total|(value: s32)->s32
    {
        total += value
        return total
    }

    let first  = cb(3)
    let second = cb(4)
    Swag.assert(total == 12)
    return first * 10 + second
}

func makeNested(base: s32)->func||()->s32
{
    let outer: func||()->func||()->s32 = func|base|()->func||()->s32
    {
        let initial = base + 1
        return func|base, var initial|()->s32
        {
            initial += base
            return initial
        }
    }

    return outer()
}

#test
{
    let fromLambda:   func||(s32)->s32 = func(value: s32)->s32 { return value * 3 }
    let fromFunction: func||(s32)->s32 = &addOne
    Swag.assert(fromLambda(4) == 12)
    Swag.assert(fromFunction(4) == 5)
}

#test
{
    let counter = makeCounter(10)
    Swag.assert(counter() == 11)
    Swag.assert(counter() == 12)
    Swag.assert(counter() == 13)
}

#test
{
    Swag.assert(runParamRefCapture(7) == 101)
}

#test
{
    Swag.assert(runLocalRefCapture() == 92)
}

#test
{
    let pair:  Pair             = {base: 7, step: 4}
    let apply: func||(s32)->s32 = func|pair|(value: s32)->s32 { return pair.base + pair.step * value }
    Swag.assert(apply(3) == 19)
}

#test
{
    let boundary: Boundary64    = {a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8}
    let sum:      func||()->u64 = func|boundary|()->u64 { return boundary.a + boundary.h }
    Swag.assert(sum() == 9'u64)
}

#test
{
    let nested = makeNested(6)
    Swag.assert(nested() == 13)
    Swag.assert(nested() == 19)
}

#test
{
    func toto(x: s32)->s32 { return 42 + x }

    var fb: func||(s32)->s32 = undefined
    fb = &toto
    Swag.assert(fb(5) == 47)
}

// Local variables inside control flow within closure bodies must be accessible.
#test
{
    var arr = [10, 20, 30]
    var fct: func||(s32)->s32 = undefined
    fct = func|arr|(extra: s32)->s32
    {
        var sum = 0
        for v in arr do
            sum += v
        return sum + extra
    }
    Swag.assert(fct(4) == 64)
}

#test
{
    var fct: func||(s32)->s32 = undefined
    fct = func(n: s32)->s32
    {
        var total = 0
        for i in cast(u32) n do
            total += cast(s32) i
        return total
    }
    Swag.assert(fct(5) == 0 + 1 + 2 + 3 + 4)
}

#test
{
    var fct: func||(s32)->s32 = undefined
    let base = 100
    fct = func|base|(x: s32)->s32
    {
        var result = base
        if x > 0
        {
            var bonus = x * 2
            result += bonus
        }
        return result
    }
    Swag.assert(fct(5) == 110)
    Swag.assert(fct(0) == 100)
}

struct LifecycleCounter
{
    value: s32
}

impl LifecycleCounter
{
    mtd opPostCopy() { .value += 100 }
    mtd opDrop() {}
}

// A type with lifecycle operations can be captured by reference: the closure stores
// a pointer, so no hidden copy or drop is involved.
#test
{
    var tracked             = LifecycleCounter{value: 5}
    let read: func||()->s32 = func|&tracked|()->s32 { return tracked.value }
    Swag.assert(read() == 5)
    tracked.value = 9
    Swag.assert(read() == 9)
}

// 'var' makes the copy writable and leaves the source alone, whether it was 'let' or 'var'.
#test
{
    let fromLet                = 10
    var fromVar                = 20
    let bumpLet: func||()->s32 = func|var fromLet|()->s32 { fromLet += 1; return fromLet }
    let bumpVar: func||()->s32 = func|var fromVar|()->s32 { fromVar += 1; return fromVar }

    Swag.assert(bumpLet() == 11)
    Swag.assert(bumpLet() == 12)
    Swag.assert(bumpVar() == 21)
    Swag.assert(fromLet == 10)
    Swag.assert(fromVar == 20)
}

// Two 'var' captures of the same source own separate cells.
#test
{
    var seed = 5
    let first:  func||()->s32 = func|var seed|()->s32 { seed += 1; return seed }
    let second: func||()->s32 = func|var seed|()->s32 { seed += 10; return seed }

    Swag.assert(first() == 6)
    Swag.assert(second() == 15)
    Swag.assert(first() == 7)
    Swag.assert(seed == 5)
}
