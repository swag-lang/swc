#global fileprivate

// Every enum must declare at least one value, regardless of its underlying type.
enum A: u8 {}                    // swc-expected-error {{sema_err_empty_enum}}
enum B: s32 {}                   // swc-expected-error {{sema_err_empty_enum}}
enum C {}                        // swc-expected-error {{sema_err_empty_enum}}
