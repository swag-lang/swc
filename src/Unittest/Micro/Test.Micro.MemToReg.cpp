#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.MemToReg.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runMemToRegPass(MicroBuilder& builder)
    {
        MicroMemToRegPass pass;
        MicroPassManager  passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    uint32_t countOpcode(const MicroBuilder& builder, const MicroInstrOpcode opcode)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                ++count;
        }

        return count;
    }
}

// A frame slot only ever reached as the constant-offset base of scalar
// accesses promotes to a virtual register: the immediate store becomes a
// register immediate, the load becomes a copy.
SWC_TEST_BEGIN(MemToReg_PlainSlot_Promotes)
{
    const MicroReg     sp   = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg vFb  = MicroReg::virtualIntReg(1);
    constexpr MicroReg vVal = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadAddressRegMem(vFb, sp, 0, MicroOpBits::B64);
    builder.emitLoadMemImm(vFb, 0x10, ApInt(42, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(vVal, vFb, 0x10, MicroOpBits::B64);
    builder.emitCmpRegImm(vVal, ApInt(0, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runMemToRegPass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadMemImm) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// F-028: an address register minted by `lea ar, [fb + off]` and then redefined
// by plain arithmetic no longer points at its recorded offset, so nothing may
// resolve through it. Without local-variable extents (none here) the whole
// function must bail: every access stays a memory access, in particular the
// unrelated slot at fb+0x30 whose promotion would otherwise swallow the store
// that goes through the moved pointer. The pass disqualifies the register in
// its collection pass, upstream of the extent information, so the same holds
// when extents allow per-variable poisoning.
SWC_TEST_BEGIN(MemToReg_RedefinedAddressRegister_BailsFunction)
{
    const MicroReg     sp   = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg vFb  = MicroReg::virtualIntReg(1);
    constexpr MicroReg vAr  = MicroReg::virtualIntReg(2);
    constexpr MicroReg vIdx = MicroReg::virtualIntReg(3);
    constexpr MicroReg vVal = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadAddressRegMem(vFb, sp, 0, MicroOpBits::B64);
    builder.emitLoadAddressRegMem(vAr, vFb, 0x10, MicroOpBits::B64);
    builder.emitLoadMemImm(vAr, 0, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(vIdx, ApInt(8, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(vAr, vIdx, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemImm(vAr, 0x20, ApInt(9, 64), MicroOpBits::B64);
    builder.emitLoadMemImm(vFb, 0x30, ApInt(1, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(vVal, vFb, 0x30, MicroOpBits::B64);
    builder.emitCmpRegImm(vVal, ApInt(0, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runMemToRegPass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadMemImm) != 3)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
