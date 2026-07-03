#global private
using Swag

#[Swag.NoInline]
func exerciseGenericCloneCodegen()->bool
{
    var values: GenericCloneCodegenSupport.BufferBox's32
    values.reserve(8)
    values.add(1)
    values.add(2)
    values.add(3)

    let slice = values.toSlice()
    if @countof(slice) != 3 or slice[1] != 2 do
        return false

    var total = 0's32
    foreach value in slice do
        total += value

    var ptrs: GenericCloneCodegenSupport.PtrBox's32
    ptrs.values.reserve(4)
    ptrs.addNew(4)
    ptrs.addNew(5)
    ptrs.clear()

    values.free()
    ptrs.values.free()
    return total == 6 and ptrs.values.count == 0
}

#test
{
    @assert(exerciseGenericCloneCodegen())
}
