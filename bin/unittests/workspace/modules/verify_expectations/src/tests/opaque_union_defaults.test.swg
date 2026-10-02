#global if #command == Swag.CompilerCommand.Test
#global private

const OPAQUE_SPARSE_UNION_CONSTANT: StaticApi.OpaqueSparseUnion = {}
var opaqueSparseUnionGlobal: StaticApi.OpaqueSparseUnion

#test
{
    Swag.assert(StaticApi.opaqueUnionSourceControl())
    #assert(#sizeof(StaticApi.OpaqueSparseUnion) == 136)
    #assert(#alignof(StaticApi.OpaqueSparseUnion) == 8)
    #assert(#sizeof(StaticApi.OpaqueTextUnion) == 152)
    #assert(#sizeof(StaticApi.OpaquePointerUnion) == 8)
    Swag.assert(OPAQUE_SPARSE_UNION_CONSTANT.isDefault())
    Swag.assert(opaqueSparseUnionGlobal.isDefault())
}

#test
{
    var value: StaticApi.OpaqueSparseUnion
    let literal = StaticApi.OpaqueSparseUnion{}
    Swag.assert(value.isDefault())
    Swag.assert(literal.isDefault())
    value.change()
    value = {}
    Swag.assert(value.isDefault())
    var values: [2] StaticApi.OpaqueSparseUnion
    values[0].change()
    Swag.init(&values)
    Swag.assert(values[0].isDefault())
    Swag.assert(values[1].isDefault())
}

// Relocated union defaults use the provider's complete initialization function.
#test
{
    var value: StaticApi.OpaqueTextUnion
    let literal = StaticApi.OpaqueTextUnion{}
    Swag.assert(value.isDefault())
    Swag.assert(literal.isDefault())
    value.change()
    value = {}
    Swag.assert(value.isDefault())
    var values: [2] StaticApi.OpaqueTextUnion
    values[1].change()
    Swag.init(&values)
    Swag.assert(values[0].isDefault())
    Swag.assert(values[1].isDefault())
}

#test
{
    var value: StaticApi.OpaquePointerUnion
    let literal = StaticApi.OpaquePointerUnion{}
    Swag.assert(value.isDefault())
    Swag.assert(literal.isDefault())
    value.change()
    value = {}
    Swag.assert(value.isDefault())
    value.change()
    Swag.init(&value)
    Swag.assert(value.isDefault())
}

#test
{
    let sparseInfo = cast(const *Swag.TypeInfoStruct) #typeof(StaticApi.OpaqueSparseUnion)
    let textInfo   = cast(const *Swag.TypeInfoStruct) #typeof(StaticApi.OpaqueTextUnion)
    Swag.assert(sparseInfo.opInit != null)
    Swag.assert(textInfo.opInit != null)
    var sparse: StaticApi.OpaqueSparseUnion
    var text:   StaticApi.OpaqueTextUnion
    sparse.change()
    text.change()
    let initSparse = sparseInfo.opInit
    let initText   = textInfo.opInit
    initSparse(&sparse)
    initText(&text)
    Swag.assert(sparse.isDefault())
    Swag.assert(text.isDefault())
}

func rejectOpaqueUnionPointerConstant()
{
    const value: StaticApi.OpaquePointerUnion = {}     // swc-expected-error {{sema_err_expr_not_const}}
}
