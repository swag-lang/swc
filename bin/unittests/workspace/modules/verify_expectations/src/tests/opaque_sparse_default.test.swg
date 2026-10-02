#global if #command == Swag.CompilerCommand.Test
#global private

const OPAQUE_SPARSE_CONSTANT: StaticApi.OpaqueSparseDefault = {}
var opaqueSparseGlobal: StaticApi.OpaqueSparseDefault

#test
{
    #assert(#sizeof(StaticApi.OpaqueSparseDefault) == 17456)
    #assert(#alignof(StaticApi.OpaqueSparseDefault) == 16)
    Swag.assert(OPAQUE_SPARSE_CONSTANT.isDefault())
    Swag.assert(opaqueSparseGlobal.isDefault())
}

#test
{
    var value: StaticApi.OpaqueSparseDefault
    let literal = StaticApi.OpaqueSparseDefault{}
    Swag.assert(value.isDefault())
    Swag.assert(literal.isDefault())
    value.change()
    Swag.assert(not value.isDefault())
    value = {}
    Swag.assert(value.isDefault())
    value.change()
    Swag.init(&value)
    Swag.assert(value.isDefault())
}

#test
{
    var values: [2] StaticApi.OpaqueSparseDefault
    values[0].change()
    Swag.init(&values)
    Swag.assert(values[0].isDefault())
    Swag.assert(values[1].isDefault())
}
