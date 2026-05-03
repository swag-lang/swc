#global fileprivate

struct Pair { a: s32; b: bool }

func semaTest001()
{
    var s: Pair
    var a: s32
    var b: bool
    (a, b) = s
}

func semaTest002()
{
    var s: Pair
    var a: s32
    (a, ?) = s
}
