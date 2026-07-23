#global private

const A = 0
#assert(#stringof(A) == "0")

enum Test
{
    A = 1,
    B = 2,
    C = 3,
}

namespace Scoped
{
    struct Box
    {
        value: s32
    }

    struct(T) Wrapper
    {
        value: T
    }

    func(T) Make(value: T)->Wrapper'T
    {
        return {value: value}
    }
}

var ScopedValue:     Scoped.Box
var ScopedFunc:      func(Scoped.Box)->Scoped.Box = undefined
var ScopedClosure:   func||(Scoped.Box)->Scoped.Box = undefined
var ScopedNamedFunc: func(value: Scoped.Box)->Scoped.Box throw = undefined
var ScopedVariadic:  func(Scoped.Box...)->Scoped.Box = undefined
var ScopedArray:     [2] Scoped.Box
var ScopedWrapped:   Scoped.Wrapper'(Scoped.Box)

#assert(#fullnameof(Test.A) == "Test.A")
#assert(#fullnameof(Test.B) == "Test.B")
#assert(#fullnameof(Test.C) == "Test.C")
#assert(#fullnameof(#typeof(ScopedValue)) == "Scoped.Box")
#assert(#fullnameof(#typeof(ScopedFunc)) == "func(Scoped.Box)->Scoped.Box")
#assert(#fullnameof(#typeof(ScopedClosure)) == "func||(Scoped.Box)->Scoped.Box")
#assert(#fullnameof(#typeof(ScopedNamedFunc)) == "func(value: Scoped.Box)->Scoped.Box throw")
#assert(#fullnameof(#typeof(ScopedVariadic)) == "func(Scoped.Box...)->Scoped.Box")
#assert(#fullnameof(#typeof(ScopedArray)) == "[2] Scoped.Box")
#assert(#fullnameof(Scoped.Wrapper'(Scoped.Box)) == "Scoped.Wrapper'(Scoped.Box)")
#assert(#fullnameof(Scoped.Wrapper'(Scoped.Wrapper'(Scoped.Box))) == "Scoped.Wrapper'(Scoped.Wrapper'(Scoped.Box))")
#assert(#fullnameof(#type *Scoped.Wrapper'(Scoped.Box)) == "*Scoped.Wrapper'(Scoped.Box)")
#assert(#fullnameof(#type [..] Scoped.Wrapper'(Scoped.Box)) == "[..] Scoped.Wrapper'(Scoped.Box)")
#assert(#fullnameof(#type func(Scoped.Wrapper'(Scoped.Box))->Scoped.Wrapper'(Scoped.Box)) == "func(Scoped.Wrapper'(Scoped.Box))->Scoped.Wrapper'(Scoped.Box)")

func semaTestGeneric001()
{
    let made = Scoped.Make'(Scoped.Box)({value: 1})
    #assert(#typeof(made) == Scoped.Wrapper'(Scoped.Box))
}

#assert(#nameof(Test.A) == "A")
#assert(#nameof(Test.B) == "B")
#assert(#nameof(Test.C) == "C")

#assert(#stringof(cast(u32) Test.A) == "1")
#assert(#stringof(cast(u32) Test.B) == "2")
#assert(#stringof(cast(u32) Test.C) == "3")

#assert(#stringof(5) == "5")
#assert(#stringof(5 * 5) == "25")
#assert(#stringof(1 + 2 * 3) == "7")

#assert(#stringof("hello") == "hello")
#assert(#stringof("foo" ++ "bar") == "foobar")

#assert(#stringof(bool) == "bool")
#assert(#stringof(Test) == "Test")

var S: string = "Swag"
#assert(#stringof(S) == "S")

const B = 2 + 3
#assert(#stringof(B) == "5")

const NEG = -10
#assert(#stringof(NEG) == "-10")

#assert(#stringof(true) == "true")
#assert(#stringof(false) == "false")

var X: s32 = 42
#assert(#stringof(X) == "X")
