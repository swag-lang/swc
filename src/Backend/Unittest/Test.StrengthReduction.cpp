#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPass.h"
#include "Backend/Micro/Passes/Pass.StrengthReduction.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    void runStrengthReductionPass(MicroBuilder& builder)
    {
        MicroStrengthReductionPass pass;
        MicroPassManager           passManager;
        passManager.add(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        builder.runPasses(passManager, nullptr, passContext);
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

SWC_TEST_BEGIN(MicroStrengthReduction_RewritesPowerOfTwoOps)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg reg = MicroReg::intReg(8);

    builder.emitOpBinaryRegImm(reg, ApInt(8, 64), MicroOp::MultiplyUnsigned, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(reg, ApInt(4, 64), MicroOp::DivideUnsigned, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(reg, ApInt(16, 64), MicroOp::ModuloUnsigned, MicroOpBits::B64);

    runStrengthReductionPass(builder);

    if (builder.instructions().count() != 3)
        return Result::Error;

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          instMul  = instructionAt(builder, 0);
    const MicroInstr*          instDiv  = instructionAt(builder, 1);
    const MicroInstr*          instMod  = instructionAt(builder, 2);
    if (!instMul || !instDiv || !instMod)
        return Result::Error;

    const MicroInstrOperand* opsMul = instMul->ops(operands);
    if (instMul->op != MicroInstrOpcode::OpBinaryRegImm || opsMul[2].microOp != MicroOp::ShiftLeft || opsMul[3].valueU64 != 3)
        return Result::Error;

    const MicroInstrOperand* opsDiv = instDiv->ops(operands);
    if (instDiv->op != MicroInstrOpcode::OpBinaryRegImm || opsDiv[2].microOp != MicroOp::ShiftRight || opsDiv[3].valueU64 != 2)
        return Result::Error;

    const MicroInstrOperand* opsMod = instMod->ops(operands);
    if (instMod->op != MicroInstrOpcode::OpBinaryRegImm || opsMod[2].microOp != MicroOp::And || opsMod[3].valueU64 != 15)
        return Result::Error;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
