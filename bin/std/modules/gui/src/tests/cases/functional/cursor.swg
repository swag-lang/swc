#global if #command == Swag.CompilerCommand.Test
#global private

#test
{
    let hidden = Cursor.from(.Hidden)
    let arrow  = Cursor.from(.Arrow)
    var invalid: Cursor

    Swag.require(hidden.isValid() and hidden.isHidden())
    Swag.require(arrow.isValid() and not arrow.isHidden())
    Swag.require(not invalid.isValid() and not invalid.isHidden())

    invalid = hidden
    invalid.clear()
    Swag.require(not invalid.isValid() and not invalid.isHidden())

    var host: Testing.HeadlessHost
    host.setup(320, 200)
    host.app.setCursorHidden(true)
    Swag.require(host.app.isCursorHidden())
    host.app.setCursorHidden(false)
    Swag.require(not host.app.isCursorHidden())
}

// Cursor state can be selected before a renderer creates any native resources.
#test
{
    var app: Application
    app.setCursorHidden(true)
    Swag.require(app.isCursorHidden())
    app.setCursorHidden(false)
    Swag.require(not app.isCursorHidden())
}
