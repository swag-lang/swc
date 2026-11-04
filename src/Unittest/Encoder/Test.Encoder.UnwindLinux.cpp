#include "pch.h"

#if SWC_HAS_UNITTEST && defined(__linux__)
#include "Backend/Encoder/Encoder.x64.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/Passes/Pass.Emit.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Support/Os/Os.Exception.Linux.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"
#include <signal.h>

SWC_BEGIN_NAMESPACE();

namespace
{
    struct UnwindMarker {};
    thread_local std::array<uintptr_t, 64> captured{};
    thread_local uint32_t capturedCount = 0;

    __attribute__((noinline)) void captureGeneratedStack()
    {
        capturedCount = Os::captureCallStack(captured);
        asm volatile("" ::: "memory");
    }

    __attribute__((noinline)) void throwAcrossGeneratedFrame()
    {
        throw UnwindMarker{};
    }

    struct Invocation
    {
        void* entry;
        void (*callback)();
        uint64_t path;
        uint32_t destroyed = 0;
    };

    __attribute__((noinline)) void invokeWithCleanup(void* argument)
    {
        auto& invocation = *static_cast<Invocation*>(argument);
        struct Cleanup
        {
            uint32_t* destroyed;
            ~Cleanup() { ++*destroyed; }
        } cleanup{&invocation.destroyed};
        using Entry = void (*)(void (*)(), uint64_t, uint64_t);
        reinterpret_cast<Entry>(invocation.entry)(invocation.callback, invocation.path, 16);
        asm volatile("" ::: "memory");
    }

    void emitEpilogue(MicroBuilder& builder)
    {
        builder.emitLoadRegReg(MicroReg::intReg(4), MicroReg::intReg(5), MicroOpBits::B64);
        builder.emitPop(MicroReg::intReg(5));
        builder.emitRet();
    }

    void emitCallback(MicroBuilder& builder, const bool fault)
    {
        // The fixture uses the host's RDI function pointer explicitly. No foreign
        // signature lowering is involved in this instruction/unwind boundary.
        builder.emitCallReg(MicroReg::intReg(7), CallConvKind::C);
        if (fault)
        {
            builder.emitLoadRegImm(MicroReg::intReg(0), ApInt(0, 64), MicroOpBits::B64);
            builder.emitLoadMemImm(MicroReg::intReg(0), 0, ApInt(42, 32), MicroOpBits::B32);
        }
    }

    Result verifyGeneratedUnwind(TaskContext& context, MicroBuilder& builder, const bool fault)
    {
        X64Encoder encoder(context);
        SWC_RESULT(Backend::Unittest::runMicroPass<MicroEmitPass>(builder, &encoder));
        ByteArray code;
        code.resize(encoder.size());
        encoder.copyTo(code);
        ByteArray unwind;
        encoder.buildUnwindInfo(unwind);
        JITMemoryManager manager;
        JITMemory memory;
        manager.allocateWithCodeSize(memory, static_cast<uint32_t>(code.size() + unwind.size() + 3), static_cast<uint32_t>(code.size()));
        std::memcpy(memory.entryPoint(), code.data(), code.size());
        JITMemoryManager::copyUnwindInfo(memory, unwind.span());
        JITMemoryManager::registerUnwindInfo(memory);
        JITMemoryManager::makeExecutable(memory);
        const auto address = reinterpret_cast<uintptr_t>(memory.entryPoint());
        for (const uint64_t path : {0, 1})
        {
            capturedCount = 0;
            Invocation invocation{memory.entryPoint(), captureGeneratedStack, path};
            Os::LinuxException exception;
            const bool completed = Os::executeWithHostFaultHandler(exception, invokeWithCleanup, &invocation);
            if (completed == fault || invocation.destroyed != 1)
                return Result::Error;
            if (fault && (exception.signal != SIGSEGV || exception.instructionAddress < address || exception.instructionAddress >= address + code.size()))
                return Result::Error;
            bool sawGenerated = false;
            for (uint32_t index = 0; index < capturedCount; ++index)
                sawGenerated |= captured[index] >= address && captured[index] < address + code.size();
            if (!sawGenerated || capturedCount < 3)
                return Result::Error;

            invocation.callback = throwAcrossGeneratedFrame;
            invocation.destroyed = 0;
            bool caught = false;
            try
            {
                Os::executeWithHostFaultHandler(exception, invokeWithCleanup, &invocation);
            }
            catch (const UnwindMarker&)
            {
                caught = true;
            }
            if (!caught || invocation.destroyed != 1)
                return Result::Error;
        }
        return Result::Continue;
    }

