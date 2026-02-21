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

    TypeRef resolveCompareTypeRef(CodeGen& codeGen, const SemaNodeView& leftView, const SemaNodeView& rightView)
    {
        if (leftView.type()->isScalarNumeric() && rightView.type()->isScalarNumeric())
            return codeGen.typeMgr().promote(leftView.typeRef(), rightView.typeRef(), false);

        return leftView.typeRef();
    }

    void loadCompareOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        outReg                        = codeGen.nextVirtualRegisterForType(operandTypeRef);
        const TypeInfo&   operandType = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits opBits      = compareOpBits(operandType);

        MicroBuilder& builder = codeGen.builder();
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    void convertCompareOperand(MicroReg& outReg, CodeGen& codeGen, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (srcTypeRef == dstTypeRef)
            return;

        const TypeInfo&   srcType = codeGen.typeMgr().get(srcTypeRef);
        const TypeInfo&   dstType = codeGen.typeMgr().get(dstTypeRef);
        const MicroOpBits srcBits = compareOpBits(srcType);
        const MicroOpBits dstBits = compareOpBits(dstType);

        MicroBuilder& builder = codeGen.builder();

        if (srcType.isIntLike() && dstType.isIntLike())
        {
            const MicroReg dstReg = codeGen.nextVirtualIntRegister();
            if (srcBits == dstBits)
            {
                builder.emitLoadRegReg(dstReg, outReg, dstBits);
                outReg = dstReg;
                return;
            }

            if (static_cast<uint32_t>(srcBits) > static_cast<uint32_t>(dstBits))
            {
                builder.emitLoadRegReg(dstReg, outReg, dstBits);
                outReg = dstReg;
                return;
            }

            if (srcType.isIntSigned())
                builder.emitLoadSignedExtendRegReg(dstReg, outReg, dstBits, srcBits);
            else
                builder.emitLoadZeroExtendRegReg(dstReg, outReg, dstBits, srcBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isIntLike() && dstType.isFloat())
        {
            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, outReg, MicroOp::ConvertIntToFloat, dstBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isFloat() && dstType.isFloat())
        {
            builder.emitOpBinaryRegReg(outReg, outReg, MicroOp::ConvertFloatToFloat, srcBits);
            return;
        }
    }

    void materializeCompareOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, TypeRef compareTypeRef)
    {
        loadCompareOperand(outReg, codeGen, operandPayload, operandTypeRef);
        convertCompareOperand(outReg, codeGen, operandTypeRef, compareTypeRef);
    }

    bool usesUnsignedConditions(const TypeInfo& typeInfo)
    {
        return typeInfo.isFloat() || typeInfo.isIntLikeUnsigned() || typeInfo.isPointerLike() || typeInfo.isBool();
    }

    void materializeLogicalOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        const TypeInfo&   operandType = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits operandBits = compareOpBits(operandType);
        outReg                        = codeGen.nextVirtualRegisterForType(operandTypeRef);

        MicroBuilder& builder = codeGen.builder();
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, operandBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, operandBits);

        if (operandType.isBool())
            return;

        const MicroReg zeroReg = codeGen.nextVirtualRegisterForType(operandTypeRef);
        builder.emitClearReg(zeroReg, operandBits);
        builder.emitCmpRegReg(outReg, zeroReg, operandBits);

        const MicroReg boolReg = codeGen.nextVirtualIntRegister();
        builder.emitSetCondReg(boolReg, MicroCond::NotEqual);
        outReg = boolReg;
    }

    void materializeScalarOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, MicroOpBits opBits)
    {
        outReg = codeGen.nextVirtualRegisterForType(operandTypeRef);

        MicroBuilder& builder = codeGen.builder();
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
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

        const CodeGenNodePayload& leftPayload         = ensureOperandPayload(codeGen, node.nodeLeftRef);
        const CodeGenNodePayload& rightPayload        = ensureOperandPayload(codeGen, node.nodeRightRef);
        const TypeRef             leftOperandTypeRef  = leftPayload.typeRef.isValid() ? leftPayload.typeRef : leftView.typeRef();
        const TypeRef             rightOperandTypeRef = rightPayload.typeRef.isValid() ? rightPayload.typeRef : rightView.typeRef();

        const TypeRef     compareTypeRef = resolveCompareTypeRef(codeGen, leftView, rightView);
        const TypeInfo&   compareType    = codeGen.typeMgr().get(compareTypeRef);
        const MicroOpBits opBits         = compareOpBits(compareType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg  = MicroReg::invalid();
        MicroReg rightReg = MicroReg::invalid();
        materializeCompareOperand(leftReg, codeGen, leftPayload, leftOperandTypeRef, compareTypeRef);
        materializeCompareOperand(rightReg, codeGen, rightPayload, rightOperandTypeRef, compareTypeRef);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        resultPayload.reg                 = codeGen.nextVirtualIntRegister();
        MicroBuilder& builder             = codeGen.builder();
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
                cond = relationalCondition(tokId, usesUnsignedConditions(compareType));
                break;

            default:
                SWC_UNREACHABLE();
        }

        builder.emitSetCondReg(resultPayload.reg, cond);
        builder.emitLoadZeroExtendRegReg(resultPayload.reg, resultPayload.reg, MicroOpBits::B32, MicroOpBits::B8);
        return Result::Continue;
    }

    Result emitThreeWayCompare(CodeGen& codeGen, const AstRelationalExpr& node)
    {
        const SemaNodeView leftView  = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.viewType(node.nodeRightRef);
        SWC_ASSERT(leftView.type() && rightView.type());

        const CodeGenNodePayload& leftPayload         = ensureOperandPayload(codeGen, node.nodeLeftRef);
        const CodeGenNodePayload& rightPayload        = ensureOperandPayload(codeGen, node.nodeRightRef);
        const TypeRef             leftOperandTypeRef  = leftPayload.typeRef.isValid() ? leftPayload.typeRef : leftView.typeRef();
        const TypeRef             rightOperandTypeRef = rightPayload.typeRef.isValid() ? rightPayload.typeRef : rightView.typeRef();

        const TypeRef     compareTypeRef = resolveCompareTypeRef(codeGen, leftView, rightView);
        const TypeInfo&   compareType    = codeGen.typeMgr().get(compareTypeRef);
        const MicroOpBits opBits         = compareOpBits(compareType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg  = MicroReg::invalid();
        MicroReg rightReg = MicroReg::invalid();
        materializeCompareOperand(leftReg, codeGen, leftPayload, leftOperandTypeRef, compareTypeRef);
        materializeCompareOperand(rightReg, codeGen, rightPayload, rightOperandTypeRef, compareTypeRef);

        MicroBuilder& builder = codeGen.builder();

        const bool      unsignedOrFloat = usesUnsignedConditions(compareType);
        const MicroCond lessCond        = unsignedOrFloat ? MicroCond::Below : MicroCond::Less;
        const MicroCond greatCond       = unsignedOrFloat ? MicroCond::Above : MicroCond::Greater;

        const MicroReg lessReg  = codeGen.nextVirtualIntRegister();
        const MicroReg greatReg = codeGen.nextVirtualIntRegister();
        builder.emitCmpRegReg(leftReg, rightReg, opBits);
        builder.emitSetCondReg(lessReg, lessCond);
        builder.emitLoadZeroExtendRegReg(lessReg, lessReg, MicroOpBits::B32, MicroOpBits::B8);
        builder.emitSetCondReg(greatReg, greatCond);
        builder.emitLoadZeroExtendRegReg(greatReg, greatReg, MicroOpBits::B32, MicroOpBits::B8);

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

Result AstLogicalExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const CodeGenNodePayload* leftPayload  = codeGen.payload(nodeLeftRef);
    const CodeGenNodePayload* rightPayload = codeGen.payload(nodeRightRef);
    SWC_ASSERT(leftPayload != nullptr);
    SWC_ASSERT(rightPayload != nullptr);

    const SemaNodeView leftView  = codeGen.viewType(nodeLeftRef);
    const SemaNodeView rightView = codeGen.viewType(nodeRightRef);
    const TypeRef      leftType  = leftPayload->typeRef.isValid() ? leftPayload->typeRef : leftView.typeRef();
    const TypeRef      rightType = rightPayload->typeRef.isValid() ? rightPayload->typeRef : rightView.typeRef();

    MicroReg leftReg  = MicroReg::invalid();
    MicroReg rightReg = MicroReg::invalid();
    materializeLogicalOperand(leftReg, codeGen, *leftPayload, leftType);
    materializeLogicalOperand(rightReg, codeGen, *rightPayload, rightType);

    const CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
    MicroBuilder&             builder     = codeGen.builder();
    builder.emitLoadRegReg(nodePayload.reg, leftReg, MicroOpBits::B8);

    const Token& tok = codeGen.token(codeRef());
    if (tok.id == TokenId::KwdAnd)
        builder.emitOpBinaryRegReg(nodePayload.reg, rightReg, MicroOp::And, MicroOpBits::B8);
    else if (tok.id == TokenId::KwdOr)
        builder.emitOpBinaryRegReg(nodePayload.reg, rightReg, MicroOp::Or, MicroOpBits::B8);
    else
        SWC_UNREACHABLE();

    return Result::Continue;
}

Result AstConditionalExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView condView   = codeGen.viewType(nodeCondRef);
    const SemaNodeView trueView   = codeGen.viewType(nodeTrueRef);
    const SemaNodeView falseView  = codeGen.viewType(nodeFalseRef);
    const SemaNodeView resultView = codeGen.curViewType();
    SWC_ASSERT(condView.type() && trueView.type() && falseView.type() && resultView.type());

    const CodeGenNodePayload* condPayload  = codeGen.payload(nodeCondRef);
    const CodeGenNodePayload* truePayload  = codeGen.payload(nodeTrueRef);
    const CodeGenNodePayload* falsePayload = codeGen.payload(nodeFalseRef);
    SWC_ASSERT(condPayload && truePayload && falsePayload);

    const TypeRef condTypeRef   = condPayload->typeRef.isValid() ? condPayload->typeRef : condView.typeRef();
    const TypeRef resultTypeRef = resultView.typeRef();
    const TypeRef trueTypeRef   = truePayload->typeRef.isValid() ? truePayload->typeRef : trueView.typeRef();
    const TypeRef falseTypeRef  = falsePayload->typeRef.isValid() ? falsePayload->typeRef : falseView.typeRef();

    const MicroOpBits condBits   = compareOpBits(codeGen.typeMgr().get(condTypeRef));
    const MicroOpBits resultBits = compareOpBits(codeGen.typeMgr().get(resultTypeRef));
    SWC_ASSERT(condBits != MicroOpBits::Zero && resultBits != MicroOpBits::Zero);

    MicroReg condReg  = MicroReg::invalid();
    MicroReg trueReg  = MicroReg::invalid();
    MicroReg falseReg = MicroReg::invalid();
    materializeScalarOperand(condReg, codeGen, *condPayload, condTypeRef, condBits);
    materializeScalarOperand(trueReg, codeGen, *truePayload, trueTypeRef, resultBits);
    materializeScalarOperand(falseReg, codeGen, *falsePayload, falseTypeRef, resultBits);

    CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
    resultPayload.reg                 = codeGen.nextVirtualRegisterForType(resultTypeRef);

    MicroBuilder& builder    = codeGen.builder();
    const Ref     falseLabel = builder.createLabel();
    const Ref     doneLabel  = builder.createLabel();

    builder.emitCmpRegZero(condReg, condBits);
    builder.emitJumpToLabel(MicroCond::Equal, condBits, falseLabel);
    builder.emitLoadRegReg(resultPayload.reg, trueReg, resultBits);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    builder.placeLabel(falseLabel);
    builder.emitLoadRegReg(resultPayload.reg, falseReg, resultBits);
    builder.placeLabel(doneLabel);

    return Result::Continue;
}

SWC_END_NAMESPACE();
