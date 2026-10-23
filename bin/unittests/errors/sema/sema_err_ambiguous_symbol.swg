#global private

func Amb() {}
func Amb(a: s32) { discard a }

#test
{
    Amb()
    Amb(10)
}

#test
{
    #assert(#nameof(Amb) == "Amb")     // swc-expected-error {{ambiguous function name 'Amb'}}
}

namespace N
{
    func Amb() {}
    func Amb(a: s32) { discard a }
}

#test
{
    N.Amb()
    N.Amb(10)
}

#test
{
    #assert(#nameof(N.Amb) == "Amb")     // swc-expected-error {{sema_err_ambiguous_symbol}}
}

#test
{
    let p0 = #typeof(Amb)     // swc-expected-error {{sema_err_ambiguous_symbol}}
}

#test
{
    let p1 = #typeof(N.Amb)     // swc-expected-error {{sema_err_ambiguous_symbol}}
}

func DeclAndDef()
func DeclAndDef() {}

#test
{
    DeclAndDef()
    #assert(#nameof(DeclAndDef) == "DeclAndDef")
}

func DeclOnly()
func DeclOnly(a: s32)

#test
{
    #assert(#nameof(DeclOnly) == "DeclOnly")     // swc-expected-error {{sema_err_ambiguous_symbol}}
}

func AmbiguousFamily() {}     // swc-expected-note {{could refer to a function 'AmbiguousFamily'}}
func AmbiguousFamily(value: s32) { discard value }     // swc-expected-note {{could refer to a function 'AmbiguousFamily'}}

#test
{
    #assert(#nameof(AmbiguousFamily) == "AmbiguousFamily")     // swc-expected-error {{ambiguous function name 'AmbiguousFamily'}}
}
