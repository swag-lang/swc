#global if #command == Swag.CompilerCommand.Test
#global private

const OPAQUE_SPARSE_UNION_CONSTANT: StaticApi.OpaqueSparseUnion = {}
var opaqueSparseUnionGlobal: StaticApi.OpaqueSparseUnion

#test
{
    Swag.require(StaticApi.opaqueUnionSourceControl())
    #assert(#sizeof(StaticApi.OpaqueSparseUnion) == 136)
    #assert(#alignof(StaticApi.OpaqueSparseUnion) == 8)
    #assert(#sizeof(StaticApi.OpaqueTextUnion) == 152)
    #assert(#sizeof(StaticApi.OpaquePointerUnion) == 8)
    Swag.require(OPAQUE_SPARSE_UNION_CONSTANT.isDefault())
    Swag.require(opaqueSparseUnionGlobal.isDefault())
}

#test
{
    var value: StaticApi.OpaqueSparseUnion
    let literal = StaticApi.OpaqueSparseUnion{}
    Swag.require(value.isDefault())
    Swag.require(literal.isDefault())
    value.change()
    value = {}
    Swag.require(value.isDefault())
    var values: [2] StaticApi.OpaqueSparseUnion
    values[0].change()
    Swag.init(&values)
    Swag.require(values[0].isDefault())
    Swag.require(values[1].isDefault())
}

// Relocated union defaults use the provider's complete initialization function.
#test
{
    var value: StaticApi.OpaqueTextUnion
    let literal = StaticApi.OpaqueTextUnion{}
    Swag.require(value.isDefault())
    Swag.require(literal.isDefault())
    value.change()
    value = {}
    Swag.require(value.isDefault())
    var values: [2] StaticApi.OpaqueTextUnion
    values[1].change()
    Swag.init(&values)
    Swag.require(values[0].isDefault())
    Swag.require(values[1].isDefault())
}

#test
{
    var value: StaticApi.OpaquePointerUnion
    let literal = StaticApi.OpaquePointerUnion{}
    Swag.require(value.isDefault())
    Swag.require(literal.isDefault())
    value.change()
    value = {}
    Swag.require(value.isDefault())
    value.change()
    Swag.init(&value)
    Swag.require(value.isDefault())
}

#test
{
    let sparseInfo = cast(const *Swag.TypeInfoStruct, #typeof(StaticApi.OpaqueSparseUnion))
    let textInfo   = cast(const *Swag.TypeInfoStruct, #typeof(StaticApi.OpaqueTextUnion))
    Swag.require(sparseInfo.opInit != null)
    Swag.require(textInfo.opInit != null)
    var sparse: StaticApi.OpaqueSparseUnion
    var text:   StaticApi.OpaqueTextUnion
    sparse.change()
    text.change()
    let initSparse = sparseInfo.opInit
    let initText   = textInfo.opInit
    initSparse(&sparse)
    initText(&text)
    Swag.require(sparse.isDefault())
    Swag.require(text.isDefault())
}

func rejectOpaqueUnionPointerConstant()
{
    const value: StaticApi.OpaquePointerUnion = {}     // swc-expected-error {{sema_err_expr_not_const}}
}
