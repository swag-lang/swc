#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct InterfaceCastInfo
    {
        const SymbolStruct*   objectStruct        = nullptr;
        const SymbolImpl*     implSym             = nullptr;
        const SymbolVariable* usingField          = nullptr;
        bool                  usingFieldIsPointer = false;
    };

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

            // Interface implementation can come from a `using` field, but the runtime object pointer must
            // still be adjusted to the embedded object before building the interface pair.
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

    Result loadInterfaceMethodTableAddress(MicroReg& outReg, CodeGen& codeGen, const InterfaceCastInfo& castInfo)
    {
        SWC_ASSERT(castInfo.implSym != nullptr);
        ConstantRef tableCstRef = ConstantRef::invalid();
        SWC_RESULT(castInfo.implSym->ensureInterfaceMethodTable(codeGen.sema(), tableCstRef));
        SWC_ASSERT(tableCstRef.isValid());

        if (const SymbolInterface* interfaceSym = castInfo.implSym->symInterface())
        {
            for (const SymbolFunction* interfaceMethod : interfaceSym->functions())
            {
                SWC_ASSERT(interfaceMethod != nullptr);
                const SymbolFunction* implMethod = castInfo.implSym->resolveInterfaceMethodTarget(*interfaceMethod);
                SWC_ASSERT(implMethod != nullptr);
                codeGen.function().addCallDependency(const_cast<SymbolFunction*>(implMethod));
            }
        }

        const ConstantValue& tableCst = codeGen.cstMgr().get(tableCstRef);
        SWC_ASSERT(tableCst.isArray());
        outReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegPtrReloc(outReg, reinterpret_cast<uint64_t>(tableCst.getArray().data()), tableCstRef);
        return Result::Continue;
    }

    bool anyCastAsValueBits(CodeGen& codeGen, const TypeInfo& dstType, MicroOpBits& outBits)
    {
        outBits = CodeGenTypeHelpers::scalarStoreBits(dstType, codeGen.ctx());
        return outBits != MicroOpBits::Zero;
    }

    enum class DynamicStructCastSourceKind : uint8_t
    {
        Invalid,
        StructAddress,
        StructPointerLike,
        Interface,
        Any,
    };

    struct DynamicStructCastSourceInfo
    {
        DynamicStructCastSourceKind kind          = DynamicStructCastSourceKind::Invalid;
        TypeRef                     structTypeRef = TypeRef::invalid();
    };

    TypeRef unwrapAliasEnumTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeRef unwrappedTypeRef = codeGen.typeMgr().get(typeRef).unwrapAliasEnum(codeGen.ctx(), typeRef);
        if (unwrappedTypeRef.isValid())
            return unwrappedTypeRef;

        return typeRef;
    }

    bool resolveDynamicStructCastSourceInfo(CodeGen& codeGen, AstNodeRef sourceRef, TypeRef sourceTypeRef, DynamicStructCastSourceInfo& outInfo)
    {
        outInfo = {};
        if (!sourceTypeRef.isValid())
            return false;

        const TypeRef   resolvedSourceTypeRef = unwrapAliasEnumTypeRef(codeGen, sourceTypeRef);
        const TypeInfo& sourceType            = codeGen.typeMgr().get(resolvedSourceTypeRef);

        if (sourceType.isInterface())
        {
            outInfo.kind = DynamicStructCastSourceKind::Interface;
            return true;
        }

        if (sourceType.isAny())
        {
            outInfo.kind = DynamicStructCastSourceKind::Any;
            return true;
        }

        if (sourceType.isPointerOrReference())
        {
            const TypeRef   pointeeTypeRef = unwrapAliasEnumTypeRef(codeGen, sourceType.payloadTypeRef());
            const TypeInfo& pointeeType    = codeGen.typeMgr().get(pointeeTypeRef);
            if (pointeeType.isStruct())
            {
                outInfo.kind          = DynamicStructCastSourceKind::StructPointerLike;
                outInfo.structTypeRef = pointeeTypeRef;
                return true;
            }
        }

        if (!codeGen.sema().isLValue(sourceRef))
            return false;

        const TypeRef   structTypeRef = unwrapAliasEnumTypeRef(codeGen, resolvedSourceTypeRef);
        const TypeInfo& structType    = codeGen.typeMgr().get(structTypeRef);
        if (!structType.isStruct())
            return false;

        outInfo.kind          = DynamicStructCastSourceKind::StructAddress;
        outInfo.structTypeRef = structTypeRef;
        return true;
    }

    Result loadTypeInfoConstantReg(MicroReg& outReg, CodeGen& codeGen, TypeRef typeRef)
    {
        ConstantRef typeInfoCstRef = ConstantRef::invalid();
        SWC_RESULT(codeGen.cstMgr().makeTypeInfo(codeGen.sema(), typeInfoCstRef, typeRef, codeGen.curNodeRef()));
        const ConstantValue& typeInfoCst = codeGen.cstMgr().get(typeInfoCstRef);
        SWC_ASSERT(typeInfoCst.isValuePointer());

        outReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegPtrReloc(outReg, typeInfoCst.getValuePointer(), typeInfoCstRef);
        return Result::Continue;
    }

    void appendDirectPreparedArg(SmallVector<ABICall::PreparedArg>& outArgs,
                                 CodeGen&                           codeGen,
                                 const CallConv&                    callConv,
                                 TypeRef                            argTypeRef,
                                 MicroReg                           srcReg)
    {
        const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, argTypeRef, ABITypeNormalize::Usage::Argument);

        ABICall::PreparedArg arg;
        arg.srcReg      = srcReg;
        arg.kind        = ABICall::PreparedArgKind::Direct;
        arg.isFloat     = normalizedArg.isFloat;
        arg.isAddressed = false;
        arg.numBits     = normalizedArg.numBits;
        outArgs.push_back(arg);
    }

    Result emitDynamicStructRuntimeCall(CodeGen& codeGen, SymbolFunction& runtimeFunction, std::span<const MicroReg> argRegs, MicroReg resultReg)
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
            appendDirectPreparedArg(preparedArgs, codeGen, callConv, params[i]->typeRef(), argRegs[i]);
        }

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

    Result emitDynamicStructCast(CodeGen& codeGen, AstNodeRef sourceRef, TypeRef targetTypeRef, bool checkOnly)
    {
        const CodeGenNodePayload& sourcePayload = codeGen.payload(sourceRef);
        const TypeRef             sourceTypeRef = codeGen.viewType(sourceRef).typeRef();

        DynamicStructCastSourceInfo sourceInfo;
        const bool                  hasSourceInfo = resolveDynamicStructCastSourceInfo(codeGen, sourceRef, sourceTypeRef, sourceInfo);
        SWC_ASSERT(hasSourceInfo);
        if (!hasSourceInfo)
            return Result::Error;

        const TypeRef targetStructTypeRef = unwrapAliasEnumTypeRef(codeGen, targetTypeRef);

        const auto* runtimePayload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
        SWC_ASSERT(runtimePayload != nullptr);
        SWC_ASSERT(runtimePayload->runtimeFunctionSymbol != nullptr);
        auto& runtimeFunction = *runtimePayload->runtimeFunctionSymbol;

        const TypeRef       resultTypeRef = codeGen.curViewType().typeRef();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        MicroBuilder&       builder       = codeGen.builder();
        const MicroOpBits   resultBits    = checkOnly ? MicroOpBits::B8 : MicroOpBits::B64;
        resultPayload.reg                 = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(resultPayload.reg, ApInt(0, 64), resultBits);

        MicroReg targetTypeReg = MicroReg::invalid();
        SWC_RESULT(loadTypeInfoConstantReg(targetTypeReg, codeGen, targetStructTypeRef));

        MicroReg sourceTypeReg = MicroReg::invalid();
        MicroReg sourcePtrReg  = MicroReg::invalid();
        switch (sourceInfo.kind)
        {
            case DynamicStructCastSourceKind::StructAddress:
                SWC_RESULT(loadTypeInfoConstantReg(sourceTypeReg, codeGen, sourceInfo.structTypeRef));
                sourcePtrReg = sourcePayload.reg;
                if (!sourcePtrReg.isValid())
                    return Result::Error;
                break;

            case DynamicStructCastSourceKind::StructPointerLike:
                SWC_RESULT(loadTypeInfoConstantReg(sourceTypeReg, codeGen, sourceInfo.structTypeRef));
                sourcePtrReg = codeGen.nextVirtualIntRegister();
                if (sourcePayload.isAddress())
                    builder.emitLoadRegMem(sourcePtrReg, sourcePayload.reg, 0, MicroOpBits::B64);
                else
                    builder.emitLoadRegReg(sourcePtrReg, sourcePayload.reg, MicroOpBits::B64);
                break;

            case DynamicStructCastSourceKind::Interface:
            {
                SWC_ASSERT(sourcePayload.isAddress());
                const MicroReg itableReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(itableReg, sourcePayload.reg, offsetof(Runtime::Interface, itable), MicroOpBits::B64);

                sourceTypeReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegImm(sourceTypeReg, ApInt(0, 64), MicroOpBits::B64);
                const MicroLabelRef typeDoneLabel = builder.createLabel();
                builder.emitCmpRegImm(itableReg, ApInt(0, 64), MicroOpBits::B64);
                builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, typeDoneLabel);
                builder.emitLoadRegMem(sourceTypeReg, itableReg, 0, MicroOpBits::B64);
                builder.placeLabel(typeDoneLabel);

                sourcePtrReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(sourcePtrReg, sourcePayload.reg, offsetof(Runtime::Interface, obj), MicroOpBits::B64);
                break;
            }

            case DynamicStructCastSourceKind::Any:
            {
                SWC_ASSERT(sourcePayload.isAddress());
                sourceTypeReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(sourceTypeReg, sourcePayload.reg, offsetof(Runtime::Any, type), MicroOpBits::B64);

                if (!checkOnly)
                {
                    sourcePtrReg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegMem(sourcePtrReg, sourcePayload.reg, offsetof(Runtime::Any, value), MicroOpBits::B64);
                }

                const MicroLabelRef doneLabel = builder.createLabel();
                builder.emitCmpRegImm(sourceTypeReg, ApInt(0, 64), MicroOpBits::B64);
                builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

                const MicroReg kindReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(kindReg, sourceTypeReg, offsetof(Runtime::TypeInfo, kind), MicroOpBits::B8);
                builder.emitCmpRegImm(kindReg, ApInt(static_cast<uint64_t>(Runtime::TypeInfoKind::Struct), 64), MicroOpBits::B8);
                builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, doneLabel);

                if (checkOnly)
                {
                    const MicroReg args[] = {targetTypeReg, sourceTypeReg};
                    SWC_RESULT(emitDynamicStructRuntimeCall(codeGen, runtimeFunction, args, resultPayload.reg));
                }
                else
                {
                    const MicroReg args[] = {targetTypeReg, sourceTypeReg, sourcePtrReg};
                    SWC_RESULT(emitDynamicStructRuntimeCall(codeGen, runtimeFunction, args, resultPayload.reg));
                }

                builder.placeLabel(doneLabel);
                return Result::Continue;
            }

            default:
                return Result::Error;
        }

        if (checkOnly)
        {
            const MicroReg args[] = {targetTypeReg, sourceTypeReg};
            return emitDynamicStructRuntimeCall(codeGen, runtimeFunction, args, resultPayload.reg);
        }

        const MicroReg args[] = {targetTypeReg, sourceTypeReg, sourcePtrReg};
        return emitDynamicStructRuntimeCall(codeGen, runtimeFunction, args, resultPayload.reg);
    }

    Result emitArrayToStringCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef, const TypeInfo& srcType)
    {
        MicroBuilder&             builder    = codeGen.builder();
        const CodeGenNodePayload& srcPayload = codeGen.payload(srcNodeRef);

        const SemaNodeView srcConstView = codeGen.viewConstant(srcNodeRef);
        if (srcConstView.hasConstant())
        {
            const ConstantValue& srcConst = codeGen.cstMgr().get(srcConstView.cstRef());
            if (srcConst.isArray())
            {
                const ByteSpan    arrayBytes       = srcConst.getArray();
                const ConstantRef runtimeStringRef = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, dstTypeRef, arrayBytes.data(), arrayBytes.size());
                SWC_ASSERT(runtimeStringRef.isValid());
                const ConstantValue&      runtimeStringCst = codeGen.cstMgr().get(runtimeStringRef);
                const CodeGenNodePayload& dstPayload       = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
                builder.emitLoadRegPtrReloc(dstPayload.reg, reinterpret_cast<uint64_t>(runtimeStringCst.getStruct().data()), runtimeStringRef);
                return Result::Continue;
            }
        }

        const uint64_t length          = srcType.sizeOf(codeGen.ctx());
        const MicroReg runtimeValueReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());

        MicroReg srcDataReg = srcPayload.reg;
        if (!srcPayload.isAddress())
        {
            srcDataReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(srcDataReg, srcPayload.reg, MicroOpBits::B64);
        }

        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::String, ptr), srcDataReg, MicroOpBits::B64);

        const MicroReg lengthReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(lengthReg, ApInt(length, 64), MicroOpBits::B64);
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::String, length), lengthReg, MicroOpBits::B64);

        const CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        builder.emitLoadRegReg(dstPayload.reg, runtimeValueReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitArrayToSliceCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef, const TypeInfo& srcType, const TypeInfo& dstType)
    {
        SWC_ASSERT(dstType.isSlice());

        const TypeInfo& dstElementType = codeGen.typeMgr().get(dstType.payloadTypeRef());
        const uint64_t  totalSize      = srcType.sizeOf(codeGen.ctx());
        const uint64_t  elementSize    = dstElementType.sizeOf(codeGen.ctx());
        const uint64_t  elementCount   = elementSize ? totalSize / elementSize : 0;

        MicroBuilder&             builder    = codeGen.builder();
        const CodeGenNodePayload& srcPayload = codeGen.payload(srcNodeRef);

        const SemaNodeView srcConstView = codeGen.viewConstant(srcNodeRef);
        if (srcConstView.hasConstant())
        {
            const ConstantValue& srcConst = codeGen.cstMgr().get(srcConstView.cstRef());
            if (srcConst.isArray())
            {
                const ConstantRef safeArrayCstRef = CodeGenConstantHelpers::ensureStaticPayloadConstant(codeGen, srcConstView.cstRef(), srcConst.typeRef());
                SWC_ASSERT(safeArrayCstRef.isValid());
                const ConstantValue& safeArrayCst    = codeGen.cstMgr().get(safeArrayCstRef);
                const ConstantRef    runtimeSliceRef = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, dstTypeRef, safeArrayCst.getArray().data(), elementCount);
                SWC_ASSERT(runtimeSliceRef.isValid());
                const ConstantValue&      runtimeSliceCst = codeGen.cstMgr().get(runtimeSliceRef);
                const CodeGenNodePayload& dstPayload      = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
                builder.emitLoadRegPtrReloc(dstPayload.reg, reinterpret_cast<uint64_t>(runtimeSliceCst.getStruct().data()), runtimeSliceRef);
                return Result::Continue;
            }
        }

        const MicroReg runtimeValueReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());

        MicroReg srcDataReg = srcPayload.reg;
        if (!srcPayload.isAddress())
        {
            srcDataReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(srcDataReg, srcPayload.reg, MicroOpBits::B64);
        }

        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Slice<std::byte>, ptr), srcDataReg, MicroOpBits::B64);

        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(countReg, ApInt(elementCount, 64), MicroOpBits::B64);
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Slice<std::byte>, count), countReg, MicroOpBits::B64);

        const CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        builder.emitLoadRegReg(dstPayload.reg, runtimeValueReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitAnyCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef)
    {
        if (dstTypeRef.isInvalid())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef);
            return Result::Continue;
        }

        const CodeGenNodePayload& srcPayload = codeGen.payload(srcNodeRef);

        const SemaNodeView srcView = codeGen.viewType(srcNodeRef);
        SWC_ASSERT(srcView.type());
        if (!srcView.type()->isAny())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const TypeInfo& dstType = codeGen.typeMgr().get(dstTypeRef);
        if (dstType.isAny())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        SWC_ASSERT(srcPayload.isAddress());

        MicroBuilder& builder = codeGen.builder();
        // Runtime `any` stores a type pointer plus an address to the erased value. Casting out of it only
        // decides whether the destination expects that address directly or wants the pointed-to bits.
        const MicroReg valueAddrReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(valueAddrReg, srcPayload.reg, offsetof(Runtime::Any, value), MicroOpBits::B64);

        if (dstType.isString() || dstType.isSlice() || dstType.isInterface() || dstType.isAnyVariadic())
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(dstPayload.reg, valueAddrReg, MicroOpBits::B64);
            return Result::Continue;
        }

        if (dstType.isReference() || dstType.isMoveReference())
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(dstPayload.reg, valueAddrReg, MicroOpBits::B64);
            return Result::Continue;
        }

        auto valueBits = MicroOpBits::Zero;
        if (anyCastAsValueBits(codeGen, dstType, valueBits))
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitLoadRegMem(dstPayload.reg, valueAddrReg, 0, valueBits);
            return Result::Continue;
        }

        const CodeGenNodePayload& dstPayload = codeGen.setPayloadAddressReg(codeGen.curNodeRef(), codeGen.nextVirtualIntRegister(), dstTypeRef);
        builder.emitLoadRegReg(dstPayload.reg, valueAddrReg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitFunctionToClosureCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& srcType = codeGen.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = codeGen.typeMgr().get(dstTypeRef);
        if (srcType.isLambdaClosure())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const auto* castPayload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
        SWC_ASSERT(castPayload != nullptr);
        SWC_ASSERT(castPayload->runtimeStorageSym != nullptr);

        auto&           dstFunc = dstType.payloadSymFunction();
        SymbolFunction* adapter = nullptr;
        SWC_RESULT(dstFunc.ensureClosureAdapter(codeGen.ctx(), adapter));
        SWC_ASSERT(adapter != nullptr);
        codeGen.function().addCallDependency(adapter);

        MicroBuilder&             builder         = codeGen.builder();
        const CodeGenNodePayload& srcPayload      = codeGen.payload(srcNodeRef);
        const MicroReg            runtimeValueReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        CodeGenMemoryHelpers::emitMemZero(codeGen, runtimeValueReg, sizeof(Runtime::ClosureValue));

        const MicroReg invokeReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegPtrReloc(invokeReg, 0, ConstantRef::invalid(), adapter);
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::ClosureValue, invoke), invokeReg, MicroOpBits::B64);

        MicroReg targetReg = srcPayload.reg;
        if (srcPayload.isAddress())
        {
            targetReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(targetReg, srcPayload.reg, 0, MicroOpBits::B64);
        }

        const MicroReg captureDstReg = codeGen.offsetAddressReg(runtimeValueReg, offsetof(Runtime::ClosureValue, capture));
        builder.emitLoadMemReg(captureDstReg, 0, targetReg, MicroOpBits::B64);
        codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeValueReg, dstTypeRef);
        return Result::Continue;
    }

    Result emitNumericCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef)
    {
        MicroBuilder&             builder             = codeGen.builder();
        const CodeGenNodePayload& srcPayload          = codeGen.payload(srcNodeRef);
        const auto*               castPayload         = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
        const bool                needsRuntimeStorage = castPayload && castPayload->runtimeStorageSym != nullptr;

        TypeRef sourceTypeRef = codeGen.sema().viewStored(srcNodeRef, SemaNodeViewPartE::Type).typeRef();
        if (!sourceTypeRef.isValid())
            sourceTypeRef = srcPayload.typeRef;

        if (dstTypeRef.isInvalid())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef);
            return Result::Continue;
        }

        if (!sourceTypeRef.isValid())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const AstNodeRef resolvedSrcNodeRef = codeGen.viewZero(srcNodeRef).nodeRef();
        const AstNode&   srcNode            = codeGen.node(resolvedSrcNodeRef);
        if (!needsRuntimeStorage &&
            (srcNode.is(AstNodeId::CastExpr) || srcNode.is(AstNodeId::AutoCastExpr)) &&
            srcPayload.typeRef.isValid() &&
            srcPayload.typeRef == dstTypeRef &&
            sourceTypeRef != dstTypeRef)
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        if (codeGen.typeMgr().get(sourceTypeRef).isAny())
            return emitAnyCast(codeGen, srcNodeRef, dstTypeRef);

        const TypeInfo& srcType = codeGen.typeMgr().get(sourceTypeRef);
        const TypeInfo& dstType = codeGen.typeMgr().get(dstTypeRef);
        if (srcType.isFunction() && dstType.isFunction() && !srcType.isLambdaClosure() && dstType.isLambdaClosure())
            return emitFunctionToClosureCast(codeGen, srcNodeRef, sourceTypeRef, dstTypeRef);

        if (srcType.isNull() && dstType.isPointerLike())
        {
            const uint64_t dstSize = dstType.sizeOf(codeGen.ctx());
            if (dstSize <= sizeof(uint64_t))
            {
                codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
                return Result::Continue;
            }

            SWC_ASSERT(dstSize <= std::numeric_limits<uint32_t>::max());
            // Large pointer-like layouts cannot be represented as a raw zero immediate; materialize a
            // typed zero blob that matches the destination runtime representation.
            SmallVector<std::byte> typedNullBytes;
            typedNullBytes.resize(dstSize);
            std::memset(typedNullBytes.data(), 0, typedNullBytes.size());

            const SemaNodeView srcConstView = codeGen.viewTypeConstant(srcNodeRef);
            const ConstantRef  nullCstRef   = srcConstView.cstRef().isValid() ? srcConstView.cstRef() : codeGen.cstMgr().cstNull();
            SWC_RESULT(ConstantLower::lowerToBytes(codeGen.sema(), ByteSpanRW{typedNullBytes.data(), typedNullBytes.size()}, nullCstRef, dstTypeRef));

            const ConstantRef         typedNullCstRef = CodeGenConstantHelpers::materializeStaticPayloadConstant(codeGen, dstTypeRef, ByteSpan{typedNullBytes.data(), typedNullBytes.size()});
            const ConstantValue&      typedNullCst    = codeGen.cstMgr().get(typedNullCstRef);
            const CodeGenNodePayload& dstPayload      = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            builder.emitLoadRegPtrReloc(dstPayload.reg, reinterpret_cast<uint64_t>(typedNullCst.getStruct().data()), typedNullCstRef);
            return Result::Continue;
        }

        if (dstType.isString() && srcType.isArray())
            return emitArrayToStringCast(codeGen, srcNodeRef, dstTypeRef, srcType);
        if (dstType.isSlice() && srcType.isArray())
            return emitArrayToSliceCast(codeGen, srcNodeRef, dstTypeRef, srcType, dstType);

        if (dstType.isAny() && !srcType.isAny())
        {
            if (!castPayload || castPayload->runtimeStorageSym == nullptr)
            {
                codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
                return Result::Continue;
            }

            const MicroReg runtimeAnyReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
            TypeRef        anyTypeRef    = sourceTypeRef;
            if (srcType.isChar())
                anyTypeRef = codeGen.typeMgr().typeRune();

            MicroReg valuePtrReg = srcPayload.reg;
            if (!srcPayload.isAddress())
            {
                auto srcValueBits = MicroOpBits::Zero;
                if (!anyCastAsValueBits(codeGen, srcType, srcValueBits))
                {
                    codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
                    return Result::Continue;
                }

                valuePtrReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(valuePtrReg, runtimeAnyReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(valuePtrReg, ApInt(sizeof(Runtime::Any), 64), MicroOp::Add, MicroOpBits::B64);
                builder.emitLoadMemReg(valuePtrReg, 0, srcPayload.reg, srcValueBits);
            }

            builder.emitLoadMemReg(runtimeAnyReg, offsetof(Runtime::Any, value), valuePtrReg, MicroOpBits::B64);

            ConstantRef typeInfoCstRef = ConstantRef::invalid();
            SWC_RESULT(codeGen.cstMgr().makeTypeInfo(codeGen.sema(), typeInfoCstRef, anyTypeRef, codeGen.curNodeRef()));
            const ConstantValue& typeInfoCst = codeGen.cstMgr().get(typeInfoCstRef);
            SWC_ASSERT(typeInfoCst.isValuePointer());

            const MicroReg typeInfoReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegPtrReloc(typeInfoReg, typeInfoCst.getValuePointer(), typeInfoCstRef);
            builder.emitLoadMemReg(runtimeAnyReg, offsetof(Runtime::Any, type), typeInfoReg, MicroOpBits::B64);

            codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeAnyReg, dstTypeRef);
            return Result::Continue;
        }

        if (srcType.isStruct() && dstType.isInterface())
        {
            SWC_ASSERT(castPayload && castPayload->runtimeStorageSym != nullptr);

            const auto&       srcStruct = srcType.payloadSymStruct();
            const auto&       dstItf    = dstType.payloadSymInterface();
            InterfaceCastInfo castInfo;
            const bool        hasCastInfo = resolveInterfaceCastInfo(codeGen, srcStruct, dstItf, castInfo);
            SWC_ASSERT(hasCastInfo);
            SWC_ASSERT(castInfo.implSym != nullptr);

            constexpr uint64_t interfaceStorageSize  = sizeof(Runtime::Interface);
            const uint64_t     objectStorageSize     = srcType.sizeOf(codeGen.ctx());
            const bool         preserveSourceAddress = srcPayload.isAddress() && codeGen.sema().isLValue(srcNodeRef);

            const MicroReg runtimeItfReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
            MicroReg       objectReg     = srcPayload.reg;
            if (!preserveSourceAddress)
            {
                MicroReg objectStorageReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(objectStorageReg, runtimeItfReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(objectStorageReg, ApInt(interfaceStorageSize, 64), MicroOp::Add, MicroOpBits::B64);

                if (objectStorageSize)
                {
                    if (srcPayload.isAddress())
                    {
                        SWC_ASSERT(objectStorageSize <= std::numeric_limits<uint32_t>::max());
                        CodeGenMemoryHelpers::emitMemCopy(codeGen, objectStorageReg, srcPayload.reg, static_cast<uint32_t>(objectStorageSize));
                    }
                    else
                    {
                        const MicroOpBits storeBits = microOpBitsFromChunkSize(static_cast<uint32_t>(objectStorageSize));
                        SWC_ASSERT(storeBits != MicroOpBits::Zero);
                        builder.emitLoadMemReg(objectStorageReg, 0, srcPayload.reg, storeBits);
                    }
                }

                objectReg = objectStorageReg;
            }

            if (castInfo.usingField)
            {
                const SymbolVariable& usingField = *castInfo.usingField;
                // The runtime object pointer must target the `using` field implementation, whether we reused the
                // original lvalue address or spilled a temporary copy.
                if (castInfo.usingFieldIsPointer)
                {
                    const MicroReg baseObjectReg = objectReg;
                    objectReg                    = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegMem(objectReg, baseObjectReg, usingField.offset(), MicroOpBits::B64);
                }
                else
                {
                    const MicroReg baseObjectReg = objectReg;
                    objectReg                    = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegReg(objectReg, baseObjectReg, MicroOpBits::B64);
                    if (usingField.offset())
                        builder.emitOpBinaryRegImm(objectReg, ApInt(usingField.offset(), 64), MicroOp::Add, MicroOpBits::B64);
                }
            }

            builder.emitLoadMemReg(runtimeItfReg, offsetof(Runtime::Interface, obj), objectReg, MicroOpBits::B64);

            MicroReg itableReg = MicroReg::invalid();
            SWC_RESULT(loadInterfaceMethodTableAddress(itableReg, codeGen, castInfo));
            builder.emitLoadMemReg(runtimeItfReg, offsetof(Runtime::Interface, itable), itableReg, MicroOpBits::B64);

            codeGen.setPayloadAddressReg(codeGen.curNodeRef(), runtimeItfReg, dstTypeRef);
            return Result::Continue;
        }

        const bool srcFloatType   = srcType.isFloat();
        const bool srcIntLikeType = srcType.isNumericIntLike();
        const bool dstFloatType   = dstType.isFloat();
        const bool dstIntLikeType = dstType.isNumericIntLike();

        if (dstType.isBool() && (srcType.isPointerLike() || srcType.isReference() || srcType.isMoveReference() || srcType.isNull()))
        {
            MicroReg srcReg = srcPayload.reg;
            if (srcPayload.isAddress())
            {
                srcReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, MicroOpBits::B64);
            }

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();
            builder.emitCmpRegImm(srcReg, ApInt(0, 64), MicroOpBits::B64);
            builder.emitSetCondReg(dstPayload.reg, MicroCond::NotEqual);
            return Result::Continue;
        }

        if (srcIntLikeType && dstIntLikeType)
        {
            const MicroOpBits srcOpBits = CodeGenTypeHelpers::numericOrBoolBits(srcType);
            const MicroOpBits dstOpBits = CodeGenTypeHelpers::numericOrBoolBits(dstType);
            SWC_ASSERT(srcOpBits != MicroOpBits::Zero);
            SWC_ASSERT(dstOpBits != MicroOpBits::Zero);

            MicroReg srcReg = srcPayload.reg;
            if (srcPayload.isAddress())
            {
                srcReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, srcOpBits);
            }

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();

            if (dstType.isBool())
            {
                builder.emitCmpRegImm(srcReg, ApInt(0, 64), srcOpBits);
                builder.emitSetCondReg(dstPayload.reg, MicroCond::NotEqual);
                return Result::Continue;
            }

            const uint32_t srcWidth = getNumBits(srcOpBits);
            const uint32_t dstWidth = getNumBits(dstOpBits);
            if (srcWidth == dstWidth)
            {
                builder.emitLoadRegReg(dstPayload.reg, srcReg, dstOpBits);
                return Result::Continue;
            }

            if (srcWidth > dstWidth)
            {
                builder.emitLoadRegReg(dstPayload.reg, srcReg, dstOpBits);
                return Result::Continue;
            }

            if (srcType.isNumericSigned())
            {
                builder.emitLoadSignedExtendRegReg(dstPayload.reg, srcReg, dstOpBits, srcOpBits);
                return Result::Continue;
            }

            builder.emitLoadZeroExtendRegReg(dstPayload.reg, srcReg, dstOpBits, srcOpBits);
            return Result::Continue;
        }

        if (sourceTypeRef == dstTypeRef)
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        if (!((srcIntLikeType && dstFloatType) || (srcFloatType && dstFloatType) || (srcFloatType && dstIntLikeType)))
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const MicroOpBits srcOpBits = CodeGenTypeHelpers::numericOrBoolBits(srcType);
        const MicroOpBits dstOpBits = CodeGenTypeHelpers::numericOrBoolBits(dstType);
        if (srcOpBits == MicroOpBits::Zero || dstOpBits == MicroOpBits::Zero)
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        MicroReg srcReg = srcPayload.reg;
        if (srcPayload.isAddress())
        {
            srcReg = codeGen.nextVirtualRegisterForType(sourceTypeRef);
            builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, srcOpBits);
        }

        if (srcIntLikeType && dstFloatType)
        {
            if (getNumBits(srcOpBits) < 32 || (dstOpBits == MicroOpBits::B64 && getNumBits(srcOpBits) == 32))
            {
                const MicroReg    widenedReg  = codeGen.nextVirtualIntRegister();
                const MicroOpBits widenedBits = dstOpBits == MicroOpBits::B64 ? MicroOpBits::B64 : MicroOpBits::B32;
                if (srcType.isIntSigned())
                    builder.emitLoadSignedExtendRegReg(widenedReg, srcReg, widenedBits, srcOpBits);
                else
                    builder.emitLoadZeroExtendRegReg(widenedReg, srcReg, widenedBits, srcOpBits);
                srcReg = widenedReg;
            }

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstPayload.reg, dstOpBits);
            builder.emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertIntToFloat, dstOpBits);
            return Result::Continue;
        }

        if (srcFloatType && dstFloatType)
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            if (srcOpBits == dstOpBits)
            {
                dstPayload.reg = srcReg;
                return Result::Continue;
            }

            dstPayload.reg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstPayload.reg, dstOpBits);
            builder.emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertFloatToFloat, srcOpBits);
            return Result::Continue;
        }

        CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        dstPayload.reg                 = codeGen.nextVirtualRegisterForType(dstTypeRef);
        builder.emitClearReg(dstPayload.reg, dstOpBits);
        builder.emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertFloatToInt, srcOpBits);

        return Result::Continue;
    }
}

Result AstAutoCastExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return emitNumericCast(codeGen, nodeExprRef, codeGen.curViewType().typeRef());
}

Result AstCastExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return emitNumericCast(codeGen, nodeExprRef, codeGen.curViewType().typeRef());
}

Result AstAsCastExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return emitDynamicStructCast(codeGen, nodeExprRef, codeGen.viewType(nodeTypeRef).typeRef(), false);
}

Result AstIsTypeExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return emitDynamicStructCast(codeGen, nodeExprRef, codeGen.viewType(nodeTypeRef).typeRef(), true);
}

SWC_END_NAMESPACE();
