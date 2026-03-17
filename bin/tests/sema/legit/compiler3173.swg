#global fileprivate // swc-option sema-only
#global skip
attr AA()

func toto(x: typeinfo) {}

#test
{
    toto(AA)
}
