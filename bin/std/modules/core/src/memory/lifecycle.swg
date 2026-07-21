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
        let pointedType = typeArray.pointedType
        if !pointedType do
            return false
        return canDefaultInit(pointedType orelse #typeof(u8))
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
        let pointedType = field.pointedType
        if !pointedType do
            return false
        if !canDefaultInit(pointedType orelse #typeof(u8)) do
            return false
    }

    return true
}

internal func defaultInit(dst: #null *void, type: typeinfo)
{
    if !dst do
        return
    let data = dst

    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast(const *TypeInfoArray) concreteType
        var scan      = cast([*] u8) data
        for typeArray.count
        {
            let pointedType = typeArray.pointedType
            if !pointedType do
                return
            let valueType = pointedType orelse #typeof(u8)
            defaultInit(scan, valueType)
            scan += valueType.sizeof
        }
        return
    }

    if concreteType.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast(const *TypeInfoStruct) concreteType
        if typeStruct.opInit
        {
            typeStruct.opInit(data)
            return
        }

        if !(concreteType.flags & TypeInfoFlags.Tuple)
        {
            Debug.assert(false)
            return
        }
        for field in typeStruct.fields
        {
            let pointedType = field.pointedType
            if !pointedType do
                return
            defaultInit(cast([*] u8) data + field.offset, pointedType orelse #typeof(u8))
        }
        return
    }

    clear(data, cast(u64) concreteType.sizeof)
}

internal func dropType(dst: #null *void, type: typeinfo)
{
    if !dst do
        return
    let data = dst

    if !(type.flags & TypeInfoFlags.HasDrop) do
        return

    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast(const *TypeInfoArray) concreteType
        var scan      = cast([*] u8) data
        for typeArray.count
        {
            let pointedType = typeArray.pointedType
            if !pointedType do
                return
            let valueType = pointedType orelse #typeof(u8)
            dropType(scan, valueType)
            scan += valueType.sizeof
        }
        return
    }

    if concreteType.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast(const *TypeInfoStruct) concreteType
        if typeStruct.opDrop
        {
            typeStruct.opDrop(data)
            return
        }

        if concreteType.flags & TypeInfoFlags.Tuple
        {
            for #reverse field in typeStruct.fields
            {
                let pointedType = field.pointedType
                if !pointedType do
                    return
                dropType(cast([*] u8) data + field.offset, pointedType orelse #typeof(u8))
            }
        }
    }
}

internal func postCopyType(dst: #null *void, type: typeinfo)
{
    if !dst do
        return
    let data = dst

    if !(type.flags & TypeInfoFlags.HasPostCopy) do
        return

    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast(const *TypeInfoArray) concreteType
        var scan      = cast([*] u8) data
        for typeArray.count
        {
            let pointedType = typeArray.pointedType
            if !pointedType do
                return
            let valueType = pointedType orelse #typeof(u8)
            postCopyType(scan, valueType)
            scan += valueType.sizeof
        }
        return
    }

    if concreteType.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast(const *TypeInfoStruct) concreteType
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
                if !pointedType do
                    return
                postCopyType(cast([*] u8) data + field.offset, pointedType orelse #typeof(u8))
            }
        }
    }
}

internal func postMoveType(dst: #null *void, type: typeinfo)
{
    if !dst do
        return
    let data = dst

    if !(type.flags & TypeInfoFlags.HasPostMove) do
        return

    let concreteType = concreteRuntimeType(type)
    if concreteType.kind == TypeInfoKind.Array
    {
        let typeArray = cast(const *TypeInfoArray) concreteType
        var scan      = cast([*] u8) data
        for typeArray.count
        {
            let pointedType = typeArray.pointedType
            if !pointedType do
                return
            let valueType = pointedType orelse #typeof(u8)
            postMoveType(scan, valueType)
            scan += valueType.sizeof
        }
        return
    }

    if concreteType.kind == TypeInfoKind.Struct
    {
        let typeStruct = cast(const *TypeInfoStruct) concreteType
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
                if !pointedType do
                    return
                postMoveType(cast([*] u8) data + field.offset, pointedType orelse #typeof(u8))
            }
        }
    }
}
