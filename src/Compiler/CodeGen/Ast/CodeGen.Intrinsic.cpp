#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_RUNTIME_EXCEPTION_KIND_ASSERT = 3;

    uint64_t addIntrinsicPayloadToConstantManagerAndGetAddress(CodeGen& codeGen, ByteSpan payload)
    {
        const std::string_view stored = codeGen.cstMgr().addPayloadBuffer(asStringView(payload));
        return reinterpret_cast<uint64_t>(stored.data());
    }

    CodeGenNodePayload makeAddressPayloadFromConstant(CodeGen& codeGen, ConstantRef cstRef)
    {
        const ConstantValue& cst = codeGen.cstMgr().get(cstRef);
        SWC_ASSERT(cst.isStruct() || cst.isArray());

        const ByteSpan bytes = cst.isStruct() ? cst.getStruct() : cst.getArray();
        const uint64_t addr  = cst.isStruct() ? reinterpret_cast<uint64_t>(bytes.data()) : addIntrinsicPayloadToConstantManagerAndGetAddress(codeGen, bytes);

        CodeGenNodePayload payload;
        payload.typeRef = cst.typeRef();
        payload.reg     = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegPtrReloc(payload.reg, addr, cstRef);
        payload.setIsAddress();
        return payload;
    }

    enum class BitCountKind
    {
        Nz,
        Tz,
        Lz,
    };

    enum class FloatRoundKind : uint8_t
    {
        Floor = 1,
        Ceil  = 2,
        Trunc = 3,
    };

    MicroOpBits intrinsicNumericOpBits(const TypeInfo& typeInfo)
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

        return MicroOpBits::Zero;
    }

    void loadIntrinsicNumericOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        outReg                        = codeGen.nextVirtualRegisterForType(operandTypeRef);
        const TypeInfo&   operandType = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits opBits      = intrinsicNumericOpBits(operandType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroBuilder& builder = codeGen.builder();
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    void convertIntrinsicNumericOperand(MicroReg& outReg, CodeGen& codeGen, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (srcTypeRef == dstTypeRef)
            return;

        const TypeInfo&   srcType = codeGen.typeMgr().get(srcTypeRef);
        const TypeInfo&   dstType = codeGen.typeMgr().get(dstTypeRef);
        const MicroOpBits srcBits = intrinsicNumericOpBits(srcType);
        const MicroOpBits dstBits = intrinsicNumericOpBits(dstType);
        SWC_ASSERT(srcBits != MicroOpBits::Zero);
        SWC_ASSERT(dstBits != MicroOpBits::Zero);

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

            if (getNumBits(srcBits) > getNumBits(dstBits))
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

        SWC_INTERNAL_ERROR();
    }

    void materializeIntrinsicNumericOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, TypeRef resultTypeRef)
    {
        loadIntrinsicNumericOperand(outReg, codeGen, operandPayload, operandTypeRef);
        convertIntrinsicNumericOperand(outReg, codeGen, operandTypeRef, resultTypeRef);
    }

    CodeGenNodePayload resolveIntrinsicRuntimeStoragePayload(CodeGen& codeGen, const SymbolVariable& storageSym)
    {
        if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(storageSym))
            return *symbolPayload;

        SWC_ASSERT(storageSym.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
        SWC_ASSERT(codeGen.localStackBaseReg().isValid());

        CodeGenNodePayload localPayload;
        localPayload.typeRef = storageSym.typeRef();
        localPayload.setIsAddress();
        if (!storageSym.offset())
        {
            localPayload.reg = codeGen.localStackBaseReg();
        }
        else
        {
            MicroBuilder& builder = codeGen.builder();
            localPayload.reg      = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(localPayload.reg, codeGen.localStackBaseReg(), MicroOpBits::B64);
            builder.emitOpBinaryRegImm(localPayload.reg, ApInt(storageSym.offset(), 64), MicroOp::Add, MicroOpBits::B64);
        }

        codeGen.setVariablePayload(storageSym, localPayload);
        return localPayload;
    }

    MicroReg intrinsicRuntimeStorageAddressReg(CodeGen& codeGen)
    {
        const auto* payload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->runtimeStorageSym != nullptr);
        const CodeGenNodePayload storagePayload = resolveIntrinsicRuntimeStoragePayload(codeGen, *(payload->runtimeStorageSym));
        SWC_ASSERT(storagePayload.isAddress());
        return storagePayload.reg;
    }

    bool tryGetIntrinsicMemSizeConst(CodeGen& codeGen, AstNodeRef sizeRef, uint32_t& outSizeInBytes)
    {
        outSizeInBytes              = 0;
        const SemaNodeView sizeView = codeGen.viewConstant(sizeRef);
        if (!sizeView.hasConstant())
            return false;

        const ConstantValue& sizeCst = codeGen.cstMgr().get(sizeView.cstRef());
        if (!sizeCst.isInt())
            return false;

        const ApsInt& sizeInt = sizeCst.getInt();
        if (!sizeInt.fit64())
            return false;

        const uint64_t sizeU64 = sizeInt.as64();
        if (sizeU64 > std::numeric_limits<uint32_t>::max())
            return false;

        outSizeInBytes = static_cast<uint32_t>(sizeU64);
        return true;
    }

    bool isIntrinsicIntConstantZero(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        const SemaNodeView valueView = codeGen.viewConstant(nodeRef);
        if (!valueView.hasConstant())
            return false;

        const ConstantValue& valueCst = codeGen.cstMgr().get(valueView.cstRef());
        if (!valueCst.isInt())
            return false;

        return valueCst.getInt().isZero();
    }

    MicroReg materializeIntrinsicIntArgReg(CodeGen& codeGen, const CodeGenNodePayload& payload, MicroOpBits opBits)
    {
        const MicroReg outReg = codeGen.nextVirtualIntRegister();
        if (payload.isAddress())
            codeGen.builder().emitLoadRegMem(outReg, payload.reg, 0, opBits);
        else
            codeGen.builder().emitLoadRegReg(outReg, payload.reg, opBits);
        return outReg;
    }

    TypeRef intrinsicOperandTypeRef(CodeGen& codeGen, AstNodeRef nodeRef, const CodeGenNodePayload& payload)
    {
        if (payload.typeRef.isValid())
            return payload.typeRef;
        return codeGen.viewType(nodeRef).typeRef();
    }

    Result codeGenAtomicBinaryRmw(CodeGen& codeGen, const AstIntrinsicCallExpr& node, MicroOp op)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 2);

        const AstNodeRef          ptrRef         = children[0];
        const AstNodeRef          valueRef       = children[1];
        const CodeGenNodePayload& ptrPayload     = codeGen.payload(ptrRef);
        const CodeGenNodePayload& valuePayload   = codeGen.payload(valueRef);
        const TypeRef             valueTypeRef   = intrinsicOperandTypeRef(codeGen, valueRef, valuePayload);
        const TypeRef             resultTypeRef  = codeGen.curViewType().typeRef();
        const TypeInfo&           resultTypeInfo = codeGen.typeMgr().get(resultTypeRef);
        const MicroOpBits         opBits         = intrinsicNumericOpBits(resultTypeInfo);
        MicroBuilder&             builder        = codeGen.builder();

        SWC_ASSERT(resultTypeInfo.isIntLike());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        const MicroReg ptrReg = materializeIntrinsicIntArgReg(codeGen, ptrPayload, MicroOpBits::B64);

        MicroReg valueReg = MicroReg::invalid();
        materializeIntrinsicNumericOperand(valueReg, codeGen, valuePayload, valueTypeRef, resultTypeRef);

        const MicroReg expectedReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(expectedReg, ptrReg, 0, opBits);

        const MicroLabelRef retryLabel = builder.createLabel();
        const MicroLabelRef doneLabel  = builder.createLabel();
        builder.placeLabel(retryLabel);

        const MicroReg desiredReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(desiredReg, expectedReg, opBits);
        builder.emitOpBinaryRegReg(desiredReg, valueReg, op, opBits);

        const MicroReg observedReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(observedReg, expectedReg, opBits);
        builder.emitOpTernaryRegRegReg(observedReg, ptrReg, desiredReg, MicroOp::CompareExchange, opBits);
        builder.emitCmpRegReg(observedReg, expectedReg, opBits);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
        builder.emitLoadRegReg(expectedReg, observedReg, opBits);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, retryLabel);
        builder.placeLabel(doneLabel);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        resultPayload.reg                 = expectedReg;
        return Result::Continue;
    }

    Result codeGenAtomicExchange(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 2);

        const AstNodeRef          ptrRef         = children[0];
        const AstNodeRef          valueRef       = children[1];
        const CodeGenNodePayload& ptrPayload     = codeGen.payload(ptrRef);
        const CodeGenNodePayload& valuePayload   = codeGen.payload(valueRef);
        const TypeRef             valueTypeRef   = intrinsicOperandTypeRef(codeGen, valueRef, valuePayload);
        const TypeRef             resultTypeRef  = codeGen.curViewType().typeRef();
        const TypeInfo&           resultTypeInfo = codeGen.typeMgr().get(resultTypeRef);
        const MicroOpBits         opBits         = intrinsicNumericOpBits(resultTypeInfo);
        MicroBuilder&             builder        = codeGen.builder();

        SWC_ASSERT(resultTypeInfo.isIntLike());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        const MicroReg ptrReg = materializeIntrinsicIntArgReg(codeGen, ptrPayload, MicroOpBits::B64);

        MicroReg valueReg = MicroReg::invalid();
        materializeIntrinsicNumericOperand(valueReg, codeGen, valuePayload, valueTypeRef, resultTypeRef);
        builder.emitOpBinaryMemReg(ptrReg, 0, valueReg, MicroOp::Exchange, opBits);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        resultPayload.reg                 = valueReg;
        return Result::Continue;
    }

    Result codeGenAtomicCompareExchange(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 3);

        const AstNodeRef          ptrRef          = children[0];
        const AstNodeRef          compareRef      = children[1];
        const AstNodeRef          exchangeRef     = children[2];
        const CodeGenNodePayload& ptrPayload      = codeGen.payload(ptrRef);
        const CodeGenNodePayload& comparePayload  = codeGen.payload(compareRef);
        const CodeGenNodePayload& exchangePayload = codeGen.payload(exchangeRef);
        const TypeRef             compareTypeRef  = intrinsicOperandTypeRef(codeGen, compareRef, comparePayload);
        const TypeRef             exchangeTypeRef = intrinsicOperandTypeRef(codeGen, exchangeRef, exchangePayload);
        const TypeRef             resultTypeRef   = codeGen.curViewType().typeRef();
        const TypeInfo&           resultTypeInfo  = codeGen.typeMgr().get(resultTypeRef);
        const MicroOpBits         opBits          = intrinsicNumericOpBits(resultTypeInfo);
        MicroBuilder&             builder         = codeGen.builder();

        SWC_ASSERT(resultTypeInfo.isIntLike());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        const MicroReg ptrReg = materializeIntrinsicIntArgReg(codeGen, ptrPayload, MicroOpBits::B64);

        MicroReg compareReg  = MicroReg::invalid();
        MicroReg exchangeReg = MicroReg::invalid();
        materializeIntrinsicNumericOperand(compareReg, codeGen, comparePayload, compareTypeRef, resultTypeRef);
        materializeIntrinsicNumericOperand(exchangeReg, codeGen, exchangePayload, exchangeTypeRef, resultTypeRef);
        builder.emitOpTernaryRegRegReg(compareReg, ptrReg, exchangeReg, MicroOp::CompareExchange, opBits);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        resultPayload.reg                 = compareReg;
        return Result::Continue;
    }

    Result codeGenMemCopyIntrinsic(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 3);

        const AstNodeRef          dstRef     = children[0];
        const AstNodeRef          srcRef     = children[1];
        const AstNodeRef          sizeRef    = children[2];
        const CodeGenNodePayload& dstPayload = codeGen.payload(dstRef);
        const CodeGenNodePayload& srcPayload = codeGen.payload(srcRef);

        uint32_t sizeInBytes = 0;
        if (!tryGetIntrinsicMemSizeConst(codeGen, sizeRef, sizeInBytes))
            return CodeGenFunctionHelpers::codeGenCallExprCommon(codeGen, node.nodeExprRef);

        const MicroReg dstReg = materializeIntrinsicIntArgReg(codeGen, dstPayload, MicroOpBits::B64);
        const MicroReg srcReg = materializeIntrinsicIntArgReg(codeGen, srcPayload, MicroOpBits::B64);
        CodeGenMemoryHelpers::emitMemCopy(codeGen, dstReg, srcReg, sizeInBytes);
        return Result::Continue;
    }

    Result codeGenMemSetIntrinsic(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 3);

        const AstNodeRef          dstRef       = children[0];
        const AstNodeRef          valueRef     = children[1];
        const AstNodeRef          sizeRef      = children[2];
        const CodeGenNodePayload& dstPayload   = codeGen.payload(dstRef);
        const CodeGenNodePayload& valuePayload = codeGen.payload(valueRef);

        uint32_t sizeInBytes = 0;
        if (!tryGetIntrinsicMemSizeConst(codeGen, sizeRef, sizeInBytes))
            return CodeGenFunctionHelpers::codeGenCallExprCommon(codeGen, node.nodeExprRef);

        const MicroReg dstReg = materializeIntrinsicIntArgReg(codeGen, dstPayload, MicroOpBits::B64);
        if (isIntrinsicIntConstantZero(codeGen, valueRef))
        {
            CodeGenMemoryHelpers::emitMemZero(codeGen, dstReg, sizeInBytes);
            return Result::Continue;
        }

        const MicroReg valueReg = materializeIntrinsicIntArgReg(codeGen, valuePayload, MicroOpBits::B8);
        CodeGenMemoryHelpers::emitMemSet(codeGen, dstReg, valueReg, sizeInBytes);
        return Result::Continue;
    }

    Result codeGenMemMoveIntrinsic(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 3);

        const AstNodeRef          dstRef     = children[0];
        const AstNodeRef          srcRef     = children[1];
        const AstNodeRef          sizeRef    = children[2];
        const CodeGenNodePayload& dstPayload = codeGen.payload(dstRef);
        const CodeGenNodePayload& srcPayload = codeGen.payload(srcRef);

        uint32_t sizeInBytes = 0;
        if (!tryGetIntrinsicMemSizeConst(codeGen, sizeRef, sizeInBytes))
            return CodeGenFunctionHelpers::codeGenCallExprCommon(codeGen, node.nodeExprRef);

        const MicroReg dstReg = materializeIntrinsicIntArgReg(codeGen, dstPayload, MicroOpBits::B64);
        const MicroReg srcReg = materializeIntrinsicIntArgReg(codeGen, srcPayload, MicroOpBits::B64);
        CodeGenMemoryHelpers::emitMemMove(codeGen, dstReg, srcReg, sizeInBytes);
        return Result::Continue;
    }

    Result codeGenMemCmpIntrinsic(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 3);

        const AstNodeRef          leftRef      = children[0];
        const AstNodeRef          rightRef     = children[1];
        const AstNodeRef          sizeRef      = children[2];
        const CodeGenNodePayload& leftPayload  = codeGen.payload(leftRef);
        const CodeGenNodePayload& rightPayload = codeGen.payload(rightRef);

        uint32_t sizeInBytes = 0;
        if (!tryGetIntrinsicMemSizeConst(codeGen, sizeRef, sizeInBytes))
            return CodeGenFunctionHelpers::codeGenCallExprCommon(codeGen, node.nodeExprRef);

        const MicroReg            leftReg       = materializeIntrinsicIntArgReg(codeGen, leftPayload, MicroOpBits::B64);
        const MicroReg            rightReg      = materializeIntrinsicIntArgReg(codeGen, rightPayload, MicroOpBits::B64);
        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        CodeGenMemoryHelpers::emitMemCompare(codeGen, resultPayload.reg, leftReg, rightReg, sizeInBytes);
        return Result::Continue;
    }

    Result codeGenMakeAny(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 2);

        const AstNodeRef          ptrRef        = children[0];
        const AstNodeRef          typeRef       = children[1];
        const CodeGenNodePayload& ptrPayload    = codeGen.payload(ptrRef);
        const CodeGenNodePayload& typePayload   = codeGen.payload(typeRef);
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();

        const MicroReg ptrReg          = materializeIntrinsicIntArgReg(codeGen, ptrPayload, MicroOpBits::B64);
        const MicroReg typeInfoReg     = materializeIntrinsicIntArgReg(codeGen, typePayload, MicroOpBits::B64);
        const MicroReg runtimeValueReg = intrinsicRuntimeStorageAddressReg(codeGen);
        MicroBuilder&  builder         = codeGen.builder();
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Any, value), ptrReg, MicroOpBits::B64);
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Any, type), typeInfoReg, MicroOpBits::B64);

        CodeGenNodePayload& payload = codeGen.setPayloadAddress(codeGen.curNodeRef(), resultTypeRef);
        payload.reg                 = runtimeValueReg;
        return Result::Continue;
    }

    Result codeGenMakeSlice(CodeGen& codeGen, const AstIntrinsicCall& node, bool forString)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 2);

        const AstNodeRef          ptrRef        = children[0];
        const AstNodeRef          sizeRef       = children[1];
        const CodeGenNodePayload& ptrPayload    = codeGen.payload(ptrRef);
        const CodeGenNodePayload& sizePayload   = codeGen.payload(sizeRef);
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();

        MicroBuilder& builder = codeGen.builder();

        const MicroReg ptrReg = codeGen.nextVirtualIntRegister();
        if (ptrPayload.isAddress())
            builder.emitLoadRegMem(ptrReg, ptrPayload.reg, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(ptrReg, ptrPayload.reg, MicroOpBits::B64);

        const MicroReg sizeReg = codeGen.nextVirtualIntRegister();
        if (sizePayload.isAddress())
            builder.emitLoadRegMem(sizeReg, sizePayload.reg, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(sizeReg, sizePayload.reg, MicroOpBits::B64);

        const MicroReg runtimeStorageReg = intrinsicRuntimeStorageAddressReg(codeGen);
        const uint64_t countOffset       = forString ? offsetof(Runtime::String, length) : offsetof(Runtime::Slice<std::byte>, count);
        builder.emitLoadMemReg(runtimeStorageReg, offsetof(Runtime::Slice<std::byte>, ptr), ptrReg, MicroOpBits::B64);
        builder.emitLoadMemReg(runtimeStorageReg, countOffset, sizeReg, MicroOpBits::B64);

        CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        payload.reg                 = runtimeStorageReg;
        return Result::Continue;
    }

    MicroReg materializeCountLikeBaseReg(const CodeGen& codeGen, const CodeGenNodePayload& payload)
    {
        SWC_UNUSED(codeGen);
        return payload.reg;
    }

    Result codeGenCountOf(CodeGen& codeGen, AstNodeRef exprRef)
    {
        MicroBuilder&             builder       = codeGen.builder();
        const SemaNodeView        exprView      = codeGen.viewType(exprRef);
        const CodeGenNodePayload& exprPayload   = codeGen.payload(exprRef);
        const TypeInfo* const     exprType      = exprView.type();
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        SWC_ASSERT(exprType != nullptr);

        if (exprType->isIntUnsigned())
        {
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
            const uint32_t            intBits       = exprType->payloadIntBits() ? exprType->payloadIntBits() : 64;
            const MicroOpBits         opBits        = microOpBitsFromBitWidth(intBits);
            if (exprPayload.isAddress())
                builder.emitLoadRegMem(resultPayload.reg, exprPayload.reg, 0, opBits);
            else
                builder.emitLoadRegReg(resultPayload.reg, exprPayload.reg, opBits);
            return Result::Continue;
        }

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        const MicroReg            baseReg       = materializeCountLikeBaseReg(codeGen, exprPayload);
        if (exprType->isCString())
        {
            const MicroReg cstrReg = codeGen.nextVirtualIntRegister();
            if (exprPayload.isAddress())
                builder.emitLoadRegMem(cstrReg, baseReg, 0, MicroOpBits::B64);
            else
                builder.emitLoadRegReg(cstrReg, baseReg, MicroOpBits::B64);

            const MicroReg scanReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(scanReg, cstrReg, MicroOpBits::B64);
            builder.emitClearReg(resultPayload.reg, MicroOpBits::B64);

            const MicroLabelRef loopLabel = builder.createLabel();
            const MicroLabelRef doneLabel = builder.createLabel();
            builder.placeLabel(loopLabel);

            const MicroReg charReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(charReg, scanReg, 0, MicroOpBits::B8);
            builder.emitCmpRegImm(charReg, ApInt(0, 64), MicroOpBits::B8);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
            builder.emitOpBinaryRegImm(scanReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(resultPayload.reg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopLabel);
            builder.placeLabel(doneLabel);
            return Result::Continue;
        }

        if (exprType->isString())
        {
            builder.emitLoadRegMem(resultPayload.reg, baseReg, offsetof(Runtime::String, length), MicroOpBits::B64);
            return Result::Continue;
        }

        if (exprType->isSlice() || exprType->isAnyVariadic())
        {
            builder.emitLoadRegMem(resultPayload.reg, baseReg, offsetof(Runtime::Slice<std::byte>, count), MicroOpBits::B64);
            return Result::Continue;
        }

        SWC_INTERNAL_ERROR();
    }

    Result codeGenDataOf(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(!children.empty());

        const AstNodeRef          exprRef     = children[0];
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        const CodeGenNodePayload& payload     = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        MicroBuilder&             builder     = codeGen.builder();

        if (exprView.type() && (exprView.type()->isString() || exprView.type()->isSlice() || exprView.type()->isAny()))
            builder.emitLoadRegMem(payload.reg, exprPayload.reg, 0, MicroOpBits::B64);
        else if (exprView.type() && exprView.type()->isArray())
            builder.emitLoadRegReg(payload.reg, exprPayload.reg, MicroOpBits::B64);
        else if (exprPayload.isAddress())
            builder.emitLoadRegMem(payload.reg, exprPayload.reg, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(payload.reg, exprPayload.reg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenKindOf(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(!children.empty());

        const AstNodeRef          exprRef     = children[0];
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        CodeGenNodePayload&       result      = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        MicroBuilder&             builder     = codeGen.builder();
        const MicroReg            anyBaseReg  = exprPayload.reg;
        result.reg                            = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(result.reg, anyBaseReg, offsetof(Runtime::Any, type), MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenAssert(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        MicroBuilder&                   builder    = codeGen.builder();
        const Runtime::BuildCfgBackend& backendCfg = builder.backendBuildCfg();
        if (!backendCfg.emitAssert)
            return Result::Continue;

        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        if (children.empty())
            return Result::Continue;

        const AstNodeRef          exprRef     = children[0];
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        const MicroReg            condReg     = codeGen.nextVirtualIntRegister();
        constexpr auto            condBits    = MicroOpBits::B8;

        if (exprPayload.isAddress())
            builder.emitLoadRegMem(condReg, exprPayload.reg, 0, condBits);
        else
            builder.emitLoadRegReg(condReg, exprPayload.reg, condBits);

        const auto* payload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->runtimeFunctionSymbol != nullptr);

        auto&                      raiseExceptionFunction = *payload->runtimeFunctionSymbol;
        const CallConvKind         callConvKind           = raiseExceptionFunction.callConvKind();
        const CallConv&            callConv               = CallConv::get(callConvKind);
        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(3);

        const Runtime::String nullRuntimeString{};
        const ByteSpan        nullRuntimeStringBytes = asByteSpan(reinterpret_cast<const std::byte*>(&nullRuntimeString), sizeof(nullRuntimeString));
        const ConstantRef     nullMessageRef         = codeGen.cstMgr().addConstant(codeGen.ctx(), ConstantValue::makeStruct(codeGen.ctx(), codeGen.typeMgr().typeString(), nullRuntimeStringBytes));
        const auto        nullMessage    = makeAddressPayloadFromConstant(codeGen, nullMessageRef);

        const ConstantRef sourceLocRef = ConstantHelpers::makeSourceCodeLocation(codeGen.sema(), node);
        const auto        sourceLoc    = makeAddressPayloadFromConstant(codeGen, sourceLocRef);

        ABICall::PreparedArg messageArg;
        messageArg.srcReg = nullMessage.reg;
        {
            const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.typeMgr().typeString(), ABITypeNormalize::Usage::Argument);
            messageArg.kind        = ABICall::PreparedArgKind::Direct;
            messageArg.isFloat     = normalizedArg.isFloat;
            messageArg.numBits     = normalizedArg.numBits;
            messageArg.isAddressed = false;
        }
        preparedArgs.push_back(messageArg);

        ABICall::PreparedArg locationArg;
        locationArg.srcReg = sourceLoc.reg;
        {
            const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.typeMgr().structSourceCodeLocation(), ABITypeNormalize::Usage::Argument);
            locationArg.kind        = ABICall::PreparedArgKind::Direct;
            locationArg.isFloat     = normalizedArg.isFloat;
            locationArg.numBits     = normalizedArg.numBits;
            locationArg.isAddressed = false;
        }
        preparedArgs.push_back(locationArg);

        ABICall::PreparedArg kindArg;
        kindArg.srcReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(kindArg.srcReg, ApInt(K_RUNTIME_EXCEPTION_KIND_ASSERT, 64), MicroOpBits::B64);
        kindArg.kind        = ABICall::PreparedArgKind::Direct;
        kindArg.isFloat     = false;
        kindArg.numBits     = 64;
        kindArg.isAddressed = false;
        preparedArgs.push_back(kindArg);

        const MicroLabelRef doneLabel = builder.createLabel();
        builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, doneLabel);
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        ABICall::callLocal(builder, callConvKind, &raiseExceptionFunction, preparedCall);
        builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    Result codeGenSqrt(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 1);

        const AstNodeRef          exprRef       = children[0];
        const CodeGenNodePayload& exprPayload   = codeGen.payload(exprRef);
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType    = codeGen.typeMgr().get(resultTypeRef);
        SWC_ASSERT(resultType.isFloat());

        const uint32_t    floatBits = resultType.payloadFloatBits() ? resultType.payloadFloatBits() : 64;
        const MicroOpBits opBits    = microOpBitsFromBitWidth(floatBits);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroBuilder&       builder       = codeGen.builder();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        resultPayload.reg                 = codeGen.nextVirtualRegisterForType(resultTypeRef);
        if (exprPayload.isAddress())
            builder.emitLoadRegMem(resultPayload.reg, exprPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(resultPayload.reg, exprPayload.reg, opBits);
        builder.emitOpBinaryRegReg(resultPayload.reg, resultPayload.reg, MicroOp::FloatSqrt, opBits);
        return Result::Continue;
    }

    Result codeGenAbs(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 1);

        const AstNodeRef          exprRef       = children[0];
        const CodeGenNodePayload& exprPayload   = codeGen.payload(exprRef);
        const SemaNodeView        exprView      = codeGen.viewType(exprRef);
        const TypeRef             exprTypeRef   = exprPayload.typeRef.isValid() ? exprPayload.typeRef : exprView.typeRef();
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType    = codeGen.typeMgr().get(resultTypeRef);
        const MicroOpBits         opBits        = intrinsicNumericOpBits(resultType);
        CodeGenNodePayload&       resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        MicroBuilder&             builder       = codeGen.builder();
        MicroReg                  materializedReg;

        SWC_ASSERT(opBits != MicroOpBits::Zero);
        materializeIntrinsicNumericOperand(materializedReg, codeGen, exprPayload, exprTypeRef, resultTypeRef);

        if (resultType.isFloat())
        {
            resultPayload.reg = codeGen.nextVirtualRegisterForType(resultTypeRef);
            builder.emitLoadRegReg(resultPayload.reg, materializedReg, opBits);

            const uint64_t mask    = opBits == MicroOpBits::B32 ? 0x7FFFFFFFu : 0x7FFFFFFFFFFFFFFFull;
            const MicroReg maskReg = codeGen.nextVirtualRegisterForType(resultTypeRef);
            builder.emitLoadRegImm(maskReg, ApInt(mask, 64), opBits);
            builder.emitOpBinaryRegReg(resultPayload.reg, maskReg, MicroOp::FloatAnd, opBits);
            return Result::Continue;
        }

        SWC_ASSERT(resultType.isIntLike());
        resultPayload.reg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(resultPayload.reg, materializedReg, opBits);
        if (resultType.isIntLikeUnsigned())
            return Result::Continue;

        const uint32_t bitWidth = getNumBits(opBits);
        SWC_ASSERT(bitWidth > 0);

        const MicroReg signMaskReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(signMaskReg, resultPayload.reg, opBits);
        builder.emitOpBinaryRegImm(signMaskReg, ApInt(bitWidth - 1, 64), MicroOp::ShiftArithmeticRight, opBits);
        builder.emitOpBinaryRegReg(resultPayload.reg, signMaskReg, MicroOp::Xor, opBits);
        builder.emitOpBinaryRegReg(resultPayload.reg, signMaskReg, MicroOp::Subtract, opBits);
        return Result::Continue;
    }

    Result codeGenMinMax(CodeGen& codeGen, const AstIntrinsicCallExpr& node, bool isMin)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 2);

        const AstNodeRef          leftRef             = children[0];
        const AstNodeRef          rightRef            = children[1];
        const CodeGenNodePayload& leftPayload         = codeGen.payload(leftRef);
        const CodeGenNodePayload& rightPayload        = codeGen.payload(rightRef);
        const SemaNodeView        leftView            = codeGen.viewType(leftRef);
        const SemaNodeView        rightView           = codeGen.viewType(rightRef);
        const TypeRef             leftOperandTypeRef  = leftPayload.typeRef.isValid() ? leftPayload.typeRef : leftView.typeRef();
        const TypeRef             rightOperandTypeRef = rightPayload.typeRef.isValid() ? rightPayload.typeRef : rightView.typeRef();
        const TypeRef             resultTypeRef       = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType          = codeGen.typeMgr().get(resultTypeRef);
        const MicroOpBits         opBits              = intrinsicNumericOpBits(resultType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg, rightReg;
        materializeIntrinsicNumericOperand(leftReg, codeGen, leftPayload, leftOperandTypeRef, resultTypeRef);
        materializeIntrinsicNumericOperand(rightReg, codeGen, rightPayload, rightOperandTypeRef, resultTypeRef);

        MicroBuilder&       builder       = codeGen.builder();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);

        if (resultType.isFloat())
        {
            resultPayload.reg = codeGen.nextVirtualRegisterForType(resultTypeRef);
            builder.emitLoadRegReg(resultPayload.reg, leftReg, opBits);
            builder.emitOpBinaryRegReg(resultPayload.reg, rightReg, isMin ? MicroOp::FloatMin : MicroOp::FloatMax, opBits);
            return Result::Continue;
        }

        SWC_ASSERT(resultType.isIntLike());
        resultPayload.reg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(resultPayload.reg, leftReg, opBits);
        builder.emitCmpRegReg(leftReg, rightReg, opBits);

        auto takeLeftCond = MicroCond::Equal;
        if (resultType.isIntLikeUnsigned())
            takeLeftCond = isMin ? MicroCond::BelowOrEqual : MicroCond::AboveOrEqual;
        else
            takeLeftCond = isMin ? MicroCond::LessOrEqual : MicroCond::GreaterOrEqual;

        const MicroLabelRef doneLabel = builder.createLabel();
        builder.emitJumpToLabel(takeLeftCond, MicroOpBits::B32, doneLabel);
        builder.emitLoadRegReg(resultPayload.reg, rightReg, opBits);
        builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    Result codeGenRotate(CodeGen& codeGen, const AstIntrinsicCallExpr& node, MicroOp op)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 2);

        const AstNodeRef          valueRef      = children[0];
        const AstNodeRef          countRef      = children[1];
        const CodeGenNodePayload& valuePayload  = codeGen.payload(valueRef);
        const CodeGenNodePayload& countPayload  = codeGen.payload(countRef);
        const SemaNodeView        valueView     = codeGen.viewType(valueRef);
        const SemaNodeView        countView     = codeGen.viewType(countRef);
        const TypeRef             valueTypeRef  = valuePayload.typeRef.isValid() ? valuePayload.typeRef : valueView.typeRef();
        const TypeRef             countTypeRef  = countPayload.typeRef.isValid() ? countPayload.typeRef : countView.typeRef();
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType    = codeGen.typeMgr().get(resultTypeRef);
        const TypeInfo&           countType     = codeGen.typeMgr().get(countTypeRef);
        const MicroOpBits         resultBits    = intrinsicNumericOpBits(resultType);
        CodeGenNodePayload&       resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        MicroBuilder&             builder       = codeGen.builder();
        MicroReg                  materializedValue;
        MicroReg                  materializedCount;

        SWC_ASSERT(resultType.isIntLikeUnsigned());
        SWC_ASSERT(countType.isIntLikeUnsigned());
        SWC_ASSERT(resultBits != MicroOpBits::Zero);

        materializeIntrinsicNumericOperand(materializedValue, codeGen, valuePayload, valueTypeRef, resultTypeRef);
        loadIntrinsicNumericOperand(materializedCount, codeGen, countPayload, countTypeRef);

        resultPayload.reg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(resultPayload.reg, materializedValue, resultBits);
        builder.emitOpBinaryRegReg(resultPayload.reg, materializedCount, op, resultBits);
        return Result::Continue;
    }

    Result codeGenByteSwap(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 1);

        const AstNodeRef          valueRef      = children[0];
        const CodeGenNodePayload& valuePayload  = codeGen.payload(valueRef);
        const SemaNodeView        valueView     = codeGen.viewType(valueRef);
        const TypeRef             valueTypeRef  = valuePayload.typeRef.isValid() ? valuePayload.typeRef : valueView.typeRef();
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType    = codeGen.typeMgr().get(resultTypeRef);
        const MicroOpBits         resultBits    = intrinsicNumericOpBits(resultType);
        CodeGenNodePayload&       resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        MicroBuilder&             builder       = codeGen.builder();
        MicroReg                  materializedValue;

        SWC_ASSERT(resultType.isIntLikeUnsigned());
        SWC_ASSERT(resultBits == MicroOpBits::B16 || resultBits == MicroOpBits::B32 || resultBits == MicroOpBits::B64);

        materializeIntrinsicNumericOperand(materializedValue, codeGen, valuePayload, valueTypeRef, resultTypeRef);
        resultPayload.reg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(resultPayload.reg, materializedValue, resultBits);
        builder.emitOpUnaryReg(resultPayload.reg, MicroOp::ByteSwap, resultBits);
        return Result::Continue;
    }

    Result codeGenBitCount(CodeGen& codeGen, const AstIntrinsicCallExpr& node, BitCountKind kind)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 1);

        const AstNodeRef          valueRef        = children[0];
        const CodeGenNodePayload& valuePayload    = codeGen.payload(valueRef);
        const SemaNodeView        valueView       = codeGen.viewType(valueRef);
        const TypeRef             valueTypeRef    = valuePayload.typeRef.isValid() ? valuePayload.typeRef : valueView.typeRef();
        const TypeRef             resultTypeRef   = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType      = codeGen.typeMgr().get(resultTypeRef);
        const MicroOpBits         resultBits      = intrinsicNumericOpBits(resultType);
        const uint32_t            logicalBitWidth = getNumBits(resultBits);
        CodeGenNodePayload&       resultPayload   = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        MicroBuilder&             builder         = codeGen.builder();
        MicroReg                  materializedValue;

        SWC_ASSERT(resultType.isIntLikeUnsigned());
        SWC_ASSERT(resultBits == MicroOpBits::B8 || resultBits == MicroOpBits::B16 || resultBits == MicroOpBits::B32 || resultBits == MicroOpBits::B64);

        materializeIntrinsicNumericOperand(materializedValue, codeGen, valuePayload, valueTypeRef, resultTypeRef);

        resultPayload.reg = codeGen.nextVirtualIntRegister();
        if (kind == BitCountKind::Nz)
        {
            builder.emitClearReg(resultPayload.reg, resultBits);
            builder.emitOpBinaryRegReg(resultPayload.reg, materializedValue, MicroOp::PopCount, resultBits);
            return Result::Continue;
        }

        builder.emitClearReg(resultPayload.reg, resultBits);
        builder.emitCmpRegImm(materializedValue, ApInt(0, 64), resultBits);
        const MicroLabelRef doneLabel = builder.createLabel();
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

        if (kind == BitCountKind::Tz)
        {
            builder.emitOpBinaryRegReg(resultPayload.reg, materializedValue, MicroOp::BitScanForward, resultBits);
            builder.emitOpBinaryRegImm(resultPayload.reg, ApInt(1, 64), MicroOp::Add, resultBits);
        }
        else
        {
            SWC_ASSERT(kind == BitCountKind::Lz);
            const MicroReg bitPosReg = codeGen.nextVirtualIntRegister();
            builder.emitClearReg(bitPosReg, resultBits);
            builder.emitOpBinaryRegReg(bitPosReg, materializedValue, MicroOp::BitScanReverse, resultBits);
            builder.emitLoadRegImm(resultPayload.reg, ApInt(logicalBitWidth, 64), resultBits);
            builder.emitOpBinaryRegReg(resultPayload.reg, bitPosReg, MicroOp::Subtract, resultBits);
        }

        builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    Result codeGenMulAdd(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 3);

        const AstNodeRef          aRef          = children[0];
        const AstNodeRef          bRef          = children[1];
        const AstNodeRef          cRef          = children[2];
        const CodeGenNodePayload& aPayload      = codeGen.payload(aRef);
        const CodeGenNodePayload& bPayload      = codeGen.payload(bRef);
        const CodeGenNodePayload& cPayload      = codeGen.payload(cRef);
        const SemaNodeView        aView         = codeGen.viewType(aRef);
        const SemaNodeView        bView         = codeGen.viewType(bRef);
        const SemaNodeView        cView         = codeGen.viewType(cRef);
        const TypeRef             aTypeRef      = aPayload.typeRef.isValid() ? aPayload.typeRef : aView.typeRef();
        const TypeRef             bTypeRef      = bPayload.typeRef.isValid() ? bPayload.typeRef : bView.typeRef();
        const TypeRef             cTypeRef      = cPayload.typeRef.isValid() ? cPayload.typeRef : cView.typeRef();
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType    = codeGen.typeMgr().get(resultTypeRef);
        const MicroOpBits         opBits        = intrinsicNumericOpBits(resultType);
        SWC_ASSERT(resultType.isFloat());
        SWC_ASSERT(opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64);

        MicroReg aReg, bReg, cReg;
        materializeIntrinsicNumericOperand(aReg, codeGen, aPayload, aTypeRef, resultTypeRef);
        materializeIntrinsicNumericOperand(bReg, codeGen, bPayload, bTypeRef, resultTypeRef);
        materializeIntrinsicNumericOperand(cReg, codeGen, cPayload, cTypeRef, resultTypeRef);

        MicroBuilder&       builder       = codeGen.builder();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        resultPayload.reg                 = codeGen.nextVirtualRegisterForType(resultTypeRef);
        builder.emitLoadRegReg(resultPayload.reg, aReg, opBits);
        builder.emitOpTernaryRegRegReg(resultPayload.reg, bReg, cReg, MicroOp::MultiplyAdd, opBits);
        return Result::Continue;
    }

    Result codeGenFloatRoundIntrinsic(CodeGen& codeGen, const AstIntrinsicCallExpr& node, FloatRoundKind kind)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 1);

        const AstNodeRef          valueRef      = children[0];
        const CodeGenNodePayload& valuePayload  = codeGen.payload(valueRef);
        const SemaNodeView        valueView     = codeGen.viewType(valueRef);
        const TypeRef             valueTypeRef  = valuePayload.typeRef.isValid() ? valuePayload.typeRef : valueView.typeRef();
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType    = codeGen.typeMgr().get(resultTypeRef);
        const MicroOpBits         opBits        = intrinsicNumericOpBits(resultType);
        SWC_ASSERT(resultType.isFloat());
        SWC_ASSERT(opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64);

        MicroReg materializedValue = MicroReg::invalid();
        materializeIntrinsicNumericOperand(materializedValue, codeGen, valuePayload, valueTypeRef, resultTypeRef);

        MicroBuilder&       builder       = codeGen.builder();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        resultPayload.reg                 = codeGen.nextVirtualRegisterForType(resultTypeRef);
        builder.emitLoadRegReg(resultPayload.reg, materializedValue, opBits);
        builder.emitOpBinaryRegImm(resultPayload.reg, ApInt(static_cast<uint64_t>(kind), 64), MicroOp::FloatRound, opBits);
        return Result::Continue;
    }

    Result codeGenRoundAwayFromZero(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 1);

        const AstNodeRef          valueRef      = children[0];
        const CodeGenNodePayload& valuePayload  = codeGen.payload(valueRef);
        const SemaNodeView        valueView     = codeGen.viewType(valueRef);
        const TypeRef             valueTypeRef  = valuePayload.typeRef.isValid() ? valuePayload.typeRef : valueView.typeRef();
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType    = codeGen.typeMgr().get(resultTypeRef);
        const MicroOpBits         opBits        = intrinsicNumericOpBits(resultType);
        SWC_ASSERT(resultType.isFloat());
        SWC_ASSERT(opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64);

        MicroReg materializedValue = MicroReg::invalid();
        materializeIntrinsicNumericOperand(materializedValue, codeGen, valuePayload, valueTypeRef, resultTypeRef);

        MicroBuilder&       builder       = codeGen.builder();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        resultPayload.reg                 = codeGen.nextVirtualRegisterForType(resultTypeRef);
        builder.emitLoadRegReg(resultPayload.reg, materializedValue, opBits);

        const MicroReg zeroReg = codeGen.nextVirtualRegisterForType(resultTypeRef);
        builder.emitClearReg(zeroReg, opBits);

        const uint64_t halfBits = opBits == MicroOpBits::B32 ? 0x3F000000ull : 0x3FE0000000000000ull;
        const MicroReg halfReg  = codeGen.nextVirtualRegisterForType(resultTypeRef);
        builder.emitLoadRegImm(halfReg, ApInt(halfBits, 64), opBits);

        const MicroLabelRef negativeLabel = builder.createLabel();
        const MicroLabelRef doneLabel     = builder.createLabel();
        builder.emitCmpRegReg(resultPayload.reg, zeroReg, opBits);
        builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, negativeLabel);

        builder.emitOpBinaryRegReg(resultPayload.reg, halfReg, MicroOp::FloatAdd, opBits);
        builder.emitOpBinaryRegImm(resultPayload.reg, ApInt(static_cast<uint64_t>(FloatRoundKind::Floor), 64), MicroOp::FloatRound, opBits);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

        builder.placeLabel(negativeLabel);
        builder.emitOpBinaryRegReg(resultPayload.reg, halfReg, MicroOp::FloatSubtract, opBits);
        builder.emitOpBinaryRegImm(resultPayload.reg, ApInt(static_cast<uint64_t>(FloatRoundKind::Ceil), 64), MicroOp::FloatRound, opBits);
        builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    Result codeGenCompiler(CodeGen& codeGen)
    {
        const uint64_t      compilerIfAddress = reinterpret_cast<uint64_t>(&codeGen.compiler().runtimeCompiler());
        const ConstantValue compilerIfCst     = ConstantValue::makeValuePointer(codeGen.ctx(), codeGen.typeMgr().typeVoid(), compilerIfAddress, TypeInfoFlagsE::Const);
        const ConstantRef   compilerIfCstRef  = codeGen.cstMgr().addConstant(codeGen.ctx(), compilerIfCst);
        const SemaNodeView  view              = codeGen.curViewType();
        const auto&         payload           = codeGen.setPayloadValue(codeGen.curNodeRef(), view.typeRef());
        codeGen.builder().emitLoadRegPtrReloc(payload.reg, compilerIfAddress, compilerIfCstRef);
        return Result::Continue;
    }

    Result codeGenGetContext(CodeGen& codeGen)
    {
        const auto* payload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->runtimeFunctionSymbol != nullptr);

        auto&                             tlsGetValueFunction = *payload->runtimeFunctionSymbol;
        const CallConvKind                callConvKind        = tlsGetValueFunction.callConvKind();
        const TypeRef                     resultType          = codeGen.curViewType().typeRef();
        MicroBuilder&                     builder             = codeGen.builder();
        SmallVector<ABICall::PreparedArg> preparedArgs;

        const uint64_t    tlsIdAddress   = reinterpret_cast<uint64_t>(CompilerInstance::runtimeContextTlsIdStorage());
        const ConstantRef tlsIdAddressCf = codeGen.cstMgr().addConstant(codeGen.ctx(), ConstantValue::makeValuePointer(codeGen.ctx(), codeGen.typeMgr().typeU64(), tlsIdAddress, TypeInfoFlagsE::Const));
        const MicroReg    tlsIdPtrReg    = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegPtrReloc(tlsIdPtrReg, tlsIdAddress, tlsIdAddressCf);

        const MicroReg tlsIdReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(tlsIdReg, tlsIdPtrReg, 0, MicroOpBits::B64);

        ABICall::PreparedArg arg;
        arg.srcReg      = tlsIdReg;
        arg.kind        = ABICall::PreparedArgKind::Direct;
        arg.isFloat     = false;
        arg.isAddressed = false;
        arg.numBits     = 64;
        preparedArgs.push_back(arg);

        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        ABICall::callLocal(builder, callConvKind, &tlsGetValueFunction, preparedCall);

        const CallConv&                        callConv      = CallConv::get(callConvKind);
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, resultType, ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!normalizedRet.isVoid);
        SWC_ASSERT(!normalizedRet.isIndirect);

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultType);
        ABICall::materializeReturnToReg(builder, resultPayload.reg, callConvKind, normalizedRet);
        return Result::Continue;
    }
}

