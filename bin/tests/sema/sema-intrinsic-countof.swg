#global internal

enum A { R, G, B }
#assert(@countof(A) == 3)
#assert(@countof(A) != 2)

#assert(@countof("ABCDE") == 5)
const B = "XYZ"
#assert(@countof(B) == 3)

namespace NS {}
#assert(@countof(NS) == 3) // swc-expected-error {{sema_err_invalid_countof}}
#assert(@countof(true) == 1) // swc-expected-error {{sema_err_invalid_countof_type}}