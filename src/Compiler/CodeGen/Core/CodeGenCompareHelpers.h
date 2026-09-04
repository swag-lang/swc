#pragma once
#include "Backend/RuntimeTypeInfo.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Support/Core/RefTypes.h"

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
        MicroCond          primaryCond        = MicroCond::Equal;
        FloatUnorderedMode floatUnorderedMode = FloatUnorderedMode::ExcludedByPrimary;
    };

    inline bool needsFloatUnorderedHandling(const TypeInfo& compareType, CompareCondition condition)
    {
        return compareType.isFloat() && condition.floatUnorderedMode != FloatUnorderedMode::ExcludedByPrimary;
    }

    inline CompareCondition truthyCondition(const TypeInfo& compareType)
    {
        return {.primaryCond        = MicroCond::NotEqual,
                .floatUnorderedMode = compareType.isFloat() ? FloatUnorderedMode::AcceptUnordered : FloatUnorderedMode::ExcludedByPrimary};
    }

    inline CompareCondition falseyCondition(const TypeInfo& compareType)
    {
        return {.primaryCond        = MicroCond::Equal,
                .floatUnorderedMode = compareType.isFloat() ? FloatUnorderedMode::RequireOrdered : FloatUnorderedMode::ExcludedByPrimary};
    }

    inline void emitCompareRegZero(CodeGen& codeGen, MicroReg reg, const TypeInfo& compareType, MicroOpBits opBits)
    {
        MicroBuilder& builder = codeGen.builder();
        if (!compareType.isFloat())
        {
            builder.emitCmpRegImm(reg, ApInt(0, 64), opBits);
            return;
        }

        const MicroReg zeroReg = codeGen.nextVirtualFloatRegister();
        builder.emitClearReg(zeroReg, opBits);
        builder.emitCmpRegReg(reg, zeroReg, opBits);
    }

    inline void emitConditionBool(CodeGen& codeGen, MicroReg dstReg, const TypeInfo& compareType, CompareCondition condition)
    {
        MicroBuilder& builder = codeGen.builder();
        builder.emitSetCondReg(dstReg, condition.primaryCond);
        builder.emitLoadZeroExtendRegReg(dstReg, dstReg, MicroOpBits::B32, MicroOpBits::B8);

        if (!needsFloatUnorderedHandling(compareType, condition))
            return;

        const MicroReg  unorderedReg  = codeGen.nextVirtualIntRegister();
        const MicroCond unorderedCond = condition.floatUnorderedMode == FloatUnorderedMode::RequireOrdered ? MicroCond::NotParity : MicroCond::Parity;
        const MicroOp   combineOp     = condition.floatUnorderedMode == FloatUnorderedMode::RequireOrdered ? MicroOp::And : MicroOp::Or;

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

    inline void emitTruthyBool(CodeGen& codeGen, MicroReg dstReg, MicroReg srcReg, const TypeInfo& compareType, MicroOpBits opBits)
    {
        emitCompareRegZero(codeGen, srcReg, compareType, opBits);
        emitConditionBool(codeGen, dstReg, compareType, truthyCondition(compareType));
    }

    // Jumps to 'equalLabel' when both registers name the same type, to 'notEqualLabel' otherwise.
    //
    // Type identity is the runtime hash, not the address of the descriptor: a qualified form such
    // as 'nullable string' gets its own typeinfo but shares the hash of 'string', which is the rule
    // 'Swag.typeCmp' applies. Comparing the pointers alone would report those as different types, so
    // every construct that matches a type against another one has to come through here.
    inline void emitTypeInfoEqualJump(CodeGen& codeGen, MicroReg leftReg, MicroReg rightReg, MicroLabelRef equalLabel, MicroLabelRef notEqualLabel)
    {
        MicroBuilder& builder = codeGen.builder();
        builder.emitCmpRegReg(leftReg, rightReg, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, equalLabel);

        // A null descriptor carries no hash to read, so it only ever matches the very same pointer.
        builder.emitCmpRegImm(leftReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, notEqualLabel);
        builder.emitCmpRegImm(rightReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, notEqualLabel);

        const MicroReg leftCrcReg  = codeGen.nextVirtualIntRegister();
        const MicroReg rightCrcReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(leftCrcReg, leftReg, offsetof(Runtime::TypeInfo, crc), MicroOpBits::B32);
        builder.emitLoadRegMem(rightCrcReg, rightReg, offsetof(Runtime::TypeInfo, crc), MicroOpBits::B32);
        builder.emitCmpRegReg(leftCrcReg, rightCrcReg, MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, equalLabel);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, notEqualLabel);
    }

    inline void emitConditionFalseJump(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef typeRef, MicroLabelRef falseLabel)
    {
        if (typeRef.isValid() && payload.typeRef.isValid() && codeGen.typeMgr().get(typeRef).isBool())
            typeRef = payload.typeRef;

        const TypeInfo&   typeInfo           = codeGen.typeMgr().get(typeRef);
        const MicroOpBits condBits           = CodeGenTypeHelpers::compareBits(typeInfo, codeGen.ctx());
        const MicroReg    condReg            = codeGen.nextVirtualRegisterForType(typeRef);
        const bool        addressBackedValue = !payload.isAddress() && typeInfo.sizeOf(codeGen.ctx()) > 8;

        MicroBuilder& builder = codeGen.builder();
        if (payload.isAddress() || addressBackedValue)
            builder.emitLoadRegMem(condReg, payload.reg, 0, condBits);
        else
            builder.emitLoadRegReg(condReg, payload.reg, condBits);

        emitCompareRegZero(codeGen, condReg, typeInfo, condBits);
        emitConditionJump(codeGen, typeInfo, falseyCondition(typeInfo), falseLabel);
    }
}

SWC_END_NAMESPACE();
