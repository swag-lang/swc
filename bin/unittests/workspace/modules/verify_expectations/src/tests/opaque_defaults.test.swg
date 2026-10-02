#global if #command == Swag.CompilerCommand.Test
#global private

union RuntimeDefaultUnion
{
    ignored: u64
    value:   StaticApi.OpaqueDefaultPointer
}

const OPAQUE_SCALAR_CONSTANT: StaticApi.OpaqueDefaultScalar   = {}
const OPAQUE_TEXT_CONSTANT:   StaticApi.OpaqueDefaultText     = {}
const OPAQUE_NESTED_CONSTANT: StaticApi.OpaqueDefaultNested   = {}
const OPAQUE_ARRAY_CONSTANT:  [2] StaticApi.OpaqueDefaultText = [{}]

var opaqueScalarGlobal: StaticApi.OpaqueDefaultScalar
var opaqueTextGlobal:   StaticApi.OpaqueDefaultText
var opaqueNestedGlobal: StaticApi.OpaqueDefaultNested
var opaqueArrayGlobal:  [2] StaticApi.OpaqueDefaultText

// Both constant storage and mutable global storage must contain the provider's defaults.
#test
{
    Swag.assert(OPAQUE_SCALAR_CONSTANT.isDefault())
    Swag.assert(OPAQUE_TEXT_CONSTANT.isDefault())
    Swag.assert(OPAQUE_NESTED_CONSTANT.isDefault())
    Swag.assert(OPAQUE_ARRAY_CONSTANT[0].isDefault())
    Swag.assert(OPAQUE_ARRAY_CONSTANT[1].isDefault())
    Swag.assert(opaqueScalarGlobal.isDefault())
    Swag.assert(opaqueTextGlobal.isDefault())
    Swag.assert(opaqueNestedGlobal.isDefault())
    Swag.assert(opaqueArrayGlobal[0].isDefault())
    Swag.assert(opaqueArrayGlobal[1].isDefault())
}

// Implicit locals and explicit empty construction use the same imported initializer.
#test
{
    var scalar: StaticApi.OpaqueDefaultScalar
    var text:   StaticApi.OpaqueDefaultText
    var nested: StaticApi.OpaqueDefaultNested
    var array:  [2] StaticApi.OpaqueDefaultText
    Swag.assert(scalar.isDefault())
    Swag.assert(text.isDefault())
    Swag.assert(nested.isDefault())
    Swag.assert(array[0].isDefault())
    Swag.assert(array[1].isDefault())
    let scalarLiteral = StaticApi.OpaqueDefaultScalar{}
    let textLiteral   = StaticApi.OpaqueDefaultText{}
    let nestedLiteral = StaticApi.OpaqueDefaultNested{}
    Swag.assert(scalarLiteral.isDefault())
    Swag.assert(textLiteral.isDefault())
    Swag.assert(nestedLiteral.isDefault())
}

// Reset by assignment and the initialization intrinsic must preserve nested relocations too.
#test
{
    var scalar: StaticApi.OpaqueDefaultScalar
    var text:   StaticApi.OpaqueDefaultText
    var nested: StaticApi.OpaqueDefaultNested
    scalar.change()
    text.change()
    nested.change()
    scalar = {}
    text   = {}
    nested = {}
    Swag.assert(scalar.isDefault())
    Swag.assert(text.isDefault())
    Swag.assert(nested.isDefault())
    text.change()
    nested.change()
    Swag.init(&text)
    Swag.init(&nested)
    Swag.assert(text.isDefault())
    Swag.assert(nested.isDefault())
}

// Provider-private addresses are initialized by the exported thunk and retain their identity.
#test
{
    var value:  StaticApi.OpaqueDefaultPointer
    let literal = StaticApi.OpaqueDefaultPointer{}
    var nested: StaticApi.OpaqueDefaultPointerNested
    var array:  [2] StaticApi.OpaqueDefaultPointer
    Swag.assert(value.isDefault())
    Swag.assert(literal.isDefault())
    Swag.assert(nested.isDefault())
    Swag.assert(array[0].isDefault())
    Swag.assert(array[1].isDefault())
    value.change()
    nested.change()
    array[0].change()
    array[1].change()
    value  = {}
    nested = {}
    Swag.init(&array)
    Swag.assert(value.isDefault())
    Swag.assert(nested.isDefault())
    Swag.assert(array[0].isDefault())
    Swag.assert(array[1].isDefault())
    value.change()
    nested.change()
    Swag.init(&value)
    Swag.init(&nested)
    Swag.assert(value.isDefault())
    Swag.assert(nested.isDefault())
}

// A full initializer remains usable even when the opaque type has no implicit default.
#test
{
    let value = cast(StaticApi.OpaqueRequiredDefault) "ready"
    Swag.assert(value.isReady())
}

// Empty element construction and omitted array elements keep the provider's address identity.
#test
{
    let implicit: StaticApi.OpaqueDefaultPointer
    var values:   [2] StaticApi.OpaqueDefaultPointer    = [{}]
    var matrix:   [2, 2] StaticApi.OpaqueDefaultPointer = [[{}]]
    Swag.assert(implicit.isDefault())
    Swag.assert(values[0].isDefault())
    Swag.assert(values[1].isDefault())
    Swag.assert(matrix[0, 0].isDefault())
    Swag.assert(matrix[0, 1].isDefault())
    Swag.assert(matrix[1, 0].isDefault())
    Swag.assert(matrix[1, 1].isDefault())
    var fullMatrix: [2, 2] StaticApi.OpaqueDefaultPointer = [[{}, {}], [{}, {}]]
    Swag.assert(fullMatrix[0, 0].isDefault())
    Swag.assert(fullMatrix[0, 1].isDefault())
    Swag.assert(fullMatrix[1, 0].isDefault())
    Swag.assert(fullMatrix[1, 1].isDefault())
}

// Union fields overlap; the provider initializes the final field without a linear layout.
#test
{
    var value: RuntimeDefaultUnion
    Swag.assert(value.value.isDefault())
    value.value.change()
    Swag.init(&value)
    Swag.assert(value.value.isDefault())
}

// Supplied values stay unchanged while missing rows and elements receive their own defaults.
#test
{
    var changed: StaticApi.OpaqueDefaultPointer
    changed.change()
    var values: [2] StaticApi.OpaqueDefaultPointer    = [changed]
    var matrix: [2, 2] StaticApi.OpaqueDefaultPointer = [[changed]]
    Swag.assert(not values[0].isDefault())
    Swag.assert(values[1].isDefault())
    Swag.assert(not matrix[0, 0].isDefault())
    Swag.assert(matrix[0, 1].isDefault())
    Swag.assert(matrix[1, 0].isDefault())
    Swag.assert(matrix[1, 1].isDefault())
}
