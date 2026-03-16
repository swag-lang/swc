#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenCompareHelpers
{
    inline MicroCond lessCond(bool useUnsignedCond)
    {
        return useUnsignedCond ? MicroCond::Below : MicroCond::Less;
    }

    inline MicroCond lessEqualCond(bool useUnsignedCond)
    {
        return useUnsignedCond ? MicroCond::BelowOrEqual : MicroCond::LessOrEqual;
    }

    inline MicroCond greaterCond(bool useUnsignedCond)
    {
        return useUnsignedCond ? MicroCond::Above : MicroCond::Greater;
    }

    inline MicroCond greaterEqualCond(bool useUnsignedCond)
    {
        return useUnsignedCond ? MicroCond::AboveOrEqual : MicroCond::GreaterOrEqual;
    }

    enum class FloatUnorderedMode : uint8_t
    {
        ExcludedByPrimary,
        RequireOrdered,
        AcceptUnordered,
    };

    struct CompareCondition
    {
        MicroCond          primaryCond       = MicroCond::Equal;
        FloatUnorderedMode floatUnorderedMode = FloatUnorderedMode::ExcludedByPrimary;
    };

    inline bool needsFloatUnorderedHandling(const TypeInfo& compareType, CompareCondition condition)
    {
        return compareType.isFloat() && condition.floatUnorderedMode != FloatUnorderedMode::ExcludedByPrimary;
    }

    inline void emitConditionBool(CodeGen& codeGen, MicroReg dstReg, const TypeInfo& compareType, CompareCondition condition)
    {
        MicroBuilder& builder = codeGen.builder();
        builder.emitSetCondReg(dstReg, condition.primaryCond);
        builder.emitLoadZeroExtendRegReg(dstReg, dstReg, MicroOpBits::B32, MicroOpBits::B8);

        if (!needsFloatUnorderedHandling(compareType, condition))
            return;

        const MicroReg unorderedReg = codeGen.nextVirtualIntRegister();
        const MicroCond unorderedCond = condition.floatUnorderedMode == FloatUnorderedMode::RequireOrdered ? MicroCond::NotParity : MicroCond::Parity;
        const MicroOp combineOp = condition.floatUnorderedMode == FloatUnorderedMode::RequireOrdered ? MicroOp::And : MicroOp::Or;

        builder.emitSetCondReg(unorderedReg, unorderedCond);
        builder.emitLoadZeroExtendRegReg(unorderedReg, unorderedReg, MicroOpBits::B32, MicroOpBits::B8);
        builder.emitOpBinaryRegReg(dstReg, unorderedReg, combineOp, MicroOpBits::B32);
    }

    inline void emitConditionJump(CodeGen& codeGen, const TypeInfo& compareType, CompareCondition condition, MicroLabelRef labelRef)
    {
        MicroBuilder& builder = codeGen.builder();
        if (!needsFloatUnorderedHandling(compareType, condition))
        {
            builder.emitJumpToLabel(condition.primaryCond, MicroOpBits::B32, labelRef);
            return;
        }

        if (condition.floatUnorderedMode == FloatUnorderedMode::AcceptUnordered)
        {
            builder.emitJumpToLabel(MicroCond::Parity, MicroOpBits::B32, labelRef);
            builder.emitJumpToLabel(condition.primaryCond, MicroOpBits::B32, labelRef);
            return;
        }

        const MicroLabelRef skipLabel = builder.createLabel();
        builder.emitJumpToLabel(MicroCond::Parity, MicroOpBits::B32, skipLabel);
        builder.emitJumpToLabel(condition.primaryCond, MicroOpBits::B32, labelRef);
        builder.placeLabel(skipLabel);
    }

    inline void emitConditionFalseJump(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef typeRef, MicroLabelRef falseLabel)
    {
        const TypeInfo&   typeInfo = codeGen.typeMgr().get(typeRef);
        const MicroOpBits condBits = CodeGenTypeHelpers::conditionBits(typeInfo, codeGen.ctx());
        const MicroReg    condReg  = codeGen.nextVirtualIntRegister();

        MicroBuilder& builder = codeGen.builder();
        if (payload.isAddress())
            builder.emitLoadRegMem(condReg, payload.reg, 0, condBits);
        else
            builder.emitLoadRegReg(condReg, payload.reg, condBits);

        builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, falseLabel);
    }
}

SWC_END_NAMESPACE();
