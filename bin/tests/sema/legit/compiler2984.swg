#global fileprivate // swc-option sema-only
#global skip
struct AA {}

enum Col { AA, BB }

#test
{
    let v = Col.AA
    switch v
    {
    case AA:
        break
    }
}
