#global public

using Core, Gui

// Version of the in-process viewer plugin contract.
const ViewerPluginApiVersion = 5'u32

// Name of the function every viewer plugin exports.
const ViewerPluginCreateSymbol = "s_file_scope_plugin_create"

// Reveals `text` at its absolute byte offset without loading the preceding file content.
alias ViewerRevealMatch = func(*Wnd, u64, string)->bool

// Creates a plugin-owned view and reports its optional commands, details, and search callback.
alias ViewerPluginCreate = func(*Wnd, *Wnd, string, u32, *#null *Wnd, *String, *#null ViewerRevealMatch)->#null *Wnd
