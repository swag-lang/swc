#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.FrameCompact.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // The register the code generator names for its locals, as MachineCode::emit passes it.
    constexpr MicroReg K_FRAME = MicroReg::virtualIntReg(1);

    struct FrameLocal
    {
        SymbolVariable symbol{nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero};
        uint32_t       offset = 0;
        uint32_t       size   = 0;
    };

    // A lowered function whose locals sit at the given offsets in a frame of 'frameSize' bytes.
    void declareLocals(TaskContext& ctx, SymbolFunction& function, std::span<FrameLocal> locals, uint32_t frameSize)
    {
        for (FrameLocal& local : locals)
        {
            local.symbol.setTypeRef(ctx.typeMgr().typeU64());
            local.symbol.addExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
            local.symbol.setCodeGenLocalSize(local.size);
            function.addLocalVariable(ctx, &local.symbol);
            local.symbol.setOffset(local.offset);
        }
        function.setDebugStackFrameSize(frameSize);
    }

    Result runFrameCompactPass(MicroBuilder& builder, const SymbolFunction& function)
    {
        MicroFrameCompactPass pass;
        MicroPassManager      passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind             = CallConvKind::Swag;
        passContext.sanitizerFunction        = &function;
        passContext.debugStackBaseVirtualReg = K_FRAME;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    // The displacement of a memory-form instruction, or the immediate of a stack adjustment.
    uint64_t displacementOf(MicroBuilder& builder, const MicroInstrRef ref)
    {
        const MicroInstr&    inst  = *builder.instructions().ptr(ref);
        const MicroInstrDef& info  = MicroInstr::info(inst.op);
        const uint8_t        index = inst.op == MicroInstrOpcode::OpBinaryRegImm ? 3 : info.memOffsetOperandIndex;
        return inst.ops(builder.operands())[index].valueU64;
    }

    MicroInstrRef emitFrameEntry(MicroBuilder& builder, const uint64_t frameSize)
    {
        const MicroReg sp = CallConv::get(CallConvKind::Swag).stackPointer;
        builder.emitOpBinaryRegImm(sp, ApInt(frameSize, 64), MicroOp::Subtract, MicroOpBits::B64);
        const MicroInstrRef entryRef = builder.instructions().lastInstructionRef();
        builder.emitLoadAddressRegMem(K_FRAME, sp, 0, MicroOpBits::B64);
        return entryRef;
    }

    MicroInstrRef emitFrameExit(MicroBuilder& builder, const uint64_t frameSize)
    {
        const MicroReg sp = CallConv::get(CallConvKind::Swag).stackPointer;
        builder.emitOpBinaryRegImm(sp, ApInt(frameSize, 64), MicroOp::Add, MicroOpBits::B64);
        const MicroInstrRef releaseRef = builder.instructions().lastInstructionRef();
        builder.emitRet();
        return releaseRef;
    }
}

