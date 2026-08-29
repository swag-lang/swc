#global export

using Core, Gui

// Identifies the source-level viewer contract implemented by this module.
//
// A future runtime loader must reject a descriptor whose version it does not support before it
// invokes any callback. Increasing this value denotes an incompatible contract change.
const ViewerApiVersion = 2'u32

// Options shared by file-backed and plugin-owned text searches.
struct SearchOptions
{
    public
    {
        matchCase:         bool                     // Whether letter case has to match.
        wholeWord:         bool                     // Whether word characters may touch either side of a match.
        regularExpression: bool                     // Whether the query is a regular expression rather than literal text.
        expression:        #null *Parser.RegExp     // Compiled expression borrowed for one synchronous collection.
    }
}

// Identifies one searchable location owned by a viewer.
//
// `major` and `minor` identify containers such as a PDF page or table cell. `offset` is a byte
// offset inside that container, or inside the source file when both container indexes are zero.
struct SearchMatch
{
    public
    {
        major:  u64     // Zero-based outer container index, such as a page or row.
        minor:  u64     // Zero-based inner container index, such as a span or cell.
        offset: u64     // Byte offset within the container, or within the file for zero indexes.
        length: u64     // Nonzero matched length in bytes.
    }
}

// Reveals one exact match without loading the preceding file content.
alias RevealSearchMatch = func(*Wnd, SearchMatch, string)->bool

// Returns the rendered bounds of one revealed match in surface coordinates.
alias SearchMatchBounds = func(*Wnd, SearchMatch, *Math.Rectangle)->bool

// Removes presentation left by the last revealed match.
alias ClearSearch = func(*Wnd)

