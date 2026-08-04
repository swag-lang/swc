#global public
#global namespace Reflection

using Swag

// Returns true if this is a struct of the given 'name'.
#[ConstExpr]
func isNamedStruct(type: #null typeinfo, name: #null string)->bool
{
    if !isStruct(type) do
        return false

    let typeStruct = cast(const *TypeInfoStruct) type!
    return typeStruct.structName == name
}

// Get information about a specific method in a given struct.
// Returns null if the method does not exist
#[ConstExpr]
func findMethod(type: #null typeinfo, name: #null string)->#null const *TypeValue
{
    if !isStruct(type) do
        return null

    let typeStruct = cast(const *TypeInfoStruct) type!
    for &it in typeStruct.methods where it.name == name do
        return it
    return null
}

// Get information about a specific field in a given struct
// Returns null if the field does not exist
#[ConstExpr]
func findField(type: #null typeinfo, name: #null string)->#null const *TypeValue
{
    if !isStruct(type) do
        return null

    let typeStruct = cast(const *TypeInfoStruct) type!
    for &it in typeStruct.fields where it.name == name do
        return it
    return null
}

// CRC of a struct field's name, read straight from the reflected TypeValue (the value the
// compiler exported in TypeValue.crc). Use it to switch on item.typeValue.crc without
// recomputing the hash. Returns 0 if the field does not exist.
#[ConstExpr]
func fieldCrc(type: typeinfo, name: string)->u32
{
    let f = findField(type, name)
    return f ? f.crc : 0
}

// Get a field value with a given runtime type.
#[ConstExpr]
func readFieldValue(destination: #null *void, field: #null const *TypeValue, source: #null *void)
{
    if !destination or !field or !source do
        return

    let fieldType = field.pointedType
    if !fieldType do
        return
    Reflection.assign(destination, cast([*] u8) source + field.offset, fieldType)
}

// Assigns a value to a reflected field while preserving its lifecycle semantics.
#[ConstExpr]
func writeFieldValue(destination: #null *void, field: #null const *TypeValue, source: #null const *void)
{
    if !destination or !field or !source do
        return

    let fieldType = field.pointedType
    if !fieldType do
        return
    Reflection.assign(cast([*] u8) destination + field.offset, source, fieldType)
}

// Helper function to know if a struct has a special method
#[ConstExpr]
func hasMethod(type: #null typeinfo, name: #null string)->bool => findMethod(type, name) != null

// Returns true if values of that type can use the default '<=>' comparison.
#[ConstExpr]
func canCompare(type: #null typeinfo)->bool
{
    if !type do
        return false

    let nnType = type
    switch nnType.kind
    {
    case .Alias:
        let typeAlias = cast(const *TypeInfoAlias) nnType
        return canCompare(typeAlias.rawType)

    case .Enum:
        let typeEnum = cast(const *TypeInfoEnum) nnType
        return canCompare(typeEnum.rawType)

    case .Pointer:
        return true

    case .Native:
        let typeNative = cast(const *TypeInfoNative) nnType
        switch typeNative.nativeKind
        {
        case .S8, .S16, .S32, .S64, .U8, .U16, .U32, .U64, .F32, .F64, .Rune, .String: return true
        default:                                                                       return false
        }

    case .Struct:
        return true

    default:
        return false
    }
}

#[ConstExpr, Inline]
{
    // Returns whether this value has drop.
    func hasDrop(type: #null typeinfo)->bool => type and (type.flags & TypeInfoFlags.HasDrop) ? true : false

    // Returns whether this value has post move.
    func hasPostMove(type: #null typeinfo)->bool => type and (type.flags & TypeInfoFlags.HasPostMove) ? true : false

    // Returns whether this value has post copy.
    func hasPostCopy(type: #null typeinfo)->bool => type and (type.flags & TypeInfoFlags.HasPostCopy) ? true : false

    // Returns whether this value can copy.
    func canCopy(type: typeinfo)->bool => type and (type.flags & TypeInfoFlags.CanCopy) ? true : false

    // Returns whether pod.
    func isPod(type: #null typeinfo)->bool
    {
        if !type do
            return false
        return type.flags & (TypeInfoFlags.HasDrop | TypeInfoFlags.HasPostMove | TypeInfoFlags.HasPostCopy) ? false : true
    }
}

// Returns true if the interface 'itf' is implemented in the given structure type.
#[ConstExpr]
func hasInterface(type: #null typeinfo, itf: typeinfo)->bool
{
    if !isStruct(type) do
        return false

    let typeStruct = cast(const *TypeInfoStruct) type!
    for it in typeStruct.interfaces
    {
        // Compare with the canonical crc so a '#null'-qualified interface type matches the
        // bare interface registered in the implementation list (same identity, different
        // nullability qualifier). Fall back to the name for entries without a pointed type.
        if it.pointedType
        {
            if it.pointedType.crc == itf.crc do
                return true
        }
        elif it.name == itf.fullname do
            return true
    }

    return false
}
