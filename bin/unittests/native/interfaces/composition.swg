#global private

// Interface composition: multiple interfaces on one struct,
// interface stored in struct fields, iteration over interface arrays,
// and state mutation through interface methods.

interface IName
{
    mtd getName()->string
}

interface IValue
{
    mtd getValue()->s32
    mtd setValue(v: s32)
}

struct Counter
{
    label: string
    count: s32
}

impl IName for Counter
{
    mtd impl getName()->string => me.label
}

impl IValue for Counter
{
    mtd impl getValue()->s32 => me.count
    mtd impl setValue(v: s32) { me.count = v }
}

// Cast one struct to two different interfaces.
#test
{
    var c: Counter = {label: "hits", count: 0}
    var n          = cast(IName) c
    var v          = cast(IValue) c

    Swag.assert(n.getName() == "hits")
    Swag.assert(v.getValue() == 0)

    v.setValue(5)
    Swag.assert(c.count == 5)
    Swag.assert(v.getValue() == 5)
}

// Interface stored as struct field and dispatched through it.
struct Holder
{
    itf: #null IValue
}

func increment(h: *Holder)
{
    let itf = h.itf!
    let cur = itf.getValue()
    itf.setValue(cur + 1)
}

#test
{
    var c: Counter = {label: "held", count: 10}
    var h: Holder
    h.itf = cast(IValue) c
    increment(&h)
    increment(&h)
    Swag.assert(c.count == 12)
    Swag.assert(h.itf!.getValue() == 12)
}

// Iterate over an array of interfaces with different concrete types.
struct Doubler { val: s32 }
struct Tripler { val: s32 }

impl IValue for Doubler
{
    mtd impl getValue()->s32 => me.val * 2
    mtd impl setValue(v: s32) { me.val = v }
}

impl IValue for Tripler
{
    mtd impl getValue()->s32 => me.val * 3
    mtd impl setValue(v: s32) { me.val = v }
}

#test
{
    var d:     Doubler    = {val: 5}
    var t:     Tripler    = {val: 5}
    var items: [2] IValue = [cast(IValue) d, cast(IValue) t]

    var sum = 0
    for i in 2 do
        sum += items[i].getValue()

    Swag.assert(sum == 25)
}

// Mutation through interface array elements.
#test
{
    var a: Counter = {label: "a", count: 1}
    var b: Counter = {label: "b", count: 2}
    var c: Counter = {label: "c", count: 3}

    var arr: [3] IValue = [cast(IValue) a, cast(IValue) b, cast(IValue) c]

    for i in 3 do
        arr[i].setValue(arr[i].getValue() * 10)

    Swag.assert(a.count == 10)
    Swag.assert(b.count == 20)
    Swag.assert(c.count == 30)
}

// Interface reassignment between different concrete types via Swag.kindOf.
#test
{
    var d: Doubler = {val: 7}
    var t: Tripler = {val: 7}

    var itf: IValue = cast(IValue) d
    Swag.assert(itf.getValue() == 14)
    Swag.assert(Swag.kindOf(itf) == Doubler)

    itf = cast(IValue) t
    Swag.assert(itf.getValue() == 21)
    Swag.assert(Swag.kindOf(itf) == Tripler)
}

// Interface passed to a generic-like helper function.
func sumValues(items: [*] IValue, count: u32)->s32
{
    var total: s32 = 0
    for i in count do
        total += items[i].getValue()
    return total
}

#test
{
    var d1: Doubler = {val: 3}
    var d2: Doubler = {val: 7}
    var t1: Tripler = {val: 2}

    var arr: [3] IValue = [cast(IValue) d1, cast(IValue) d2, cast(IValue) t1]

    Swag.assert(sumValues(&arr[0], 3) == 6 + 14 + 6)
    Swag.assert(sumValues(&arr[0], 3) == 26)
}
