#global fileprivate

namespace Swag {} // swc-expected-error {{sema_err_reserved_swag_ns}}
namespace swag {} // swc-expected-error {{sema_err_reserved_swag_ns}}
namespace SWG.SWAG {} // swc-expected-error {{sema_err_reserved_swag_ns}}
