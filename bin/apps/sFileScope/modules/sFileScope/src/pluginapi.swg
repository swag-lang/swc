#global public

using Core, Pixel, Gui

// Version of the in-process viewer plugin contract.
const ViewerPluginApiVersion = 2'u32

// Name of the function every viewer plugin exports.
const ViewerPluginCreateSymbol = "s_file_scope_plugin_create"

// Creates a plugin-owned view below `contentParent` for one file.
//
// The plugin can also return one compact command group parented by `commandParent`. The host places
// that group in its single command bar and destroys it together with the view. A plugin returns null
// only when `apiVersion` is not supported. File and decode errors are shown inside the returned view
// so the host can remain independent from plugin-specific diagnostics.
alias ViewerPluginCreate = func(*Wnd, *Wnd, string, u32, *#null *Wnd)->#null *Wnd