    Result verifyControlFlowUnwind(TaskContext& ctx, const bool sharedEpilogue, const bool fault)
    {
        CommandLine commandLine = ctx.cmdLine();
        commandLine.targetOs = Runtime::TargetOs::Linux;
        CompilerInstance compiler(ctx.global(), commandLine);
        TaskContext linuxContext(compiler);
        MicroBuilder builder(linuxContext);
        const auto cold = builder.createLabel();
        const auto done = builder.createLabel();
        const auto loop = builder.createLabel();
        builder.emitPush(MicroReg::intReg(5));
        builder.emitLoadRegReg(MicroReg::intReg(5), MicroReg::intReg(4), MicroOpBits::B64);
        builder.emitOpBinaryRegImm(MicroReg::intReg(4), ApInt(32, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(MicroReg::intReg(6), ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, cold);
        emitCallback(builder, fault);
        if (sharedEpilogue)
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, done);
        else
            emitEpilogue(builder);
        builder.placeLabel(cold);
        // RDX is a runtime size: RSP becomes unknown while RBP still names the CFA.
        builder.emitOpBinaryRegReg(MicroReg::intReg(4), MicroReg::intReg(3), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitLoadRegImm(MicroReg::intReg(0), ApInt(3, 64), MicroOpBits::B64);
        builder.placeLabel(loop);
        builder.emitOpBinaryRegImm(MicroReg::intReg(0), ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(MicroReg::intReg(0), ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, loop);
        emitCallback(builder, fault);
        builder.placeLabel(done);
        emitEpilogue(builder);

        return verifyGeneratedUnwind(linuxContext, builder, fault);
    }

    Result verifyFramelessUnwind(TaskContext& ctx, const bool indirectJump, const bool fault)
    {
        CommandLine commandLine = ctx.cmdLine();
        commandLine.targetOs = Runtime::TargetOs::Linux;
        CompilerInstance compiler(ctx.global(), commandLine);
        TaskContext context(compiler);
        MicroBuilder builder(context);
        constexpr MicroReg sp = MicroReg::intReg(4);
        constexpr MicroReg rbx = MicroReg::intReg(1);
        constexpr MicroReg xmm6 = MicroReg::floatReg(6);
        builder.emitPush(rbx);
        builder.emitOpBinaryRegImm(sp, ApInt(512, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitLoadMemReg(sp, 0, xmm6, MicroOpBits::B128);
        builder.emitLoadRegReg(xmm6, MicroReg::floatReg(0), MicroOpBits::B128);
        builder.emitLoadRegImm(rbx, ApInt(0x12345678, 64), MicroOpBits::B64);
        if (indirectJump)
        {
            const auto destination = builder.createLabel();
            const std::array labels{destination};
            builder.emitLoadLabelAddress(MicroReg::intReg(0), destination);
            builder.emitJumpReg(MicroReg::intReg(0), labels);
            builder.emitJumpTableData(labels);
            builder.placeLabel(destination);
        }
        emitCallback(builder, fault);
        builder.emitLoadRegMem(xmm6, sp, 0, MicroOpBits::B128);
        builder.emitOpBinaryRegImm(sp, ApInt(512, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitPop(rbx);
        builder.emitRet();
        return verifyGeneratedUnwind(context, builder, fault);
    }
}

SWC_TEST_BEGIN(EncodeX64_LinuxUnwindsBothReturnPaths)
{
    SWC_RESULT(verifyControlFlowUnwind(ctx, false, false));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_LinuxUnwindsMergedDynamicStackPaths)
{
    SWC_RESULT(verifyControlFlowUnwind(ctx, true, false));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_LinuxFaultUnwindsColdPathAndNativeCleanup)
{
    SWC_RESULT(verifyControlFlowUnwind(ctx, false, true));
    SWC_RESULT(verifyControlFlowUnwind(ctx, true, true));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_LinuxUnwindsFramelessSavedRegisters)
{
    SWC_RESULT(verifyFramelessUnwind(ctx, false, false));
    SWC_RESULT(verifyFramelessUnwind(ctx, false, true));
}
SWC_TEST_END()

SWC_TEST_BEGIN(EncodeX64_LinuxUnwindsIndirectJumpPastEmbeddedData)
{
    SWC_RESULT(verifyFramelessUnwind(ctx, true, false));
    SWC_RESULT(verifyFramelessUnwind(ctx, true, true));
}
SWC_TEST_END()

SWC_END_NAMESPACE();
#endif
