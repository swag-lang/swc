#global fileprivate // swc-option sema-only
#global skip
//#global skip
struct A {}

func toto()->{ x: A, y: A }
{
    return {{}, {}}
}
