#global if #command == Swag.CompilerCommand.Test
#global private

union RuntimeDefaultUnion
{
    ignored: u64
    value:   StaticApi.OpaqueDefaultPointer
}

const OPAQUE_SCALAR_CONSTANT: StaticApi.OpaqueDefaultScalar   = StaticApi.OpaqueDefaultScalar{}
const OPAQUE_TEXT_CONSTANT:   StaticApi.OpaqueDefaultText     = StaticApi.OpaqueDefaultText{}
const OPAQUE_NESTED_CONSTANT: StaticApi.OpaqueDefaultNested   = StaticApi.OpaqueDefaultNested{}
const OPAQUE_ARRAY_CONSTANT:  [2] StaticApi.OpaqueDefaultText = [StaticApi.OpaqueDefaultText{}]

var opaqueScalarGlobal: StaticApi.OpaqueDefaultScalar
var opaqueTextGlobal:   StaticApi.OpaqueDefaultText
var opaqueNestedGlobal: StaticApi.OpaqueDefaultNested
var opaqueArrayGlobal:  [2] StaticApi.OpaqueDefaultText

// Both constant storage and mutable global storage must contain the provider's defaults.
#test
{
    Swag.require(OPAQUE_SCALAR_CONSTANT.isDefault())
    Swag.require(OPAQUE_TEXT_CONSTANT.isDefault())
    Swag.require(OPAQUE_NESTED_CONSTANT.isDefault())
    Swag.require(OPAQUE_ARRAY_CONSTANT[0].isDefault())
    Swag.require(OPAQUE_ARRAY_CONSTANT[1].isDefault())
    Swag.require(opaqueScalarGlobal.isDefault())
    Swag.require(opaqueTextGlobal.isDefault())
    Swag.require(opaqueNestedGlobal.isDefault())
    Swag.require(opaqueArrayGlobal[0].isDefault())
    Swag.require(opaqueArrayGlobal[1].isDefault())
}

// Implicit locals and explicit empty construction use the same imported initializer.
#test
{
    var scalar: StaticApi.OpaqueDefaultScalar
    var text:   StaticApi.OpaqueDefaultText
    var nested: StaticApi.OpaqueDefaultNested
    var array:  [2] StaticApi.OpaqueDefaultText
    Swag.require(scalar.isDefault())
    Swag.require(text.isDefault())
    Swag.require(nested.isDefault())
    Swag.require(array[0].isDefault())
    Swag.require(array[1].isDefault())
    let scalarLiteral = StaticApi.OpaqueDefaultScalar{}
    let textLiteral   = StaticApi.OpaqueDefaultText{}
    let nestedLiteral = StaticApi.OpaqueDefaultNested{}
    Swag.require(scalarLiteral.isDefault())
    Swag.require(textLiteral.isDefault())
    Swag.require(nestedLiteral.isDefault())
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
    Swag.require(scalar.isDefault())
    Swag.require(text.isDefault())
    Swag.require(nested.isDefault())
    text.change()
    nested.change()
    Swag.init(&text)
    Swag.init(&nested)
    Swag.require(text.isDefault())
    Swag.require(nested.isDefault())
}

// Provider-private addresses are initialized by the exported thunk and retain their identity.
#test
{
    var value:  StaticApi.OpaqueDefaultPointer
    let literal = StaticApi.OpaqueDefaultPointer{}
    var nested: StaticApi.OpaqueDefaultPointerNested
    var array:  [2] StaticApi.OpaqueDefaultPointer
    Swag.require(value.isDefault())
    Swag.require(literal.isDefault())
    Swag.require(nested.isDefault())
    Swag.require(array[0].isDefault())
    Swag.require(array[1].isDefault())
    value.change()
    nested.change()
    array[0].change()
    array[1].change()
    value  = {}
    nested = {}
    Swag.init(&array)
    Swag.require(value.isDefault())
    Swag.require(nested.isDefault())
    Swag.require(array[0].isDefault())
    Swag.require(array[1].isDefault())
    value.change()
    nested.change()
    Swag.init(&value)
    Swag.init(&nested)
    Swag.require(value.isDefault())
    Swag.require(nested.isDefault())
}

// A full initializer remains usable even when the opaque type has no implicit default.
#test
{
    let value = cast(StaticApi.OpaqueRequiredDefault, "ready")
    Swag.require(value.isReady())
}

// Empty element construction and omitted array elements keep the provider's address identity.
#test
{
    let implicit: StaticApi.OpaqueDefaultPointer
    var values:   [2] StaticApi.OpaqueDefaultPointer    = [StaticApi.OpaqueDefaultPointer{}]
    var matrix:   [2, 2] StaticApi.OpaqueDefaultPointer = [[{}]]
    Swag.require(implicit.isDefault())
    Swag.require(values[0].isDefault())
    Swag.require(values[1].isDefault())
    Swag.require(matrix[0, 0].isDefault())
    Swag.require(matrix[0, 1].isDefault())
    Swag.require(matrix[1, 0].isDefault())
    Swag.require(matrix[1, 1].isDefault())
    var fullMatrix: [2, 2] StaticApi.OpaqueDefaultPointer = [[{}, {}], [{}, {}]]
    Swag.require(fullMatrix[0, 0].isDefault())
    Swag.require(fullMatrix[0, 1].isDefault())
    Swag.require(fullMatrix[1, 0].isDefault())
    Swag.require(fullMatrix[1, 1].isDefault())
}

// Union fields overlap; the provider initializes the final field without a linear layout.
#test
{
    var value: RuntimeDefaultUnion
    Swag.require(value.value.isDefault())
    value.value.change()
    Swag.init(&value)
    Swag.require(value.value.isDefault())
}

// Supplied values stay unchanged while missing rows and elements receive their own defaults.
#test
{
    var changed: StaticApi.OpaqueDefaultPointer
    changed.change()
    var values: [2] StaticApi.OpaqueDefaultPointer    = [changed]
    var matrix: [2, 2] StaticApi.OpaqueDefaultPointer = [[changed]]
    Swag.require(not values[0].isDefault())
    Swag.require(values[1].isDefault())
    Swag.require(not matrix[0, 0].isDefault())
    Swag.require(matrix[0, 1].isDefault())
    Swag.require(matrix[1, 0].isDefault())
    Swag.require(matrix[1, 1].isDefault())
}
