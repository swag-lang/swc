#global internal
#global namespace Viewers.Scene

using Core, Gui

struct Texts
{
    ui_Name:       string = "3D Scene"
    ui_ZoomMenu:   string = "Choose scene zoom"
    ui_FrameAll:   string = "Frame All"
    ui_OrbitLeft:  string = "Orbit Left"
    ui_OrbitRight: string = "Orbit Right"
    ui_OrbitUp:    string = "Orbit Up"
    ui_OrbitDown:  string = "Orbit Down"
    ui_PanLeft:    string = "Pan Left"
    ui_PanRight:   string = "Pan Right"
    ui_PanUp:      string = "Pan Up"
    ui_PanDown:    string = "Pan Down"
    ui_Meshes:     string = "% meshes"
    ui_Nodes:      string = "% nodes"
    ui_Vertices:   string = "% vertices"
    ui_Triangles:  string = "% triangles"
    ui_Details:           string = "% meshes · % triangles · % vertices"
    err_RangeUnsupported: string = "The scene is too large to frame safely."
}

private const FrenchStringsName = "lang/fr/scope.scene3d.tweak"
private const FrenchStrings = #include("../../../datas/lang/fr/scope.scene3d.tweak")
private var g_Texts: Texts
func texts()->const *Texts => &g_Texts

func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.scene3d")
}

#run { expect Gui.validateStrings'Texts(cast(string, FrenchStrings)) }
