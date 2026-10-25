#global private

#[Swag.NoInline]
func runtimeValue(value: s32)->s32 => value

func makePair()->(s32, s32) => (runtimeValue(10), runtimeValue(20))

#test
{
    let (first, second) = makePair()
    Swag.assert(first == 10 and second == 20)
    let (only,) = (runtimeValue(42),)
    Swag.assert(only == 42)
    let (_, last) = makePair()
    Swag.assert(last == 20)
}

#test
{
    let point  = {x: 10, y: 20}
    let {y, x} = point
    Swag.assert(y == 20 and x == 10)
    let {y: vertical, x: _} = point
    Swag.assert(vertical == 20)
}

#test
{
    var point = {x: runtimeValue(10), y: runtimeValue(20)}
    point = {y: runtimeValue(40), x: runtimeValue(30)}
    Swag.assert(point.x == 30 and point.y == 40)
    let expected = {y: runtimeValue(40), x: runtimeValue(30)}
    Swag.assert(point == expected)
    {y: point.x, x: point.y} = point
    Swag.assert(point.x == 40 and point.y == 30)
}

#test
{
    var pair: (s32, s32) = makePair()
    (pair.item1, pair.item0) = pair
    Swag.assert(pair.item0 == 20 and pair.item1 == 10)
}

func namedArgument(point: {x: s32, y: s32})->s32 => point.x * 100 + point.y

#test
{
    let x     = runtimeValue(10)
    let y     = runtimeValue(20)
    let point = {y, x}
    Swag.assert(namedArgument(point) == 1020)
}

func makeReorderedRecord()->{y: s32, x: s32} => {y: runtimeValue(60), x: runtimeValue(50)}

#test
{
    var point = {x: runtimeValue(10), y: runtimeValue(20)}
    point = makeReorderedRecord()
    Swag.assert(point.x == 50 and point.y == 60)
    var destination: {x: s32, y: s32} = makeReorderedRecord()
    Swag.assert(destination.x == 50 and destination.y == 60)
}

#test
{
    const original:  {x: s32, y: s32} = {x: 10, y: 20}
    const reordered: {y: s32, x: s32} = original
    Swag.assert(reordered.x == 10 and reordered.y == 20)
}

#test
{
    let nested = (runtimeValue(1), {x: runtimeValue(10), y: runtimeValue(20)})
    let (first, {y, x}) = nested
    Swag.assert(first == 1 and y == 20 and x == 10)
    var a, b, c: s32
    (a, {y: c, x: b}) = nested
    Swag.assert(a == 1 and b == 10 and c == 20)
}

#test
{
    let {point: (first, second)} = {point: (10, 20)}
    Swag.assert(first == 10 and second == 20)
}

#[Swag.NoInline]
func runtimeFloat(value: f64)->f64 => value

#test
{
    let positive = {value: runtimeFloat(0.0)}
    let negative = {value: runtimeFloat(-0.0)}
    Swag.assert(positive == negative)
    let a = (runtimeFloat(0.0),)
    let b = (runtimeFloat(-0.0),)
    Swag.assert(a == b)
}

#test
{
    const (first, {y}) = (1, {y: 2})
    #assert(first == 1 and y == 2)
}

#[Swag.NoInline]
func loadFloat(value: const *f64)->f64 => value[]

#test
{
    var zeros: [2] f64 = [0.0, -0.0]
    let positive       = {value: loadFloat(&zeros[0])}
    let negative       = {value: loadFloat(&zeros[1])}
    Swag.assert(positive == negative)
}

#[Swag.NoInline]
func evaluateRecord(calls: *s32)->{y: s32, x: s32}
{
    calls[] += 1
    return {y: 20, x: 10}
}

#test
{
    var calls: s32
    var point = {x: 0, y: 0}
    point = evaluateRecord(&calls)
    Swag.assert(calls == 1 and point.x == 10 and point.y == 20)
    let {x, y} = evaluateRecord(&calls)
    Swag.assert(calls == 2 and x == 10 and y == 20)
}

#[Swag.NoInline]
func floatRecord(value: const *f64)->{value: f64} => {value: value[]}

#test
{
    var zeros: [2] f64 = [0.0, -0.0]
    Swag.assert(floatRecord(&zeros[0]) == floatRecord(&zeros[1]))
    const left  = {point: {x: 10, y: 20}, tag: 3}
    const right = {tag: 3, point: {y: 20, x: 10}}
    #assert(left == right)
}

struct RecordCounter { value: s32 }

#[Swag.NoInline]
func countRecords(counter: *RecordCounter?)->s32
{
    if not counter do
        return 0
    for
    {
        let {amount} = {amount: 1}
        counter.value += amount
        if counter.value == 3 do
            break
    }
    return counter.value
}

#test
{
    var counter: RecordCounter
    Swag.assert(countRecords(&counter) == 3)
}

#test
{
    var point: {x: s32, y: s32}
    (point,) = ({y: 20, x: 10},)
    Swag.assert(point.x == 10 and point.y == 20)
}

#test
{
    var calls: s32
    var point: {x: s32, y: s32}
    (point,) = (evaluateRecord(&calls),)
    Swag.assert(calls == 1 and point.x == 10 and point.y == 20)
}
