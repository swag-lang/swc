#global if #os == Swag.TargetOs.Linux
#global namespace Env

#[Swag.NoCopy]
private struct DesktopRegistration
{
    library:            *void?
    late createKeyFile: Linux.g_key_file_new_fn
    late freeKeyFile:   Linux.g_key_file_unref_fn
    late loadKeyFile:   Linux.g_key_file_load_from_file_fn
    late hasKey:        Linux.g_key_file_has_key_fn
    late setString:     Linux.g_key_file_set_string_fn
    late keyFileData:   Linux.g_key_file_to_data_fn
    late writeContents: Linux.g_file_set_contents_fn
    late escapeMarkup:  Linux.g_markup_escape_text_fn
    late freeMemory:    Linux.g_free_fn
    late createApp:     Linux.g_desktop_app_info_new_from_filename_fn
    late freeObject:    Linux.g_object_unref_fn
    late contentType:   Linux.g_content_type_guess_fn
    late addType:       Linux.g_app_info_add_supports_type_fn
    late defaultType:   Linux.g_app_info_set_as_default_for_type_fn
}

private impl DesktopRegistration
{
    mtd opDrop()
    {
        if .library do
            discard Linux.dlclose(.library)
    }

    func load()->DesktopRegistration fail
    {
        func(T) symbol(handle: *void, name: string)->T fail
        {
            let pointer = Linux.dlsym(handle, String.from(name).storage())
            if not pointer do
                fail Swag.SystemError{"a required GIO desktop integration symbol is unavailable"}
            return cast(T, pointer)
        }

        var result: #returntype

        // GObject registers process-global types whose callbacks remain valid after this
        // request. NODELETE keeps their code mapped even when Core itself is unloaded.
        result.library = Linux.dlopen("libgio-2.0.so.0".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL | Linux.RTLD_NODELETE)
        let handle = result.library
        if not handle do
            fail Swag.SystemError{"cannot load libgio-2.0.so.0"}
        result.createKeyFile = try symbol'Linux.g_key_file_new_fn(handle, "g_key_file_new")
        result.freeKeyFile   = try symbol'Linux.g_key_file_unref_fn(handle, "g_key_file_unref")
        result.loadKeyFile   = try symbol'Linux.g_key_file_load_from_file_fn(handle, "g_key_file_load_from_file")
        result.hasKey        = try symbol'Linux.g_key_file_has_key_fn(handle, "g_key_file_has_key")
        result.setString     = try symbol'Linux.g_key_file_set_string_fn(handle, "g_key_file_set_string")
        result.keyFileData   = try symbol'Linux.g_key_file_to_data_fn(handle, "g_key_file_to_data")
        result.writeContents = try symbol'Linux.g_file_set_contents_fn(handle, "g_file_set_contents")
        result.escapeMarkup  = try symbol'Linux.g_markup_escape_text_fn(handle, "g_markup_escape_text")
        result.freeMemory    = try symbol'Linux.g_free_fn(handle, "g_free")
        result.createApp     = try symbol'Linux.g_desktop_app_info_new_from_filename_fn(handle, "g_desktop_app_info_new_from_filename")
        result.freeObject    = try symbol'Linux.g_object_unref_fn(handle, "g_object_unref")
        result.contentType   = try symbol'Linux.g_content_type_guess_fn(handle, "g_content_type_guess")
        result.addType       = try symbol'Linux.g_app_info_add_supports_type_fn(handle, "g_app_info_add_supports_type")
        result.defaultType   = try symbol'Linux.g_app_info_set_as_default_for_type_fn(handle, "g_app_info_set_as_default_for_type")
        return result
    }

    func validId(value: string)->bool
    {
        if value.count == 0 or value.count > 128 or value == "." or value == ".." do
            return false
        for byte in value
        {
            if not ((byte >= 'a' and byte <= 'z') or
                    (byte >= 'A' and byte <= 'Z') or
                    (byte >= '0' and byte <= '9') or
                    byte == '.' or
                    byte == '_' or
                    byte == '-') do
                return false
        }

        return true
    }

