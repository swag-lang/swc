#global if #os == Swag.TargetOs.Linux
#global namespace Env

private func homeDirectory()->String
{
    let home = variable("HOME")
    if Path.isValidPathName(home) and Path.isRooted(home) do
        return home
    var buffer: Array'u8
    buffer.resize(1024)
    for
    {
        var entry: Linux.passwd
        var found: *Linux.passwd?
        let error = Linux.getpwuid_r(Linux.getuid(), &entry, buffer.storage(), buffer.count, &found)
        if error == Linux.ERANGE
        {
            if buffer.count > Swag.U32.Max / 2 do
                return ""
            buffer.resize(buffer.count * 2)
            continue
        }

        if error != 0 or not found or not entry.pw_dir do
            return ""
        let result = String.from(cast(string, cast(cstring, entry.pw_dir)))
        return Path.isValidPathName(result) and Path.isRooted(result) ? result : String{}
    }
}

// XDG base directory variables must be absolute; a relative value is ignored.
private func xdgBaseDirectory(name, home, fallback: string)->String
{
    let configured = variable(name)
    if Path.isValidPathName(configured) and Path.isRooted(configured) do
        return configured
    return Path.combine(home, fallback)
}

private func userDirectoryValue(value, home: string)->String
{
    if value.count < 2 or value[0] != '"' do
        return ""
    var result: String
    var cursor = 1'u64
    if Utf8.startsWith(value[1 to], "$HOME") and
       value.count > 6 and
       (value[6] == '/' or value[6] == '"')
    {
        result = home
        cursor = 6
    }
    elif Utf8.startsWith(value[1 to], "${HOME}") and
         value.count > 8 and
         (value[8] == '/' or value[8] == '"')
    {
        result = home
        cursor = 8
    }
    elif value[1] != '/'
    {
        return ""
    }

    while cursor < value.count
    {
        let byte = value[cursor]
        if byte == '"'
        {
            let trailing = Latin1.trim(value[cursor + 1 to])
            if trailing.count != 0 and trailing[0] != '#' do
                return ""
            if not Path.isValidPathName(result) or not Path.isRooted(result) do
                return ""
            return result
        }

        if byte == '\\'
        {
            cursor += 1
            if cursor == value.count do
                return ""
            let escaped = value[cursor]
            if escaped != '\\' and escaped != '"' and escaped != '$' and escaped != '`' do
                result += '\\'u8
            result += escaped
        }
        elif byte == '$' or byte == '`'
        {
            return ""
        }
        else
        {
            result += byte
        }

        cursor += 1
    }

    return ""
}

// Parse data only: user-dirs.dirs is not executed as a shell program.
internal func userDirectoryFromConfig(contents, name, home: string)->String
{
    var result: #returntype
    for raw in Tokenize.splitLines(contents)
    {
        let line = Latin1.trim(raw)
        if not Utf8.startsWith(line, name) do
            continue
        let suffix = Latin1.trim(line[name.count to])
        if not suffix.count or suffix[0] != '=' do
            continue
        let decoded = userDirectoryValue(Latin1.trim(suffix[1 to]), home)
        if not decoded.isEmpty() do
            result = decoded
    }

    return result
}

private func userDirectory(name, home, fallback: string)->String
{
    let configRoot = xdgBaseDirectory("XDG_CONFIG_HOME", home, ".config")
    let configPath = Path.combine(configRoot, "user-dirs.dirs")
    let contents   = catch File.readAllText(configPath) { return Path.combine(home, fallback) }
    let configured = userDirectoryFromConfig(contents, name, home)
    return configured.isEmpty() ? Path.combine(home, fallback) : configured
}

// Returns a Linux special directory, redirected inside the process sandbox when it is armed.
//
// Returns an empty string when the corresponding real directory cannot be resolved. Sandboxed
// queries instead use a distinct scratch directory for every kind.
public func getSpecialDirectory(what: SpecialDirectory)->String
{
    if isSandboxed() do
        return sandboxSpecialDirectory(what)
    return realSpecialDirectory(what)
}

// Resolves a Linux special directory without applying the process sandbox.
//
// Temp uses TMPDIR (resolved against the current directory), or /tmp. Home uses absolute HOME,
// falling back to the user database. UserAppData follows XDG_DATA_HOME; desktop and media folders
// read quoted absolute or $HOME paths in XDG_CONFIG_HOME/user-dirs.dirs, with conventional home
// subdirectories as defaults. No shell code is executed. Font is /usr/share/fonts and CommonAppData
// is /var/lib. Shared pictures, videos and music have no standard Linux location and return empty.
// The returned location is not created or required to exist; unresolved homes return empty.
public func realSpecialDirectory(what: SpecialDirectory)->String
{
    switch what
    {
    case .Temp:
        let configured = variable("TMPDIR")
        if configured.isEmpty() do
            return "/tmp"
        return catch Path.absolute(configured) { return "" }

    case .Font:
        return "/usr/share/fonts"

    case .CommonAppData:
        return "/var/lib"

    case .CommonPictures, .CommonVideos, .CommonMusic:
        return ""
    }

    let home = homeDirectory()
    if home.isEmpty() do
        return ""
    switch #complete what
    {
    case .UserAppData:   return xdgBaseDirectory("XDG_DATA_HOME", home, ".local/share")
    case .UserDocuments: return userDirectory("XDG_DOCUMENTS_DIR", home, "Documents")
    case .Desktop:       return userDirectory("XDG_DESKTOP_DIR", home, "Desktop")
    case .Downloads:     return userDirectory("XDG_DOWNLOAD_DIR", home, "Downloads")
    case .UserPictures:  return userDirectory("XDG_PICTURES_DIR", home, "Pictures")
    case .UserVideos:    return userDirectory("XDG_VIDEOS_DIR", home, "Videos")
    case .UserMusic:     return userDirectory("XDG_MUSIC_DIR", home, "Music")
    case .Temp, .Font, .CommonAppData, .CommonPictures, .CommonVideos, .CommonMusic: unreachable
    }
}
