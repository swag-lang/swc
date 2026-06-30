#global public
#global namespace Reflection
using Swag

// Returns true if this is a struct of the given 'name'.
#[ConstExpr]
func isStructOfName(type: typeinfo, name: string)->bool
{
    if !isStruct(type) do
        return false

    let typeStruct = cast(const *TypeInfoStruct) type
    return typeStruct.structName == name
}

// Get information about a specific method in a given struct.
// Returns null if the method does not exist
#[ConstExpr]
func getMethod(type: typeinfo, name: string)->#null const *TypeValue
{
    if !isStruct(type) do
        return null

    let typeStruct = cast(const *TypeInfoStruct) type
    foreach &it in typeStruct.methods where it.name == name do
        return it
    return null
}

// Get information about a specific field in a given struct
// Returns null if the field does not exist
#[ConstExpr]
func getField(type: typeinfo, name: string)->#null const *TypeValue
{
    if !isStruct(type) do
        return null

    let typeStruct = cast(const *TypeInfoStruct) type
    foreach &it in typeStruct.fields where it.name == name do
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
func getFieldValue(dest: *void, type: const *TypeValue, src: *void, hardCast: bool = false)
{
    let patch = cast([*] u8) src + type.offset
    switch type.pointedType
    {
    case s8, u8, bool:
        dref cast(*u8) dest = dref cast(*u8) patch
    case s16, u16:
        dref cast(*u16) dest = dref cast(*u16) patch
    case s32, u32, f32, rune:
        dref cast(*u32) dest = dref cast(*u32) patch
    case s64, u64, f64:
        dref cast(*u64) dest = dref cast(*u64) patch
    case string:
        dref cast(*string) dest = dref cast(*string) patch
    default:
        if !hardCast do
            Debug.assert(false, "unsupported getFieldValue type")
        switch type.pointedType.sizeof
        {
        case 1:
            dref cast(*u8) dest = dref cast(*u8) patch
        case 2:
            dref cast(*u16) dest = dref cast(*u16) patch
        case 4:
            dref cast(*u32) dest = dref cast(*u32) patch
        case 8:
            dref cast(*u64) dest = dref cast(*u64) patch
        default:
            Debug.assert(false, "unsupported getFieldValue type")
        }
    }
}

// Set a field value with a given runtime type.
#[ConstExpr]
func setFieldValue(dest: *void, type: const *TypeValue, src: const *void, hardCast: bool = false)
{
    var patch = cast([*] u8) dest + type.offset
    switch type.pointedType
    {
    case s8, u8, bool:
        dref cast(*u8) patch = dref cast(const *u8) src
    case s16, u16:
        dref cast(*u16) patch = dref cast(const *u16) src
    case s32, u32, f32, rune:
        dref cast(*u32) patch = dref cast(const *u32) src
    case s64, u64, f64:
        dref cast(*u64) patch = dref cast(const *u64) src
    case string:
        dref cast(*string) patch = dref cast(const *string) src
    default:
        if !hardCast do
            Debug.assert(false, "unsupported setFieldValue type")
        switch type.pointedType.sizeof
        {
        case 1:
            dref cast(*u8) patch = dref cast(const *u8) src
        case 2:
            dref cast(*u16) patch = dref cast(const *u16) src
        case 4:
            dref cast(*u32) patch = dref cast(const *u32) src
        case 8:
            dref cast(*u64) patch = dref cast(const *u64) src
        default:
            Debug.assert(false, "unsupported setFieldValue type")
        }
    }
}

// Helper function to know if a struct has a special method
#[ConstExpr]
func hasMethod(type: typeinfo, name: string)->bool => getMethod(type, name) != null

// Returns true if values of that type can use the default '<=>' comparison.
#[ConstExpr]
func canCompare(type: typeinfo)->bool
{
    switch type.kind
    {
    case .Alias:
        let typeAlias = cast(const *TypeInfoAlias) type
        return canCompare(typeAlias.rawType)
    case .Enum:
        let typeEnum = cast(const *TypeInfoEnum) type
        return canCompare(typeEnum.rawType)
    case .Pointer:
        return true
    case .Native:
        let typeNative = cast(const *TypeInfoNative) type
        switch typeNative.nativeKind
        {
        case .S8, .S16, .S32, .S64, .U8, .U16, .U32, .U64, .F32, .F64, .Rune, .String:
            return true
        default:
            return false
        }
    case .Struct:
        return true
    default:
        return false
    }
}

#[ConstExpr, Inline]
{
    func hasDrop(type: typeinfo)->bool     => (type.flags & TypeInfoFlags.HasDrop) ? true : false
    func hasPostMove(type: typeinfo)->bool => (type.flags & TypeInfoFlags.HasPostMove) ? true : false
    func hasPostCopy(type: typeinfo)->bool => (type.flags & TypeInfoFlags.HasPostCopy) ? true : false
    func canCopy(type: typeinfo)->bool     => (type.flags & TypeInfoFlags.CanCopy) ? true : false
    func isPod(type: typeinfo)->bool       => (type.flags & (TypeInfoFlags.HasDrop | TypeInfoFlags.HasPostMove | TypeInfoFlags.HasPostCopy) ? false : true)
}

// Returns true if the interface 'itf' is implemented in the given structure type.
#[ConstExpr]
func hasInterface(type: typeinfo, itf: typeinfo)->bool
{
    if !isStruct(type) do
        return false

    let typeStruct = cast(const *TypeInfoStruct) type
    foreach it in typeStruct.interfaces where it.name == itf.fullname do
        return true
    return false
}
