#global private
#global namespace TOTO

const B = true
#assert(B)
#assert(#fullnameof(B) == "TOTO.B")

var C: Swag.TargetOs.Windows     // swc-expected-error {{sema_err_not_type}}
var D: Swag.TargetOs = Swag.TargetOs.Windows

namespace NotAType
{
    const K = 1
}

var E = NotAType{x: 1}     // swc-expected-error {{sema_err_not_type}}
