#global fileprivate

struct AllUndefined {x: s32 = undefined, y: s32 = undefined}
struct NestedAllUndefined {inner: AllUndefined, z: s32 = undefined}

#test { const VALUE: AllUndefined } // swc-expected-error {{sema_err_const_missing_init}}
#test { const NESTED: NestedAllUndefined } // swc-expected-error {{sema_err_const_missing_init}}
