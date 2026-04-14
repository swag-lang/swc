#include "pch.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroUseDefMap.h"
#include "Backend/Micro/MicroVerify.h"
#include "Backend/Micro/Passes/Pass.BranchSimplify.h"
#include "Backend/Micro/Passes/Pass.ConstantFolding.h"
#include "Backend/Micro/Passes/Pass.CopyElimination.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/Passes/Pass.PostRADeadCodeElim.h"
#include "Backend/Micro/Passes/Pass.Emit.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.h"
#include "Backend/Micro/Passes/Pass.Legalize.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.h"
#include "Backend/Micro/Passes/Pass.PrologEpilog.h"
#include "Backend/Micro/Passes/Pass.PrologEpilogSanitize.h"
#include "Backend/Micro/Passes/Pass.RegisterAllocation.h"
#include "Backend/Micro/Passes/Pass.StackAdjustNormalize.h"
#include "Backend/Micro/Passes/Pass.StrengthReduction.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/Logger.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_OPT_ITERATION_OFF = 1;
    constexpr uint32_t K_OPT_ITERATION_ON  = 16;
    constexpr uint32_t K_RA_ITERATION_ON   = 16;

    std::string backendOptimizeLevelName(const Runtime::BuildCfgBackend& backendCfg)
    {
        if (!backendCfg.optimize)
            return "off";
        return "on";
    }

    std::string passStageName(const MicroPass& pass, bool before)
    {
        return std::format("{}-{}", before ? "pre" : "post", pass.name());
    }

    bool shouldPrintPass(const MicroPassContext& context, const MicroPass& pass, bool before)
    {
        if (context.passPrintOptions.empty())
            return false;

        const std::string stageName = passStageName(pass, before);
        for (const Utf8& options : context.passPrintOptions)
        {
            if (std::string_view{options} == stageName)
                return true;
        }

        return false;
    }

    std::string backendOptimizeWithInstructionStats(const MicroPassContext& context, const MicroBuilder& builder)
    {
        const Runtime::BuildCfgBackend& backendCfg = builder.backendBuildCfg();
        std::string                     optimize   = backendOptimizeLevelName(backendCfg);
        if (!backendCfg.optimize)
            return optimize;

        const size_t countAfter  = context.instructions->count();
        const size_t countBefore = context.printInstrCountBefore;
        double       gainPercent = 0.0;

        if (countBefore)
        {
            const double delta = static_cast<double>(countBefore) - static_cast<double>(countAfter);
            gainPercent        = (delta * 100.0) / static_cast<double>(countBefore);
        }

        return std::format("{} (instr: {} -> {}, gain: {:.2f}%)", optimize, countBefore, countAfter, gainPercent);
    }

    void printPassHeader(const MicroPassContext& context, const TaskContext& ctx, const MicroBuilder& builder, std::string_view stageName)
    {
        const std::string_view symbolName = builder.printSymbolName().empty() ? std::string_view{"<unknown-symbol>"} : std::string_view{builder.printSymbolName()};
        const std::string_view filePath   = builder.printFilePath().empty() ? std::string_view{"<unknown-file>"} : std::string_view{builder.printFilePath()};
        const uint32_t         sourceLine = builder.printSourceLine();
        const std::string      optimize   = backendOptimizeWithInstructionStats(context, builder);

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Compiler));
        Logger::print(ctx, "[micro]");
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Keyword));
        Logger::print(ctx, "  stage");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Code));
        Logger::print(ctx, "    : ");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Attribute));
        Logger::print(ctx, stageName);
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Keyword));
        Logger::print(ctx, "  function");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Code));
        Logger::print(ctx, " : ");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Function));
        Logger::print(ctx, symbolName);
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Keyword));
        Logger::print(ctx, "  location");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Code));
        Logger::print(ctx, " : ");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::String));
        Logger::print(ctx, std::format("{}:{}", filePath, sourceLine));
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Keyword));
        Logger::print(ctx, "  optimize");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Code));
        Logger::print(ctx, " : ");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Number));
        Logger::print(ctx, optimize);
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Default));
    }

    void printPassInstructions(const MicroPassContext& context, const MicroPass& pass, bool before)
    {
        if (!context.taskContext || !context.builder)
            return;

        const TaskContext&       ctx     = *context.taskContext;
        const MicroBuilder&      builder = *context.builder;
        const Logger::ScopedLock loggerLock(ctx.global().logger());

        const std::string stageName = passStageName(pass, before);

        Logger::print(ctx, "\n");
        printPassHeader(context, ctx, builder, stageName);

        const MicroRegPrintMode printMode = before ? pass.printModeBefore() : pass.printModeAfter();
        const Encoder*          encoder   = printMode == MicroRegPrintMode::Concrete ? context.encoder : nullptr;
        builder.printInstructions(printMode, encoder);
    }

    uint32_t optimizationIterationLimit(const Runtime::BuildCfgBackend& backendCfg)
    {
        if (!backendCfg.optimize)
            return K_OPT_ITERATION_OFF;
        return K_OPT_ITERATION_ON;
    }

    uint32_t loopIterationLimit(const MicroPassContext& context, const uint32_t defaultLimit)
    {
        if (context.optimizationIterationLimit)
            return context.optimizationIterationLimit;
        return defaultLimit;
    }

    struct VerifyStateCache
    {
        bool     hasCurrentState = false;
        uint64_t structuralHash  = 0;
    };

