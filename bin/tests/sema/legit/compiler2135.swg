#global fileprivate // swc-option sema-only
#global skip
enum Toto
{
    R
    G
    B
}

struct A
{
    x     = false
    e     = Toto.R
}

func toto(x = false) {}
