#global fileprivate

// swc-expected-error@(+1,+2,+3) {{sema_err_cyclic_dependency}}
const first: s32 = second + 1
const second: s32 = third + 1
const third: s32 = first

// swc-expected-error@(+1,+2) {{sema_err_cyclic_dependency}}
struct A { b: B }
struct B { a: A }
