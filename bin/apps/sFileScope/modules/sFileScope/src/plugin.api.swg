#global public

using Core, Pixel, Gui

// Version of the in-process viewer plugin contract.
const ViewerPluginApiVersion = 4'u32

// Name of the function every viewer plugin exports.
const ViewerPluginCreateSymbol = "s_file_scope_plugin_create"

// Creates a plugin-owned view below `contentParent` for one file.
//
// The plugin can also return one compact command group parented by `commandParent` and a concise
// file-specific detail string for the shared information bar. The host places the command group in
// its single action bar and destroys it together with the view. A plugin returns null only when
// `apiVersion` is not supported. File and decode errors are shown inside the returned view so the
// host can remain independent from plugin-specific diagnostics.
// Reveals `text` at its absolute byte offset without loading the preceding file content.
alias ViewerRevealMatch = func(*Wnd, u64, string)->bool

// Creates a plugin view and reports its optional document-search entry point.
alias ViewerPluginCreate = func(*Wnd, *Wnd, string, u32, *#null *Wnd, *String, *#null ViewerRevealMatch)->#null *Wnd
