#global private

// Mutable container with full mutation API
struct(T) MutBox
{
    value: T
}

impl MutBox
{
    mtd get()->T => .value
    mtd set(v: T) { .value = v }
    mtd reset(zero: T) { .value = zero }
}

// Counter with generic step
struct(T) StepCounter
{
    current: T
    step:    T
}

impl StepCounter
{
    mtd advance() { .current += .step }
    mtd retreat() { .current -= .step }
    mtd getCurrent()->T => .current
    mtd advanceN(n: s32)
    {
        for var i = 0; i < n; i += 1 do
            .current += .step
    }
}

// Generic accumulator: method calls another method
struct(T) Accum
{
    total: T
    count: s32
}

impl Accum
{
    mtd add(value: T)
    {
        .total += value
        .count += 1
    }

    mtd addTwice(value: T)
    {
        .add(value)
        .add(value)
    }

    mtd getTotal()->T   => .total
    mtd getCount()->s32 => .count
    mtd getAverage()->T => .total / cast(T) .count
}

// Generic with method returning new generic struct instance
struct(T) Box
{
    value: T
}

struct(A, B) Pair
{
    first:  A
    second: B
}

impl Box
{
    mtd const get()->T => .value

    func(var U) zipWith(const me, other: Box'U)->Pair'(T, U)
    {
        return {first: me.value, second: other.value}
    }
}

// Range struct with iteration-style methods
struct(T) Range
{
    lo: T
    hi: T
}

impl Range
{
    mtd const contains(value: T)->bool
    {
        return value >= .lo and value <= .hi
    }

    mtd const width()->T => .hi - .lo

    mtd expand(delta: T)
    {
        .lo -= delta
        .hi += delta
    }

    mtd shrink(delta: T)
    {
        .lo += delta
        .hi -= delta
    }
}

// Method with const param on generic struct
struct(T, N: s32) FixedVec
{
    data: [N] T
    len:  s32
}

impl FixedVec
{
    mtd push(value: T)
    {
        .data[.len] = value
        .len        += 1
    }

    mtd pop()->T
    {
        .len -= 1
        return .data[.len]
    }

    mtd top()->T        => .data[.len - 1]
    mtd size()->s32     => .len
    mtd capacity()->s32 => N
    mtd isEmpty()->bool => .len == 0
    mtd isFull()->bool  => .len == N

    mtd clear() { .len = 0 }

    mtd get(index: s32)->T => .data[index]
}

// Generic struct with copy/move overloads gated by a where-constraint
struct(T) CopyGate
{
    values: [2] T
    count:  s32
}

impl CopyGate
{
    mtd add(value: T)
        where T == string
    {
        .values[.count] = value
        .count          += 1
    }

