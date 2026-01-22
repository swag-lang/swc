#global internal

#[Swag.EnumFlags]
enum A { R = 1, G = 2, B = 4 }

const B: A = .R
const C = A.R | .G
#assert(C == 3)