#global fileprivate

interface I {
    mtd A() -> s32;
}

namespace B {}

impl I for B {} // swc-expected-error {{sema_err_impl_not_struct}}

enum ARC { A, B }

impl I for ARC {} // swc-expected-error {{sema_err_impl_not_struct}}
