#global internal

const A = true
const B = A orelse false
#assert(B)

const C: string = null
const D = C orelse "d"
#assert(D == "d")

const E: string = "e"
const F = E orelse "f"
#assert(F == "e")