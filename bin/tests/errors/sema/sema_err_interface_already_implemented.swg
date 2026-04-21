#global fileprivate

interface I0 { mtd toto(); }
struct S0 {}

// swc-expected-error@(+1,+2) {{sema_err_interface_already_implemented}}
impl I0 for S0 { mtd impl toto() {} }
impl I0 for S0 { mtd impl toto() {} }

namespace Nested
{
    interface I1 { mtd ping(); }
}

struct S1 {}

// swc-expected-error@(+1,+2) {{sema_err_interface_already_implemented}}
impl Nested.I1 for S1 { mtd impl ping() {} }
impl Nested.I1 for S1 { mtd impl ping() {} }
