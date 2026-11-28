#global namespace Hash

using Swag

// Returns whether `type` contains a string value whose bytes define equality.
#[ConstExpr, Safety(.All, false)]
private func containsContentString(type: typeinfo)->bool
{
    if Reflection.isString(type) or type == Core.String
    {
        return true
    }

    switch type.kind
    {
    case .Alias:
        let info = assume cast(const *TypeInfoAlias, type)
        return containsContentString(info.rawType)

    case .Array, .TypeListArray:
        let info = assume cast(const *TypeInfoArray, type)
        return containsContentString(info.pointedType)

    case .Struct, .TypeListTuple:
        let info = assume cast(const *TypeInfoStruct, type)
        for field in info.fields
        {
            if field.pointedType and containsContentString(field.pointedType)
            {
                return true
            }
        }

    default:
        return false
    }

    return false
}

// The first two Core.String fields form this non-owning view. Copying the header avoids
// treating an embedded String as an owned local whose drop would release the original buffer.
private struct NativeStringView
{
    buffer: const [*] u8?
    count:  u64
}

#assert(#sizeof(NativeStringView) == #sizeof(string))

private struct OwnedStringView
{
    buffer: [*] u8?
    length: u64
}

// Hash dynamic identity fields and strings by their values instead of their storage addresses.
#[ConstExpr, Safety(.All, false)]
private func hashDynamicStorage(type: typeinfo, data: const [*] u8)->u64
{
    if type.kind == .Alias
    {
        let info = assume cast(const *TypeInfoAlias, type)
        return hashDynamicStorage(info.rawType, data)
    }

    if Reflection.isString(type)
    {
        var value: NativeStringView = {buffer: null, count: 0}
        Memory.copy(cast([*] void, &value), cast(const [*] void, data), #sizeof(value))
        if not value.count
        {
            return murmur3(data, 0, 0)
        }

        return murmur3(unwrap value.buffer, value.count, 0)
    }

    if type == Core.String
    {
        var value: OwnedStringView = {buffer: null, length: 0}
        Memory.copy(cast([*] void, &value), cast(const [*] void, data), #sizeof(value))
        if not value.length
        {
            return murmur3(data, 0, 0)
        }

        return murmur3(unwrap value.buffer, value.length, 0)
    }

    if not Reflection.hasDynamicStorage(type) and not containsContentString(type)
    {
        return murmur3(data, type.sizeof, 0)
    }

    switch type.kind
    {
    case .Array, .TypeListArray:
        let info   = assume cast(const *TypeInfoArray, type)
        var result = 0_u64
        for i in info.count
        {
            result = murmur3(result, hashDynamicStorage(info.pointedType, data + i * info.pointedType.sizeof))
        }

        return result

    case .Struct, .TypeListTuple:
        let info   = assume cast(const *TypeInfoStruct, type)
        var result = 0_u64
        for field in info.fields
        {
            result = murmur3(result, hashDynamicStorage(unwrap field.pointedType, data + field.offset))
        }

        return result

    default:
        unreachable
    }
}

// Lets a type supply its own 64-bit hash to [[Core.Hash.hash64]].
public interface IHash64
{
    // Returns the 64-bit hash of this value.
    mtd const compute()->u64
}

// Returns a 64-bit hash of `value`.
//
// A string and string fields hash their contents. A struct that implements [[Core.Hash.IHash64]]
// or [[Core.Hash.IHash32]] supplies its own hash; another struct hashes its bytes, skipping the
// dynamic identity slots it contains. Other values hash their bits.
#[ConstExpr, Safety(.All, false)]
public func(T) hash64(value: T)->u64
{
    #static if Reflection.isString(T)
    {
        return Hash.murmur3(value.buffer, value.count, 0)
    }
    else if Reflection.isStruct(T) and #defined(T.IHash64)
    {
        return T.IHash64.compute(value)
    }
    else if Reflection.isStruct(T) and #defined(T.IHash32)
    {
        return T.IHash32.compute(value)
    }
    else if Reflection.hasDynamicStorage(T) or containsContentString(T)
    {
        return hashDynamicStorage(T, cast(const [*] u8, &value))
    }
    else if Reflection.isStruct(T)
    {
        return Hash.murmur3(cast(const [*] u8, &value), #sizeof(T), 0)
    }
    else if Reflection.isFloat(T)
    {
        // IEEE-754 positive and negative zero compare equal, so they must share a hash.
        if value == 0
        {
            return murmur3(0_u64)
        }

        #static if #sizeof(T) == 8
        {
            return murmur3(cast #bit (u64, value))
        }
        else
        {
            return murmur3(cast #bit (u32, value))
        }
    }
    else if #sizeof(T) == 8
    {
        return murmur3(cast #bit (u64, value))
    }
    else if #sizeof(T) == 4
    {
        return murmur3(cast #bit (u32, value))
    }
    else if Reflection.isInteger(T)
    {
        return murmur3(cast(u64, value))
    }
    else
    {
        return murmur3(cast(const [*] u8, &value), #sizeof(T), 0)
    }
}
