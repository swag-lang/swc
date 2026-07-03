// Coverage for static (per-impl) data members accessed from instance methods.
//
// A `var` declared inside an `impl` is a single static storage shared by all
// instances (e.g. Pixel's Image.encoders registry). Accessing it from a `func`
// or via a type-qualified name resolves to that global storage. Accessing it
// from inside a `mtd` must resolve to the SAME global storage - it must not be
// treated as an instance-relative (`me` + offset) field. These tests pin that
// down (a regression previously crashed/garbled Image.save, which reads the
// `encoders` static from a method).

#global private

struct Bag { dummy: s32 }
impl Bag
{
    var counter: s32
    var values:  [4] s32

    mtd mInc()              { counter += 1 }
    mtd mSet(v: s32)        { counter = v }
    mtd mGet()->s32         { return counter }
    mtd mGetViaMe()->s32    { return me.counter }
    mtd mSetAt(i, v: s32)   { values[i] = v }
    mtd mGetAt(i: s32)->s32 { return values[i] }

    func fSet(v: s32)       { counter = v }
    func fGet()->s32        { return counter }
}

// Control: type-qualified access (no instance) reaches the static.
#test
{
    Bag.counter = 7
    @assert(Bag.counter == 7)
}

// Control: free-function access reaches the static.
#test
{
    Bag.fSet(11)
    @assert(Bag.fGet() == 11)
    @assert(Bag.counter == 11)
}

// A write performed inside a method must hit the static, not me-relative memory.
#test
{
    Bag.counter = 0
    var b: Bag
    b.mInc()
    b.mInc()
    b.mInc()
    @assert(Bag.counter == 3)
}

// A read performed inside a method must see the static.
#test
{
    Bag.fSet(42)
    var b: Bag
    @assert(b.mGet() == 42)
}

// Explicit `me.<static>` inside a method resolves to the static.
#test
{
    Bag.fSet(99)
    var b: Bag
    @assert(b.mGetViaMe() == 99)
}

// Method write then method read round-trips through the static.
#test
{
    var b: Bag
    b.mSet(123)
    @assert(b.mGet() == 123)
    @assert(Bag.fGet() == 123)
}

// Static array member accessed from methods.
#test
{
    Bag.values[2] = 0
    var b: Bag
    b.mSetAt(2, 55)
    @assert(b.mGetAt(2) == 55)
    @assert(Bag.values[2] == 55)
}
