#include "pch.h"

#if SWC_HAS_UNITTEST && defined(__linux__) && defined(__x86_64__)
#include "Backend/ABI/ABICall.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Backend/Micro/Passes/Pass.Emit.h"
#include "Backend/Micro/Passes/Pass.PostRADeadCodeElim.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr auto K_SYSTEM_V = CallConvKind::SystemVAMD64;

    __attribute__((noinline)) double sumMixed(uint64_t a0, double f0, uint64_t a1, double f1, uint64_t a2, double f2, uint64_t a3, double f3, uint64_t a4, double f4, uint64_t a5, double f5, uint64_t a6, double f6, uint64_t a7, double f7, uint64_t a8, double f8, uint64_t a9, double f9)
    {
        return a0 + f0 + 2 * (a1 + f1) + 3 * (a2 + f2) + 4 * (a3 + f3) + 5 * (a4 + f4) + 6 * (a5 + f5) + 7 * (a6 + f6) + 8 * (a7 + f7) + 9 * (a8 + f8) + 10 * (a9 + f9);
    }

    __attribute__((noinline)) double sumVariadic(uint32_t count, ...)
    {
        va_list args;
        va_start(args, count);
        double result = 0;
        for (uint32_t index = 0; index < count; ++index)
            result += (index + 1) * va_arg(args, double);
        va_end(args);
        return result;
    }

    __attribute__((naked, noinline)) uint64_t vectorCount(uint32_t, ...)
    {
        asm("movzbl %al, %eax\nret");
    }

    __attribute__((noinline)) double twoScalars(uint64_t integer, double floating)
    {
        return integer * 2 + floating;
    }

    Result executeSystemVThunk(TaskContext& context, MicroBuilder& builder)
    {
        builder.emitRet();
        X64Encoder encoder(context);
        SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaDeadCodeElimPass>(builder, &encoder, K_SYSTEM_V));
        SWC_RESULT(Backend::Unittest::runMicroPass<MicroEmitPass>(builder, &encoder, K_SYSTEM_V));
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
        reinterpret_cast<void (*)()>(memory.entryPoint())();
        return Result::Continue;
    }
}

SWC_TEST_BEGIN(ABI_SystemVScalarRegisterAndStackBanks)
{
    const CallConv& conv = CallConv::get(K_SYSTEM_V);
    if (conv.intArgRegs.size() != 6 || conv.floatArgRegs.size() != 8 || conv.stackShadowSpace || !conv.independentArgBanks || conv.stackAlignment != 16)
        return Result::Error;
    if (conv.isIntPersistentReg(MicroReg::intReg(6)) || conv.isIntPersistentReg(MicroReg::intReg(7)) || !conv.floatPersistentRegs.empty())
        return Result::Error;

    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    MicroBuilder builder(context);
    std::array<ABICall::Arg, 20> args{};
    double expected = 0;
    for (uint32_t index = 0; index < 10; ++index)
    {
        const uint64_t integer = index + 11;
        const double floating = index + 0.25;
        args[2 * index] = {.value = integer, .numBits = 64};
        args[2 * index + 1] = {.value = std::bit_cast<uint64_t>(floating), .isFloat = true, .numBits = 64};
        expected += (index + 1) * (integer + floating);
    }
    double result = 0;
    ABICall::callAddress(builder, K_SYSTEM_V, reinterpret_cast<uint64_t>(sumMixed), args, {.valuePtr = &result, .isVoid = false, .isFloat = true, .numBits = 64});
    SWC_RESULT(executeSystemVThunk(context, builder));
    if (result != expected)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVVariadicVectorCountAndStackArguments)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    for (const uint32_t count : {0, 1, 8, 10})
    {
        MicroBuilder builder(context);
        std::vector<ABICall::Arg> args{{.value = count, .numBits = 32}};
        double expected = 0;
        for (uint32_t index = 0; index < count; ++index)
        {
            const double value = index + 0.5;
            args.push_back({.value = std::bit_cast<uint64_t>(value), .isFloat = true, .numBits = 64});
            expected += (index + 1) * value;
        }
        double result = -1;
        ABICall::callAddress(builder, K_SYSTEM_V, reinterpret_cast<uint64_t>(sumVariadic), args, {.valuePtr = &result, .isVoid = false, .isFloat = true, .numBits = 64});
        SWC_RESULT(executeSystemVThunk(context, builder));
        if (result != expected)
            return Result::Error;

        MicroBuilder inspect(context);
        uint64_t vectorRegisters = UINT64_MAX;
        ABICall::callAddress(inspect, K_SYSTEM_V, reinterpret_cast<uint64_t>(vectorCount), args, {.valuePtr = &vectorRegisters, .isVoid = false, .numBits = 64});
        SWC_RESULT(executeSystemVThunk(context, inspect));
        if (vectorRegisters != std::min(count, 8u))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVPreparedRegistersPreserveRaxCallTarget)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    MicroBuilder builder(context);
    constexpr MicroReg integer = MicroReg::intReg(10);
    constexpr MicroReg bits = MicroReg::intReg(11);
    constexpr MicroReg floating = MicroReg::floatReg(8);
    constexpr MicroReg target = MicroReg::intReg(0);
    builder.emitLoadRegImm(integer, ApInt(9, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(bits, ApInt(std::bit_cast<uint64_t>(3.5), 64), MicroOpBits::B64);
    builder.emitLoadRegReg(floating, bits, MicroOpBits::B64);
    const std::array args = {
        ABICall::PreparedArg{.srcReg = integer, .numBits = 64},
        ABICall::PreparedArg{.srcReg = floating, .isFloat = true, .numBits = 64},
    };
    const auto prepared = ABICall::prepareArgs(builder, K_SYSTEM_V, args);
    builder.emitLoadRegPtrImm(target, reinterpret_cast<uint64_t>(twoScalars));
    double result = 0;
    ABICall::callReg(builder, K_SYSTEM_V, target, prepared, {.valuePtr = &result, .isVoid = false, .isFloat = true, .numBits = 64});
    SWC_RESULT(executeSystemVThunk(context, builder));
    if (result != 21.5)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();
#endif
