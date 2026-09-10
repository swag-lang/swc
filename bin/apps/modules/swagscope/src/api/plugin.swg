#global public
#global namespace Viewer

using Core, Gui

// Identifies the viewer contract this application publishes to its plugins.
//
// A descriptor whose version the host does not support is rejected before any of its callbacks
// runs. Increasing this value denotes an incompatible contract change.
const ApiVersion = 5'u32

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

// Bytes of a file the host reads before it asks any content probe.
//
// A few kilobytes carry every signature a format announces itself with and every encoding a text
// file uses. Reading more answers no better and delays the first screen.
const ProbeHeadSize = 4 * 1024'u64

// What a content probe is shown about the file being classified.
//
// The host opens the file once and hands the same beginning of it to every probe, because what a
// file is costs one read whatever the number of viewers asking. `head` is empty when the file
// could not be read at all, and shorter than [[Viewer.ProbeHeadSize]] when the file is.
struct ProbeContent
{
    public
    {
        fileName:    string            // Name of the file being classified.
        head:        const [..] u8     // Beginning of the file, at most `ProbeHeadSize` bytes.
        claimed:     bool              // Whether a viewer already offered itself for this file.
        claimedText: bool              // Whether every viewer that did reads the file as text.
    }
}

impl ProbeContent
{
    // Reports whether the file opens with `signature`, byte for byte.
    //
    // This is how a format that puts a magic number at offset zero recognizes itself.
    mtd const startsWith(signature: string)->bool
    {
        if .head.count < signature.count do
            return false
        for index in signature.count where .head[index] != signature[index] do
            return false
        return true
    }

    // Reports whether the file opens with `marker`, past a byte-order mark and any leading blank,
    // and whatever the letter case.
    //
    // This is how a textual format that begins with a keyword rather than a signature recognizes
    // itself. `marker` is ASCII, because a format keyword always is.
    mtd const opensWith(marker: string)->bool
    {
        var start = 0'u64
        if .head.count >= 3 and .head[0] == 0xEF and .head[1] == 0xBB and .head[2] == 0xBF do
            start = 3
        while start < .head.count and Latin1.isSpace(.head[start]) do
            start += 1
        if .head.count - start < marker.count do
            return false
        for index in marker.count where Latin1.toLower(.head[start + index]) != Latin1.toLower(marker[index]) do
            return false
        return true
    }
}

// Performs content-aware discovery after named associations have been evaluated.
//
// This is what makes a misnamed or extensionless file reach the viewer that can show it. Probes
// run in registration order, so `claimed` reports whether any plugin already offered itself for
// the file, by name or through an earlier probe, and `claimedText` whether all of them read it as
// text. A last-resort reader declines what a format viewer took; a raw-source reader follows one.
//
// A probe must not reach GUI resources because the host may call it on a worker thread.
alias PluginProbe = func(ProbeContent)->bool

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
        apiVersion:   u32  = ApiVersion     // Contract version implemented by every callback.
        key:          String                // Stable lowercase identity persisted by the host.
        staticName:   String                // Display name used when `resolveName` is null.
        resolveName:  PluginName?           // Optional dynamic or localized display-name provider.
        attach:       PluginAttach?         // Optional one-time preparation for the host application.
        iconAtlas:    *IconAtlas?           // Vector document the viewer glyph is rasterized from.
        iconIndex:    s32                   // Zero-based cell of that document, in grid order.
        late create:  PluginCreate          // Synchronous presentation factory.
        probe:        PluginProbe?          // Optional content-aware discovery callback.
        matchNames:   bool = true           // Whether non-wildcard selectors offer this plugin directly.
        textual:      bool                  // Whether this format's bytes are text a reader may also want raw.
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
            return .resolveName()
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
