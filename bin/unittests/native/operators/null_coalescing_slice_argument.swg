#global private

#[Swag.ConstExpr, Swag.Safety(.All, false)]
func byteCount(value: const [..] u8?)->u64 => value.count

#[Swag.ConstExpr, Swag.Safety(.All, false)]
func(T) coalescedByteCount(value: T)->u64
{
    return byteCount(value orelse "")
}

#test
{
    let present: string? = "abc"
    let absent:  string? = null
    Swag.assert(coalescedByteCount("abc") == 3)
    Swag.assert(coalescedByteCount(present) == 3)
    Swag.assert(coalescedByteCount(absent) == 0)
}
