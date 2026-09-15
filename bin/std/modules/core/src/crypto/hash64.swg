#global namespace Hash

using Swag

// Dynamic identities describe storage ownership, not the value used as a key.
// Visit fields only for aggregates that contain such identities; ordinary
// values keep the contiguous byte hashing path.
#[ConstExpr, Safety(.All, false)]
private func hashDynamicStorage(type: typeinfo, data: const [*] u8)->u64
{
    if not Reflection.hasDynamicStorage(type) do
        return murmur3(data, type.sizeof, 0)
    switch type.kind
    {
    case .Alias:
        let info = cast #assume(const *TypeInfoAlias) type
        return hashDynamicStorage(info.rawType, data)

    case .Array, .TypeListArray:
        let info   = cast #assume(const *TypeInfoArray) type
        var result = 0'u64
        for i in info.count do
            result = murmur3(result, hashDynamicStorage(info.pointedType, data + i * info.pointedType.sizeof))
        return result

    case .Struct, .TypeListTuple:
        let info   = cast #assume(const *TypeInfoStruct) type
        var result = 0'u64
        for field in info.fields do
            result = murmur3(result, hashDynamicStorage(field.pointedType!, data + field.offset))
        return result

    default:
        unreachable
    }
}

// Defines the operations supported by i hash64.
public interface IHash64
{
    // Defines compute.
    mtd const compute()->u64
}

// Hash the given value and returns the corresponding u64
#[ConstExpr, Safety(.All, false)]
public func(T) hash64(value: T)->u64
{
    #static if Reflection.isString(T) do
        return Hash.murmur3(value.buffer, value.count, 0)
    elif Reflection.isStruct(T) and #defined(T.IHash64) do
        #ast("return ", #typeof(T).fullname, ".IHash64.compute(value)")
    elif Reflection.isStruct(T) and #defined(T.IHash32) do
        #ast("return ", #typeof(T).fullname, ".IHash32.compute(value)")
    elif Reflection.hasDynamicStorage(T) do
        return hashDynamicStorage(T, cast(const [*] u8) &value)
    elif Reflection.isStruct(T) do
        return Hash.murmur3(cast(const [*] u8) &value, #sizeof(T), 0)
    elif #sizeof(T) == 8 do
        return murmur3(cast #bit (u64) value)
    elif #sizeof(T) == 4 do
        return murmur3(cast #bit (u32) value)
    elif Reflection.isInteger(T) do
        return murmur3(cast(u64) value)
    else do
        return 0
}
