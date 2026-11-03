#global private

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
    Swag.require(partial.values[0] == 10'u16)
    Swag.require(partial.values[1] == 20'u16)
    #assert(#typeof(partial.values) == #type [2] u16)

    let explicit: DefaultBuffer'(s32, 3) = {values: [1, 2, 3]}
    Swag.require(explicit.values[2] == 3)

    let bools: DefaultBuffer'(bool, 3) = {values: [true, false, true]}
    Swag.require(bools.values[1] == false)

    let defBox: DefaultBox = {value: 42}
    Swag.require(defBox.value == 42)
    #assert(#typeof(defBox.value) == s32)

    let defBoxF: DefaultBox'f64 = {value: 1.5}
    Swag.require(defBoxF.value == 1.5)
    #assert(#typeof(defBoxF.value) == f64)
}

#test
{
    var x:      s32 = 42
    let holder: PtrHolder's32 = {ptr: &x}
    Swag.require(holder.ptr[] == 42)

    var y:       f64 = 1.5
    let holderF: PtrHolder'f64 = {ptr: &y}
    Swag.require(holderF.ptr[] == 1.5)
}
