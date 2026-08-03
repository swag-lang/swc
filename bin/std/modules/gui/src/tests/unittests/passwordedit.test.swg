#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func passwordBytesEqual(actual: const [..] u8, expected: string)->bool
{
    return @countof(actual) == @countof(expected) and
           @memcmp(@dataof(actual), @dataof(expected), @countof(actual)) == 0
}

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

    @assert(password.edit.text() == "***")
    @assert(passwordBytesEqual(password.bytes(), "A\u00E9\U0001F642"))
    @assert(password.byteCount == 7)

    host.keyPress(Input.Key.Left)
    host.keyPress(Input.Key.Back)
    @assert(password.edit.text() == "**")
    @assert(passwordBytesEqual(password.bytes(), "A\U0001F642"))

    password.selectAll()
    host.sendRune(Input.Key.B, 'Z')
    @assert(password.edit.text() == "*")
    @assert(passwordBytesEqual(password.bytes(), "Z"))
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
    @assert(passwordBytesEqual(password.bytes(), "secret"))
    @assert(password.edit.text() == "******")

    password.clear()
    @assert(password.isEmpty())
    @assert(password.edit.text() == "")
    for byte in password.storage do
        @assert(byte == 0)
}
