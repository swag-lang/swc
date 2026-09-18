#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

#test
{
    var host: Testing.HeadlessHost
    host.setup(280, 60)
    defer host.shutdown()

    let password = PasswordEdit.create(&host.root, {20, 20, 240, 26})
    password.setPlaceholder("Password")
    host.focus(password.edit)
    host.sendRune(Input.Key.A, 'A')
    host.sendRune(Input.Key.A, '\u00E9')
    host.sendRune(Input.Key.A, '\U0001F642')

    Swag.assert(password.edit.text() == "***")
    Swag.assert(Slice.equals(password.bytes(), cast(const [..] u8) "A\u00E9\U0001F642"))
    Swag.assert(password.byteCount == 7)

    host.keyPress(Input.Key.Left)
    host.keyPress(Input.Key.Back)
    Swag.assert(password.edit.text() == "**")
    Swag.assert(Slice.equals(password.bytes(), cast(const [..] u8) "A\U0001F642"))

    password.selectAll()
    host.sendRune(Input.Key.B, 'Z')
    Swag.assert(password.edit.text() == "*")
    Swag.assert(Slice.equals(password.bytes(), cast(const [..] u8) "Z"))
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(280, 60)
    defer host.shutdown()

    let password = PasswordEdit.create(&host.root, {20, 20, 240, 26})
    host.focus(password.edit)
    host.sendRune(Input.Key.A, 's')
    host.sendRune(Input.Key.A, 'e')
    host.sendRune(Input.Key.A, 'c')
    host.sendRune(Input.Key.A, 'r')
    host.sendRune(Input.Key.A, 'e')
    host.sendRune(Input.Key.A, 't')

    host.shortcut(Input.Key.V, Input.KeyModifiers.Control)
    host.shortcut(Input.Key.Insert, Input.KeyModifiers.Shift)
    Swag.assert(Slice.equals(password.bytes(), cast(const [..] u8) "secret"))
    Swag.assert(password.edit.text() == "******")

    password.clear()
    Swag.assert(password.isEmpty())
    Swag.assert(password.edit.text() == "")
    for byte in password.storage do
        Swag.assert(byte == 0)
}

// A password field refuses dropped text: it would show in clear and never reach the password.
#test
{
    var host: Testing.HeadlessHost
    host.setup(280, 60)
    defer host.shutdown()

    let password = PasswordEdit.create(&host.root, {20, 20, 240, 26})
    let rect     = password.edit.surfaceRect()
    let effect   = host.dropText({rect.center().x, rect.center().y}, "secret")
    Swag.assert(effect == .None)
    Swag.assert(password.edit.text() == "")
    Swag.assert(password.byteCount == 0)
}
