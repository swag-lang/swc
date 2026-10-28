#global internal

using Core

// The starter snippets, in the order of the example menu.
enum ExampleKind
{
    Plasma
    Julia
    Gui
    Dot
}

// Identities of the entries of the example menu, which borrows them, in the order of `ExampleKind`.
const ExampleIds = ["prism.example.plasma", "prism.example.julia", "prism.example.gui", "prism.example.dot"]

// Returns the source text of an example.
func exampleSource(kind: ExampleKind)->string
{
    switch #complete kind
    {
    case .Plasma: return cast(string, #include("../datas/examples/plasma.txt"))
    case .Julia:  return cast(string, #include("../datas/examples/julia.txt"))
    case .Gui:    return cast(string, #include("../datas/examples/gui.txt"))
    case .Dot:    return cast(string, #include("../datas/examples/dot.txt"))
    }
}

// Returns the name of an example, as its menu, the lens and the window title write it.
func exampleName(kind: ExampleKind)->string
{
    switch #complete kind
    {
    case .Plasma: return appStrings().ui_Plasma
    case .Julia:  return appStrings().ui_Julia
    case .Gui:    return appStrings().ui_GuiExample
    case .Dot:    return appStrings().ui_Dot
    }
}

// Returns the name of the file an example stands for, which heads the source column. A file name is
// not translated.
func exampleFileName(kind: ExampleKind)->string
{
    switch #complete kind
    {
    case .Plasma: return "plasma.swg"
    case .Julia:  return "julia.swg"
    case .Gui:    return "gui.swg"
    case .Dot:    return "dot.swg"
    }
}

// Returns the viewer the main build switches to when an example opens.
func exampleViewer(kind: ExampleKind)->ViewerKind
{
    switch #complete kind
    {
    case .Plasma, .Julia: return .Render2D
    case .Gui: return .Gui
    case .Dot: return .Microcode
    }
}
