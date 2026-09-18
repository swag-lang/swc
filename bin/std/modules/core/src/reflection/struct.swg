#global public
#global namespace Reflection

using Swag

// Returns whether `type` is a struct whose name is `name`.
#[ConstExpr]
func isNamedStruct(type: typeinfo?, name: string?)->bool
{
    if not isStruct(type) do
        return false

    let typeStruct = cast #assume(const *TypeInfoStruct) type!
    return typeStruct.structName == name
}

// Returns the reflected method `name` of a struct type, or null when it does not exist.
#[ConstExpr]
func findMethod(type: typeinfo?, name: string?)->const *TypeValue?
{
    if not isStruct(type) do
        return null

    let typeStruct = cast #assume(const *TypeInfoStruct) type!
    for &it in typeStruct.methods where it.name == name do
        return it
    return null
}

// Returns the reflected field `name` of a struct type, or null when it does not exist.
#[ConstExpr]
func findField(type: typeinfo?, name: string?)->const *TypeValue?
{
    if not isStruct(type) do
        return null

    let typeStruct = cast #assume(const *TypeInfoStruct) type!
    for &it in typeStruct.fields where it.name == name do
        return it
    return null
}

// Returns the CRC of the field `name` of a struct type, or 0 when the field does not exist.
//
// The value is the `crc` the compiler exported in the field's [[Swag.TypeValue]], so a caller
// can switch on `item.typeValue.crc` without recomputing the hash.
#[ConstExpr]
func fieldCrc(type: typeinfo, name: string)->u32 => findField(type, name)?.crc orelse 0

// Copies the value of `field` from the struct at `source` into `destination`.
//
// The copy follows [[Core.Reflection.assign]]. Nothing happens when a pointer or the field type is null.
#[ConstExpr]
func readFieldValue(destination: *void?, field: const *TypeValue?, source: *void?)
{
    if not destination or not field or not source do
        return

    let fieldType = field.pointedType
    if not fieldType do
        return
    Reflection.assign(destination, cast([*] u8) source + field.offset, fieldType)
}

// Copies the value at `source` into `field` of the struct at `destination`.
//
// The copy follows [[Core.Reflection.assign]]. Nothing happens when a pointer or the field type is null.
#[ConstExpr]
func writeFieldValue(destination: *void?, field: const *TypeValue?, source: const *void?)
{
    if not destination or not field or not source do
        return

    let fieldType = field.pointedType
    if not fieldType do
        return
    Reflection.assign(cast([*] u8) destination + field.offset, source, fieldType)
}

// Returns whether a struct type has the method `name`.
#[ConstExpr]
func hasMethod(type: typeinfo?, name: string?)->bool => findMethod(type, name) != null

// Returns whether values of `type` can use the default `<=>` comparison.
#[ConstExpr]
func canCompare(type: typeinfo?)->bool
{
    if not type do
        return false

    switch type.kind
    {
    case .Alias:
        let typeAlias = cast #assume(const *TypeInfoAlias) type
        return canCompare(typeAlias.rawType)

    case .Enum:
        let typeEnum = cast #assume(const *TypeInfoEnum) type
        return canCompare(typeEnum.rawType)

    case .Pointer:
        return true

    case .Native:
        let typeNative = cast #assume(const *TypeInfoNative) type
        switch typeNative.nativeKind
        {
        case .S8, .S16, .S32, .S64, .U8, .U16, .U32, .U64, .F32, .F64, .Rune, .String: return true
        default: return false
        }

    case .Struct:
        return true

    default:
        return false
    }
}

#[ConstExpr, Inline]
{
    // Returns whether values of `type` must be dropped.
    func hasDrop(type: typeinfo?)->bool => type and (type.flags & TypeInfoFlags.HasDrop) ? true : false

    // Returns whether values of `type` need a post-move hook after their bytes are relocated.
    func hasPostMove(type: typeinfo?)->bool => type and (type.flags & TypeInfoFlags.HasPostMove) ? true : false

    // Returns whether values of `type` need a post-copy hook after their bytes are copied.
    func hasPostCopy(type: typeinfo?)->bool => type and (type.flags & TypeInfoFlags.HasPostCopy) ? true : false

    // Returns whether values of `type` contain identity slots managed by [[Swag.DynCast]], in embedded fields and array elements included.
    //
    // Initialize new storage and use typed assignments when copying a view of such a value into a
    // new complete object.
    func hasDynamicStorage(type: typeinfo?)->bool => type and (type.flags & TypeInfoFlags.HasDynamicStorage) ? true : false

    // Returns whether values of `type` can be copied.
    func canCopy(type: typeinfo?)->bool => type and (type.flags & TypeInfoFlags.CanCopy) ? true : false

    // Returns whether values of `type` are plain data that can be copied and relocated as raw bytes.
    //
    // A plain-data type has no drop, post-move, or post-copy hook and no dynamic identity storage.
    func isPod(type: typeinfo?)->bool
    {
        if not type do
            return false
        return type.flags & (TypeInfoFlags.HasDrop | TypeInfoFlags.HasPostMove | TypeInfoFlags.HasPostCopy | TypeInfoFlags.HasDynamicStorage) ? false : true
    }
}

// Returns whether a struct type implements the interface `itf`.
#[ConstExpr]
func hasInterface(type: typeinfo?, itf: typeinfo)->bool
{
    if not isStruct(type) do
        return false

    let typeStruct = cast #assume(const *TypeInfoStruct) type!
    for it in typeStruct.interfaces
    {
        // Compare with the canonical crc so a '?'-qualified interface type matches the
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
