#global fileprivate // swc-option sema-only
#global skip
const CONST = true

interface TOTO
{
    #if CONST do
        func print(v: *TOTO, x: bool);
}