#if SWC_DEV_MODE
    struct LoopPassTraceEntry
    {
        std::string passName;
        uint64_t    structuralHash = 0;
    };
#endif

    Result verifyCurrentState(const MicroPassContext& context, std::string_view phase, VerifyStateCache& cache)
    {
#if SWC_DEV_MODE
        if (!MicroVerify::isEnabled(context))
            return Result::Continue;

        if (!cache.hasCurrentState)
        {
            SWC_RESULT(MicroVerify::verify(context, phase, &cache.structuralHash));
            cache.hasCurrentState = true;
        }
#else
        SWC_UNUSED(context);
        SWC_UNUSED(phase);
        SWC_UNUSED(cache);
#endif

        return Result::Continue;
    }

    Result runPass(MicroPassContext& context, MicroPass& pass, VerifyStateCache& verifyCache)
    {
        uint64_t storageRevisionBefore = 0;
        if (context.instructions)
            storageRevisionBefore = context.instructions->revision();

#if SWC_DEV_MODE
        uint64_t structuralHashBefore = 0;
        if (MicroVerify::isEnabled(context))
        {
            const std::string stageNameBefore = passStageName(pass, true);
            SWC_RESULT(verifyCurrentState(context, stageNameBefore, verifyCache));
            structuralHashBefore = verifyCache.structuralHash;
        }
#endif

        if (shouldPrintPass(context, pass, true))
            printPassInstructions(context, pass, true);

        context.passChanged = false;
        SWC_RESULT(pass.run(context));

        uint64_t storageRevisionAfter = storageRevisionBefore;
        if (context.instructions)
            storageRevisionAfter = context.instructions->revision();

        if (context.passChanged && context.builder)
        {
            if (storageRevisionAfter != storageRevisionBefore)
                context.builder->invalidateControlFlowGraph();
            else
                context.builder->markControlFlowGraphMaybeDirty();
        }

        if (context.passChanged && context.builder)
            context.builder->pruneDeadRelocations();

        if (context.passChanged && context.useDefMap)
            context.useDefMap->invalidate();
        if (context.passChanged && context.ssaState)
            context.ssaState->invalidate();

#if SWC_DEV_MODE
        if (MicroVerify::isEnabled(context))
        {
            const std::string stageNameAfter = passStageName(pass, false);
            verifyCache.hasCurrentState      = false;
            SWC_RESULT(verifyCurrentState(context, stageNameAfter, verifyCache));
            const uint64_t structuralHashAfter = verifyCache.structuralHash;

            if (!context.passChanged)
            {
                if (storageRevisionAfter != storageRevisionBefore || structuralHashAfter != structuralHashBefore)
                {
                    return MicroVerify::reportError(context, pass.name(), "pass mutated micro state without setting passChanged");
                }
            }
            else if (storageRevisionAfter == storageRevisionBefore && structuralHashAfter == structuralHashBefore)
            {
                return MicroVerify::reportError(context, pass.name(), "pass set passChanged but produced no observable micro-state change");
            }
        }
#endif

        if (shouldPrintPass(context, pass, false))
            printPassInstructions(context, pass, false);

        return Result::Continue;
    }

    Result runLinearPasses(MicroPassContext& context, std::span<MicroPass* const> passes, VerifyStateCache& verifyCache)
    {
        for (MicroPass* pass : passes)
        {
            SWC_ASSERT(pass != nullptr);
            SWC_RESULT(runPass(context, *pass, verifyCache));
        }

        return Result::Continue;
    }

    Result runLoopPasses(MicroPassContext&           context,
                         std::span<MicroPass* const> passes,
                         const uint32_t              maxIterations,
                         const bool                  buildSsa,
                         std::string_view            loopName,
                         VerifyStateCache&           verifyCache)
    {
        if (passes.empty())
            return Result::Continue;

#if SWC_DEV_MODE
        std::unordered_set<uint64_t> seenStates;
        if (MicroVerify::isEnabled(context))
        {
            seenStates.reserve(maxIterations + 1);
            SWC_RESULT(verifyCurrentState(context, "optimization-loop-start", verifyCache));
            seenStates.insert(verifyCache.structuralHash);
        }
#endif

        MicroSsaState ssaState;
        const bool    useSharedSsa = buildSsa && context.builder && context.instructions && context.operands;
        const auto    refreshSsa   = [&] {
            if (useSharedSsa && !ssaState.isValid())
                ssaState.build(*context.builder, *context.instructions, *context.operands, context.encoder);
        };
        if (useSharedSsa)
        {
            refreshSsa();
            context.ssaState = &ssaState;
        }

        bool reachedFixedPoint = false;
        for (uint32_t iteration = 0; iteration < maxIterations; ++iteration)
        {
            refreshSsa();

            bool iterationMutated = false;
#if SWC_DEV_MODE
            std::vector<LoopPassTraceEntry> iterationTrace;
            if (MicroVerify::isEnabled(context))
                iterationTrace.reserve(passes.size());
#endif
            for (MicroPass* pass : passes)
            {
                refreshSsa();
                SWC_RESULT(runPass(context, *pass, verifyCache));
                iterationMutated = iterationMutated || context.passChanged;
#if SWC_DEV_MODE
                if (MicroVerify::isEnabled(context) && context.passChanged)
                {
                    SWC_ASSERT(verifyCache.hasCurrentState);
                    iterationTrace.emplace_back(LoopPassTraceEntry{
                        .passName       = std::string{pass->name()},
                        .structuralHash = verifyCache.structuralHash,
                    });
                }
#endif
            }

            if (!iterationMutated)
            {
                reachedFixedPoint = true;
                break;
            }

#if SWC_DEV_MODE
            if (MicroVerify::isEnabled(context))
            {
                SWC_ASSERT(verifyCache.hasCurrentState);
                const uint64_t structuralHash = verifyCache.structuralHash;
                if (!seenStates.insert(structuralHash).second)
                {
                    std::string traceText;
                    if (!iterationTrace.empty())
                    {
                        traceText = " after";
                        for (const auto& traceEntry : iterationTrace)
                            traceText += std::format(" {}(0x{:016X})", traceEntry.passName, traceEntry.structuralHash);
                    }

                    return MicroVerify::reportError(context,
                                                    "optimization-loop",
                                                    std::format("re-entered a previous micro state at iteration {}{}", iteration + 1, traceText));
                }
            }
#endif
        }

        if (!reachedFixedPoint)
        {
            context.useDefMap = nullptr;
            context.ssaState  = nullptr;
            return MicroVerify::reportError(context,
                                            loopName,
                                            std::format("failed to reach a fixed point after {} iterations", maxIterations));
        }

        context.useDefMap = nullptr;
        context.ssaState  = nullptr;
        return Result::Continue;
    }
}