Result AstCountOfExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return codeGenCountOf(codeGen, nodeExprRef);
}

Result AstIntrinsicCall::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicDataOf:
            return codeGenDataOf(codeGen, *this);
        case TokenId::IntrinsicKindOf:
            return codeGenKindOf(codeGen, *this);
        case TokenId::IntrinsicMakeAny:
            return codeGenMakeAny(codeGen, *this);
        case TokenId::IntrinsicMakeSlice:
            return codeGenMakeSlice(codeGen, *this, false);
        case TokenId::IntrinsicMakeString:
            return codeGenMakeSlice(codeGen, *this, true);

        default:
            SWC_UNREACHABLE();
    }
}

Result AstIntrinsicCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicAssert:
            return codeGenAssert(codeGen, *this);
        case TokenId::IntrinsicSqrt:
            return codeGenSqrt(codeGen, *this);
        case TokenId::IntrinsicAbs:
            return codeGenAbs(codeGen, *this);
        case TokenId::IntrinsicMin:
            return codeGenMinMax(codeGen, *this, true);
        case TokenId::IntrinsicMax:
            return codeGenMinMax(codeGen, *this, false);
        case TokenId::IntrinsicRol:
            return codeGenRotate(codeGen, *this, MicroOp::RotateLeft);
        case TokenId::IntrinsicRor:
            return codeGenRotate(codeGen, *this, MicroOp::RotateRight);
        case TokenId::IntrinsicByteSwap:
            return codeGenByteSwap(codeGen, *this);
        case TokenId::IntrinsicBitCountNz:
            return codeGenBitCount(codeGen, *this, BitCountKind::Nz);
        case TokenId::IntrinsicBitCountTz:
            return codeGenBitCount(codeGen, *this, BitCountKind::Tz);
        case TokenId::IntrinsicBitCountLz:
            return codeGenBitCount(codeGen, *this, BitCountKind::Lz);
        case TokenId::IntrinsicMulAdd:
            return codeGenMulAdd(codeGen, *this);
        case TokenId::IntrinsicFloor:
            return codeGenFloatRoundIntrinsic(codeGen, *this, FloatRoundKind::Floor);
        case TokenId::IntrinsicCeil:
            return codeGenFloatRoundIntrinsic(codeGen, *this, FloatRoundKind::Ceil);
        case TokenId::IntrinsicTrunc:
            return codeGenFloatRoundIntrinsic(codeGen, *this, FloatRoundKind::Trunc);
        case TokenId::IntrinsicRound:
            return codeGenRoundAwayFromZero(codeGen, *this);
        case TokenId::IntrinsicMemCpy:
            return codeGenMemCopyIntrinsic(codeGen, *this);
        case TokenId::IntrinsicMemSet:
            return codeGenMemSetIntrinsic(codeGen, *this);
        case TokenId::IntrinsicMemMove:
            return codeGenMemMoveIntrinsic(codeGen, *this);
        case TokenId::IntrinsicMemCmp:
            return codeGenMemCmpIntrinsic(codeGen, *this);
        case TokenId::IntrinsicAtomicAdd:
            return codeGenAtomicBinaryRmw(codeGen, *this, MicroOp::Add);
        case TokenId::IntrinsicAtomicAnd:
            return codeGenAtomicBinaryRmw(codeGen, *this, MicroOp::And);
        case TokenId::IntrinsicAtomicOr:
            return codeGenAtomicBinaryRmw(codeGen, *this, MicroOp::Or);
        case TokenId::IntrinsicAtomicXor:
            return codeGenAtomicBinaryRmw(codeGen, *this, MicroOp::Xor);
        case TokenId::IntrinsicAtomicXchg:
            return codeGenAtomicExchange(codeGen, *this);
        case TokenId::IntrinsicAtomicCmpXchg:
            return codeGenAtomicCompareExchange(codeGen, *this);

        case TokenId::IntrinsicGetContext:
            return codeGenGetContext(codeGen);
        case TokenId::IntrinsicCompiler:
            return codeGenCompiler(codeGen);
        case TokenId::IntrinsicBreakpoint:
            codeGen.builder().emitBreakpoint();
            return Result::Continue;

        default:
            return CodeGenFunctionHelpers::codeGenCallExprCommon(codeGen, nodeExprRef);
    }
}

SWC_END_NAMESPACE();
