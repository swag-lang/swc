#global private

struct Pair
{
    base: s32
    step: s32
}

struct UnaryClosureHolder
{
    cb: (func||(s32)->s32)?
}

struct NullaryClosureHolder
{
    cb: (func||()->s32)?
}

struct PathTarget
{
    value: s32
}

struct PathHolder
{
    target: *PathTarget?
}

struct PathOwner
{
    target: *PathTarget?
    bias:   s32
}

struct MethodClosureReceiver
{
    base: s32
}

const GlobalBonus = 2
var GlobalSeed = 40

func addOne(value: s32)->s32 => value + 1
func invokeUnary(cb: func||(s32)->s32, value: s32)->s32 => cb(value)
func relayUnary(cb: func||(s32)->s32)->func||(s32)->s32 => cb

impl MethodClosureReceiver
{
    mtd makeAdder(offset: s32)->func ||(*MethodClosureReceiver, s32)->s32
    {
        return mtd|offset|(value: s32)->s32
        {
            return .base + offset + value
        }
    }
}

impl PathOwner
{
    mtd makeCallback()->func||()->s32
    {
        return func|me.target, me.bias|()->s32
        {
            let safeTarget = unwrap target
            safeTarget.value += bias
            return safeTarget.value
        }
    }
}

func maybeInvoke(cb: (func||()->s32)? = null)->s32
{
    if cb do
        return cb()
    return -1
}

func makeParamPairClosure(pair: Pair)->func||(s32)->s32
{
    return func|pair|(value: s32)->s32
    {
        pair.base += value
        return pair.base + pair.step
    }
}

func makeParamArrayClosure(values: [3] s32)->func||()->s32
{
    return func|values|()->s32
    {
        values[1] += 1
        return values[0] + values[1] + values[2]
    }
}

#[Swag.Inline]
func makeInlineCapturedValue(value: s32)->func||()->s32
{
    return func|value|()->s32
    {
        return value
    }
}

#[Swag.Inline]
func inlineCapturedRefValue(value: s32)->s32
{
    let cb = func|&value|()->s32
    {
        value += 1
        return value
    }

    let first  = cb()
    let second = cb()
    return first * 10 + second
}

func normalTypedVariadicClosureCapture(values: s32...)->s32
{
    let cb = func|values|()->s32
    {
        return values[0] + values[1]
    }

    return cb()
}

#[Swag.Inline]
func inlineTypedVariadicClosureCapture(values: s32...)->s32
{
    let cb = func|values|()->s32
    {
        return values[0] + values[1]
    }

    return cb()
}

func normalUntypedVariadicClosureCapture(values: ...)->s32
{
    let cb = func|values|()->s32
    {
        return assume cast(s32, values[0]) + assume cast(s32, values[1])
    }

    return cb()
}

#[Swag.Inline]
func inlineUntypedVariadicClosureCapture(values: ...)->s32
{
    let cb = func|values|()->s32
    {
        return assume cast(s32, values[0]) + assume cast(s32, values[1])
    }

    return cb()
}

func normalAnyVariadicClosureCapture(values: any...)->s32
{
    let cb = func|values|()->s32
    {
        return assume cast(s32, values[0]) + assume cast(s32, values[1])
    }

    return cb()
}

#[Swag.Inline]
func inlineAnyVariadicClosureCapture(values: any...)->s32
{
    let cb = func|values|()->s32
    {
        return assume cast(s32, values[0]) + assume cast(s32, values[1])
    }

    return cb()
}

func runDottedPathCapture()->s32
{
    var first:  PathTarget = PathTarget{value: 10}
    var second: PathTarget = PathTarget{value: 50}
    var holder: PathHolder
    holder.target = &first

    let cb: func||()->s32 = func|holder.target|()->s32
    {
        let t = unwrap target
        t.value += 3
        return t.value
    }

    holder.target = &second
    Swag.assert(cb() == 13)
    Swag.assert(cb() == 16)
    return first.value * 100 + second.value
}

func runMePathCapture()->s32
{
    var first:  PathTarget = PathTarget{value: 5}
    var second: PathTarget = PathTarget{value: 90}
    var owner:  PathOwner
    owner.target = &first
    owner.bias   = 4

    let cb = owner.makeCallback()
    owner.target = &second
    owner.bias   = 100

    let firstValue  = cb()
    let secondValue = cb()
    Swag.assert(first.value == 13)
    Swag.assert(second.value == 90)
    return firstValue * 100 + secondValue
}

func runInlineClosureCaptureExpr()->s32
{
    var base = 6
    let cb   = makeInlineCapturedValue(base + 1)
    base = 100
    return cb()
}

func runInlineClosureCaptureRef()->s32
{
    return inlineCapturedRefValue(6)
}

#test
{
    var cb: (func||(s32)->s32)? = null
    Swag.require(cb == null)

    cb = func(value: s32)->s32 { return value + 1 }
    Swag.require(cb(4) == 5)

    cb = &addOne
    Swag.require(cb(8) == 9)

    let offset = 5
    cb = func|offset|(value: s32)->s32 { return value + offset }
    Swag.require(cb(3) == 8)
    Swag.require(cb != null)
}