    func validText(value: string)->bool
    {
        if value.count == 0 or value.count > 4096 or not Utf8.isValid(cast(const [..] u8, value)) do
            return false
        for byte in value where byte < 32 or byte == 127 do
            return false
        return true
    }

    func execCommand(path: string)->String
    {
        // Desktop launchers inspect the first command word before expanding field codes.
        // Keep the executable pathname as an argument so its literal percent signs survive
        // both stages. env replaces itself directly; no shell interprets the command.
        var command: String = "/usr/bin/env -- \""
        for byte in path
        {
            if byte == '\\' or byte == '"' or byte == '$' or byte == '`' do
                command += '\\'u8
            command += byte
            if byte == '%' do
                command += '%'u8
        }

        command += "\" %f"
        return command
    }

    mtd const saveDesktop(appName, friendly, appPath: string)->String fail
    {
        if not validId(appName) or
           not validText(appPath) or
           not Path.isRooted(appPath) or
           (friendly.count != 0 and not validText(friendly)) do
            fail Swag.SystemError{"desktop registration needs an application identifier and an absolute executable path"}
        let folder = Path.combine(getSpecialDirectory(.UserAppData), "applications")
        try Directory.create(folder, recurse: true)
        let path    = Path.combine(folder, Format.toString("%.desktop", appName))
        let keyFile = .createKeyFile()
        defer .freeKeyFile(keyFile)
        if File.exists(path) and .loadKeyFile(keyFile, path.storage(), Linux.G_KEY_FILE_KEEP_COMMENTS | Linux.G_KEY_FILE_KEEP_TRANSLATIONS, null) == 0 do
            fail Swag.SystemError{"cannot read the existing desktop entry"}
        .setString(keyFile, "Desktop Entry".buffer, "Type".buffer, "Application".buffer)
        .setString(keyFile, "Desktop Entry".buffer, "Exec".buffer, execCommand(appPath).storage())
        .setString(keyFile, "Desktop Entry".buffer, "Terminal".buffer, "false".buffer)
        .setString(keyFile, "Desktop Entry".buffer, "TryExec".buffer, String.from(appPath).storage())
        if friendly.count != 0 or .hasKey(keyFile, "Desktop Entry".buffer, "Name".buffer, null) == 0
        {
            let displayName = String.from(friendly.count != 0 ? friendly : appName)
            .setString(keyFile, "Desktop Entry".buffer, "Name".buffer, displayName.storage())
        }

        var length: u64
        let data = .keyFileData(keyFile, &length, null)
        if not data do
            fail Swag.SystemError{"cannot serialize the desktop entry"}
        defer .freeMemory(data)
        if .writeContents(path.storage(), data, cast(s64, length), null) == 0 do
            fail Swag.SystemError{"cannot save the desktop entry"}
        return path
    }

    mtd const extensionType(extension, description: string, updateDescription: bool)->String fail
    {
        if extension.count < 2 or extension[0] != '.' or not validId(extension[1 to]) do
            fail Swag.SystemError{"file association needs a dotted filename extension"}
        let filename = Format.toString("file%", extension)
        let guessed  = .contentType(filename.storage(), null, 0, null)
        if not guessed do
            fail Swag.SystemError{"cannot determine the filename extension's content type"}
        defer .freeMemory(guessed)
        let known = cast(string, cast(cstring, guessed))
        let mime  = Format.toString("application/x-swag-extension-%", extension[1 to])
        if known != "application/octet-stream" and (known != mime.toString() or not updateDescription) do
            return String.from(known)

        // Unknown extensions get their own shared-mime-info type. Never associate an
        // application with every arbitrary binary file through application/octet-stream.
        let escaped = .escapeMarkup(description.buffer, cast(s64, description.count))
        if not escaped do
            fail Swag.SystemError{"cannot encode the file type description"}
        defer .freeMemory(escaped)
        const Template = """<?xml version="1.0" encoding="UTF-8"?>
                            <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
                              <mime-type type="%">
                                <comment>%</comment>
                                <glob pattern="*%"/>
                              </mime-type>
                            </mime-info>
                            """
        let xml      = Format.toString(Template, mime, cast(string, cast(cstring, escaped)), extension)
        let mimeRoot = Path.combine(getSpecialDirectory(.UserAppData), "mime")
        let packages = Path.combine(mimeRoot, "packages")
        try Directory.create(packages, recurse: true)
        let path = Path.combine(packages, Format.toString("swag-extension-%.xml", extension[1 to]))
        if .writeContents(path.storage(), xml.storage(), cast(s64, xml.length), null) == 0 do
            fail Swag.SystemError{"cannot save the file type definition"}
        let arguments = [mimeRoot.toString()]
        with let info = StartInfo{fileName: "update-mime-database", arguments: arguments}
        {
            .standardInput  = .Discard
            .standardOutput = .Discard
            .standardError  = .Discard
        }

        var process = try startProcess(info)
        defer
        {
            if process.isRunning() do
                discard catch process.kill()
        }

        let finished = try process.tryWaitForExit(Time.Duration.fromMilliseconds(2000))
        if not finished or process.exitCode() != 0 do
            fail Swag.SystemError{"cannot update the user MIME database"}
        return mime
    }

