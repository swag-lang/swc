#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenInterfaceHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenReferenceHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/CompilerInstance.h"
#include "Support/Math/Fold.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_RUNTIME_EXCEPTION_KIND_ASSERT = 3;

    ConstantRef makeZeroStructConstant(CodeGen& codeGen, TypeRef typeRef)
    {
        const ConstantRef cstRef = codeGen.cstMgr().addZeroPayloadConstant(codeGen.ctx(), typeRef);
        SWC_ASSERT(cstRef.isValid());
        return cstRef;
    }

    CodeGenNodePayload makeAddressPayloadFromConstant(CodeGen& codeGen, ConstantRef cstRef)
    {
        const ConstantValue& cst = codeGen.cstMgr().get(cstRef);
        SWC_ASSERT(cst.isStruct() || cst.isArray());

        const std::span<const std::byte> bytes = cst.isStruct() ? cst.getStruct() : cst.getArray();
        const uint64_t                   addr  = reinterpret_cast<uint64_t>(bytes.data());

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

    using CodeGenInterfaceHelpers::InterfaceCastInfo;

    struct InterfaceMakeRuntimeCandidate
    {
        TypeRef           objectTypeRef = TypeRef::invalid();
        InterfaceCastInfo castInfo;
    };

    struct InterfaceTableRuntimeCandidate
    {
        TypeRef           objectTypeRef    = TypeRef::invalid();
        TypeRef           interfaceTypeRef = TypeRef::invalid();
        InterfaceCastInfo castInfo;
    };

    struct PreparedInterfaceMakeRuntimeCandidate
    {
        ConstantRef       objectTypeCstRef     = ConstantRef::invalid();
        ConstantRef       interfaceTableCstRef = ConstantRef::invalid();
        InterfaceCastInfo castInfo;
    };

    struct PreparedInterfaceTableRuntimeCandidate
    {
        ConstantRef objectTypeCstRef     = ConstantRef::invalid();
        ConstantRef interfaceTypeCstRef  = ConstantRef::invalid();
        ConstantRef interfaceTableCstRef = ConstantRef::invalid();
    };

    void collectRuntimeInterfaceSymbolsRec(const SymbolMap& symbolMap, SmallVector<const SymbolInterface*>& outSymbols, std::unordered_set<const SymbolInterface*>& seenSymbols)
    {
        std::vector<const Symbol*> symbols;
        symbolMap.getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            SWC_ASSERT(symbol != nullptr);

            if (symbol->isInterface())
            {
                const auto* symInterface = &symbol->cast<SymbolInterface>();
                if (seenSymbols.insert(symInterface).second)
                    outSymbols.push_back(symInterface);
            }

            if (symbol->isModule() || symbol->isNamespace() || symbol->isStruct())
                collectRuntimeInterfaceSymbolsRec(*symbol->asSymMap(), outSymbols, seenSymbols);
        }
    }

    TypeRef intrinsicNumericStorageTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& typeInfo       = codeGen.typeMgr().get(typeRef);
        const TypeRef   storageTypeRef = typeInfo.unwrapAliasEnum(codeGen.ctx(), typeRef);
        return storageTypeRef.isValid() ? storageTypeRef : typeRef;
    }

    void loadIntrinsicNumericOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        const TypeRef operandStorageTypeRef = intrinsicNumericStorageTypeRef(codeGen, operandTypeRef);
        outReg                              = codeGen.nextVirtualRegisterForType(operandStorageTypeRef);
        const TypeInfo&   operandType       = codeGen.typeMgr().get(operandStorageTypeRef);
        const MicroOpBits opBits            = CodeGenTypeHelpers::numericBits(operandType);
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

        const TypeRef srcStorageTypeRef = intrinsicNumericStorageTypeRef(codeGen, srcTypeRef);
        const TypeRef dstStorageTypeRef = intrinsicNumericStorageTypeRef(codeGen, dstTypeRef);
        if (srcStorageTypeRef == dstStorageTypeRef)
            return;

        const TypeInfo&   srcType = codeGen.typeMgr().get(srcStorageTypeRef);
        const TypeInfo&   dstType = codeGen.typeMgr().get(dstStorageTypeRef);
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

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstStorageTypeRef);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, srcReg, MicroOp::ConvertIntToFloat, dstBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isFloat() && dstType.isFloat())
        {
            if (srcBits == dstBits)
                return;

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstStorageTypeRef);
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

    Result emitIntrinsicRuntimeCall(CodeGen& codeGen, SymbolFunction& runtimeFunction, std::span<const MicroReg> argRegs, MicroReg resultReg)
    {
        codeGen.function().addCallDependency(&runtimeFunction);

        const CallConvKind                callConvKind = runtimeFunction.callConvKind();
        const CallConv&                   callConv     = CallConv::get(callConvKind);
        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(argRegs.size());

        const auto& params = runtimeFunction.parameters();
        SWC_ASSERT(params.size() == argRegs.size());
        for (size_t i = 0; i < argRegs.size(); ++i)
        {
            SWC_ASSERT(params[i] != nullptr);
            CodeGenCallHelpers::appendDirectPreparedArg(preparedArgs, codeGen, callConv, params[i]->typeRef(), argRegs[i]);
        }

        CodeGenCallHelpers::isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);

        MicroBuilder&               builder      = codeGen.builder();
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        if (runtimeFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &runtimeFunction, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &runtimeFunction, preparedCall);

        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, runtimeFunction.returnTypeRef(), ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!normalizedRet.isVoid);
        SWC_ASSERT(!normalizedRet.isIndirect);
        ABICall::materializeReturnToReg(builder, resultReg, callConvKind, normalizedRet);
        return Result::Continue;
    }

    TypeRef intrinsicOperandTypeRef(CodeGen& codeGen, AstNodeRef nodeRef, const CodeGenNodePayload& payload)
    {
        if (payload.typeRef.isValid())
            return payload.typeRef;
        return codeGen.viewType(nodeRef).typeRef();
    }

    using CodeGenInterfaceHelpers::prepareInterfaceMethodTable;
    using CodeGenInterfaceHelpers::resolveInterfaceCastInfo;

    Result prepareTypeInfoValuePointer(ConstantRef& outRef, CodeGen& codeGen, TypeRef typeRef, AstNodeRef ownerNodeRef)
    {
        SWC_RESULT(codeGen.cstMgr().makeTypeInfo(codeGen.sema(), outRef, typeRef, ownerNodeRef));
        const ConstantValue& typeInfoCst = codeGen.cstMgr().get(outRef);
        SWC_ASSERT(typeInfoCst.isValuePointer());
        return Result::Continue;
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
                const auto& symStruct = symbol->cast<SymbolStruct>();
                if (!symStruct.isTyped() || !symStruct.isSemaCompleted())
                    continue;

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

    void collectTableOfRuntimeCandidatesRec(CodeGen& codeGen, const SymbolMap& symbolMap, std::span<const SymbolInterface* const> interfaces, SmallVector<InterfaceTableRuntimeCandidate>& outCandidates)
    {
        std::vector<const Symbol*> symbols;
        symbolMap.getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            SWC_ASSERT(symbol != nullptr);

            if (symbol->isStruct())
            {
                const auto& symStruct = symbol->cast<SymbolStruct>();
                if (!symStruct.isTyped() || !symStruct.isSemaCompleted())
                {
                    collectTableOfRuntimeCandidatesRec(codeGen, *symStruct.asSymMap(), interfaces, outCandidates);
                    continue;
                }

                const TypeRef objectTypeRef = symStruct.typeRef();
                if (objectTypeRef.isValid())
                {
                    const TypeInfo& objectType = codeGen.typeMgr().get(objectTypeRef);
                    if (objectType.isStruct())
                    {
                        for (const SymbolInterface* interfaceSym : interfaces)
                        {
                            SWC_ASSERT(interfaceSym != nullptr);
                            InterfaceCastInfo castInfo;
                            if (resolveInterfaceCastInfo(codeGen, objectType.payloadSymStruct(), *interfaceSym, castInfo))
                                outCandidates.push_back({.objectTypeRef = objectTypeRef, .interfaceTypeRef = interfaceSym->typeRef(), .castInfo = castInfo});
                        }
                    }
                }

                collectTableOfRuntimeCandidatesRec(codeGen, *symStruct.asSymMap(), interfaces, outCandidates);
                continue;
            }

            if (symbol->isModule() || symbol->isNamespace())
                collectTableOfRuntimeCandidatesRec(codeGen, *symbol->asSymMap(), interfaces, outCandidates);
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

    using CodeGenInterfaceHelpers::emitLoadInterfaceMethodTableAddress;

    MicroReg materializeInterfaceObjectPointer(CodeGen& codeGen, const CodeGenNodePayload& objectPayload, TypeRef objectValueTypeRef, const MicroReg runtimeStorageReg, const uint64_t objectSpillOffset)
    {
        MicroBuilder&   builder         = codeGen.builder();
        const TypeInfo& objectValueType = codeGen.typeMgr().get(objectValueTypeRef);

        if (objectValueType.isNull())
        {
            const MicroReg objectReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegImm(objectReg, ApInt(0, 64), MicroOpBits::B64);
            return objectReg;
        }

        if (objectValueType.isPointerLikeAliasAware(codeGen.ctx()) || objectValueType.isReference())
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

    Result emitMakeInterfaceValue(CodeGen& codeGen, const SymbolInterface& interfaceSym, const InterfaceCastInfo& castInfo, ConstantRef interfaceTableCstRef, const CodeGenNodePayload& objectPayload, TypeRef objectValueTypeRef, const MicroReg runtimeStorageReg, const uint64_t objectSpillOffset)
    {
        MicroBuilder&   builder         = codeGen.builder();
        const TypeInfo& objectValueType = codeGen.typeMgr().get(objectValueTypeRef);
        SWC_UNUSED(interfaceSym);

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
        MicroReg itableReg = MicroReg::invalid();
        emitLoadInterfaceMethodTableAddress(itableReg, codeGen, interfaceTableCstRef);
        builder.emitLoadMemReg(runtimeStorageReg, offsetof(Runtime::Interface, itable), itableReg, MicroOpBits::B64);
        return Result::Continue;
    }

    void emitTypeInfoIdentityMatchOrJump(CodeGen& codeGen, MicroReg runtimeTypeReg, MicroReg candidateTypeReg, MicroLabelRef matchLabel, MicroLabelRef mismatchLabel);

    // Build an interface value by reading the method table straight from the runtime typeinfo's
    // interface array (TypeValue.value, wired by TypeGen). This is the only mechanism that works
    // when the implementing struct lives in a module that the call site cannot enumerate as a
    // static candidate (e.g. `parseValue` in core building an interface for `Pixel.Color`). On a
    // match it fills `runtimeStorage` and jumps to `doneLabel`; otherwise it falls through leaving
    // the (already zeroed) storage untouched.
    Result emitMakeInterfaceFromRuntimeTypeInfo(CodeGen& codeGen, TypeRef interfaceTypeRef, AstNodeRef typeRefNode, MicroReg typeInfoReg, const CodeGenNodePayload& objectPayload, TypeRef objectValueTypeRef, MicroReg runtimeStorageReg, uint64_t objectSpillOffset, MicroLabelRef doneLabel)
    {
        MicroBuilder& builder = codeGen.builder();

        ConstantRef itfTypeCstRef = ConstantRef::invalid();
        SWC_RESULT(prepareTypeInfoValuePointer(itfTypeCstRef, codeGen, interfaceTypeRef, typeRefNode));
        if (!itfTypeCstRef.isValid())
            return Result::Continue;
        const ConstantValue& itfTypeCst = codeGen.cstMgr().get(itfTypeCstRef);
        SWC_ASSERT(itfTypeCst.isValuePointer());

        const MicroLabelRef skipLabel = builder.createLabel();

        // Only a non-null struct typeinfo carries an interface array.
        builder.emitCmpRegImm(typeInfoReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, skipLabel);
        const MicroReg kindReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(kindReg, typeInfoReg, offsetof(Runtime::TypeInfo, kind), MicroOpBits::B8);
        builder.emitCmpRegImm(kindReg, ApInt(static_cast<uint64_t>(Runtime::TypeInfoKind::Struct), 8), MicroOpBits::B8);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, skipLabel);

        const MicroReg entryReg = codeGen.nextVirtualIntRegister();
        const MicroReg cntReg   = codeGen.nextVirtualIntRegister();
        const MicroReg idxReg   = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(entryReg, typeInfoReg, offsetof(Runtime::TypeInfoStruct, interfaces), MicroOpBits::B64);
        builder.emitLoadRegMem(cntReg, typeInfoReg, offsetof(Runtime::TypeInfoStruct, interfaces) + static_cast<uint32_t>(sizeof(void*)), MicroOpBits::B64);
        builder.emitLoadRegImm(idxReg, ApInt(0, 64), MicroOpBits::B64);

        const MicroLabelRef loopLabel = builder.createLabel();
        const MicroLabelRef nextLabel = builder.createLabel();
        builder.placeLabel(loopLabel);
        builder.emitCmpRegReg(idxReg, cntReg, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, skipLabel);

        const MicroReg pointedTypeReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(pointedTypeReg, entryReg, offsetof(Runtime::TypeValue, pointedType), MicroOpBits::B64);
        const MicroReg itfTypeReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegPtrReloc(itfTypeReg, itfTypeCst.getValuePointer(), itfTypeCstRef);

        const MicroLabelRef matchLabel = builder.createLabel();
        emitTypeInfoIdentityMatchOrJump(codeGen, pointedTypeReg, itfTypeReg, matchLabel, nextLabel);

        builder.placeLabel(matchLabel);
        const MicroReg itableReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(itableReg, entryReg, offsetof(Runtime::TypeValue, value), MicroOpBits::B64);
        const MicroReg objReg = materializeInterfaceObjectPointer(codeGen, objectPayload, objectValueTypeRef, runtimeStorageReg, objectSpillOffset);
        builder.emitLoadMemReg(runtimeStorageReg, offsetof(Runtime::Interface, obj), objReg, MicroOpBits::B64);
        builder.emitLoadMemReg(runtimeStorageReg, offsetof(Runtime::Interface, itable), itableReg, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

        builder.placeLabel(nextLabel);
        builder.emitOpBinaryRegImm(entryReg, ApInt(sizeof(Runtime::TypeValue), 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(idxReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopLabel);

        builder.placeLabel(skipLabel);
        return Result::Continue;
    }

    // `@tableof` counterpart of emitMakeInterfaceFromRuntimeTypeInfo: read the method table from the
    // runtime typeinfo's interface array. On a match writes the itable to `outTableReg` and jumps to
    // `doneLabel`; otherwise falls through leaving `outTableReg` untouched.
    Result emitTableOfFromRuntimeTypeInfo(CodeGen& codeGen, MicroReg objectTypeReg, MicroReg interfaceTypeReg, MicroReg outTableReg, MicroLabelRef doneLabel)
    {
        MicroBuilder&       builder   = codeGen.builder();
        const MicroLabelRef skipLabel = builder.createLabel();

        builder.emitCmpRegImm(objectTypeReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, skipLabel);
        const MicroReg kindReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(kindReg, objectTypeReg, offsetof(Runtime::TypeInfo, kind), MicroOpBits::B8);
        builder.emitCmpRegImm(kindReg, ApInt(static_cast<uint64_t>(Runtime::TypeInfoKind::Struct), 8), MicroOpBits::B8);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, skipLabel);

        const MicroReg entryReg = codeGen.nextVirtualIntRegister();
        const MicroReg cntReg   = codeGen.nextVirtualIntRegister();
        const MicroReg idxReg   = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(entryReg, objectTypeReg, offsetof(Runtime::TypeInfoStruct, interfaces), MicroOpBits::B64);
        builder.emitLoadRegMem(cntReg, objectTypeReg, offsetof(Runtime::TypeInfoStruct, interfaces) + static_cast<uint32_t>(sizeof(void*)), MicroOpBits::B64);
        builder.emitLoadRegImm(idxReg, ApInt(0, 64), MicroOpBits::B64);

        const MicroLabelRef loopLabel = builder.createLabel();
        const MicroLabelRef nextLabel = builder.createLabel();
        builder.placeLabel(loopLabel);
        builder.emitCmpRegReg(idxReg, cntReg, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, skipLabel);

        const MicroReg pointedTypeReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(pointedTypeReg, entryReg, offsetof(Runtime::TypeValue, pointedType), MicroOpBits::B64);

        const MicroLabelRef matchLabel = builder.createLabel();
        emitTypeInfoIdentityMatchOrJump(codeGen, pointedTypeReg, interfaceTypeReg, matchLabel, nextLabel);

        builder.placeLabel(matchLabel);
        builder.emitLoadRegMem(outTableReg, entryReg, offsetof(Runtime::TypeValue, value), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

        builder.placeLabel(nextLabel);
        builder.emitOpBinaryRegImm(entryReg, ApInt(sizeof(Runtime::TypeValue), 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(idxReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopLabel);

        builder.placeLabel(skipLabel);
        return Result::Continue;
    }

    Result codeGenAtomicBinaryRmw(CodeGen& codeGen, const AstIntrinsicCallExpr& node, MicroOp op)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 2);

        const AstNodeRef          ptrRef               = children[0];
        const AstNodeRef          valueRef             = children[1];
        const CodeGenNodePayload& ptrPayload           = codeGen.payload(ptrRef);
        const CodeGenNodePayload& valuePayload         = codeGen.payload(valueRef);
        const TypeRef             valueTypeRef         = intrinsicOperandTypeRef(codeGen, valueRef, valuePayload);
        const TypeRef             resultTypeRef        = codeGen.curViewType().typeRef();
        const TypeRef             resultStorageTypeRef = intrinsicNumericStorageTypeRef(codeGen, resultTypeRef);
        const TypeInfo&           resultTypeInfo       = codeGen.typeMgr().get(resultStorageTypeRef);
        const MicroOpBits         opBits               = CodeGenTypeHelpers::numericBits(resultTypeInfo);
        MicroBuilder&             builder              = codeGen.builder();

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

        const AstNodeRef          ptrRef               = children[0];
        const AstNodeRef          valueRef             = children[1];
        const CodeGenNodePayload& ptrPayload           = codeGen.payload(ptrRef);
        const CodeGenNodePayload& valuePayload         = codeGen.payload(valueRef);
        const TypeRef             valueTypeRef         = intrinsicOperandTypeRef(codeGen, valueRef, valuePayload);
        const TypeRef             resultTypeRef        = codeGen.curViewType().typeRef();
        const TypeRef             resultStorageTypeRef = intrinsicNumericStorageTypeRef(codeGen, resultTypeRef);
        const TypeInfo&           resultTypeInfo       = codeGen.typeMgr().get(resultStorageTypeRef);
        const MicroOpBits         opBits               = CodeGenTypeHelpers::numericBits(resultTypeInfo);
        MicroBuilder&             builder              = codeGen.builder();

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

        const AstNodeRef          ptrRef               = children[0];
        const AstNodeRef          compareRef           = children[1];
        const AstNodeRef          exchangeRef          = children[2];
        const CodeGenNodePayload& ptrPayload           = codeGen.payload(ptrRef);
        const CodeGenNodePayload& comparePayload       = codeGen.payload(compareRef);
        const CodeGenNodePayload& exchangePayload      = codeGen.payload(exchangeRef);
        const TypeRef             compareTypeRef       = intrinsicOperandTypeRef(codeGen, compareRef, comparePayload);
        const TypeRef             exchangeTypeRef      = intrinsicOperandTypeRef(codeGen, exchangeRef, exchangePayload);
        const TypeRef             resultTypeRef        = codeGen.curViewType().typeRef();
        const TypeRef             resultStorageTypeRef = intrinsicNumericStorageTypeRef(codeGen, resultTypeRef);
        const TypeInfo&           resultTypeInfo       = codeGen.typeMgr().get(resultStorageTypeRef);
        const MicroOpBits         opBits               = CodeGenTypeHelpers::numericBits(resultTypeInfo);
        MicroBuilder&             builder              = codeGen.builder();

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

        codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeStorageReg, resultTypeRef);
        return Result::Continue;
    }

    // Emit a cross-module-stable type identity check between a runtime type info
    // pointer and a compile-time candidate type info. Types reflected from an
    // imported API are regenerated locally in every importing module, so the same
    // logical type has a different `TypeInfo` pointer per module; their reflection
    // `crc` identity stays equal (the same identity `@is`/`@typecmp` rely on).
    // On match, falls through to the following code; otherwise jumps to mismatchLabel.
    void emitTypeInfoIdentityMatchOrJump(CodeGen& codeGen, MicroReg runtimeTypeReg, MicroReg candidateTypeReg, MicroLabelRef matchLabel, MicroLabelRef mismatchLabel)
    {
        MicroBuilder& builder = codeGen.builder();

        // Fast path: identical pointer (same module) is an immediate match.
        builder.emitCmpRegReg(runtimeTypeReg, candidateTypeReg, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, matchLabel);

        // The candidate is a compile-time constant pointer, so it is never null; a
        // null runtime type cannot match and must not be dereferenced for its crc.
        builder.emitCmpRegImm(runtimeTypeReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, mismatchLabel);

        const MicroReg runtimeCrcReg   = codeGen.nextVirtualIntRegister();
        const MicroReg candidateCrcReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(runtimeCrcReg, runtimeTypeReg, offsetof(Runtime::TypeInfo, crc), MicroOpBits::B32);
        builder.emitLoadRegMem(candidateCrcReg, candidateTypeReg, offsetof(Runtime::TypeInfo, crc), MicroOpBits::B32);
        builder.emitCmpRegReg(runtimeCrcReg, candidateCrcReg, MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, mismatchLabel);
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

        InterfaceCastInfo directCastInfo;
        ConstantRef       directInterfaceTableCstRef = ConstantRef::invalid();
        bool              hasDirectCastInfo          = false;
        if (objectTypeRef.isValid())
        {
            const TypeInfo& concreteObjectType = codeGen.typeMgr().get(objectTypeRef);
            if (concreteObjectType.isStruct())
            {
                hasDirectCastInfo = resolveInterfaceCastInfo(codeGen, concreteObjectType.payloadSymStruct(), resultType.payloadSymInterface(), directCastInfo);
                if (hasDirectCastInfo)
                    SWC_RESULT(prepareInterfaceMethodTable(directInterfaceTableCstRef, codeGen, directCastInfo));
            }

            CodeGenMemoryHelpers::emitMemZero(codeGen, runtimeStorageReg, interfaceSize);
            if (hasDirectCastInfo)
                SWC_RESULT(emitMakeInterfaceValue(codeGen, resultType.payloadSymInterface(), directCastInfo, directInterfaceTableCstRef, objectPayload, objectValueTypeRef, runtimeStorageReg, objectSpillOff));

            codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeStorageReg, resultTypeRef);
            return Result::Continue;
        }

        SmallVector<InterfaceMakeRuntimeCandidate> candidates;
        if (const SymbolModule* rootModule = codeGen.compiler().symModule())
            collectMakeInterfaceRuntimeCandidatesRec(codeGen, *rootModule, resultType.payloadSymInterface(), candidates);
        // Imported modules' symbols live under the import-root namespace (siblings of this module),
        // so enumerate them too — otherwise an imported struct could not be matched as a candidate.
        if (const SymbolNamespace* importRoot = codeGen.compiler().importRootNamespace())
            collectMakeInterfaceRuntimeCandidatesRec(codeGen, *importRoot, resultType.payloadSymInterface(), candidates);

        SmallVector<PreparedInterfaceMakeRuntimeCandidate> preparedCandidates;
        preparedCandidates.reserve(candidates.size());
        for (const auto& candidate : candidates)
        {
            ConstantRef objectTypeCstRef = ConstantRef::invalid();
            SWC_RESULT(prepareTypeInfoValuePointer(objectTypeCstRef, codeGen, candidate.objectTypeRef, typeRefNode));

            ConstantRef interfaceTableCstRef = ConstantRef::invalid();
            SWC_RESULT(prepareInterfaceMethodTable(interfaceTableCstRef, codeGen, candidate.castInfo, true));
            if (!interfaceTableCstRef.isValid())
                continue;

            preparedCandidates.push_back({.objectTypeCstRef = objectTypeCstRef, .interfaceTableCstRef = interfaceTableCstRef, .castInfo = candidate.castInfo});
        }

        CodeGenMemoryHelpers::emitMemZero(codeGen, runtimeStorageReg, interfaceSize);

        const MicroReg      typeInfoReg = materializeIntrinsicIntArgReg(codeGen, typePayload, MicroOpBits::B64);
        const MicroLabelRef doneLabel   = builder.createLabel();

        // Static candidates first: they share `ensureInterfaceMethodTable`'s cached constant with
        // the direct path and `@tableof`, so all routes to the same (struct, interface) yield one
        // itable pointer.
        for (const auto& candidate : preparedCandidates)
        {
            const ConstantValue& typeInfoCst = codeGen.cstMgr().get(candidate.objectTypeCstRef);
            SWC_ASSERT(typeInfoCst.isValuePointer());

            const MicroLabelRef nextLabel        = builder.createLabel();
            const MicroLabelRef matchLabel       = builder.createLabel();
            const MicroReg      candidateTypeReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegPtrReloc(candidateTypeReg, typeInfoCst.getValuePointer(), candidate.objectTypeCstRef);
            emitTypeInfoIdentityMatchOrJump(codeGen, typeInfoReg, candidateTypeReg, matchLabel, nextLabel);
            builder.placeLabel(matchLabel);
            SWC_RESULT(emitMakeInterfaceValue(codeGen, resultType.payloadSymInterface(), candidate.castInfo, candidate.interfaceTableCstRef, objectPayload, objectValueTypeRef, runtimeStorageReg, objectSpillOff));
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
            builder.placeLabel(nextLabel);
        }

        // Fallback: read the itable from the runtime typeinfo. Required when no module at this call
        // site enumerates the implementing struct as a candidate (e.g. core's `parseValue` for
        // `Pixel.Color`).
        SWC_RESULT(emitMakeInterfaceFromRuntimeTypeInfo(codeGen, resultTypeRef, typeRefNode, typeInfoReg, objectPayload, objectValueTypeRef, runtimeStorageReg, objectSpillOff, doneLabel));

        builder.placeLabel(doneLabel);

        codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeStorageReg, resultTypeRef);
        return Result::Continue;
    }

    Result codeGenIntrinsicIs(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 2);

        const auto* payload = codeGen.loweringPayload(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->runtimeFunctionSymbol != nullptr);

        const MicroReg toTypeReg   = materializeIntrinsicIntArgReg(codeGen, codeGen.payload(children[0]), MicroOpBits::B64);
        const MicroReg fromTypeReg = materializeIntrinsicIntArgReg(codeGen, codeGen.payload(children[1]), MicroOpBits::B64);

        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        const MicroReg            args[]        = {toTypeReg, fromTypeReg};
        return emitIntrinsicRuntimeCall(codeGen, *payload->runtimeFunctionSymbol, args, resultPayload.reg);
    }

    Result codeGenIntrinsicAs(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 3);

        const auto* payload = codeGen.loweringPayload(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->runtimeFunctionSymbol != nullptr);

        const MicroReg toTypeReg   = materializeIntrinsicIntArgReg(codeGen, codeGen.payload(children[0]), MicroOpBits::B64);
        const MicroReg fromTypeReg = materializeIntrinsicIntArgReg(codeGen, codeGen.payload(children[1]), MicroOpBits::B64);
        const MicroReg ptrReg      = materializeIntrinsicIntArgReg(codeGen, codeGen.payload(children[2]), MicroOpBits::B64);

        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        const MicroReg            args[]        = {toTypeReg, fromTypeReg, ptrReg};
        return emitIntrinsicRuntimeCall(codeGen, *payload->runtimeFunctionSymbol, args, resultPayload.reg);
    }

    Result codeGenIntrinsicTableOf(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 2);

        const TypeRef resultTypeRef = codeGen.curViewType().typeRef();

        SmallVector<const SymbolInterface*>        interfaces;
        std::unordered_set<const SymbolInterface*> seenInterfaces;
        const SymbolModule*                        rootModule = codeGen.compiler().symModule();
        const SymbolNamespace*                     importRoot = codeGen.compiler().importRootNamespace();
        if (rootModule)
            collectRuntimeInterfaceSymbolsRec(*rootModule, interfaces, seenInterfaces);
        if (importRoot)
            collectRuntimeInterfaceSymbolsRec(*importRoot, interfaces, seenInterfaces);

        SmallVector<InterfaceTableRuntimeCandidate> candidates;
        if (!interfaces.empty())
        {
            if (rootModule)
                collectTableOfRuntimeCandidatesRec(codeGen, *rootModule, interfaces.span(), candidates);
            // Imported structs live under the import-root namespace; enumerate them too.
            if (importRoot)
                collectTableOfRuntimeCandidatesRec(codeGen, *importRoot, interfaces.span(), candidates);
        }

        SmallVector<PreparedInterfaceTableRuntimeCandidate> preparedCandidates;
        preparedCandidates.reserve(candidates.size());
        for (const auto& candidate : candidates)
        {
            ConstantRef objectTypeCstRef = ConstantRef::invalid();
            SWC_RESULT(prepareTypeInfoValuePointer(objectTypeCstRef, codeGen, candidate.objectTypeRef, children[0]));

            ConstantRef interfaceTypeCstRef = ConstantRef::invalid();
            SWC_RESULT(prepareTypeInfoValuePointer(interfaceTypeCstRef, codeGen, candidate.interfaceTypeRef, children[1]));

            ConstantRef interfaceTableCstRef = ConstantRef::invalid();
            SWC_RESULT(prepareInterfaceMethodTable(interfaceTableCstRef, codeGen, candidate.castInfo, true));
            if (!interfaceTableCstRef.isValid())
                continue;

            preparedCandidates.push_back({.objectTypeCstRef = objectTypeCstRef, .interfaceTypeCstRef = interfaceTypeCstRef, .interfaceTableCstRef = interfaceTableCstRef});
        }

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        MicroBuilder&             builder       = codeGen.builder();
        builder.emitLoadRegImm(resultPayload.reg, ApInt(0, 64), MicroOpBits::B64);

        const MicroReg      objectTypeReg    = materializeIntrinsicIntArgReg(codeGen, codeGen.payload(children[0]), MicroOpBits::B64);
        const MicroReg      interfaceTypeReg = materializeIntrinsicIntArgReg(codeGen, codeGen.payload(children[1]), MicroOpBits::B64);
        const MicroLabelRef doneLabel        = builder.createLabel();

        // Static candidates first (share `ensureInterfaceMethodTable`'s cached constant with
        // `@mkinterface`, so both intrinsics yield the same itable pointer).
        for (const auto& candidate : preparedCandidates)
        {
            const ConstantValue& objectTypeCst = codeGen.cstMgr().get(candidate.objectTypeCstRef);
            SWC_ASSERT(objectTypeCst.isValuePointer());

            const ConstantValue& interfaceTypeCst = codeGen.cstMgr().get(candidate.interfaceTypeCstRef);
            SWC_ASSERT(interfaceTypeCst.isValuePointer());

            const MicroLabelRef nextLabel          = builder.createLabel();
            const MicroReg      candidateObjectReg = codeGen.nextVirtualIntRegister();
            const MicroReg      candidateItfReg    = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegPtrReloc(candidateObjectReg, objectTypeCst.getValuePointer(), candidate.objectTypeCstRef);
            builder.emitCmpRegReg(objectTypeReg, candidateObjectReg, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, nextLabel);
            builder.emitLoadRegPtrReloc(candidateItfReg, interfaceTypeCst.getValuePointer(), candidate.interfaceTypeCstRef);
            builder.emitCmpRegReg(interfaceTypeReg, candidateItfReg, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, nextLabel);

            MicroReg tableReg = MicroReg::invalid();
            emitLoadInterfaceMethodTableAddress(tableReg, codeGen, candidate.interfaceTableCstRef);
            builder.emitLoadRegReg(resultPayload.reg, tableReg, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
            builder.placeLabel(nextLabel);
        }

        // Fallback: read the itable from the runtime typeinfo (cross-module, where the struct is not
        // an enumerable candidate here).
        SWC_RESULT(emitTableOfFromRuntimeTypeInfo(codeGen, objectTypeReg, interfaceTypeReg, resultPayload.reg, doneLabel));

        builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    Result codeGenDataOf(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        const auto* dataPayload = codeGen.sema().semaPayload<DataOfSpecOpPayload>(codeGen.curNodeRef());
        if (dataPayload && dataPayload->calledFn != nullptr)
        {
            codeGen.sema().setSymbol(codeGen.curNodeRef(), dataPayload->calledFn);
            return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid());
        }

        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(!children.empty());

        const AstNodeRef          exprRef     = children[0];
        CodeGenNodePayload        exprPayload = codeGen.payload(exprRef);
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        TypeRef                   exprTypeRef = exprPayload.effectiveTypeRef(exprView.typeRef());
        const CodeGenNodePayload& payload     = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        MicroBuilder&             builder     = codeGen.builder();
        CodeGenReferenceHelpers::unwrapAliasRefPayload(codeGen, exprPayload, exprTypeRef);
        SWC_ASSERT(exprTypeRef.isValid());
        const TypeInfo& exprType = codeGen.typeMgr().get(exprTypeRef);

        if (exprType.isInterface())
            builder.emitLoadRegMem(payload.reg, exprPayload.reg, offsetof(Runtime::Interface, obj), MicroOpBits::B64);
        else if (exprType.isString() || exprType.isSlice() || exprType.isAny())
            builder.emitLoadRegMem(payload.reg, exprPayload.reg, 0, MicroOpBits::B64);
        else if (exprType.isArray())
        {
            if (exprPayload.isAddress())
            {
                builder.emitLoadRegReg(payload.reg, exprPayload.reg, MicroOpBits::B64);
            }
            else
            {
                const uint32_t copySize = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, exprType);
                SWC_ASSERT(copySize == 1 || copySize == 2 || copySize == 4 || copySize == 8);

                const MicroReg storageReg = codeGen.runtimeStorageAddressReg(exprRef);
                CodeGenMemoryHelpers::storePayloadToAddress(codeGen, storageReg, exprPayload, copySize);
                builder.emitLoadRegReg(payload.reg, storageReg, MicroOpBits::B64);
            }
        }
        else if (exprPayload.isAddress())
            builder.emitLoadRegMem(payload.reg, exprPayload.reg, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(payload.reg, exprPayload.reg, MicroOpBits::B64);
        return Result::Continue;
    }

    // '@isset(x.field)': the operand payload is the '#late' field address; the
    // field is set iff its presence word is non-zero.
    Result codeGenIsSet(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(!children.empty());

        const AstNodeRef          exprRef     = children[0];
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        const TypeRef             exprTypeRef = exprPayload.effectiveTypeRef(exprView.typeRef());

        TypeRef resolvedTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), exprTypeRef);
        if (resolvedTypeRef.isInvalid())
            resolvedTypeRef = exprTypeRef;
        const TypeInfo& fieldType = codeGen.typeMgr().get(resolvedTypeRef);

        const uint64_t sizeOf = fieldType.sizeOf(codeGen.ctx());
        const auto     bits   = sizeOf > sizeof(uint64_t) ? MicroOpBits::B64 : CodeGenTypeHelpers::compareBits(fieldType, codeGen.ctx());
        SWC_ASSERT(bits != MicroOpBits::Zero);

        MicroBuilder&  builder     = codeGen.builder();
        const MicroReg presenceReg = codeGen.nextVirtualIntRegister();
        if (exprPayload.isAddress() || sizeOf > sizeof(uint64_t))
            builder.emitLoadRegMem(presenceReg, exprPayload.reg, 0, bits);
        else
            builder.emitLoadRegReg(presenceReg, exprPayload.reg, bits);

        CodeGenNodePayload& result = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        result.reg                 = codeGen.nextVirtualIntRegister();
        builder.emitCmpRegImm(presenceReg, ApInt(0, 64), bits);
        builder.emitSetCondReg(result.reg, MicroCond::NotEqual);
        return Result::Continue;
    }

    Result codeGenKindOf(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(!children.empty());

        const AstNodeRef    exprRef     = children[0];
        CodeGenNodePayload  exprPayload = codeGen.payload(exprRef);
        const SemaNodeView  exprView    = codeGen.viewType(exprRef);
        TypeRef             exprTypeRef = exprPayload.effectiveTypeRef(exprView.typeRef());
        CodeGenNodePayload& result      = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        MicroBuilder&       builder     = codeGen.builder();
        result.reg                      = codeGen.nextVirtualIntRegister();
        CodeGenReferenceHelpers::unwrapAliasRefPayload(codeGen, exprPayload, exprTypeRef);
        SWC_ASSERT(exprTypeRef.isValid());
        const TypeInfo& exprType = codeGen.typeMgr().get(exprTypeRef);

        if (exprType.isInterface())
        {
            const MicroReg itableReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(itableReg, exprPayload.reg, offsetof(Runtime::Interface, itable), MicroOpBits::B64);

            const MicroLabelRef doneLabel = builder.createLabel();
            builder.emitLoadRegImm(result.reg, ApInt(0, 64), MicroOpBits::B64);
            builder.emitCmpRegImm(itableReg, ApInt(0, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
            builder.emitLoadRegMem(result.reg, itableReg, 0, MicroOpBits::B64);
            builder.placeLabel(doneLabel);
            return Result::Continue;
        }

        const MicroReg anyBaseReg = exprPayload.reg;
        builder.emitLoadRegMem(result.reg, anyBaseReg, offsetof(Runtime::Any, type), MicroOpBits::B64);
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

        const auto* payload = codeGen.loweringPayload(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->runtimeFunctionSymbol != nullptr);

        auto&                             raiseExceptionFunction = *payload->runtimeFunctionSymbol;
        const CallConvKind                callConvKind           = raiseExceptionFunction.callConvKind();
        const CallConv&                   callConv               = CallConv::get(callConvKind);
        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(3);

        const ConstantRef nullMessageRef = makeZeroStructConstant(codeGen, codeGen.typeMgr().typeString());
        const auto        nullMessage    = makeAddressPayloadFromConstant(codeGen, nullMessageRef);

        ConstantRef sourceLocRef = ConstantRef::invalid();
        SWC_RESULT(ConstantHelpers::makeSourceCodeLocation(codeGen.sema(), sourceLocRef, node));
        const auto sourceLoc = makeAddressPayloadFromConstant(codeGen, sourceLocRef);

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
            const TypeRef                          locationTypeRef = codeGen.cstMgr().get(sourceLocRef).typeRef();
            const ABITypeNormalize::NormalizedType normalizedArg   = ABITypeNormalize::normalize(codeGen.ctx(), callConv, locationTypeRef, ABITypeNormalize::Usage::Argument);
            locationArg.kind                                       = ABICall::PreparedArgKind::Direct;
            locationArg.isFloat                                    = normalizedArg.isFloat;
            locationArg.numBits                                    = normalizedArg.numBits;
            locationArg.isAddressed                                = false;
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
        CodeGenCallHelpers::isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);
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

        const MicroLabelRef failLabel = builder.createLabel();
        const MicroLabelRef doneLabel = builder.createLabel();
        SWC_RESULT(CodeGenSafety::emitUnaryMathDomainCheck(codeGen, resultPayload.reg, resultType, Math::FoldIntrinsicUnaryFloatOp::Sqrt, failLabel));
        builder.emitOpBinaryRegReg(resultPayload.reg, resultPayload.reg, MicroOp::FloatSqrt, opBits);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
        builder.placeLabel(failLabel);
        SWC_RESULT(CodeGenSafety::emitMathCheck(codeGen, node));
        builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    Result codeGenAbs(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 1);

        const AstNodeRef          exprRef              = children[0];
        const CodeGenNodePayload& exprPayload          = codeGen.payload(exprRef);
        const SemaNodeView        exprView             = codeGen.viewType(exprRef);
        const TypeRef             exprTypeRef          = exprPayload.typeRef.isValid() ? exprPayload.typeRef : exprView.typeRef();
        const TypeRef             resultTypeRef        = codeGen.curViewType().typeRef();
        const TypeRef             resultStorageTypeRef = intrinsicNumericStorageTypeRef(codeGen, resultTypeRef);
        const TypeInfo&           resultType           = codeGen.typeMgr().get(resultStorageTypeRef);
        const MicroOpBits         opBits               = CodeGenTypeHelpers::numericBits(resultType);
        CodeGenNodePayload&       resultPayload        = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        MicroBuilder&             builder              = codeGen.builder();
        MicroReg                  materializedReg;

        SWC_ASSERT(opBits != MicroOpBits::Zero);
        materializeIntrinsicNumericOperand(materializedReg, codeGen, exprPayload, exprTypeRef, resultTypeRef);

        if (resultType.isFloat())
        {
            resultPayload.reg = codeGen.nextVirtualRegisterForType(resultStorageTypeRef);
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

        const AstNodeRef          leftRef              = children[0];
        const AstNodeRef          rightRef             = children[1];
        const CodeGenNodePayload& leftPayload          = codeGen.payload(leftRef);
        const CodeGenNodePayload& rightPayload         = codeGen.payload(rightRef);
        const SemaNodeView        leftView             = codeGen.viewType(leftRef);
        const SemaNodeView        rightView            = codeGen.viewType(rightRef);
        const TypeRef             leftOperandTypeRef   = leftPayload.typeRef.isValid() ? leftPayload.typeRef : leftView.typeRef();
        const TypeRef             rightOperandTypeRef  = rightPayload.typeRef.isValid() ? rightPayload.typeRef : rightView.typeRef();
        const TypeRef             resultTypeRef        = codeGen.curViewType().typeRef();
        const TypeRef             resultStorageTypeRef = intrinsicNumericStorageTypeRef(codeGen, resultTypeRef);
        const TypeInfo&           resultType           = codeGen.typeMgr().get(resultStorageTypeRef);
        const MicroOpBits         opBits               = CodeGenTypeHelpers::numericBits(resultType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg, rightReg;
        materializeIntrinsicNumericOperand(leftReg, codeGen, leftPayload, leftOperandTypeRef, resultTypeRef);
        materializeIntrinsicNumericOperand(rightReg, codeGen, rightPayload, rightOperandTypeRef, resultTypeRef);

        MicroBuilder&       builder       = codeGen.builder();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);

        if (resultType.isFloat())
        {
            resultPayload.reg = codeGen.nextVirtualRegisterForType(resultStorageTypeRef);
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

        const AstNodeRef          valueRef             = children[0];
        const AstNodeRef          countRef             = children[1];
        const CodeGenNodePayload& valuePayload         = codeGen.payload(valueRef);
        const CodeGenNodePayload& countPayload         = codeGen.payload(countRef);
        const SemaNodeView        valueView            = codeGen.viewType(valueRef);
        const SemaNodeView        countView            = codeGen.viewType(countRef);
        const TypeRef             valueTypeRef         = valuePayload.typeRef.isValid() ? valuePayload.typeRef : valueView.typeRef();
        const TypeRef             countTypeRef         = countPayload.typeRef.isValid() ? countPayload.typeRef : countView.typeRef();
        const TypeRef             resultTypeRef        = codeGen.curViewType().typeRef();
        const TypeRef             resultStorageTypeRef = intrinsicNumericStorageTypeRef(codeGen, resultTypeRef);
        const TypeRef             countStorageTypeRef  = intrinsicNumericStorageTypeRef(codeGen, countTypeRef);
        const TypeInfo&           resultType           = codeGen.typeMgr().get(resultStorageTypeRef);
        const TypeInfo&           countType            = codeGen.typeMgr().get(countStorageTypeRef);
        const MicroOpBits         resultBits           = CodeGenTypeHelpers::numericBits(resultType);
        CodeGenNodePayload&       resultPayload        = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        MicroBuilder&             builder              = codeGen.builder();
        MicroReg                  materializedValue;
        MicroReg                  materializedCount;

        SWC_ASSERT(resultType.isIntLikeUnsigned());
        SWC_ASSERT(countType.isIntLikeUnsigned());
        SWC_ASSERT(resultBits != MicroOpBits::Zero);

        materializeIntrinsicNumericOperand(materializedValue, codeGen, valuePayload, valueTypeRef, resultTypeRef);
        loadIntrinsicNumericOperand(materializedCount, codeGen, countPayload, countStorageTypeRef);

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

        const AstNodeRef          valueRef             = children[0];
        const CodeGenNodePayload& valuePayload         = codeGen.payload(valueRef);
        const SemaNodeView        valueView            = codeGen.viewType(valueRef);
        const TypeRef             valueTypeRef         = valuePayload.typeRef.isValid() ? valuePayload.typeRef : valueView.typeRef();
        const TypeRef             resultTypeRef        = codeGen.curViewType().typeRef();
        const TypeRef             resultStorageTypeRef = intrinsicNumericStorageTypeRef(codeGen, resultTypeRef);
        const TypeInfo&           resultType           = codeGen.typeMgr().get(resultStorageTypeRef);
        const MicroOpBits         resultBits           = CodeGenTypeHelpers::numericBits(resultType);
        CodeGenNodePayload&       resultPayload        = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        MicroBuilder&             builder              = codeGen.builder();
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

        const AstNodeRef          valueRef             = children[0];
        const CodeGenNodePayload& valuePayload         = codeGen.payload(valueRef);
        const SemaNodeView        valueView            = codeGen.viewType(valueRef);
        const TypeRef             valueTypeRef         = valuePayload.typeRef.isValid() ? valuePayload.typeRef : valueView.typeRef();
        const TypeRef             resultTypeRef        = codeGen.curViewType().typeRef();
        const TypeRef             resultStorageTypeRef = intrinsicNumericStorageTypeRef(codeGen, resultTypeRef);
        const TypeInfo&           resultType           = codeGen.typeMgr().get(resultStorageTypeRef);
        const MicroOpBits         resultBits           = CodeGenTypeHelpers::numericBits(resultType);
        const uint32_t            logicalBitWidth      = getNumBits(resultBits);
        CodeGenNodePayload&       resultPayload        = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        MicroBuilder&             builder              = codeGen.builder();
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

        builder.emitLoadRegImm(resultPayload.reg, ApInt(logicalBitWidth, 64), resultBits);
        builder.emitCmpRegImm(materializedValue, ApInt(0, 64), resultBits);
        const MicroLabelRef doneLabel = builder.createLabel();
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

        if (kind == BitCountKind::Tz)
        {
            builder.emitOpBinaryRegReg(resultPayload.reg, materializedValue, MicroOp::BitScanForward, resultBits);
        }
        else
        {
            SWC_ASSERT(kind == BitCountKind::Lz);
            const MicroReg bitPosReg = codeGen.nextVirtualIntRegister();
            builder.emitClearReg(bitPosReg, resultBits);
            builder.emitOpBinaryRegReg(bitPosReg, materializedValue, MicroOp::BitScanReverse, resultBits);
            builder.emitLoadRegImm(resultPayload.reg, ApInt(logicalBitWidth - 1, 64), resultBits);
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

    Result materializeNativeRuntimeContextTlsId(MicroReg& outTlsIdReg, CodeGen& codeGen, const SymbolFunction& tlsAllocFunction)
    {
        codeGen.function().addCallDependency(&tlsAllocFunction);

        MicroBuilder&  builder       = codeGen.builder();
        const uint32_t tlsIdOffset   = codeGen.compiler().nativeRuntimeContextTlsIdOffset();
        const MicroReg tlsStorageReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegDataSegmentReloc(tlsStorageReg, DataSegmentKind::GlobalZero, tlsIdOffset);

        const MicroReg tlsIdPlusOneReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(tlsIdPlusOneReg, tlsStorageReg, 0, MicroOpBits::B64);

        const MicroLabelRef haveTlsIdLabel = builder.createLabel();
        builder.emitCmpRegImm(tlsIdPlusOneReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, haveTlsIdLabel);

        const CallConvKind          tlsAllocCallConvKind = tlsAllocFunction.callConvKind();
        const ABICall::PreparedCall preparedTlsAllocCall = ABICall::prepareArgs(builder, tlsAllocCallConvKind, {});
        ABICall::callLocal(builder, tlsAllocCallConvKind, &tlsAllocFunction, preparedTlsAllocCall);

        const CallConv&                        tlsAllocCallConv = CallConv::get(tlsAllocCallConvKind);
        const ABITypeNormalize::NormalizedType tlsAllocRet      = ABITypeNormalize::normalize(codeGen.ctx(), tlsAllocCallConv, tlsAllocFunction.returnTypeRef(), ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!tlsAllocRet.isVoid);
        SWC_ASSERT(!tlsAllocRet.isIndirect);

        ABICall::materializeReturnToReg(builder, tlsIdPlusOneReg, tlsAllocCallConvKind, tlsAllocRet);
        builder.emitOpBinaryRegImm(tlsIdPlusOneReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitLoadMemReg(tlsStorageReg, 0, tlsIdPlusOneReg, MicroOpBits::B64);
        builder.placeLabel(haveTlsIdLabel);

        outTlsIdReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(outTlsIdReg, tlsIdPlusOneReg, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(outTlsIdReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        return Result::Continue;
    }

    MicroReg materializeHostRuntimeContextTlsId(CodeGen& codeGen)
    {
        MicroBuilder&     builder        = codeGen.builder();
        const uint64_t    tlsIdAddress   = reinterpret_cast<uint64_t>(CompilerInstance::runtimeContextTlsIdStorage());
        const ConstantRef tlsIdAddressCf = codeGen.cstMgr().addConstant(codeGen.ctx(), ConstantValue::makeValuePointer(codeGen.ctx(), codeGen.typeMgr().typeU64(), tlsIdAddress, TypeInfoFlagsE::Const));
        const MicroReg    tlsIdPtrReg    = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegPtrReloc(tlsIdPtrReg, tlsIdAddress, tlsIdAddressCf);

        const MicroReg tlsIdReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(tlsIdReg, tlsIdPtrReg, 0, MicroOpBits::B64);
        return tlsIdReg;
    }

    Result emitTlsSetValueCall(CodeGen& codeGen, const SymbolFunction& tlsSetValueFunction, MicroReg tlsIdReg, MicroReg contextReg)
    {
        codeGen.function().addCallDependency(&tlsSetValueFunction);

        ABICall::PreparedArg directU64Arg;
        directU64Arg.kind    = ABICall::PreparedArgKind::Direct;
        directU64Arg.numBits = 64;

        SmallVector<ABICall::PreparedArg> preparedArgs;
        directU64Arg.srcReg = tlsIdReg;
        preparedArgs.push_back(directU64Arg);
        directU64Arg.srcReg = contextReg;
        preparedArgs.push_back(directU64Arg);

        const CallConvKind callConvKind = tlsSetValueFunction.callConvKind();
        const CallConv&    callConv     = CallConv::get(callConvKind);
        CodeGenCallHelpers::isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);
        MicroBuilder&               builder      = codeGen.builder();
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        ABICall::callLocal(builder, callConvKind, &tlsSetValueFunction, preparedCall);
        return Result::Continue;
    }

    MicroReg materializeSetContextArgument(CodeGen& codeGen, AstNodeRef contextRef)
    {
        const CodeGenNodePayload& contextPayload = codeGen.payload(contextRef);
        TypeRef                   contextTypeRef = intrinsicOperandTypeRef(codeGen, contextRef, contextPayload);
        SWC_ASSERT(contextTypeRef.isValid());

        const TypeInfo& contextType = codeGen.typeMgr().get(contextTypeRef);
        const TypeRef   rawTypeRef  = contextType.unwrap(codeGen.ctx(), contextTypeRef, TypeExpandE::Alias);
        if (rawTypeRef.isValid())
            contextTypeRef = rawTypeRef;

        const TypeInfo& rawContextType = codeGen.typeMgr().get(contextTypeRef);
        if (rawContextType.isReference() || rawContextType.isAnyPointer())
        {
            if (!contextPayload.isAddress())
                return contextPayload.reg;

            const MicroReg contextReg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegMem(contextReg, contextPayload.reg, 0, MicroOpBits::B64);
            return contextReg;
        }

        SWC_ASSERT(contextPayload.isAddress());
        return contextPayload.reg;
    }

    Result codeGenProcessInfos(CodeGen& codeGen)
    {
        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        codeGen.builder().emitLoadRegDataSegmentReloc(resultPayload.reg, DataSegmentKind::GlobalZero, codeGen.compiler().nativeProcessInfosOffset());
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
        const SymbolFunction* tlsAllocFunction  = runtimeFunctionByName(codeGen, "__tlsAlloc");
        const SymbolFunction* tlsGetPtrFunction = runtimeFunctionByName(codeGen, "__tlsGetPtr");
        SWC_ASSERT(tlsAllocFunction != nullptr);
        SWC_ASSERT(tlsGetPtrFunction != nullptr);
        if (!tlsAllocFunction || !tlsGetPtrFunction)
            return Result::Error;

        codeGen.function().addCallDependency(tlsGetPtrFunction);

        MicroBuilder& builder = codeGen.builder();
        MicroReg      tlsIdReg;
        SWC_RESULT(materializeNativeRuntimeContextTlsId(tlsIdReg, codeGen, *tlsAllocFunction));

        const TypeRef      contextTypeRef     = codeGen.typeMgr().structContext();
        const TypeInfo&    contextType        = codeGen.typeMgr().get(contextTypeRef);
        const ConstantRef  initContextCstRef  = makeZeroStructConstant(codeGen, contextTypeRef);
        CodeGenNodePayload initContextPayload = makeAddressPayloadFromConstant(codeGen, initContextCstRef);
        initContextPayload.setIsValue();

        const MicroReg contextSizeReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(contextSizeReg, ApInt(contextType.sizeOf(codeGen.ctx()), 64), MicroOpBits::B64);

        ABICall::PreparedArg directU64Arg;
        directU64Arg.kind    = ABICall::PreparedArgKind::Direct;
        directU64Arg.numBits = 64;

        SmallVector<ABICall::PreparedArg> preparedArgs;
        directU64Arg.srcReg = tlsIdReg;
        preparedArgs.push_back(directU64Arg);
        directU64Arg.srcReg = contextSizeReg;
        preparedArgs.push_back(directU64Arg);
        directU64Arg.srcReg = initContextPayload.reg;
        preparedArgs.push_back(directU64Arg);

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

        const auto* payload = codeGen.loweringPayload(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->runtimeFunctionSymbol != nullptr);

        const auto&                       tlsGetValueFunction = *payload->runtimeFunctionSymbol;
        const CallConvKind                callConvKind        = tlsGetValueFunction.callConvKind();
        const TypeRef                     resultType          = codeGen.curViewType().typeRef();
        MicroBuilder&                     builder             = codeGen.builder();
        SmallVector<ABICall::PreparedArg> preparedArgs;

        const MicroReg tlsIdReg = materializeHostRuntimeContextTlsId(codeGen);

        ABICall::PreparedArg arg;
        arg.srcReg      = tlsIdReg;
        arg.kind        = ABICall::PreparedArgKind::Direct;
        arg.isFloat     = false;
        arg.isAddressed = false;
        arg.numBits     = 64;
        preparedArgs.push_back(arg);

        const CallConv& callConv = CallConv::get(callConvKind);
        CodeGenCallHelpers::isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        ABICall::callLocal(builder, callConvKind, &tlsGetValueFunction, preparedCall);

        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, resultType, ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!normalizedRet.isVoid);
        SWC_ASSERT(!normalizedRet.isIndirect);

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultType);
        ABICall::materializeReturnToReg(builder, resultPayload.reg, callConvKind, normalizedRet);
        return Result::Continue;
    }

    Result codeGenSetContext(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 1);

        const auto* payload = codeGen.loweringPayload(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->runtimeFunctionSymbol != nullptr);
        if (!payload || !payload->runtimeFunctionSymbol)
            return Result::Error;

        const MicroReg contextReg = materializeSetContextArgument(codeGen, children[0]);
        MicroReg       tlsIdReg   = MicroReg::invalid();
        if (codeGen.isNativeBuild())
        {
            const SymbolFunction* tlsAllocFunction = runtimeFunctionByName(codeGen, "__tlsAlloc");
            SWC_ASSERT(tlsAllocFunction != nullptr);
            if (!tlsAllocFunction)
                return Result::Error;

            SWC_RESULT(materializeNativeRuntimeContextTlsId(tlsIdReg, codeGen, *tlsAllocFunction));
        }
        else
        {
            tlsIdReg = materializeHostRuntimeContextTlsId(codeGen);
        }

        return emitTlsSetValueCall(codeGen, *payload->runtimeFunctionSymbol, tlsIdReg, contextReg);
    }
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
        case TokenId::IntrinsicIsSet:
            return codeGenIsSet(codeGen, *this);
        case TokenId::IntrinsicMakeAny:
            return codeGenMakeAny(codeGen, *this);
        case TokenId::IntrinsicMakeSlice:
            return codeGenMakeSlice(codeGen, *this, false);
        case TokenId::IntrinsicMakeString:
            return codeGenMakeSlice(codeGen, *this, true);
        case TokenId::IntrinsicMakeInterface:
            return codeGenMakeInterface(codeGen, *this);
        case TokenId::IntrinsicTableOf:
            return codeGenIntrinsicTableOf(codeGen, *this);
        case TokenId::IntrinsicIs:
            return codeGenIntrinsicIs(codeGen, *this);
        case TokenId::IntrinsicAs:
            return codeGenIntrinsicAs(codeGen, *this);

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
        case TokenId::IntrinsicASin:
            return CodeGenSafety::emitUnaryMathIntrinsicCall(codeGen, *this, Math::FoldIntrinsicUnaryFloatOp::ASin, materializeIntrinsicNumericOperand);
        case TokenId::IntrinsicACos:
            return CodeGenSafety::emitUnaryMathIntrinsicCall(codeGen, *this, Math::FoldIntrinsicUnaryFloatOp::ACos, materializeIntrinsicNumericOperand);
        case TokenId::IntrinsicLog:
            return CodeGenSafety::emitUnaryMathIntrinsicCall(codeGen, *this, Math::FoldIntrinsicUnaryFloatOp::Log, materializeIntrinsicNumericOperand);
        case TokenId::IntrinsicLog2:
            return CodeGenSafety::emitUnaryMathIntrinsicCall(codeGen, *this, Math::FoldIntrinsicUnaryFloatOp::Log2, materializeIntrinsicNumericOperand);
        case TokenId::IntrinsicLog10:
            return CodeGenSafety::emitUnaryMathIntrinsicCall(codeGen, *this, Math::FoldIntrinsicUnaryFloatOp::Log10, materializeIntrinsicNumericOperand);
        case TokenId::IntrinsicPow:
            return CodeGenSafety::emitPowIntrinsicCall(codeGen, *this, loadIntrinsicNumericOperand);
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
        case TokenId::IntrinsicSetContext:
            return codeGenSetContext(codeGen, *this);
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
