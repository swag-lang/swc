#global internal

const A = 0
#assert(#defined(A))
#assert(!#defined(B))

namespace NS { const AA = 0 }
#assert(#defined(NS.AA))

#assert(#defined(C))
const C = 1