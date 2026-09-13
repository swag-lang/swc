#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.SinkToUse.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runSinkToUsePass(MicroBuilder& builder)
    {
        MicroSinkToUsePass pass;
        MicroPassManager   passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }
}

SWC_TEST_BEGIN(SinkToUse_MovesDefinitionToItsConsumer)
{
    constexpr MicroReg value  = MicroReg::virtualIntReg(1);
    constexpr MicroReg other  = MicroReg::virtualIntReg(2);
    constexpr MicroReg result = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(value, ApInt(7, 64), MicroOpBits::B64);
    const auto original = builder.instructions().lastInstructionRef();
    builder.emitLoadRegImm(other, ApInt(2, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(other, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegReg(result, value, MicroOpBits::B64);
    const auto consumer = builder.instructions().lastInstructionRef();
    builder.emitRet();

    SWC_RESULT(runSinkToUsePass(builder));
    if (builder.instructions().ptr(original))
        return Result::Error;
    const auto  precedingRef = builder.instructions().findPreviousInstructionRef(consumer);
    const auto* preceding    = builder.instructions().ptr(precedingRef);
    if (!preceding || preceding->op != MicroInstrOpcode::LoadRegImm || preceding->ops(builder.operands())[0].reg != value)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SinkToUse_LoadCannotCrossBaseRedefinition)
{
    constexpr MicroReg base   = MicroReg::virtualIntReg(1);
    constexpr MicroReg value  = MicroReg::virtualIntReg(2);
    constexpr MicroReg result = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(4096, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(value, base, 0, MicroOpBits::B64);
    const auto load = builder.instructions().lastInstructionRef();
    builder.emitLoadRegImm(base, ApInt(8192, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(result, value, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runSinkToUsePass(builder));
    if (!builder.instructions().ptr(load))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SinkToUse_LoadCannotCrossMemoryWrite)
{
    constexpr MicroReg base   = MicroReg::virtualIntReg(1);
    constexpr MicroReg value  = MicroReg::virtualIntReg(2);
    constexpr MicroReg result = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(base, ApInt(4096, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(value, base, 0, MicroOpBits::B64);
    const auto load = builder.instructions().lastInstructionRef();
    builder.emitLoadMemReg(base, 0, base, MicroOpBits::B64);
    builder.emitLoadRegReg(result, value, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runSinkToUsePass(builder));
    if (!builder.instructions().ptr(load))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
