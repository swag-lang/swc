#global fileprivate // swc-option suite-test

func Amb() {}
func Amb(a: s32) {}

#test
{
    Amb()
    Amb(10)
}


namespace N
{
    func Amb() {}
    func Amb(a: s32) {}
}

#test
{
    N.Amb()
    N.Amb(10)
}




func DeclAndDef();
func DeclAndDef() {}

#test
{
    DeclAndDef()
    #assert(#nameof(DeclAndDef) == "DeclAndDef")
}

func DeclOnly();
func DeclOnly(a: s32);

