#global private

// --- Basic generic type assertions ---

func(T) identity(value: T)->T => value
func(T = s32) withDefault()->T => 42
func(T, N: s32) arrayIdentity(values: [N] T)->[N] T => values

struct(T) Box { value: T }
struct(T, N: s32) Buffer { values: [N] T }
struct(A, B) Pair { first: A, second: B }
struct(T) Wrapper { inner: Box'T }

struct(T, N: s32 = 2) DefaultBuffer { values: [N] T }
struct(T = s32) DefaultBox { value: T }

// Type of identity with explicit type
#assert(#typeof(identity'(s32)(0)) == s32)
#assert(#typeof(identity'(bool)(true)) == bool)
#assert(#typeof(identity'(f64)(0.0)) == f64)
#assert(#typeof(identity'(u8)(0'u8)) == u8)
#assert(#typeof(identity'(s64)(0's64)) == s64)
#assert(#typeof(identity'(u16)(0'u16)) == u16)

// Type deduction from literal
#assert(#typeof(identity(42)) == s32)
#assert(#typeof(identity(true)) == bool)
#assert(#typeof(identity(3.14)) == f64)
#assert(#typeof(identity(10'u8)) == u8)

// Default type parameter
#assert(#typeof(withDefault()) == s32)
#assert(#typeof(withDefault'(f64)()) == f64)
#assert(#typeof(withDefault'(u16)()) == u16)

// --- Struct type assertions ---

// Box types
func semaTest001()
{
    let b: Box's32
    let bs: Box'string
    let bb: Box'bool
    let bf: Box'f64
    let bu: Box'u8

    #assert(#typeof(b.value) == s32)
    #assert(#typeof(bs.value) == string)
    #assert(#typeof(bb.value) == bool)
    #assert(#typeof(bf.value) == f64)
    #assert(#typeof(bu.value) == u8)
}

// Buffer types with const params
func semaTest002()
{
    let b2: Buffer'(s32, 2)
    let b4: Buffer'(u8, 4)
    let b3: Buffer'(f64, 3)

    #assert(#typeof(b2.values) == #type [2] s32)
    #assert(#typeof(b4.values) == #type [4] u8)
    #assert(#typeof(b3.values) == #type [3] f64)
}

// Pair types (heterogeneous)
func semaTest003()
{
    let p1: Pair'(s32, f64)
    let p2: Pair'(string, bool)
    let p3: Pair'(u8, u16)

    #assert(#typeof(p1.first) == s32)
    #assert(#typeof(p1.second) == f64)
    #assert(#typeof(p2.first) == string)
    #assert(#typeof(p2.second) == bool)
    #assert(#typeof(p3.first) == u8)
    #assert(#typeof(p3.second) == u16)
}

// Nested generic type assertions
func semaTest004()
{
    let w: Wrapper's32
    let ws: Wrapper'string
    let wf: Wrapper'f64

    #assert(#typeof(w.inner.value) == s32)
    #assert(#typeof(ws.inner.value) == string)
    #assert(#typeof(wf.inner.value) == f64)
}

// Default params
func semaTest005()
{
    let db: DefaultBuffer'u16
    let db3: DefaultBuffer'(s32, 3)
    let dxf: DefaultBox'f64

    #assert(#typeof(db.values) == #type [2] u16)
    #assert(#typeof(db3.values) == #type [3] s32)
    #assert(#typeof(dxf.value) == f64)
}

// Nested generics: Pair of Pairs
func semaTest006()
{
    let pp: Pair'(Pair'(s32, s32), Pair'(f64, f64))

    #assert(#typeof(pp.first.first) == s32)
    #assert(#typeof(pp.first.second) == s32)
    #assert(#typeof(pp.second.first) == f64)
    #assert(#typeof(pp.second.second) == f64)
}

// Box of Box
func semaTest007()
{
    let bb: Box'(Box's32)
    let bbb: Box'(Box'(Box'bool))

    #assert(#typeof(bb.value.value) == s32)
    #assert(#typeof(bbb.value.value.value) == bool)
}

// Pair of Box
func semaTest008()
{
    let pb: Pair'(Box's32, Box'string)

    #assert(#typeof(pb.first.value) == s32)
    #assert(#typeof(pb.second.value) == string)
}

// Array identity preserves type
func semaTest009()
{
    let a: [3] s32 = [1, 2, 3]
    #assert(#typeof(arrayIdentity(a)) == #type [3] s32)

    let b: [2] f64 = [1.0, 2.0]
    #assert(#typeof(arrayIdentity(b)) == #type [2] f64)
}

// Struct-level type equivalence
func semaTest010()
{
    let b1: Box's32
    let b2: Box's32
    #assert(#typeof(b1) == #typeof(b2))
    #assert(#typeof(b1) == Box's32)
}

func semaTest011()
{
    let p1: Pair'(s32, f64)
    #assert(#typeof(p1) == Pair'(s32, f64))
}
