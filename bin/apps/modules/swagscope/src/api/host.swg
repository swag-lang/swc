#global public
#global namespace Viewer

using Core, Gui

// Hands a decoder error discovered after creation back to the host.
alias ReportFailure = func(*Wnd, string)

// Hands format statistics that changed after creation back to the host information band.
alias ReportDetails = func(*Wnd, string)

// Requests a re-measure after plugin-owned action or information content changes shape.
alias ReportChromeChanged = func(*Wnd)

// Notifies the host that [[Viewer.LifecycleApi.isLoading]] may now answer differently.
alias ReportLoadingChanged = func(*Wnd)

// Requests a neighboring file when a plugin assigns meaning to that direction.
alias NavigateFile = func(*Wnd, s32)

// Callbacks a plugin may retain for asynchronous notifications after creation.
struct HostServices
{
    public
    {
        reportFailure:        ReportFailure?            // Reports a decoder failure discovered after creation.
        reportDetails:        ReportDetails?            // Replaces the host-owned format summary.
        reportChromeChanged:  ReportChromeChanged?      // Requests another contributed-group layout pass.
        reportLoadingChanged: ReportLoadingChanged?     // Notifies the host of changed loading state.
        navigateFile:         NavigateFile?             // Requests a neighboring file by signed direction.
    }
}

// Hosts one file through the same viewer registry inside another viewer.
//
// The returned interface borrows a host-owned child window. Its parent owns that window, while
// the caller controls the viewer resources through [[Viewer.Embedded.retire]]. A caller must let
// `retire` return true before destroying the parent or deleting the file currently being shown.
interface Embedded
{
    // Opens `fileName` with the host's normal viewer selection and shows `title` as its identity.
    //
    // The embedded host needs to be empty; call [[Viewer.Embedded.retire]] until it returns true
    // before opening another file. File discovery and viewer creation failures are reported with
    // `fail`, while failures discovered by a progressive viewer appear in its document surface.
    mtd open(fileName, title: string) fail

    // Requests release of every hosted viewer and reports when its source file is no longer used.
    //
    // A false result means progressive work is still retiring and the caller should poll again
    // without blocking the GUI thread. Repeated calls after success are harmless.
    mtd retire()->bool

    // Reports whether the selected hosted viewer is still producing visible content.
    mtd isLoading()->bool
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
        late content: *Wnd     // Parent in which the plugin builds the panel contents.

        late toggle: *IconButton     // Toggle placed by the host at the edge controlled by the panel.
    }
}

// Gives one plugin controlled access to the surface hosting it.
//
// The interface is borrowed only during the synchronous creation callback. A plugin may retain
// the callback values returned by [[Viewer.Host.services]], but never the interface itself or
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

    // Creates a child host that can display files through the application's viewer registry.
    //
    // `parent` takes ownership of the child window. The returned interface borrows that child and
    // remains valid until `parent` is destroyed.
    mtd createEmbedded(parent: *Wnd)->Embedded

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
