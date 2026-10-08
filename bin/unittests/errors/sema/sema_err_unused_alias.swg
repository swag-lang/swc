#global private

// Names a call site gives to a macro's '#code' values follow the unused rule like any other
// local: the error points at the name the caller wrote.

#[Swag.Macro]
func pair(value: s32, stmt: #code(first: s32, second: s32))
{
    #inject(stmt, first = value, second = value * 2)
}

struct Triple
{
    values: [3] s32 = [1, 2, 3]
}

impl Triple
{
    #[Swag.Macro]
    mtd(ptr: bool) opVisit(stmt: #code(item, index: u64))
    {
        for idx in 3
        {
            #inject(stmt, item = me.values[idx], index = idx)
        }
    }
}

func binders()->s32
{
    var total = 0
    pair(1) #code(a, b) { total += a + b }
    pair(2) #code(a, _) { total += a }
    pair(3) #code(a, b) { total += a }     // swc-expected-error {{sema_err_unused_variable}}
    return total
}

func visits()->s32
{
    let t: Triple
    var total = 0
    for v in t do
        total += v
    for _, i in t do
        total += cast(s32, i)
    for v, i in t do     // swc-expected-error {{sema_err_unused_variable}}
        total += v
    return total
}

// A local the caller writes inside the code it passes is checked as well.
func passedCode()->s32
{
    var total = 0
    pair(1) #code(a, b)
    {
        let unused = a     // swc-expected-error {{sema_err_unused_variable}}
        total += b
    }
    return total
}