// Collects every logical-text match owned by a viewer.
alias CollectSearchMatches = func(*Wnd, string, SearchOptions, *Array'SearchMatch)

// Describes viewer-specific wording and option visibility for the shared search field.
struct SearchPresentation
{
    public
    {
        placeholder:    String          // Short query hint shown while the search field is empty.
        toolTip:        String          // Longer syntax help owned by the presentation value.
        useTextOptions: bool = true     // Whether case, whole-word, and regular-expression options apply.
    }
}

// Describes the active viewer's search syntax in the application's current language.
alias DescribeSearch = func(*Wnd, *SearchPresentation)

// Describes a streamed-file search prepared by a viewer.
struct SearchPlan
{
    public
    {
        span:  u64        // Greatest number of source bytes one match can cover.
        error: String     // Explanation shown beside the shared field when the query is invalid.
    }
}

// Parses a viewer-specific query before the host opens and scans the file.
alias PrepareSearch = func(*Wnd, string, *SearchPlan)->EditBoxCheckResult

// Collects candidates inside one host-owned streamed source window.
alias CollectFileMatches = func(*Wnd, string, u64, *Array'SearchMatch)

// Lets a viewer borrow the host-owned result index while the current query remains active.
alias UseSearchMatches = func(*Wnd, #null *Array'SearchMatch)

// Configures the optional search behavior of one attached document view.
//
// A null `collectMatches` asks the host to scan file bytes. The view and every callback remain
// owned by the plugin; the host calls them only while the attached view is alive.
struct SearchApi
{
    public
    {
        revealMatch:        #null RevealSearchMatch        // Makes one host-selected match visible.
        matchBounds:        #null SearchMatchBounds        // Reports the revealed match geometry.
        clear:              #null ClearSearch              // Removes the current match presentation.
        collectMatches:     #null CollectSearchMatches     // Replaces host file scanning with viewer search.
        describe:           #null DescribeSearch           // Supplies localized query presentation.
        prepare:            #null PrepareSearch            // Validates a streamed-file query before scanning.
        collectFileMatches: #null CollectFileMatches       // Scans one host-owned streamed source window.
        useMatches:         #null UseSearchMatches         // Borrows the active host result index.
    }
}

// Reports whether a view is still doing work whose result has not reached the screen.
alias IsLoading = func(*Wnd)->bool

// Reports whether unfinished work has left the viewer with no useful content to present.
alias NeedsLoadingOverlay = func(*Wnd)->bool

// Requests release of a viewer's external resources without blocking the GUI thread.
//
// A false result asks the host to poll again. The host destroys the document and its contributed
// chrome only after this callback returns true.
alias Retire = func(*Wnd)->bool

// Configures optional progressive-loading and retirement behavior.
struct LifecycleApi
{
    public
    {
        isLoading:           #null IsLoading               // Reports unfinished viewer work.
        needsLoadingOverlay: #null NeedsLoadingOverlay     // Reports whether useful content is unavailable.
        retire:              #null Retire                  // Releases external resources before destruction.
    }
}

// Notifies the host that [[FileScope.LifecycleApi.isLoading]] may now answer differently.
alias ReportLoadingChanged = func(*Wnd)

// Hands a decoder error discovered after creation back to the host.
alias ReportFailure = func(*Wnd, string)

// Hands format statistics that changed after creation back to the host information band.
alias ReportDetails = func(*Wnd, string)

// Requests a re-measure after plugin-owned action or information content changes shape.
alias ReportChromeChanged = func(*Wnd)

// Requests a neighboring file when a plugin assigns meaning to that direction.
alias NavigateFile = func(*Wnd, s32)

// Callbacks a plugin may retain for asynchronous notifications after creation.
struct HostServices
{
    public
    {
        reportFailure:        #null ReportFailure            // Reports a decoder failure discovered after creation.
        reportDetails:        #null ReportDetails            // Replaces the host-owned format summary.
        reportChromeChanged:  #null ReportChromeChanged      // Requests another contributed-group layout pass.
        reportLoadingChanged: #null ReportLoadingChanged     // Notifies the host of changed loading state.
        navigateFile:         #null NavigateFile             // Requests a neighboring file by signed direction.
    }
}

// One viewer-owned contribution hosted in the application side-panel lane.
//
// The host owns both windows and keeps them valid until the attached viewer is retired. The
// plugin may connect to [[Gui.IconButton.sigCheckedChanged]] to start or stop work when the
// reader opens or closes the panel, but it must not destroy either window.
struct SidePanel
{
    public
    {
        #[Swag.Late]
        content: *Wnd     // Parent in which the plugin builds the panel contents.

        #[Swag.Late]
        toggle: *IconButton     // Toggle placed by the host at the edge controlled by the panel.
    }
}

// Gives one plugin controlled access to the sFileScope surface hosting it.
//
// The interface is borrowed only during the synchronous creation callback. A plugin may retain
// the callback values returned by [[FileScope.Host.services]], but never the interface itself or
// a string returned by it. The host owns every group created through this interface and destroys
// it with the attached document view.
interface Host
{
    // Returns the application that owns the viewer surface.
    mtd application()->*Application

    // Returns the parent under which the plugin creates its document view.
    mtd contentParent()->*Wnd

    // Returns the absolute file name for this viewer instance.
    mtd fileName()->string

    // Returns the plugin's glyph at the host's action-bar size.
    mtd icon()->Icon

    // Returns callbacks that may be retained for asynchronous host notifications.
    mtd services()->HostServices

    // Creates and registers the plugin's compact action-bar group.
    mtd createActionGroup(width: f32)->*Wnd

    // Creates and registers the plugin's compact information-bar group.
    mtd createInfoGroup(width: f32)->*Wnd

    // Creates and registers the plugin's full-width lower command group.
    mtd createCommandGroup(width: f32)->*Wnd

    // Creates the plugin's optional right-side panel and its host-positioned toggle.
    //
    // `width` is the content width in logical pixels; the host adds the themed integration
    // gutter. `icon` is displayed at the application toolbar size and `toolTip` is copied.
    mtd createSidePanel(width: f32, icon: Icon, toolTip: string)->SidePanel

    // Attaches the document view produced by the plugin.
    mtd attachView(view: *Wnd)

    // Sets the short format-specific summary shown by the host.
    mtd setDetails(details: string)

    // Rejects the file, discards contributed chrome, and records the exact decoder explanation.
    mtd reject(reason: string)

    // Replaces the search callbacks for the attached view.
    mtd setSearch(api: SearchApi)

    // Replaces the progressive-loading and retirement callbacks for the attached view.
    mtd setLifecycle(api: LifecycleApi)
}

// Creates one viewer synchronously through the host API.
//
// The callback creates presentation only. External I/O and decoding that can wait starts in the
// background, with progress and retirement exposed through [[FileScope.LifecycleApi]].
alias PluginCreate = func(Host)

// Performs content-aware discovery after named associations have been evaluated.
//
// `hasNamedMatch` reports whether any plugin already claimed the file by name. A probe must not
// reach GUI resources because the host may call it on a worker thread.
alias PluginProbe = func(string, bool)->bool

// Resolves a translated or otherwise dynamic viewer name on the GUI thread.
alias PluginName = func()->string

// Creates a viewer glyph for `size` logical pixels.
//
// `data` is descriptor-owned opaque context. The callback runs on the GUI thread and may use
// `parent` to reach the active renderer and scale.
alias PluginIcon = func(*Wnd, f32, u64)->Icon

// Describes one viewer plugin independently of the sFileScope window implementation.
struct Plugin
{
    public
    {
        apiVersion:   u32          = ViewerApiVersion     // Contract version implemented by every callback.
        key:          String                              // Stable lowercase identity persisted by the host.
        staticName:   String                              // Display name used when `resolveName` is null.
        resolveName:  #null PluginName                    // Optional dynamic or localized display-name provider.
        icon:         PluginIcon   = undefined            // Glyph provider called only on the GUI thread.
        iconData:     u64                                 // Opaque value forwarded to `icon`.
        create:       PluginCreate = undefined            // Synchronous presentation factory.
        probe:        #null PluginProbe                   // Optional content-aware discovery callback.
        matchNames:   bool         = true                 // Whether non-wildcard selectors offer this plugin directly.
        smokeFixture: String                              // Immutable basename used by application smoke review.
        selectors:    Array'String                        // Lowercase extensions, exact basenames, or `*` for fallback.
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
}
