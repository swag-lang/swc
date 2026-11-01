#include "pch.h"

#if SWC_HAS_UNITTEST && defined(__linux__) && defined(__x86_64__)
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABICall.SystemV.h"
#include "Backend/ABI/SystemVAbi.h"
#include <sys/mman.h>
#include <pthread.h>
#include <unistd.h>
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/JIT/JIT.h"
#include "Backend/RuntimeContext.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Support/Os/Os.h"
#include "Backend/Micro/Passes/Pass.Emit.h"
#include "Backend/Micro/Passes/Pass.PostRADeadCodeElim.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/Command.h"
#include "Unittest/UnittestSource.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenParameterReg.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Unittest/ABI/AbiTestTypes.h"
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

    __attribute__((naked, noinline)) uint64_t fullIntegerArgument(int8_t)
    {
        asm("mov %rdi, %rax\nret");
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

    thread_local uint32_t lifecycleCopies = 0;
    thread_local uint32_t lifecycleDrops = 0;

    __attribute__((ms_abi, noinline)) void copyMixedValue(MixedValue* value)
    {
        ++lifecycleCopies;
        value->integer += 101;
        value->floating *= 7;
    }

    __attribute__((ms_abi, noinline)) void dropMixedValue(MixedValue* value)
    {
        ++lifecycleDrops;
        *value = {};
    }

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

    Result buildSystemVReceivingThunk(TaskContext& context, JITMemoryManager& manager, JITMemory& memory, const std::span<const SystemVAbi::Classification> types, const std::span<void* const> destinations)
    {
        SWC_ASSERT(types.size() == destinations.size());
        MicroBuilder builder(context);
        SystemVAbi::ArgumentAllocator allocator;
        std::vector<SystemVAbi::ArgumentLocation> locations;
        for (const auto& type : types)
            locations.push_back(allocator.next(type));
        // Exercise stack copies before capturing register arguments, so any scratch
        // clobber of an incoming lane changes the later values the native caller sent.
        for (const bool onStack : {true, false})
        {
            for (uint32_t index = 0; index < types.size(); ++index)
            {
                if (locations[index].onStack != onStack)
                    continue;
                const MicroReg destination = MicroReg::intReg(10);
                builder.emitLoadRegPtrImm(destination, reinterpret_cast<uint64_t>(destinations[index]));
                ABICall::storeSystemVArgument(builder, destination, types[index], locations[index]);
            }
        }
        builder.setRetUsesAbiRegs(false, false);
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

SWC_TEST_BEGIN(JIT_CrossHostForeignBranchRejectsOnlyWhenExecuted)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Windows;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    context.setMuteOutput(true);
    SWC_RESULT(compiler.setupSema(context));
    auto* foreign = Symbol::make<SymbolFunction>(context, nullptr, TokenRef::invalid(), context.idMgr().addIdentifier("unavailable_foreign"), SymbolFlagsE::Zero);
    AttributeList attributes;
    attributes.hasForeign = true;
    attributes.foreignModuleName = "kernel32";
    attributes.foreignFunctionName = "ExitProcess";
    foreign->setAttributes(context, attributes);
    foreign->setCallConvKind(CallConvKind::WindowsX64);
    foreign->setReturnTypeRef(context.typeMgr().typeVoid());

    uint64_t executeForeign = 0;
    MicroBuilder builder(context);
    const auto done = builder.createLabel();
    const auto flag = MicroReg::virtualIntReg(1);
    builder.emitLoadRegPtrImm(flag, reinterpret_cast<uint64_t>(&executeForeign));
    builder.emitLoadRegMem(flag, flag, 0, MicroOpBits::B64);
    builder.emitCmpRegImm(flag, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, done);
    const ABICall::PreparedCall prepared = ABICall::prepareArgs(builder, CallConvKind::WindowsX64, {});
    ABICall::callExtern(builder, CallConvKind::WindowsX64, foreign, prepared);
    builder.placeLabel(done);
    builder.emitRet();
    MachineCode lowered;
    SWC_RESULT(lowered.emit(context, builder));
    JITMemory memory;
    SWC_RESULT(JIT::emit(context, memory, lowered.bytes, lowered.codeRelocations, lowered.jitUnwindInfo(context)));
    if (!foreign->jitEntryAddress() || foreign->jitForeignTargetGuard(context) != foreign->jitEntryAddress())
    {
        std::println(stderr, "[foreign target guard] relocation did not retain the guard, relocations={}", lowered.codeRelocations.size());
        return Result::Error;
    }
    SWC_RESULT(JIT::call(context, memory.entryPoint(), nullptr, nullptr, JITRuntimeSetupMode::None, CallConvKind::Swag));

    executeForeign = 1;
    const uint64_t errorsBefore = Stats::getNumErrors();
    const Result rejected = JIT::call(context, memory.entryPoint(), nullptr, nullptr, JITRuntimeSetupMode::None, CallConvKind::Swag);
    const uint64_t errorsAfter = Stats::getNumErrors();
    Stats::get().numErrors.store(errorsBefore, std::memory_order_relaxed);
    if (rejected != Result::Error || errorsAfter != errorsBefore + 1)
    {
        std::println(stderr, "[foreign target guard] call result={}, errors={} -> {}", static_cast<uint32_t>(rejected), errorsBefore, errorsAfter);
        return Result::Error;
    }

    // An aborted call must leave the host fault boundary and context usable.
    executeForeign = 0;
    SWC_RESULT(JIT::call(context, memory.entryPoint(), nullptr, nullptr, JITRuntimeSetupMode::None, CallConvKind::Swag));
    compiler.resetPreparedJitFunctions();
    if (foreign->jitEntryAddress())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_LinuxHostUnwindsGeneratedCodeForEitherOutputTarget)
{
    // Reuse the worker encoder across target changes. Both the native format and
    // the additional host format must be reset with each emitted function.
    for (const auto target : {Runtime::TargetOs::Windows, Runtime::TargetOs::Linux, Runtime::TargetOs::Windows})
    {
        CommandLine commandLine = ctx.cmdLine();
        commandLine.targetOs = target;
        CompilerInstance compiler(ctx.global(), commandLine);
        TaskContext context(compiler);
        MicroBuilder builder(context);
        const std::array<ABICall::Arg, 2> args{{{.value = 31, .numBits = 64}, {.value = 37, .numBits = 64}}};
        ABICall::callAddress(builder, CallConv::hostKind(), reinterpret_cast<uint64_t>(nativeCallbackThrows), args, {});
        builder.emitRet();
        MachineCode lowered;
        SWC_RESULT(lowered.emit(context, builder));
        if (lowered.unwindInfo.empty() || lowered.hostUnwindInfo.empty() != (target == Runtime::TargetOs::Linux))
            return Result::Error;
        JITMemory memory;
        SWC_RESULT(JIT::emit(context, memory, lowered.bytes, lowered.codeRelocations, lowered.jitUnwindInfo(context)));
        bool caught = false;
        try
        {
            SWC_RESULT(JIT::call(context, memory.entryPoint(), nullptr, nullptr, JITRuntimeSetupMode::None, CallConvKind::Swag));
        }
        catch (const CallbackException& error)
        {
            caught = error.value == 31 * 7 + 37 * 11;
        }
        if (!caught)
            return Result::Error;
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

SWC_TEST_BEGIN(JIT_LinuxTlsReadsPreserveRegistersFlagsAndLeafStack)
{
    struct Slot
    {
        uint64_t id = Os::tlsAlloc();
        ~Slot() { pthread_key_delete(static_cast<pthread_key_t>(id)); }
    } slot;
    uint64_t value = 42;
    Os::tlsSetValue(slot.id, &value);
    CommandLine command = ctx.cmdLine();
    command.targetOs = Runtime::TargetOs::Windows;
    CompilerInstance compiler(ctx.global(), command);
    TaskContext context(compiler);
    using Probe = uint64_t(__attribute__((ms_abi)) *)();
    for (const bool preserveState : {false, true})
    {
        MicroBuilder builder(context);
        Runtime::BuildCfgBackend backend{};
        backend.optimLevel = Runtime::BuildCfgBackendOptimLevel::O0;
        builder.setBackendBuildCfg(backend);
        builder.setRetUsesAbiRegs(true, false);
        const MicroReg result = MicroReg::intReg(0);
        const MicroReg index = MicroReg::intReg(2);
        std::array<std::array<uint64_t, 2>, 16> vectors{}, actualVectors{};
        std::array<uint64_t, 16> actualRegisters{};
        const auto failed = builder.createLabel();
        if (preserveState)
        {
            for (uint32_t reg = 0; reg < 16; ++reg)
                vectors[reg] = {0x1234567800000000 + reg, 0xfedcba9800000000 + reg};
            builder.emitLoadRegPtrImm(index, reinterpret_cast<uint64_t>(vectors.data()));
            for (uint32_t reg = 0; reg < 16; ++reg)
                builder.emitLoadVecRegMem(MicroReg::floatReg(reg), index, reg * 16, MicroOpBits::B128);
            for (uint32_t reg = 0; reg < 16; ++reg)
                if (reg != 4)
                    builder.emitLoadRegImm(MicroReg::intReg(reg), ApInt(0x1000 + reg, 64), MicroOpBits::B64);
        }
        builder.emitLoadRegImm(index, ApInt(slot.id + 1, 64), MicroOpBits::B64);
        // The real stack pointer keeps this flag producer unknown to constant folding.
        builder.emitCmpRegImm(MicroReg::intReg(4), ApInt(0, 64), MicroOpBits::B64);
        builder.emitLoadRegTlsSlot(result, index);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, failed);
        if (preserveState)
        {
            builder.emitCmpRegImm(index, ApInt(slot.id + 1, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, failed);
            builder.emitLoadRegPtrImm(index, reinterpret_cast<uint64_t>(actualRegisters.data()));
            for (uint32_t reg = 0; reg < 16; ++reg)
                if (reg != 4 && reg != index.index())
                    builder.emitLoadMemReg(index, reg * 8, MicroReg::intReg(reg), MicroOpBits::B64);
            builder.emitLoadRegPtrImm(index, reinterpret_cast<uint64_t>(actualVectors.data()));
            for (uint32_t reg = 0; reg < 16; ++reg)
                builder.emitLoadMemReg(index, reg * 16, MicroReg::floatReg(reg), MicroOpBits::B128);
        }
        builder.emitRet();
        builder.placeLabel(failed);
        builder.emitLoadRegImm(result, ApInt(0, 64), MicroOpBits::B64);
        builder.emitRet();
        MachineCode code;
        SWC_RESULT(code.emit(context, builder));
        if (code.tlsAccesses.size() != 1 || !code.tlsAccesses[0].valid(code.bytes.span()))
            return Result::Error;
        JITMemory memory;
        SWC_RESULT(JIT::prepare(context, memory, code.bytes, code.jitUnwindInfo(context), code.codeRelocations, code.tlsAccesses));
        SWC_RESULT(JIT::patch(context, memory, code.codeRelocations));
        JIT::finalize(memory);
        if (reinterpret_cast<Probe>(memory.entryPoint())() != reinterpret_cast<uint64_t>(&value))
            return Result::Error;
        if (preserveState)
        {
            for (uint32_t reg = 0; reg < 16; ++reg)
                if (reg != 4 && reg != index.index() && actualRegisters[reg] != (reg == result.index() ? reinterpret_cast<uint64_t>(&value) : 0x1000 + reg))
                    return Result::Error;
            if (actualVectors != vectors)
                return Result::Error;
        }
        if (!code.tlsAccesses[0].valid(code.bytes.span()))
            return Result::Error;
    }
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

SWC_TEST_BEGIN(ABI_SystemVGeneratedCalleeReceivesMixedRegisterValues)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    using SystemVAbi::Class;
    const std::array<SystemVAbi::Classification, 5> types{{
        {{Class::Integer, Class::Sse}, 16, 8},
        {{Class::Sse, Class::Integer}, 16, 8},
        {{Class::Sse, Class::Sse}, 16, 8},
        {{Class::Integer, Class::Integer}, 16, 8},
        {{Class::Sse, Class::SseUp}, 16, 16},
    }};
    const MixedValue mixed{13, 2.5};
    const ReverseMixedValue reverse{3.5, 17};
    const TwoFloats floats{5.5, 7.5};
    const TwoIntegers integers{19, 23};
    const FourFloats vector{1.5, 2.5, 3.5, 4.5};
    std::array<std::array<std::byte, 16>, 5> actual{};
    const std::array<void*, 5> destinations{actual[0].data(), actual[1].data(), actual[2].data(), actual[3].data(), actual[4].data()};
    const std::array<const void*, 5> expected{&mixed, &reverse, &floats, &integers, &vector};
    JITMemoryManager manager;
    JITMemory memory;
    SWC_RESULT(buildSystemVReceivingThunk(context, manager, memory, types, destinations));
    using Receiver = void (*)(MixedValue, ReverseMixedValue, TwoFloats, TwoIntegers, FourFloats);
    reinterpret_cast<Receiver>(memory.entryPoint())(mixed, reverse, floats, integers, vector);
    for (uint32_t index = 0; index < actual.size(); ++index)
    {
        if (std::memcmp(actual[index].data(), expected[index], 16))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVGeneratedCalleeReceivesStackValuesBeforeRegisterHomes)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    using SystemVAbi::Class;
    std::array<SystemVAbi::Classification, 10> types{};
    std::array<uint64_t, 6> integers{};
    MixedValue mixed{};
    double floating = 0;
    LargeValue large{};
    FourFloats vector{};
    std::array<void*, 10> destinations{};
    for (uint32_t index = 0; index < 6; ++index)
    {
        types[index] = {{Class::Integer, Class::None}, 8, 8};
        destinations[index] = &integers[index];
    }
    types[6] = {{Class::Integer, Class::Sse}, 16, 8};
    types[7] = {{Class::Sse, Class::None}, 8, 8};
    types[8] = {{Class::Memory, Class::None}, 24, 8};
    types[9] = {{Class::Sse, Class::SseUp}, 16, 16};
    destinations[6] = &mixed;
    destinations[7] = &floating;
    destinations[8] = &large;
    destinations[9] = &vector;
    const MixedValue expectedMixed{29, 4.5};
    const LargeValue expectedLarge{31, 37, 41};
    const FourFloats expectedVector{1.5, 2.5, 3.5, 4.5};
    JITMemoryManager manager;
    JITMemory memory;
    SWC_RESULT(buildSystemVReceivingThunk(context, manager, memory, types, destinations));
    using Receiver = void (*)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, MixedValue, double, LargeValue, FourFloats);
    reinterpret_cast<Receiver>(memory.entryPoint())(1, 2, 3, 4, 5, 6, expectedMixed, 13.5, expectedLarge, expectedVector);
    for (uint32_t index = 0; index < 6; ++index)
    {
        if (integers[index] != index + 1)
            return Result::Error;
    }
    if (mixed.integer != expectedMixed.integer || mixed.floating != expectedMixed.floating || floating != 13.5)
        return Result::Error;
    if (std::memcmp(&large, &expectedLarge, sizeof(large)) || std::memcmp(&vector, &expectedVector, sizeof(vector)))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVGeneratedCalleeReceivesAlignedAndPackedStackValues)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    using SystemVAbi::Class;
    std::array<SystemVAbi::Classification, 12> types{};
    std::array<FourFloats, 9> vectors{};
    std::array<FourFloats, 9> expectedVectors{};
    std::array<void*, 12> destinations{};
    for (uint32_t index = 0; index < 9; ++index)
    {
        types[index] = {{Class::Sse, Class::SseUp}, 16, 16};
        destinations[index] = &vectors[index];
        expectedVectors[index] = FourFloats{index + 0.5f, index + 1.5f, index + 2.5f, index + 3.5f};
    }
    GuardedStorage packedStorage;
    auto* packed = static_cast<PackedValue*>(packedStorage.tail(sizeof(PackedValue)));
    if (!packed)
        return Result::Error;
    *packed = {};
    MixedValue mixed{};
    uint64_t integer = 0;
    types[9] = {{Class::Memory, Class::None}, sizeof(PackedValue), alignof(PackedValue)};
    types[10] = {{Class::Integer, Class::Sse}, 16, 8};
    types[11] = {{Class::Integer, Class::None}, 8, 8};
    destinations[9] = packed;
    destinations[10] = &mixed;
    destinations[11] = &integer;
    const PackedValue expectedPacked{29, 0x123456789abcdef0};
    const MixedValue expectedMixed{31, 4.5};
    JITMemoryManager manager;
    JITMemory memory;
    SWC_RESULT(buildSystemVReceivingThunk(context, manager, memory, types, destinations));
    using Receiver = void (*)(FourFloats, FourFloats, FourFloats, FourFloats, FourFloats, FourFloats, FourFloats, FourFloats, FourFloats, PackedValue, MixedValue, uint64_t);
    reinterpret_cast<Receiver>(memory.entryPoint())(expectedVectors[0], expectedVectors[1], expectedVectors[2], expectedVectors[3], expectedVectors[4], expectedVectors[5], expectedVectors[6], expectedVectors[7], expectedVectors[8], expectedPacked, expectedMixed, 37);
    if (std::memcmp(vectors.data(), expectedVectors.data(), sizeof(vectors)))
        return Result::Error;
    if (std::memcmp(packed, &expectedPacked, sizeof(*packed)) || mixed.integer != expectedMixed.integer || mixed.floating != expectedMixed.floating || integer != 37)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVGeneratedCalleeFillsHiddenMemoryResult)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    MicroBuilder builder(context);
    using SystemVAbi::Class;
    const SystemVAbi::Classification type{{Class::Memory, Class::None}, sizeof(LargeValue), alignof(LargeValue)};
    const CallConv& conv = CallConv::get(K_SYSTEM_V);
    const MicroReg destination = conv.intArgRegs[0];
    const MicroReg value = conv.intArgRegs[1];
    const MicroReg scratch = MicroReg::intReg(10);
    for (uint32_t field = 0; field < 3; ++field)
    {
        builder.emitLoadRegReg(scratch, value, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(scratch, ApInt(field + 1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitLoadMemReg(destination, field * sizeof(uint64_t), scratch, MicroOpBits::B64);
    }
    ABICall::loadSystemVReturn(builder, destination, type);
    builder.emitRet();
    MachineCode lowered;
    SWC_RESULT(lowered.emit(context, builder));
    JITMemoryManager manager;
    JITMemory memory;
    installSystemVCode(manager, memory, lowered.bytes, lowered.unwindInfo);
    const LargeValue result = reinterpret_cast<LargeValue (*)(uint64_t)>(memory.entryPoint())(37);
    if (result.first != 38 || result.second != 39 || result.third != 40)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVSemanticTypeHandlesDrivePreparedCallsAndReturnStorage)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    SWC_RESULT(compiler.setupSema(context));
    const std::array fields{context.typeMgr().typeU64(), context.typeMgr().typeF64()};
    const TypeRef typeRef = Backend::Unittest::makeStructType(context, fields);
    const auto& type = context.typeMgr().get(typeRef);
    const auto& conv = CallConv::get(K_SYSTEM_V);
    const auto argument = ABITypeNormalize::normalize(context, conv, type, ABITypeNormalize::Usage::Argument);
    const auto returned = ABITypeNormalize::normalize(context, conv, type, ABITypeNormalize::Usage::Return);
    if (!argument.isSystemVStorage() || !returned.isSystemVStorage())
        return Result::Error;
    const MixedValue input{31, 2.5};
    MixedValue result{};
    MicroBuilder builder(context);
    const auto source = MicroReg::virtualIntReg(100);
    builder.emitLoadRegPtrImm(source, reinterpret_cast<uint64_t>(&input));
    const std::array args{ABICall::PreparedArg{.srcReg = source, .isAddressed = true, .numBits = argument.numBits, .systemVTypeRef = typeRef}};
    const auto prepared = ABICall::prepareArgs(builder, K_SYSTEM_V, args);
    const auto target = MicroReg::virtualIntReg(101);
    builder.emitLoadRegPtrImm(target, reinterpret_cast<uint64_t>(changeMixed));
    ABICall::callReg(builder, K_SYSTEM_V, target, prepared);
    const auto output = MicroReg::virtualIntReg(102);
    builder.emitLoadRegPtrImm(output, reinterpret_cast<uint64_t>(&result));
    ABICall::storeReturnRegsToReturnBuffer(builder, K_SYSTEM_V, output, returned);
    SWC_RESULT(executeSystemVThunk(context, builder, true));
    const auto expected = changeMixed(input);
    if (result.integer != expected.integer || result.floating != expected.floating)
        return Result::Error;

    MicroBuilder callee(context);
    const auto value = MicroReg::intReg(0);
    callee.emitLoadRegPtrImm(value, reinterpret_cast<uint64_t>(&input));
    ABICall::materializeValueToReturnRegs(callee, K_SYSTEM_V, value, true, returned);
    callee.emitRet();
    MachineCode lowered;
    SWC_RESULT(lowered.emit(context, callee));
    JITMemoryManager manager;
    JITMemory memory;
    installSystemVCode(manager, memory, lowered.bytes, lowered.unwindInfo);
    const auto nativeResult = reinterpret_cast<MixedValue (*)()>(memory.entryPoint())();
    if (nativeResult.integer != input.integer || nativeResult.floating != input.floating)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVIntermediateReturnStorageKeepsEnclosingResultLive)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    MicroBuilder builder(context);
    builder.setRetUsesAbiRegs(true, false);
    using SystemVAbi::Class;
    const SystemVAbi::Classification type{{Class::Sse, Class::Sse}, 16, 8};
    const TwoFloats input{13.5, 27.25};
    TwoFloats stored{};
    const MicroReg address = MicroReg::intReg(0);
    builder.emitLoadRegPtrImm(address, reinterpret_cast<uint64_t>(&input));
    ABICall::loadSystemVReturn(builder, address, type);
    ABICall::storeSystemVReturn(builder, {.valuePtr = &stored, .isVoid = false, .systemVType = &type});
    constexpr uint64_t expected = 0x123456789abcdef0;
    builder.emitLoadRegImm(MicroReg::intReg(0), ApInt(expected, 64), MicroOpBits::B64);
    builder.emitRet();
    MachineCode lowered;
    SWC_RESULT(lowered.emit(context, builder));
    JITMemoryManager manager;
    JITMemory memory;
    installSystemVCode(manager, memory, lowered.bytes, lowered.unwindInfo);
    const uint64_t result = reinterpret_cast<uint64_t (*)()>(memory.entryPoint())();
    if (result != expected || stored.first != input.first || stored.second != input.second)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVCodeGenHomesPreserveIncomingScalarAndAggregateParameters)
{
    for (const auto level : {Runtime::BuildCfgBackendOptimLevel::O0, Runtime::BuildCfgBackendOptimLevel::O2})
    {
        CommandLine commandLine = ctx.cmdLine();
        commandLine.targetOs = Runtime::TargetOs::Linux;
        CompilerInstance compiler(ctx.global(), commandLine);
        TaskContext context(compiler);
        SWC_RESULT(compiler.setupSema(context));
        auto& types = context.typeMgr();
        const std::array locationFields{types.typeString(), types.typeString(), types.typeU32(), types.typeU32(), types.typeU32(), types.typeU32()};
        types.registerRuntimeType(context.idMgr().predefined(IdentifierManager::PredefinedName::SourceCodeLocation), Backend::Unittest::makeStructType(context, locationFields));
        const std::array mixedFields{types.typeU64(), types.typeF64()};
        const auto mixedType = Backend::Unittest::makeStructType(context, mixedFields);
        const std::array largeFields{types.typeU64(), types.typeU64(), types.typeU64()};
        const auto largeType = Backend::Unittest::makeStructType(context, largeFields);
        const std::array parameterTypes{largeType, mixedType, types.typeU64(), types.typeU64(), types.typeU64(), types.typeU64(), types.typeU64(), mixedType, types.typeF64(), types.typeString()};
        SourceFile& file = Backend::Unittest::makeCodeGenSource(context, "SystemVParameterHomes");
        Sema sema(context, file.nodePayloadContext(), false);
        CodeGen codeGen(sema);
        const auto [declRef, decl] = file.ast().makeNode<AstNodeId::FunctionDecl>(TokenRef::invalid());
        auto* function = Symbol::make<SymbolFunction>(context, decl, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        function->setDeclNodeRef(declRef);
        function->setCallConvKind(K_SYSTEM_V);
        function->setReturnTypeRef(types.typeVoid());
        for (const auto type : parameterTypes)
        {
            auto* param = Symbol::make<SymbolVariable>(context, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
            param->setTypeRef(type);
            param->addExtraFlag(SymbolVariableFlagsE::Parameter);
            function->addParameter(param);
        }
        // Initialize codegen on an empty AST, then exercise its parameter boundary
        // directly. This fixture needs no executable Swag runtime on the host.
        SWC_RESULT(codeGen.exec(*function, file.ast().root()));
        MicroBuilder& builder = codeGen.builder();
        auto backend = builder.backendBuildCfg();
        backend.optimLevel = level;
        builder.setBackendBuildCfg(backend);
        std::array<CodeGenFunctionHelpers::FunctionParameterInfo, parameterTypes.size()> infos;
        CodeGenFunctionHelpers::fillFunctionParameterInfos(codeGen, infos, *function, false, false);
        codeGen.setLocalStackFrameSize(128);
        uint32_t localOffset = 0;
        for (size_t i = 0; i < parameterTypes.size(); ++i)
        {
            if (!infos[i].isSystemVStorage)
                continue;
            auto& param = *function->parameters()[i];
            param.addExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
            param.setOffset(localOffset);
            param.setCodeGenLocalSize(static_cast<uint32_t>(types.get(param.typeRef()).sizeOf(context)));
            localOffset += 32;
        }
        CodeGenFunctionHelpers::emitLocalStackFramePrologue(codeGen, K_SYSTEM_V);
        CodeGenFunctionHelpers::materializeSystemVStorageParameters(codeGen, *function, infos);
        CodeGenParameterReg::materializeRegisterParameters(codeGen, *function, infos);
        std::array<std::array<std::byte, 24>, parameterTypes.size()> actual{};
        for (size_t i = 0; i < parameterTypes.size(); ++i)
        {
            const auto payload = CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, *function, *function->parameters()[i], &infos[i]);
            const MicroReg destination = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegPtrImm(destination, reinterpret_cast<uint64_t>(actual[i].data()));
            if (payload.isAddress())
            {
                const auto size = types.get(parameterTypes[i]).sizeOf(context);
                for (uint32_t offset = 0; offset < size; offset += 8)
                {
                    const MicroReg value = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegMem(value, payload.reg, offset, MicroOpBits::B64);
                    builder.emitLoadMemReg(destination, offset, value, MicroOpBits::B64);
                }
            }
            else
                builder.emitLoadMemReg(destination, 0, payload.reg, MicroOpBits::B64);
        }
        CodeGenFunctionHelpers::emitLocalStackFrameEpilogue(codeGen, K_SYSTEM_V);
        builder.setRetUsesAbiRegs(false, false);
        builder.emitRet();
        MachineCode lowered;
        SWC_RESULT(lowered.emit(context, builder));
        JITMemoryManager manager;
        JITMemory memory;
        installSystemVCode(manager, memory, lowered.bytes, lowered.unwindInfo);
        const LargeValue large{17, 19, 23};
        const MixedValue mixed{29, 3.5};
        const MixedValue spilled{31, 5.5};
        const double tail = 7.5;
        const Runtime::String string{"native parameter", 16};
        const std::array<uint64_t, 5> integers{41, 43, 47, 53, 59};
        using Receiver = void (*)(LargeValue, MixedValue, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, MixedValue, double, Runtime::String);
        reinterpret_cast<Receiver>(memory.entryPoint())(large, mixed, integers[0], integers[1], integers[2], integers[3], integers[4], spilled, tail, string);
        const std::array<const void*, parameterTypes.size()> expected{&large, &mixed, &integers[0], &integers[1], &integers[2], &integers[3], &integers[4], &spilled, &tail, &string};
        for (size_t i = 0; i < parameterTypes.size(); ++i)
        {
            if (std::memcmp(actual[i].data(), expected[i], types.get(parameterTypes[i]).sizeOf(context)))
                return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVDirectResultsMaterializeInCallerOwnedStorage)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    SWC_RESULT(compiler.setupSema(context));
    auto& types = context.typeMgr();
    const std::array mixedFields{types.typeU64(), types.typeF64()};
    const std::array integerFields{types.typeU64(), types.typeU64()};
    const std::array floatingFields{types.typeF64(), types.typeF64()};
    const std::array typeRefs{
        Backend::Unittest::makeStructType(context, mixedFields),
        Backend::Unittest::makeStructType(context, integerFields),
        Backend::Unittest::makeStructType(context, floatingFields),
    };
    const MixedValue mixed{41, 2.5};
    const TwoIntegers integers{43, 47};
    const TwoFloats floating{3.5, 5.5};
    const auto expectedMixed = changeMixed(mixed);
    const auto expectedIntegers = changeIntegers(integers);
    const auto expectedFloating = changeFloats(floating);
    const std::array<const void*, 3> inputs{&mixed, &integers, &floating};
    const std::array<const void*, 3> expected{&expectedMixed, &expectedIntegers, &expectedFloating};
    const std::array targets{reinterpret_cast<uint64_t>(changeMixed), reinterpret_cast<uint64_t>(changeIntegers), reinterpret_cast<uint64_t>(changeFloats)};
    for (size_t i = 0; i < typeRefs.size(); ++i)
    {
        std::array<std::byte, 16> result{};
        uint64_t resultAddress = 0;
        MicroBuilder builder(context);
        const auto source = MicroReg::virtualIntReg(1);
        const auto output = MicroReg::virtualIntReg(2);
        const auto target = MicroReg::virtualIntReg(3);
        const auto payload = MicroReg::virtualIntReg(4);
        const auto captured = MicroReg::virtualIntReg(5);
        builder.emitLoadRegPtrImm(source, reinterpret_cast<uint64_t>(inputs[i]));
        // The destination must survive the foreign call, just like a source
        // expression's local result slot prepared before argument placement.
        builder.emitLoadRegPtrImm(output, reinterpret_cast<uint64_t>(result.data()));
        const std::array args{ABICall::PreparedArg{.srcReg = source, .isAddressed = true, .numBits = 64, .systemVTypeRef = typeRefs[i]}};
        const auto prepared = ABICall::prepareArgs(builder, K_SYSTEM_V, args);
        builder.emitLoadRegPtrImm(target, targets[i]);
        ABICall::callReg(builder, K_SYSTEM_V, target, prepared);
        const auto returned = ABITypeNormalize::normalize(context, CallConv::get(K_SYSTEM_V), types.get(typeRefs[i]), ABITypeNormalize::Usage::Return);
        ABICall::materializeReturnToReg(builder, payload, K_SYSTEM_V, returned, output);
        builder.emitLoadRegPtrImm(captured, reinterpret_cast<uint64_t>(&resultAddress));
        builder.emitLoadMemReg(captured, 0, payload, MicroOpBits::B64);
        SWC_RESULT(executeSystemVThunk(context, builder, true));
        if (resultAddress != reinterpret_cast<uint64_t>(result.data()) || std::memcmp(result.data(), expected[i], result.size()))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVSourceReturnLoweringPreservesAllResultLanes)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    SWC_RESULT(compiler.setupSema(context));
    // This internal AST fixture exercises ordinary function/parameter/return
    // visitors without importing platform runtime bodies or executing sema JIT.
    compiler.buildCfg().safetyGuards = static_cast<Runtime::SafetyWhat>(0);
    compiler.buildCfg().sanityGuards = static_cast<Runtime::SafetyWhat>(0);
    auto& types = context.typeMgr();
    const std::array locationFields{types.typeString(), types.typeString(), types.typeU32(), types.typeU32(), types.typeU32(), types.typeU32()};
    types.registerRuntimeType(context.idMgr().predefined(IdentifierManager::PredefinedName::SourceCodeLocation), Backend::Unittest::makeStructType(context, locationFields));
    const std::array mixedFields{types.typeU64(), types.typeF64()};
    const std::array integerFields{types.typeU64(), types.typeU64()};
    const std::array floatingFields{types.typeF64(), types.typeF64()};
    const std::array largeFields{types.typeU64(), types.typeU64(), types.typeU64()};
    const std::array typeRefs{
        Backend::Unittest::makeStructType(context, mixedFields),
        Backend::Unittest::makeStructType(context, integerFields),
        Backend::Unittest::makeStructType(context, floatingFields),
        types.typeString(),
        Backend::Unittest::makeStructType(context, largeFields),
    };
    for (const auto level : {Runtime::BuildCfgBackendOptimLevel::O0, Runtime::BuildCfgBackendOptimLevel::O2})
    {
        compiler.buildCfg().backend.optimLevel = level;
        for (size_t i = 0; i < typeRefs.size(); ++i)
        {
            SourceFile& file = Backend::Unittest::makeCodeGenSource(context, std::format("SystemVSourceReturn_{}_{}", static_cast<uint32_t>(level), i));
            auto& ast = file.ast();
            const auto [declRef, decl] = ast.makeNode<AstNodeId::FunctionDecl>(TokenRef::invalid());
            const auto [exprRef, expr] = ast.makeNode<AstNodeId::Identifier>(TokenRef::invalid());
            decl->nodeBodyRef = exprRef;
            decl->addFlag(AstFunctionFlagsE::Short);
            auto* function = Symbol::make<SymbolFunction>(context, decl, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
            function->setDeclNodeRef(declRef);
            function->setDeclNodePayloadContext(&file.nodePayloadContext());
            function->setCallConvKind(K_SYSTEM_V);
            function->setReturnTypeRef(typeRefs[i]);
            auto* parameter = Symbol::make<SymbolVariable>(context, expr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
            parameter->setTypeRef(typeRefs[i]);
            parameter->addExtraFlag(SymbolVariableFlagsE::Parameter);
            function->addParameter(parameter);
            Sema sema(context, file.nodePayloadContext(), false);
            sema.setSymbol(declRef, function);
            sema.setSymbol(exprRef, parameter);
            sema.setIsLValue(exprRef);
            sema.frame().setCurrentFunction(function);
            CodeGen codeGen(sema);
            SWC_RESULT(codeGen.exec(*function, declRef));
            SWC_RESULT(function->emit(context));
            const auto& lowered = function->loweredCode();
            JITMemoryManager manager;
            JITMemory memory;
            installSystemVCode(manager, memory, lowered.bytes, lowered.unwindInfo);
            if (i == 0)
            {
                const MixedValue input{41, 3.5};
                const auto result = reinterpret_cast<MixedValue (*)(MixedValue)>(memory.entryPoint())(input);
                if (result.integer != input.integer || result.floating != input.floating)
                    return Result::Error;
            }
            else if (i == 1)
            {
                const TwoIntegers input{43, 47};
                const auto result = reinterpret_cast<TwoIntegers (*)(TwoIntegers)>(memory.entryPoint())(input);
                if (result.first != input.first || result.second != input.second)
                    return Result::Error;
            }
            else if (i == 2)
            {
                const TwoFloats input{5.5, 7.5};
                const auto result = reinterpret_cast<TwoFloats (*)(TwoFloats)>(memory.entryPoint())(input);
                if (result.first != input.first || result.second != input.second)
                    return Result::Error;
            }
            else if (i == 3)
            {
                const Runtime::String input{"source return", 13};
                const auto result = reinterpret_cast<Runtime::String (*)(Runtime::String)>(memory.entryPoint())(input);
                if (result.ptr != input.ptr || result.length != input.length)
                    return Result::Error;
            }
            else
            {
                const LargeValue input{53, 59, 61};
                const auto result = reinterpret_cast<LargeValue (*)(LargeValue)>(memory.entryPoint())(input);
                if (result.first != input.first || result.second != input.second || result.third != input.third)
                    return Result::Error;
            }
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVSourceReturnRunsCopyHookWithoutDroppingBorrowedArgument)
{
    for (const auto level : {Runtime::BuildCfgBackendOptimLevel::O0, Runtime::BuildCfgBackendOptimLevel::O2})
    {
        CommandLine commandLine = ctx.cmdLine();
        commandLine.targetOs = Runtime::TargetOs::Linux;
        CompilerInstance compiler(ctx.global(), commandLine);
        TaskContext context(compiler);
        SWC_RESULT(compiler.setupSema(context));
        compiler.buildCfg().safetyGuards = static_cast<Runtime::SafetyWhat>(0);
        compiler.buildCfg().sanityGuards = static_cast<Runtime::SafetyWhat>(0);
        compiler.buildCfg().backend.optimLevel = level;
        auto& types = context.typeMgr();
        const std::array locationFields{types.typeString(), types.typeString(), types.typeU32(), types.typeU32(), types.typeU32(), types.typeU32()};
        types.registerRuntimeType(context.idMgr().predefined(IdentifierManager::PredefinedName::SourceCodeLocation), Backend::Unittest::makeStructType(context, locationFields));
        const std::array fields{types.typeU64(), types.typeF64()};
        const TypeRef type = Backend::Unittest::makeStructType(context, fields);
        const TypeRef pointer = types.addType(TypeInfo::makeValuePointer(type));
        SourceFile& file = Backend::Unittest::makeCodeGenSource(context, "SystemVLifecycleReturn");
        auto& ast = file.ast();
        const auto [declRef, decl] = ast.makeNode<AstNodeId::FunctionDecl>(TokenRef::invalid());
        const auto [exprRef, expr] = ast.makeNode<AstNodeId::Identifier>(TokenRef::invalid());
        decl->nodeBodyRef = exprRef;
        decl->addFlag(AstFunctionFlagsE::Short);
        auto* function = Symbol::make<SymbolFunction>(context, decl, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        function->setDeclNodeRef(declRef);
        function->setDeclNodePayloadContext(&file.nodePayloadContext());
        function->setCallConvKind(K_SYSTEM_V);
        function->setReturnTypeRef(type);
        auto* parameter = Symbol::make<SymbolVariable>(context, expr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        parameter->setTypeRef(type);
        parameter->addExtraFlag(SymbolVariableFlagsE::Parameter);
        function->addParameter(parameter);

        // Lifecycle methods retain the Swag pointer ABI even when the enclosing
        // function returns an aggregate through the native System V registers.
        for (const auto kind : {SpecOpKind::OpPostCopy, SpecOpKind::OpDrop})
        {
            auto* hook = Symbol::make<SymbolFunction>(context, decl, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::SemaCompleted);
            hook->setCallConvKind(CallConvKind::Swag);
            hook->setReturnTypeRef(types.typeVoid());
            auto* receiver = Symbol::make<SymbolVariable>(context, expr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
            receiver->setTypeRef(pointer);
            receiver->addExtraFlag(SymbolVariableFlagsE::Parameter);
            hook->addParameter(receiver);
            SWC_RESULT(types.get(type).payloadSymStruct().registerSpecOp(*hook, kind));
            compiler.publishJitFunctionEntry(*hook, reinterpret_cast<void*>(kind == SpecOpKind::OpPostCopy ? &copyMixedValue : &dropMixedValue));
        }

        Sema sema(context, file.nodePayloadContext(), false);
        sema.setSymbol(declRef, function);
        sema.setSymbol(exprRef, parameter);
        sema.setIsLValue(exprRef);
        sema.frame().setCurrentFunction(function);
        CodeGen codeGen(sema);
        SWC_RESULT(codeGen.exec(*function, declRef));
        SWC_RESULT(function->emit(context));
        const auto& lowered = function->loweredCode();
        // These hook bodies live in the native test executable, so bind their
        // relocations directly instead of scheduling source compilation for them.
        auto relocations = lowered.codeRelocations;
        for (auto& relocation : relocations)
        {
            if (relocation.targetSymbol && relocation.targetSymbol->isFunction())
                relocation.targetAddress = reinterpret_cast<uint64_t>(relocation.targetSymbol->cast<SymbolFunction>().jitEntryAddress());
        }
        JITMemory memory;
        SWC_RESULT(JIT::prepare(context, memory, lowered.bytes, lowered.unwindInfo, relocations));
        SWC_RESULT(JIT::patch(context, memory, relocations, function));
        JIT::finalize(memory);
        lifecycleCopies = 0;
        lifecycleDrops = 0;
        const MixedValue input{79, 2.5};
        const auto result = reinterpret_cast<MixedValue (*)(MixedValue)>(memory.entryPoint())(input);
        if (result.integer != input.integer + 101 || result.floating != input.floating * 7)
            return Result::Error;
        if (lifecycleCopies != 1 || lifecycleDrops != 0)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVSourceReturnCapturesValueBeforeDeferredMutation)
{
    constexpr std::string_view source = R"(func identity(value: Value, replacement: Value, sink: *Value)->Value
{
    defer
    {
        value = replacement
        sink[] = value
    }
    return value
}
)";
    for (const auto level : {Runtime::BuildCfgBackendOptimLevel::O0, Runtime::BuildCfgBackendOptimLevel::O2})
    {
        CommandLine commandLine = ctx.cmdLine();
        commandLine.targetOs = Runtime::TargetOs::Linux;
        CompilerInstance compiler(ctx.global(), commandLine);
        TaskContext context(compiler);
        SWC_RESULT(compiler.setupSema(context));
        compiler.buildCfg().safetyGuards = static_cast<Runtime::SafetyWhat>(0);
        compiler.buildCfg().sanityGuards = static_cast<Runtime::SafetyWhat>(0);
        compiler.buildCfg().backend.optimLevel = level;
        auto& types = context.typeMgr();
        const std::array locationFields{types.typeString(), types.typeString(), types.typeU32(), types.typeU32(), types.typeU32(), types.typeU32()};
        types.registerRuntimeType(context.idMgr().predefined(IdentifierManager::PredefinedName::SourceCodeLocation), Backend::Unittest::makeStructType(context, locationFields));
        const std::array fields{types.typeU64(), types.typeF64()};
        const TypeRef type = Backend::Unittest::makeStructType(context, fields);
        const TypeRef pointer = types.addType(TypeInfo::makeValuePointer(type));
        SourceFile& file = Backend::Unittest::makeCodeGenSource(context, "SystemVDeferredReturn", source);
        auto& ast = file.ast();
        AstNodeRef declRef;
        Ast::visit(ast, ast.root(), [&](AstNodeRef ref, const AstNode& node) {
            if (node.is(AstNodeId::FunctionDecl))
            {
                declRef = ref;
                return Ast::VisitResult::Stop;
            }
            return Ast::VisitResult::Continue;
        });
        if (declRef.isInvalid())
            return Result::Error;
        auto& decl = ast.node(declRef).cast<AstFunctionDecl>();
        auto* function = Symbol::make<SymbolFunction>(context, &decl, decl.tokNameRef, context.idMgr().addIdentifier("identity"), SymbolFlagsE::Zero);
        function->setDeclNodeRef(declRef);
        function->setDeclNodePayloadContext(&file.nodePayloadContext());
        function->setCallConvKind(K_SYSTEM_V);
        function->setReturnTypeRef(type);
        for (const auto name : {"value", "replacement", "sink"})
        {
            auto* parameter = Symbol::make<SymbolVariable>(context, &decl, decl.tokNameRef, context.idMgr().addIdentifier(name), SymbolFlagsE::Zero);
            parameter->setTypeRef(std::string_view(name) == "sink" ? pointer : type);
            parameter->addExtraFlag(SymbolVariableFlagsE::Parameter);
            function->addParameter(parameter);
        }
        Sema sema(context, file.nodePayloadContext(), false);
        sema.setSymbol(declRef, function);
        sema.frame().setCurrentFunction(function);
        // Bind the parsed body as a completed semantic tree. Its opaque Value
        // type is supplied by this ABI fixture, independent of runtime imports.
        Ast::visit(ast, decl.nodeBodyRef, [&](AstNodeRef ref, const AstNode& node) {
            if (node.is(AstNodeId::Identifier))
            {
                const auto name = ast.srcView().tokenString(node.tokRef());
                for (auto* parameter : function->parameters())
                {
                    if (parameter->name(context) == name)
                    {
                        sema.setSymbol(ref, parameter);
                        sema.setIsLValue(ref);
                    }
                }
            }
            else if (node.is(AstNodeId::IndexExpr))
            {
                sema.setType(ref, type);
                sema.setIsLValue(ref);
            }
            return Ast::VisitResult::Continue;
        });
        CodeGen codeGen(sema);
        SWC_RESULT(codeGen.exec(*function, declRef));
        SWC_RESULT(function->emit(context));
        const auto& lowered = function->loweredCode();
        JITMemoryManager manager;
        JITMemory memory;
        installSystemVCode(manager, memory, lowered.bytes, lowered.unwindInfo);
        const MixedValue value{67, 3.5};
        const MixedValue replacement{71, 5.5};
        MixedValue sink{};
        using Identity = MixedValue (*)(MixedValue, MixedValue, MixedValue*);
        const auto result = reinterpret_cast<Identity>(memory.entryPoint())(value, replacement, &sink);
        if (result.integer != value.integer || result.floating != value.floating)
            return Result::Error;
        if (sink.integer != replacement.integer || sink.floating != replacement.floating)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_LinuxTypedInvokerReadsNativeFrameAndSeparatesAggregateShapes)
{
    // Recreate semantic types after each compiler dies. Cached wrappers must
    // retain ABI shapes alone, never these type handles or argument addresses.
    for (uint32_t iteration = 0; iteration < 3; ++iteration)
    {
        CommandLine commandLine = ctx.cmdLine();
        commandLine.targetOs = Runtime::TargetOs::Linux;
        CompilerInstance compiler(ctx.global(), commandLine);
        TaskContext context(compiler);
        SWC_RESULT(compiler.setupSema(context));
        auto& types = context.typeMgr();
        const int8_t negative = -7;
        uint64_t extended = 0;
        const std::array narrowArgs{JITArgument{types.typeS8(), &negative}};
        SWC_RESULT(JIT::emitAndCall(context, reinterpret_cast<void*>(fullIntegerArgument), narrowArgs, {types.typeU64(), &extended}, K_SYSTEM_V));
        if (extended != static_cast<uint64_t>(static_cast<int64_t>(negative)))
            return Result::Error;
        const uint64_t integer = 31 + iteration;
        const double floating = 2.5 + iteration;
        double scalarResult = 0;
        const std::array scalarArgs{JITArgument{types.typeU64(), &integer}, JITArgument{types.typeF64(), &floating}};
        SWC_RESULT(JIT::emitAndCall(context, reinterpret_cast<void*>(twoScalars), scalarArgs, {types.typeF64(), &scalarResult}, K_SYSTEM_V));
        if (scalarResult != twoScalars(integer, floating))
            return Result::Error;
        const std::array mixedFields{types.typeU64(), types.typeF64()};
        const std::array integerFields{types.typeU64(), types.typeU64()};
        const std::array floatingFields{types.typeF64(), types.typeF64()};
        const std::array typeRefs{
            Backend::Unittest::makeStructType(context, mixedFields),
            Backend::Unittest::makeStructType(context, integerFields),
            Backend::Unittest::makeStructType(context, floatingFields),
        };
        const MixedValue mixed{integer, floating};
        const TwoIntegers integers{integer, integer + 7};
        const TwoFloats floats{floating, floating + 11};
        const auto expectedMixed = changeMixed(mixed);
        const auto expectedIntegers = changeIntegers(integers);
        const auto expectedFloats = changeFloats(floats);
        const std::array<const void*, 3> inputs{&mixed, &integers, &floats};
        const std::array<const void*, 3> expected{&expectedMixed, &expectedIntegers, &expectedFloats};
        const std::array targets{reinterpret_cast<void*>(changeMixed), reinterpret_cast<void*>(changeIntegers), reinterpret_cast<void*>(changeFloats)};
        for (size_t i = 0; i < typeRefs.size(); ++i)
        {
            std::array<std::byte, 16> output{};
            const std::array args{JITArgument{typeRefs[i], inputs[i]}};
            SWC_RESULT(JIT::emitAndCall(context, targets[i], args, {typeRefs[i], output.data()}, K_SYSTEM_V));
            if (std::memcmp(output.data(), expected[i], output.size()))
                return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_LinuxTypedInvokerPassesStackAggregatesAndHiddenResults)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    SWC_RESULT(compiler.setupSema(context));
    auto& types = context.typeMgr();
    const std::array largeFields{types.typeU64(), types.typeU64(), types.typeU64()};
    const auto largeType = Backend::Unittest::makeStructType(context, largeFields);
    const std::array mixedFields{types.typeU64(), types.typeF64()};
    const auto mixedType = Backend::Unittest::makeStructType(context, mixedFields);
    const LargeValue input{17, 19, 23};
    const MixedValue mixed{29, 3.5};
    const std::array<uint64_t, 6> integers{31, 37, 41, 43, 47, 53};
    const double tail = 5.5;
    std::array<JITArgument, 8> args;
    args[0] = {largeType, &input};
    for (size_t i = 0; i < integers.size(); ++i)
        args[i + 1] = {types.typeU64(), &integers[i]};
    args[7] = {types.typeF64(), &tail};
    LargeValue result{};
    SWC_RESULT(JIT::emitAndCall(context, reinterpret_cast<void*>(changeLarge), args, {largeType, &result}, K_SYSTEM_V));
    const auto expected = changeLarge(input, integers[0], integers[1], integers[2], integers[3], integers[4], integers[5], tail);
    if (std::memcmp(&result, &expected, sizeof(result)))
        return Result::Error;
    for (size_t i = 0; i < integers.size(); ++i)
        args[i] = {types.typeU64(), &integers[i]};
    args[6] = {mixedType, &mixed};
    double scalar = 0;
    SWC_RESULT(JIT::emitAndCall(context, reinterpret_cast<void*>(exhaustedIntegers), args, {types.typeF64(), &scalar}, K_SYSTEM_V));
    if (scalar != exhaustedIntegers(integers[0], integers[1], integers[2], integers[3], integers[4], integers[5], mixed, tail))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_LinuxTypedInvokerCountsVariadicAggregateVectors)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    SWC_RESULT(compiler.setupSema(context));
    auto& types = context.typeMgr();
    const std::array mixedFields{types.typeU64(), types.typeF64()};
    const auto mixedType = Backend::Unittest::makeStructType(context, mixedFields);
    const std::array floatFields{types.typeF64(), types.typeF64()};
    const auto floatsType = Backend::Unittest::makeStructType(context, floatFields);
    const uint32_t count = 3;
    const MixedValue mixed{17, 2.5};
    const TwoFloats floats{3.5, 5.5};
    const double tail = 7.5;
    const std::array args{JITArgument{types.typeU32(), &count}, JITArgument{mixedType, &mixed}, JITArgument{floatsType, &floats}, JITArgument{types.typeF64(), &tail}};
    uint64_t vectors = 0;
    SWC_RESULT(JIT::emitAndCall(context, reinterpret_cast<void*>(vectorCount), args, {types.typeU64(), &vectors}, K_SYSTEM_V));
    if (vectors != 4)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_LinuxRuntimeSetupReceivesSwagScalarConvention)
{
    CommandLine commandLine = ctx.cmdLine();
    commandLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), commandLine);
    TaskContext context(compiler);
    SWC_RESULT(compiler.setupSema(context));
    uint64_t receivedFlags = UINT64_MAX;
    MicroBuilder builder(context);
    const auto destination = MicroReg::virtualIntReg(1);
    builder.emitLoadRegPtrImm(destination, reinterpret_cast<uint64_t>(&receivedFlags));
    builder.emitLoadMemReg(destination, 0, CallConv::swag().intArgRegs[0], MicroOpBits::B64);
    builder.setRetUsesAbiRegs(false, false);
    builder.emitRet();
    MachineCode lowered;
    SWC_RESULT(lowered.emit(context, builder));
    JITMemoryManager manager;
    JITMemory memory;
    installSystemVCode(manager, memory, lowered.bytes, lowered.unwindInfo);
    auto* declaration = compiler.allocate<AstNode>(AstNodeId::FunctionDecl, SourceCodeRef::invalid());
    const auto setupId = context.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::SetupRuntime);
    auto* setup = Symbol::make<SymbolFunction>(context, declaration, TokenRef::invalid(), setupId, SymbolFlagsE::SemaCompleted);
    compiler.registerRuntimeFunctionSymbol(setupId, setup);
    compiler.publishJitFunctionEntry(*setup, memory.entryPoint());
    auto* function = Symbol::make<SymbolFunction>(context, declaration, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::SemaCompleted);
    context.state().runJitFunction = function;
    SWC_RESULT(JIT::call(context, reinterpret_cast<void*>(nativeCallbackZero)));
    if (receivedFlags != static_cast<uint64_t>(Runtime::RuntimeFlags::FromCompiler))
    {
        std::println(stderr, "runtime setup flags: {}", receivedFlags);
        return Result::Error;
    }
    const uint64_t directArgument = 0x123456789ABCDEF0;
    SWC_RESULT(JIT::call(context, memory.entryPoint(), &directArgument, nullptr, JITRuntimeSetupMode::None, CallConvKind::Swag));
    if (receivedFlags != directArgument)
    {
        std::println(stderr, "direct Swag argument: {}", receivedFlags);
        return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_LinuxRuntimeDiagnosticsResumeWarningsAndUnwindErrors)
{
    CommandLine cmdLine;
    cmdLine.targetOs = Runtime::TargetOs::Linux;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext context(compiler);
    SWC_RESULT(compiler.setupSema(context));
    context.setMuteOutput(true);
    compiler.initPerThreadRuntimeContextForJit();
    auto* runtime = CompilerInstance::runtimeContextFromTls();
    const uint64_t argument = reinterpret_cast<uint64_t>(runtime);
    const uint64_t errorsBefore = Stats::getNumErrors();
    struct RestoreErrors
    {
        uint64_t saved;
        ~RestoreErrors() { Stats::get().numErrors.store(saved); }
    } restore{errorsBefore};

    for (const auto kind : {Runtime::ExceptionKind::Warning, Runtime::ExceptionKind::Error, Runtime::ExceptionKind::Warning})
    {
        runtime->exceptionParams[3] = reinterpret_cast<const void*>(static_cast<uint64_t>(kind));
        auto errorKind = JITCallErrorKind::None;
        const Result result = JIT::call(context, reinterpret_cast<void*>(runtime->compilerRaise), &argument, &errorKind, JITRuntimeSetupMode::None, CallConvKind::Swag);
        if (kind == Runtime::ExceptionKind::Warning)
        {
            if (result != Result::Continue || errorKind != JITCallErrorKind::None)
                return Result::Error;
        }
        else if (result != Result::Error || errorKind != JITCallErrorKind::HardwareException)
            return Result::Error;
        if (runtime->exceptionParams[3])
            return Result::Error;
    }
    if (Stats::getNumErrors() != errorsBefore + 1)
        return Result::Error;
}
SWC_TEST_END()

namespace
{
    struct RuntimeProbeOptions
    {
        bool native = false;
        Runtime::TargetOs targetOs = Runtime::TargetOs::Linux;
    };

    Result runLinuxRuntimeProbe(const TaskContext& ctx, std::string_view name, std::string_view source, RuntimeProbeOptions options = {})
    {
        struct RemoveNativeArtifacts
        {
            fs::path path;
            ~RemoveNativeArtifacts() { if (!path.empty()) { std::error_code error; fs::remove_all(path, error); } }
        } artifacts;
        CommandLine command;
        command.command  = options.native ? CommandKind::Run : CommandKind::Sema;
        command.targetOs = options.targetOs;
        command.buildCfg = "devmode";
        command.numCores = 3;
        command.silent   = true;
        command.name     = name;
        if (options.native)
        {
            artifacts.path = Os::getTemporaryPath() / "swc_unittest" / std::format("{}_p{}", name, Os::currentProcessId());
            command.outDir = artifacts.path / "output";
            command.workDir = artifacts.path / "work";
            command.outDirStorage = Utf8(command.outDir);
            command.workDirStorage = Utf8(command.workDir);
        }
        CommandLineParser::refreshBuildCfg(command);
        const uint64_t errorsBefore = Stats::getNumErrors();
        struct RestoreErrors
        {
            uint64_t saved;
            ~RestoreErrors() { Stats::get().numErrors.store(saved); }
        } restore{errorsBefore};
        CompilerInstance compiler(ctx.global(), command);
        TaskContext context(compiler);
        // These exercise the bootstrap's private host boundary, before application setup.
        Unittest::addTestSource(context, "Runtime", name, source, FileFlagsE::Runtime);
        Command::sema(compiler);
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;
        if (options.native)
        {
            NativeBackendBuilder builder(compiler, false);
            SWC_RESULT(builder.run());
            std::string output;
            const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 15000};
            uint32_t exitCode = 0;
            if (Os::runProcess(exitCode, builder.artifactPath, {}, artifacts.path, &options) != Os::ProcessRunResult::Ok || exitCode != 0)
            {
                std::println(stderr, "[runtime-test] {} exited with {}\n{}", name, exitCode, output);
                return Result::Error;
            }
        }
        return Stats::getNumErrors() == errorsBefore ? Result::Continue : Result::Error;
    }
}

SWC_FILESYSTEM_TEST_BEGIN(Runtime_CrossTargetContextFallbackUsesCompilerHost)
{
    static constexpr std::string_view SOURCE = R"(#global namespace Swag
#run
{
    let context = Swag.getContext()
    Swag.assert(__tlsGetPtr(context.runtimeTlsIdPlusOne - 1) == context)
}
)";
    return runLinuxRuntimeProbe(ctx, "CrossTargetContextFallback", SOURCE, {.targetOs = Runtime::TargetOs::Windows});
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Runtime_LinuxProcessStorageSharesCompilerAndNativeAnchor)
{
    constexpr uint32_t key = 0x43504353;
    auto* shared = static_cast<uint64_t*>(Os::processStorage(key, 64));
    if (!shared || Os::processStorage(key, 0) || Os::processStorage(key, 32))
        return Result::Error;
    shared[0] = 0x123456789abcdef0;
    static constexpr std::string_view SOURCE = R"(#global if #os == Swag.TargetOs.Linux
#run
{
    let shared = cast([*] u64, unwrap __hostProcessStorage(0x43504353, 64))
    Swag.assert(shared[0] == 0x123456789abcdef0'u64)
    shared[7] = 0xfedcba9876543210'u64
}
)";
    SWC_RESULT(runLinuxRuntimeProbe(ctx, "LinuxProcessStorageInterop", SOURCE));
    auto* second = static_cast<uint64_t*>(Os::processStorage(key, 64));
    return second && shared[7] == 0xfedcba9876543210 && second[0] == shared[0] && second[7] == shared[7] ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Runtime_LinuxHostedPrimitives)
{
    static constexpr std::string_view SOURCE = R"(#global if #os == Swag.TargetOs.Linux
#global private

#run
{
    Swag.assert(__LinuxRT.sinf(0'f32) == 0'f32)
    Swag.assert(__LinuxRT.cos(0'f64) == 1'f64)
    Swag.assert(__LinuxRT.pow(2'f64, 5'f64) == 32'f64)
    Swag.assert(__hostMonotonicFrequency() == 1_000_000_000)
    let before = __hostMonotonicTicks()
    __hostThreadSleep(1)
    Swag.assert(__hostMonotonicTicks() >= before)
    Swag.assert(__hostProcessorCount() >= 1)
    let pressure = __hostWorkPressure()
    Swag.assert(pressure.cpuValid)
    Swag.assert(pressure.memoryValid)
    Swag.assert(pressure.totalTicks >= pressure.idleTicks)
    Swag.assert(pressure.physicalBytes > 0)
    Swag.assert(pressure.availableBytes <= pressure.physicalBytes)
    Swag.assert(pressure.availableCommitBytes <= pressure.commitBytes)
    Swag.assert(__hostHasAvx2())
}
)";
    return runLinuxRuntimeProbe(ctx, "LinuxHostedPrimitives", SOURCE);
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Runtime_LinuxPageReservationsAndProcessStorage)
{
    static constexpr std::string_view SOURCE = R"(#global if #os == Swag.TargetOs.Linux
#global private

#run
{
    let size = 2 * AllocatorHostCommitGranularity
    let reservation = __hostPageReserve(size)
    Swag.assert(reservation != null)
    defer __hostPageRelease(reservation, size)
    let address = cast(u64, reservation)
    Swag.assert(__hostPageAllocationBase(address) == 0)
    Swag.assert(__hostPageCommit(reservation, AllocatorHostCommitGranularity))
    Swag.assert(__hostPageAllocationBase(address + size - 1) == address)
    Swag.assert(__hostPageAllocationBase(address + size) == 0)
    reservation[0] = 123
    __hostPageDecommit(reservation, AllocatorHostCommitGranularity)
    Swag.assert(__hostPageAllocationBase(address) == 0)
    Swag.assert(__hostPageCommit(reservation, AllocatorHostCommitGranularity))
    Swag.assert(reservation[0] == 0)

    let first = __hostProcessStorage(0x5453_5431, 8)
    let second = __hostProcessStorage(0x5453_5431, 8)
    Swag.assert(first != null and second != null)
    let value = cast(*u64, first)
    Swag.assert(value[] == 0)
    value[] = 0x1234_5678_9ABC_DEF0
    Swag.assert(cast(*u64, second)[] == value[])
    Swag.assert(__hostProcessStorage(0x5453_5431, 16) == null)
}
)";
    return runLinuxRuntimeProbe(ctx, "LinuxPageReservationsAndProcessStorage", SOURCE);
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Runtime_LinuxThreadStorageAndExitCleanup)
{
    static constexpr std::string_view SOURCE = R"(#global if #os == Swag.TargetOs.Linux
#global private

struct LinuxTlsState
{
    slot: u64
    cleanupCount: Swag.AtomicValue'u32
    correct: bool
}

#[Swag.CallingConvention(.C)]
func linuxTlsCleanup(value: *void?)
{
    if value do
        cast(*LinuxTlsState, value).cleanupCount.add(1)
}

#[Swag.CallingConvention(.C)]
func linuxTlsWorker(value: *void?)->u32
{
    let state = cast(*LinuxTlsState, unwrap value)
    state.correct = __hostThreadStorageGet(state.slot) == null and
                    __hostThreadStorageSet(state.slot, state) and
                    __hostThreadStorageGet(state.slot) == state
    return 0
}

#run
{
    let key = __hostTlsAlloc()
    Swag.assert(key != Swag.U64.Max)
    defer __hostTlsFree(key)
    var value = 42'u64
    Swag.assert(__hostTlsGet(key) == null)
    Swag.assert(__hostTlsSet(key, &value))
    Swag.assert(__hostTlsGet(key) == &value)
    Swag.assert(__hostTlsSet(key, null))
    Swag.assert(__hostTlsGet(key) == null)

    var state: LinuxTlsState
    state.slot = __hostThreadStorageAlloc(&linuxTlsCleanup)
    Swag.assert(state.slot != 0)
    defer __hostThreadStorageFree(state.slot)
    let thread = __hostThreadCreate(&linuxTlsWorker, &state)
    Swag.assert(thread != null)
    __hostThreadJoin(thread)
    Swag.assert(state.correct)
    Swag.assert(state.cleanupCount.load() == 1)
    Swag.assert(__hostThreadStorageGet(state.slot) == null)
}
)";
    return runLinuxRuntimeProbe(ctx, "LinuxThreadStorageAndExitCleanup", SOURCE);
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Runtime_LinuxUnixArgumentVector)
{
    static constexpr std::string_view SOURCE = R"(#global if #os == Swag.TargetOs.Linux
#global private

#run
{
    let values: [6] (const [*] u8) = ["program".buffer, "".buffer, "two words".buffer, "a\"b".buffer, "tail\\".buffer, "café".buffer]
    let initialized = __setUnixArguments(6, &values[0])
    Swag.assert(initialized)
    let actual = Swag.args()
    Swag.assert(actual.count == 6)
    Swag.assert(actual[0] == "program")
    Swag.assert(actual[1] == "")
    Swag.assert(actual[2] == "two words")
    Swag.assert(actual[3] == "a\"b")
    Swag.assert(actual[4] == "tail\\")
    Swag.assert(actual[5] == "café")
}
)";
    return runLinuxRuntimeProbe(ctx, "LinuxUnixArgumentVector", SOURCE);
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Runtime_LinuxNativeFaultRecovery)
{
    static constexpr std::string_view SOURCE = R"SWAG(#global if #os == Swag.TargetOs.Linux
#global private

var faultPage: *void?
var caughtFaults: u32
var forwardedSignals: u32
var signalMaskCorrect: bool

#[Swag.CallingConvention(.C)]
func priorSignalHandler(signal: s32)
{
    var mask: [16] u64
    discard __LinuxRT.sigprocmask(0, null, &mask)
    if signal == 7 do
        signalMaskCorrect = (mask[0] & (1'u64 << 9)) != 0
    discard Swag.atomicAdd(&forwardedSignals, 1)
}

#[Swag.CallingConvention(.C)]
func signalWorker(parameter: *void?)->u32
{
    discard parameter
    discard __LinuxRT.raise(7)
    return 0
}

#[Swag.NoInline, Swag.Safety(.ValueBorrow, false)]
func writeProtectedPage()
{
    cast(*u64, unwrap faultPage)[] = 42
}

#[Swag.NoInline, Swag.Optimize(false), Swag.Safety(.All, false)]
func exhaustStack(depth: *u32)->u64
{
    var frame: [1024] u64
    frame[0] = depth[]
    depth[] += 1
    if depth[] < 100000 do
        return exhaustStack(depth) + frame[0]
    return 0
}

func testFaultBody()
{
    Swag.assert(__LinuxRT.raise(7) == 0)
    Swag.assert(__LinuxRT.raise(4) == 0)
    let thread = __hostThreadCreate(&signalWorker, null)
    Swag.assert(thread != null)
    __hostThreadJoin(thread)
    for 2
    {
        let caught = Swag.catchPanic(func() { writeProtectedPage() })
        Swag.assert(caught.raised)
        Swag.assert(caught.message() == "memory access violation")
        caughtFaults += 1
    }
    var depth = 0'u32
    let overflow = Swag.catchPanic(func|&depth|() { discard exhaustStack(&depth) })
    Swag.assert(overflow.raised and depth > 0 and depth < 100000)
    let panic = Swag.catchPanic(func() { Swag.panic("ordinary panic", #curlocation) })
    Swag.assert(panic.raised and panic.message() == "ordinary panic")
}

var faultDrops: [16] Swag.AtomicValue'u32
var faultGeneration: u32
var switchFaultContext: bool
var faultContext: *Swag.Context?

struct FaultError { generation: u32 }
impl FaultError
{
    mtd opPostCopy() { .generation += 1 }
    mtd opDrop() { faultDrops[.generation].add(1) }
}

func failWithOwnedError() fail { fail FaultError{} }

#[Swag.Safety(.All, false)]
func uncaughtFaultBody()
{
    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    faultContext = previous
    var local: Swag.Context
    if switchFaultContext
    {
        local.allocator = previous.allocator
        local.defaultAllocator = previous.defaultAllocator
        local.runtimeFlags = previous.runtimeFlags
        local.panic = previous.panic
        Swag.setContext(local)
    }
    catch failWithOwnedError()
    {
        if Swag.err is FaultError as value do
            faultGeneration = value.generation
        writeProtectedPage()
    }
}

func verifyFaultCleanup()
{
    let context = Swag.getContext()
    Swag.assert(context == faultContext)
    Swag.assert(context.errorCaptures == null and context.errorIndex == 0)
    Swag.assert(context.hasError == 0 and context.curError == null)
    Swag.assert(faultDrops[faultGeneration].load() == 1)
    catch failWithOwnedError() { Swag.assert((Swag.err is FaultError)) }
}

#run
{
    #assert(#sizeof(__LinuxRT.SignalAction) == 152)
    #assert(#sizeof(__LinuxRT.SignalStack) == 24)
    faultPage = __LinuxRT.mmap(null, 4096, 0, __LinuxRT.MapPrivateAnonymous, -1, 0)
    Swag.assert(cast(s64, faultPage) != -1)
    var before, after: __LinuxRT.SignalAction
    var stackBefore, stackAfter: __LinuxRT.SignalStack
    Swag.assert(__LinuxRT.sigaction(11, null, &before) == 0)
    Swag.assert(__LinuxRT.sigaltstack(null, &stackBefore) == 0)
    var busBefore, illegalBefore: __LinuxRT.SignalAction
    var observer: __LinuxRT.SignalAction
    observer.handler = cast(*void, &priorSignalHandler)
    observer.mask[0] = 1'u64 << 9 // SIGUSR1 is blocked while the previous handler runs.
    Swag.assert(__LinuxRT.sigaction(7, &observer, &busBefore) == 0)
    observer.flags = 0x80000000 // SA_RESETHAND must stay consumed after restoration.
    Swag.assert(__LinuxRT.sigaction(4, &observer, &illegalBefore) == 0)
    var maskBefore, maskAfter: [16] u64
    Swag.assert(__LinuxRT.sigprocmask(0, null, &maskBefore) == 0)
    Swag.g_TestThreadId = __hostCurrentThreadId()
    let previous = __hostTestInstallHardwareFilter()
    Swag.g_TestRunning = true
    __hostTestCall(cast(*void, &testFaultBody))
    Swag.g_TestRunning = false
    __hostTestRestoreHardwareFilter(previous)
    Swag.assert(caughtFaults == 2 and forwardedSignals == 3 and signalMaskCorrect)
    Swag.assert(__LinuxRT.sigprocmask(0, null, &maskAfter) == 0)
    Swag.assert(maskBefore[0] == maskAfter[0])
    var illegalAfter: __LinuxRT.SignalAction
    Swag.assert(__LinuxRT.sigaction(4, null, &illegalAfter) == 0)
    Swag.assert(illegalAfter.handler == null)
    Swag.assert(__LinuxRT.sigaction(4, &illegalBefore, null) == 0)
    Swag.assert(__LinuxRT.sigaction(7, &busBefore, null) == 0)
    Swag.assert(__LinuxRT.sigaction(11, null, &after) == 0)
    Swag.assert(__LinuxRT.sigaltstack(null, &stackAfter) == 0)
    // glibc adds its private SA_RESTORER when reinstalling an initially default action.
    Swag.assert(before.handler == after.handler and (before.flags & 0xFBFFFFFF) == (after.flags & 0xFBFFFFFF))
    Swag.assert(before.mask[0] == after.mask[0])
    Swag.assert(stackBefore.address == stackAfter.address and stackBefore.flags == stackAfter.flags and stackBefore.size == stackAfter.size)
    let previousArguments = Swag.processInfo().arguments
    let arguments = ["swag.test"]
    Swag.processInfo().arguments = arguments
    let previousFailures = Swag.g_TestsFailedCnt
    let previousExecuted = Swag.g_TestsExecuted
    for useLocal in [false, true]
    {
        for &count in faultDrops do count.store(0)
        switchFaultContext = useLocal
        Swag.__runTest(cast(*void, &uncaughtFaultBody), "fault".buffer, "probe".buffer, "".buffer)
        Swag.__runTest(cast(*void, &verifyFaultCleanup), "cleanup".buffer, "probe".buffer, "".buffer)
    }
    Swag.processInfo().arguments = previousArguments
    Swag.assert(Swag.g_TestsFailedCnt == previousFailures + 2)
    Swag.assert(Swag.g_TestsExecuted == previousExecuted + 4)
    Swag.assert(__LinuxRT.munmap(faultPage, 4096) == 0)
}
)SWAG";
    SWC_RESULT(runLinuxRuntimeProbe(ctx, "LinuxNativeFaultRecovery", SOURCE));
    std::string nativeSource(SOURCE);
    const size_t entry = nativeSource.find("#run\n");
    SWC_ASSERT(entry != std::string::npos);
    nativeSource.replace(entry, 4, "#main");
    return runLinuxRuntimeProbe(ctx, "LinuxElfFaultRecovery", nativeSource, {.native = true});
}
SWC_TEST_END()

SWC_END_NAMESPACE();
#endif