    mtd const associate(extension, appName, appPath, description: string, claim: bool)->bool fail
    {
        if not validId(appName) or
           not validText(appPath) or
           not Path.isRooted(appPath) or
           not validText(description) do
            fail Swag.SystemError{"file association needs an application identifier, an absolute path and a UTF-8 description"}
        let mime    = try .extensionType(extension, description, claim)
        let desktop = try .saveDesktop(appName, "", appPath)
        let created = .createApp(desktop.storage())
        if not created do
            return false
        let app: *void = created
        defer .freeObject(app)
        return claim ? .defaultType(app, mime.storage(), null) != 0 : .addType(app, mime.storage(), null) != 0
    }
}

// Registers a per-user XDG desktop entry with `appFriendly` as its display name.
//
// Uses the current executable through `/usr/bin/env` and preserves existing entry keys.
// Invalid identifiers, paths,
// missing GIO and write failures are ignored, matching the registration API's void result.
// A sandbox refuses registration. No session bus or running graphical desktop is required.
public func registerApplication(appName, appFriendly: string)
{
    if denySystemMutation(.ApplicationRegistration) do
        return
    var native = catch DesktopRegistration.load() { return; }
    discard catch native.saveDesktop(appName, appFriendly, executablePath())
}

// Offers `appName` in the current user's XDG Open With list for `extension`.
//
// Leaves the MIME type's default handler unchanged. `appPath` must be absolute; `extension`
// includes its leading dot. Known extensions share their system MIME type; unknown extensions
// get a user MIME definition. Requires GIO, `/usr/bin/env` and, for unknown types,
// `update-mime-database`.
// Returns `false` for sandbox refusal, invalid inputs, unavailable services or failed writes.
// Registration can be partially written on failure; retrying updates the same desktop entry.
#[Swag.Discardable]
public func associateFileExtension(extension, appName, appPath: string)->bool
{
    if denySystemMutation(.FileAssociation) do
        return false
    var native = catch DesktopRegistration.load() { return false }
    return catch native.associate(extension, appName, appPath, appName, false) { return false }
}

// Makes `appPath` the current user's default XDG handler for `extension`'s MIME type.
//
// `progId` identifies a stable desktop entry. Known MIME types also cover their other filename
// extensions; unknown types receive a user definition labelled with `description`. The command
// passes one opened filename through `/usr/bin/env`. Requires GIO and, for unknown types,
// `update-mime-database`.
// Returns `false` for sandbox refusal, invalid inputs, unavailable services or failed writes.
// Earlier successful writes remain on failure; retrying updates the same registration.
#[Swag.Discardable]
public func claimFileExtension(extension, progId, description, appPath: string)->bool
{
    if denySystemMutation(.FileAssociation) do
        return false
    var native = catch DesktopRegistration.load() { return false }
    return catch native.associate(extension, progId, appPath, description, true) { return false }
}
