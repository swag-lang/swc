#global fileprivate

struct(T, N: s32 = 2) DefaultBuffer
{
    values: [N] T
}

struct(T = s32) DefaultBox
{
    value: T
}

struct(T) PtrHolder
{
    ptr: *T
}

#test
{
    let partial: DefaultBuffer'u16 = {values: [10'u16, 20]}
    @assert(partial.values[0] == 10'u16)
    @assert(partial.values[1] == 20'u16)
    #assert(#typeof(partial.values) == #type [2] u16)

    let explicit: DefaultBuffer'(s32, 3) = {values: [1, 2, 3]}
    @assert(explicit.values[2] == 3)

    let bools: DefaultBuffer'(bool, 3) = {values: [true, false, true]}
    @assert(bools.values[1] == false)

    let defBox: DefaultBox = {value: 42}
    @assert(defBox.value == 42)
    #assert(#typeof(defBox.value) == s32)

    let defBoxF: DefaultBox'f64 = {value: 1.5}
    @assert(defBoxF.value == 1.5)
    #assert(#typeof(defBoxF.value) == f64)
}

#test
{
    var x: s32 = 42
    let holder: PtrHolder's32 = {ptr: &x}
    @assert(dref holder.ptr == 42)

    var y: f64 = 1.5
    let holderF: PtrHolder'f64 = {ptr: &y}
    @assert(dref holderF.ptr == 1.5)
}
