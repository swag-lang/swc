#global internal

using Core, Gui

// A viewer supplies its own option controls, output, and compilation lifecycle.
interface IViewer
{
    mtd window()->*Wnd
    mtd compile(source: string)
    mtd shutdown()
    mtd isRunning()->bool
    mtd subscribeChanged(action: func||(*Wnd))
}

enum ViewerKind
{
    Microcode
}

// New viewer kinds enter through this factory without changing the comparison window.
func createViewer(parent: *Wnd, source: *RichEditCtrl, kind: ViewerKind, level: Swag.BuildCfgBackendOptimLevel)->IViewer
{
    switch #complete kind
    {
    case .Microcode: return MicrocodeViewer.create(parent, source, level)
    }
}
