#global internal

using Core, Gui

// A viewer supplies its own option controls, output, and compilation lifecycle.
interface IViewer
{
    // Returns the window the panel docks in its body.
    mtd window()->*Wnd

    // Compiles `request`, replacing any request that is still waiting.
    mtd compile(request: Pipeline.BuildRequest)

    // Returns the pipeline stage the viewer prints, or an empty string when it only runs the program.
    mtd inspectionStage()->string

    // Records the backend optimization level the panel selected.
    mtd setOptimization(level: Swag.BuildCfgBackendOptimLevel)

    // Returns whether playback is paused.
    mtd isPaused()->bool

    // Pauses or resumes playback. A viewer with nothing to play ignores it.
    mtd setPaused(paused: bool)

    // Stops the viewer's compilation and running program, and waits for them.
    mtd shutdown()

    // Returns whether work the reader is waiting for is still in flight.
    mtd isRunning()->bool

    // Calls `action` whenever the viewer's status or output changes.
    mtd subscribeChanged(action: func||(*Wnd))
}

// The viewers a panel can host, in the order of its viewer-type selector.
enum ViewerKind
{
    Microcode     // The instructions of the first function at a chosen stage.
    Render2D      // The live output of a `shade` pixel function.
    Gui           // The live interface a `buildView` function builds.
}

// New viewer kinds enter through this factory without changing the comparison window.
func createViewer(parent: *ViewerPanel, source: *RichEditCtrl, kind: ViewerKind, level: Swag.BuildCfgBackendOptimLevel)->IViewer
{
    switch #complete kind
    {
    case .Microcode: return MicrocodeViewer.create(parent, source, level)
    case .Render2D:  return PreviewViewer.create(parent, source, false, level)
    case .Gui:       return PreviewViewer.create(parent, source, true, level)
    }
}
