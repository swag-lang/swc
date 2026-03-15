#global fileprivate // swc-option suite-test

var gAmb0Calls: s32
var gAmb1Last: s32
var gNAmb0Calls: s32
var gNAmb1Last: s32
var gDeclAndDefCalls: s32
func Amb() { gAmb0Calls += 1 }
func Amb(a: s32) { gAmb1Last = a }

#test
{
    gAmb0Calls = 0
    gAmb1Last  = 0
    Amb()
    Amb(10)
    @assert(gAmb0Calls == 1)
    @assert(gAmb1Last == 10)
}


namespace N
{
    func Amb() { gNAmb0Calls += 1 }
    func Amb(a: s32) { gNAmb1Last = a }
}

#test
{
    gNAmb0Calls = 0
    gNAmb1Last  = 0
    N.Amb()
    N.Amb(10)
    @assert(gNAmb0Calls == 1)
    @assert(gNAmb1Last == 10)
}




func DeclAndDef();
func DeclAndDef() { gDeclAndDefCalls += 1 }

#test
{
    gDeclAndDefCalls = 0
    DeclAndDef()
    #assert(#nameof(DeclAndDef) == "DeclAndDef")
    @assert(gDeclAndDefCalls == 1)
}

func DeclOnly();
func DeclOnly(a: s32);

