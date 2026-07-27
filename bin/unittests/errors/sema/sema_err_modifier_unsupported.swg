#global private

const InvalidWrapDiv = 1 / #wrap 4      // swc-expected-error {{sema_err_modifier_unsupported}}
const InvalidBitDiv  = 1 / #bit 4       // swc-expected-error {{sema_err_modifier_unsupported}}
const InvalidWrapInc = 1 ++ #wrap 4     // swc-expected-error {{sema_err_modifier_unsupported}}
#assert(1 ^ #wrap 0 == 1)               // swc-expected-error {{sema_err_modifier_unsupported}}
#assert(1 & #wrap 0 == 1)               // swc-expected-error {{sema_err_modifier_unsupported}}
#assert(1 | #wrap 0 == 1)               // swc-expected-error {{sema_err_modifier_unsupported}}

// A modifier written on a variable initializer sits to the LEFT of the node it modifies,
// so the report has to find its token from the '=' anchor.
func initializerWrap()
{
    var x = 1
    var a = #wrap x     // swc-expected-error {{sema_err_modifier_unsupported}}
    discard a
}

func initializerReverse()
{
    var x = 1
    var a = #reverse x     // swc-expected-error {{sema_err_modifier_unsupported}}
    discard a
}

func initializerComplete()
{
    var x = 1
    var a = #complete x     // swc-expected-error {{sema_err_modifier_unsupported}}
    discard a
}
