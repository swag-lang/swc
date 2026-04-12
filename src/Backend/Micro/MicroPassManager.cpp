#include "pch.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroVerify.h"
#include "Backend/Micro/Passes/Pass.BranchFolding.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.h"
#include "Backend/Micro/Passes/Pass.ControlFlowSimplification.h"
#include "Backend/Micro/Passes/Pass.CopyPropagation.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/Passes/Pass.Emit.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.h"
#include "Backend/Micro/Passes/Pass.Legalize.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.h"
#include "Backend/Micro/Passes/Pass.Peephole.h"
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

    uint32_t optimizationIterationLimit(const MicroPassContext& context)
    {
        if (context.optimizationIterationLimit)
            return context.optimizationIterationLimit;
        SWC_ASSERT(context.builder);
        return optimizationIterationLimit(context.builder->backendBuildCfg());
    }

    struct VerifyStateCache
    {
        bool     hasCurrentState = false;
        uint64_t structuralHash  = 0;
    };

    Result verifyCurrentState(MicroPassContext& context, std::string_view phase, VerifyStateCache& cache)
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

#if SWC_DEV_MODE
        if (MicroVerify::isEnabled(context))
        {
            const std::string stageNameAfter = passStageName(pass, false);
            verifyCache.hasCurrentState = false;
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

    Result runLoopPasses(MicroPassContext& context, std::span<MicroPass* const> passes, VerifyStateCache& verifyCache)
    {
        if (passes.empty())
            return Result::Continue;

        const uint32_t maxIterations = std::max<uint32_t>(optimizationIterationLimit(context), 1);

#if SWC_DEV_MODE
        std::unordered_set<uint64_t> seenStates;
        if (MicroVerify::isEnabled(context))
        {
            seenStates.reserve(maxIterations + 1);
            SWC_RESULT(verifyCurrentState(context, "optimization-loop-start", verifyCache));
            seenStates.insert(verifyCache.structuralHash);
        }
#endif

        for (uint32_t iteration = 0; iteration < maxIterations; ++iteration)
        {
            bool iterationMutated = false;
            for (MicroPass* pass : passes)
            {
                SWC_RESULT(runPass(context, *pass, verifyCache));
                iterationMutated = iterationMutated || context.passChanged;
            }

            if (!iterationMutated)
                break;

#if SWC_DEV_MODE
            if (MicroVerify::isEnabled(context))
            {
                SWC_ASSERT(verifyCache.hasCurrentState);
                const uint64_t structuralHash = verifyCache.structuralHash;
                if (!seenStates.insert(structuralHash).second)
                {
                    return MicroVerify::reportError(context, "optimization-loop", std::format("re-entered a previous micro state at iteration {}", iteration + 1));
                }
            }
#endif
        }

        return Result::Continue;
    }
}

MicroPassManager::MicroPassManager()
{
    cfgSimplifyPass_          = std::make_unique<MicroControlFlowSimplificationPass>();
    instructionCombinePass_   = std::make_unique<MicroInstructionCombinePass>();
    strengthReductionPass_    = std::make_unique<MicroStrengthReductionPass>();
    copyPropagationPass_      = std::make_unique<MicroCopyPropagationPass>();
    constantPropagationPass_  = std::make_unique<MicroConstantPropagationPass>();
    deadCodePass_             = std::make_unique<MicroDeadCodeEliminationPass>();
    branchFoldingPass_        = std::make_unique<MicroBranchFoldingPass>();
    loadStoreForwardPass_     = std::make_unique<MicroLoadStoreForwardingPass>();
    peepholePass_             = std::make_unique<MicroPeepholePass>();
    stackAdjustNormalizePass_ = std::make_unique<MicroStackAdjustNormalizePass>();
    regAllocPass_             = std::make_unique<MicroRegisterAllocationPass>();
    prologEpilogPass_         = std::make_unique<MicroPrologEpilogPass>();
    prologEpilogSanitizePass_ = std::make_unique<MicroPrologEpilogSanitizePass>();
    legalizePass_             = std::make_unique<MicroLegalizePass>();
    emitPass_                 = std::make_unique<MicroEmitPass>();
}

MicroPassManager::~MicroPassManager()                                      = default;
MicroPassManager::MicroPassManager(MicroPassManager&&) noexcept            = default;
MicroPassManager& MicroPassManager::operator=(MicroPassManager&&) noexcept = default;

void MicroPassManager::clear()
{
    startPasses_.clear();
    loopPasses_.clear();
    finalPasses_.clear();
}

void MicroPassManager::configureDefaultPipeline(const bool optimize)
{
    clear();

    addStartPass(*stackAdjustNormalizePass_);
    addStartPass(*legalizePass_);
    addStartPass(*regAllocPass_);
    addStartPass(*prologEpilogPass_);

    if (optimize)
    {
        addLoopPass(*strengthReductionPass_);
        addLoopPass(*instructionCombinePass_);
        addLoopPass(*copyPropagationPass_);
        addLoopPass(*constantPropagationPass_);
        addLoopPass(*loadStoreForwardPass_);
        addLoopPass(*branchFoldingPass_);
        addLoopPass(*cfgSimplifyPass_);
        addLoopPass(*deadCodePass_);
        addLoopPass(*peepholePass_);
    }

    addLoopPass(*legalizePass_);
    addLoopPass(*regAllocPass_);
    addFinalPass(*prologEpilogSanitizePass_);
    addFinalPass(*emitPass_);
}

Result MicroPassManager::run(MicroPassContext& context) const
{
    SWC_ASSERT(context.instructions != nullptr);
    VerifyStateCache verifyCache;
    SWC_RESULT(runLinearPasses(context, startPasses_, verifyCache));

    context.printInstrCountBefore = context.instructions->count();
    SWC_RESULT(runLoopPasses(context, loopPasses_, verifyCache));
    SWC_RESULT(runLinearPasses(context, finalPasses_, verifyCache));

    return Result::Continue;
}

SWC_END_NAMESPACE();
