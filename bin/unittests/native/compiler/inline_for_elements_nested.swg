#global private

struct Visits
{
    values: [4] s32 = [10, 20, 30, 40]
}

impl Visits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code(item: s32))
    {
        #if ptr do
            #error("no pointer iteration")
        #if back do
            #error("no reverse iteration")

        for [idx] in @countof(.values)
        {
            #inject(stmt, item = me.values[idx])
        }
    }
}

// Inlining this callee at a call site that already sits INSIDE the caller's own
// `for` (whose body is lowered to a void `opVisit` callback) must keep this
// `return true` routed to the callee's own bool result, not to the caller's
// enclosing void callback.
#[Swag.Inline]
func contains(v: Visits, target: s32)->bool
{
    for value in v
    {
        if value == target do
            return true
    }
    return false
}

func countCommon(a: Visits, b: Visits)->s32
{
    var n = 0
    for value in a
    {
        if contains(b, value) do
            n += 1
    }
    return n
}

#test
{
    let a = Visits{values: [10, 20, 30, 40]}
    let b = Visits{values: [20, 40, 50, 60]}
    @assert(countCommon(a, b) == 2)
    @assert(countCommon(a, a) == 4)
}
