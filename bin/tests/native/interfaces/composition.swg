#global fileprivate

// Interface composition: multiple interfaces on one struct,
// interface stored in struct fields, iteration over interface arrays,
// and state mutation through interface methods.

interface IName
{
    mtd getName()->string;
}

interface IValue
{
    mtd getValue()->s32;
    mtd setValue(v: s32);
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
    var n = cast(IName) c
    var v = cast(IValue) c

    @assert(n.getName() == "hits")
    @assert(v.getValue() == 0)

    v.setValue(5)
    @assert(c.count == 5)
    @assert(v.getValue() == 5)
}

// Interface stored as struct field and dispatched through it.
struct Holder
{
    itf: IValue
}

func increment(h: *Holder)
{
    let cur = h.itf.getValue()
    h.itf.setValue(cur + 1)
}

#test
{
    var c: Counter = {label: "held", count: 10}
    var h: Holder
    h.itf = cast(IValue) c
    increment(&h)
    increment(&h)
    @assert(c.count == 12)
    @assert(h.itf.getValue() == 12)
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
    var d: Doubler = {val: 5}
    var t: Tripler = {val: 5}
    var items: [2] IValue
    items[0] = cast(IValue) d
    items[1] = cast(IValue) t

    var sum = 0
    for i in 2 do
        sum += items[i].getValue()

    @assert(sum == 25)
}

// Mutation through interface array elements.
#test
{
    var a: Counter = {label: "a", count: 1}
    var b: Counter = {label: "b", count: 2}
    var c: Counter = {label: "c", count: 3}

    var arr: [3] IValue
    arr[0] = cast(IValue) a
    arr[1] = cast(IValue) b
    arr[2] = cast(IValue) c

    for i in 3 do
        arr[i].setValue(arr[i].getValue() * 10)

    @assert(a.count == 10)
    @assert(b.count == 20)
    @assert(c.count == 30)
}

// Interface reassignment between different concrete types via @kindof.
#test
{
    var d: Doubler = {val: 7}
    var t: Tripler = {val: 7}

    var itf: IValue = cast(IValue) d
    @assert(itf.getValue() == 14)
    @assert(@kindof(itf) == Doubler)

    itf = cast(IValue) t
    @assert(itf.getValue() == 21)
    @assert(@kindof(itf) == Tripler)
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

    var arr: [3] IValue
    arr[0] = cast(IValue) d1
    arr[1] = cast(IValue) d2
    arr[2] = cast(IValue) t1

    @assert(sumValues(&arr[0], 3) == 6 + 14 + 6)
    @assert(sumValues(&arr[0], 3) == 26)
}
