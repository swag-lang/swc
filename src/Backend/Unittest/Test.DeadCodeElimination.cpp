#include "pch.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPass.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    Result runDeadCodeEliminationPass(MicroBuilder& builder)
    {
        MicroDeadCodeEliminationPass pass;
        MicroPassManager             passManager;
        passManager.add(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    const MicroInstr* instructionAt(const MicroBuilder& builder, uint32_t index)
    {
        uint32_t currentIndex = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (currentIndex == index)
                return &inst;
            ++currentIndex;
        }

        return nullptr;
    }
}

SWC_TEST_BEGIN(MicroDeadCodeElimination_RemovesDeadDefinitions)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg r8 = MicroReg::intReg(8);

    builder.emitLoadRegImm(r8, ApInt(1, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(r8, ApInt(2, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runDeadCodeEliminationPass(builder));

    if (builder.instructions().count() != 1)
        return Result::Error;

    const MicroInstr* inst0 = instructionAt(builder, 0);
    if (!inst0 || inst0->op != MicroInstrOpcode::Ret)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroDeadCodeElimination_PreservesReturnRegisterDefinition)
{
    MicroBuilder    builder(ctx);
    const CallConv& conv = CallConv::get(CallConvKind::Host);

    builder.emitLoadRegImm(conv.intReturn, ApInt(99, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runDeadCodeEliminationPass(builder));

    if (builder.instructions().count() != 2)
        return Result::Error;

    const MicroInstr* inst0 = instructionAt(builder, 0);
    const MicroInstr* inst1 = instructionAt(builder, 1);
    if (!inst0 || !inst1)
        return Result::Error;

    if (inst0->op != MicroInstrOpcode::LoadRegImm || inst1->op != MicroInstrOpcode::Ret)
        return Result::Error;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
