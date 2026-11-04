#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#test
{
    const Home = "/home/example"
    const Key  = "XDG_DOWNLOAD_DIR"
    Swag.require(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"$HOME/Downloads\"", Key, Home) == "/home/example/Downloads")
    Swag.require(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"${HOME}/My Downloads\"", Key, Home) == "/home/example/My Downloads")
    Swag.require(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"$HOME\"", Key, Home) == Home)
    Swag.require(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"/mnt/é.事\" # redirected", Key, Home) == "/mnt/é.事")
    Swag.require(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"/mnt/\\$literal\"", Key, Home) == "/mnt/$literal")
    Swag.require(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"/first\"\nXDG_DOWNLOAD_DIR=\"/second\"", Key, Home) == "/second")
    Swag.require(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"$HOME\"", Key, "").isEmpty())
    Swag.require(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"$HOME/Downloads\"", Key, "/bad\0home").isEmpty())
    for invalid in ["# XDG_DOWNLOAD_DIR=\"/ignored\"",
                    "XDG_DOWNLOAD_DIR_EXTRA=\"/ignored\"",
                    "XDG_DOWNLOAD_DIR=\"relative\"",
                    "XDG_DOWNLOAD_DIR=\"$OTHER/path\"",
                    "XDG_DOWNLOAD_DIR=\"/tmp/$(command)\"",
                    "XDG_DOWNLOAD_DIR=\"/tmp/`command`\"",
                    "XDG_DOWNLOAD_DIR=\"/unterminated",
                    "XDG_DOWNLOAD_DIR=\"/ok\"; command",
                    "XDG_DOWNLOAD_DIR=\"/ok\0ignored\""] do
        Swag.require(Env.userDirectoryFromConfig(invalid, Key, Home).isEmpty())
}

#[Swag.TestTag("integration.system")]
#test
{
    let temporary = Env.realSpecialDirectory(.Temp)
    Swag.require(not temporary.isEmpty() and Path.isRooted(temporary))
    Swag.require(Env.realSpecialDirectory(.CommonAppData) == "/var/lib")
    Swag.require(Env.realSpecialDirectory(.Font) == "/usr/share/fonts")
    Swag.require(Env.realSpecialDirectory(.CommonPictures).isEmpty())
    Swag.require(Env.realSpecialDirectory(.CommonVideos).isEmpty())
    Swag.require(Env.realSpecialDirectory(.CommonMusic).isEmpty())

    // Missing or relative HOME/XDG overrides must use their fallback without asserting.
    for what in [Env.SpecialDirectory.UserAppData, .UserDocuments, .Desktop, .Downloads, .UserPictures, .UserVideos, .UserMusic]
    {
        let directory = Env.realSpecialDirectory(what)
        Swag.require(directory.isEmpty() or Path.isRooted(directory))
    }

    if Env.isSandboxed()
    {
        let documents = Env.getSpecialDirectory(.UserDocuments)
        let data      = Env.getSpecialDirectory(.UserAppData)
        Swag.require(documents != data)
        Swag.require(Env.isInsideSandbox(documents) and Env.isInsideSandbox(data))
        Swag.require(Directory.exists(documents) and Directory.exists(data))
    }
}
