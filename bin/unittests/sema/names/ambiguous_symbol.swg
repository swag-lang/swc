#global fileprivate

func Amb() {}
func Amb(a: s32) {}

func semaTest001()
{
    Amb()
    Amb(10)
}

namespace N
{
    func Amb() {}
    func Amb(a: s32) {}
}

func semaTest002()
{
    N.Amb()
    N.Amb(10)
}

func DeclAndDef();
func DeclAndDef() {}

func semaTest003()
{
    DeclAndDef()
    #assert(#nameof(DeclAndDef) == "DeclAndDef")
}

func DeclOnly();
func DeclOnly(a: s32);
