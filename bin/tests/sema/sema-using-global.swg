#global internal
using Swag, Swag

#[EnumFlags]
enum A { B }

const AA = A.B | A.B
#assert(AA == A.B)

const AB = A.B & A.B
#assert(AB == A.B)

const AC = A.B ^ A.B
#assert(cast #bit (u32) AC == 0)

const AD = ~A.B
#assert(AD != A.B)