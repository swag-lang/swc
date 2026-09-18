#global namespace Memory

using Swag

internal func concreteRuntimeType(type: typeinfo)->typeinfo
{
    var result = type
    while result.kind == TypeInfoKind.Alias
    {
        let typeAlias = cast #assume(const *TypeInfoAlias) result
        result = typeAlias.rawType
    }

    return result
}

// Assignments retain the destination's identity, including identities nested in
// ordinary fields and arrays. Lifecycle hooks surround this storage copy.
internal func copyValueStorage(dst: *void, src: const *void, type: typeinfo)
{
    if not (type.flags & .HasDynamicStorage)
    {
        copy(dst, src, type.sizeof)
        return
    }

    let concreteType = concreteRuntimeType(type)
    let target       = cast([*] u8) dst
    let source       = cast(const [*] u8) src
    if concreteType.kind == .Array
    {
        let info = cast #assume(const *TypeInfoArray) concreteType
        for i in info.count
        {
            let offset = i * info.pointedType.sizeof
            copyValueStorage(target + offset, source + offset, info.pointedType)
        }

        return
    }

    let info = cast #assume(const *TypeInfoStruct) concreteType
    for field in info.fields do
        copyValueStorage(target + field.offset, source + field.offset, field.pointedType!)
}

private func resetDynamicSlots(dst: *void, type: const *TypeInfoStruct, index: u64)
{
    if index == type.dynamicSlots.count
    {
        dropType(dst, type)
        defaultInit(dst, type)
        return
    }

    // Keep each descriptor in the call frame; resetting needs no allocation.
    let address  = cast([*] u8) dst + type.dynamicSlots![index].offset
    let slot     = cast(*const *DynamicStructInfo) cast(*void) address
    let identity = slot[]
    resetDynamicSlots(dst, type, index + 1)
    slot[] = identity
}

internal func resetValueStorage(dst: *void, type: typeinfo)
{
    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == .Struct
    {
        let info = cast #assume(const *TypeInfoStruct) concreteType
        if info.dynamicSlots.count
        {
            resetDynamicSlots(dst, info, 0)
            return
        }
    }

    dropType(dst, type)
    defaultInit(dst, type)
}

internal func canDefaultInit(type: typeinfo)->bool
{
    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast #assume(const *TypeInfoArray) concreteType
        if not typeArray.count do
            return true
        if type.flags & TypeInfoFlags.RequiresExplicitInit do
            return false
        return canDefaultInit(typeArray.pointedType)
    }

    if type.flags & TypeInfoFlags.RequiresExplicitInit do
        return false
    if concreteType.kind != TypeInfoKind.Struct do
        return true

    let typeStruct = cast #assume(const *TypeInfoStruct) concreteType
    if typeStruct.opInit do
        return true
    if not (concreteType.flags & TypeInfoFlags.Tuple) do
        return false

    for field in typeStruct.fields
    {
        let pointedType = field.pointedType
        if not pointedType do
            return false
        if not canDefaultInit(pointedType orelse #typeof(u8)) do
            return false
    }

    return true
}

internal func defaultInit(dst: *void?, type: typeinfo)
{
    if not dst do
        return
    let data = dst

    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast #assume(const *TypeInfoArray) concreteType
        let valueType = typeArray.pointedType
        var scan      = cast([*] u8) data
        for typeArray.count
        {
            defaultInit(scan, valueType)
            scan += valueType.sizeof
        }

        return
    }

    if concreteType.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast #assume(const *TypeInfoStruct) concreteType
        if typeStruct.opInit
        {
            typeStruct.opInit(data)
            return
        }

        // Every struct gets a generated 'opInit' except one that requires explicit initialization,
        // which has no default value to write.
        if not (concreteType.flags & TypeInfoFlags.Tuple)
        {
            Swag.assert(false, "the type requires explicit initialization and has no default value")
            return
        }

        for field in typeStruct.fields
        {
            let pointedType = field.pointedType
            if not pointedType do
                return
            defaultInit(cast([*] u8) data + field.offset, pointedType orelse #typeof(u8))
        }

        return
    }

    clear(data, cast(u64) concreteType.sizeof)
}

internal func dropType(dst: *void?, type: typeinfo)
{
    if not dst do
        return
    let data = dst

    if not (type.flags & TypeInfoFlags.HasDrop) do
        return

    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast #assume(const *TypeInfoArray) concreteType
        let valueType = typeArray.pointedType
        var scan      = cast([*] u8) data
        for typeArray.count
        {
            dropType(scan, valueType)
            scan += valueType.sizeof
        }

        return
    }

    if concreteType.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast #assume(const *TypeInfoStruct) concreteType
        if typeStruct.opDrop
        {
            typeStruct.opDrop(data)
            return
        }

        if concreteType.flags & TypeInfoFlags.Tuple
        {
            for field in typeStruct.fields!.reversed()
            {
                let pointedType = field.pointedType
                if not pointedType do
                    return
                dropType(cast([*] u8) data + field.offset, pointedType orelse #typeof(u8))
            }
        }
    }
}

internal func postCopyType(dst: *void?, type: typeinfo)
{
    if not dst do
        return
    let data = dst

    if not (type.flags & TypeInfoFlags.HasPostCopy) do
        return

    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast #assume(const *TypeInfoArray) concreteType
        let valueType = typeArray.pointedType
        var scan      = cast([*] u8) data
        for typeArray.count
        {
            postCopyType(scan, valueType)
            scan += valueType.sizeof
        }

        return
    }

    if concreteType.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast #assume(const *TypeInfoStruct) concreteType
        if typeStruct.opPostCopy
        {
            typeStruct.opPostCopy(data)
            return
        }

        if concreteType.flags & TypeInfoFlags.Tuple
        {
            for field in typeStruct.fields
            {
                let pointedType = field.pointedType
                if not pointedType do
                    return
                postCopyType(cast([*] u8) data + field.offset, pointedType orelse #typeof(u8))
            }
        }
    }
}

internal func postMoveType(dst: *void?, type: typeinfo)
{
    if not dst do
        return
    let data = dst

    if not (type.flags & TypeInfoFlags.HasPostMove) do
        return

    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast #assume(const *TypeInfoArray) concreteType
        let valueType = typeArray.pointedType
        var scan      = cast([*] u8) data
        for typeArray.count
        {
            postMoveType(scan, valueType)
            scan += valueType.sizeof
        }

        return
    }

    if concreteType.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast #assume(const *TypeInfoStruct) concreteType
        if typeStruct.opPostMove
        {
            typeStruct.opPostMove(data)
            return
        }

        if concreteType.flags & TypeInfoFlags.Tuple
        {
            for field in typeStruct.fields
            {
                let pointedType = field.pointedType
                if not pointedType do
                    return
                postMoveType(cast([*] u8) data + field.offset, pointedType orelse #typeof(u8))
            }
        }
    }
}
