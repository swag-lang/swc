#global internal
#global namespace TOTO

const B = true
#assert(B)
#assert(#stringof(B) == "TOTO.B")

var C: Swag.TargetOs.Windows // swc-expected-error {{sema_err_not_type}}
var D: Swag.TargetOs = Swag.TargetOs.Windows