// A local nothing reaches any more leaves the frame: the locals behind it move down,
// every displacement follows, and the entry subtract and release shrink together.
SWC_TEST_BEGIN(FrameCompact_DeadObjectsRemoved)
{
    SymbolFunction            function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    std::array<FrameLocal, 3> locals = {FrameLocal{.offset = 0x0, .size = 8}, FrameLocal{.offset = 0x10, .size = 16}, FrameLocal{.offset = 0x20, .size = 8}};
    declareLocals(ctx, function, locals, 0x30);

    constexpr MicroReg address = MicroReg::virtualIntReg(2);
    constexpr MicroReg value   = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);
    const MicroInstrRef entryRef = emitFrameEntry(builder, 0x30);
    builder.emitLoadAddressRegMem(address, K_FRAME, 0x0, MicroOpBits::B64);
    const MicroInstrRef addressRef = builder.instructions().lastInstructionRef();
    builder.emitCmpRegImm(address, ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadMemImm(K_FRAME, 0x20, ApInt(7, 64), MicroOpBits::B64);
    const MicroInstrRef storeRef = builder.instructions().lastInstructionRef();
    builder.emitLoadRegMem(value, K_FRAME, 0x20, MicroOpBits::B64);
    const MicroInstrRef loadRef    = builder.instructions().lastInstructionRef();
    const MicroInstrRef releaseRef = emitFrameExit(builder, 0x30);

    SWC_RESULT(runFrameCompactPass(builder, function));
    if (displacementOf(builder, entryRef) != 0x10 || displacementOf(builder, releaseRef) != 0x10)
        return Result::Error;
    if (displacementOf(builder, addressRef) != 0x0)
        return Result::Error;
    if (displacementOf(builder, storeRef) != 0x8 || displacementOf(builder, loadRef) != 0x8)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A packed access covering two locals cannot be mapped to one object: the frame stays as lowered.
SWC_TEST_BEGIN(FrameCompact_StraddlingAccessKeepsFrame)
{
    SymbolFunction            function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    std::array<FrameLocal, 3> locals = {FrameLocal{.offset = 0x0, .size = 8}, FrameLocal{.offset = 0x8, .size = 8}, FrameLocal{.offset = 0x10, .size = 8}};
    declareLocals(ctx, function, locals, 0x20);

    constexpr MicroReg vector = MicroReg::virtualFloatReg(1);
    MicroBuilder       builder(ctx);
    const MicroInstrRef entryRef = emitFrameEntry(builder, 0x20);
    builder.emitLoadMemReg(K_FRAME, 0x0, vector, MicroOpBits::B128);
    const MicroInstrRef releaseRef = emitFrameExit(builder, 0x20);

    SWC_RESULT(runFrameCompactPass(builder, function));
    if (displacementOf(builder, entryRef) != 0x20 || displacementOf(builder, releaseRef) != 0x20)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Outgoing argument slots below the frame keep their stack-pointer displacement; a local
// read through the moved stack pointer follows its object.
SWC_TEST_BEGIN(FrameCompact_CallAreaBelowFrameStays)
{
    SymbolFunction            function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    std::array<FrameLocal, 2> locals = {FrameLocal{.offset = 0x0, .size = 8}, FrameLocal{.offset = 0x10, .size = 8}};
    declareLocals(ctx, function, locals, 0x20);

    const MicroReg     sp    = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg value = MicroReg::virtualIntReg(2);
    constexpr MicroReg other = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);
    const MicroInstrRef entryRef = emitFrameEntry(builder, 0x20);
    builder.emitLoadRegImm(value, ApInt(1, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(sp, ApInt(0x20, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitLoadMemReg(sp, 0x8, value, MicroOpBits::B64);
    const MicroInstrRef argumentRef = builder.instructions().lastInstructionRef();
    builder.emitLoadRegMem(other, sp, 0x30, MicroOpBits::B64);
    const MicroInstrRef localRef = builder.instructions().lastInstructionRef();
    builder.emitOpBinaryRegImm(sp, ApInt(0x20, 64), MicroOp::Add, MicroOpBits::B64);
    const MicroInstrRef releaseRef = emitFrameExit(builder, 0x20);

    SWC_RESULT(runFrameCompactPass(builder, function));
    if (displacementOf(builder, entryRef) != 0x10 || displacementOf(builder, releaseRef) != 0x10)
        return Result::Error;
    if (displacementOf(builder, argumentRef) != 0x8)
        return Result::Error;
    if (displacementOf(builder, localRef) != 0x20)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// An incoming stack argument sits above the locals: its displacement from the base
// follows the frame size.
SWC_TEST_BEGIN(FrameCompact_IncomingArgumentFollowsFrameSize)
{
    SymbolFunction            function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    std::array<FrameLocal, 2> locals = {FrameLocal{.offset = 0x0, .size = 8}, FrameLocal{.offset = 0x10, .size = 8}};
    declareLocals(ctx, function, locals, 0x20);

    constexpr MicroReg value    = MicroReg::virtualIntReg(2);
    constexpr MicroReg argument = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);
    const MicroInstrRef entryRef = emitFrameEntry(builder, 0x20);
    builder.emitLoadRegMem(argument, K_FRAME, 0x28, MicroOpBits::B64);
    const MicroInstrRef argumentRef = builder.instructions().lastInstructionRef();
    builder.emitLoadMemReg(K_FRAME, 0x10, argument, MicroOpBits::B64);
    const MicroInstrRef storeRef = builder.instructions().lastInstructionRef();
    builder.emitLoadRegMem(value, K_FRAME, 0x10, MicroOpBits::B64);
    const MicroInstrRef releaseRef = emitFrameExit(builder, 0x20);

    SWC_RESULT(runFrameCompactPass(builder, function));
    if (displacementOf(builder, entryRef) != 0x10 || displacementOf(builder, releaseRef) != 0x10)
        return Result::Error;
    if (displacementOf(builder, argumentRef) != 0x18)
        return Result::Error;
    if (displacementOf(builder, storeRef) != 0x0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A frame address redefined by register arithmetic no longer names an object: nothing moves.
SWC_TEST_BEGIN(FrameCompact_AddressArithmeticKeepsFrame)
{
    SymbolFunction            function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    std::array<FrameLocal, 2> locals = {FrameLocal{.offset = 0x0, .size = 8}, FrameLocal{.offset = 0x10, .size = 8}};
    declareLocals(ctx, function, locals, 0x20);

    constexpr MicroReg address = MicroReg::virtualIntReg(2);
    constexpr MicroReg index   = MicroReg::virtualIntReg(3);
    constexpr MicroReg value   = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);
    const MicroInstrRef entryRef = emitFrameEntry(builder, 0x20);
    builder.emitLoadAddressRegMem(address, K_FRAME, 0x10, MicroOpBits::B64);
    builder.emitLoadRegImm(index, ApInt(8, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(address, index, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegMem(value, address, 0x0, MicroOpBits::B64);
    const MicroInstrRef releaseRef = emitFrameExit(builder, 0x20);

    SWC_RESULT(runFrameCompactPass(builder, function));
    if (displacementOf(builder, entryRef) != 0x20 || displacementOf(builder, releaseRef) != 0x20)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A frame address passed as a plain copy of the base pins the first object; the dead
// local behind it still leaves and the later one moves down.
SWC_TEST_BEGIN(FrameCompact_BaseCopyPinsFirstObject)
{
    SymbolFunction            function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    std::array<FrameLocal, 3> locals = {FrameLocal{.offset = 0x0, .size = 8}, FrameLocal{.offset = 0x8, .size = 8}, FrameLocal{.offset = 0x10, .size = 8}};
    declareLocals(ctx, function, locals, 0x20);

    constexpr MicroReg address = MicroReg::virtualIntReg(2);
    constexpr MicroReg value   = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);
    const MicroInstrRef entryRef = emitFrameEntry(builder, 0x20);
    builder.emitLoadRegReg(address, K_FRAME, MicroOpBits::B64);
    builder.emitCmpRegImm(address, ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(value, K_FRAME, 0x10, MicroOpBits::B64);
    const MicroInstrRef loadRef    = builder.instructions().lastInstructionRef();
    const MicroInstrRef releaseRef = emitFrameExit(builder, 0x20);

    SWC_RESULT(runFrameCompactPass(builder, function));
    if (displacementOf(builder, entryRef) != 0x10 || displacementOf(builder, releaseRef) != 0x10)
        return Result::Error;
    if (displacementOf(builder, loadRef) != 0x8)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// An address formed at the start of a local may be the end of the local before it. When
// that one survives, nothing moves; when it is dead, the address follows its local.
SWC_TEST_BEGIN(FrameCompact_BoundaryAddressFollowsLivePredecessor)
{
    for (uint32_t variant = 0; variant < 2; ++variant)
    {
        const bool                predecessorLive = variant == 0;
        SymbolFunction            function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        std::array<FrameLocal, 3> locals = {FrameLocal{.offset = 0x0, .size = 8}, FrameLocal{.offset = 0x8, .size = 8}, FrameLocal{.offset = 0x10, .size = 8}};
        declareLocals(ctx, function, locals, 0x20);

        constexpr MicroReg address = MicroReg::virtualIntReg(2);
        constexpr MicroReg value   = MicroReg::virtualIntReg(3);
        MicroBuilder       builder(ctx);
        const MicroInstrRef entryRef = emitFrameEntry(builder, 0x20);
        if (predecessorLive)
            builder.emitLoadMemImm(K_FRAME, 0x0, ApInt(1, 64), MicroOpBits::B64);
        builder.emitLoadAddressRegMem(address, K_FRAME, 0x8, MicroOpBits::B64);
        const MicroInstrRef addressRef = builder.instructions().lastInstructionRef();
        builder.emitCmpRegImm(address, ApInt(0, 64), MicroOpBits::B64);
        builder.emitLoadRegMem(value, K_FRAME, 0x8, MicroOpBits::B64);
        const MicroInstrRef releaseRef = emitFrameExit(builder, 0x20);

        SWC_RESULT(runFrameCompactPass(builder, function));
        const uint64_t expectedFrame   = predecessorLive ? 0x20 : 0x10;
        const uint64_t expectedAddress = predecessorLive ? 0x8 : 0x0;
        if (displacementOf(builder, entryRef) != expectedFrame || displacementOf(builder, releaseRef) != expectedFrame)
            return Result::Error;
        if (displacementOf(builder, addressRef) != expectedAddress)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
