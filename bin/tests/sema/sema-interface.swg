#global internal

struct A {}

interface I {
    mtd A() -> s32;
}

impl I for A {
    mtd A() -> s32 {
        return 0;
    }
}
/*
namespace B {}
impl I for B {} // swc-expected-error {{sema_err_impl_not_struct}}
impl B for B {} // swc-expected-error {{sema_err_impl_not_interface}}

enum ARC { A, B }
impl I for ARC {} // swc-expected-error {{sema_err_impl_not_struct}}
impl ARC for ARC {} // swc-expected-error {{sema_err_impl_not_interface}}
*/
interface I0 { mtd toto(); }
struct S0 {}
/*
// swc-expected-error@(+1,+2) {{sema_err_interface_already_implemented}}
impl I0 for S0 { mtd impl toto() {} }
impl I0 for S0 { mtd impl toto() {} }
*/

#test
{
    var a: I0
    a.toto()
}


interface I1 { mtd toto(); }
struct T {}

// Force `T` completion through another type before the interface impl is registered.
struct U { t: T }
impl T
{
    mtd toto(x: s32) {}
}

impl I1 for T
{
    mtd impl toto() {}
    func titi() {}
    mtd tata() { me.toto() }
    mtd tonton() { .toto() }
}

#test
{
    T.I1.titi()
}