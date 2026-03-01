#include "pch.h"
#include "Backend/Micro/MicroPass.h"
#include "Backend/Micro/MicroBuilder.h"
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
#include "Backend/Micro/Passes/Pass.RegisterAllocation.h"
#include "Backend/Micro/Passes/Pass.StrengthReduction.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/Logger.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_OPT_ITERATION_OFF = 1;
    constexpr uint32_t K_OPT_ITERATION_ON  = 4;
    size_t             countNonLabelInstructions(const MicroStorage* instructions);

    void updatePrintInstructionCountBaseline(MicroPassContext& context)
    {
        if (!context.instructions)
            return;

        const size_t currentCount = countNonLabelInstructions(context.instructions);
        if (!context.hasPrintInstrCountBeforeAll || currentCount > context.printInstrCountBeforeAll)
        {
            context.printInstrCountBeforeAll    = currentCount;
            context.hasPrintInstrCountBeforeAll = true;
        }
    }

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

        if (!context.instructions || !context.hasPrintInstrCountBeforeAll)
            return optimize;

        const size_t countAfter  = countNonLabelInstructions(context.instructions);
        const size_t countBefore = context.printInstrCountBeforeAll;
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

        if (context.builder)
            return optimizationIterationLimit(context.builder->backendBuildCfg());

        return optimizationIterationLimit(Runtime::BuildCfgBackend{});
    }

    size_t countNonLabelInstructions(const MicroStorage* instructions)
    {
        if (!instructions)
            return 0;

        size_t                        count = 0;
        const MicroStorage::ConstView view  = instructions->view();
        for (const auto& inst : view)
        {
            if (inst.op == MicroInstrOpcode::Label)
                continue;

            ++count;
        }

        return count;
    }

    Result runPass(MicroPassContext& context, MicroPass& pass, bool& outChanged)
    {
        uint64_t storageRevisionBefore = 0;
        if (context.instructions)
            storageRevisionBefore = context.instructions->revision();

        updatePrintInstructionCountBaseline(context);
        if (shouldPrintPass(context, pass, true))
            printPassInstructions(context, pass, true);

        context.passChanged = false;
        SWC_RESULT_VERIFY(pass.run(context));

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

        bool changed = context.passChanged;
        if (changed && context.builder && SWC_NOT_NULL(context.builder)->pruneDeadRelocations())
            changed = true;

        updatePrintInstructionCountBaseline(context);
        if (shouldPrintPass(context, pass, false))
            printPassInstructions(context, pass, false);

        outChanged = changed;
        return Result::Continue;
    }

    Result runLinearPasses(MicroPassContext& context, std::span<MicroPass* const> passes)
    {
        for (MicroPass* pass : passes)
        {
            SWC_ASSERT(pass != nullptr);
            bool changed = false;
            SWC_RESULT_VERIFY(runPass(context, *SWC_NOT_NULL(pass), changed));
        }

        return Result::Continue;
    }

    Result runOptimizationPasses(MicroPassContext& context, std::span<MicroPass* const> optimizationPasses)
    {
        if (optimizationPasses.empty())
            return Result::Continue;

#if SWC_HAS_STATS
        const size_t countBefore = countNonLabelInstructions(context.instructions);
#endif
        const uint32_t maxIterations = std::max<uint32_t>(optimizationIterationLimit(context), 1);
        for (uint32_t iteration = 0; iteration < maxIterations; ++iteration)
        {
            bool changed = false;
            for (MicroPass* pass : optimizationPasses)
            {
                SWC_ASSERT(pass != nullptr);
                bool passChanged = false;
                SWC_RESULT_VERIFY(runPass(context, *SWC_NOT_NULL(pass), passChanged));
                if (passChanged)
                    changed = true;
            }

            if (!changed)
                break;
        }

#if SWC_HAS_STATS
        const size_t countAfter = countNonLabelInstructions(context.instructions);
        if (countAfter <= countBefore)
            context.optimizationInstrRemoved += countBefore - countAfter;
        else
            context.optimizationInstrAdded += countAfter - countBefore;
#endif

        return Result::Continue;
    }
}

MicroPassManager::MicroPassManager()
{
    cfgSimplifyPass_         = std::make_unique<MicroControlFlowSimplificationPass>();
    instructionCombinePass_  = std::make_unique<MicroInstructionCombinePass>();
    strengthReductionPass_   = std::make_unique<MicroStrengthReductionPass>();
    copyPropagationPass_     = std::make_unique<MicroCopyPropagationPass>();
    constantPropagationPass_ = std::make_unique<MicroConstantPropagationPass>();
    deadCodePass_            = std::make_unique<MicroDeadCodeEliminationPass>();
    branchFoldingPass_       = std::make_unique<MicroBranchFoldingPass>();
    loadStoreForwardPass_    = std::make_unique<MicroLoadStoreForwardingPass>();
    peepholePass_            = std::make_unique<MicroPeepholePass>();
    regAllocPass_            = std::make_unique<MicroRegisterAllocationPass>();
    prologEpilogPass_        = std::make_unique<MicroPrologEpilogPass>();
    legalizePass_            = std::make_unique<MicroLegalizePass>();
    emitPass_                = std::make_unique<MicroEmitPass>();
}

