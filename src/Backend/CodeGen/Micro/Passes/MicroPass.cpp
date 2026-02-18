#include "pch.h"
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
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

    std::string_view passStageName(MicroPassKind passKind, bool before)
    {
        // Stage names are user-facing and used by --pass print filters.
        switch (passKind)
        {
            case MicroPassKind::RegisterAllocation:
                return before ? "pre-regalloc" : "post-regalloc";
            case MicroPassKind::PrologEpilog:
                return before ? "pre-prolog-epilog" : "post-prolog-epilog";
            case MicroPassKind::Legalize:
                return before ? "pre-legalize" : "post-legalize";
            case MicroPassKind::Emit:
                return before ? "pre-emit" : "post-emit";
            default:
                SWC_UNREACHABLE();
        }
    }

    MicroRegPrintMode passPrintMode(MicroPassKind passKind, bool before)
    {
        if (passKind == MicroPassKind::RegisterAllocation && before)
            return MicroRegPrintMode::Virtual;
        return MicroRegPrintMode::Concrete;
    }

    bool shouldPrintPass(const MicroPassContext& context, MicroPassKind passKind, bool before)
    {
        // Printing is opt-in to keep non-debug runs quiet and fast.
        if (context.passPrintOptions.empty())
            return false;

        const auto stageName = passStageName(passKind, before);
        for (const auto& options : context.passPrintOptions)
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
        const std::string_view optimize   = backendOptimizeLevelName(builder.backendBuildCfg().backendOptimize);

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

    void printPassInstructions(const MicroPassContext& context, MicroPassKind passKind, bool before)
    {
        if (!context.taskContext || !context.builder)
            return;

        const auto&        ctx     = *context.taskContext;
        const auto&        builder = *context.builder;
        Logger::ScopedLock loggerLock(ctx.global().logger());

        const auto stageName = passStageName(passKind, before);

        Logger::print(ctx, "\n");
        printPassHeader(ctx, builder, stageName);

        const auto     printMode = passPrintMode(passKind, before);
        const Encoder* encoder   = printMode == MicroRegPrintMode::Concrete ? context.encoder : nullptr;
        builder.printInstructions(printMode, encoder);
    }
}

void MicroPassManager::add(MicroPass& pass)
{
    passes_.push_back(&pass);
}

void MicroPassManager::run(MicroPassContext& context) const
{
    // Keep one linear pipeline: each pass observes outputs from previous passes.
    for (MicroPass* pass : passes_)
    {
        SWC_ASSERT(pass);
        const auto passKind = pass->kind();
        if (shouldPrintPass(context, passKind, true))
            printPassInstructions(context, passKind, true);

        pass->run(context);

        if (shouldPrintPass(context, passKind, false))
            printPassInstructions(context, passKind, false);
    }
}

SWC_END_NAMESPACE();
