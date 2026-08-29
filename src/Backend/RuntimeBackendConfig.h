#pragma once

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    // Controls which calls the semantic inliner expands.
    //  - Never:      no heuristic inlining; only mandatory expansions (macro/mixin).
    //  - MarkedOnly: also inline functions explicitly tagged #[Inline] (the historical
    //                behavior when optimization was on).
    //  - Auto:       MarkedOnly plus compiler-chosen small/cheap callees.
    // Default (and per-config presets) live in applyBuildCfgPreset. Keep this enum and the
    // field order below in sync with the Swag mirror in bin/runtime/api.swg (the user-visible
    // build config is read directly through that layout).
    enum class BuildCfgBackendInlineMode : uint8_t
    {
        Never      = 0,
        MarkedOnly = 1,
        Auto       = 2,
    };

    struct BuildCfgBackend
    {
        bool                      optimize;
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
