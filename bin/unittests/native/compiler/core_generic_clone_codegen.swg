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
    for value in slice do
        total += value

    var ptrs: GenericCloneCodegenSupport.PtrBox's32
    ptrs.values.reserve(4)
    ptrs.addNew(4)
    ptrs.addNew(5)
    ptrs.clear()

    var owned: GenericCloneCodegenSupport.OwnedPtrVisitBox's32
    owned.addNew(6)
    owned.addNew(7)
    if dref owned.first != 6 or dref owned.second != 7 do
        return false
    owned.clearOwned()
    if owned.count != 0 do
        return false

    values.free()
    ptrs.values.free()
    return total == 6 and ptrs.values.count == 0
}

#test
{
    @assert(exerciseGenericCloneCodegen())
}
