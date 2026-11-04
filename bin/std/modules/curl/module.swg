/*
Raw libcurl C ABI declarations for Linux x86-64 consumers.

Names and contracts follow the [libcurl API reference](https://curl.se/libcurl/c/).
Function pointers borrow a loaded `libcurl.so.4`; this module neither loads the library
nor initializes it. Native allocations retain libcurl's matching cleanup obligations.
Net owns HTTP request policy, bounded response storage, and error translation.
*/
#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.moduleVersion     = #swcversion
    cfg.moduleRevision    = #swcrevision
    cfg.moduleBuildNum    = #swcbuildnum
    cfg.moduleNamespace   = "Curl"
    cfg.backendKind       = .Export
    cfg.repoPath          = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/curl"
    cfg.genDoc.kind       = .Api
    cfg.genDoc.outputName = "std.curl"
    cfg.genDoc.icon       = "favicon.svg"
    cfg.genDoc.css        = "css/style.css"
}
