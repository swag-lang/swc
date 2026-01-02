#global internal
#global namespace TOTO

const B = true
#assert(B)
#assert(#stringof(B) == "TOTO.B")

//var C: Swag.TargetOs.Windows