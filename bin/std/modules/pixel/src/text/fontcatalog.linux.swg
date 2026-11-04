#global if #os == Swag.TargetOs.Linux

using Core

internal func linuxFontDirectories(userHome, dataHome: string)->Array'String
{
    var result: #returntype
    result.add("/usr/local/share/fonts")
    result.add("/usr/share/fonts")
    if Path.isValidPathName(dataHome) and Path.isRooted(dataHome)
    {
        let path = Path.combine(dataHome, "fonts")
        if not result.contains(path) do
            result.add(path)
    }

    if Path.isValidPathName(userHome) and Path.isRooted(userHome)
    {
        let path = Path.combine(userHome, ".fonts")
        if not result.contains(path) do
            result.add(path)
    }

    return result
}

public impl FontCatalog
{
    // Scans conventional Linux system and user font directories into a fresh catalog.
    //
    // Searches `/usr/local/share/fonts`, `/usr/share/fonts`, the user's XDG data directory
    // followed by `fonts`, and `$HOME/.fonts` when HOME is absolute. The XDG base follows
    // [[Core.Env.realSpecialDirectory]] with `UserAppData`, including its fallback rules.
    // Missing or unreadable directory trees and invalid font files are skipped. An empty
    // catalog means no readable supported faces were found. Does not consult Fontconfig,
    // resolve its aliases, or retain a process-wide snapshot; callers may keep their result.
    //
    // ```swag
    // let catalog = Pixel.FontCatalog.loadSystem()
    // let families = catalog.familyNames()
    // ```
    func loadSystem()->FontCatalog
    {
        var result: #returntype
        let directories = linuxFontDirectories(Env.variable("HOME"), Env.realSpecialDirectory(.UserAppData))
        for directory in directories do
            discard catch result.addDirectory(directory.toString())
        return result
    }
}
