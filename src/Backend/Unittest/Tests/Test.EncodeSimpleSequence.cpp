#include "pch.h"
#include "Backend/Unittest/BackendUnittest.h"
#include "Backend/Unittest/BackendUnittestHelpers.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

#if SWC_DEV_MODE

SWC_BACKEND_TEST(EncodeSimpleSequence)
{
    MicroInstrBuilder builder(ctx);

    builder.encodeLoadRegImm(MicroReg::intReg(0), 0x1234, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeOpBinaryRegReg(MicroReg::intReg(0), MicroReg::intReg(1), MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeRet(EncodeFlagsE::Zero);

    Backend::Unittest::TestX64Encoder encoder(ctx);
    MicroEncodePass encodePass;
    MicroPassManager passes;
    passes.add(encodePass);

    MicroPassContext passCtx;
    builder.runPasses(passes, &encoder, passCtx);

    SWC_ASSERT(encoder.size() > 0);
    SWC_ASSERT(encoder.data());
}

#endif

SWC_END_NAMESPACE();
