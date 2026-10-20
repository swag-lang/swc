#pragma once

SWC_BEGIN_NAMESPACE();

struct ByteArray;

namespace Runtime
{
    // Controls which calls the semantic inliner expands.
    //  - Never:      no heuristic inlining; only mandatory expansions (macro/mixin).
    //  - MarkedOnly: also inline functions explicitly tagged #[Inline] (the historical
    //                behavior when optimization was on).
    //  - Auto:       MarkedOnly plus compiler-chosen small/cheap callees.
    // Default (and per-config presets) live in applyBuildCfgPreset. Keep these enums and the
    // field order below in sync with the Swag mirror in bin/runtime/build.swg (the user-visible
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

    struct BuildCfgBackendOptimizerIterations
    {
        uint32_t preRaSweeps             = 0; // Pre-allocation optimization sweeps; exhaustion reports a compiler error.
        uint32_t allocationSweeps        = 0; // Legalization/allocation sweeps; exhaustion reports a compiler error.
        uint32_t postRaSweeps            = 0; // Post-allocation cleanup sweeps; exhaustion keeps the last valid result.
        uint32_t prePrologueSweeps       = 0; // Peephole and dead-code cleanup sweeps before frame setup.
        uint32_t branchThreadRounds      = 0; // Branch-threading rounds within one pass invocation.
        uint32_t inductionVariableRounds = 0; // Loop rediscovery rounds within one induction-variable pass.
        uint32_t loopInvariantRounds     = 0; // Hoisting rounds within one loop-invariant-code-motion pass.
        uint32_t sinkToUseRounds         = 0; // Scheduling rounds that move definitions towards their consumers.
        uint32_t registerJoinRounds      = 0; // Copy-coalescing rounds before register allocation.
        uint32_t postRaHoistLevels       = 0; // Outer-loop levels visited by post-allocation hoisting.
    };

    struct BuildCfgBackendOptimizerUnroll
    {
        uint32_t memoryBytes                  = 0; // Maximum bytes expanded for constant-size memory operations.
        uint32_t maxTrips                     = 0; // Maximum trip count for ordinary full loop unrolling.
        uint32_t maxWideTableTrips            = 0; // Maximum trip count admitting larger constant-table bodies.
        uint32_t maxBodyInstructions          = 0; // Maximum original instructions considered for full unrolling; ordinary loops also obey their own cap.
        uint32_t maxTotalInstructions         = 0; // Maximum expanded instructions for the constant-table exception.
        uint32_t maxOrdinaryBodyInstructions  = 0; // Maximum original instructions for ordinary full unrolling.
        uint32_t maxOrdinaryTotalInstructions = 0; // Maximum expanded instructions for ordinary full unrolling.
        uint32_t maxBranchedTotalInstructions = 0; // Maximum expanded instructions when branches survive unrolling.
        uint32_t maxNestedTotalInstructions   = 0; // Maximum flattened instructions for a fully unrolled loop nest.
        uint32_t maxPartialBodyInstructions   = 0; // Maximum original instructions for partial indexed-loop unrolling.
        uint32_t partialFactor                = 0; // Scalar copies per partial indexed-loop iteration; clamped to 1..64.
        uint32_t initializerLookback          = 0; // Maximum preheader instructions searched for the loop counter initializer.
        uint32_t sumInitializerLookback       = 0; // Maximum preheader instructions searched for an accumulator initializer.
    };

    struct BuildCfgBackendOptimizerVectorization
    {
        uint32_t maxPlanInstructions = 0; // Maximum generated instructions in one SLP vectorization plan.
        uint32_t maxTreeDepth        = 0; // Maximum recursive SLP tree depth; capped at the implementation stack bound of 512.
        uint32_t maxPromotedPerLoop  = 0; // Maximum vector-state objects promoted simultaneously in one loop.
    };

    // Keep field order synchronized with Swag.Build.Optimizer in bin/runtime/build.swg.
    struct BuildCfgBackendOptimizer
    {
        BuildCfgBackendOptimizerIterations    iterations;
        BuildCfgBackendOptimizerUnroll        unroll;
        BuildCfgBackendOptimizerVectorization vectorization;
    };

    // Floating-point policy; keep the layout synchronized with Swag.Build.BackendMath.
    struct BuildCfgBackendMath
    {
        bool fma          = false; // Allow fused multiply-add contraction; true in release.
        bool noNaN        = false; // Assume floating-point values are not NaN; true in release.
        bool noInf        = false; // Assume floating-point values are finite; true in release.
        bool noSignedZero = false; // Allow transformations that ignore the sign of zero; true in release.
        bool unsafe       = false; // Reserve permission for unsafe floating-point transformations.
        bool approxFunc   = false; // Reserve permission for approximate math-function implementations.
    };

    struct BuildCfgBackend
    {
        // Every backend control that can change emitted code participates here.
        void appendCacheIdentity(ByteArray& bytes) const;

        BuildCfgBackendOptimLevel optimLevel = BuildCfgBackendOptimLevel::O0;
        bool                      vectorize;
        bool                      debugInfo;
        bool                      enableExceptions;
        BuildCfgBackendMath       math;
        BuildCfgBackendInlineMode inlineMode = BuildCfgBackendInlineMode::MarkedOnly;

        BuildCfgBackendOptimizer optimizer;

        // The optimizer runs at all.
        constexpr bool optimizes() const { return optimLevel != BuildCfgBackendOptimLevel::O0; }

        // The optimizer also runs the analyses that cost compilation time: induction variables,
        // strength reduction, value numbering, loop-invariant code motion, loop unrolling, and
        // scheduling for register pressure. They are what separates O1 from O2, so the
        // edit-build loop pays for the rewrites that are nearly free and a shipped build pays
        // for the rest.
        constexpr bool runsCostlyOptimizations() const { return optimLevel >= BuildCfgBackendOptimLevel::O2; }

        // Register allocation splits live intervals instead of assigning one register per
        // value for its whole life. Measured neutral on compilation time, so the
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
