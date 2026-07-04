#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
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
        if (!modifierFlags.hasAny({AstModifierFlagsE::Move, AstModifierFlagsE::MoveRaw}))
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

    using CodeGenTypeHelpers::floatBinaryMicroOp;
    using CodeGenTypeHelpers::intBinaryMicroOp;

    TypeRef unwrapAssignScalarTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return typeRef;
        return codeGen.typeMgr().get(typeRef).unwrapAliasEnum(codeGen.ctx(), typeRef);
    }

    MicroReg materializeAssignPointerIndexReg(CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        operandTypeRef                = unwrapAssignScalarTypeRef(codeGen, operandTypeRef);
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

    void normalizeReferenceAssignTarget(CodeGen& codeGen, CodeGenNodePayload& ioPayload, TypeRef& ioTypeRef)
    {
        if (!ioTypeRef.isValid())
            return;

        const TypeInfo& leftTypeInfo = codeGen.typeMgr().get(ioTypeRef);
        if (!leftTypeInfo.isReference())
            return;

        ioTypeRef         = leftTypeInfo.payloadTypeRef();
        ioPayload.typeRef = ioTypeRef;
        if (ioPayload.isValue())
        {
            ioPayload.setIsAddress();
            return;
        }

        const MicroReg referenceSlotReg = ioPayload.reg;
        ioPayload.reg                   = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegMem(ioPayload.reg, referenceSlotReg, 0, MicroOpBits::B64);
        ioPayload.setIsAddress();
    }

    AssignTarget resolveAssignTarget(CodeGen& codeGen, AstNodeRef leftRef)
    {
        AssignTarget target;
        target.payload = codeGen.payload(leftRef);

        const SemaNodeView leftTypeView = codeGen.viewType(leftRef);
        const TypeRef      leftTypeRef  = target.payload.effectiveTypeRef(leftTypeView.typeRef());
        SWC_ASSERT(leftTypeRef.isValid());

        TypeRef targetTypeRef = leftTypeRef;
        normalizeReferenceAssignTarget(codeGen, target.payload, targetTypeRef);

        if (!codeGen.typeMgr().get(leftTypeRef).isReference())
            SWC_ASSERT(target.payload.isAddress());

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
            CodeGenMemoryHelpers::emitMemCopy(codeGen, targetPayload.reg, rightPayload.reg, encodeCtx.copySize);
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

        const auto&        node          = codeGen.node(codeGen.curNodeRef()).cast<AstAssignStmt>();
        const TypeInfo&    targetType    = codeGen.typeMgr().get(encodeCtx.target.opTypeRef);
        const bool         isSigned      = targetType.isIntLike() && !targetType.isIntLikeUnsigned();
        const TokenId      binaryOp      = Token::assignToBinary(assignOp);
        const MicroOp      op            = intBinaryMicroOp(binaryOp, isSigned);
        const bool         hasSafety     = CodeGenSafety::hasOverflowRuntimeSafety(codeGen);
        MicroBuilder&      builder       = codeGen.builder();
        CodeGenNodePayload targetPayload = encodeCtx.target.payload;
        stabilizeAssignAddressPayload(codeGen, targetPayload);
        const MicroReg leftReg = codeGen.nextVirtualRegisterForType(encodeCtx.target.typeRef);
        builder.emitLoadRegMem(leftReg, targetPayload.reg, 0, encodeCtx.opBits);

        const MicroReg rightReg = CodeGenMemoryHelpers::materializeScalarPayloadForStore(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef, encodeCtx.target.opTypeRef);

        if (assignOp == TokenId::SymLowerLowerEqual || assignOp == TokenId::SymGreaterGreaterEqual)
        {
            SWC_RESULT(CodeGenSafety::emitShiftIntLike(codeGen, node, node.nodeRightRef, leftReg, rightReg, targetType, encodeCtx.opBits, Token::assignToBinary(assignOp), node.modifierFlags.has(AstModifierFlagsE::Wrap)));
        }
        else if (isSigned && (assignOp == TokenId::SymSlashEqual || assignOp == TokenId::SymPercentEqual))
        {
            SWC_RESULT(CodeGenSafety::emitSignedDivOrModIntLike(codeGen, node, leftReg, rightReg, op, encodeCtx.opBits, assignOp == TokenId::SymPercentEqual));
        }
        else
        {
            builder.emitOpBinaryRegReg(leftReg, rightReg, op, encodeCtx.opBits);
            if (hasSafety)
                SWC_RESULT(CodeGenSafety::emitIntArithmeticOverflowCheck(codeGen, node, binaryOp, isSigned));
        }

        builder.emitLoadMemReg(targetPayload.reg, 0, leftReg, encodeCtx.opBits);
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

        const TokenId      binaryOp      = Token::assignToBinary(assignOp);
        const MicroOp      op            = floatBinaryMicroOp(binaryOp);
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

        const uint64_t     stride        = CodeGenTypeHelpers::blockPointerStride(codeGen.ctx(), encodeCtx.target.opTypeRef);
        const MicroReg     leftReg       = codeGen.nextVirtualIntRegister();
        const MicroReg     indexReg      = materializeAssignPointerIndexReg(codeGen, *encodeCtx.rightPayload, encodeCtx.rightTypeRef);
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

    Result emitAssignStructLifecycle(CodeGen& codeGen, AstNodeRef leftRef, const CodeGenNodePayload& originalRightPayload, TypeRef rightTypeRef, TypeRef originalRightTypeRef, TokenId assignOp, AstModifierFlags modifierFlags, AstNodeRef rightRef)
    {
        const AssignEncodeContext encodeCtx = buildAssignEncodeContext(codeGen, leftRef, originalRightPayload, rightTypeRef, assignOp);
        if (assignOp != TokenId::SymEqual)
            return emitAssignEncoded(codeGen, encodeCtx, assignOp);
        if (!encodeCtx.target.opTypeRef.isValid())
            return emitAssignEncoded(codeGen, encodeCtx, assignOp);

        const TypeInfo& targetType = codeGen.typeMgr().get(encodeCtx.target.opTypeRef);
        if (!targetType.isStruct())
            return emitAssignEncoded(codeGen, encodeCtx, assignOp);

        const bool                   isMove            = modifierFlags.hasAny({AstModifierFlagsE::Move, AstModifierFlagsE::MoveRaw});
        const bool                   isMoveRaw         = modifierFlags.has(AstModifierFlagsE::MoveRaw);
        const bool                   skipTargetDrop    = modifierFlags.has(AstModifierFlagsE::NoDrop);
        const CodeGen::LifecycleKind postKind          = isMove ? CodeGen::LifecycleKind::PostMove : CodeGen::LifecycleKind::PostCopy;
        const bool                   hasTargetDrop     = !skipTargetDrop && codeGen.hasLifecycle(encodeCtx.target.opTypeRef, CodeGen::LifecycleKind::Drop);
        const bool                   hasPostLifecycle  = codeGen.hasLifecycle(encodeCtx.target.opTypeRef, postKind);
        const bool                   canResetSource    = isMove && !isMoveRaw && originalRightPayload.isAddress() && canReinitializeMoveSource(codeGen, rightRef, originalRightTypeRef);
        const bool                   shouldResetSource = canResetSource && codeGen.hasLifecycle(rightTypeRef, CodeGen::LifecycleKind::Drop);

        if (!hasTargetDrop && !hasPostLifecycle && !shouldResetSource)
            return emitAssignEncoded(codeGen, encodeCtx, assignOp);

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

        MicroLabelRef doneLabel = MicroLabelRef::invalid();
        if (stableRight.isAddress() && lifecycleCtx.target.payload.isAddress())
        {
            doneLabel = builder.createLabel();
            builder.emitCmpRegReg(lifecycleCtx.target.payload.reg, stableRight.reg, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
        }

        if (hasTargetDrop)
            SWC_RESULT(codeGen.emitLifecycle(encodeCtx.target.opTypeRef, CodeGen::LifecycleKind::Drop, lifecycleCtx.target.payload.reg));

        SWC_RESULT(emitAssignEncoded(codeGen, lifecycleCtx, assignOp));

        if (hasPostLifecycle)
            SWC_RESULT(codeGen.emitLifecycle(encodeCtx.target.opTypeRef, postKind, lifecycleCtx.target.payload.reg));

        if (shouldResetSource)
            SWC_RESULT(CodeGenFunctionHelpers::emitStructDefaultValue(codeGen, rightTypeRef, stableRight.reg));

        if (doneLabel.isValid())
            builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    Result emitAssign(CodeGen& codeGen, AstNodeRef leftRef, const CodeGenNodePayload& rightPayload, TypeRef rightTypeRef, TokenId assignOp)
    {
        const AssignEncodeContext encodeCtx = buildAssignEncodeContext(codeGen, leftRef, rightPayload, rightTypeRef, assignOp);
        return emitAssignEncoded(codeGen, encodeCtx, assignOp);
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

    MicroReg materializeDestructuringSourceCopy(CodeGen& codeGen, const CodeGenNodePayload& rightPayload, TypeRef rightTypeRef)
    {
        const TypeInfo& rightType = codeGen.typeMgr().get(rightTypeRef);
        const uint64_t  copySize  = rightType.sizeOf(codeGen.ctx());
        SWC_ASSERT(copySize > 0);
        SWC_ASSERT(copySize <= std::numeric_limits<uint32_t>::max());

        const CodeGenNodePayload* storagePayload = codeGen.safePayload(codeGen.curNodeRef());
        SWC_ASSERT(storagePayload && storagePayload->runtimeStorageSym != nullptr);

        const MicroReg storageReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        CodeGenMemoryHelpers::storePayloadToAddress(codeGen, storageReg, rightPayload, static_cast<uint32_t>(copySize));
        return storageReg;
    }

    Result emitAssignDestructuringList(CodeGen& codeGen, const AstAssignList& assignList, const CodeGenNodePayload& rightPayload, TypeRef rightTypeRef, TokenId assignOp)
    {
        SmallVector<AstNodeRef> leftRefs;
        codeGen.ast().appendNodes(leftRefs, assignList.spanChildrenRef);

        SWC_ASSERT(assignOp == TokenId::SymEqual);
        const TypeInfo& rightType = codeGen.typeMgr().get(rightTypeRef);
        SWC_ASSERT(rightType.isStruct());

        const MicroReg sourceReg = materializeDestructuringSourceCopy(codeGen, rightPayload, rightTypeRef);
        const auto&    fields    = rightType.payloadSymStruct().fields();

        for (size_t i = 0; i < leftRefs.size(); i++)
        {
            const AstNodeRef leftRef = leftRefs[i];
            if (leftRef.isInvalid())
                continue;
            if (codeGen.node(leftRef).is(AstNodeId::AssignIgnore))
                continue;

            SWC_ASSERT(i < fields.size() && fields[i]);
            const SymbolVariable& field = *fields[i];

            CodeGenNodePayload fieldPayload;
            fieldPayload.typeRef = field.typeRef();
            fieldPayload.setIsAddress();
            fieldPayload.reg = field.offset() ? codeGen.offsetAddressReg(sourceReg, field.offset()) : sourceReg;

            SWC_RESULT(emitAssign(codeGen, leftRef, fieldPayload, field.typeRef(), assignOp));
        }

        return Result::Continue;
    }
}

Result AstAssignStmt::codeGenPostNode(CodeGen& codeGen) const
{
    const auto* assignPayload = codeGen.sema().semaPayload<AssignSpecOpPayload>(codeGen.curNodeRef());
    if (assignPayload && assignPayload->calledFn != nullptr)
    {
        codeGen.sema().setSymbol(codeGen.curNodeRef(), assignPayload->calledFn);
        if (assignPayload->calledFn->specOpKind() == SpecOpKind::OpSet ||
            assignPayload->calledFn->specOpKind() == SpecOpKind::OpSetLiteral ||
            assignPayload->calledFn->specOpKind() == SpecOpKind::OpAssign ||
            assignPayload->calledFn->specOpKind() == SpecOpKind::OpIndexSet ||
            assignPayload->calledFn->specOpKind() == SpecOpKind::OpIndexAssign)
            return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid());
    }

    const Token&       tok                  = codeGen.token(codeRef());
    CodeGenNodePayload rightPayload         = codeGen.payload(nodeRightRef);
    const SemaNodeView rightView            = codeGen.viewType(nodeRightRef);
    const TypeRef      originalRightTypeRef = rightView.typeRef();
    TypeRef            rightTypeRef         = originalRightTypeRef;
    rightPayload                            = normalizeMoveAssignPayload(codeGen, rightPayload, rightTypeRef, modifierFlags);
    const AstNodeRef leftRef                = codeGen.viewZero(nodeLeftRef).nodeRef();

    if (leftRef.isValid() && codeGen.node(leftRef).is(AstNodeId::AssignList))
    {
        const auto& assignList = codeGen.node(leftRef).cast<AstAssignList>();
        if (assignList.hasFlag(AstAssignListFlagsE::Destructuring))
            return emitAssignDestructuringList(codeGen, assignList, rightPayload, rightTypeRef, tok.id);
        return emitAssignList(codeGen, assignList, rightPayload, rightTypeRef, tok.id);
    }

    return emitAssignStructLifecycle(codeGen, nodeLeftRef, rightPayload, rightTypeRef, originalRightTypeRef, tok.id, modifierFlags, nodeRightRef);
}

SWC_END_NAMESPACE();
