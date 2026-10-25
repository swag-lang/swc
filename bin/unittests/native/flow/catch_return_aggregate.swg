#global private

// Both catch paths initialize the caller return slot, including consecutive failed calls.

var drops:  u32
var target: u32 = 12
struct Owner
{
    data:     *u32?
    reserved: [16] u64
}
impl Owner
{
    mtd opDrop()
    {
        Swag.assert(.data == null or .data == &target)
        if .data do drops += 1
    }
}
#[Swag.NoInline]
func load(ok: bool)->Owner fail
{
    if not ok do fail 7
    return {data: &target}
}
#[Swag.NoInline]
func fallback(ok: bool)->Owner
{
    return catch load(ok) orelse Owner{}
}
#[Swag.NoInline]
func defaultFallback(ok: bool)->Owner => catch load(ok)

#[Swag.Inline]
func inlineFallback(ok: bool)->Owner => catch load(ok) orelse Owner{}

#test
{
    for index in 1000
    {
        scope
        {
            let result = fallback(index % 2 == 0)
            Swag.assert(result.data == (index % 2 == 0 ? &target : null))
            let defaultResult = defaultFallback(index % 2 == 0)
            Swag.assert(defaultResult.data == result.data)
            let inlineResult = inlineFallback(index % 2 == 0)
            Swag.assert(inlineResult.data == result.data)
        }
    }
    Swag.assert(drops == 1500)
}
