#global using Core, Pixel, Gui

#message(Swag.CompilerMsgMask.PassBeforeOutput)
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.resAppIcoFileName = Path.directoryName(#file) ++ "/../datas/appicon.ico"
}

func sCaptureFont(font: #null *Font)->*Font
{
    return notnull font
}
