#include "pch.h"
#include "Backend/Micro/MicroPass.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/Logger.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::string_view backendOptimizeLevelName(Runtime::BuildCfgBackendOptim level)
    {
        switch (level)
        {
            case Runtime::BuildCfgBackendOptim::O0:
                return "O0";
            case Runtime::BuildCfgBackendOptim::O1:
                return "O1";
            case Runtime::BuildCfgBackendOptim::O2:
                return "O2";
            case Runtime::BuildCfgBackendOptim::O3:
                return "O3";
            case Runtime::BuildCfgBackendOptim::Os:
                return "Os";
            case Runtime::BuildCfgBackendOptim::Oz:
                return "Oz";
            default:
                SWC_UNREACHABLE();
        }
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

    void printPassHeader(const TaskContext& ctx, const MicroBuilder& builder, std::string_view stageName)
    {
        const std::string_view symbolName = builder.printSymbolName().empty() ? std::string_view{"<unknown-symbol>"} : std::string_view{builder.printSymbolName()};
        const std::string_view filePath   = builder.printFilePath().empty() ? std::string_view{"<unknown-file>"} : std::string_view{builder.printFilePath()};
        const uint32_t         sourceLine = builder.printSourceLine();
        const std::string_view optimize   = backendOptimizeLevelName(builder.backendBuildCfg().optimizeLevel);

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
        Logger::print(ctx, "  opt");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Code));
        Logger::print(ctx, "      : ");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Number));
        Logger::print(ctx, optimize);
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Default));
    }

    void printPassInstructions(const MicroPassContext& context, const MicroPass& pass, bool before)
    {
        if (!context.taskContext || !context.builder)
            return;

        const TaskContext&  ctx     = *context.taskContext;
        const MicroBuilder& builder = *context.builder;
        Logger::ScopedLock  loggerLock(ctx.global().logger());

        const std::string stageName = passStageName(pass, before);

        Logger::print(ctx, "\n");
        printPassHeader(ctx, builder, stageName);

        const MicroRegPrintMode printMode = before ? pass.printModeBefore() : pass.printModeAfter();
        const Encoder*          encoder   = printMode == MicroRegPrintMode::Concrete ? context.encoder : nullptr;
        builder.printInstructions(printMode, encoder);
    }

    uint32_t optimizationIterationLimit(Runtime::BuildCfgBackendOptim optimizeLevel)
    {
        switch (optimizeLevel)
        {
            case Runtime::BuildCfgBackendOptim::O0:
                return 1;
            case Runtime::BuildCfgBackendOptim::O1:
                return 2;
            case Runtime::BuildCfgBackendOptim::O2:
                return 4;
            case Runtime::BuildCfgBackendOptim::O3:
                return 8;
            case Runtime::BuildCfgBackendOptim::Os:
                return 4;
            case Runtime::BuildCfgBackendOptim::Oz:
                return 6;
            default:
                SWC_UNREACHABLE();
        }
    }

    uint32_t optimizationIterationLimit(const MicroPassContext& context)
    {
        if (context.optimizationIterationLimit)
            return context.optimizationIterationLimit;

        if (context.builder)
            return optimizationIterationLimit(context.builder->backendBuildCfg().optimizeLevel);

        return optimizationIterationLimit(Runtime::BuildCfgBackendOptim::O0);
    }

    bool runPass(MicroPassContext& context, MicroPass& pass)
    {
        if (shouldPrintPass(context, pass, true))
            printPassInstructions(context, pass, true);

        const bool changed = pass.run(context);

        if (shouldPrintPass(context, pass, false))
            printPassInstructions(context, pass, false);

        return changed;
    }

    void runLinearPasses(MicroPassContext& context, std::span<MicroPass* const> passes)
    {
        for (MicroPass* pass : passes)
        {
            SWC_ASSERT(pass != nullptr);
            runPass(context, *SWC_CHECK_NOT_NULL(pass));
        }
    }

    void runOptimizationPasses(MicroPassContext& context, std::span<MicroPass* const> optimizationPasses)
    {
        if (optimizationPasses.empty())
            return;

#if SWC_HAS_STATS
        const size_t countBefore = context.instructions ? context.instructions->count() : 0;
#endif
        const uint32_t maxIterations = std::max<uint32_t>(optimizationIterationLimit(context), 1);
        for (uint32_t iteration = 0; iteration < maxIterations; ++iteration)
        {
            bool changed = false;
            for (MicroPass* pass : optimizationPasses)
            {
                SWC_ASSERT(pass != nullptr);
                if (runPass(context, *SWC_CHECK_NOT_NULL(pass)))
                    changed = true;
            }

            if (!changed)
                break;
        }

#if SWC_HAS_STATS
        const size_t countAfter = context.instructions ? context.instructions->count() : 0;
        if (countAfter <= countBefore)
            context.optimizationInstrRemoved += countBefore - countAfter;
        else
            context.optimizationInstrAdded += countAfter - countBefore;
#endif
    }
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

void MicroPassManager::run(MicroPassContext& context) const
{
    runOptimizationPasses(context, preOptimizationPasses_);
    runLinearPasses(context, mandatoryPasses_);
    runOptimizationPasses(context, postOptimizationPasses_);
    runLinearPasses(context, finalPasses_);
}

SWC_END_NAMESPACE();
