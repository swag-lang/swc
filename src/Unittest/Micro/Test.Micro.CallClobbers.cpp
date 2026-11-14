#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.RegisterAllocation.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint64_t clobberBit(const MicroReg reg)
    {
        return 1ull << MicroPassHelpers::MicroPhysLiveness::bitOf(reg);
    }

    SymbolFunction* makeCallee(TaskContext& ctx)
    {
        auto* function = Symbol::make<SymbolFunction>(ctx, nullptr, TokenRef::invalid(), ctx.idMgr().addIdentifier("clobbersCallee"), SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted);
        function->setReturnTypeRef(ctx.typeMgr().typeVoid());
        function->setTypeRef(ctx.typeMgr().addType(TypeInfo::makeFunction(function)));
        return function;
    }

    const MicroInstr& lastInstruction(const MicroBuilder& builder)
    {
        return *builder.instructions().ptr(builder.instructions().lastInstructionRef());
    }
}

SWC_TEST_BEGIN(CallClobbers_RegisterOnlyCallsRespectBothArgumentBanks)
{
    const CallConv& conv = CallConv::swag();
    for (uint32_t integers = 0; integers <= conv.intArgRegs.size() + 1; ++integers)
    {
        for (uint32_t floats = 0; floats <= conv.floatArgRegs.size() + 1; ++floats)
        {
            for (const bool floatsFirst : {false, true})
            {
                SymbolFunction* function = makeCallee(ctx);
                for (uint32_t index = 0; index < integers + floats; ++index)
                {
                    const bool isFloat   = floatsFirst ? index < floats : index >= integers;
                    auto*      parameter = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
                    parameter->setTypeRef(isFloat ? ctx.typeMgr().typeF64() : ctx.typeMgr().typeU64());
                    function->addParameter(parameter);
                }

                MicroBuilder builder(ctx);
                builder.emitCallLocal(function, CallConvKind::Swag, 0, 0);
                const MicroInstrRef callRef  = builder.instructions().lastInstructionRef();
                const auto          calls    = MicroPassHelpers::collectRegisterOnlyCallRefs(builder);
                const bool          expected = integers <= conv.intArgRegs.size() && floats <= conv.floatArgRegs.size();
                if (calls.contains(callRef.get()) != expected || calls.size() != (expected ? 1u : 0u))
                    return Result::Error;
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

// A direct call writes the convention's whole transient set until its target's code proves
// less, and then exactly the registers the proof names.
SWC_TEST_BEGIN(CallClobbers_NarrowDirectCallDefs)
{
    const CallConv& conv = CallConv::swag();
    MicroBuilder    builder(ctx);
    builder.emitCallLocal(makeCallee(ctx), CallConvKind::Swag, 0, 0);
    const MicroInstr& call = lastInstruction(builder);

    const auto whole = call.collectUseDef(builder.operands(), nullptr).defs;
    if (whole.size() != conv.intTransientRegs.size() + conv.floatTransientRegs.size())
        return Result::Error;

    constexpr MicroReg rdx = MicroReg::intReg(3);
    call.setCallClobbers(builder.operands(), clobberBit(conv.intReturn) | clobberBit(rdx));
    const auto narrowed = call.collectUseDef(builder.operands(), nullptr).defs;
    if (narrowed.size() != 2 || narrowed[0] != conv.intReturn || narrowed[1] != rdx)
        return Result::Error;
}
SWC_TEST_END()

// A value live across a call that leaves the transient registers alone needs no callee-saved
// register, and so no save in the prologue.
SWC_TEST_BEGIN(CallClobbers_ValueCrossesNarrowedCallInTransientRegister)
{
    const CallConv& conv   = CallConv::swag();
    auto*           callee = makeCallee(ctx);
    for (const bool narrowed : {false, true})
    {
        constexpr MicroReg value = MicroReg::virtualIntReg(9000);
        MicroBuilder       builder(ctx);
        builder.setBackendBuildCfg({.optimLevel = Runtime::BuildCfgBackendOptimLevel::O2});
        builder.emitLoadRegImm(value, ApInt(42, 64), MicroOpBits::B64);
        const MicroInstrRef valueDef = builder.instructions().lastInstructionRef();
        builder.emitCallLocal(callee, CallConvKind::Swag, 0, 0);
        if (narrowed)
            lastInstruction(builder).setCallClobbers(builder.operands(), clobberBit(conv.intReturn) | clobberBit(conv.floatReturn));
        builder.emitLoadMemReg(conv.stackPointer, 32, value, MicroOpBits::B64);
        builder.emitRet();

        MicroRegisterAllocationPass pass;
        MicroPassContext            passCtx;
        passCtx.taskContext  = &ctx;
        passCtx.builder      = &builder;
        passCtx.instructions = &builder.instructions();
        passCtx.operands     = &builder.operands();
        passCtx.callConvKind = CallConvKind::Swag;
        SWC_RESULT(pass.run(passCtx));
        SWC_RESULT(Backend::Unittest::assertNoVirtualRegs(builder));

        const MicroReg assigned = builder.instructions().ptr(valueDef)->ops(builder.operands())[0].reg;
        if (!passCtx.intervalAllocated || conv.isIntPersistentReg(assigned) == narrowed)
            return Result::Error;
    }
}
SWC_TEST_END()

// The final code of a leaf names the transient registers it writes, plus both return registers;
// a nonvolatile one is saved and restored, so it is not a clobber. Code that still calls proves
// nothing about what its own callers lose.
SWC_TEST_BEGIN(CallClobbers_LeafCodeNamesWrittenTransientRegisters)
{
    const CallConv&    conv       = CallConv::swag();
    constexpr MicroReg transient  = MicroReg::intReg(9);
    const MicroReg     persistent = conv.intPersistentRegs.front();

    MicroBuilder leaf(ctx);
    leaf.emitLoadRegImm(transient, ApInt(1, 64), MicroOpBits::B64);
    leaf.emitLoadRegImm(persistent, ApInt(2, 64), MicroOpBits::B64);
    leaf.emitOpBinaryRegReg(transient, persistent, MicroOp::Add, MicroOpBits::B64);
    leaf.emitLoadRegReg(conv.intReturn, transient, MicroOpBits::B64);
    leaf.emitRet();

    MachineCode leafCode;
    SWC_RESULT(leafCode.emit(ctx, leaf));
    if (leafCode.callClobbers != (clobberBit(conv.intReturn) | clobberBit(conv.floatReturn) | clobberBit(transient)))
        return Result::Error;

    MicroBuilder caller(ctx);
    caller.emitLoadRegImm(transient, ApInt(1, 64), MicroOpBits::B64);
    caller.emitCallReg(transient, CallConvKind::Swag, 0, 0);
    caller.emitRet();

    MachineCode callerCode;
    SWC_RESULT(callerCode.emit(ctx, caller));
    if (callerCode.callClobbers != MicroInstr::K_CALL_CLOBBERS_ALL)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
