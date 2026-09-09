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

    mtd moduleSource()->String
    {
        let dependency = .kind == .Microcode ? "core" : (.kind == .Render2D ? "pixel" : "gui")
        let backend    = .kind == .Microcode ? "StaticLibrary" : "SharedLibrary"
        return Format.toString("#import(\"%\", location: \"swag@std\")\n%\n#run { Swag.compiler().getBuildCfg()!.backend.optimLevel = .O% }\n%\n#run\n{\n    with let cfg = Swag.compiler().getBuildCfg()!\n    {\n        .backendKind = .%\n        .publishDependencies = true\n    }\n}\n", dependency, .settings.presetSource(), cast(u8) .settings.optimization, .settings.configuration, backend)
    }
}
