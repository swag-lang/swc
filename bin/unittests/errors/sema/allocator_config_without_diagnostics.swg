#global if not #hastag("Swag.AllocatorDiagnostics")
#global private

#test
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.allocatorCaptureStack = true     // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.allocatorLeaks = true     // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.allocatorTrackAllocations = true     // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.allocatorElectricMode = true     // swc-expected-error {{sema_err_unknown_symbol}}
}

#test
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.allocatorFillMemory = true     // swc-expected-error {{sema_err_unknown_symbol}}
}
