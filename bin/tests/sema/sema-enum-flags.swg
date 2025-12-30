#global internal

enum AA { A, B }
const BB = AA.A | 1 // swc-expected-error {{sema_err_invalid_op_enum}}
const CC = 1 | AA.A // swc-expected-error {{sema_err_invalid_op_enum}}
