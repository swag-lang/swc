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

SWC_TEST_BEGIN(InductionVariable_ProductsKeepPriorityWhenCarrierIsRejected)
{
    // Without a product both sums can be carried. An accepted product takes
    // priority over sums before and after it, even if its delta is too wide.
    for (uint32_t mode = 0; mode < 3; ++mode)
    {
        constexpr MicroReg productInduction = MicroReg::virtualIntReg(1);
        constexpr MicroReg sumInduction     = MicroReg::virtualIntReg(2);
        constexpr MicroReg base             = MicroReg::virtualIntReg(3);
        constexpr MicroReg count            = MicroReg::virtualIntReg(4);
        constexpr MicroReg product          = MicroReg::virtualIntReg(5);
        constexpr MicroReg firstSum         = MicroReg::virtualIntReg(6);
        constexpr MicroReg lastSum          = MicroReg::virtualIntReg(7);
        constexpr MicroReg carrier          = MicroReg::virtualIntReg(8);
        const MicroReg     sp               = CallConv::get(CallConvKind::Swag).stackPointer;
        MicroBuilder       builder(ctx);
        const auto         header = builder.createLabel();
        builder.emitLoadRegImm(productInduction, ApInt(0, 64), MicroOpBits::B64);
        builder.emitLoadRegImm(sumInduction, ApInt(0, 64), MicroOpBits::B64);
        builder.emitLoadRegReg(base, MicroReg::intReg(2), MicroOpBits::B64);
        builder.emitLoadRegImm(count, ApInt(0, 64), MicroOpBits::B64);
        builder.placeLabel(header);
        builder.emitOpBinaryRegRegReg(firstSum, base, sumInduction, MicroOp::Add, MicroOpBits::B64);
        const auto firstSumRef = builder.instructions().lastInstructionRef();
        builder.emitLoadMemReg(sp, 0x40, firstSum, MicroOpBits::B64);
        MicroInstrRef productRef  = MicroInstrRef::invalid();
        MicroInstrRef multiplyRef = MicroInstrRef::invalid();
        if (mode != 0)
        {
            builder.emitLoadRegReg(product, productInduction, MicroOpBits::B64);
            productRef                = builder.instructions().lastInstructionRef();
            const uint64_t multiplier = mode == 1 ? 101 : 0x40000000;
            builder.emitOpBinaryRegImm(product, ApInt(multiplier, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
            multiplyRef = builder.instructions().lastInstructionRef();
            builder.emitLoadMemReg(sp, 0x48, product, MicroOpBits::B64);
        }
        builder.emitOpBinaryRegRegReg(lastSum, base, sumInduction, MicroOp::Add, MicroOpBits::B64);
        const auto lastSumRef = builder.instructions().lastInstructionRef();
        builder.emitLoadMemReg(sp, 0x50, lastSum, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(productInduction, ApInt(2, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(sumInduction, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        const auto sumStepRef = builder.instructions().lastInstructionRef();
        builder.emitOpBinaryRegImm(count, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(count, ApInt(4, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, header);
        builder.emitRet();
        const auto originalCount = builder.instructions().count();

        MicroPassContext passContext;
        passContext.builder      = &builder;
        passContext.instructions = &builder.instructions();
        passContext.operands     = &builder.operands();
        passContext.callConvKind = CallConvKind::Swag;
        MicroInductionVariablePass pass;
        SWC_RESULT(pass.run(passContext));
        for (const auto sumRef : {firstSumRef, lastSumRef})
        {
            const auto* sum = builder.instructions().ptr(sumRef);
            if (!sum)
                return Result::Error;
            if (mode == 0)
            {
                if (sum->op != MicroInstrOpcode::LoadRegReg || sum->ops(builder.operands())[1].reg != carrier)
                    return Result::Error;
            }
            else if (sum->op != MicroInstrOpcode::OpBinaryRegRegReg || sum->ops(builder.operands())[2].reg != sumInduction)
                return Result::Error;
        }
        if ((builder.instructions().ptr(sumStepRef) == nullptr) != (mode == 0) || passContext.passChanged != (mode != 2))
            return Result::Error;
        if (mode != 0)
        {
            const auto* copy = builder.instructions().ptr(productRef);
            if (!copy || copy->op != MicroInstrOpcode::LoadRegReg || copy->ops(builder.operands())[1].reg != (mode == 1 ? carrier : productInduction))
                return Result::Error;
            if ((builder.instructions().ptr(multiplyRef) == nullptr) != (mode == 1))
                return Result::Error;
        }
        if (mode == 2 && builder.instructions().count() != originalCount)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
