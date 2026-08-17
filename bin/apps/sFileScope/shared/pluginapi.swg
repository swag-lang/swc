#global public

using Core, Gui

/*
The contract between sFileScope and one viewer plugin.

This file is not a module. Every module that speaks the contract — the host and each plugin —
loads it with `#load` from its own `module.swg`, so the constants, the aliases, and the two
structures below are compiled into each of them. A shared declaration set is not a dependency:
making it one would add a module to the build graph, an export artifact under `.output`, and an
import edge, all to publish a small declaration set that carries no code.
*/

// Version of the in-process viewer plugin contract.
//
// The host passes it in and the plugin refuses anything else, so a plugin library left behind by
// an older build is declined instead of being called through a layout it does not share. Bump it
// whenever a field of [[ViewerRequest]] or [[ViewerResult]] moves, changes meaning, or appears.
const ViewerPluginApiVersion = 7'u32

// Name of the function every viewer plugin exports.
const ViewerPluginCreateSymbol = "s_file_scope_plugin_create"

// Reveals `text` at its absolute byte offset without loading the preceding file content.
alias ViewerRevealMatch = func(*Wnd, u64, string)->bool

// Reports whether a view is still doing work whose result has not reached the screen.
alias ViewerIsLoading = func(*Wnd)->bool

// What the host asks one plugin to display.
//
// The plugin reads it and never writes it: everything it produces goes through [[ViewerResult]].
struct ViewerRequest
{
    apiVersion:    u32                  // Contract version the host was built against.
    contentParent: *Wnd = undefined     // Parent the document view must be created under.
    commandParent: *Wnd = undefined     // Parent the optional command group must be created under.
    fileName:      string               // File the view has to show.
}

// What one plugin gives back.
//
// Only `view` is required. A plugin that needs no action bar leaves `commands` null, and one that
// cannot reveal an offset leaves `revealMatch` null; the host then owns the whole search itself.
// A view that does no progressive work leaves `isLoading` null.
struct ViewerResult
{
    view:        #null *Wnd                  // Document view the plugin owns.
    commands:    #null *Wnd                  // One group of compact controls, or null.
    details:     String                      // Short format-specific summary shown by the host.
    revealMatch: #null ViewerRevealMatch     // Reveals a byte offset, or null when not searchable.
    isLoading:   #null ViewerIsLoading       // Reports unfinished visible work, or null for an immediate view.
}

// Creates a plugin-owned view and reports its optional commands, details, and search callback.
//
// Returns false when the plugin does not implement the requested contract version, and leaves
// `result` untouched in that case.
alias ViewerPluginCreate = func(const *ViewerRequest, *ViewerResult)->bool
