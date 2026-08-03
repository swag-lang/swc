#global using Core, Pixel, Gui

#message(Swag.CompilerMsgMask.PassBeforeOutput)
{
    let cfg = notnull @compiler.getBuildCfg()
    cfg.resAppIcoFileName = Path.directoryName(#file) ++ "/../datas/appicon.ico"
}
