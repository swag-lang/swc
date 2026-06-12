#global fileprivate

struct NullableLogicalGuardItem
{
    value: s32
}

func nullableLogicalGuardOrFallthrough(item: #null *NullableLogicalGuardItem)->s32
{
    if !item or item.value == 0
    {
        return 0
    }

    return item.value
}

func nullableLogicalGuardOrElse(item: #null *NullableLogicalGuardItem)->s32
{
    if !item or item.value == 0
    {
        return 0
    }
    else
    {
        return item.value
    }
}

func nullableLogicalGuardAndThen(item: #null *NullableLogicalGuardItem)->s32
{
    if item and item.value != 0
    {
        return item.value
    }

    return 0
}

func nullableLogicalGuardKeepsVarStorageNullable(item: #null *NullableLogicalGuardItem)->#null *NullableLogicalGuardItem
{
    if !item
    {
        return null
    }

    var scan = item
    scan = null
    return scan
}