MicroPassManager::MicroPassManager()
{
    // Structural passes
    stackAdjustNormalizePass_ = std::make_unique<MicroStackAdjustNormalizePass>();
    legalizePass_             = std::make_unique<MicroLegalizePass>();
    regAllocPass_             = std::make_unique<MicroRegisterAllocationPass>();
    prologEpilogPass_         = std::make_unique<MicroPrologEpilogPass>();
    prologEpilogSanitizePass_ = std::make_unique<MicroPrologEpilogSanitizePass>();
    emitPass_                 = std::make_unique<MicroEmitPass>();

    // Pre-RA optimization passes
    constantFoldingPass_     = std::make_unique<MicroConstantFoldingPass>();
    copyEliminationPass_     = std::make_unique<MicroCopyEliminationPass>();
    instructionCombinePass_  = std::make_unique<MicroInstructionCombinePass>();
    strengthReductionPass_   = std::make_unique<MicroStrengthReductionPass>();
    deadCodeEliminationPass_ = std::make_unique<MicroDeadCodeEliminationPass>();
    branchSimplifyPass_      = std::make_unique<MicroBranchSimplifyPass>();

    // Post-RA optimization passes
    postRAPeepholePass_      = std::make_unique<MicroPostRAPeepholePass>();
    postRADeadCodeElimPass_  = std::make_unique<MicroPostRADeadCodeElimPass>();
}

