#global namespace Memory
using Swag

internal func concreteRuntimeType(type: typeinfo)->typeinfo
{
    var result = type
    while result.kind == TypeInfoKind.Alias
    {
        let typeAlias = cast(const *TypeInfoAlias) result
        result = typeAlias.rawType
    }

    return result
}

internal func canDefaultInit(type: typeinfo)->bool
{
    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast(const *TypeInfoArray) concreteType
        if !typeArray.count do
            return true
        if type.flags & TypeInfoFlags.RequiresExplicitInit do
            return false
        return canDefaultInit(typeArray.pointedType)
    }

    if type.flags & TypeInfoFlags.RequiresExplicitInit do
        return false
    if concreteType.kind != TypeInfoKind.Struct do
        return true

    let typeStruct = cast(const *TypeInfoStruct) concreteType
    if typeStruct.opInit do
        return true
    if !(concreteType.flags & TypeInfoFlags.Tuple) do
        return false

    for field in typeStruct.fields
    {
        if !canDefaultInit(field.pointedType) do
            return false
    }

    return true
}

internal func defaultInit(dst: *void, type: typeinfo)
{
    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast(const *TypeInfoArray) concreteType
        var scan      = cast([*] u8) dst
        for typeArray.count
        {
            defaultInit(scan, typeArray.pointedType)
            scan += typeArray.pointedType.sizeof
        }
        return
    }

    if concreteType.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast(const *TypeInfoStruct) concreteType
        if typeStruct.opInit
        {
            typeStruct.opInit(dst)
            return
        }

        if !(concreteType.flags & TypeInfoFlags.Tuple)
        {
            Debug.assert(false)
            return
        }
        for field in typeStruct.fields do
            defaultInit(cast([*] u8) dst + field.offset, field.pointedType)
        return
    }

    clear(dst, cast(u64) concreteType.sizeof)
}

internal func dropType(dst: *void, type: typeinfo)
{
    if !(type.flags & TypeInfoFlags.HasDrop) do
        return

    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast(const *TypeInfoArray) concreteType
        var scan      = cast([*] u8) dst
        for typeArray.count
        {
            dropType(scan, typeArray.pointedType)
            scan += typeArray.pointedType.sizeof
        }
        return
    }

    if concreteType.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast(const *TypeInfoStruct) concreteType
        if typeStruct.opDrop
        {
            typeStruct.opDrop(dst)
            return
        }

        if concreteType.flags & TypeInfoFlags.Tuple
        {
            for #reverse field in typeStruct.fields do
                dropType(cast([*] u8) dst + field.offset, field.pointedType)
        }
    }
}

internal func postCopyType(dst: *void, type: typeinfo)
{
    if !(type.flags & TypeInfoFlags.HasPostCopy) do
        return

    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast(const *TypeInfoArray) concreteType
        var scan      = cast([*] u8) dst
        for typeArray.count
        {
            postCopyType(scan, typeArray.pointedType)
            scan += typeArray.pointedType.sizeof
        }
        return
    }

    if concreteType.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast(const *TypeInfoStruct) concreteType
        if typeStruct.opPostCopy
        {
            typeStruct.opPostCopy(dst)
            return
        }

        if concreteType.flags & TypeInfoFlags.Tuple
        {
            for field in typeStruct.fields do
                postCopyType(cast([*] u8) dst + field.offset, field.pointedType)
        }
    }
}

internal func postMoveType(dst: *void, type: typeinfo)
{
    if !(type.flags & TypeInfoFlags.HasPostMove) do
        return

    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast(const *TypeInfoArray) concreteType
        var scan      = cast([*] u8) dst
        for typeArray.count
        {
            postMoveType(scan, typeArray.pointedType)
            scan += typeArray.pointedType.sizeof
        }
        return
    }

    if concreteType.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast(const *TypeInfoStruct) concreteType
        if typeStruct.opPostMove
        {
            typeStruct.opPostMove(dst)
            return
        }

        if concreteType.flags & TypeInfoFlags.Tuple
        {
            for field in typeStruct.fields do
                postMoveType(cast([*] u8) dst + field.offset, field.pointedType)
        }
    }
}
