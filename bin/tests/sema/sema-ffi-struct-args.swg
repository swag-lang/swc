/*#global #if #os == Swag.TargetOs.Windows

struct Pair32
{
    a: u32
    b: u32
}

struct Triple64
{
    a: u64
    b: u64
    c: u64
}

#[Swag.Foreign("kernel32", "GetTickCount")]
func ForeignTakePair(value: Pair32)->u32;

#[Swag.Foreign("kernel32", "GetTickCount")]
func ForeignTakeTriple(value: Triple64)->u32;

#test
{
    var pair: Pair32 = {a: 1, b: 2}
    var triple: Triple64 = {a: 1, b: 2, c: 3}
    if false
    {
        var a = ForeignTakePair(pair)
        var b = ForeignTakeTriple(triple)
    }
}

#test { var x = ForeignTakePair(1) } // swc-expected-error {{sema_err_cannot_cast}}
#test { var y = ForeignTakePair() } // swc-expected-error {{sema_err_too_few_arguments}}
*/