#global fileprivate
#global namespace TOTO

const B = true
#assert(B)
#assert(#fullnameof(B) == "TOTO.B")

var D: Swag.TargetOs = Swag.TargetOs.Windows
