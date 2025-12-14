#global internal

/*const A: s32 = 10
const B: s32 = 10's8*/

const C:  bool = 10's8   // swc-expected-error {{sema_err_cannot_cast}}
/*const C1: bool = cast(bool) 10's8
#assert(C1 == true)*/
