#global private

struct DynamicSwapStorage
{
    buffer: *s32?
    value:  s32
}

impl DynamicSwapStorage
{
    mtd opPostMove()
    {
        if .buffer != null do
            .buffer = &.value
    }

    mtd opDrop()
    {
        Swag.assert(.buffer == null or .buffer == &.value)
    }
}

#[Swag.Inline]
func(T) dynamicSwapStorage(left, right: *T)
{
    var temporary: T
    temporary = #relocate left[]
    left[]    = #relocate right[]
    right[]   = #relocate temporary
}

#test
{
    var left  = DynamicSwapStorage{value: 17}
    var right = DynamicSwapStorage{value: 42}
    left.buffer  = &left.value
    right.buffer = &right.value
    dynamicSwapStorage(&left, &right)
    Swag.require(left.value == 42)
    Swag.require(right.value == 17)
    Swag.require(left.buffer == &left.value)
    Swag.require(right.buffer == &right.value)
}
