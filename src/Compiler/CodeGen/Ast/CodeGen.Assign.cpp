#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMoveElision.h"
#include "Compiler/CodeGen/Core/CodeGenPointerIndex.h"
#include "Compiler/CodeGen/Core/CodeGenReferenceHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Compiler/CodeGen/Core/CodeGenStructHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenVectorHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    CodeGenNodePayload normalizeMoveAssignPayload(CodeGen& codeGen, const CodeGenNodePayload& rightPayload, TypeRef& ioRightTypeRef, AstModifierFlags modifierFlags)
    {
        CodeGenNodePayload payload = rightPayload;
        if (!ioRightTypeRef.isValid())
            return payload;
        if (!modifierFlags.hasAny({AstModifierFlagsE::Move, AstModifierFlagsE::Relocate}))
            return payload;

        const TypeInfo& rightType = codeGen.typeMgr().get(ioRightTypeRef);
        if (!rightType.isMoveReference())
            return payload;

        ioRightTypeRef  = rightType.payloadTypeRef();
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
        VectorCompound,
    };

    struct AssignTarget
    {
        CodeGenNodePayload payload;
        TypeRef            typeRef   = TypeRef::invalid();
        TypeRef            opTypeRef = TypeRef::invalid();
    };

    struct AssignEncodeContext
    {
        AssignTarget target;

        const CodeGenNodePayload* rightPayload = nullptr;
        TypeRef                   rightTypeRef = TypeRef::invalid();

        MicroOpBits        opBits       = MicroOpBits::Zero;
        uint32_t           copySize     = 0;
        AssignEncodingKind encodingKind = AssignEncodingKind::EqualStore;
    };

    AssignEncodingKind resolveAssignEncodingKind(const TypeInfo& targetType, TokenId assignOp)
    {
        if (assignOp == TokenId::SymEqual)
            return AssignEncodingKind::EqualStore;

        if (targetType.isBlockPointer())
            return AssignEncodingKind::PointerCompound;

        if (targetType.isFloat())
            return AssignEncodingKind::FloatCompound;

        if (targetType.isSimd())
            return AssignEncodingKind::VectorCompound;

        return AssignEncodingKind::IntLikeCompound;
    }

    using CodeGenTypeHelpers::floatBinaryMicroOp;
    using CodeGenTypeHelpers::intBinaryMicroOp;

    MicroReg materializeAssignPointerIndexReg(CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        operandTypeRef = CodeGenTypeHelpers::unwrapAliasEnumTypeRef(codeGen.typeMgr(), codeGen.ctx(), operandTypeRef);

        const TypeInfo&   operandType = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits srcBits     = CodeGenTypeHelpers::scalarStoreBits(operandType, codeGen.ctx());
        return CodeGenPointerIndex::materialize(codeGen, operandPayload, operandType, srcBits);
    }

    void normalizeReferenceAssignTarget(CodeGen& codeGen, CodeGenNodePayload& ioPayload, TypeRef& ioTypeRef)
    {
        if (!ioTypeRef.isValid())
            return;

        const TypeInfo& leftTypeInfo = codeGen.typeMgr().get(ioTypeRef);
        if (!leftTypeInfo.isReference())
            return;

        ioTypeRef = leftTypeInfo.payloadTypeRef();
        CodeGenReferenceHelpers::derefReferencePayload(codeGen, ioPayload, ioTypeRef);
    }

    AssignTarget resolveAssignTarget(CodeGen& codeGen, AstNodeRef leftRef)
    {
        AssignTarget target;
        target.payload = codeGen.payload(leftRef);

        const TypeRef leftTypeRef = target.payload.typeRef.isValid() ? target.payload.typeRef : codeGen.viewType(leftRef).typeRef();
        SWC_ASSERT(leftTypeRef.isValid());

        TypeRef targetTypeRef = leftTypeRef;
        normalizeReferenceAssignTarget(codeGen, target.payload, targetTypeRef);

        if (!codeGen.typeMgr().get(leftTypeRef).isReference())
            SWC_ASSERT(target.payload.isAddress());

        const TypeRef opTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), targetTypeRef);
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
        encodeCtx.opBits           = CodeGenTypeHelpers::scalarStoreBits(targetType, codeGen.ctx());
        if (encodeCtx.opBits != MicroOpBits::Zero)
        {
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

    void stabilizeAssignAddressPayload(CodeGen& codeGen, CodeGenNodePayload& ioPayload)
    {
        if (!ioPayload.isAddress() || !ioPayload.reg.isInt())
            return;

        const MicroReg stableReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegReg(stableReg, ioPayload.reg, MicroOpBits::B64);
        ioPayload.reg = stableReg;
    }

    Result emitAssignEqualStoreBulk(CodeGen& codeGen, const AssignEncodeContext& encodeCtx)
    {
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.payload.isAddress());
        SWC_ASSERT(encodeCtx.copySize > 0);

        CodeGenNodePayload targetPayload = encodeCtx.target.payload;
        stabilizeAssignAddressPayload(codeGen, targetPayload);

        if (encodeCtx.rightPayload->isAddress())
        {
            CodeGenNodePayload rightPayload = *encodeCtx.rightPayload;
            stabilizeAssignAddressPayload(codeGen, rightPayload);
            CodeGenMemoryHelpers::emitCopyPreservingDynamicIdentity(codeGen, codeGen.typeMgr().get(encodeCtx.target.opTypeRef), targetPayload.reg, rightPayload.reg);
            return Result::Continue;
        }

        if (encodeCtx.copySize == 1 || encodeCtx.copySize == 2 || encodeCtx.copySize == 4 || encodeCtx.copySize == 8)
        {
            const MicroOpBits storeBits = microOpBitsFromChunkSize(encodeCtx.copySize);
            codeGen.builder().emitLoadMemReg(targetPayload.reg, 0, encodeCtx.rightPayload->reg, storeBits);
            return Result::Continue;
        }

        CodeGenMemoryHelpers::emitMemCopy(codeGen, targetPayload.reg, encodeCtx.rightPayload->reg, encodeCtx.copySize);
        return Result::Continue;
    }

    Result emitAssignEqualStore(CodeGen& codeGen, const AssignEncodeContext& encodeCtx)
    {
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.typeRef.isValid());
        SWC_ASSERT(encodeCtx.rightTypeRef.isValid());
        SWC_ASSERT(encodeCtx.opBits != MicroOpBits::Zero);

        // An eight-byte dynamic value contains only its identity slot.
        if (SymbolStruct::typeHasDynamicStorage(codeGen.ctx(), codeGen.typeMgr().get(encodeCtx.target.opTypeRef)))
        {
            SWC_ASSERT(codeGen.typeMgr().get(encodeCtx.target.opTypeRef).sizeOf(codeGen.ctx()) == sizeof(void*));
            return Result::Continue;
        }

        MicroBuilder&      builder       = codeGen.builder();
        CodeGenNodePayload targetPayload = encodeCtx.target.payload;
        CodeGenNodePayload rightPayload  = *encodeCtx.rightPayload;
        stabilizeAssignAddressPayload(codeGen, targetPayload);
        stabilizeAssignAddressPayload(codeGen, rightPayload);

        const MicroReg rightReg = CodeGenMemoryHelpers::materializeScalarPayloadForStore(codeGen, rightPayload, encodeCtx.rightTypeRef, encodeCtx.target.opTypeRef);
        builder.emitLoadMemReg(targetPayload.reg, 0, rightReg, encodeCtx.opBits);
        return Result::Continue;
    }

    Result emitAssignCompoundIntLike(CodeGen& codeGen, const AssignEncodeContext& encodeCtx, TokenId assignOp)
    {
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.typeRef.isValid());
        SWC_ASSERT(encodeCtx.target.opTypeRef.isValid());
        SWC_ASSERT(encodeCtx.rightTypeRef.isValid());
        SWC_ASSERT(encodeCtx.opBits != MicroOpBits::Zero);

        const auto&     node       = codeGen.node(codeGen.curNodeRef()).cast<AstAssignStmt>();
        const TypeInfo& targetType = codeGen.typeMgr().get(encodeCtx.target.opTypeRef);
        const bool      isSigned   = targetType.isIntLike() && !targetType.isIntLikeUnsigned();
        const TokenId   binaryOp   = Token::assignToBinary(assignOp);
        const MicroOp   op         = intBinaryMicroOp(binaryOp, isSigned);

        MicroBuilder&      builder       = codeGen.builder();
        CodeGenNodePayload targetPayload = encodeCtx.target.payload;
        stabilizeAssignAddressPayload(codeGen, targetPayload);

        const MicroReg leftReg = codeGen.nextVirtualRegisterForType(encodeCtx.target.typeRef);
        builder.emitLoadRegMem(leftReg, targetPayload.reg, 0, encodeCtx.opBits);

        if (assignOp == TokenId::SymLowerLowerEqual || assignOp == TokenId::SymGreaterGreaterEqual)
        {
            const TypeRef     countTypeRef = CodeGenTypeHelpers::unwrapAliasEnumTypeRef(codeGen.typeMgr(), codeGen.ctx(), encodeCtx.rightTypeRef);
            const TypeInfo&   countType    = codeGen.typeMgr().get(countTypeRef);
            const MicroOpBits countBits    = CodeGenTypeHelpers::numericBits(countType);
            const MicroReg    countReg     = CodeGenMemoryHelpers::materializeScalarPayloadForStore(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef, countTypeRef);

            CodeGenSafety::ShiftIntLikeContext shiftCtx;
            shiftCtx.countOperandRef = node.nodeRightRef;
            shiftCtx.valueReg        = leftReg;
            shiftCtx.countReg        = countReg;
            shiftCtx.valueType       = &targetType;
            shiftCtx.countType       = &countType;
            shiftCtx.valueBits       = encodeCtx.opBits;
            shiftCtx.countBits       = countBits;
            shiftCtx.op              = Token::assignToBinary(assignOp);
            SWC_RESULT(CodeGenSafety::emitShiftIntLike(codeGen, node, shiftCtx));
        }
        else
        {
            const MicroReg rightReg = CodeGenMemoryHelpers::materializeScalarPayloadForStore(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef, encodeCtx.target.opTypeRef);
            if (assignOp == TokenId::SymSlashEqual || assignOp == TokenId::SymPercentEqual)
            {
                SWC_RESULT(CodeGenSafety::emitDivOrModIntLike(codeGen, node, leftReg, rightReg, op, encodeCtx.opBits, isSigned, assignOp == TokenId::SymPercentEqual));
            }
            else
            {
                builder.emitOpBinaryRegReg(leftReg, rightReg, op, encodeCtx.opBits);
                if (CodeGenSafety::hasOverflowRuntimeSafety(codeGen))
                    SWC_RESULT(CodeGenSafety::emitIntArithmeticOverflowCheck(codeGen, node, binaryOp, isSigned));
            }
        }

        builder.emitLoadMemReg(targetPayload.reg, 0, leftReg, encodeCtx.opBits);
        return Result::Continue;
    }

    Result emitAssignCompoundVector(CodeGen& codeGen, const AssignEncodeContext& encodeCtx, TokenId assignOp)
    {
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.opTypeRef.isValid());

        const TypeInfo& targetType = codeGen.typeMgr().get(encodeCtx.target.opTypeRef);
        SWC_ASSERT(targetType.isSimd());
        const TypeInfo& laneType = codeGen.typeMgr().get(targetType.payloadSimdLaneTypeRef());

        const TokenId binaryOp = Token::assignToBinary(assignOp);

        MicroBuilder&      builder       = codeGen.builder();
        CodeGenNodePayload targetPayload = encodeCtx.target.payload;
        stabilizeAssignAddressPayload(codeGen, targetPayload);

        const MicroReg leftReg = codeGen.nextVirtualFloatRegister();
        builder.emitLoadVecRegMem(leftReg, targetPayload.reg, 0, MicroOpBits::B128);

        MicroReg resultReg;
        if (binaryOp == TokenId::SymLowerLower || binaryOp == TokenId::SymGreaterGreater)
        {
            // Encode constant shift counts directly; runtime counts use the
            // low bits of a vector register.
            const auto& node = codeGen.node(codeGen.curNodeRef()).cast<AstAssignStmt>();
            resultReg        = CodeGenVectorHelpers::emitConstantShift(codeGen, binaryOp, leftReg, laneType, node.nodeRightRef);
            if (!resultReg.isValid())
            {
                const TypeRef     countTypeRef = CodeGenTypeHelpers::unwrapAliasEnumTypeRef(codeGen.typeMgr(), codeGen.ctx(), encodeCtx.rightTypeRef);
                const TypeInfo&   countType    = codeGen.typeMgr().get(countTypeRef);
                const MicroOpBits countBits    = CodeGenTypeHelpers::numericBits(countType);
                MicroReg          countReg     = CodeGenMemoryHelpers::materializeScalarPayloadForStore(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef, countTypeRef);
                if (countBits != MicroOpBits::B64)
                {
                    const MicroReg wideCountReg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadZeroExtendRegReg(wideCountReg, countReg, MicroOpBits::B64, countBits);
                    countReg = wideCountReg;
                }

                const MicroReg countVecReg = codeGen.nextVirtualFloatRegister();
                builder.emitLoadRegReg(countVecReg, countReg, MicroOpBits::B64);
                resultReg = CodeGenVectorHelpers::emitVariableShift(codeGen, binaryOp, leftReg, countVecReg, laneType);
            }
        }
        else
        {
            const TypeRef   rightResolvedTypeRef = CodeGenTypeHelpers::unwrapAliasEnumTypeRef(codeGen.typeMgr(), codeGen.ctx(), encodeCtx.rightTypeRef);
            const TypeInfo& rightType            = codeGen.typeMgr().get(rightResolvedTypeRef);

            MicroReg rhsReg;
            if (rightType.isSimd())
            {
                if (encodeCtx.rightPayload->isAddress())
                {
                    rhsReg = codeGen.nextVirtualFloatRegister();
                    builder.emitLoadVecRegMem(rhsReg, encodeCtx.rightPayload->reg, 0, MicroOpBits::B128);
                }
                else
                {
                    rhsReg = encodeCtx.rightPayload->reg;
                }
            }
            else
            {
                const MicroReg scalarReg = CodeGenMemoryHelpers::materializeScalarPayloadForStore(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef, targetType.payloadSimdLaneTypeRef());
                rhsReg                   = CodeGenVectorHelpers::splatScalarLane(codeGen, scalarReg, laneType);
            }

            if (binaryOp == TokenId::SymAsterisk && laneType.isInt() && (laneType.payloadIntBits() == 8 || laneType.payloadIntBits() == 64))
                resultReg = CodeGenVectorHelpers::emitDecomposedMultiply(codeGen, leftReg, rhsReg, laneType);
            else
            {
                resultReg = codeGen.nextVirtualFloatRegister();
                builder.emitOpBinaryRegRegReg(resultReg, leftReg, rhsReg, CodeGenVectorHelpers::binaryMicroOpForLane(binaryOp, laneType), MicroOpBits::B128);
            }
        }

        builder.emitStoreVecMemReg(targetPayload.reg, 0, resultReg, MicroOpBits::B128);
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

        const TokenId binaryOp = Token::assignToBinary(assignOp);
        const MicroOp op       = floatBinaryMicroOp(binaryOp);

        MicroBuilder&      builder       = codeGen.builder();
        CodeGenNodePayload targetPayload = encodeCtx.target.payload;
        stabilizeAssignAddressPayload(codeGen, targetPayload);

        const MicroReg leftReg = codeGen.nextVirtualRegisterForType(encodeCtx.target.typeRef);
        builder.emitLoadRegMem(leftReg, targetPayload.reg, 0, encodeCtx.opBits);

        const MicroReg rightReg = CodeGenMemoryHelpers::materializeScalarPayloadForStore(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef, encodeCtx.target.opTypeRef);
        builder.emitOpBinaryRegReg(leftReg, rightReg, op, encodeCtx.opBits);
        builder.emitLoadMemReg(targetPayload.reg, 0, leftReg, encodeCtx.opBits);
        return Result::Continue;
    }

    Result emitAssignCompoundPointer(CodeGen& codeGen, const AssignEncodeContext& encodeCtx, TokenId assignOp)
    {
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.target.opTypeRef.isValid());
        SWC_ASSERT(encodeCtx.rightTypeRef.isValid());
        SWC_ASSERT(assignOp == TokenId::SymPlusEqual || assignOp == TokenId::SymMinusEqual);

        const uint64_t stride   = CodeGenTypeHelpers::blockPointerStride(codeGen.ctx(), encodeCtx.target.opTypeRef);
        const MicroReg leftReg  = codeGen.nextVirtualIntRegister();
        const MicroReg indexReg = materializeAssignPointerIndexReg(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef);

        MicroBuilder&      builder       = codeGen.builder();
        CodeGenNodePayload targetPayload = encodeCtx.target.payload;
        stabilizeAssignAddressPayload(codeGen, targetPayload);
        builder.emitLoadRegMem(leftReg, targetPayload.reg, 0, MicroOpBits::B64);

        if (stride == 1)
        {
            const MicroOp op = assignOp == TokenId::SymMinusEqual ? MicroOp::Subtract : MicroOp::Add;
            builder.emitOpBinaryRegReg(leftReg, indexReg, op, MicroOpBits::B64);
            builder.emitLoadMemReg(targetPayload.reg, 0, leftReg, MicroOpBits::B64);
            return Result::Continue;
        }

        if (assignOp == TokenId::SymMinusEqual)
        {
            const MicroReg resultReg   = codeGen.nextVirtualIntRegister();
            const MicroReg negIndexReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(negIndexReg, indexReg, MicroOpBits::B64);
            builder.emitOpUnaryReg(negIndexReg, MicroOp::Negate, MicroOpBits::B64);
            builder.emitLoadAddressAmcRegMem(resultReg, MicroOpBits::B64, leftReg, negIndexReg, stride, 0, MicroOpBits::B64);
            builder.emitLoadMemReg(targetPayload.reg, 0, resultReg, MicroOpBits::B64);
            return Result::Continue;
        }

        const MicroReg resultReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadAddressAmcRegMem(resultReg, MicroOpBits::B64, leftReg, indexReg, stride, 0, MicroOpBits::B64);
        builder.emitLoadMemReg(targetPayload.reg, 0, resultReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitAssignEncoded(CodeGen& codeGen, const AssignEncodeContext& encodeCtx, TokenId assignOp)
    {
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
            case AssignEncodingKind::VectorCompound:
                return emitAssignCompoundVector(codeGen, encodeCtx, assignOp);
            case AssignEncodingKind::PointerCompound:
                return emitAssignCompoundPointer(codeGen, encodeCtx, assignOp);
        }

        SWC_UNREACHABLE();
    }

    bool canReinitializeMoveSource(CodeGen& codeGen, AstNodeRef rightRef, TypeRef originalRightTypeRef)
    {
        if (originalRightTypeRef.isValid() && codeGen.typeMgr().get(originalRightTypeRef).isMoveReference())
            return true;

        return codeGen.sema().isLValue(codeGen.node(rightRef));
    }

    Result emitAssignLifecycle(CodeGen& codeGen, AstNodeRef leftRef, const CodeGenNodePayload& originalRightPayload, TypeRef rightTypeRef, TypeRef originalRightTypeRef, TokenId assignOp, AstModifierFlags modifierFlags, AstNodeRef rightRef)
    {
        const AssignEncodeContext encodeCtx = buildAssignEncodeContext(codeGen, leftRef, originalRightPayload, rightTypeRef, assignOp);
        if (encodeCtx.target.payload.isAddress() && !CodeGenSafety::isUnborrowableLocalWrite(codeGen, leftRef))
            SWC_RESULT(CodeGenSafety::emitValueBorrowWrite(codeGen, encodeCtx.target.payload.reg, codeGen.typeMgr().get(encodeCtx.target.typeRef).sizeOf(codeGen.ctx())));

        if (assignOp != TokenId::SymEqual)
            return emitAssignEncoded(codeGen, encodeCtx, assignOp);
        if (!encodeCtx.target.opTypeRef.isValid())
            return emitAssignEncoded(codeGen, encodeCtx, assignOp);

        const TypeInfo& targetType = codeGen.typeMgr().get(encodeCtx.target.opTypeRef);
        if (!targetType.isStructOrAggregateStruct() && !targetType.isArray())
            return emitAssignEncoded(codeGen, encodeCtx, assignOp);

        const bool isMove         = modifierFlags.hasAny({AstModifierFlagsE::Move, AstModifierFlagsE::Relocate});
        const bool isRelocate     = modifierFlags.has(AstModifierFlagsE::Relocate);
        const bool skipTargetDrop = modifierFlags.has(AstModifierFlagsE::NoDrop) || modifierFlags.has(AstModifierFlagsE::FirstInit) || isRelocate;

        const SymbolVariable* sourceStorage  = originalRightPayload.runtimeStorageSym ? originalRightPayload.runtimeStorageSym : codeGen.runtimeStorageSymbol(rightRef);
        const bool            ownedRValue    = originalRightPayload.isAddress() && (CodeGenFunctionHelpers::isFreshAggregateLiteral(codeGen, rightRef) || CodeGenFunctionHelpers::isOwnedCallResult(codeGen, rightRef));
        const bool            movesTemporary = originalRightPayload.ownsValue || (sourceStorage && codeGen.hasTemporaryDrop(*sourceStorage)) || ownedRValue;

        const CodeGen::LifecycleKind postKind         = isMove || movesTemporary ? CodeGen::LifecycleKind::PostMove : CodeGen::LifecycleKind::PostCopy;
        const bool                   hasTargetDrop    = !skipTargetDrop && codeGen.hasLifecycle(encodeCtx.target.opTypeRef, CodeGen::LifecycleKind::Drop);
        const bool                   hasPostLifecycle = codeGen.hasLifecycle(encodeCtx.target.opTypeRef, postKind);

        const bool canTouchSource    = isMove && originalRightPayload.isAddress() && canReinitializeMoveSource(codeGen, rightRef, originalRightTypeRef);
        const bool shouldResetSource = canTouchSource && !isRelocate && codeGen.hasLifecycle(rightTypeRef, CodeGen::LifecycleKind::Drop);

        // A '#relocate' source, or a '#move' source without a drop lifecycle, is abandoned
        // with its stale bits: under lifecycle safety it is poisoned and marked moved-from.
        const bool shouldInvalidateSource = canTouchSource && !shouldResetSource && CodeGenSafety::hasLifecycleInvalidate(codeGen);

        // A local whose lifetime ends at a move or relocation has no remaining value
        // to reset or drop. Lifecycle safety can still poison its abandoned storage.
        AstNodeRef            resolvedRightRef = AstNodeRef::invalid();
        const SymbolVariable* rightVar         = CodeGenMoveElision::directStructVariable(codeGen, rightRef, &resolvedRightRef);

        const bool elideSource = (shouldResetSource || (canTouchSource && isRelocate)) && rightVar && CodeGenMoveElision::canElideMoveSource(codeGen, *rightVar, resolvedRightRef);

        if (elideSource)
            codeGen.markImplicitDropElided(*rightVar);

        const bool wantInvalidateSource = shouldInvalidateSource || (elideSource && CodeGenSafety::hasLifecycleInvalidate(codeGen));

        if (!hasTargetDrop && !hasPostLifecycle && !shouldResetSource && !shouldInvalidateSource)
        {
            SWC_RESULT(emitAssignEncoded(codeGen, encodeCtx, assignOp));
            if (modifierFlags.has(AstModifierFlagsE::FirstInit))
                SWC_RESULT(CodeGenMemoryHelpers::emitDynamicIdentity(codeGen, encodeCtx.target.opTypeRef, encodeCtx.target.payload.reg));
            if (movesTemporary && sourceStorage)
                codeGen.cancelTemporaryDrop(*sourceStorage);

            return Result::Continue;
        }

        AssignEncodeContext lifecycleCtx = encodeCtx;
        CodeGenNodePayload  stableRight  = originalRightPayload;
        MicroBuilder&       builder      = codeGen.builder();
        const MicroReg      targetReg    = lifecycleCtx.target.payload.reg;
        if (targetReg.isValid())
        {
            const MicroReg stableTargetReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(stableTargetReg, targetReg, MicroOpBits::B64);
            lifecycleCtx.target.payload.reg = stableTargetReg;
        }

        if (stableRight.isAddress())
        {
            const MicroReg stableSourceReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(stableSourceReg, stableRight.reg, MicroOpBits::B64);
            stableRight.reg = stableSourceReg;
        }

        lifecycleCtx.rightPayload = &stableRight;

        // Different frame slots cannot self-assign. Keep the guard for references,
        // incoming arguments and return storage, whose addresses may alias.
        const SymbolVariable* leftVar = CodeGenMoveElision::directStructVariable(codeGen, leftRef);

        const bool distinctStorage = leftVar && rightVar && leftVar != rightVar &&
                                     leftVar->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) && rightVar->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) &&
                                     !leftVar->hasExtraFlag(SymbolVariableFlagsE::Parameter) && !rightVar->hasExtraFlag(SymbolVariableFlagsE::Parameter) &&
                                     leftVar->offset() != rightVar->offset() &&
                                     !CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, *leftVar) && !CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, *rightVar);

        MicroLabelRef doneLabel = MicroLabelRef::invalid();
        if (stableRight.isAddress() && lifecycleCtx.target.payload.isAddress() && !distinctStorage)
        {
            doneLabel = builder.createLabel();
            builder.emitCmpRegReg(lifecycleCtx.target.payload.reg, stableRight.reg, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
        }

        if (hasTargetDrop)
            SWC_RESULT(codeGen.emitLifecycle(encodeCtx.target.opTypeRef, CodeGen::LifecycleKind::Drop, lifecycleCtx.target.payload.reg));

        SWC_RESULT(emitAssignEncoded(codeGen, lifecycleCtx, assignOp));

        if (modifierFlags.has(AstModifierFlagsE::FirstInit))
            SWC_RESULT(CodeGenMemoryHelpers::emitDynamicIdentity(codeGen, encodeCtx.target.opTypeRef, lifecycleCtx.target.payload.reg));

        if (hasPostLifecycle)
            SWC_RESULT(codeGen.emitLifecycle(encodeCtx.target.opTypeRef, postKind, lifecycleCtx.target.payload.reg));

        // Preserve the existing named-source proof when another storage shape still
        // needs a runtime guard: its invalidation belongs after the join.
        const bool invalidateAfterGuard = wantInvalidateSource && doneLabel.isValid() && leftVar && rightVar && leftVar != rightVar;

        if (shouldResetSource && !elideSource)
            SWC_RESULT(CodeGenFunctionHelpers::emitMovedFromDefaultValue(codeGen, rightTypeRef, stableRight.reg));
        else if (wantInvalidateSource && !invalidateAfterGuard)
            SWC_RESULT(CodeGenSafety::emitLifecycleInvalidate(codeGen, stableRight.reg, rightTypeRef, rightRef));

        if (doneLabel.isValid())
            builder.placeLabel(doneLabel);

        if (invalidateAfterGuard)
            SWC_RESULT(CodeGenSafety::emitLifecycleInvalidate(codeGen, stableRight.reg, rightTypeRef, rightRef));

        // Call results and fresh aggregates are owned rvalues, even when inline or
        // error-managed calls have no registered cleanup. After post-move repair,
        // their bits belong to the destination; cancel any remaining statement cleanup.
        if (movesTemporary && sourceStorage)
            codeGen.cancelTemporaryDrop(*sourceStorage);

        return Result::Continue;
    }

    Result emitAssign(CodeGen& codeGen, AstNodeRef leftRef, const CodeGenNodePayload& rightPayload, TypeRef rightTypeRef, TokenId assignOp)
    {
        const AssignEncodeContext encodeCtx = buildAssignEncodeContext(codeGen, leftRef, rightPayload, rightTypeRef, assignOp);
        return emitAssignEncoded(codeGen, encodeCtx, assignOp);
    }

    Result emitAssignList(CodeGen& codeGen, const AstAssignList& assignList, const CodeGenNodePayload& rightPayload, TypeRef rightTypeRef, TokenId assignOp)
    {
        const auto leftRefs = codeGen.ast().nodeSpan(assignList.spanChildrenRef);

        for (auto chunk = leftRefs.chunksBegin(); chunk != leftRefs.chunksEnd(); ++chunk)
        {
            for (const AstNodeRef leftRef : std::span(static_cast<const AstNodeRef*>(chunk->ptr), chunk->count))
            {
                if (leftRef.isInvalid())
                    continue;
                if (codeGen.node(leftRef).is(AstNodeId::AssignIgnore))
                    continue;

                SWC_RESULT(emitAssign(codeGen, leftRef, rightPayload, rightTypeRef, assignOp));
            }
        }

        return Result::Continue;
    }

    MicroReg materializeDestructuringSourceCopy(CodeGen& codeGen, const CodeGenNodePayload& rightPayload, const TypeInfo& rightType)
    {
        const uint64_t copySize = rightType.sizeOf(codeGen.ctx());
        SWC_ASSERT(copySize > 0);
        SWC_ASSERT(copySize <= std::numeric_limits<uint32_t>::max());

        const CodeGenNodePayload* storagePayload = codeGen.safePayload(codeGen.curNodeRef());
        SWC_ASSERT(storagePayload && storagePayload->runtimeStorageSym != nullptr);

        const MicroReg storageReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        CodeGenMemoryHelpers::storePayloadToAddress(codeGen, storageReg, rightPayload, static_cast<uint32_t>(copySize));
        return storageReg;
    }

    // Targets adopt the snapshot's selected fields after releasing their old values.
    // Named sources were copied into the snapshot before any target changed.
    Result emitAssignDestructuringField(CodeGen& codeGen, AstNodeRef leftRef, const CodeGenNodePayload& fieldPayload, TypeRef fieldTypeRef, CodeGen::LifecycleKind postKind, AstModifierFlags modifiers)
    {
        AssignEncodeContext encodeCtx = buildAssignEncodeContext(codeGen, leftRef, fieldPayload, fieldTypeRef, TokenId::SymEqual);
        if (encodeCtx.target.payload.isAddress() && !CodeGenSafety::isUnborrowableLocalWrite(codeGen, leftRef))
            SWC_RESULT(CodeGenSafety::emitValueBorrowWrite(codeGen, encodeCtx.target.payload.reg, codeGen.typeMgr().get(encodeCtx.target.typeRef).sizeOf(codeGen.ctx())));

        const TypeInfo& targetType   = codeGen.typeMgr().get(encodeCtx.target.opTypeRef);
        const TypeInfo& sourceType   = codeGen.typeMgr().get(fieldTypeRef);
        const bool      remapsFields = targetType.isStructOrAggregateStruct() && sourceType.isStructOrAggregateStruct() && fieldTypeRef != encodeCtx.target.opTypeRef;
        if (!targetType.isStructOrAggregateStruct() && !targetType.isArray())
            return emitAssignEncoded(codeGen, encodeCtx, TokenId::SymEqual);

        const bool hasTargetDrop    = !modifiers.hasAny({AstModifierFlagsE::NoDrop, AstModifierFlagsE::Relocate}) && codeGen.hasLifecycle(encodeCtx.target.opTypeRef, CodeGen::LifecycleKind::Drop);
        const bool hasPostLifecycle = codeGen.hasLifecycle(encodeCtx.target.opTypeRef, postKind);
        if (!hasTargetDrop && !hasPostLifecycle && !remapsFields)
            return emitAssignEncoded(codeGen, encodeCtx, TokenId::SymEqual);

        // The source is the private copy of the right side, never the target itself, so the
        // self-assignment guard a plain assignment needs has nothing to protect here.
        CodeGenNodePayload stableField = fieldPayload;
        stabilizeAssignAddressPayload(codeGen, encodeCtx.target.payload);
        stabilizeAssignAddressPayload(codeGen, stableField);
        encodeCtx.rightPayload = &stableField;

        if (hasTargetDrop)
            SWC_RESULT(codeGen.emitLifecycle(encodeCtx.target.opTypeRef, CodeGen::LifecycleKind::Drop, encodeCtx.target.payload.reg));

        if (remapsFields)
            CodeGenStructHelpers::emitRecordOrTupleCast(codeGen, encodeCtx.target.payload.reg, stableField.reg, fieldTypeRef, encodeCtx.target.opTypeRef);
        else
            SWC_RESULT(emitAssignEncoded(codeGen, encodeCtx, TokenId::SymEqual));

        if (hasPostLifecycle)
            SWC_RESULT(codeGen.emitLifecycle(encodeCtx.target.opTypeRef, postKind, encodeCtx.target.payload.reg));

        return Result::Continue;
    }

    bool destructuringTargetsMayAliasSource(CodeGen& codeGen, AstNodeRef sourceRef, std::span<const SemaHelpers::DestructuringField> fields)
    {
        SmallVector4<const Symbol*> sourcePath;
        if (!SemaHelpers::extractNarrowPath(codeGen.sema(), sourceRef, sourcePath))
            return true;
        auto indirect = [&](const auto& path) {
            return std::ranges::any_of(path, [&](const Symbol* symbol) {
                return codeGen.typeMgr().get(symbol->typeRef()).unwrapAliasTypeOrSelf(codeGen.ctx()).isPointerOrReference();
            });
        };
        if (indirect(sourcePath))
            return true;
        for (const auto& field : fields)
        {
            if (field.ignored)
                continue;
            SmallVector4<const Symbol*> targetPath;
            if (!SemaHelpers::extractNarrowPath(codeGen.sema(), field.bindingRef, targetPath) || indirect(targetPath) || targetPath.front() == sourcePath.front())
                return true;
        }
        return false;
    }

    Result emitAssignDestructuringList(CodeGen& codeGen, const AstAssignList& assignList, AstNodeRef rightRef, const CodeGenNodePayload& rightPayload, TypeRef rightTypeRef, ConstantRef rightCstRef, TokenId assignOp, AstModifierFlags modifiers)
    {
        SWC_ASSERT(assignOp == TokenId::SymEqual);
        const TypeInfo&                              rightType = codeGen.typeMgr().get(rightTypeRef);
        SmallVector<SemaHelpers::DestructuringField> fields;
        SWC_RESULT(SemaHelpers::resolveDestructuringPattern(codeGen.sema(), fields, assignList.nodeRef(codeGen.ast()), rightTypeRef, rightCstRef));
        const SymbolVariable* sourceStorage  = rightPayload.runtimeStorageSym ? rightPayload.runtimeStorageSym : codeGen.runtimeStorageSymbol(rightRef);
        const bool            movesTemporary = sourceStorage && codeGen.hasTemporaryDrop(*sourceStorage);
        const bool            movesSource    = modifiers.hasAny({AstModifierFlagsE::Move, AstModifierFlagsE::Relocate});
        const bool            copiesSource   = !movesSource && CodeGenStructHelpers::destructuringSourceIsLValue(codeGen, rightRef);
        if (fields.empty())
            return Result::Continue;
        const bool                   ownsSnapshot = copiesSource && destructuringTargetsMayAliasSource(codeGen, rightRef, fields.span());
        const CodeGen::LifecycleKind postKind     = copiesSource && !ownsSnapshot ? CodeGen::LifecycleKind::PostCopy : CodeGen::LifecycleKind::PostMove;
        MicroReg                     source       = MicroReg::invalid();
        if (!rightCstRef.isValid() || movesTemporary || movesSource)
        {
            source = materializeDestructuringSourceCopy(codeGen, rightPayload, rightType);
            // Copy selected values before dropping any destination: a target can alias a source
            // field whose storage or resources another target is about to replace.
            if (ownsSnapshot)
            {
                for (const auto& field : fields)
                {
                    if (!field.ignored && codeGen.hasLifecycle(field.typeRef, CodeGen::LifecycleKind::PostCopy))
                        SWC_RESULT(codeGen.emitLifecycle(field.typeRef, CodeGen::LifecycleKind::PostCopy, codeGen.offsetAddressReg(source, static_cast<uint32_t>(field.offset))));
                }
            }
            else if (movesSource && !movesTemporary && codeGen.hasLifecycle(rightTypeRef, CodeGen::LifecycleKind::PostMove))
                SWC_RESULT(codeGen.emitLifecycle(rightTypeRef, CodeGen::LifecycleKind::PostMove, source));
            if (movesSource && !movesTemporary && rightPayload.isAddress())
            {
                if (!modifiers.has(AstModifierFlagsE::Relocate) && codeGen.hasLifecycle(rightTypeRef, CodeGen::LifecycleKind::Drop))
                    SWC_RESULT(CodeGenFunctionHelpers::emitMovedFromDefaultValue(codeGen, rightTypeRef, rightPayload.reg));
                else if (CodeGenSafety::hasLifecycleInvalidate(codeGen))
                    SWC_RESULT(CodeGenSafety::emitLifecycleInvalidate(codeGen, rightPayload.reg, rightTypeRef, rightRef));
            }
        }
        for (const auto& field : fields)
        {
            if (field.ignored)
                continue;
            CodeGenNodePayload fieldPayload;
            TypeRef            fieldType  = field.typeRef;
            const TypeRef      targetType = resolveAssignTarget(codeGen, field.bindingRef).opTypeRef;
            ConstantRef        constant   = field.constantRef;
            if (constant.isValid() && fieldType != targetType)
            {
                SWC_RESULT(Cast::castConstant(codeGen.sema(), constant, constant, targetType, field.bindingRef, CastKind::Assignment));
                if (constant.isValid())
                    fieldType = targetType;
            }
            if (constant.isValid())
                SWC_INTERNAL_CHECK(CodeGenCallHelpers::materializeTypedConstantPayload(codeGen, fieldPayload, fieldType, constant));
            else
            {
                fieldPayload.typeRef = fieldType;
                fieldPayload.setIsAddress();
                fieldPayload.reg = codeGen.offsetAddressReg(source, static_cast<uint32_t>(field.offset));
            }
            SWC_RESULT(emitAssignDestructuringField(codeGen, field.bindingRef, fieldPayload, fieldType, postKind, modifiers));
        }
        if (movesTemporary || movesSource)
        {
            const MicroReg remainder = movesTemporary ? codeGen.resolveLocalStackPayload(*sourceStorage).reg : source;
            SWC_RESULT(CodeGenStructHelpers::emitDropDestructuringRemainder(codeGen, remainder, fields.span()));
            if (movesTemporary)
                codeGen.cancelTemporaryDrop(*sourceStorage);
        }
        return Result::Continue;
    }
}

