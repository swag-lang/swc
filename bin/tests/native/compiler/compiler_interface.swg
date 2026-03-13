#global fileprivate // swc-option suite-test

const BuildCfgValue = #run dref @compiler.getBuildCfg()

#assert(#run @compiler.getMessage() != null)
#assert(#typeof(BuildCfgValue) == Swag.BuildCfg)

#test
{
    #assert(BuildCfgValue.backendKind == Swag.BuildCfgBackendKind.Executable or
            BuildCfgValue.backendKind == Swag.BuildCfgBackendKind.Library or
            BuildCfgValue.backendKind == Swag.BuildCfgBackendKind.Export)
}

#test
{
    const V = #run @compiler.compileString(1) // swc-expected-error {{sema_err_too_many_arguments}}
}
