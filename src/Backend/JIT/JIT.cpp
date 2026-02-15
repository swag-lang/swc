#include "pch.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecMemoryManager.h"
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Backend/MachineCode/Micro/Passes/MicroRegAllocPass.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void printMicroHeader(const TaskContext& ctx, const MicroInstrBuilder& builder, std::string_view stage)
    {
        const std::string_view symbolName = builder.printSymbolName().empty() ? std::string_view{"<unknown-symbol>"} : std::string_view{builder.printSymbolName()};
        const std::string_view filePath   = builder.printFilePath().empty() ? std::string_view{"<unknown-file>"} : std::string_view{builder.printFilePath()};
        const uint32_t         sourceLine = builder.printSourceLine();

        Logger::print(ctx, LogColorHelper::toAnsi(ctx, LogColor::Yellow));
        Logger::print(ctx, std::format("[micro:{}] {} @ {}:{}", stage, symbolName, filePath, sourceLine));
        Logger::print(ctx, LogColorHelper::toAnsi(ctx, LogColor::Reset));
        Logger::print(ctx, "\n");
    }

    Result compileWithEncoder(TaskContext& ctx, MicroInstrBuilder& builder, Encoder& encoder, JITExecMemory& outExecutableMemory)
    {
        MicroRegAllocPass regAllocPass;
        MicroEncodePass   encodePass;

        MicroPassContext passContext;
        passContext.callConvKind           = CallConvKind::Host;
        passContext.preservePersistentRegs = true;

        if (builder.hasFlag(MicroInstrBuilderFlagsE::PrintBeforePasses))
        {
            printMicroHeader(ctx, builder, "raw");
            builder.printInstructions();
        }

        if (builder.hasFlag(MicroInstrBuilderFlagsE::PrintBeforeEncode))
        {
            MicroPassManager regAllocManager;
            regAllocManager.add(regAllocPass);
            builder.runPasses(regAllocManager, &encoder, passContext);
            printMicroHeader(ctx, builder, "pre-encode");
            builder.printInstructions();

            MicroPassManager encodeManager;
            encodeManager.add(encodePass);
            builder.runPasses(encodeManager, &encoder, passContext);
        }
        else
        {
            MicroPassManager passManager;
            passManager.add(regAllocPass);
            passManager.add(encodePass);
            builder.runPasses(passManager, &encoder, passContext);
        }

        const auto codeSize = encoder.size();
        if (!codeSize)
            return Result::Error;

        std::vector<std::byte> linearCode(codeSize);
        encoder.copyTo(linearCode);

        if (!ctx.compiler().jitMemMgr().allocateAndCopy(asByteSpan(linearCode), outExecutableMemory))
            return Result::Error;

        return Result::Continue;
    }
}

Result JIT::compile(TaskContext& ctx, MicroInstrBuilder& builder, JITExecMemory& outExecutableMemory)
{
#ifdef _M_X64
    X64Encoder encoder(ctx);
    return compileWithEncoder(ctx, builder, encoder, outExecutableMemory);
#else
    SWC_UNREACHABLE();
#endif
}

SWC_END_NAMESPACE();
