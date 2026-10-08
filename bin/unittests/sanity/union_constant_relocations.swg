#global private

const UNION_PARTIAL_TARGET = "partial-pointer-default"

union PartialPointerConstant
{
    whole:   u64
    byte:    u8
    pointer: const [*] u8 = UNION_PARTIAL_TARGET.buffer
}

union PartialPointerDefault
{
    whole:   u64
    pointer: const [*] u8 = UNION_PARTIAL_TARGET.buffer
    byte:    u8 = 0x55
}

// The untouched bytes depend on the final native address and cannot be frozen in a constant.
const PARTIAL_POINTER: PartialPointerConstant = {byte: 0x55}     // swc-expected-error {{sema_err_expr_not_const}}
const PARTIAL_DEFAULT: PartialPointerDefault  = {}      // swc-expected-error {{sema_err_expr_not_const}}
var partialPointerGlobal: PartialPointerDefault         // swc-expected-error {{sema_err_expr_not_const}}
var partialPointerArray:  [2] PartialPointerDefault     // swc-expected-error {{sema_err_expr_not_const}}
