# Writing a viewer plugin

A viewer plugin is a descriptor plus a synchronous creation callback. Keep format metadata,
selection rules, the icon provider, and the factory together in the descriptor. The stable,
lowercase key is the identity the host may persist; the display name can be static or resolved at
runtime for localization.

The creation callback receives only `FileScope.Host`. Create the document below
`Host.contentParent`, then attach it with `Host.attachView`. Use `Host.createActionGroup` for
compact document actions in the top bar, `Host.createInfoGroup` for short trailing values in the
information band, and `Host.createCommandGroup` only for wider controls that need a lower row.
Each kind of group can be created at most once for one plugin instance. The host owns and destroys
all four roots together.

Reject unsupported or malformed content with `Host.reject` before attaching a document. For a
failure discovered later, retain `HostServices.reportFailure` and call it with the attached view.
Never retain the `Host` interface or strings borrowed from it after the creation callback returns.

Search and progressive work are optional. `Host.setSearch` lets a viewer reveal logical matches,
replace byte scanning with format-aware collection, or describe custom query syntax. A progressive
viewer uses `Host.setLifecycle` so the application can show shared loading presentation and delay
destruction until external workers have released their borrowed state.

The current shared module is a source-level contract used by built-in plugins. A future external
loader still needs a stable native entry point, discovery policy, trust policy, and adapter for ABI
evolution. It must compare `FileScope.ViewerApiVersion` before invoking a descriptor callback; the
source-level API deliberately does not pretend that loading arbitrary DLLs is already supported.
