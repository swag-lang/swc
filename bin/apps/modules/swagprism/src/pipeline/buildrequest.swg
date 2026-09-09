#global internal
#global namespace Pipeline

using Core

enum BuildPreset
{
    Release
    Devmode
}

struct BuildSettings
{
    preset:        BuildPreset
    optimization:  Swag.BuildCfgBackendOptimLevel
    configuration: String
}

impl BuildSettings
{
    const DefaultConfiguration = cast(string) #include("../../datas/preview/configuration.txt")

    // Applied inside module.swg: an explicit CLI build preset would overwrite user edits.
    // These are the preset deltas from the compiler's implicit devmode configuration.
    mtd presetSource()->string
    {
        if .preset == .Devmode do
            return ""
        return """\
            #run
            {
                with let cfg = Swag.compiler().getBuildCfg()!
                {
                    .safetyGuards = .None
                    .allocatorLeaks = false
                    .errorStackTrace = false
                    .backend.vectorize = true
                    .backend.fpMathFma = true
                    .backend.fpMathNoNaN = true
                    .backend.fpMathNoInf = true
                    .backend.fpMathNoSignedZero = true
                    .backend.inlineMode = .Auto
                }
            }
            """
    }

    mtd matches(other: BuildSettings)->bool => .preset == other.preset and .optimization == other.optimization and .configuration == other.configuration
}

// An execution build can also print a microcode stage for another panel.
struct BuildRequest
{
    source:   String
    stage:    String
    kind:     ViewerKind
    settings: BuildSettings
}

impl BuildRequest
{
    mtd matches(other: BuildRequest)->bool     => .kind == other.kind and .stage == other.stage and .sameProgram(other)
    mtd sameProgram(other: BuildRequest)->bool => .source == other.source and .settings.matches(other.settings)

    mtd satisfies(other: BuildRequest)->bool => .kind == other.kind and .sameProgram(other) and (.stage == other.stage or other.stage.isEmpty())

    /*
    Whether the snippet has to be compiled against the standard module its viewer builds on.

    A rendering or interface preview always does: the host program calls into what the snippet
    declares, through `pixel` or `gui`. A microcode snippet usually does not — it is one function
    over primitives — and that import is by far the most expensive part of compiling one, because
    the module's public API is analyzed again from source on every keystroke: 294 ms against
    122 ms, measured on `core`.

    Naming the module is the only way a snippet can reach into it, as a qualified access or as a
    `using`, so scanning the source for the namespace answers the question. A snippet that names it
    in a comment or a string buys a slower compilation, never a wrong one.
    */
    mtd needsDependency()->bool
    {
        if .kind != .Microcode do
            return true
        return Utf8.indexOf(cast(const [..] u8) .source.toString(), "Core") != Swag.U64.Max
    }

    mtd moduleSource()->String
    {
        let dependency = .kind == .Microcode ? "core" : (.kind == .Render2D ? "pixel" : "gui")
        let backend    = .kind == .Microcode ? "StaticLibrary" : "SharedLibrary"

        var result: retval
        if .needsDependency() do
            result.appendFormat("#import(\"%\", location: \"swag@std\")\n", dependency)
        result.appendFormat("%\n#run { Swag.compiler().getBuildCfg()!.backend.optimLevel = .O% }\n%\n#run\n{\n    with let cfg = Swag.compiler().getBuildCfg()!\n    {\n        .backendKind = .%\n        .publishDependencies = true\n    }\n}\n", .settings.presetSource(), cast(u8) .settings.optimization, .settings.configuration, backend)
        return result
    }
}
