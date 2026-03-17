#global fileprivate // swc-option sema-only
#global skip
enum RGB { R, G, B }

func toto(rgb: RGB) {}

#test
{
    toto(.R)
}
