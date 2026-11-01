#include "pch.h"

#if SWC_HAS_UNITTEST && defined(__linux__) && defined(__x86_64__)
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABICall.SystemV.h"
#include "Backend/ABI/SystemVAbi.h"
#include <sys/mman.h>
#include <unistd.h>
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Backend/Micro/MachineCode.h"
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

    struct MixedValue { uint64_t integer; double floating; };
    struct ReverseMixedValue { double floating; uint64_t integer; };
    struct TwoIntegers { uint64_t first; uint64_t second; };
    struct TwoFloats { double first; double second; };
    struct LargeValue { uint64_t first; uint64_t second; uint64_t third; };
    struct SevenBytes { uint8_t bytes[7]; };
    using FourFloats = float __attribute__((vector_size(16)));

    __attribute__((noinline)) MixedValue changeMixed(MixedValue value)
    {
        return {value.integer + 19, value.floating * 3};
    }

    __attribute__((noinline)) ReverseMixedValue changeReverseMixed(ReverseMixedValue value)
    {
        return {value.floating * 5, value.integer + 23};
    }

    __attribute__((noinline)) TwoIntegers changeIntegers(TwoIntegers value)
    {
        return {value.second + 17, value.first + 29};
    }

    __attribute__((noinline)) TwoFloats changeFloats(TwoFloats value)
    {
        return {value.second * 7, value.first * 11};
    }

    __attribute__((noinline)) double exhaustedIntegers(uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f, MixedValue value, double tail)
    {
        return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + value.integer * 7 + value.floating * 8 + tail * 9;
    }

    __attribute__((noinline)) double exhaustedFloats(double a, double b, double c, double d, double e, double f, double g, double h, MixedValue value, uint64_t tail)
    {
        return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g + 8 * h + value.integer * 9 + value.floating * 10 + tail * 11;
    }

    __attribute__((noinline)) LargeValue changeLarge(LargeValue value, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f, double tail)
    {
        return {value.third + a + 2 * b, value.second + c + 3 * d, value.first + e + 4 * f + static_cast<uint64_t>(tail)};
    }

    __attribute__((noinline)) FourFloats addVectors(FourFloats a, FourFloats b, FourFloats c, FourFloats d, FourFloats e, FourFloats f, FourFloats g, FourFloats h, FourFloats i)
    {
        return a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7 + h * 8 + i * 9;
    }

    __attribute__((noinline)) SevenBytes changeSeven(SevenBytes value, uint64_t increment)
    {
        for (uint32_t index = 0; index < 7; ++index)
            value.bytes[index] += static_cast<uint8_t>(increment + index);
        return value;
    }

    struct __attribute__((packed)) PackedValue { uint8_t prefix; uint64_t integer; };

    __attribute__((noinline)) PackedValue changePacked(PackedValue value, uint64_t increment)
    {
        return {static_cast<uint8_t>(value.prefix + 3), value.integer + increment};
    }

    __attribute__((noinline)) double sumVariadicMixed(uint32_t count, ...)
    {
        va_list args;
        va_start(args, count);
        double result = 0;
        for (uint32_t index = 0; index < count; ++index)
        {
            const MixedValue value = va_arg(args, MixedValue);
            result += (index + 1) * (value.integer + value.floating);
        }
        va_end(args);
        return result;
    }

    __attribute__((noinline)) MixedValue mergePrepared(MixedValue first, uint64_t marker, MixedValue second, double tail)
    {
        return {first.integer + second.integer * 3 + marker * 5, first.floating + second.floating * 7 + tail * 11};
    }

    __attribute__((noinline)) uint64_t nativeCallbackZero()
    {
        return 0x123456789abcdef0;
    }

    __attribute__((noinline)) uint64_t nativeCallbackOne(uint64_t value)
    {
        return value * 13 + 7;
    }

    __attribute__((noinline)) uint64_t nativeCallbackTwo(uint64_t first, uint64_t second)
    {
        const uint64_t result = first * 7 + second * 11;
        // These are volatile in System V and persistent in the incoming Swag ABI.
        asm volatile("xor %%edi, %%edi; xor %%esi, %%esi; pxor %%xmm6, %%xmm6; pxor %%xmm7, %%xmm7" : : : "rdi", "rsi", "xmm6", "xmm7", "cc");
        return result;
    }

    struct CallbackException { uint64_t value; };

    __attribute__((noinline)) uint64_t nativeCallbackThrows(uint64_t first, uint64_t second)
    {
        throw CallbackException{first * 7 + second * 11};
    }

    struct GuardedStorage
    {
        size_t pageSize = static_cast<size_t>(sysconf(_SC_PAGESIZE));
        void* pages = mmap(nullptr, pageSize * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);

        ~GuardedStorage()
        {
            if (pages != MAP_FAILED)
                munmap(pages, pageSize * 2);
        }

        void* tail(const size_t bytes) const
        {
            if (pages == MAP_FAILED || mprotect(static_cast<std::byte*>(pages) + pageSize, pageSize, PROT_NONE))
                return nullptr;
            return static_cast<std::byte*>(pages) + pageSize - bytes;
        }
    };

    void installSystemVCode(JITMemoryManager& manager, JITMemory& memory, const ByteArray& code, const ByteArray& unwind)
    {
        manager.allocateWithCodeSize(memory, static_cast<uint32_t>(code.size() + unwind.size() + 3), static_cast<uint32_t>(code.size()));
        std::memcpy(memory.entryPoint(), code.data(), code.size());
        JITMemoryManager::copyUnwindInfo(memory, unwind.span());
        JITMemoryManager::registerUnwindInfo(memory);
        JITMemoryManager::makeExecutable(memory);
    }

    Result buildSystemVReturningThunk(TaskContext& context, JITMemoryManager& manager, JITMemory& memory, const SystemVAbi::Classification& type, const void* value)
    {
        MicroBuilder builder(context);
        // RAX deliberately starts as the address and ends as a result lane.
        const MicroReg address = MicroReg::intReg(0);
        builder.emitLoadRegPtrImm(address, reinterpret_cast<uint64_t>(value));
        ABICall::loadSystemVReturn(builder, address, type);
        builder.emitRet();
        MachineCode lowered;
        SWC_RESULT(lowered.emit(context, builder));
        if (lowered.unwindInfo.empty())
            return Result::Error;
        installSystemVCode(manager, memory, lowered.bytes, lowered.unwindInfo);
        return Result::Continue;
    }

    Result executeSystemVThunk(TaskContext& context, MicroBuilder& builder, const bool fullPipeline = false)
    {
        builder.emitRet();
        ByteArray code;
        ByteArray unwind;
        if (fullPipeline)
        {
            MachineCode lowered;
            SWC_RESULT(lowered.emit(context, builder));
            code = std::move(lowered.bytes);
            unwind = std::move(lowered.unwindInfo);
        }
        else
        {
            X64Encoder encoder(context);
            SWC_RESULT(Backend::Unittest::runMicroPass<MicroPostRaDeadCodeElimPass>(builder, &encoder, K_SYSTEM_V));
            SWC_RESULT(Backend::Unittest::runMicroPass<MicroEmitPass>(builder, &encoder, K_SYSTEM_V));
            code.resize(encoder.size());
            encoder.copyTo(code);
            encoder.buildUnwindInfo(unwind);
        }
        if (unwind.empty())
            return Result::Error;
        JITMemoryManager manager;
        JITMemory memory;
        installSystemVCode(manager, memory, code, unwind);
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
    compiler.buildCfg().backend.enableExceptions = false;
    compiler.buildCfg().backend.debugInfo = false;
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
    SWC_RESULT(executeSystemVThunk(context, builder, true));
    if (result != 21.5)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVRoundTripsMixedAndTwoRegisterResults)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    using SystemVAbi::Class;
    const std::array<SystemVAbi::Classification, 4> types{{
        {{Class::Integer, Class::Sse}, 16, 8},
        {{Class::Sse, Class::Integer}, 16, 8},
        {{Class::Integer, Class::Integer}, 16, 8},
        {{Class::Sse, Class::Sse}, 16, 8},
    }};
    const MixedValue mixed{31, 2.5};
    const ReverseMixedValue reverse{4.5, 37};
    const TwoIntegers integers{41, 43};
    const TwoFloats floats{6.5, 8.5};
    const std::array<const void*, 4> inputs{&mixed, &reverse, &integers, &floats};
    const std::array<uint64_t, 4> targets{reinterpret_cast<uint64_t>(changeMixed), reinterpret_cast<uint64_t>(changeReverseMixed), reinterpret_cast<uint64_t>(changeIntegers), reinterpret_cast<uint64_t>(changeFloats)};
    const MixedValue expectedMixed = changeMixed(mixed);
    const ReverseMixedValue expectedReverse = changeReverseMixed(reverse);
    const TwoIntegers expectedIntegers = changeIntegers(integers);
    const TwoFloats expectedFloats = changeFloats(floats);
    const std::array<const void*, 4> expected{&expectedMixed, &expectedReverse, &expectedIntegers, &expectedFloats};
    for (const bool fullPipeline : {false, true})
    {
        for (uint32_t index = 0; index < types.size(); ++index)
        {
            MicroBuilder builder(context);
            std::array<std::byte, 16> result{};
            const std::array args{ABICall::Arg{.value = reinterpret_cast<uint64_t>(inputs[index]), .systemVType = &types[index]}};
            ABICall::callAddress(builder, K_SYSTEM_V, targets[index], args, {.valuePtr = result.data(), .isVoid = false, .systemVType = &types[index]});
            SWC_RESULT(executeSystemVThunk(context, builder, fullPipeline));
            if (std::memcmp(result.data(), expected[index], result.size()))
                return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVSpilledAggregateLeavesOtherBankAvailable)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    using SystemVAbi::Class;
    const SystemVAbi::Classification type{{Class::Integer, Class::Sse}, 16, 8};
    const MixedValue mixed{29, 4.5};
    for (const bool exhaustInteger : {false, true})
    {
        MicroBuilder builder(context);
        std::vector<ABICall::Arg> args;
        for (uint32_t index = 0; index < (exhaustInteger ? 6u : 8u); ++index)
            args.push_back({.value = exhaustInteger ? index + 1 : std::bit_cast<uint64_t>(static_cast<double>(index + 1)), .isFloat = !exhaustInteger, .numBits = 64});
        args.push_back({.value = reinterpret_cast<uint64_t>(&mixed), .systemVType = &type});
        args.push_back({.value = exhaustInteger ? std::bit_cast<uint64_t>(13.5) : 17, .isFloat = exhaustInteger, .numBits = 64});
        double result = 0;
        const auto target = exhaustInteger ? reinterpret_cast<uint64_t>(exhaustedIntegers) : reinterpret_cast<uint64_t>(exhaustedFloats);
        ABICall::callAddress(builder, K_SYSTEM_V, target, args, {.valuePtr = &result, .isVoid = false, .isFloat = true, .numBits = 64});
        SWC_RESULT(executeSystemVThunk(context, builder, true));
        const double expected = exhaustInteger ? exhaustedIntegers(1, 2, 3, 4, 5, 6, mixed, 13.5) : exhaustedFloats(1, 2, 3, 4, 5, 6, 7, 8, mixed, 17);
        if (result != expected)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVMemoryResultConsumesFirstIntegerLane)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    MicroBuilder builder(context);
    using SystemVAbi::Class;
    const SystemVAbi::Classification type{{Class::Memory, Class::None}, 24, 8};
    const LargeValue input{19, 23, 29};
    LargeValue result{};
    std::vector<ABICall::Arg> args{{.value = reinterpret_cast<uint64_t>(&input), .systemVType = &type}};
    for (uint64_t index = 1; index <= 6; ++index)
        args.push_back({.value = index, .numBits = 64});
    args.push_back({.value = std::bit_cast<uint64_t>(13.0), .isFloat = true, .numBits = 64});
    ABICall::callAddress(builder, K_SYSTEM_V, reinterpret_cast<uint64_t>(changeLarge), args, {.valuePtr = &result, .isVoid = false, .systemVType = &type});
    SWC_RESULT(executeSystemVThunk(context, builder, true));
    const LargeValue expected = changeLarge(input, 1, 2, 3, 4, 5, 6, 13);
    if (std::memcmp(&result, &expected, sizeof(result)))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVVectorUpperHalfSurvivesRegistersAndStack)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    MicroBuilder builder(context);
    using SystemVAbi::Class;
    const SystemVAbi::Classification type{{Class::Sse, Class::SseUp}, 16, 16};
    std::array<FourFloats, 9> values{};
    std::array<ABICall::Arg, 9> args{};
    FourFloats expected{};
    for (uint32_t index = 0; index < values.size(); ++index)
    {
        values[index] = FourFloats{index + 0.5f, index + 1.5f, index + 2.5f, index + 3.5f};
        expected += values[index] * static_cast<float>(index + 1);
        args[index] = {.value = reinterpret_cast<uint64_t>(&values[index]), .systemVType = &type};
    }
    FourFloats result{};
    ABICall::callAddress(builder, K_SYSTEM_V, reinterpret_cast<uint64_t>(addVectors), args, {.valuePtr = &result, .isVoid = false, .systemVType = &type});
    SWC_RESULT(executeSystemVThunk(context, builder, true));
    for (uint32_t index = 0; index < 4; ++index)
    {
        if (result[index] != expected[index])
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVPartialEightbyteRespectsStorageBoundary)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    using SystemVAbi::Class;
    const SystemVAbi::Classification type{{Class::Integer, Class::None}, 7, 1};
    GuardedStorage inputStorage;
    GuardedStorage outputStorage;
    auto* input = static_cast<SevenBytes*>(inputStorage.tail(sizeof(SevenBytes)));
    auto* result = static_cast<SevenBytes*>(outputStorage.tail(sizeof(SevenBytes)));
    if (!input || !result)
        return Result::Error;
    *input = {{1, 3, 5, 7, 9, 11, 13}};
    const auto expected = changeSeven(*input, 17);
    for (const bool fullPipeline : {false, true})
    {
        MicroBuilder builder(context);
        *result = {};
        const std::array args{ABICall::Arg{.value = reinterpret_cast<uint64_t>(input), .systemVType = &type}, ABICall::Arg{.value = 17, .numBits = 64}};
        ABICall::callAddress(builder, K_SYSTEM_V, reinterpret_cast<uint64_t>(changeSeven), args, {.valuePtr = result, .isVoid = false, .systemVType = &type});
        SWC_RESULT(executeSystemVThunk(context, builder, fullPipeline));
        if (std::memcmp(result, &expected, sizeof(expected)))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVPackedMemoryValueRespectsStorageBoundary)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    MicroBuilder builder(context);
    using SystemVAbi::Class;
    const SystemVAbi::Classification type{{Class::Memory, Class::None}, sizeof(PackedValue), alignof(PackedValue)};
    GuardedStorage inputStorage;
    GuardedStorage outputStorage;
    auto* input = static_cast<PackedValue*>(inputStorage.tail(sizeof(PackedValue)));
    auto* result = static_cast<PackedValue*>(outputStorage.tail(sizeof(PackedValue)));
    if (!input || !result)
        return Result::Error;
    *input = {29, 0x123456789abcdef0};
    *result = {};
    const std::array args{ABICall::Arg{.value = reinterpret_cast<uint64_t>(input), .systemVType = &type}, ABICall::Arg{.value = 37, .numBits = 64}};
    ABICall::callAddress(builder, K_SYSTEM_V, reinterpret_cast<uint64_t>(changePacked), args, {.valuePtr = result, .isVoid = false, .systemVType = &type});
    SWC_RESULT(executeSystemVThunk(context, builder, true));
    const auto expected = changePacked(*input, 37);
    if (std::memcmp(result, &expected, sizeof(expected)))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVVariadicAggregatesUseBothBanksAndStack)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    using SystemVAbi::Class;
    const SystemVAbi::Classification type{{Class::Integer, Class::Sse}, 16, 8};
    std::array<MixedValue, 10> values{};
    for (const uint32_t count : {0, 1, 5, 6, 10})
    {
        MicroBuilder builder(context);
        std::vector<ABICall::Arg> args{{.value = count, .numBits = 32}};
        double expected = 0;
        for (uint32_t index = 0; index < count; ++index)
        {
            values[index] = {index + 7, index + 0.5};
            expected += (index + 1) * (values[index].integer + values[index].floating);
            args.push_back({.value = reinterpret_cast<uint64_t>(&values[index]), .systemVType = &type});
        }
        double result = -1;
        ABICall::callAddress(builder, K_SYSTEM_V, reinterpret_cast<uint64_t>(sumVariadicMixed), args, {.valuePtr = &result, .isVoid = false, .isFloat = true, .numBits = 64});
        SWC_RESULT(executeSystemVThunk(context, builder, true));
        if (result != expected)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVPreparedAggregatesPreserveOverlappingSources)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    using SystemVAbi::Class;
    const SystemVAbi::Classification type{{Class::Integer, Class::Sse}, 16, 8};
    const MixedValue first{13, 2.5};
    const MixedValue second{17, 3.5};
    const auto expected = mergePrepared(first, 19, second, 4.5);
    for (const bool virtualSources : {false, true})
    {
        MicroBuilder builder(context);
        const MicroReg firstAddress = virtualSources ? MicroReg::virtualIntReg(100) : MicroReg::intReg(7);
        const MicroReg secondAddress = virtualSources ? MicroReg::virtualIntReg(101) : MicroReg::intReg(6);
        const MicroReg marker = virtualSources ? MicroReg::virtualIntReg(102) : MicroReg::intReg(10);
        const MicroReg floating = virtualSources ? MicroReg::virtualFloatReg(100) : MicroReg::floatReg(0);
        const MicroReg floatBits = virtualSources ? MicroReg::virtualIntReg(103) : MicroReg::intReg(11);
        builder.emitLoadRegPtrImm(firstAddress, reinterpret_cast<uint64_t>(&first));
        builder.emitLoadRegPtrImm(secondAddress, reinterpret_cast<uint64_t>(&second));
        builder.emitLoadRegImm(marker, ApInt(19, 64), MicroOpBits::B64);
        builder.emitLoadRegImm(floatBits, ApInt(std::bit_cast<uint64_t>(4.5), 64), MicroOpBits::B64);
        builder.emitLoadRegReg(floating, floatBits, MicroOpBits::B64);
        const std::array args{
            ABICall::PreparedArg{.srcReg = firstAddress, .systemVType = &type},
            ABICall::PreparedArg{.srcReg = marker, .numBits = 64},
            ABICall::PreparedArg{.srcReg = secondAddress, .systemVType = &type},
            ABICall::PreparedArg{.srcReg = floating, .isFloat = true, .numBits = 64},
        };
        const auto prepared = ABICall::prepareArgs(builder, K_SYSTEM_V, args);
        const MicroReg target = MicroReg::intReg(0);
        builder.emitLoadRegPtrImm(target, reinterpret_cast<uint64_t>(mergePrepared));
        MixedValue result{};
        ABICall::callReg(builder, K_SYSTEM_V, target, prepared, {.valuePtr = &result, .isVoid = false, .systemVType = &type});
        SWC_RESULT(executeSystemVThunk(context, builder, true));
        if (result.integer != expected.integer || result.floating != expected.floating)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVPreparedAggregateSpillKeepsLaterVectorLane)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    MicroBuilder builder(context);
    using SystemVAbi::Class;
    const SystemVAbi::Classification type{{Class::Integer, Class::Sse}, 16, 8};
    const MixedValue mixed{29, 4.5};
    std::vector<ABICall::PreparedArg> args;
    for (uint32_t index = 0; index < 6; ++index)
    {
        const auto source = MicroReg::virtualIntReg(100 + index);
        builder.emitLoadRegImm(source, ApInt(index + 1, 64), MicroOpBits::B64);
        args.push_back({.srcReg = source, .numBits = 64});
    }
    const auto address = MicroReg::virtualIntReg(200);
    builder.emitLoadRegPtrImm(address, reinterpret_cast<uint64_t>(&mixed));
    args.push_back({.srcReg = address, .systemVType = &type});
    const auto tail = MicroReg::virtualIntReg(201);
    builder.emitLoadRegImm(tail, ApInt(std::bit_cast<uint64_t>(13.5), 64), MicroOpBits::B64);
    args.push_back({.srcReg = tail, .isFloat = true, .numBits = 64});
    const auto prepared = ABICall::prepareArgs(builder, K_SYSTEM_V, args);
    const MicroReg target = MicroReg::intReg(0);
    builder.emitLoadRegPtrImm(target, reinterpret_cast<uint64_t>(exhaustedIntegers));
    double result = 0;
    ABICall::callReg(builder, K_SYSTEM_V, target, prepared, {.valuePtr = &result, .isVoid = false, .isFloat = true, .numBits = 64});
    SWC_RESULT(executeSystemVThunk(context, builder, true));
    if (result != exhaustedIntegers(1, 2, 3, 4, 5, 6, mixed, 13.5))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVPreparedMemoryResultAndStackArgument)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    MicroBuilder builder(context);
    using SystemVAbi::Class;
    const SystemVAbi::Classification type{{Class::Memory, Class::None}, 24, 8};
    const LargeValue input{19, 23, 29};
    LargeValue result{};
    const auto output = MicroReg::virtualIntReg(100);
    const auto source = MicroReg::virtualIntReg(101);
    builder.emitLoadRegPtrImm(output, reinterpret_cast<uint64_t>(&result));
    builder.emitLoadRegPtrImm(source, reinterpret_cast<uint64_t>(&input));
    std::vector<ABICall::PreparedArg> args{{.srcReg = output, .numBits = 64}, {.srcReg = source, .systemVType = &type}};
    for (uint32_t index = 0; index < 6; ++index)
    {
        const auto integer = MicroReg::virtualIntReg(102 + index);
        builder.emitLoadRegImm(integer, ApInt(index + 1, 64), MicroOpBits::B64);
        args.push_back({.srcReg = integer, .numBits = 64});
    }
    const auto floating = MicroReg::virtualIntReg(108);
    builder.emitLoadRegImm(floating, ApInt(std::bit_cast<uint64_t>(13.0), 64), MicroOpBits::B64);
    args.push_back({.srcReg = floating, .isFloat = true, .numBits = 64});
    const auto prepared = ABICall::prepareArgs(builder, K_SYSTEM_V, args);
    const auto target = MicroReg::virtualIntReg(109);
    builder.emitLoadRegPtrImm(target, reinterpret_cast<uint64_t>(changeLarge));
    ABICall::callReg(builder, K_SYSTEM_V, target, prepared);
    SWC_RESULT(executeSystemVThunk(context, builder, true));
    const auto expected = changeLarge(input, 1, 2, 3, 4, 5, 6, 13);
    if (std::memcmp(&result, &expected, sizeof(result)))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVGeneratedCalleeReturnsIndependentBanks)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    using SystemVAbi::Class;
    JITMemoryManager manager;
    {
        const TwoIntegers value{0x123456789abcdef0, 0xfedcba9876543210};
        const SystemVAbi::Classification type{{Class::Integer, Class::Integer}, 16, 8};
        JITMemory memory;
        SWC_RESULT(buildSystemVReturningThunk(context, manager, memory, type, &value));
        const auto result = reinterpret_cast<TwoIntegers (*)()>(memory.entryPoint())();
        if (result.first != value.first || result.second != value.second)
            return Result::Error;
    }
    {
        const TwoFloats value{13.5, 27.25};
        const SystemVAbi::Classification type{{Class::Sse, Class::Sse}, 16, 8};
        JITMemory memory;
        SWC_RESULT(buildSystemVReturningThunk(context, manager, memory, type, &value));
        const auto result = reinterpret_cast<TwoFloats (*)()>(memory.entryPoint())();
        if (result.first != value.first || result.second != value.second)
            return Result::Error;
    }
    {
        const MixedValue value{0x123456789abcdef0, 17.5};
        const SystemVAbi::Classification type{{Class::Integer, Class::Sse}, 16, 8};
        JITMemory memory;
        SWC_RESULT(buildSystemVReturningThunk(context, manager, memory, type, &value));
        const auto result = reinterpret_cast<MixedValue (*)()>(memory.entryPoint())();
        if (result.integer != value.integer || result.floating != value.floating)
            return Result::Error;
    }
    {
        const ReverseMixedValue value{19.5, 0xfedcba9876543210};
        const SystemVAbi::Classification type{{Class::Sse, Class::Integer}, 16, 8};
        JITMemory memory;
        SWC_RESULT(buildSystemVReturningThunk(context, manager, memory, type, &value));
        const auto result = reinterpret_cast<ReverseMixedValue (*)()>(memory.entryPoint())();
        if (result.integer != value.integer || result.floating != value.floating)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVGeneratedCalleeReturnsPartialAndVectorValues)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    using SystemVAbi::Class;
    JITMemoryManager manager;
    {
        GuardedStorage storage;
        auto* value = static_cast<SevenBytes*>(storage.tail(sizeof(SevenBytes)));
        if (!value)
            return Result::Error;
        *value = {{1, 3, 5, 7, 9, 11, 13}};
        const SystemVAbi::Classification type{{Class::Integer, Class::None}, 7, 1};
        JITMemory memory;
        SWC_RESULT(buildSystemVReturningThunk(context, manager, memory, type, value));
        const auto result = reinterpret_cast<SevenBytes (*)()>(memory.entryPoint())();
        if (std::memcmp(&result, value, sizeof(result)))
            return Result::Error;
    }
    {
        const FourFloats value{1.5, 2.5, 3.5, 4.5};
        const SystemVAbi::Classification type{{Class::Sse, Class::SseUp}, 16, 16};
        JITMemory memory;
        SWC_RESULT(buildSystemVReturningThunk(context, manager, memory, type, &value));
        const auto result = reinterpret_cast<FourFloats (*)()>(memory.entryPoint())();
        for (uint32_t index = 0; index < 4; ++index)
        {
            if (result[index] != value[index])
                return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_LinuxNativeInterfaceAdaptersTranslateArgumentsAndOutliveCompiler)
{
    std::array<void*, 3> adapters{};
    const std::array targets{reinterpret_cast<void*>(nativeCallbackZero), reinterpret_cast<void*>(nativeCallbackOne), reinterpret_cast<void*>(nativeCallbackTwo)};
    {
        CommandLine commandLine = ctx.cmdLine();
        commandLine.targetOs = Runtime::TargetOs::Linux;
        CompilerInstance compiler(ctx.global(), commandLine);
        TaskContext context(compiler);
        for (uint32_t count = 0; count < adapters.size(); ++count)
        {
            adapters[count] = JIT::getNativeInterfaceAdapter(context, targets[count], count);
            if (!adapters[count] || adapters[count] != JIT::getNativeInterfaceAdapter(context, targets[count], count))
                return Result::Error;
        }
    }
    using Zero = uint64_t (__attribute__((ms_abi)) *)();
    using One = uint64_t (__attribute__((ms_abi)) *)(uint64_t);
    using Two = uint64_t (__attribute__((ms_abi)) *)(uint64_t, uint64_t);
    if (reinterpret_cast<Zero>(adapters[0])() != nativeCallbackZero())
        return Result::Error;
    if (reinterpret_cast<One>(adapters[1])(29) != nativeCallbackOne(29))
        return Result::Error;
    if (reinterpret_cast<Two>(adapters[2])(31, 37) != nativeCallbackTwo(31, 37))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_LinuxNativeInterfaceAdaptersPreserveSwagRegisters)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    void* adapter = JIT::getNativeInterfaceAdapter(context, reinterpret_cast<void*>(nativeCallbackTwo), 2);
    if (!adapter)
        return Result::Error;
    MicroBuilder builder(context);
    const std::array<uint64_t, 4> sentinels{0x123456789abcdef0, 0xfedcba9876543210, 0xa1b2c3d4e5f60718, 0x1827364554637281};
    builder.emitLoadRegImm(MicroReg::intReg(7), ApInt(sentinels[0], 64), MicroOpBits::B64);
    builder.emitLoadRegImm(MicroReg::intReg(6), ApInt(sentinels[1], 64), MicroOpBits::B64);
    for (uint32_t index = 0; index < 2; ++index)
    {
        builder.emitLoadRegImm(MicroReg::intReg(10), ApInt(sentinels[index + 2], 64), MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::floatReg(6 + index), MicroReg::intReg(10), MicroOpBits::B64);
    }
    const CallConv& swag = CallConv::get(CallConvKind::Swag);
    builder.emitLoadRegImm(swag.intArgRegs[0], ApInt(31, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(swag.intArgRegs[1], ApInt(37, 64), MicroOpBits::B64);
    builder.emitLoadRegPtrImm(swag.intReturn, reinterpret_cast<uint64_t>(adapter));
    const ABICall::PreparedCall prepared{.numPreparedArgs = 2, .intArgMask = 3};
    ABICall::callReg(builder, CallConvKind::Swag, swag.intReturn, prepared);
    std::array<uint64_t, 5> actual{};
    const MicroReg output = MicroReg::intReg(10);
    builder.emitLoadRegPtrImm(output, reinterpret_cast<uint64_t>(actual.data()));
    builder.emitLoadMemReg(output, 0, MicroReg::intReg(7), MicroOpBits::B64);
    builder.emitLoadMemReg(output, 8, MicroReg::intReg(6), MicroOpBits::B64);
    builder.emitLoadMemReg(output, 16, MicroReg::floatReg(6), MicroOpBits::B64);
    builder.emitLoadMemReg(output, 24, MicroReg::floatReg(7), MicroOpBits::B64);
    builder.emitLoadMemReg(output, 32, swag.intReturn, MicroOpBits::B64);
    SWC_RESULT(executeSystemVThunk(context, builder, true));
    for (uint32_t index = 0; index < sentinels.size(); ++index)
    {
        if (actual[index] != sentinels[index])
        {
            std::fprintf(stderr, "System V adapter changed preserved lane %u: expected %llx, got %llx\n", index, static_cast<unsigned long long>(sentinels[index]), static_cast<unsigned long long>(actual[index]));
            return Result::Error;
        }
    }
    if (actual[4] != nativeCallbackTwo(31, 37))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_LinuxNativeInterfaceAdapterUnwindsThroughHostCallback)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    void* adapter = JIT::getNativeInterfaceAdapter(context, reinterpret_cast<void*>(nativeCallbackThrows), 2);
    if (!adapter)
        return Result::Error;
    using Callback = uint64_t (__attribute__((ms_abi)) *)(uint64_t, uint64_t);
    try
    {
        reinterpret_cast<Callback>(adapter)(31, 37);
    }
    catch (const CallbackException& error)
    {
        return error.value == 31 * 7 + 37 * 11 ? Result::Continue : Result::Error;
    }
    return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();
#endif
