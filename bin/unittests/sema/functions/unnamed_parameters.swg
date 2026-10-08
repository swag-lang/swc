#global private

// '?' holds a parameter position without a name, wherever a parameter is declared.
func first(a: s32, _: s32)->s32 => a
func grouped(_, _: s32, c: u8)->u8 => c
func defaulted(a: s32, _: string = "unused")->s32 => a

struct Counter
{
    value: s32
}

impl Counter
{
    mtd add(_: bool, amount: s32)
    {
        .value += amount
    }
}

// A function type accepts '?' too, and the type name leaves the position unnamed.
alias Callback = func(_: s32, b: s32)->s32
#assert(#typeof(Callback).name == "func(s32, b: s32)->s32")
#assert(#typeof(first).name == "func(a: s32, s32)->s32")

// Reflection reports an empty name for an unnamed parameter.
const FIRST = #typeof(first)
#assert(FIRST.parameters[0].name == "a")
#assert(FIRST.parameters[1].name == "")

func semaTest001()->s32
{
    var counter: Counter
    counter.add(true, 2)
    let cb: Callback = func(_, b) => b
    return first(1, 2) + cast(s32, grouped(1, 2, 3)) + defaulted(4) + counter.value + cb(5, 6)
}
