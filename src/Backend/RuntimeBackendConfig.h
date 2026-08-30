#pragma once

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    // Controls which calls the semantic inliner expands.
    //  - Never:      no heuristic inlining; only mandatory expansions (macro/mixin).
    //  - MarkedOnly: also inline functions explicitly tagged #[Inline] (the historical
    //                behavior when optimization was on).
    //  - Auto:       MarkedOnly plus compiler-chosen small/cheap callees.
    // Default (and per-config presets) live in applyBuildCfgPreset. Keep these enums and the
    // field order below in sync with the Swag mirror in bin/runtime/api.swg (the user-visible
    // build config is read directly through that layout).
    enum class BuildCfgBackendInlineMode : uint8_t
    {
        Never      = 0,
        MarkedOnly = 1,
        Auto       = 2,
    };

    // How much of the backend optimizer a build asks for. The levels are ordered, and what
    // each one wires is decided here and nowhere else - a pass asks the level a question
    // through the predicates below rather than testing the level itself.
    //  - O0: no backend optimization at all.
    //  - O1: everything that does not cost compilation time. The `devmode` preset.
    //  - O2: also what does. The `release` preset.
    enum class BuildCfgBackendOptimLevel : uint8_t
    {
        O0 = 0,
        O1 = 1,
        O2 = 2,
    };

    struct BuildCfgBackend
    {
        BuildCfgBackendOptimLevel optimLevel = BuildCfgBackendOptimLevel::O0;
        bool                      vectorize;
        bool                      debugInfo;
        bool                      enableExceptions;
        bool                      fpMathFma;
        bool                      fpMathNoNaN;
        bool                      fpMathNoInf;
        bool                      fpMathNoSignedZero;
        bool                      fpMathUnsafe;
        bool                      fpMathApproxFunc;
        uint32_t                  unrollMemLimit;
        BuildCfgBackendInlineMode inlineMode = BuildCfgBackendInlineMode::MarkedOnly;

        // The optimizer runs at all.
        constexpr bool optimizes() const { return optimLevel != BuildCfgBackendOptimLevel::O0; }

        // Register allocation splits live intervals instead of assigning one register per
        // value for its whole life (compiler.optimization.024). Measured neutral on compilation time, so the
        // level it needs is the first one that optimizes at all.
        constexpr bool splitsLiveRanges() const { return optimLevel >= BuildCfgBackendOptimLevel::O1; }
    };

    enum class BuildCfgBackendKind
    {
        None,
        SharedLibrary,
        Executable,
        StaticLibrary,
        Export,
    };

    constexpr bool backendKindProducesNativeArtifact(const BuildCfgBackendKind backendKind)
    {
        return backendKind == BuildCfgBackendKind::Executable ||
               backendKind == BuildCfgBackendKind::SharedLibrary ||
               backendKind == BuildCfgBackendKind::StaticLibrary;
    }

    enum class BuildCfgBackendSubKind
    {
        Default,
        Console,
    };
}

SWC_END_NAMESPACE();
