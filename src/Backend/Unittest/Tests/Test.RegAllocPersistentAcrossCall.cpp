#include "pch.h"
#include "Backend/Unittest/BackendUnittest.h"
#include "Backend/Unittest/BackendUnittestHelpers.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"
#include "Backend/MachineCode/Micro/Passes/MicroRegAllocPass.h"

SWC_BEGIN_NAMESPACE();

#if SWC_DEV_MODE

SWC_BACKEND_TEST_BEGIN(RegAllocPersistentAcrossCall)
    MicroInstrBuilder builder(ctx);
    const auto        vLive = MicroReg::virtualIntReg(0);
    const auto        vTemp = MicroReg::virtualIntReg(1);

    builder.encodeLoadRegImm(vLive, 0x11, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeLoadRegImm(vTemp, 0x22, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeOpBinaryRegImm(vTemp, 1, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeCallReg(MicroReg::intReg(0), CallConvKind::C, EncodeFlagsE::Zero);
    builder.encodeOpBinaryRegImm(vLive, 2, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);

    MicroRegAllocPass regAllocPass;
    MicroPassManager  passes;
    passes.add(regAllocPass);

    MicroPassContext passCtx;
    builder.runPasses(passes, nullptr, passCtx);

    Backend::Unittest::assertNoVirtualRegs(builder);

    const auto& conv = CallConv::get(CallConvKind::C);
    auto&       ops  = builder.operands().store();

    const MicroInstr* firstInst  = nullptr;
    const MicroInstr* secondInst = nullptr;
    for (const auto& inst : builder.instructions().view())
    {
        if (!firstInst)
        {
            firstInst = &inst;
            continue;
        }

        secondInst = &inst;
        break;
    }

    SWC_ASSERT(firstInst);
    SWC_ASSERT(secondInst);
    const auto* firstOps  = firstInst->ops(ops);
    const auto* secondOps = secondInst->ops(ops);
    SWC_ASSERT(firstOps && secondOps);

    const MicroReg regLive = firstOps[0].reg;
    const MicroReg regTemp = secondOps[0].reg;
    SWC_ASSERT(regLive.isInt());
    SWC_ASSERT(regTemp.isInt());
    SWC_ASSERT(Backend::Unittest::isPersistentReg(conv.intPersistentRegs, regLive));
    SWC_ASSERT(!Backend::Unittest::isPersistentReg(conv.intPersistentRegs, regTemp));
SWC_BACKEND_TEST_END()

#endif

SWC_END_NAMESPACE();
