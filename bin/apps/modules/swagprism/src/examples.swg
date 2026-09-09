#global internal

using Core

enum ExampleKind
{
    Plasma
    Julia
    Gui
    Dot
}

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

func exampleViewer(kind: ExampleKind)->ViewerKind
{
    switch #complete kind
    {
    case .Plasma, .Julia: return .Render2D
    case .Gui: return .Gui
    case .Dot: return .Microcode
    }
}
