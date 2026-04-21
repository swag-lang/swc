#global fileprivate

// 'mtd' methods must live inside an 'impl <T> { ... }' block.
mtd a() {}                       // swc-expected-error {{sema_err_method_outside_impl}}
mtd b()->s32 { return 0 }        // swc-expected-error {{sema_err_method_outside_impl}}
