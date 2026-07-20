#global using Core, Pixel, Gui

#message(Swag.CompilerMsgMask.PassBeforeOutput)
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()
    cfg.resAppIcoFileName = Path.getDirectoryName(#file) ++ "/datas/appicon.ico"
}

func captmeFont(font: #null *Font)->*Font
{
    Debug.assert(font != null)
    return font orelse cast(*Font) 1'u64
}
