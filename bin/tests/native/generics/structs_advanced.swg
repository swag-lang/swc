#global fileprivate

// Generic struct with using (embedded field)
struct(T) Base
{
    value: T
}

struct(T) Extended
{
    using base: Base'T
    extra: s32
}

// Deep nesting: 3 levels
struct(T) Box
{
    value: T
}

struct(T) MiddleBox
{
    inner: Box'T
}

struct(T) OuterBox
{
    middle: MiddleBox'T
}

// Generic struct holding two different instantiations
struct(A, B) HeteroHolder
{
    left: Box'A
    right: Box'B
}

// Generic struct with pointer to generic
struct(T) RefBox
{
    ptr: *Box'T
}

// Non-generic struct with multiple generic field instantiations
struct MultiBox
{
    intBox:    Box's32
    floatBox:  Box'f64
    boolBox:   Box'bool
    stringBox: Box'string
}

// Generic struct of generic struct (nested type parameter)
struct(T) BoxOfBox
{
    inner: Box'(Box'T)
}

// Generic struct with array of generic structs
struct(T, N: s32) BoxList
{
    items: [N] Box'T
}

// Generic struct with two const params used in expressions
struct(T, Rows: s32, Cols: s32) Matrix
{
    data: [Rows * Cols] T
}

impl Matrix
{
    mtd at(row: s32, col: s32)->T => .data[row * Cols + col]
    mtd rows()->s32 => Rows
    mtd cols()->s32 => Cols
    mtd totalSize()->s32 => Rows * Cols
}

// --- Tests ---

// Using/embedded generic field
#test
{
    var ext: Extended's32 = {base: {value: 42}, extra: 10}
    @assert(ext.value == 42)
    @assert(ext.extra == 10)

    var extF: Extended'f64 = {base: {value: 3.14}, extra: 7}
    @assert(extF.value == 3.14)
    @assert(extF.extra == 7)
}

// Deep 3-level nesting
#test
{
    let outer: OuterBox's32 = {middle: {inner: {value: 99}}}
    @assert(outer.middle.inner.value == 99)

    let outerStr: OuterBox'string = {middle: {inner: {value: "deep"}}}
    @assert(outerStr.middle.inner.value == "deep")

    let outerBool: OuterBox'bool = {middle: {inner: {value: true}}}
    @assert(outerBool.middle.inner.value == true)
}

// Heterogeneous holder
#test
{
    let h: HeteroHolder'(s32, string) = {left: {value: 42}, right: {value: "hello"}}
    @assert(h.left.value == 42)
    @assert(h.right.value == "hello")

    let h2: HeteroHolder'(bool, f64) = {left: {value: false}, right: {value: 2.718}}
    @assert(h2.left.value == false)
    @assert(h2.right.value == 2.718)
}

// Generic pointer to generic struct
#test
{
    var box: Box's32 = {value: 77}
    let refb: RefBox's32 = {ptr: &box}
    @assert(dref refb.ptr == box)
    @assert((dref refb.ptr).value == 77)
}

// Non-generic struct with many generic instantiations
#test
{
    let mb: MultiBox = {
        intBox: {value: 1},
        floatBox: {value: 2.5},
        boolBox: {value: true},
        stringBox: {value: "multi"}}
    @assert(mb.intBox.value == 1)
    @assert(mb.floatBox.value == 2.5)
    @assert(mb.boolBox.value == true)
    @assert(mb.stringBox.value == "multi")
}

// Box of Box (nested generic type parameter)
#test
{
    let bb: BoxOfBox's32 = {inner: {value: {value: 123}}}
    @assert(bb.inner.value.value == 123)

    let bbs: BoxOfBox'string = {inner: {value: {value: "nested"}}}
    @assert(bbs.inner.value.value == "nested")
}

// Array of generic structs
#test
{
    let list: BoxList'(s32, 3) = {items: [{value: 10}, {value: 20}, {value: 30}]}
    @assert(list.items[0].value == 10)
    @assert(list.items[1].value == 20)
    @assert(list.items[2].value == 30)

    let blist: BoxList'(bool, 2) = {items: [{value: true}, {value: false}]}
    @assert(blist.items[0].value == true)
    @assert(blist.items[1].value == false)
}

// Matrix with two const params
#test
{
    var m: Matrix'(s32, 2, 3) = {data: [1, 2, 3, 4, 5, 6]}
    @assert(m.rows() == 2)
    @assert(m.cols() == 3)
    @assert(m.totalSize() == 6)
    @assert(m.at(0, 0) == 1)
    @assert(m.at(0, 2) == 3)
    @assert(m.at(1, 0) == 4)
    @assert(m.at(1, 2) == 6)
}

#test
{
    var m: Matrix'(f64, 3, 2) = {data: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]}
    @assert(m.rows() == 3)
    @assert(m.cols() == 2)
    @assert(m.at(0, 0) == 1.0)
    @assert(m.at(2, 1) == 6.0)
}

// Type assertions on nested generics
#test
{
    let outer: OuterBox'u16
    #assert(#typeof(outer.middle.inner.value) == u16)

    let h: HeteroHolder'(s32, f64)
    #assert(#typeof(h.left.value) == s32)
    #assert(#typeof(h.right.value) == f64)

    let bb: BoxOfBox'u8
    #assert(#typeof(bb.inner.value.value) == u8)
}

struct(T) GenericAnonymousStructHolder
{
    using data: struct
    {
        value: T
        count: u32
    }
}

struct(T) GenericAnonymousUnionHolder
{
    using data: union
    {
        value: T
        other: T
    }
}

#test
{
    var st: GenericAnonymousStructHolder's32
    st.value = 42
    st.count = 1
    @assert(st.data.value == 42)
    @assert(st.count == 1)

    var un: GenericAnonymousUnionHolder'u32
    un.value = 42
    @assert(un.data.value == 42)
}
