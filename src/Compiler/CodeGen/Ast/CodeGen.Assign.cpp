#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    CodeGenNodePayload normalizeMoveAssignPayload(CodeGen& codeGen, const CodeGenNodePayload& rightPayload, TypeRef& ioRightTypeRef, AstModifierFlags modifierFlags)
    {
        CodeGenNodePayload payload = rightPayload;
        if (!ioRightTypeRef.isValid())
            return payload;
        if (!modifierFlags.hasAny({AstModifierFlagsE::Move, AstModifierFlagsE::MoveRaw}))
            return payload;

        const TypeInfo& rightType = codeGen.typeMgr().get(ioRightTypeRef);
        if (!rightType.isMoveReference())
            return payload;

        ioRightTypeRef = rightType.payloadTypeRef();
        payload.typeRef = ioRightTypeRef;
        if (payload.isAddress())
        {
            const MicroReg pointeeReg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegMem(pointeeReg, payload.reg, 0, MicroOpBits::B64);
            payload.reg = pointeeReg;
        }

        payload.setIsAddress();
        return payload;
    }

    enum class AssignEncodingKind : uint8_t
    {
        EqualStore,
        EqualStoreBulk,
        IntLikeCompound,
        FloatCompound,
        PointerCompound,
    };

    struct AssignTarget
    {
        CodeGenNodePayload payload;
        TypeRef            typeRef   = TypeRef::invalid();
        TypeRef            opTypeRef = TypeRef::invalid();
    };

    struct AssignEncodeContext
    {
        AssignTarget              target;
        const CodeGenNodePayload* rightPayload = nullptr;
        TypeRef                   rightTypeRef = TypeRef::invalid();
        MicroOpBits               opBits       = MicroOpBits::Zero;
        uint32_t                  copySize     = 0;
        AssignEncodingKind        encodingKind = AssignEncodingKind::EqualStore;
    };

    AssignEncodingKind resolveAssignEncodingKind(const TypeInfo& targetType, TokenId assignOp)
    {
        if (assignOp == TokenId::SymEqual)
            return AssignEncodingKind::EqualStore;

        if (targetType.isBlockPointer())
            return AssignEncodingKind::PointerCompound;

        if (targetType.isFloat())
            return AssignEncodingKind::FloatCompound;

        return AssignEncodingKind::IntLikeCompound;
    }

    bool isScalarAssignmentType(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        return CodeGenTypeHelpers::scalarStoreBits(typeInfo, codeGen.ctx()) != MicroOpBits::Zero;
    }

    MicroOp intBinaryMicroOp(TokenId tokId, bool isSigned)
    {
        switch (tokId)
        {
            case TokenId::SymPlus:
                return MicroOp::Add;
            case TokenId::SymMinus:
                return MicroOp::Subtract;
            case TokenId::SymAsterisk:
                return MicroOp::MultiplySigned;
            case TokenId::SymSlash:
                return isSigned ? MicroOp::DivideSigned : MicroOp::DivideUnsigned;
            case TokenId::SymPercent:
                return isSigned ? MicroOp::ModuloSigned : MicroOp::ModuloUnsigned;
            case TokenId::SymAmpersand:
                return MicroOp::And;
            case TokenId::SymPipe:
                return MicroOp::Or;
            case TokenId::SymCircumflex:
                return MicroOp::Xor;
            case TokenId::SymLowerLower:
                return MicroOp::ShiftLeft;
            case TokenId::SymGreaterGreater:
                return isSigned ? MicroOp::ShiftArithmeticRight : MicroOp::ShiftRight;

            default:
                SWC_UNREACHABLE();
        }
    }

    MicroOp floatBinaryMicroOp(TokenId tokId)
    {
        switch (tokId)
        {
            case TokenId::SymPlus:
                return MicroOp::FloatAdd;
            case TokenId::SymMinus:
                return MicroOp::FloatSubtract;
            case TokenId::SymAsterisk:
                return MicroOp::FloatMultiply;
            case TokenId::SymSlash:
                return MicroOp::FloatDivide;

            default:
                SWC_UNREACHABLE();
        }
    }

    TypeRef unwrapAssignScalarTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return typeRef;

        const TypeRef unwrappedTypeRef = codeGen.typeMgr().get(typeRef).unwrapAliasEnum(codeGen.ctx(), typeRef);
        return unwrappedTypeRef.isValid() ? unwrappedTypeRef : typeRef;
    }

    MicroReg loadAssignOperand(CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, MicroOpBits opBits)
    {
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        const MicroReg operandReg = codeGen.nextVirtualRegisterForType(operandTypeRef);
        if (operandPayload.isAddress())
            codeGen.builder().emitLoadRegMem(operandReg, operandPayload.reg, 0, opBits);
        else
            codeGen.builder().emitLoadRegReg(operandReg, operandPayload.reg, opBits);

        return operandReg;
    }

    MicroReg materializeAssignScalarOperand(CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, TypeRef targetTypeRef)
    {
        operandTypeRef = unwrapAssignScalarTypeRef(codeGen, operandTypeRef);
        targetTypeRef  = unwrapAssignScalarTypeRef(codeGen, targetTypeRef);
        SWC_ASSERT(operandTypeRef.isValid());
        SWC_ASSERT(targetTypeRef.isValid());

        const TypeInfo&   srcType   = codeGen.typeMgr().get(operandTypeRef);
        const TypeInfo&   dstType   = codeGen.typeMgr().get(targetTypeRef);
        const MicroOpBits srcOpBits = CodeGenTypeHelpers::scalarStoreBits(srcType, codeGen.ctx());
        const MicroOpBits dstOpBits = CodeGenTypeHelpers::scalarStoreBits(dstType, codeGen.ctx());
        SWC_ASSERT(dstOpBits != MicroOpBits::Zero);
        if (srcOpBits == MicroOpBits::Zero)
            return loadAssignOperand(codeGen, operandPayload, targetTypeRef, dstOpBits);

        const bool srcIntLikeType = srcType.isIntLike() || srcType.isBool();
        const bool dstIntLikeType = dstType.isIntLike() || dstType.isBool();
        const bool srcFloatType   = srcType.isFloat();
        const bool dstFloatType   = dstType.isFloat();

        MicroBuilder& builder = codeGen.builder();
        MicroReg      srcReg  = operandPayload.reg;
        if (operandPayload.isAddress())
            srcReg = loadAssignOperand(codeGen, operandPayload, operandTypeRef, srcOpBits);

        if (srcIntLikeType && dstIntLikeType)
        {
            if (dstType.isBool())
            {
                const MicroReg dstReg = codeGen.nextVirtualIntRegister();
                builder.emitCmpRegImm(srcReg, ApInt(0, 64), srcOpBits);
                builder.emitSetCondReg(dstReg, MicroCond::NotEqual);
                return dstReg;
            }

            const uint32_t srcWidth = getNumBits(srcOpBits);
            const uint32_t dstWidth = getNumBits(dstOpBits);
            const MicroReg dstReg   = codeGen.nextVirtualIntRegister();
            if (srcWidth == dstWidth)
            {
                builder.emitLoadRegReg(dstReg, srcReg, dstOpBits);
                return dstReg;
            }

            if (srcWidth > dstWidth)
            {
                builder.emitLoadRegReg(dstReg, srcReg, dstOpBits);
                return dstReg;
            }

            if (srcType.isNumericSigned())
            {
                builder.emitLoadSignedExtendRegReg(dstReg, srcReg, dstOpBits, srcOpBits);
                return dstReg;
            }

            builder.emitLoadZeroExtendRegReg(dstReg, srcReg, dstOpBits, srcOpBits);
            return dstReg;
        }

        if (srcIntLikeType && dstFloatType)
        {
            if (getNumBits(srcOpBits) < 32 || (dstOpBits == MicroOpBits::B64 && getNumBits(srcOpBits) == 32))
            {
                const MicroReg widenedReg  = codeGen.nextVirtualIntRegister();
                const MicroOpBits widenedBits = dstOpBits == MicroOpBits::B64 ? MicroOpBits::B64 : MicroOpBits::B32;
                if (srcType.isIntSigned())
                    builder.emitLoadSignedExtendRegReg(widenedReg, srcReg, widenedBits, srcOpBits);
                else
                    builder.emitLoadZeroExtendRegReg(widenedReg, srcReg, widenedBits, srcOpBits);
                srcReg = widenedReg;
            }

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(targetTypeRef);
            builder.emitClearReg(dstReg, dstOpBits);
            builder.emitOpBinaryRegReg(dstReg, srcReg, MicroOp::ConvertIntToFloat, dstOpBits);
            return dstReg;
        }

        if (srcFloatType && dstFloatType)
        {
            if (srcOpBits == dstOpBits)
                return srcReg;

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(targetTypeRef);
            builder.emitClearReg(dstReg, dstOpBits);
            builder.emitOpBinaryRegReg(dstReg, srcReg, MicroOp::ConvertFloatToFloat, srcOpBits);
            return dstReg;
        }

        if (srcFloatType && dstIntLikeType)
        {
            if (dstType.isBool())
            {
                const MicroReg zeroReg = codeGen.nextVirtualRegisterForType(operandTypeRef);
                const MicroReg dstReg  = codeGen.nextVirtualIntRegister();
                builder.emitClearReg(zeroReg, srcOpBits);
                builder.emitCmpRegReg(srcReg, zeroReg, srcOpBits);
                builder.emitSetCondReg(dstReg, MicroCond::NotEqual);
                return dstReg;
            }

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(targetTypeRef);
            builder.emitClearReg(dstReg, dstOpBits);
            builder.emitOpBinaryRegReg(dstReg, srcReg, MicroOp::ConvertFloatToInt, srcOpBits);
            return dstReg;
        }

        return loadAssignOperand(codeGen, operandPayload, operandTypeRef, dstOpBits);
    }

    uint64_t pointerStrideSize(CodeGen& codeGen, TypeRef pointerTypeRef)
    {
        const TypeInfo& pointerType = codeGen.typeMgr().get(pointerTypeRef);
        return CodeGenTypeHelpers::blockPointerStride(codeGen.ctx(), pointerType);
    }

    MicroReg materializeAssignPointerIndexReg(CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        const TypeInfo&   operandType = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits srcBits     = CodeGenTypeHelpers::scalarStoreBits(operandType, codeGen.ctx());
        SWC_ASSERT(operandType.isIntLike());
        SWC_ASSERT(srcBits != MicroOpBits::Zero);

        const MicroReg resultReg = codeGen.nextVirtualIntRegister();
        MicroBuilder&  builder   = codeGen.builder();
        if (operandPayload.isAddress())
        {
            if (srcBits == MicroOpBits::B64)
                builder.emitLoadRegMem(resultReg, operandPayload.reg, 0, MicroOpBits::B64);
            else if (operandType.isIntLikeUnsigned())
                builder.emitLoadZeroExtendRegMem(resultReg, operandPayload.reg, 0, MicroOpBits::B64, srcBits);
            else
                builder.emitLoadSignedExtendRegMem(resultReg, operandPayload.reg, 0, MicroOpBits::B64, srcBits);
        }
        else
        {
            if (srcBits == MicroOpBits::B64)
                builder.emitLoadRegReg(resultReg, operandPayload.reg, MicroOpBits::B64);
            else if (operandType.isIntLikeUnsigned())
                builder.emitLoadZeroExtendRegReg(resultReg, operandPayload.reg, MicroOpBits::B64, srcBits);
            else
                builder.emitLoadSignedExtendRegReg(resultReg, operandPayload.reg, MicroOpBits::B64, srcBits);
        }

        return resultReg;
    }

    AssignTarget resolveAssignTarget(CodeGen& codeGen, AstNodeRef leftRef)
    {
        AssignTarget target;
        target.payload = codeGen.payload(leftRef);

        const SemaNodeView leftTypeView = codeGen.viewType(leftRef);
        const TypeRef      leftTypeRef  = target.payload.effectiveTypeRef(leftTypeView.typeRef());
        SWC_ASSERT(leftTypeRef.isValid());

        const TypeInfo& leftTypeInfo  = codeGen.typeMgr().get(leftTypeRef);
        TypeRef         targetTypeRef = leftTypeRef;
        if (leftTypeInfo.isReference())
        {
            SWC_ASSERT(!target.payload.isAddress());
            target.payload.setIsAddress();
            targetTypeRef = leftTypeInfo.payloadTypeRef();
        }
        else
        {
            SWC_ASSERT(target.payload.isAddress());
        }

        const TypeRef opTypeRef = codeGen.typeMgr().get(targetTypeRef).unwrapAliasEnum(codeGen.ctx(), targetTypeRef);
        target.typeRef          = targetTypeRef;
        target.opTypeRef        = opTypeRef;
        return target;
    }

    AssignEncodeContext buildAssignEncodeContext(CodeGen& codeGen, AstNodeRef leftRef, const CodeGenNodePayload& rightPayload, TypeRef rightTypeRef, TokenId assignOp)
    {
        AssignEncodeContext encodeCtx;
        encodeCtx.target = resolveAssignTarget(codeGen, leftRef);
        SWC_ASSERT(encodeCtx.target.typeRef.isValid());
        SWC_ASSERT(encodeCtx.target.opTypeRef.isValid());

        encodeCtx.rightPayload = &rightPayload;
        encodeCtx.rightTypeRef = encodeCtx.rightPayload->effectiveTypeRef(rightTypeRef);
        if (!encodeCtx.rightTypeRef.isValid())
            encodeCtx.rightTypeRef = encodeCtx.target.typeRef;

        const TypeInfo& targetType = codeGen.typeMgr().get(encodeCtx.target.opTypeRef);
        if (isScalarAssignmentType(codeGen, encodeCtx.target.opTypeRef))
        {
            encodeCtx.opBits = CodeGenTypeHelpers::scalarStoreBits(targetType, codeGen.ctx());
            SWC_ASSERT(encodeCtx.opBits != MicroOpBits::Zero);
            encodeCtx.encodingKind = resolveAssignEncodingKind(targetType, assignOp);
            return encodeCtx;
        }

        SWC_ASSERT(assignOp == TokenId::SymEqual);

        const uint64_t copySize = targetType.sizeOf(codeGen.ctx());
        SWC_ASSERT(copySize > 0);
        SWC_ASSERT(copySize <= std::numeric_limits<uint32_t>::max());
        encodeCtx.copySize     = static_cast<uint32_t>(copySize);
        encodeCtx.encodingKind = AssignEncodingKind::EqualStoreBulk;
        return encodeCtx;
    }

    Result emitAssignEqualStoreBulk(CodeGen& codeGen, const AssignEncodeContext& encodeCtx)
    {
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.payload.isAddress());
        SWC_ASSERT(encodeCtx.copySize > 0);

        const MicroReg srcAddressReg = encodeCtx.rightPayload->reg;
        CodeGenMemoryHelpers::emitMemCopy(codeGen, encodeCtx.target.payload.reg, srcAddressReg, encodeCtx.copySize);
        return Result::Continue;
    }

    Result emitAssignEqualStore(CodeGen& codeGen, const AssignEncodeContext& encodeCtx)
    {
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.typeRef.isValid());
        SWC_ASSERT(encodeCtx.rightTypeRef.isValid());
        SWC_ASSERT(encodeCtx.opBits != MicroOpBits::Zero);

        MicroBuilder&      builder          = codeGen.builder();
        CodeGenNodePayload rightPayload     = *encodeCtx.rightPayload;
        MicroReg           targetAddressReg = encodeCtx.target.payload.reg;

        if (targetAddressReg.isVirtualInt())
        {
            const MicroReg stableTargetReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(stableTargetReg, targetAddressReg, MicroOpBits::B64);
            targetAddressReg = stableTargetReg;
        }

        if (rightPayload.isAddress() && rightPayload.reg.isVirtualInt())
        {
            const MicroReg stableSourceReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(stableSourceReg, rightPayload.reg, MicroOpBits::B64);
            rightPayload.reg = stableSourceReg;
        }

        const MicroReg rightReg = materializeAssignScalarOperand(codeGen, rightPayload, encodeCtx.rightTypeRef, encodeCtx.target.opTypeRef);
        builder.emitLoadMemReg(targetAddressReg, 0, rightReg, encodeCtx.opBits);
        return Result::Continue;
    }

    Result emitAssignCompoundIntLike(CodeGen& codeGen, const AssignEncodeContext& encodeCtx, TokenId assignOp)
    {
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.typeRef.isValid());
        SWC_ASSERT(encodeCtx.target.opTypeRef.isValid());
        SWC_ASSERT(encodeCtx.rightTypeRef.isValid());
        SWC_ASSERT(encodeCtx.opBits != MicroOpBits::Zero);

        const TypeInfo& targetType = codeGen.typeMgr().get(encodeCtx.target.opTypeRef);
        const bool      isSigned   = targetType.isIntLike() && !targetType.isIntLikeUnsigned();
        const TokenId   binaryOp   = Token::assignToBinary(assignOp);
        const MicroOp   op         = intBinaryMicroOp(binaryOp, isSigned);
        MicroBuilder&   builder    = codeGen.builder();
        const MicroReg  leftReg    = codeGen.nextVirtualRegisterForType(encodeCtx.target.typeRef);
        builder.emitLoadRegMem(leftReg, encodeCtx.target.payload.reg, 0, encodeCtx.opBits);

        const MicroReg rightReg = materializeAssignScalarOperand(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef, encodeCtx.target.opTypeRef);
        builder.emitOpBinaryRegReg(leftReg, rightReg, op, encodeCtx.opBits);
        builder.emitLoadMemReg(encodeCtx.target.payload.reg, 0, leftReg, encodeCtx.opBits);
        return Result::Continue;
    }

    Result emitAssignCompoundFloat(CodeGen& codeGen, const AssignEncodeContext& encodeCtx, TokenId assignOp)
    {
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.typeRef.isValid());
        SWC_ASSERT(encodeCtx.target.opTypeRef.isValid());
        SWC_ASSERT(encodeCtx.rightTypeRef.isValid());
        SWC_ASSERT(encodeCtx.opBits != MicroOpBits::Zero);

        const TypeInfo& targetType = codeGen.typeMgr().get(encodeCtx.target.opTypeRef);
        SWC_ASSERT(targetType.isFloat());

        const TokenId  binaryOp = Token::assignToBinary(assignOp);
        const MicroOp  op       = floatBinaryMicroOp(binaryOp);
        MicroBuilder&  builder  = codeGen.builder();
        const MicroReg leftReg  = codeGen.nextVirtualRegisterForType(encodeCtx.target.typeRef);
        builder.emitLoadRegMem(leftReg, encodeCtx.target.payload.reg, 0, encodeCtx.opBits);

        const MicroReg rightReg = materializeAssignScalarOperand(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef, encodeCtx.target.opTypeRef);
        builder.emitOpBinaryRegReg(leftReg, rightReg, op, encodeCtx.opBits);
        builder.emitLoadMemReg(encodeCtx.target.payload.reg, 0, leftReg, encodeCtx.opBits);
        return Result::Continue;
    }

    Result emitAssignCompoundPointer(CodeGen& codeGen, const AssignEncodeContext& encodeCtx, TokenId assignOp)
    {
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.opTypeRef.isValid());
        SWC_ASSERT(encodeCtx.rightTypeRef.isValid());
        SWC_ASSERT(assignOp == TokenId::SymPlusEqual || assignOp == TokenId::SymMinusEqual);

        const uint64_t stride   = pointerStrideSize(codeGen, encodeCtx.target.opTypeRef);
        const MicroReg leftReg  = codeGen.nextVirtualIntRegister();
        const MicroReg indexReg = materializeAssignPointerIndexReg(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef);
        MicroBuilder&  builder  = codeGen.builder();
        builder.emitLoadRegMem(leftReg, encodeCtx.target.payload.reg, 0, MicroOpBits::B64);

        if (stride == 1)
        {
            const MicroOp op = assignOp == TokenId::SymMinusEqual ? MicroOp::Subtract : MicroOp::Add;
            builder.emitOpBinaryRegReg(leftReg, indexReg, op, MicroOpBits::B64);
            builder.emitLoadMemReg(encodeCtx.target.payload.reg, 0, leftReg, MicroOpBits::B64);
            return Result::Continue;
        }

        if (assignOp == TokenId::SymMinusEqual)
        {
            const MicroReg resultReg   = codeGen.nextVirtualIntRegister();
            const MicroReg negIndexReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(negIndexReg, indexReg, MicroOpBits::B64);
            builder.emitOpUnaryReg(negIndexReg, MicroOp::Negate, MicroOpBits::B64);
            builder.emitLoadAddressAmcRegMem(resultReg, MicroOpBits::B64, leftReg, negIndexReg, stride, 0, MicroOpBits::B64);
            builder.emitLoadMemReg(encodeCtx.target.payload.reg, 0, resultReg, MicroOpBits::B64);
            return Result::Continue;
        }

        const MicroReg resultReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadAddressAmcRegMem(resultReg, MicroOpBits::B64, leftReg, indexReg, stride, 0, MicroOpBits::B64);
        builder.emitLoadMemReg(encodeCtx.target.payload.reg, 0, resultReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitAssign(CodeGen& codeGen, AstNodeRef leftRef, const CodeGenNodePayload& rightPayload, TypeRef rightTypeRef, TokenId assignOp)
    {
        const AssignEncodeContext encodeCtx = buildAssignEncodeContext(codeGen, leftRef, rightPayload, rightTypeRef, assignOp);
        switch (encodeCtx.encodingKind)
        {
            case AssignEncodingKind::EqualStore:
                return emitAssignEqualStore(codeGen, encodeCtx);
            case AssignEncodingKind::EqualStoreBulk:
                return emitAssignEqualStoreBulk(codeGen, encodeCtx);
            case AssignEncodingKind::IntLikeCompound:
                return emitAssignCompoundIntLike(codeGen, encodeCtx, assignOp);
            case AssignEncodingKind::FloatCompound:
                return emitAssignCompoundFloat(codeGen, encodeCtx, assignOp);
            case AssignEncodingKind::PointerCompound:
                return emitAssignCompoundPointer(codeGen, encodeCtx, assignOp);
        }

        SWC_UNREACHABLE();
    }

    Result emitAssignList(CodeGen& codeGen, const AstAssignList& assignList, const CodeGenNodePayload& rightPayload, TypeRef rightTypeRef, TokenId assignOp)
    {
        SmallVector<AstNodeRef> leftRefs;
        codeGen.ast().appendNodes(leftRefs, assignList.spanChildrenRef);

        for (const AstNodeRef leftRef : leftRefs)
        {
            if (leftRef.isInvalid())
                continue;
            if (codeGen.node(leftRef).is(AstNodeId::AssignIgnore))
                continue;

            SWC_RESULT(emitAssign(codeGen, leftRef, rightPayload, rightTypeRef, assignOp));
        }

        return Result::Continue;
    }
}

Result AstAssignStmt::codeGenPostNode(CodeGen& codeGen) const
{
    const Token&              tok          = codeGen.token(codeRef());
    CodeGenNodePayload        rightPayload = codeGen.payload(nodeRightRef);
    const SemaNodeView        rightView    = codeGen.viewType(nodeRightRef);
    TypeRef                   rightTypeRef = rightView.typeRef();
    rightPayload                            = normalizeMoveAssignPayload(codeGen, rightPayload, rightTypeRef, modifierFlags);
    const AstNodeRef          leftRef      = codeGen.viewZero(nodeLeftRef).nodeRef();

    if (leftRef.isValid() && codeGen.node(leftRef).is(AstNodeId::AssignList))
    {
        const auto& assignList = codeGen.node(leftRef).cast<AstAssignList>();
        return emitAssignList(codeGen, assignList, rightPayload, rightTypeRef, tok.id);
    }

    return emitAssign(codeGen, nodeLeftRef, rightPayload, rightTypeRef, tok.id);
}

SWC_END_NAMESPACE();
