#global if #command == Swag.CompilerCommand.Test
#global private

const OPAQUE_SPARSE_CONSTANT: StaticApi.OpaqueSparseDefault = StaticApi.OpaqueSparseDefault{}
var opaqueSparseGlobal: StaticApi.OpaqueSparseDefault

#test
{
    #assert(#sizeof(StaticApi.OpaqueSparseDefault) == 17456)
    #assert(#alignof(StaticApi.OpaqueSparseDefault) == 16)
    Swag.require(OPAQUE_SPARSE_CONSTANT.isDefault())
    Swag.require(opaqueSparseGlobal.isDefault())
}

#test
{
    var value: StaticApi.OpaqueSparseDefault
    let literal = StaticApi.OpaqueSparseDefault{}
    Swag.require(value.isDefault())
    Swag.require(literal.isDefault())
    value.change()
    Swag.require(not value.isDefault())
    value = {}
    Swag.require(value.isDefault())
    value.change()
    Swag.init(&value)
    Swag.require(value.isDefault())
}

#test
{
    var values: [2] StaticApi.OpaqueSparseDefault
    values[0].change()
    Swag.init(&values)
    Swag.require(values[0].isDefault())
    Swag.require(values[1].isDefault())
}