#test
{
    var seed = 5
    let first: func||()->s32 = func|var seed|()->s32
    {
        seed += 1
        return seed
    }

    let second: func||()->s32 = func|var seed|()->s32
    {
        seed += 10
        return seed
    }

    seed = 100
    Swag.require(first() == 6)
    Swag.require(first() == 7)
    Swag.require(second() == 15)
    Swag.require(second() == 25)
    Swag.require(seed == 100)
}

#test
{
    var offset = 5
    var holder: UnaryClosureHolder
    holder.cb = func|offset|(value: s32)->s32 { return value + offset }

    offset = 100
    Swag.require(holder.cb(4) == 9)
    Swag.require(invokeUnary(holder.cb, 7) == 12)
}

#test
{
    var total = 10
    var holder: NullaryClosureHolder
    holder.cb = func|&total|()->s32
    {
        total += 2
        return total
    }

    Swag.require(holder.cb() == 12)
    Swag.require(holder.cb() == 14)
    Swag.require(total == 14)
}

#test
{
    var total = 0
    let inc: func||()->s32 = func|&total|()->s32
    {
        total += 1
        return total
    }

    let boost: func||()->s32 = func|&total|()->s32
    {
        total += 10
        return total
    }

    Swag.require(inc() == 1)
    Swag.require(boost() == 11)
    Swag.require(inc() == 12)
    Swag.require(total == 12)
}

#test
{
    var total  = 4
    var factor = 3
    let cb: func||(s32)->s32 = func|var factor, &total|(value: s32)->s32
    {
        total  += value * factor
        factor += 1
        return total * 10 + factor
    }

    factor = 100
    Swag.require(cb(2) == 104)
    Swag.require(cb(1) == 145)
    Swag.require(total == 14)
    Swag.require(factor == 100)
}

#test
{
    var values: [3] s32       = [1, 2, 3]
    let cb:     func||()->s32 = func|values|()->s32
    {
        return values[0] + values[1] + values[2]
    }

    values = [100, 2, 3]
    Swag.require(cb() == 6)
    Swag.require(cb() == 6)
    Swag.require(values[0] == 100)
}

#test
{
    var values: [3] s32       = [1, 2, 3]
    let cb:     func||()->s32 = func|&values|()->s32
    {
        return values[0] + values[1] + values[2]
    }

    values = [5, 2, 3]
    Swag.require(cb() == 10)

    values = [20, 2, 3]
    Swag.require(cb() == 25)
    Swag.require(values[0] == 20)
}

#test
{
    let cb = makeParamPairClosure({base: 4, step: 3})
    Swag.require(cb(2) == 9)
    Swag.require(cb(1) == 10)
}

#test
{
    let cb = makeParamArrayClosure([1, 2, 3])
    Swag.require(cb() == 7)
    Swag.require(cb() == 8)
}

#test
{
    let plain = relayUnary(func(value: s32)->s32 { return value + 1 })
    Swag.require(plain(4) == 5)

    let fromFunction = relayUnary(&addOne)
    Swag.require(fromFunction(4) == 5)

    let offset   = 10
    let captured = relayUnary(func|offset|(value: s32)->s32 { return value + offset })
    Swag.require(captured(4) == 14)
}

#test
{
    Swag.require(maybeInvoke() == -1)
    Swag.require(maybeInvoke(null) == -1)
}

#test
{
    Swag.require(maybeInvoke(func()->s32 { return 9 }) == 9)
}

#test
{
    Swag.require(invokeUnary(func(value: s32)->s32 { return value * 2 }, 6) == 12)
}

#test
{
    let factor = 3
    let cb: func||(s32)->s32 = func|factor|(value: s32)->s32 { return value * factor }
    Swag.require(invokeUnary(cb, 7) == 21)
}

#test
{
    let offset = 3
    let cb     = func|offset|(value: s32)->s32 { return value + offset }
    Swag.require(cb(7) == 10)
}

#test
{
    let factor = 3
    Swag.require((func|factor|(value: s32)->s32 { return value * factor })(7) == 21)
}

#test
{
    var receiver = MethodClosureReceiver{base: 7}
    let cb       = receiver.makeAdder(3)
    Swag.require(cb(&receiver, 5) == 15)
}

#test
{
    Swag.require(runDottedPathCapture() == 1650)
}

#test
{
    Swag.require(runMePathCapture() == 913)
}

#test
{
    Swag.require(runInlineClosureCaptureExpr() == 7)
}

#test
{
    Swag.require(runInlineClosureCaptureRef() == 78)
}

#test
{
    Swag.require(normalTypedVariadicClosureCapture(3, 4) == 7)
    Swag.require(inlineTypedVariadicClosureCapture(3, 4) == 7)
    Swag.require(normalUntypedVariadicClosureCapture(5, 6) == 11)
    Swag.require(inlineUntypedVariadicClosureCapture(5, 6) == 11)
    Swag.require(normalAnyVariadicClosureCapture(7, 8) == 15)
    Swag.require(inlineAnyVariadicClosureCapture(7, 8) == 15)
}

#test
{
    let globalReader: func||()->s32 = func()->s32 { return GlobalSeed + GlobalBonus }
    Swag.require(globalReader() == 42)

    var text = "abc"
    let byValue: func||()->string = func|text|()->string { return text }
    let byRef:   func||()->string = func|&text|()->string { return text }

    text = "zzz"
    Swag.require(byValue() == "abc")
    Swag.require(byRef() == "zzz")
}
