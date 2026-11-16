#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Named CSS font families match without regard to case, including quoted and fallback names.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let source = "<style>#mono{font-family:'Courier New'} #serif{font:italic 18px \"Georgia\"} #stack{font-family:'Unavailable Face',CaMbRiA}</style><p id='mono'>Mono</p><p id='serif'>Serif</p><p id='stack'>Fallback</p>"
    let view   = HtmlView.createText(&host.root, source)
    view.resize(640, 360)
    view.applyLayout()
    view.rebuild()
    Swag.require(view.layout.styleOfNode(view.elementById("mono")).fontFamily == .Mono)
    Swag.require(view.layout.styleOfNode(view.elementById("serif")).fontFamily == .Serif)
    Swag.require(view.layout.styleOfNode(view.elementById("stack")).fontFamily == .Serif)
}
