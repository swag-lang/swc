#global internal

namespace NA {}
namespace NA.NB.NC {}

namespace NA
{
    const A = 0
}

// swc-expected-error@(+1,+2) {{sema_err_already_defined}}
namespace NB { const A = 0; }
namespace NB.A {}