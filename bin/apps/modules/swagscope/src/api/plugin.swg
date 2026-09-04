#global public
#global namespace Viewer

using Core, Gui

// Identifies the viewer contract this application publishes to its plugins.
//
// A descriptor whose version the host does not support is rejected before any of its callbacks
// runs. Increasing this value denotes an incompatible contract change.
const ApiVersion = 3'u32

// Prepares one plugin for the application it joined, before any other callback runs.
//
// A plugin publishes its embedded translations and registers its string tables here, so both
// its display name and the views it later creates read the language of the application around
// them. The host calls it once for every registered descriptor, before the first name is shown;
// calling it again is harmless.
alias PluginAttach = func(*Application)

// Creates one viewer synchronously through the host API.
//
// The callback creates presentation only. External I/O and decoding that can wait starts in the
// background, with progress and retirement exposed through [[Viewer.LifecycleApi]].
alias PluginCreate = func(Host)

// Performs content-aware discovery after named associations have been evaluated.
//
// `hasNamedMatch` reports whether any plugin already claimed the file by name. A probe must not
// reach GUI resources because the host may call it on a worker thread.
alias PluginProbe = func(string, bool)->bool

// Resolves a translated or otherwise dynamic viewer name on the GUI thread.
alias PluginName = func()->string

// Describes one viewer plugin independently of the host window implementation.
//
// The descriptor owns its strings and selectors for as long as it remains registered, and it is
// everything the host reads about a format: which files the viewer offers itself for, how it is
// named and drawn in the selector, and the one callback that builds it.
struct Plugin
{
    public
    {
        apiVersion:  u32 = ApiVersion       // Contract version implemented by every callback.
        key:         String                 // Stable lowercase identity persisted by the host.
        staticName:  String                 // Display name used when `resolveName` is null.
        resolveName: #null PluginName       // Optional dynamic or localized display-name provider.
        attach:      #null PluginAttach     // Optional one-time preparation for the host application.
        iconAtlas:   #null *IconAtlas       // Vector document the viewer glyph is rasterized from.
        iconIndex:   s32                    // Zero-based cell of that document, in grid order.
        #[Swag.Late]
        create:       PluginCreate          // Synchronous presentation factory.
        probe:        #null PluginProbe     // Optional content-aware discovery callback.
        matchNames:   bool = true           // Whether non-wildcard selectors offer this plugin directly.
        smokeFixture: String                // Immutable basename used by application smoke review.
        selectors:    Array'String          // Lowercase extensions, exact basenames, or `*` for fallback.
    }
}

impl Plugin
{
    // Returns the name the host currently shows for this plugin.
    mtd const displayName()->string
    {
        if .resolveName do
            return .resolveName!()
        return .staticName.toString()
    }

    // Adds every `;` separated selector of `list`.
    mtd addSelectors(list: string)
    {
        for selector in Tokenize.split(list, ';'u8) do
            .selectors.add(String.from(selector))
    }

    // Adds one selector per element of `list`.
    mtd addSelectors(list: const [..] String)
    {
        for selector in list do
            .selectors.add(String.from(selector.toString()))
    }
}
