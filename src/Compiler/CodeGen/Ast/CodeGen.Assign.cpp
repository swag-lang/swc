#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class AssignEncodingKind : uint8_t
    {
        EqualStore,
        EqualStoreBulk,
        IntLikeCompound,
        FloatCompound,
    };

    struct AssignLocalTarget
    {
        const CodeGenNodePayload* payload = nullptr;
        TypeRef                   typeRef = TypeRef::invalid();
    };

    struct AssignEncodeContext
    {
        AssignLocalTarget         target;
        const CodeGenNodePayload* rightPayload = nullptr;
        TypeRef                   rightTypeRef = TypeRef::invalid();
        MicroOpBits               opBits       = MicroOpBits::Zero;
        uint32_t                  copySize     = 0;
        AssignEncodingKind        encodingKind = AssignEncodingKind::EqualStore;
    };

    TypeRef resolveOperandTypeRef(const CodeGenNodePayload& payload, TypeRef fallbackTypeRef)
    {
        if (payload.typeRef.isValid())
            return payload.typeRef;
        return fallbackTypeRef;
    }

    MicroOpBits scalarStoreOpBits(CodeGen& codeGen, const TypeInfo& typeInfo)
    {
        if (typeInfo.isFloat())
        {
            const uint32_t floatBits = typeInfo.payloadFloatBits() ? typeInfo.payloadFloatBits() : 64;
            return microOpBitsFromBitWidth(floatBits);
        }

        if (typeInfo.isBool())
            return MicroOpBits::B8;

        if (typeInfo.isIntLike())
        {
            const uint32_t intBits = typeInfo.payloadIntLikeBits() ? typeInfo.payloadIntLikeBits() : 64;
            return microOpBitsFromBitWidth(intBits);
        }

        if (typeInfo.isEnum() || typeInfo.isAnyPointer() || typeInfo.isFunction() || typeInfo.isCString() || typeInfo.isTypeInfo())
        {
            const uint64_t sizeOf = typeInfo.sizeOf(codeGen.ctx());
            if (sizeOf == 1 || sizeOf == 2 || sizeOf == 4 || sizeOf == 8)
                return microOpBitsFromChunkSize(static_cast<uint32_t>(sizeOf));
        }

        return MicroOpBits::Zero;
    }

    AssignEncodingKind resolveAssignEncodingKind(const TypeInfo& targetType, TokenId assignOp)
    {
        if (assignOp == TokenId::SymEqual)
            return AssignEncodingKind::EqualStore;

        if (targetType.isFloat())
            return AssignEncodingKind::FloatCompound;

        return AssignEncodingKind::IntLikeCompound;
    }

    bool isScalarAssignmentType(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        return scalarStoreOpBits(codeGen, typeInfo) != MicroOpBits::Zero;
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

    MicroReg materializeAssignOperand(CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, MicroOpBits opBits)
    {
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        const MicroReg operandReg = codeGen.nextVirtualRegisterForType(operandTypeRef);
        if (operandPayload.isAddress())
            codeGen.builder().emitLoadRegMem(operandReg, operandPayload.reg, 0, opBits);
        else
            codeGen.builder().emitLoadRegReg(operandReg, operandPayload.reg, opBits);

        return operandReg;
    }

    AssignLocalTarget resolveLocalAssignTarget(CodeGen& codeGen, AstNodeRef leftRef)
    {
        AssignLocalTarget target;
        target.payload = codeGen.safePayload(leftRef);
        if (!target.payload)
            return target;
        if (!target.payload->isAddress())
            return target;

        const SemaNodeView leftTypeView = codeGen.viewType(leftRef);
        const TypeRef      leftTypeRef  = resolveOperandTypeRef(*target.payload, leftTypeView.typeRef());
        if (!leftTypeRef.isValid())
            return target;

        const TypeInfo& leftTypeInfo = codeGen.typeMgr().get(leftTypeRef);
        if (leftTypeInfo.isReference())
            return target;

        target.typeRef = leftTypeRef;
        return target;
    }

    AssignEncodeContext buildAssignEncodeContext(CodeGen& codeGen, const AstAssignStmt& node, TokenId assignOp)
    {
        AssignEncodeContext encodeCtx;
        encodeCtx.target = resolveLocalAssignTarget(codeGen, node.nodeLeftRef);
        SWC_ASSERT(encodeCtx.target.payload != nullptr);
        SWC_ASSERT(encodeCtx.target.typeRef.isValid());

        encodeCtx.rightPayload = &codeGen.payload(node.nodeRightRef);

        const SemaNodeView rightView = codeGen.viewType(node.nodeRightRef);
        encodeCtx.rightTypeRef       = resolveOperandTypeRef(*encodeCtx.rightPayload, rightView.typeRef());
        if (!encodeCtx.rightTypeRef.isValid())
            encodeCtx.rightTypeRef = encodeCtx.target.typeRef;

        const TypeInfo& targetType = codeGen.typeMgr().get(encodeCtx.target.typeRef);
        if (isScalarAssignmentType(codeGen, encodeCtx.target.typeRef))
        {
            encodeCtx.opBits = scalarStoreOpBits(codeGen, targetType);
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
        SWC_ASSERT(encodeCtx.target.payload);
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.payload->isAddress());
        SWC_ASSERT(encodeCtx.copySize > 0);

        const MicroReg srcAddressReg = encodeCtx.rightPayload->reg;
        CodeGenMemoryHelpers::emitMemCopy(codeGen, encodeCtx.target.payload->reg, srcAddressReg, encodeCtx.copySize);
        return Result::Continue;
    }

    Result emitAssignEqualStore(CodeGen& codeGen, const AssignEncodeContext& encodeCtx)
    {
        SWC_ASSERT(encodeCtx.target.payload);
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.typeRef.isValid());
        SWC_ASSERT(encodeCtx.rightTypeRef.isValid());
        SWC_ASSERT(encodeCtx.opBits != MicroOpBits::Zero);

        const MicroReg rightReg = materializeAssignOperand(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef, encodeCtx.opBits);
        codeGen.builder().emitLoadMemReg(encodeCtx.target.payload->reg, 0, rightReg, encodeCtx.opBits);
        return Result::Continue;
    }

    Result emitAssignCompoundIntLike(CodeGen& codeGen, const AssignEncodeContext& encodeCtx, TokenId assignOp)
    {
        SWC_ASSERT(encodeCtx.target.payload);
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.typeRef.isValid());
        SWC_ASSERT(encodeCtx.rightTypeRef.isValid());
        SWC_ASSERT(encodeCtx.opBits != MicroOpBits::Zero);

        const TypeInfo& targetType = codeGen.typeMgr().get(encodeCtx.target.typeRef);
        const bool      isSigned   = targetType.isIntLike() && !targetType.isIntLikeUnsigned();
        const TokenId   binaryOp   = Token::assignToBinary(assignOp);
        const MicroOp   op         = intBinaryMicroOp(binaryOp, isSigned);
        MicroBuilder&   builder    = codeGen.builder();
        const MicroReg  leftReg    = codeGen.nextVirtualRegisterForType(encodeCtx.target.typeRef);
        builder.emitLoadRegMem(leftReg, encodeCtx.target.payload->reg, 0, encodeCtx.opBits);

        const MicroReg rightReg = materializeAssignOperand(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef, encodeCtx.opBits);
        builder.emitOpBinaryRegReg(leftReg, rightReg, op, encodeCtx.opBits);
        builder.emitLoadMemReg(encodeCtx.target.payload->reg, 0, leftReg, encodeCtx.opBits);
        return Result::Continue;
    }

    Result emitAssignCompoundFloat(CodeGen& codeGen, const AssignEncodeContext& encodeCtx, TokenId assignOp)
    {
        SWC_ASSERT(encodeCtx.target.payload);
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.typeRef.isValid());
        SWC_ASSERT(encodeCtx.rightTypeRef.isValid());
        SWC_ASSERT(encodeCtx.opBits != MicroOpBits::Zero);

        const TypeInfo& targetType = codeGen.typeMgr().get(encodeCtx.target.typeRef);
        SWC_ASSERT(targetType.isFloat());

        const TokenId  binaryOp = Token::assignToBinary(assignOp);
        const MicroOp  op       = floatBinaryMicroOp(binaryOp);
        MicroBuilder&  builder  = codeGen.builder();
        const MicroReg leftReg  = codeGen.nextVirtualRegisterForType(encodeCtx.target.typeRef);
        builder.emitLoadRegMem(leftReg, encodeCtx.target.payload->reg, 0, encodeCtx.opBits);

        const MicroReg rightReg = materializeAssignOperand(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef, encodeCtx.opBits);
        builder.emitOpBinaryRegReg(leftReg, rightReg, op, encodeCtx.opBits);
        builder.emitLoadMemReg(encodeCtx.target.payload->reg, 0, leftReg, encodeCtx.opBits);
        return Result::Continue;
    }
}

Result AstAssignStmt::codeGenPostNode(CodeGen& codeGen) const
{
    const Token&              tok       = codeGen.token(codeRef());
    const AssignEncodeContext encodeCtx = buildAssignEncodeContext(codeGen, *this, tok.id);
    switch (encodeCtx.encodingKind)
    {
        case AssignEncodingKind::EqualStore:
            return emitAssignEqualStore(codeGen, encodeCtx);
        case AssignEncodingKind::EqualStoreBulk:
            return emitAssignEqualStoreBulk(codeGen, encodeCtx);
        case AssignEncodingKind::IntLikeCompound:
            return emitAssignCompoundIntLike(codeGen, encodeCtx, tok.id);
        case AssignEncodingKind::FloatCompound:
            return emitAssignCompoundFloat(codeGen, encodeCtx, tok.id);
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
