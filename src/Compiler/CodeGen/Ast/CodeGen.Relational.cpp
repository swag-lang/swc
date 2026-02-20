#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const CodeGenNodePayload& ensureOperandPayload(const CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return *SWC_CHECK_NOT_NULL(codeGen.payload(nodeRef));
    }

    MicroOpBits compareOpBits(const TypeInfo& typeInfo)
    {
        if (typeInfo.isFloat())
        {
            const uint32_t floatBits = typeInfo.payloadFloatBits() ? typeInfo.payloadFloatBits() : 64;
            return microOpBitsFromBitWidth(floatBits);
        }

        if (typeInfo.isIntLike())
        {
            const uint32_t intBits = typeInfo.payloadIntLikeBits() ? typeInfo.payloadIntLikeBits() : 64;
            return microOpBitsFromBitWidth(intBits);
        }

        if (typeInfo.isBool())
            return MicroOpBits::B8;

        return MicroOpBits::B64;
    }

    void materializeCompareOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, MicroOpBits opBits)
    {
        outReg = codeGen.nextVirtualRegisterForType(operandTypeRef);

        MicroBuilder& builder = codeGen.builder();
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    bool usesUnsignedConditions(const TypeInfo& typeInfo)
    {
        return typeInfo.isFloat() || typeInfo.isIntLikeUnsigned() || typeInfo.isPointerLike() || typeInfo.isBool();
    }

    MicroCond relationalCondition(TokenId tokId, bool unsignedOrFloatCompare)
    {
        switch (tokId)
        {
            case TokenId::SymLess:
                return unsignedOrFloatCompare ? MicroCond::Below : MicroCond::Less;
            case TokenId::SymLessEqual:
                return unsignedOrFloatCompare ? MicroCond::BelowOrEqual : MicroCond::LessOrEqual;
            case TokenId::SymGreater:
                return unsignedOrFloatCompare ? MicroCond::Above : MicroCond::Greater;
            case TokenId::SymGreaterEqual:
                return unsignedOrFloatCompare ? MicroCond::AboveOrEqual : MicroCond::GreaterOrEqual;

            default:
                SWC_UNREACHABLE();
        }
    }

    Result emitRelationalBool(CodeGen& codeGen, const AstRelationalExpr& node, TokenId tokId)
    {
        const SemaNodeView leftView  = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.viewType(node.nodeRightRef);
        SWC_ASSERT(leftView.type() && rightView.type());

        const CodeGenNodePayload& leftPayload  = ensureOperandPayload(codeGen, node.nodeLeftRef);
        const CodeGenNodePayload& rightPayload = ensureOperandPayload(codeGen, node.nodeRightRef);

        const MicroOpBits opBits = compareOpBits(*leftView.type());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg  = MicroReg::invalid();
        MicroReg rightReg = MicroReg::invalid();
        materializeCompareOperand(leftReg, codeGen, leftPayload, leftView.typeRef(), opBits);
        materializeCompareOperand(rightReg, codeGen, rightPayload, rightView.typeRef(), opBits);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        resultPayload.reg                 = codeGen.nextVirtualIntRegister();
        MicroBuilder& builder             = codeGen.builder();
        builder.emitLoadRegImm(resultPayload.reg, 0, MicroOpBits::B64);
        builder.emitCmpRegReg(leftReg, rightReg, opBits);

        auto cond = MicroCond::Equal;
        switch (tokId)
        {
            case TokenId::SymEqualEqual:
                cond = MicroCond::Equal;
                break;
            case TokenId::SymBangEqual:
                cond = MicroCond::NotEqual;
                break;

            case TokenId::SymLess:
            case TokenId::SymLessEqual:
            case TokenId::SymGreater:
            case TokenId::SymGreaterEqual:
                cond = relationalCondition(tokId, usesUnsignedConditions(*leftView.type()));
                break;

            default:
                SWC_UNREACHABLE();
        }

        builder.emitSetCondReg(resultPayload.reg, cond);
        return Result::Continue;
    }

    Result emitThreeWayCompare(CodeGen& codeGen, const AstRelationalExpr& node)
    {
        const SemaNodeView leftView  = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.viewType(node.nodeRightRef);
        SWC_ASSERT(leftView.type() && rightView.type());

        const CodeGenNodePayload& leftPayload  = ensureOperandPayload(codeGen, node.nodeLeftRef);
        const CodeGenNodePayload& rightPayload = ensureOperandPayload(codeGen, node.nodeRightRef);

        const MicroOpBits opBits = compareOpBits(*leftView.type());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg  = MicroReg::invalid();
        MicroReg rightReg = MicroReg::invalid();
        materializeCompareOperand(leftReg, codeGen, leftPayload, leftView.typeRef(), opBits);
        materializeCompareOperand(rightReg, codeGen, rightPayload, rightView.typeRef(), opBits);

        MicroBuilder& builder = codeGen.builder();

        const bool      unsignedOrFloat = usesUnsignedConditions(*leftView.type());
        const MicroCond lessCond        = unsignedOrFloat ? MicroCond::Below : MicroCond::Less;
        const MicroCond greatCond       = unsignedOrFloat ? MicroCond::Above : MicroCond::Greater;

        const MicroReg lessReg  = codeGen.nextVirtualIntRegister();
        const MicroReg greatReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(lessReg, 0, MicroOpBits::B64);
        builder.emitLoadRegImm(greatReg, 0, MicroOpBits::B64);
        builder.emitCmpRegReg(leftReg, rightReg, opBits);
        builder.emitSetCondReg(lessReg, lessCond);
        builder.emitSetCondReg(greatReg, greatCond);

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        builder.emitLoadRegReg(resultPayload.reg, greatReg, MicroOpBits::B32);
        builder.emitOpBinaryRegReg(resultPayload.reg, lessReg, MicroOp::Subtract, MicroOpBits::B32);
        return Result::Continue;
    }
}

Result AstRelationalExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::SymEqualEqual:
        case TokenId::SymBangEqual:
        case TokenId::SymLess:
        case TokenId::SymLessEqual:
        case TokenId::SymGreater:
        case TokenId::SymGreaterEqual:
            return emitRelationalBool(codeGen, *this, tok.id);

        case TokenId::SymLessEqualGreater:
            return emitThreeWayCompare(codeGen, *this);

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
