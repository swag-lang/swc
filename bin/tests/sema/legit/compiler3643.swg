#global fileprivate // swc-option sema-only
#global skip
//#global skip
enum RGB { R }
var g: func(RGB)

func toto()
{
    g(.R)
}
