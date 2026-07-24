#global using Core, Pixel, Gui

#message(Swag.CompilerMsgMask.PassBeforeOutput)
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.resAppIcoFileName = Path.getDirectoryName(#file) ++ "/datas/appicon.ico"
}

func captmeFont(font: #null *Font)->*Font
{
    return notnull font
}
