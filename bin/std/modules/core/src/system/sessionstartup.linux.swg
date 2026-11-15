#global if #os == Swag.TargetOs.Linux
#global namespace Env

internal func setSessionStartupNative(id, displayName: string, enabled: bool, arguments: const [..] string)->bool fail
{
    var root = variable("XDG_CONFIG_HOME")
    if root.isEmpty() or not Path.isRooted(root)
    {
        let homeDirectory = variable("HOME")
        if not Path.isRooted(homeDirectory) do
            fail Errors.BadParameterError{}
        root = Path.combine(homeDirectory, ".config")
    }

    let directory = Path.combine(root, "autostart")
    let path      = Path.combine(directory, Format.toString("%.desktop", id))
    if not enabled
    {
        if File.exists(path) do
            try File.delete(path)
        return true
    }

    func quote(value: string)->String
    {
        var result: String = "\""
        for byte in value
        {
            // Exec is first decoded as a desktop string, then as quoted arguments.
            if byte == '\\'
            {
                result += "\\\\\\\\"
            }
            elif byte == '"' or byte == '$' or byte == '`'
            {
                result += "\\\\"
                result += byte
            }
            else
            {
                result += byte
            }

            if byte == '%' do
                result += '%'u8
        }

        result += '"'u8
        return result
    }

    var command = quote(try Process.currentExecutablePath())
    for argument in arguments
    {
        command += ' 'u8
        command += quote(argument)
    }

    var name = String.from(displayName)
    name.replace("\\", "\\\\")
    const Template = """[Desktop Entry]
                        Type=Application
                        Name=%
                        Exec=%
                        Terminal=false
                        """
    try Directory.create(directory, recurse: true)

    // Publish a complete entry in one rename, so a failed write cannot replace the old policy.
    let temporary = Path.combine(directory, Format.toString("%.%.tmp", id, Guid64.random()))
    defer discard catch File.delete(temporary)
    var stream = try File.open(temporary, .CreateNew, .Write, .Zero)
    try stream.writeAll(Format.toString(Template, name, command))
    try stream.flush()
    stream.close()
    try File.move(path, temporary)
    return true
}
