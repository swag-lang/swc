#global private

// A parameter nothing names is an error.
func unusedParam(a: s32, b: s32)->s32     // swc-expected-error {{sema_err_unused_parameter}}
{
    return a
}

// '?' declares a parameter the body leaves unnamed, in every parameter form.
func unnamedParam(a: s32, _: s32)->s32 => a
func unnamedGroup(_, _: s32, c: s32)->s32 => c
func unnamedDefault(a: s32, _: bool = true)->s32 => a

// 'discard name' keeps the name, for a signature whose names are part of its contract.
func keptName(a: s32, b: s32)->s32
{
    discard b
    return a
}

// An interface method's parameters belong to the interface, whatever a default body does.
interface IShape
{
    mtd area(scale: f32)->f32 => 0
}

struct Square
{
    side: f32
}

impl IShape for Square
{
    mtd impl area(_: f32)->f32 => .side * .side
}

// Lambda parameters follow the same rule.
func apply(cb: func(s32, s32)->s32)->s32 => cb(1, 2)

func lambdas()->s32
{
    var total = apply(func(_, b) => b)
    total += apply(func(a, _) => a)
    total += apply(func(a, b) => a)     // swc-expected-error {{sema_err_unused_parameter}}
    return total
}

// A closure written in the body of a loop over a generic collection is the caller's own code,
// even though the expansion of the generic visitor owns the scope it sits in.
struct(T) Pair
{
    values: [2] T
}

impl Pair
{
    #[Swag.Macro]
    mtd(ptr: bool) opVisit(stmt: #code(item, index: u64))
    {
        for idx in 2
        {
            #inject(stmt, item = me.values[idx], index = idx)
        }
    }
}

func closuresInVisit()->s32
{
    let pair: Pair's32
    var total = 0
    for v in pair
    {
        total += v
        total += apply(func(a, _) => a)
        total += apply(func(a, b) => a)     // swc-expected-error {{sema_err_unused_parameter}}
    }
    return total
}

// A '?' parameter takes no argument name: the note lists the named ones only.
func namedOnly(a: s32, _: s32)->s32 => a

func callNamed()->s32 => namedOnly(a: 1, b: 2)     // swc-expected-error {{sema_err_named_argument_unknown}}
