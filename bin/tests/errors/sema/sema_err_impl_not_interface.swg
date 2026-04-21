#global fileprivate

namespace B {}

impl B for B {} // swc-expected-error {{sema_err_impl_not_interface}}

enum ARC { A, B }

impl ARC for ARC {} // swc-expected-error {{sema_err_impl_not_interface}}
