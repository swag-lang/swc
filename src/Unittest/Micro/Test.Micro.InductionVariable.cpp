#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.InductionVariable.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(InductionVariable_CountsDefinitionsAndUsesForCarriedSums)
{
    for (const bool adjacentCopy : {false, true})
    {
        // A single definition/use is eligible; an extra definition or use is not.
        for (uint32_t extra = 0; extra < 3; ++extra)
        {
            constexpr MicroReg induction = MicroReg::virtualIntReg(1);
            constexpr MicroReg base      = MicroReg::virtualIntReg(2);
            constexpr MicroReg count     = MicroReg::virtualIntReg(3);
            constexpr MicroReg copy      = MicroReg::virtualIntReg(4);
            constexpr MicroReg address   = MicroReg::virtualIntReg(5);
            const MicroReg     sp        = CallConv::get(CallConvKind::Swag).stackPointer;
            MicroBuilder       builder(ctx);
            const auto         header = builder.createLabel();
            builder.emitLoadRegImm(induction, ApInt(0, 64), MicroOpBits::B64);
            builder.emitLoadRegReg(base, MicroReg::intReg(2), MicroOpBits::B64);
            builder.emitLoadRegImm(count, ApInt(0, 64), MicroOpBits::B64);
            builder.placeLabel(header);
            MicroInstrRef copyRef = MicroInstrRef::invalid();
            if (adjacentCopy)
            {
                builder.emitLoadRegReg(copy, induction, MicroOpBits::B64);
                copyRef = builder.instructions().lastInstructionRef();
            }
            builder.emitOpBinaryRegRegReg(address, base, adjacentCopy ? copy : induction, MicroOp::Add, MicroOpBits::B64);
            const auto sumRef = builder.instructions().lastInstructionRef();
            builder.emitLoadMemReg(sp, 0x40, address, MicroOpBits::B64);
            if (extra == 2)
                builder.emitLoadMemReg(sp, 0x48, adjacentCopy ? copy : induction, MicroOpBits::B64);
            if (extra == 1)
                builder.emitLoadRegImm(adjacentCopy ? copy : induction, ApInt(9, 64), MicroOpBits::B64);
            builder.emitOpBinaryRegImm(induction, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
            const auto stepRef = builder.instructions().lastInstructionRef();
            builder.emitOpBinaryRegImm(count, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
            builder.emitCmpRegImm(count, ApInt(4, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, header);
            builder.emitRet();

            MicroPassContext passContext;
            passContext.builder      = &builder;
            passContext.instructions = &builder.instructions();
            passContext.operands     = &builder.operands();
            passContext.callConvKind = CallConvKind::Swag;
            MicroInductionVariablePass pass;
            SWC_RESULT(pass.run(passContext));
            const auto* sum = builder.instructions().ptr(sumRef);
            if (extra == 0)
            {
                if (!sum || sum->op != MicroInstrOpcode::LoadRegReg ||
                    sum->ops(builder.operands())[1].reg != MicroReg::virtualIntReg(6) || builder.instructions().ptr(stepRef))
                    return Result::Error;
                if (adjacentCopy && builder.instructions().ptr(copyRef))
                    return Result::Error;
            }
            else if (!sum || sum->op != MicroInstrOpcode::OpBinaryRegRegReg || !builder.instructions().ptr(stepRef))
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
