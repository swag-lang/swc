#global fileprivate

namespace Helpers {}

using Helpers
using Sema // swc-expected-error {{sema_err_using_module_namespace}}