MicroPassManager::~MicroPassManager()                                      = default;
MicroPassManager::MicroPassManager(MicroPassManager&&) noexcept            = default;
MicroPassManager& MicroPassManager::operator=(MicroPassManager&&) noexcept = default;

void MicroPassManager::clear()
{
    startPasses_.clear();
    preRALoopPasses_.clear();
    raLoopPasses_.clear();
    postRASetupPasses_.clear();
    postRAOptimPasses_.clear();
    finalPasses_.clear();
}

void MicroPassManager::configureDefaultPipeline(const bool optimize)
{
    clear();

    // Phase 1 — Initial lowering (runs once).
    // Only stack adjustment normalization. Legalize is deferred to the RA loop:
    // pre-RA optimization passes work on unconstrained virtual-register IR and
    // shouldn't see encoder-specific rewrites.
    addStartPass(*stackAdjustNormalizePass_);

    // Phase 2 — Pre-RA optimization loop (operates on virtual registers only).
    // Iterates until fixed point before touching register allocation.
    if (optimize)
    {
        addPreRALoopPass(*constantFoldingPass_);
        addPreRALoopPass(*copyEliminationPass_);
        addPreRALoopPass(*instructionCombinePass_);
        addPreRALoopPass(*strengthReductionPass_);
        addPreRALoopPass(*deadCodeEliminationPass_);
        addPreRALoopPass(*branchSimplifyPass_);
    }

    // Phase 3 — Register allocation loop.
    // Legalize can introduce new virtual registers; RegAlloc can introduce spills that
    // need another Legalize pass. They iterate together until stable.
    addRALoopPass(*legalizePass_);
    addRALoopPass(*regAllocPass_);

    // Phase 4 — Post-RA finalization (runs once, on physical registers).
    addPostRASetupPass(*prologEpilogPass_);
    if (optimize)
    {
        addPostRAOptimPass(*postRADeadCodeElimPass_);
        addPostRAOptimPass(*postRAPeepholePass_);
    }
    addFinalPass(*prologEpilogSanitizePass_);
    addFinalPass(*emitPass_);
}

Result MicroPassManager::run(MicroPassContext& context) const
{
    SWC_ASSERT(context.instructions != nullptr);
    VerifyStateCache verifyCache;

#if SWC_HAS_STATS
    context.statsInstrInitial = context.instructions->count();
#endif

    SWC_RESULT(runLinearPasses(context, startPasses_, verifyCache));

    context.printInstrCountBefore = context.instructions->count();
#if SWC_HAS_STATS
    context.statsInstrAfterStart = context.instructions->count();
#endif

    // Pre-RA optimization loop — converges on the virtual-register IR.
    SWC_ASSERT(context.builder);
    const uint32_t preRaMaxIterations = std::max<uint32_t>(loopIterationLimit(context, optimizationIterationLimit(context.builder->backendBuildCfg())), 1);
    SWC_RESULT(runLoopPasses(context, preRALoopPasses_, preRaMaxIterations, true, "pre-ra-optimization-loop", verifyCache));

#if SWC_HAS_STATS
    context.statsInstrAfterPreRAOptim = context.instructions->count();
#endif

    // All passes preceding the legalize/RA loop must keep the IR in virtual-register form;
    // physical registers are only legal once register allocation kicks in.
    SWC_RESULT(MicroVerify::verifyAllRegistersVirtual(context, "pre-ra-virtual-only"));

    // Register allocation loop — legalize + regalloc iterate until stable.
    const uint32_t raMaxIterations = std::max<uint32_t>(loopIterationLimit(context, K_RA_ITERATION_ON), 1);
    SWC_RESULT(runLoopPasses(context, raLoopPasses_, raMaxIterations, false, "ra-legalize-loop", verifyCache));

#if SWC_HAS_STATS
    context.statsInstrAfterRA = context.instructions->count();
#endif

    SWC_RESULT(runLinearPasses(context, postRASetupPasses_, verifyCache));

#if SWC_HAS_STATS
    context.statsInstrAfterPostRASetup = context.instructions->count();
#endif

    SWC_RESULT(runLinearPasses(context, postRAOptimPasses_, verifyCache));

#if SWC_HAS_STATS
    context.statsInstrAfterPostRAOptim = context.instructions->count();
#endif

    SWC_RESULT(runLinearPasses(context, finalPasses_, verifyCache));

#if SWC_HAS_STATS
    context.statsInstrFinal = context.instructions->count();
#endif

    return Result::Continue;
}

SWC_END_NAMESPACE();
