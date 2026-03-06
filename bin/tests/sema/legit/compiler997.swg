// @FAIL
#global skip
#global fileprivate
using Swag

#test
{
    var array = [1, 2, 3]
    let ptr   = &array[0]
    let value = dref ptr
    @assert(value == 1)
}
