#global internal

using Core

// The starter snippets, in the order of the example selector.
enum ExampleKind
{
    Plasma
    Julia
    Gui
    Dot
}

// Returns the source text of an example.
func exampleSource(kind: ExampleKind)->string
{
    switch #complete kind
    {
    case .Plasma: return cast(string) #include("../datas/examples/plasma.txt")
    case .Julia:  return cast(string) #include("../datas/examples/julia.txt")
    case .Gui:    return cast(string) #include("../datas/examples/gui.txt")
    case .Dot:    return cast(string) #include("../datas/examples/dot.txt")
    }
}

// Returns the viewer the first panel switches to when an example opens.
func exampleViewer(kind: ExampleKind)->ViewerKind
{
    switch #complete kind
    {
    case .Plasma, .Julia: return .Render2D
    case .Gui: return .Gui
    case .Dot: return .Microcode
    }
}