    mtd add(value: #move T)
    {
        .values[.count] = #move value
        .count          += 1
    }
}

// --- Tests ---

// Basic mutation
#test
{
    var mb: MutBox's32 = {value: 0}
    Swag.assert(mb.get() == 0)
    mb.set(42)
    Swag.assert(mb.get() == 42)
    mb.reset(0)
    Swag.assert(mb.get() == 0)
}

#test
{
    var mb: MutBox'f64 = {value: 1.5}
    Swag.assert(mb.get() == 1.5)
    mb.set(2.5)
    Swag.assert(mb.get() == 2.5)
}

// Step counter
#test
{
    var sc: StepCounter's32 = {current: 0, step: 5}
    sc.advance()
    Swag.assert(sc.getCurrent() == 5)
    sc.advance()
    Swag.assert(sc.getCurrent() == 10)
    sc.retreat()
    Swag.assert(sc.getCurrent() == 5)
}

#test
{
    var sc: StepCounter'f64 = {current: 0.0, step: 0.5}
    sc.advanceN(4)
    Swag.assert(sc.getCurrent() == 2.0)
    sc.retreat()
    Swag.assert(sc.getCurrent() == 1.5)
}

// Accumulator: method calling method
#test
{
    var acc: Accum's32 = {total: 0, count: 0}
    acc.add(10)
    acc.add(20)
    Swag.assert(acc.getTotal() == 30)
    Swag.assert(acc.getCount() == 2)
}

#test
{
    var acc: Accum's32 = {total: 0, count: 0}
    acc.addTwice(5)
    Swag.assert(acc.getTotal() == 10)
    Swag.assert(acc.getCount() == 2)
    acc.add(10)
    Swag.assert(acc.getTotal() == 20)
    Swag.assert(acc.getCount() == 3)
}

#test
{
    var acc: Accum'f64 = {total: 0.0, count: 0}
    acc.add(3.0)
    acc.add(6.0)
    acc.add(9.0)
    Swag.assert(acc.getTotal() == 18.0)
    Swag.assert(acc.getCount() == 3)
    Swag.assert(acc.getAverage() == 6.0)
}

#test
{
    var moved: string = "beta"

    var gate: CopyGate'string = {values: ["", ""], count: 0}
    gate.add("alpha")
    gate.add(#move moved)

    Swag.assert(gate.count == 2)
    Swag.assert(gate.values[0] == "alpha")
    Swag.assert(gate.values[1] == "beta")
}

// Zip two boxes
#test
{
    let b1: Box's32    = {value: 10}
    let b2: Box'string = {value: "ten"}
    let pair           = b1.zipWith'(string)(b2)
    Swag.assert(pair.first == 10)
    Swag.assert(pair.second == "ten")
}

#test
{
    let b1: Box'f64  = {value: 3.14}
    let b2: Box'bool = {value: true}
    let pair         = b1.zipWith'(bool)(b2)
    Swag.assert(pair.first == 3.14)
    Swag.assert(pair.second == true)
}

// Range methods
#test
{
    let r: Range's32 = {lo: 10, hi: 20}
    Swag.assert(r.contains(15) == true)
    Swag.assert(r.contains(10) == true)
    Swag.assert(r.contains(20) == true)
    Swag.assert(r.contains(5) == false)
    Swag.assert(r.contains(25) == false)
    Swag.assert(r.width() == 10)
}

#test
{
    var r: Range'f64 = {lo: 1.0, hi: 5.0}
    Swag.assert(r.width() == 4.0)
    r.expand(1.0)
    Swag.assert(r.lo == 0.0)
    Swag.assert(r.hi == 6.0)
    Swag.assert(r.width() == 6.0)
    r.shrink(2.0)
    Swag.assert(r.lo == 2.0)
    Swag.assert(r.hi == 4.0)
}

// FixedVec stack-like operations
#test
{
    var v: FixedVec'(s32, 5) = {len: 0}
    Swag.assert(v.isEmpty() == true)
    Swag.assert(v.capacity() == 5)
    v.push(10)
    v.push(20)
    v.push(30)
    Swag.assert(v.size() == 3)
    Swag.assert(v.isEmpty() == false)
    Swag.assert(v.isFull() == false)
    Swag.assert(v.top() == 30)
    Swag.assert(v.get(0) == 10)
    Swag.assert(v.get(1) == 20)

    let popped = v.pop()
    Swag.assert(popped == 30)
    Swag.assert(v.size() == 2)
    Swag.assert(v.top() == 20)

    v.clear()
    Swag.assert(v.isEmpty() == true)
    Swag.assert(v.size() == 0)
}

#test
{
    var v: FixedVec'(f64, 3) = {len: 0}
    v.push(1.1)
    v.push(2.2)
    v.push(3.3)
    Swag.assert(v.isFull() == true)
    Swag.assert(v.get(0) == 1.1)
    Swag.assert(v.get(2) == 3.3)
    Swag.assert(v.pop() == 3.3)
    Swag.assert(v.size() == 2)
}

#test
{
    var v: FixedVec'(u8, 4) = {len: 0}
    v.push(10'u8)
    v.push(20'u8)
    v.push(30'u8)
    v.push(40'u8)
    Swag.assert(v.isFull() == true)
    Swag.assert(v.pop() == 40'u8)
    Swag.assert(v.pop() == 30'u8)
    Swag.assert(v.size() == 2)
}
