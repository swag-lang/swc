#include "pch.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Support/Report/Logger.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::string_view passStageName(MicroPassKind passKind, bool before)
    {
        switch (passKind)
        {
            case MicroPassKind::RegAlloc:
                return before ? "before-regalloc" : "after-regalloc";
            case MicroPassKind::PersistentRegs:
                return before ? "before-persistent-regs" : "after-persistent-regs";
            case MicroPassKind::Encode:
                return before ? "before-encode" : "after-encode";
            default:
                SWC_UNREACHABLE();
        }
    }

    MicroInstrRegPrintMode passPrintMode(MicroPassKind passKind, bool before)
    {
        if (passKind == MicroPassKind::RegAlloc && before)
            return MicroInstrRegPrintMode::Virtual;
        return MicroInstrRegPrintMode::Concrete;
    }

    bool shouldPrintPass(const MicroPassContext& context, MicroPassKind passKind, bool before)
    {
        switch (passKind)
        {
            case MicroPassKind::RegAlloc:
                return before ? context.passPrintFlags.has(MicroPassPrintFlagsE::BeforeRegAlloc) : context.passPrintFlags.has(MicroPassPrintFlagsE::AfterRegAlloc);
            case MicroPassKind::PersistentRegs:
                return before ? context.passPrintFlags.has(MicroPassPrintFlagsE::BeforePersistentRegs) : context.passPrintFlags.has(MicroPassPrintFlagsE::AfterPersistentRegs);
            case MicroPassKind::Encode:
                return before ? context.passPrintFlags.has(MicroPassPrintFlagsE::BeforeEncode) : context.passPrintFlags.has(MicroPassPrintFlagsE::AfterEncode);
            default:
                SWC_UNREACHABLE();
        }
    }

    void printPassInstructions(const MicroPassContext& context, MicroPassKind passKind, bool before)
    {
        if (!context.taskContext || !context.builder)
            return;

        const auto& ctx     = *context.taskContext;
        const auto& builder = *context.builder;

        const std::string_view symbolName = builder.printSymbolName().empty() ? std::string_view{"<unknown-symbol>"} : std::string_view{builder.printSymbolName()};
        const std::string_view filePath   = builder.printFilePath().empty() ? std::string_view{"<unknown-file>"} : std::string_view{builder.printFilePath()};
        const uint32_t         sourceLine = builder.printSourceLine();
        const auto             stageName  = passStageName(passKind, before);

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Compiler));
        Logger::print(ctx, std::format("[micro:{}] {} @ {}:{}", stageName, symbolName, filePath, sourceLine));
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Default));
        Logger::print(ctx, "\n");

        const auto  printMode = passPrintMode(passKind, before);
        const auto* encoder   = printMode == MicroInstrRegPrintMode::Concrete ? context.encoder : nullptr;
        builder.printInstructions(printMode, encoder);
    }
}

void MicroPassManager::add(MicroPass& pass)
{
    passes_.push_back(&pass);
}

void MicroPassManager::run(MicroPassContext& context) const
{
    for (auto* pass : passes_)
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
