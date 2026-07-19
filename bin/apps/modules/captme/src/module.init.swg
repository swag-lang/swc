#global using Core, Pixel, Gui
#global #[Swag.ExplicitNullability]

#message(Swag.CompilerMsgMask.PassBeforeOutput)
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()
    cfg.resAppIcoFileName = Path.getDirectoryName(#file) ++ "/datas/appicon.ico"
}

func captmeFont(font: #null *Font)->#nonull *Font
{
    Debug.assert(font != null)
    return font orelse cast(#nonull *Font) 1'u64
}