Result AstAssignStmt::codeGenPostNode(CodeGen& codeGen) const
{
    const auto* assignPayload = codeGen.sema().semaPayload<AssignSpecOpPayload>(codeGen.curNodeRef());
    if (assignPayload && assignPayload->calledFn != nullptr)
    {
        if (assignPayload->calledFn->specOpKind() == SpecOpKind::OpSet ||
            assignPayload->calledFn->specOpKind() == SpecOpKind::OpSetLiteral ||
            assignPayload->calledFn->specOpKind() == SpecOpKind::OpAssign ||
            assignPayload->calledFn->specOpKind() == SpecOpKind::OpIndexSet ||
            assignPayload->calledFn->specOpKind() == SpecOpKind::OpIndexAssign)
            return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid(), assignPayload->calledFn);
    }

    const Token&              tok         = codeGen.token(codeRef());
    const CodeGenNodePayload* leftPayload = codeGen.safePayload(nodeLeftRef);

    const SourceCodeRef leftSourceCodeRef = leftPayload && leftPayload->sourceCodeRef.isValid() ? leftPayload->sourceCodeRef : codeGen.node(nodeLeftRef).codeRef();

    const ScopedDebugSource debugSource(codeGen.builder(), leftSourceCodeRef);

    CodeGenNodePayload rightPayload         = codeGen.payload(nodeRightRef);
    const SemaNodeView rightView            = codeGen.viewTypeConstant(nodeRightRef);
    const TypeRef      originalRightTypeRef = rightView.typeRef();
    TypeRef            rightTypeRef         = originalRightTypeRef;
    rightPayload                            = normalizeMoveAssignPayload(codeGen, rightPayload, rightTypeRef, modifierFlags);

    const AstNodeRef leftRef = codeGen.resolvedNodeRef(nodeLeftRef);

    if (leftRef.isValid() && codeGen.node(leftRef).is(AstNodeId::AssignList))
    {
        const auto& assignList = codeGen.node(leftRef).cast<AstAssignList>();
        if (assignList.hasFlag(AstAssignListFlagsE::Destructuring))
            return emitAssignDestructuringList(codeGen, assignList, nodeRightRef, rightPayload, rightTypeRef, rightView.cstRef(), tok.id, modifierFlags);

        return emitAssignList(codeGen, assignList, rightPayload, rightTypeRef, tok.id);
    }

    return emitAssignLifecycle(codeGen, nodeLeftRef, rightPayload, rightTypeRef, originalRightTypeRef, tok.id, modifierFlags, nodeRightRef);
}

SWC_END_NAMESPACE();
