#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux

using Core

#init
{
    Swag.require(Env.isSandboxed(), "Core must arm the sandbox before an importing module initializes")
}

#premain
{
    Swag.require(Env.isSandboxed())
}

#test
{
    Swag.require(Env.isSandboxed())
}
