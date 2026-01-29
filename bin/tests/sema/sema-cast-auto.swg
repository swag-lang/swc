#global internal

const a: s32 = 1
const b: bool = cast() a
const c: bool = a // swc-expected-error {{sema_err_cannot_cast}}
#assert(b == true)