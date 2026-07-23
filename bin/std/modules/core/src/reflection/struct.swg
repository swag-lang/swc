#global public
#global namespace Reflection

using Swag

// Returns true if this is a struct of the given 'name'.
#[ConstExpr]
func isStructOfName(type: #null typeinfo, name: #null string)->bool
{
    if !isStruct(type) do
        return false

    let typeStruct = cast(const *TypeInfoStruct) notnull type
    return typeStruct.structName == name
}

// Get information about a specific method in a given struct.
// Returns null if the method does not exist
#[ConstExpr]
func getMethod(type: #null typeinfo, name: #null string)->#null const *TypeValue
{
    if !isStruct(type) do
        return null

    let typeStruct = cast(const *TypeInfoStruct) notnull type
    for &it in typeStruct.methods where it.name == name do
        return it
    return null
}

// Get information about a specific field in a given struct
// Returns null if the field does not exist
#[ConstExpr]
func getField(type: #null typeinfo, name: #null string)->#null const *TypeValue
{
    if !isStruct(type) do
        return null

    let typeStruct = cast(const *TypeInfoStruct) notnull type
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
    let f = getField(type, name)
    return f ? f.crc : 0
}

// Get a field value with a given runtime type.
#[ConstExpr]
func getFieldValue(dest: #null *void, type: #null const *TypeValue, src: #null *void, hardCast: bool = false)
{
    if !dest or !type or !src do
        return

    let nnType = type
    let patch  = cast([*] u8) (src) + nnType.offset
    let nnDest = dest
    switch nnType.pointedType
    {
    case s8, u8, bool:
        dref cast(*u8) nnDest = dref cast(*u8) patch

    case s16, u16:
        dref cast(*u16) nnDest = dref cast(*u16) patch

    case s32, u32, f32, rune:
        dref cast(*u32) nnDest = dref cast(*u32) patch

    case s64, u64, f64:
        dref cast(*u64) nnDest = dref cast(*u64) patch

    case string:
        dref cast(*#null string) nnDest = dref cast(*#null string) patch

    default:
        if !hardCast do
            Debug.assert(false, "unsupported getFieldValue type")
        switch nnType.pointedType.sizeof
        {
        case 1:  dref cast(*u8) nnDest = dref cast(*u8) patch
        case 2:  dref cast(*u16) nnDest = dref cast(*u16) patch
        case 4:  dref cast(*u32) nnDest = dref cast(*u32) patch
        case 8:  dref cast(*u64) nnDest = dref cast(*u64) patch
        default: Debug.assert(false, "unsupported getFieldValue type")
        }
    }
}

// Set a field value with a given runtime type.
#[ConstExpr]
func setFieldValue(dest: *void, type: #null const *TypeValue, src: const *void, hardCast: bool = false)
{
    if !dest or !type or !src do
        return

    let nnType = type
    var patch  = cast([*] u8) (dest) + nnType.offset
    let nnSrc  = src
    switch nnType.pointedType
    {
    case s8, u8, bool:
        dref cast(*u8) patch = dref cast(const *u8) nnSrc

    case s16, u16:
        dref cast(*u16) patch = dref cast(const *u16) nnSrc

    case s32, u32, f32, rune:
        dref cast(*u32) patch = dref cast(const *u32) nnSrc

    case s64, u64, f64:
        dref cast(*u64) patch = dref cast(const *u64) nnSrc

    case string:
        dref cast(*#null string) patch = dref cast(const *#null string) nnSrc

    default:
        if !hardCast do
            Debug.assert(false, "unsupported setFieldValue type")
        switch nnType.pointedType.sizeof
        {
        case 1:  dref cast(*u8) patch = dref cast(const *u8) nnSrc
        case 2:  dref cast(*u16) patch = dref cast(const *u16) nnSrc
        case 4:  dref cast(*u32) patch = dref cast(const *u32) nnSrc
        case 8:  dref cast(*u64) patch = dref cast(const *u64) nnSrc
        default: Debug.assert(false, "unsupported setFieldValue type")
        }
    }
}

// Helper function to know if a struct has a special method
#[ConstExpr]
func hasMethod(type: #null typeinfo, name: #null string)->bool => getMethod(type, name) != null

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
    func hasDrop(type: #null typeinfo)->bool     => type and (type.flags & TypeInfoFlags.HasDrop) ? true : false
    func hasPostMove(type: #null typeinfo)->bool => type and (type.flags & TypeInfoFlags.HasPostMove) ? true : false
    func hasPostCopy(type: #null typeinfo)->bool => type and (type.flags & TypeInfoFlags.HasPostCopy) ? true : false
    func canCopy(type: typeinfo)->bool           => type and (type.flags & TypeInfoFlags.CanCopy) ? true : false

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

    let typeStruct = cast(const *TypeInfoStruct) notnull type
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
