#global internal

const a: s32 = 1
const b: bool = cast() a
const c: bool = a // swc-expected-error {{sema_err_cannot_cast}}
#assert(b == true)

func toto(ptr: *u32) {}
func takes_s32(v: s32) {}
#test
{
    var ptr: *u64
    toto(cast() ptr)
    toto(ptr) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var f: f32 = 12.75
    takes_s32(f) // swc-expected-error {{sema_err_cannot_cast}}
    takes_s32(cast() f)
}
