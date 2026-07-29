// A namespace declared by the current module wins over a same-named namespace of an imported one,
// even while that module is in scope through a 'using'. Without that rule 'Shared' below would
// resolve to 'ExportApi.Shared' and this module could no longer name its own namespace at all.
using ExportApi

namespace Shared
{
    const Marker = 2
}

#assert(Shared.Marker == 2)

// The imported one stays reachable, qualified.
#assert(ExportApi.Shared.Marker == 1)