MicroPassManager::~MicroPassManager() = default;

MicroPassManager::MicroPassManager(MicroPassManager&&) noexcept            = default;
MicroPassManager& MicroPassManager::operator=(MicroPassManager&&) noexcept = default;

void MicroPassManager::clear()
{
    preOptimizationPasses_.clear();
    mandatoryPasses_.clear();
    postOptimizationPasses_.clear();
    finalPasses_.clear();
}

void MicroPassManager::configureDefaultPipeline(const bool optimize)
{
    clear();

    if (optimize)
    {
        addPreOptimization(*strengthReductionPass_);
        addPreOptimization(*instructionCombinePass_);
        addPreOptimization(*copyPropagationPass_);
        addPreOptimization(*constantPropagationPass_);
        addPreOptimization(*loadStoreForwardPass_);
        addPreOptimization(*branchFoldingPass_);
        addPreOptimization(*cfgSimplifyPass_);
        addPostOptimization(*branchFoldingPass_);
        addPostOptimization(*cfgSimplifyPass_);
        addPostOptimization(*constantPropagationPass_);
        addPostOptimization(*deadCodePass_);
        addPostOptimization(*peepholePass_);
        addPostOptimization(*cfgSimplifyPass_);
    }

    addMandatory(*regAllocPass_);
    addMandatory(*legalizePass_);
    addMandatory(*regAllocPass_);

    if (optimize)
    {
        addFinal(*constantPropagationPass_);
        addFinal(*loadStoreForwardPass_);
        addFinal(*branchFoldingPass_);
        addFinal(*cfgSimplifyPass_);
        addFinal(*deadCodePass_);
        addFinal(*peepholePass_);
        addFinal(*constantPropagationPass_);
        addFinal(*branchFoldingPass_);
        addFinal(*cfgSimplifyPass_);
    }

    addFinal(*prologEpilogPass_);
    addFinal(*legalizePass_);

    if (optimize)
    {
        addFinal(*constantPropagationPass_);
        addFinal(*loadStoreForwardPass_);
        addFinal(*branchFoldingPass_);
        addFinal(*cfgSimplifyPass_);
        addFinal(*peepholePass_);
        addFinal(*deadCodePass_);
        addFinal(*constantPropagationPass_);
        addFinal(*branchFoldingPass_);
        addFinal(*cfgSimplifyPass_);
    }

    addFinal(*regAllocPass_);

    if (optimize)
    {
        addFinal(*constantPropagationPass_);
        addFinal(*loadStoreForwardPass_);
        addFinal(*peepholePass_);
        addFinal(*deadCodePass_);
        addFinal(*constantPropagationPass_);
        addFinal(*branchFoldingPass_);
        addFinal(*cfgSimplifyPass_);
    }

    addFinal(*emitPass_);
}

void MicroPassManager::add(MicroPass& pass)
{
    addMandatory(pass);
}

void MicroPassManager::addMandatory(MicroPass& pass)
{
    mandatoryPasses_.push_back(&pass);
}

void MicroPassManager::addPreOptimization(MicroPass& pass)
{
    preOptimizationPasses_.push_back(&pass);
}

void MicroPassManager::addPostOptimization(MicroPass& pass)
{
    postOptimizationPasses_.push_back(&pass);
}

void MicroPassManager::addFinal(MicroPass& pass)
{
    finalPasses_.push_back(&pass);
}

Result MicroPassManager::run(MicroPassContext& context) const
{
    context.printInstrCountBeforeAll    = 0;
    context.hasPrintInstrCountBeforeAll = false;
    if (context.instructions)
    {
        context.printInstrCountBeforeAll    = countNonLabelInstructions(context.instructions);
        context.hasPrintInstrCountBeforeAll = true;
    }

    SWC_RESULT_VERIFY(runOptimizationPasses(context, preOptimizationPasses_));
    SWC_RESULT_VERIFY(runLinearPasses(context, mandatoryPasses_));
    SWC_RESULT_VERIFY(runOptimizationPasses(context, postOptimizationPasses_));
    SWC_RESULT_VERIFY(runLinearPasses(context, finalPasses_));
    return Result::Continue;
}

SWC_END_NAMESPACE();
