#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#test
{
    const Home = "/home/example"
    const Key  = "XDG_DOWNLOAD_DIR"
    Swag.assert(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"$HOME/Downloads\"", Key, Home) == "/home/example/Downloads")
    Swag.assert(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"${HOME}/My Downloads\"", Key, Home) == "/home/example/My Downloads")
    Swag.assert(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"$HOME\"", Key, Home) == Home)
    Swag.assert(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"/mnt/é.事\" # redirected", Key, Home) == "/mnt/é.事")
    Swag.assert(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"/mnt/\\$literal\"", Key, Home) == "/mnt/$literal")
    Swag.assert(Env.userDirectoryFromConfig("XDG_DOWNLOAD_DIR=\"/first\"\nXDG_DOWNLOAD_DIR=\"/second\"", Key, Home) == "/second")
    for invalid in ["# XDG_DOWNLOAD_DIR=\"/ignored\"",
                    "XDG_DOWNLOAD_DIR_EXTRA=\"/ignored\"",
                    "XDG_DOWNLOAD_DIR=\"relative\"",
                    "XDG_DOWNLOAD_DIR=\"$OTHER/path\"",
                    "XDG_DOWNLOAD_DIR=\"/tmp/$(command)\"",
                    "XDG_DOWNLOAD_DIR=\"/tmp/`command`\"",
                    "XDG_DOWNLOAD_DIR=\"/unterminated",
                    "XDG_DOWNLOAD_DIR=\"/ok\"; command",
                    "XDG_DOWNLOAD_DIR=\"/ok\0ignored\""] do
        Swag.assert(Env.userDirectoryFromConfig(invalid, Key, Home).isEmpty())
}

#[Swag.TestTag("integration.system")]
#test
{
    let temporary = Env.realSpecialDirectory(.Temp)
    Swag.assert(not temporary.isEmpty() and Path.isRooted(temporary))
    Swag.assert(Env.realSpecialDirectory(.CommonAppData) == "/var/lib")
    Swag.assert(Env.realSpecialDirectory(.Font) == "/usr/share/fonts")
    Swag.assert(Env.realSpecialDirectory(.CommonPictures).isEmpty())
    Swag.assert(Env.realSpecialDirectory(.CommonVideos).isEmpty())
    Swag.assert(Env.realSpecialDirectory(.CommonMusic).isEmpty())
    if Env.isSandboxed()
    {
        let documents = Env.getSpecialDirectory(.UserDocuments)
        let data      = Env.getSpecialDirectory(.UserAppData)
        Swag.assert(documents != data)
        Swag.assert(Env.isInsideSandbox(documents) and Env.isInsideSandbox(data))
        Swag.assert(Directory.exists(documents) and Directory.exists(data))
    }
}
