#global fileprivate

struct AllUndefined {x: s32 = undefined, y: s32 = undefined}
struct NestedAllUndefined {inner: AllUndefined, z: s32 = undefined}

#test { let VALUE: AllUndefined } // swc-expected-error {{sema_err_let_missing_init}}
#test { let NESTED: NestedAllUndefined } // swc-expected-error {{sema_err_let_missing_init}}
