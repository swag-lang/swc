#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_RUNTIME_EXCEPTION_KIND_ASSERT = 3;
    ConstantRef        makeZeroStructConstant(CodeGen& codeGen, TypeRef typeRef);

    CodeGenNodePayload makeAddressPayloadFromConstant(CodeGen& codeGen, ConstantRef cstRef)
    {
        const ConstantValue& cst = codeGen.cstMgr().get(cstRef);
        SWC_ASSERT(cst.isStruct() || cst.isArray());

        const ByteSpan bytes = cst.isStruct() ? cst.getStruct() : cst.getArray();
        const uint64_t addr  = reinterpret_cast<uint64_t>(bytes.data());

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

    struct InterfaceCastInfo
    {
        const SymbolStruct*   objectStruct        = nullptr;
        const SymbolImpl*     implSym             = nullptr;
        const SymbolVariable* usingField          = nullptr;
        bool                  usingFieldIsPointer = false;
    };

    struct InterfaceMakeRuntimeCandidate
    {
        TypeRef           objectTypeRef = TypeRef::invalid();
        InterfaceCastInfo castInfo;
    };

    void loadIntrinsicNumericOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        outReg                        = codeGen.nextVirtualRegisterForType(operandTypeRef);
        const TypeInfo&   operandType = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits opBits      = CodeGenTypeHelpers::numericBits(operandType);
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
        const MicroOpBits srcBits = CodeGenTypeHelpers::numericBits(srcType);
        const MicroOpBits dstBits = CodeGenTypeHelpers::numericBits(dstType);
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
            MicroReg srcReg = outReg;
            if (getNumBits(srcBits) < 32 || (dstBits == MicroOpBits::B64 && getNumBits(srcBits) == 32))
            {
                srcReg                        = codeGen.nextVirtualIntRegister();
                const MicroOpBits widenedBits = dstBits == MicroOpBits::B64 ? MicroOpBits::B64 : MicroOpBits::B32;
                if (srcType.isIntSigned())
                    builder.emitLoadSignedExtendRegReg(srcReg, outReg, widenedBits, srcBits);
                else
                    builder.emitLoadZeroExtendRegReg(srcReg, outReg, widenedBits, srcBits);
            }

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, srcReg, MicroOp::ConvertIntToFloat, dstBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isFloat() && dstType.isFloat())
        {
            if (srcBits == dstBits)
                return;

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, outReg, MicroOp::ConvertFloatToFloat, srcBits);
            outReg = dstReg;
            return;
        }

        SWC_INTERNAL_ERROR();
    }

    void materializeIntrinsicNumericOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, TypeRef resultTypeRef)
    {
        loadIntrinsicNumericOperand(outReg, codeGen, operandPayload, operandTypeRef);
        convertIntrinsicNumericOperand(outReg, codeGen, operandTypeRef, resultTypeRef);
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

    bool resolveInterfaceCastInfo(CodeGen& codeGen, const SymbolStruct& srcStruct, const SymbolInterface& dstItf, InterfaceCastInfo& outInfo)
    {
        if (const SymbolImpl* implSym = srcStruct.findInterfaceImpl(dstItf.idRef()))
        {
            outInfo.objectStruct = &srcStruct;
            outInfo.implSym      = implSym;
            outInfo.usingField   = nullptr;
            return true;
        }

        for (const SymbolVariable* field : srcStruct.fields())
        {
            SWC_ASSERT(field != nullptr);
            if (!field->isUsingField())
                continue;

            bool                usingFieldIsPointer = false;
            const SymbolStruct* targetStruct        = field->usingTargetStruct(codeGen.ctx(), usingFieldIsPointer);
            if (!targetStruct)
                continue;

            if (const SymbolImpl* implSym = targetStruct->findInterfaceImpl(dstItf.idRef()))
            {
                outInfo.objectStruct        = targetStruct;
                outInfo.implSym             = implSym;
                outInfo.usingField          = field;
                outInfo.usingFieldIsPointer = usingFieldIsPointer;
                return true;
            }
        }

        return false;
    }

    void collectMakeInterfaceRuntimeCandidatesRec(CodeGen& codeGen, const SymbolMap& symbolMap, const SymbolInterface& dstItf, SmallVector<InterfaceMakeRuntimeCandidate>& outCandidates)
    {
        std::vector<const Symbol*> symbols;
        symbolMap.getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            SWC_ASSERT(symbol != nullptr);

            if (symbol->isStruct())
            {
                const auto&   symStruct     = symbol->cast<SymbolStruct>();
                const TypeRef objectTypeRef = symStruct.typeRef();
                if (objectTypeRef.isValid())
                {
                    const TypeInfo& objectType = codeGen.typeMgr().get(objectTypeRef);
                    if (objectType.isStruct())
                    {
                        InterfaceCastInfo castInfo;
                        if (resolveInterfaceCastInfo(codeGen, objectType.payloadSymStruct(), dstItf, castInfo))
                            outCandidates.push_back({.objectTypeRef = objectTypeRef, .castInfo = castInfo});
                    }
                }

                collectMakeInterfaceRuntimeCandidatesRec(codeGen, *symStruct.asSymMap(), dstItf, outCandidates);
                continue;
            }

            if (symbol->isModule() || symbol->isNamespace())
                collectMakeInterfaceRuntimeCandidatesRec(codeGen, *symbol->asSymMap(), dstItf, outCandidates);
        }
    }

    TypeRef intrinsicMakeInterfaceObjectTypeRef(CodeGen& codeGen, AstNodeRef typeRefNode)
    {
        const SemaNodeView typeView = codeGen.viewTypeConstant(typeRefNode);
        if (typeView.type() && typeView.type()->isTypeValue())
            return codeGen.typeMgr().get(typeView.type()->payloadTypeRef()).unwrapAliasEnum(codeGen.ctx(), typeView.type()->payloadTypeRef());

        if (!typeView.cstRef().isValid())
            return TypeRef::invalid();

        const TypeRef resolvedTypeRef = codeGen.cstMgr().makeTypeValue(codeGen.sema(), typeView.cstRef());
        if (!resolvedTypeRef.isValid())
            return TypeRef::invalid();

        return codeGen.typeMgr().get(resolvedTypeRef).unwrapAliasEnum(codeGen.ctx(), resolvedTypeRef);
    }

    MicroReg materializeInterfaceObjectPointer(CodeGen&                  codeGen,
                                               const CodeGenNodePayload& objectPayload,
                                               TypeRef                   objectValueTypeRef,
                                               const MicroReg            runtimeStorageReg,
                                               const uint64_t            objectSpillOffset)
    {
        MicroBuilder&   builder         = codeGen.builder();
        const TypeInfo& objectValueType = codeGen.typeMgr().get(objectValueTypeRef);

        if (objectValueType.isNull())
        {
            const MicroReg objectReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegImm(objectReg, ApInt(0, 64), MicroOpBits::B64);
            return objectReg;
        }

        if (objectValueType.isPointerLike() || objectValueType.isReference())
        {
            const MicroReg objectReg = codeGen.nextVirtualIntRegister();
            if (objectPayload.isAddress())
                builder.emitLoadRegMem(objectReg, objectPayload.reg, 0, MicroOpBits::B64);
            else
                builder.emitLoadRegReg(objectReg, objectPayload.reg, MicroOpBits::B64);
            return objectReg;
        }

        const uint64_t objectSize = objectValueType.sizeOf(codeGen.ctx());
        if (objectPayload.isAddress() || (objectPayload.isValue() && objectSize > sizeof(uint64_t)))
            return objectPayload.reg;

        SWC_ASSERT(objectSpillOffset <= std::numeric_limits<uint32_t>::max());
        const MicroReg spillReg  = codeGen.offsetAddressReg(runtimeStorageReg, static_cast<uint32_t>(objectSpillOffset));
        const auto     storeBits = CodeGenTypeHelpers::bitsFromStorageSize(objectSize);
        SWC_ASSERT(storeBits != MicroOpBits::Zero);
        builder.emitLoadMemReg(spillReg, 0, objectPayload.reg, storeBits);
        return spillReg;
    }

    void emitMakeInterfaceValue(CodeGen&                  codeGen,
                                const SymbolInterface&    interfaceSym,
                                const InterfaceCastInfo&  castInfo,
                                const CodeGenNodePayload& objectPayload,
                                TypeRef                   objectValueTypeRef,
                                const MicroReg            runtimeStorageReg,
                                const uint64_t            objectSpillOffset)
    {
        MicroBuilder&   builder         = codeGen.builder();
        const TypeInfo& objectValueType = codeGen.typeMgr().get(objectValueTypeRef);

        MicroReg objectReg = materializeInterfaceObjectPointer(codeGen, objectPayload, objectValueTypeRef, runtimeStorageReg, objectSpillOffset);
        if (castInfo.usingField)
        {
            const SymbolVariable& usingField = *castInfo.usingField;
            if (objectValueType.isNull())
            {
                const MicroReg nullReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegImm(nullReg, ApInt(0, 64), MicroOpBits::B64);
                objectReg = nullReg;
            }
            else if (castInfo.usingFieldIsPointer)
            {
                const MicroReg adjustedReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(adjustedReg, objectReg, usingField.offset(), MicroOpBits::B64);
                objectReg = adjustedReg;
            }
            else if (usingField.offset())
            {
                const MicroReg adjustedReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(adjustedReg, objectReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(adjustedReg, ApInt(usingField.offset(), 64), MicroOp::Add, MicroOpBits::B64);
                objectReg = adjustedReg;
            }
        }

        builder.emitLoadMemReg(runtimeStorageReg, offsetof(Runtime::Interface, obj), objectReg, MicroOpBits::B64);

        const auto&  interfaceMethods = interfaceSym.functions();
        const void*  tablePtr         = nullptr;
        ConstantRef  tableCstRef      = ConstantRef::invalid();
        const Result tableRes         = codeGen.compiler().getOrCreateInterfaceTable(codeGen.sema(), *castInfo.objectStruct, interfaceSym, *castInfo.implSym, codeGen.curNodeRef(), tablePtr, tableCstRef);
        SWC_INTERNAL_CHECK(tableRes == Result::Continue);
        SWC_ASSERT(tablePtr != nullptr);
        SWC_ASSERT(tableCstRef.isValid());

        const MicroReg itableReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegPtrReloc(itableReg, reinterpret_cast<uint64_t>(tablePtr), tableCstRef);
        builder.emitLoadMemReg(runtimeStorageReg, offsetof(Runtime::Interface, itable), itableReg, MicroOpBits::B64);

        for (size_t i = 0; i < interfaceMethods.size(); ++i)
        {
            const SymbolFunction* interfaceMethod = interfaceMethods[i];
            SWC_ASSERT(interfaceMethod != nullptr);
            const SymbolFunction* implMethod = castInfo.implSym->findFunction(interfaceMethod->idRef());
            SWC_ASSERT(implMethod != nullptr);
            codeGen.function().addCallDependency(const_cast<SymbolFunction*>(implMethod));
        }
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
        const MicroOpBits         opBits         = CodeGenTypeHelpers::numericBits(resultTypeInfo);
        MicroBuilder&             builder        = codeGen.builder();

        SWC_ASSERT(resultTypeInfo.isIntLike());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        const MicroReg ptrReg = materializeIntrinsicIntArgReg(codeGen, ptrPayload, MicroOpBits::B64);

        MicroReg valueReg = MicroReg::invalid();
        materializeIntrinsicNumericOperand(valueReg, codeGen, valuePayload, valueTypeRef, resultTypeRef);

        const MicroReg expectedReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(expectedReg, ptrReg, 0, opBits);

        // Lower atomic rmw through a compare-exchange retry loop so it maps cleanly to the generic micro
        // instruction set without needing dedicated rmw opcodes.
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
        const MicroOpBits         opBits         = CodeGenTypeHelpers::numericBits(resultTypeInfo);
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
        const MicroOpBits         opBits          = CodeGenTypeHelpers::numericBits(resultTypeInfo);
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
            return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, node.nodeExprRef);

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
            return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, node.nodeExprRef);

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
            return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, node.nodeExprRef);

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
            return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, node.nodeExprRef);

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
        const MicroReg runtimeValueReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        MicroBuilder&  builder         = codeGen.builder();
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Any, value), ptrReg, MicroOpBits::B64);
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Any, type), typeInfoReg, MicroOpBits::B64);

        codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeValueReg, resultTypeRef);
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

        const MicroReg runtimeStorageReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        const uint64_t countOffset       = forString ? offsetof(Runtime::String, length) : offsetof(Runtime::Slice<std::byte>, count);
        builder.emitLoadMemReg(runtimeStorageReg, offsetof(Runtime::Slice<std::byte>, ptr), ptrReg, MicroOpBits::B64);
        builder.emitLoadMemReg(runtimeStorageReg, countOffset, sizeReg, MicroOpBits::B64);

        CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        payload.reg                 = runtimeStorageReg;
        return Result::Continue;
    }

    Result codeGenMakeInterface(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 3);

        const AstNodeRef          objectRef          = children[0];
        const AstNodeRef          typeRefNode        = children[1];
        const CodeGenNodePayload& objectPayload      = codeGen.payload(objectRef);
        const CodeGenNodePayload& typePayload        = codeGen.payload(typeRefNode);
        const TypeRef             resultTypeRef      = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType         = codeGen.typeMgr().get(resultTypeRef);
        const TypeRef             objectValueTypeRef = intrinsicOperandTypeRef(codeGen, objectRef, objectPayload);
        const TypeRef             objectTypeRef      = intrinsicMakeInterfaceObjectTypeRef(codeGen, typeRefNode);
        constexpr uint64_t        interfaceSize      = sizeof(Runtime::Interface);
        constexpr uint64_t        objectSpillOff     = interfaceSize;
        const MicroReg            runtimeStorageReg  = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        MicroBuilder&             builder            = codeGen.builder();

        SWC_ASSERT(resultType.isInterface());
        SWC_ASSERT(interfaceSize <= std::numeric_limits<uint32_t>::max());
        CodeGenMemoryHelpers::emitMemZero(codeGen, runtimeStorageReg, interfaceSize);

        if (objectTypeRef.isValid())
        {
            const TypeInfo& concreteObjectType = codeGen.typeMgr().get(objectTypeRef);
            if (concreteObjectType.isStruct())
            {
                InterfaceCastInfo castInfo;
                if (resolveInterfaceCastInfo(codeGen, concreteObjectType.payloadSymStruct(), resultType.payloadSymInterface(), castInfo))
                    emitMakeInterfaceValue(codeGen, resultType.payloadSymInterface(), castInfo, objectPayload, objectValueTypeRef, runtimeStorageReg, objectSpillOff);
            }

            codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeStorageReg, resultTypeRef);
            return Result::Continue;
        }

        SmallVector<InterfaceMakeRuntimeCandidate> candidates;
        if (const SymbolModule* rootModule = codeGen.compiler().symModule())
            collectMakeInterfaceRuntimeCandidatesRec(codeGen, *rootModule, resultType.payloadSymInterface(), candidates);

        if (!candidates.empty())
        {
            const MicroReg      typeInfoReg = materializeIntrinsicIntArgReg(codeGen, typePayload, MicroOpBits::B64);
            const MicroLabelRef doneLabel   = builder.createLabel();

            for (const auto& candidate : candidates)
            {
                ConstantRef typeInfoCstRef = ConstantRef::invalid();
                SWC_RESULT(codeGen.cstMgr().makeTypeInfo(codeGen.sema(), typeInfoCstRef, candidate.objectTypeRef, typeRefNode));
                const ConstantValue& typeInfoCst = codeGen.cstMgr().get(typeInfoCstRef);
                SWC_ASSERT(typeInfoCst.isValuePointer());

                const MicroLabelRef nextLabel        = builder.createLabel();
                const MicroReg      candidateTypeReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegPtrReloc(candidateTypeReg, typeInfoCst.getValuePointer(), typeInfoCstRef);
                builder.emitCmpRegReg(typeInfoReg, candidateTypeReg, MicroOpBits::B64);
                builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, nextLabel);
                emitMakeInterfaceValue(codeGen, resultType.payloadSymInterface(), candidate.castInfo, objectPayload, objectValueTypeRef, runtimeStorageReg, objectSpillOff);
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
                builder.placeLabel(nextLabel);
            }

            builder.placeLabel(doneLabel);
        }

        codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeStorageReg, resultTypeRef);
        return Result::Continue;
    }

    MicroReg materializeCountLikeBaseReg(const CodeGen& codeGen, const CodeGenNodePayload& payload)
    {
        SWC_UNUSED(codeGen);
        return payload.reg;
    }

    CodeGenNodePayload resolveStoredVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (symVar.isClosureCapture())
            return CodeGenFunctionHelpers::resolveClosureCapturePayload(codeGen, symVar);

        if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar))
            return CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, symVar);

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }

        if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar))
            return *symbolPayload;

        if (symVar.hasGlobalStorage())
        {
            CodeGenNodePayload globalPayload;
            globalPayload.typeRef = symVar.typeRef();
            globalPayload.setIsAddress();
            globalPayload.reg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegDataSegmentReloc(globalPayload.reg, symVar.globalStorageKind(), symVar.offset());
            return globalPayload;
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            return codeGen.resolveLocalStackPayload(symVar);

        if (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
            return codeGen.resolveLocalStackPayload(symVar);

        SWC_UNREACHABLE();
    }

    CodeGenNodePayload countOfExprPayload(CodeGen& codeGen, AstNodeRef exprRef)
    {
        if (const auto* payload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(exprRef))
        {
            if (payload->reg.isValid())
                return *payload;
        }

        // `@countof` can target a stored symbol not reached through the current AST walk, so fall
        // back to sema-owned symbol/type views before using the transient node payload.
        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Symbol);
        if (storedView.sym() && storedView.sym()->isVariable())
        {
            const auto& symVar = storedView.sym()->cast<SymbolVariable>();
            if (symVar.isClosureCapture() ||
                CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar) ||
                symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
                symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) ||
                symVar.hasGlobalStorage() ||
                CodeGen::variablePayload(symVar) ||
                (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal)))
                return resolveStoredVariablePayload(codeGen, symVar);
        }

        return codeGen.payload(exprRef);
    }

    SemaNodeView countOfExprView(CodeGen& codeGen, AstNodeRef exprRef)
    {
        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Type);
        if (storedView.type() != nullptr)
            return storedView;
        return codeGen.viewType(exprRef);
    }

    Result codeGenCountOf(CodeGen& codeGen, AstNodeRef exprRef)
    {
        MicroBuilder&             builder       = codeGen.builder();
        const SemaNodeView        exprView      = countOfExprView(codeGen, exprRef);
        const CodeGenNodePayload& exprPayload   = countOfExprPayload(codeGen, exprRef);
        const TypeInfo* const     exprType      = exprView.type();
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        SWC_ASSERT(exprType != nullptr);

        if (exprType->isIntUnsigned())
        {
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
            const uint32_t            intBits       = exprType->payloadIntBitsOr(64);
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
            // C strings do not carry a cached length in their runtime representation, so count bytes until
            // the terminating zero.
            const MicroReg cstrReg = codeGen.nextVirtualIntRegister();
            if (exprPayload.isAddress())
                builder.emitLoadRegMem(cstrReg, baseReg, 0, MicroOpBits::B64);
            else
                builder.emitLoadRegReg(cstrReg, baseReg, MicroOpBits::B64);

            builder.emitClearReg(resultPayload.reg, MicroOpBits::B64);

            const MicroLabelRef loopLabel = builder.createLabel();
            const MicroLabelRef doneLabel = builder.createLabel();
            builder.emitCmpRegImm(cstrReg, ApInt(0, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

            const MicroReg scanReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(scanReg, cstrReg, MicroOpBits::B64);
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
        else if (exprView.type() && exprView.type()->isInterface())
            builder.emitLoadRegMem(payload.reg, exprPayload.reg, offsetof(Runtime::Interface, obj), MicroOpBits::B64);
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
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        CodeGenNodePayload&       result      = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        MicroBuilder&             builder     = codeGen.builder();
        result.reg                            = codeGen.nextVirtualIntRegister();
        if (exprView.type() && exprView.type()->isInterface())
        {
            const MicroReg tableReg    = codeGen.nextVirtualIntRegister();
            const MicroReg typeSlotReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(tableReg, exprPayload.reg, offsetof(Runtime::Interface, itable), MicroOpBits::B64);
            builder.emitLoadRegReg(typeSlotReg, tableReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(typeSlotReg, ApInt(sizeof(void*), 64), MicroOp::Subtract, MicroOpBits::B64);
            builder.emitLoadRegMem(result.reg, typeSlotReg, 0, MicroOpBits::B64);
        }
        else
        {
            builder.emitLoadRegMem(result.reg, exprPayload.reg, offsetof(Runtime::Any, type), MicroOpBits::B64);
        }
        return Result::Continue;
    }

    Result codeGenTableOf(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(!children.empty());

        const AstNodeRef          exprRef     = children[0];
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        CodeGenNodePayload&       result      = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        MicroBuilder&             builder     = codeGen.builder();
        result.reg                            = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(result.reg, exprPayload.reg, offsetof(Runtime::Interface, itable), MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenAssert(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        MicroBuilder&           builder = codeGen.builder();
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

        auto&                             raiseExceptionFunction = *payload->runtimeFunctionSymbol;
        const CallConvKind                callConvKind           = raiseExceptionFunction.callConvKind();
        const CallConv&                   callConv               = CallConv::get(callConvKind);
        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(3);

        const ConstantRef nullMessageRef = makeZeroStructConstant(codeGen, codeGen.typeMgr().typeString());
        const auto        nullMessage    = makeAddressPayloadFromConstant(codeGen, nullMessageRef);

        const ConstantRef sourceLocRef = ConstantHelpers::makeSourceCodeLocation(codeGen.sema(), node);
        const auto        sourceLoc    = makeAddressPayloadFromConstant(codeGen, sourceLocRef);

        ABICall::PreparedArg messageArg;
        messageArg.srcReg = nullMessage.reg;
        {
            const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.typeMgr().typeString(), ABITypeNormalize::Usage::Argument);
            messageArg.kind                                      = ABICall::PreparedArgKind::Direct;
            messageArg.isFloat                                   = normalizedArg.isFloat;
            messageArg.numBits                                   = normalizedArg.numBits;
            messageArg.isAddressed                               = false;
        }
        preparedArgs.push_back(messageArg);

        ABICall::PreparedArg locationArg;
        locationArg.srcReg = sourceLoc.reg;
        {
            const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.typeMgr().structSourceCodeLocation(), ABITypeNormalize::Usage::Argument);
            locationArg.kind                                     = ABICall::PreparedArgKind::Direct;
            locationArg.isFloat                                  = normalizedArg.isFloat;
            locationArg.numBits                                  = normalizedArg.numBits;
            locationArg.isAddressed                              = false;
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

        const uint32_t    floatBits = resultType.payloadFloatBitsOr(64);
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
        const MicroOpBits         opBits        = CodeGenTypeHelpers::numericBits(resultType);
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
        const MicroOpBits         opBits              = CodeGenTypeHelpers::numericBits(resultType);
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
        const MicroOpBits         resultBits    = CodeGenTypeHelpers::numericBits(resultType);
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
        const MicroOpBits         resultBits    = CodeGenTypeHelpers::numericBits(resultType);
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
        const MicroOpBits         resultBits      = CodeGenTypeHelpers::numericBits(resultType);
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
        const MicroOpBits         opBits        = CodeGenTypeHelpers::numericBits(resultType);
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
        const MicroOpBits         opBits        = CodeGenTypeHelpers::numericBits(resultType);
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
        const MicroOpBits         opBits        = CodeGenTypeHelpers::numericBits(resultType);
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

    SymbolFunction* runtimeFunctionByName(CodeGen& codeGen, const std::string_view name)
    {
        const IdentifierRef idRef = codeGen.idMgr().addIdentifier(name);
        if (idRef.isInvalid())
            return nullptr;

        return codeGen.compiler().runtimeFunctionSymbol(idRef);
    }

    ConstantRef makeZeroStructConstant(CodeGen& codeGen, TypeRef typeRef)
    {
        const TypeInfo& type   = codeGen.typeMgr().get(typeRef);
        const uint64_t  sizeOf = type.sizeOf(codeGen.ctx());

        std::vector<std::byte> bytes;
        bytes.resize(sizeOf);

        const std::string_view storedPayload(reinterpret_cast<const char*>(bytes.data()), bytes.size());
        const std::string_view persistentStorage = codeGen.cstMgr().addPayloadBuffer(storedPayload);
        const ByteSpan         persistentBytes{reinterpret_cast<const std::byte*>(persistentStorage.data()), persistentStorage.size()};
        return codeGen.cstMgr().addConstant(codeGen.ctx(), ConstantValue::makeStructBorrowed(codeGen.ctx(), typeRef, persistentBytes));
    }

    Result codeGenProcessInfos(CodeGen& codeGen)
    {
        const TypeRef             processInfosTypeRef = codeGen.typeMgr().structProcessInfos();
        const ConstantRef         processInfosCstRef  = makeZeroStructConstant(codeGen, processInfosTypeRef);
        const CodeGenNodePayload  addressPayload      = makeAddressPayloadFromConstant(codeGen, processInfosCstRef);
        const CodeGenNodePayload& resultPayload       = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        codeGen.builder().emitLoadRegReg(resultPayload.reg, addressPayload.reg, MicroOpBits::B64);
        return Result::Continue;
    }

    MicroReg gvtdScratchAddressReg(CodeGen& codeGen)
    {
        SWC_ASSERT(codeGen.hasGvtdScratchLayout());
        SWC_ASSERT(codeGen.localStackBaseReg().isValid());

        if (!codeGen.gvtdScratchOffset())
            return codeGen.localStackBaseReg();

        MicroBuilder&  builder    = codeGen.builder();
        const MicroReg addressReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(addressReg, codeGen.localStackBaseReg(), MicroOpBits::B64);
        builder.emitOpBinaryRegImm(addressReg, ApInt(codeGen.gvtdScratchOffset(), 64), MicroOp::Add, MicroOpBits::B64);
        return addressReg;
    }

    Result codeGenGvtd(CodeGen& codeGen)
    {
        constexpr uint32_t slicePtrOffset   = offsetof(Runtime::Slice<Runtime::Gvtd>, ptr);
        constexpr uint32_t sliceCountOffset = offsetof(Runtime::Slice<Runtime::Gvtd>, count);
        constexpr uint32_t entriesOffset    = (sizeof(Runtime::Slice<Runtime::Gvtd>) + alignof(Runtime::Gvtd) - 1) & ~(alignof(Runtime::Gvtd) - 1);

        SWC_ASSERT(codeGen.hasGvtdScratchLayout());
        if (!codeGen.hasGvtdScratchLayout())
            return Result::Error;

        // Rebuild the returned slice in frame-local scratch storage on each call so both the slice header
        // and the entry array stay valid for the duration of the current function.
        const MicroReg scratchReg = gvtdScratchAddressReg(codeGen);
        MicroBuilder&  builder    = codeGen.builder();
        const auto     entries    = codeGen.gvtdScratchEntries();

        if (entries.empty())
        {
            builder.emitLoadMemImm(scratchReg, slicePtrOffset, ApInt(0, 64), MicroOpBits::B64);
        }
        else
        {
            const MicroReg entriesReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(entriesReg, scratchReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(entriesReg, ApInt(entriesOffset, 64), MicroOp::Add, MicroOpBits::B64);
            builder.emitLoadMemReg(scratchReg, slicePtrOffset, entriesReg, MicroOpBits::B64);

            for (size_t i = 0; i < entries.size(); ++i)
            {
                const auto&    entry   = entries[i];
                const uint64_t baseOff = entriesOffset + i * sizeof(Runtime::Gvtd);

                const MicroReg ptrReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegDataSegmentReloc(ptrReg, entry.variable->globalStorageKind(), entry.variable->offset());
                builder.emitLoadMemReg(scratchReg, baseOff + offsetof(Runtime::Gvtd, ptr), ptrReg, MicroOpBits::B64);

                const MicroReg opDropReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegPtrReloc(opDropReg, 0, ConstantRef::invalid(), entry.opDrop);
                builder.emitLoadMemReg(scratchReg, baseOff + offsetof(Runtime::Gvtd, opDrop), opDropReg, MicroOpBits::B64);
                builder.emitLoadMemImm(scratchReg, baseOff + offsetof(Runtime::Gvtd, sizeOf), ApInt(entry.sizeOf, 32), MicroOpBits::B32);
                builder.emitLoadMemImm(scratchReg, baseOff + offsetof(Runtime::Gvtd, count), ApInt(entry.count, 32), MicroOpBits::B32);
            }
        }

        builder.emitLoadMemImm(scratchReg, sliceCountOffset, ApInt(entries.size(), 64), MicroOpBits::B64);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        resultPayload.reg                 = scratchReg;
        return Result::Continue;
    }

    Result codeGenGetContextNative(CodeGen& codeGen)
    {
        SymbolFunction* tlsAllocFunction  = runtimeFunctionByName(codeGen, "__tlsAlloc");
        SymbolFunction* tlsGetPtrFunction = runtimeFunctionByName(codeGen, "__tlsGetPtr");
        SWC_ASSERT(tlsAllocFunction != nullptr);
        SWC_ASSERT(tlsGetPtrFunction != nullptr);
        if (!tlsAllocFunction || !tlsGetPtrFunction)
            return Result::Error;

        codeGen.function().addCallDependency(tlsAllocFunction);
        codeGen.function().addCallDependency(tlsGetPtrFunction);

        MicroBuilder&  builder       = codeGen.builder();
        const uint32_t tlsIdOffset   = codeGen.compiler().nativeRuntimeContextTlsIdOffset();
        const MicroReg tlsStorageReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegDataSegmentReloc(tlsStorageReg, DataSegmentKind::GlobalZero, tlsIdOffset);

        const MicroReg tlsIdPlusOneReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(tlsIdPlusOneReg, tlsStorageReg, 0, MicroOpBits::B64);

        const MicroLabelRef haveTlsIdLabel = builder.createLabel();
        builder.emitCmpRegImm(tlsIdPlusOneReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, haveTlsIdLabel);

        const CallConvKind          tlsAllocCallConvKind = tlsAllocFunction->callConvKind();
        const ABICall::PreparedCall preparedTlsAllocCall = ABICall::prepareArgs(builder, tlsAllocCallConvKind, {});
        ABICall::callLocal(builder, tlsAllocCallConvKind, tlsAllocFunction, preparedTlsAllocCall);

        const CallConv&                        tlsAllocCallConv = CallConv::get(tlsAllocCallConvKind);
        const ABITypeNormalize::NormalizedType tlsAllocRet      = ABITypeNormalize::normalize(codeGen.ctx(), tlsAllocCallConv, tlsAllocFunction->returnTypeRef(), ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!tlsAllocRet.isVoid);
        SWC_ASSERT(!tlsAllocRet.isIndirect);

        ABICall::materializeReturnToReg(builder, tlsIdPlusOneReg, tlsAllocCallConvKind, tlsAllocRet);
        builder.emitOpBinaryRegImm(tlsIdPlusOneReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitLoadMemReg(tlsStorageReg, 0, tlsIdPlusOneReg, MicroOpBits::B64);
        builder.placeLabel(haveTlsIdLabel);

        const MicroReg tlsIdReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(tlsIdReg, tlsIdPlusOneReg, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(tlsIdReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);

        const TypeRef      contextTypeRef     = codeGen.typeMgr().structContext();
        const TypeInfo&    contextType        = codeGen.typeMgr().get(contextTypeRef);
        const ConstantRef  initContextCstRef  = makeZeroStructConstant(codeGen, contextTypeRef);
        CodeGenNodePayload initContextPayload = makeAddressPayloadFromConstant(codeGen, initContextCstRef);
        initContextPayload.setIsValue();

        const MicroReg contextSizeReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(contextSizeReg, ApInt(contextType.sizeOf(codeGen.ctx()), 64), MicroOpBits::B64);

        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.push_back({
            .srcReg      = tlsIdReg,
            .kind        = ABICall::PreparedArgKind::Direct,
            .isFloat     = false,
            .isAddressed = false,
            .numBits     = 64,
        });
        preparedArgs.push_back({
            .srcReg      = contextSizeReg,
            .kind        = ABICall::PreparedArgKind::Direct,
            .isFloat     = false,
            .isAddressed = false,
            .numBits     = 64,
        });
        preparedArgs.push_back({
            .srcReg      = initContextPayload.reg,
            .kind        = ABICall::PreparedArgKind::Direct,
            .isFloat     = false,
            .isAddressed = false,
            .numBits     = 64,
        });

        const CallConvKind          tlsGetPtrCallConvKind = tlsGetPtrFunction->callConvKind();
        const ABICall::PreparedCall preparedTlsGetPtrCall = ABICall::prepareArgs(builder, tlsGetPtrCallConvKind, preparedArgs.span());
        ABICall::callLocal(builder, tlsGetPtrCallConvKind, tlsGetPtrFunction, preparedTlsGetPtrCall);

        const CallConv&                        tlsGetPtrCallConv = CallConv::get(tlsGetPtrCallConvKind);
        const ABITypeNormalize::NormalizedType tlsGetPtrRet      = ABITypeNormalize::normalize(codeGen.ctx(), tlsGetPtrCallConv, codeGen.curViewType().typeRef(), ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!tlsGetPtrRet.isVoid);
        SWC_ASSERT(!tlsGetPtrRet.isIndirect);

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        ABICall::materializeReturnToReg(builder, resultPayload.reg, tlsGetPtrCallConvKind, tlsGetPtrRet);
        return Result::Continue;
    }

    Result codeGenGetContext(CodeGen& codeGen)
    {
        if (codeGen.isNativeBuild())
            return codeGenGetContextNative(codeGen);

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

Result AstIntrinsicValue::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicIndex:
        {
            const MicroReg indexReg = codeGen.frame().currentLoopIndexReg();
            SWC_ASSERT(indexReg.isValid());

            TypeRef indexTypeRef = codeGen.frame().currentLoopIndexTypeRef();
            if (indexTypeRef.isInvalid())
                indexTypeRef = codeGen.curViewType().typeRef();

            const CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef(), indexTypeRef);
            auto                      opBits  = MicroOpBits::B64;
            if (indexTypeRef.isValid())
            {
                const uint64_t sizeOfType = codeGen.typeMgr().get(indexTypeRef).sizeOf(codeGen.ctx());
                if (sizeOfType == 1 || sizeOfType == 2 || sizeOfType == 4 || sizeOfType == 8)
                    opBits = microOpBitsFromChunkSize(static_cast<uint32_t>(sizeOfType));
            }

            codeGen.builder().emitLoadRegReg(payload.reg, indexReg, opBits);
            return Result::Continue;
        }

        default:
            SWC_UNREACHABLE();
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
        case TokenId::IntrinsicTableOf:
            return codeGenTableOf(codeGen, *this);
        case TokenId::IntrinsicMakeAny:
            return codeGenMakeAny(codeGen, *this);
        case TokenId::IntrinsicMakeSlice:
            return codeGenMakeSlice(codeGen, *this, false);
        case TokenId::IntrinsicMakeString:
            return codeGenMakeSlice(codeGen, *this, true);
        case TokenId::IntrinsicMakeInterface:
            return codeGenMakeInterface(codeGen, *this);

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
        case TokenId::IntrinsicProcessInfos:
            return codeGenProcessInfos(codeGen);
        case TokenId::IntrinsicGvtd:
            return codeGenGvtd(codeGen);
        case TokenId::IntrinsicCompiler:
            return codeGenCompiler(codeGen);
        case TokenId::IntrinsicBreakpoint:
            codeGen.builder().emitBreakpoint();
            return Result::Continue;

        default:
            return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, nodeExprRef);
    }
}

SWC_END_NAMESPACE();
