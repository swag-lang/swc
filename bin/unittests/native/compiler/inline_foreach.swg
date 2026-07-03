#global private

// Inlining a callee whose body contains a `foreach` must keep an early `return` inside
// the loop routed to the inlined callee's result. A custom `opVisit` lowers the loop body
// into a `#code void` callback, so the materialized return must not bind to that void
// callback. Marked `#[Swag.Inline]` callees exercise this deterministically (inlined under
// MarkedOnly and Auto); the unmarked twins exercise the Auto size/shape heuristic when the
// suite runs with `-bc release`.

struct ReturnVisits
{
    values: [3] s32 = [4, 5, 6]
}

impl ReturnVisits
{
    #[Swag.Macro]
    mtd(ptr: bool, back: bool) const opVisit(stmt: #code void)
    {
        #if ptr do
            #error("ReturnVisits does not expose pointer iteration.")

        if !@countof(.values) do
            return

        var remain = @countof(.values)
        #scope(Up)
        for idx in @countof(.values)
        {
            #scope(Down)
            #macro
            {
                let #alias0 = #up me.values[#up idx]
                #inject(#up stmt, break = break to Up, continue = break to Down)
            }

            remain -= 1
            if !remain do
                break
        }
    }
}

// ---- `foreach` over a slice (builtin iteration) ----

#[Swag.Inline]
func findFirstEven(values: const [..] s32)->s32
{
    foreach v in values
    {
        if (v & 1) == 0 do
            return v
    }
    return -1
}

#[Swag.Inline]
func sumAll(values: const [..] s32)->s32
{
    var total = 0
    foreach v in values do
        total += v
    return total
}

// ---- `foreach` over a custom `opVisit` (loop body lowered to a void callback) ----

#[Swag.Inline]
func findValue(target: s32)->bool
{
    var values = ReturnVisits{}
    foreach value in values
    {
        if value == target do
            return true
    }
    return false
}

#[Swag.Inline]
func indexOfValue(target: s32)->s32
{
    var values = ReturnVisits{}
    foreach value in values
    {
        if value == target do
            return cast(s32) @index
    }
    return -1
}

// ---- Unmarked twins: auto-inline candidates under `-bc release` (Auto mode) ----

func findFirstEvenAuto(values: const [..] s32)->s32
{
    foreach v in values
    {
        if (v & 1) == 0 do
            return v
    }
    return -1
}

func findValueAuto(target: s32)->bool
{
    var values = ReturnVisits{}
    foreach value in values
    {
        if value == target do
            return true
    }
    return false
}

#test
{
    let data = [2, 3, 4, 5, 6]

    @assert(findFirstEven(data) == 2)
    @assert(findFirstEven([1, 3, 5]) == -1)
    @assert(sumAll(data) == 20)

    @assert(findValue(6))
    @assert(findValue(4))
    @assert(!findValue(99))
    @assert(indexOfValue(5) == 1)
    @assert(indexOfValue(99) == -1)

    @assert(findFirstEvenAuto(data) == 2)
    @assert(findValueAuto(6))
    @assert(!findValueAuto(99))
}
