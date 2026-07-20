#global public

struct DepByteSet
{
    values: [4] u8
    count:  u32
}

struct DepSelfBufferSet
{
    buffer:  #null [*] u8
    count:   u32
    storage: [4] u8
}

impl DepByteSet
{
    #[Swag.NoInline]
    mtd const contains(value: u8)->bool
    {
        return depContains(values, count, value)
    }
}

impl DepSelfBufferSet
{
    mtd opPostMove()
    {
        if buffer do
            buffer = cast([*] u8) &storage[0]
    }

    mtd opPostCopy()
    {
        if buffer do
            buffer = cast([*] u8) &storage[0]
    }

    #[Swag.NoInline]
    mtd const toSlice()->const [..] u8
    {
        @assert(buffer == cast([*] u8) &storage[0])
        return @mkslice(buffer, count)
    }

    #[Swag.NoInline]
    mtd const contains(value: u8)->bool
    {
        @assert(buffer == cast([*] u8) &storage[0])
        return depContains(.toSlice(), count, value)
    }

    #[Swag.NoInline]
    mtd const containsViaGeneric(value: u8)->bool
    {
        @assert(buffer == cast([*] u8) &storage[0])
        return depContainsGeneric(.toSlice(), count, value)
    }
}

#[Swag.NoInline]
func depMakeSelfBufferSet(a: u8, b: u8, c: u8, d: u8, count: u32)->DepSelfBufferSet
{
    var result: retval = undefined
    result.storage = [a, b, c, d]
    result.buffer  = cast([*] u8) &result.storage[0]
    result.count   = count
    return result
}

#[Swag.NoInline]
func depContains(values: const [..] u8, count: u32, value: u8)->bool
{
    for i in count
    {
        if values[i] == value do
            return true
    }

    return false
}

#[Swag.NoInline]
func(T) depContainsGeneric(values: const [..] T, count: u32, value: T)->bool
{
    for i in count
    {
        if values[i] == value do
            return true
    }

    return false
}

impl DepByteSet
{
    #[Swag.NoInline]
    mtd const containsViaGeneric(value: u8)->bool
    {
        return depContainsGeneric(values, count, value)
    }
}

#[Swag.NoInline]
func depInvokeUnary(value: u8, cb: func||(u8)->bool)->bool
{
    return cb(value)
}

#[Swag.NoInline]
func(T) depInvokeGeneric(value: T, cb: func||(T)->bool)->bool
{
    return cb(value)
}

#[Swag.NoInline]
func(T) depAllOf(values: const [..] T, cb: func||(T)->bool)->bool
{
    for v in values
    {
        if !cb(v) do
            return false
    }

    return true
}
