#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.process")]
#test
{
    let image = expect Env.Process.currentExecutablePath()
    Swag.assert(Path.isRooted(image.toString()) and File.exists(image.toString()))
    var environment = Env.currentEnvironment()
    let name        = "SWAG_PROCESS_SNAPSHOT_ONLY"
    let original    = Env.variable(name)
    environment.set(name, "local-value")
    Swag.assert(environment.value(name) == "local-value")
    Swag.assert(Env.variable(name) == original)
    environment.set("swag_process_snapshot_only", "different-case")
    Swag.assert(environment.value(name) == "local-value")
    Swag.assert(environment.value("swag_process_snapshot_only") == "different-case")
}
