#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result raiseInternalCallCodeGenError(CodeGen& codeGen, std::string_view because, AstNodeRef nodeRef = AstNodeRef::invalid())
    {
        SWC_ASSERT(!because.empty());

        AstNodeRef errorNodeRef = nodeRef.isValid() ? codeGen.resolvedNodeRef(nodeRef) : AstNodeRef::invalid();
        if (errorNodeRef.isInvalid())
            errorNodeRef = codeGen.resolvedNodeRef(codeGen.curNodeRef());
        if (errorNodeRef.isInvalid())
            errorNodeRef = codeGen.function().declNodeRef();
        SWC_ASSERT(errorNodeRef.isValid());

        auto diag = SemaError::report(codeGen.sema(), DiagnosticId::misc_err_internal_codegen_failure, errorNodeRef, SemaError::ReportLocation::Token);
        diag.addArgument(Diagnostic::ARG_WHAT, codeGen.function().getFullScopedName(codeGen.ctx()));
        diag.addArgument(Diagnostic::ARG_BECAUSE, because);
        diag.report(codeGen.ctx());
        return Result::Error;
    }

    SymbolFunction* singleFunctionFromView(const SemaNodeView& view)
    {
        if (view.hasSymbolList())
        {
            if (view.symList().size() != 1)
                return nullptr;

            Symbol* symbol = view.symList().front();
            if (!symbol || !symbol->isFunction())
                return nullptr;
            return &symbol->cast<SymbolFunction>();
        }

        Symbol* symbol = view.sym();
        if (!symbol || !symbol->isFunction())
            return nullptr;
        return &symbol->cast<SymbolFunction>();
    }

    void appendUniqueCandidateRef(SmallVector<AstNodeRef>& outCandidateRefs, const AstNodeRef candidateRef)
    {
        if (candidateRef.isInvalid())
            return;

        if (std::ranges::find(outCandidateRefs, candidateRef) == outCandidateRefs.end())
            outCandidateRefs.push_back(candidateRef);
    }

    std::optional<CodeGenNodePayload> tryResolveVariableSymbolPayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (symVar.isClosureCapture())
            return CodeGenFunctionHelpers::resolveClosureCapturePayload(codeGen, symVar);

        if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar))
            return CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, symVar);

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            return CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, codeGen.function(), symVar);

        if (const auto* payload = codeGen.variablePayload(symVar))
            return *payload;

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) ||
            (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal)))
            return codeGen.resolveLocalStackPayload(symVar);

        if (symVar.hasGlobalStorage())
        {
            CodeGenNodePayload payload;
            payload.typeRef = symVar.typeRef();
            payload.setIsAddress();
            payload.reg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegDataSegmentReloc(payload.reg, symVar.globalStorageKind(), symVar.offset());
            return payload;
        }

        return std::nullopt;
    }

    std::optional<CodeGenNodePayload> tryResolveVariableViewPayload(CodeGen& codeGen, const SemaNodeView& view)
    {
        const auto* symVar = view.sym() ? view.sym()->safeCast<SymbolVariable>() : nullptr;
        if (!symVar)
            return std::nullopt;
        return tryResolveVariableSymbolPayload(codeGen, *symVar);
    }

    Result resolveSelectedCallFunction(CodeGen& codeGen, AstNodeRef calleeRef, SymbolFunction*& outCalledFunction)
    {
        outCalledFunction = nullptr;

        if (SymbolFunction* calledFunction = singleFunctionFromView(codeGen.curViewSymbol()))
        {
            outCalledFunction = calledFunction;
            return Result::Continue;
        }

        const SemaNodeView storedCallView = codeGen.sema().viewStored(codeGen.curNodeRef(), SemaNodeViewPartE::Symbol);
        if (SymbolFunction* calledFunction = singleFunctionFromView(storedCallView))
        {
            outCalledFunction = calledFunction;
            return Result::Continue;
        }

        if (calleeRef.isValid())
        {
            const SemaNodeView calleeView = codeGen.viewNodeSymbolList(calleeRef);
            if (SymbolFunction* calledFunction = singleFunctionFromView(calleeView))
            {
                outCalledFunction = calledFunction;
                return Result::Continue;
            }

            const SemaNodeView storedCalleeView = codeGen.sema().viewStored(calleeRef, SemaNodeViewPartE::Symbol);
            if (SymbolFunction* calledFunction = singleFunctionFromView(storedCalleeView))
            {
                outCalledFunction = calledFunction;
                return Result::Continue;
            }

            const AstNodeRef resolvedCalleeRef = codeGen.resolvedNodeRef(calleeRef);
            if (resolvedCalleeRef.isValid() && resolvedCalleeRef != calleeRef)
            {
                const SemaNodeView resolvedCalleeView = codeGen.sema().viewStored(resolvedCalleeRef, SemaNodeViewPartE::Symbol);
                if (SymbolFunction* calledFunction = singleFunctionFromView(resolvedCalleeView))
                {
                    outCalledFunction = calledFunction;
                    return Result::Continue;
                }
            }
        }

        return raiseInternalCallCodeGenError(codeGen, "missing bound function symbol for call expression", calleeRef);
    }

    AstNodeRef resolvePreparedArgSourceRef(CodeGen& codeGen, AstNodeRef argRef)
    {
        AstNodeRef sourceRef = codeGen.resolvedNodeRef(argRef);
        if (sourceRef.isInvalid())
            sourceRef = argRef;
        return SemaHelpers::resolveTransparentExprSourceRef(codeGen.sema(), sourceRef);
    }

    TypeRef resolveUntypedVariadicArgTypeRef(CodeGen& codeGen, const CodeGenNodePayload& argPayload, AstNodeRef argRef)
    {
        TypeRef argTypeRef = argPayload.effectiveTypeRef(codeGen.viewType(argRef).typeRef());
        if (argTypeRef.isValid() && !codeGen.ctx().typeMgr().get(argTypeRef).isAnyVariadic())
            return argTypeRef;

        const AstNodeRef sourceRef = resolvePreparedArgSourceRef(codeGen, argRef);
        if (sourceRef.isInvalid())
            return argTypeRef;

        const TypeRef sourceTypeRef = codeGen.viewType(sourceRef).typeRef();
        if (sourceTypeRef.isValid())
            return sourceTypeRef;

        const TypeRef storedSourceTypeRef = codeGen.sema().viewStored(sourceRef, SemaNodeViewPartE::Type).typeRef();
        if (storedSourceTypeRef.isValid())
            return storedSourceTypeRef;

        return argTypeRef;
    }

    TypeRef concretizeUntypedVariadicRuntimeTypeRef(CodeGen& codeGen, TypeRef argTypeRef)
    {
        if (!argTypeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& argType = codeGen.ctx().typeMgr().get(argTypeRef);
        if (argType.isIntUnsized())
        {
            TypeInfo::Sign sign = argType.payloadIntSign();
            if (sign == TypeInfo::Sign::Unknown)
                sign = TypeInfo::Sign::Signed;
            return codeGen.typeMgr().typeInt(64, sign);
        }

        if (argType.isFloatUnsized())
            return codeGen.typeMgr().typeF64();

        return argTypeRef;
    }

    std::optional<CodeGenNodePayload> resolveVariableArgumentPayload(CodeGen& codeGen, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return std::nullopt;

        SmallVector<AstNodeRef> candidateRefs;
        appendUniqueCandidateRef(candidateRefs, argRef);
        appendUniqueCandidateRef(candidateRefs, codeGen.resolvedNodeRef(argRef));
        appendUniqueCandidateRef(candidateRefs, resolvePreparedArgSourceRef(codeGen, argRef));
        if (!candidateRefs.empty())
            appendUniqueCandidateRef(candidateRefs, codeGen.resolvedNodeRef(candidateRefs.back()));

        for (const AstNodeRef candidateRef : candidateRefs)
        {
            if (const auto payload = tryResolveVariableViewPayload(codeGen, codeGen.viewSymbol(candidateRef)))
                return payload;

            if (const auto payload = tryResolveVariableViewPayload(codeGen, codeGen.sema().viewStored(candidateRef, SemaNodeViewPartE::Symbol)))
                return payload;
        }

        return std::nullopt;
    }
    ABICall::PreparedArgKind abiPreparedArgKind(CallArgumentPassKind passKind)
    {
        switch (passKind)
        {
            case CallArgumentPassKind::Direct:
                return ABICall::PreparedArgKind::Direct;

            case CallArgumentPassKind::InterfaceObject:
                return ABICall::PreparedArgKind::InterfaceObject;

            default:
                SWC_UNREACHABLE();
        }
    }

    void setPayloadStorageKind(CodeGenNodePayload& payload, bool isIndirect)
    {
        if (isIndirect)
            payload.setIsAddress();
        else
            payload.setIsValue();
    }

    TypeRef resolveNormalizedArgTypeRef(CodeGen& codeGen, const SymbolVariable* param, const SemaNodeView& argView)
    {
        TypeRef normalizedTypeRef = TypeRef::invalid();
        if (param != nullptr)
            normalizedTypeRef = param->typeRef();

        if (normalizedTypeRef.isInvalid())
            return argView.typeRef();

        const TypeInfo& paramType = codeGen.ctx().typeMgr().get(normalizedTypeRef);
        if (paramType.isAnyVariadic())
            return argView.typeRef();

        return normalizedTypeRef;
    }

    TypeRef resolveConstantMaterializationTypeRef(CodeGen& codeGen, TypeRef normalizedTypeRef, ConstantRef cstRef)
    {
        if (!normalizedTypeRef.isValid() || !cstRef.isValid())
            return normalizedTypeRef;

        const TypeInfo& normalizedType = codeGen.ctx().typeMgr().get(normalizedTypeRef);
        if (!normalizedType.isReference())
            return normalizedTypeRef;

        const ConstantValue& cst = codeGen.cstMgr().get(cstRef);
        if (cst.isNull() || cst.isValuePointer() || cst.isBlockPointer())
            return normalizedTypeRef;

        const TypeRef pointeeTypeRef = normalizedType.payloadTypeRef();
        return pointeeTypeRef.isValid() ? pointeeTypeRef : normalizedTypeRef;
    }

    void materializePreparedDirectScalarArg(CodeGen& codeGen, CodeGenNodePayload& argPayload, TypeRef normalizedTypeRef, const ABITypeNormalize::NormalizedType& normalizedArg)
    {
        if (!normalizedTypeRef.isValid() || normalizedArg.isIndirect)
            return;

        TaskContext&       ctx            = codeGen.ctx();
        const TypeManager& typeMgr        = ctx.typeMgr();
        MicroBuilder&      builder        = codeGen.builder();
        const TypeInfo&    normalizedType = typeMgr.get(normalizedTypeRef);
        if (normalizedType.isReference())
            return;

        const TypeRef   normalizedTypeUnwrapped = normalizedType.unwrap(ctx, normalizedTypeRef, TypeExpandE::Alias);
        const TypeRef   dstTypeRef              = normalizedTypeUnwrapped.isValid() ? normalizedTypeUnwrapped : normalizedTypeRef;
        const TypeInfo& dstType                 = typeMgr.get(dstTypeRef);

        if (argPayload.typeRef.isValid())
        {
            const TypeInfo& srcTypeInfo      = typeMgr.get(argPayload.typeRef);
            const TypeRef   srcTypeUnwrapped = srcTypeInfo.unwrap(ctx, argPayload.typeRef, TypeExpandE::Alias);
            const TypeRef   srcTypeRef       = srcTypeUnwrapped.isValid() ? srcTypeUnwrapped : argPayload.typeRef;
            const TypeInfo& srcType          = typeMgr.get(srcTypeRef);
            const auto      srcBits          = CodeGenTypeHelpers::numericOrBoolBits(srcType);
            const auto      dstBits          = CodeGenTypeHelpers::numericOrBoolBits(dstType);

            if (srcType.isIntLike() && dstType.isFloat() && srcBits != MicroOpBits::Zero && dstBits != MicroOpBits::Zero)
            {
                MicroReg srcReg = argPayload.reg;
                if (argPayload.isAddress())
                {
                    srcReg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegMem(srcReg, argPayload.reg, 0, srcBits);
                }

                if (getNumBits(srcBits) < 32 || (dstBits == MicroOpBits::B64 && getNumBits(srcBits) == 32))
                {
                    const MicroReg    widenedReg  = codeGen.nextVirtualIntRegister();
                    const MicroOpBits widenedBits = dstBits == MicroOpBits::B64 ? MicroOpBits::B64 : MicroOpBits::B32;
                    if (srcType.isIntSigned())
                        builder.emitLoadSignedExtendRegReg(widenedReg, srcReg, widenedBits, srcBits);
                    else
                        builder.emitLoadZeroExtendRegReg(widenedReg, srcReg, widenedBits, srcBits);
                    srcReg = widenedReg;
                }

                const MicroReg dstReg = codeGen.nextVirtualFloatRegister();
                builder.emitClearReg(dstReg, dstBits);
                builder.emitOpBinaryRegReg(dstReg, srcReg, MicroOp::ConvertIntToFloat, dstBits);
                argPayload.reg     = dstReg;
                argPayload.typeRef = normalizedTypeRef;
                argPayload.setIsValue();
                return;
            }

            if (srcType.isFloat() && dstType.isFloat() && srcBits != MicroOpBits::Zero && dstBits != MicroOpBits::Zero)
            {
                MicroReg srcReg = argPayload.reg;
                if (argPayload.isAddress())
                {
                    srcReg = codeGen.nextVirtualFloatRegister();
                    builder.emitLoadRegMem(srcReg, argPayload.reg, 0, srcBits);
                }

                if (srcBits == dstBits)
                {
                    argPayload.reg     = srcReg;
                    argPayload.typeRef = normalizedTypeRef;
                    argPayload.setIsValue();
                    return;
                }

                const MicroReg dstReg = codeGen.nextVirtualFloatRegister();
                builder.emitClearReg(dstReg, dstBits);
                builder.emitOpBinaryRegReg(dstReg, srcReg, MicroOp::ConvertFloatToFloat, srcBits);
                argPayload.reg     = dstReg;
                argPayload.typeRef = normalizedTypeRef;
                argPayload.setIsValue();
                return;
            }
        }

        if (!argPayload.isAddress())
            return;

        MicroReg dstReg   = MicroReg::invalid();
        auto     loadBits = MicroOpBits::Zero;
        if (normalizedArg.isFloat)
        {
            if (normalizedArg.numBits != 32 && normalizedArg.numBits != 64)
                return;

            dstReg   = codeGen.nextVirtualFloatRegister();
            loadBits = microOpBitsFromBitWidth(normalizedArg.numBits);
        }
        else if (normalizedArg.numBits == 64 && normalizedType.sizeOf(codeGen.ctx()) == sizeof(uint64_t))
        {
            dstReg   = codeGen.nextVirtualIntRegister();
            loadBits = MicroOpBits::B64;
        }
        else
        {
            return;
        }

        builder.emitLoadRegMem(dstReg, argPayload.reg, 0, loadBits);
        argPayload.reg = dstReg;
        argPayload.setIsValue();
    }

    void materializePreparedReferenceArg(CodeGen& codeGen, CodeGenNodePayload& argPayload, TypeRef normalizedTypeRef, const ResolvedCallArgument& resolvedArg, AstNodeRef argRef)
    {
        if (argRef.isInvalid() || normalizedTypeRef.isInvalid())
            return;

        TaskContext&    ctx            = codeGen.ctx();
        const TypeInfo& normalizedType = ctx.typeMgr().get(normalizedTypeRef);
        if (!normalizedType.isReference())
            return;

        if (argPayload.isAddress())
            return;

        const SemaNodeView argView = codeGen.viewType(argRef);
        SWC_ASSERT(argView.type());
        const TypeRef sourceTypeRef = argPayload.effectiveTypeRef(argView.typeRef());
        SWC_ASSERT(sourceTypeRef.isValid());
        const TypeInfo& sourceType = ctx.typeMgr().get(sourceTypeRef);
        if ((sourceType.isPointerOrReference() && !resolvedArg.bindsReferenceToValue) || argPayload.hasMaterializedPointerLikeValue())
            return;

        const CallConv&                        callConv         = CallConv::get(codeGen.function().callConvKind());
        const ABITypeNormalize::NormalizedType normalizedSource = ABITypeNormalize::normalize(ctx, callConv, sourceTypeRef, ABITypeNormalize::Usage::Argument);
        if (normalizedSource.isIndirect)
            return;

        const uint64_t rawSize = ctx.typeMgr().get(sourceTypeRef).sizeOf(ctx);
        SWC_ASSERT(rawSize == 1 || rawSize == 2 || rawSize == 4 || rawSize == 8);

        const CodeGenNodePayload* storedPayload = codeGen.safePayload(argRef);
        SWC_ASSERT(storedPayload != nullptr && storedPayload->runtimeStorageSym != nullptr);

        MicroBuilder&  builder     = codeGen.builder();
        const MicroReg storageReg  = codeGen.runtimeStorageAddressReg(argRef);
        const auto     storageBits = CodeGenTypeHelpers::bitsFromStorageSize(rawSize);
        builder.emitLoadMemReg(storageReg, 0, argPayload.reg, storageBits);

        // Reference parameters expect the pointee address itself as the ABI value.
        argPayload.reg     = storageReg;
        argPayload.typeRef = normalizedTypeRef;
        argPayload.setIsValue();
    }

    uint32_t alignTransientCallStackSize(const CallConv& callConv, uint64_t size)
    {
        if (!size)
            return 0;

        const uint32_t stackAlignment = callConv.stackAlignment ? callConv.stackAlignment : 16;
        size                          = Math::alignUpU64(size, stackAlignment);
        SWC_ASSERT(size <= std::numeric_limits<uint32_t>::max());
        return static_cast<uint32_t>(size);
    }

    MicroReg reserveTransientCallStorage(CodeGen& codeGen, const CallConv& callConv, uint32_t sizeInBytes, uint32_t& outTransientStackSize)
    {
        const uint32_t stackSize = alignTransientCallStackSize(callConv, sizeInBytes);
        SWC_ASSERT(stackSize != 0);
        outTransientStackSize += stackSize;

        MicroBuilder&  builder    = codeGen.builder();
        const MicroReg storageReg = codeGen.nextVirtualIntRegister();
        CodeGenFunctionHelpers::emitStackPointerSubtract(codeGen, callConv, stackSize, storageReg);
        builder.emitLoadRegReg(storageReg, callConv.stackPointer, MicroOpBits::B64);
        return storageReg;
    }

    bool tryResolvePayloadRuntimeStorageAddress(CodeGen& codeGen, const CodeGenNodePayload& payload, MicroReg& outStorageReg)
    {
        outStorageReg          = MicroReg::invalid();
        const auto* storageSym = payload.runtimeStorageSym;
        if (!storageSym)
            return false;

        if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, *storageSym))
        {
            const CodeGenNodePayload storagePayload = CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, *storageSym);
            SWC_ASSERT(storagePayload.isAddress());
            outStorageReg = storagePayload.reg;
            return outStorageReg.isValid();
        }

        if (storageSym->hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            const CodeGenNodePayload storagePayload = CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, codeGen.function(), *storageSym);
            if (!storagePayload.isAddress())
                return false;

            outStorageReg = storagePayload.reg;
            return outStorageReg.isValid();
        }

        if ((storageSym->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) ||
             (codeGen.localStackBaseReg().isValid() && storageSym->hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))))
        {
            const CodeGenNodePayload storagePayload = codeGen.resolveLocalStackPayload(*storageSym);
            SWC_ASSERT(storagePayload.isAddress());
            outStorageReg = storagePayload.reg;
            return outStorageReg.isValid();
        }

        if (!storageSym->hasGlobalStorage())
            return false;

        CodeGenNodePayload storagePayload;
        storagePayload.typeRef = storageSym->typeRef();
        storagePayload.setIsAddress();
        storagePayload.reg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegDataSegmentReloc(storagePayload.reg, storageSym->globalStorageKind(), storageSym->offset());
        outStorageReg = storagePayload.reg;
        return outStorageReg.isValid();
    }

    bool tryResolvePreparedIndirectArgAddress(CodeGen& codeGen, CodeGenNodePayload& argPayload, TypeRef normalizedTypeRef, AstNodeRef argRef)
    {
        if (argPayload.isAddress())
            return true;

        MicroReg storageReg = MicroReg::invalid();
        if (tryResolvePayloadRuntimeStorageAddress(codeGen, argPayload, storageReg))
        {
            argPayload.reg     = storageReg;
            argPayload.typeRef = normalizedTypeRef;
            argPayload.setIsAddress();
            return true;
        }

        const AstNodeRef sourceRef = resolvePreparedArgSourceRef(codeGen, argRef);
        if (!sourceRef.isValid())
            return false;

        if (const auto sourcePayload = resolveVariableArgumentPayload(codeGen, sourceRef); sourcePayload && sourcePayload->isAddress())
        {
            argPayload.reg     = sourcePayload->reg;
            argPayload.typeRef = normalizedTypeRef;
            argPayload.setIsAddress();
            return true;
        }

        const SymbolVariable* sourceStorageSym = codeGen.runtimeStorageSymbol(sourceRef);
        if (sourceStorageSym == nullptr)
            return false;
        if (!sourceStorageSym->hasGlobalStorage() &&
            !CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, *sourceStorageSym) &&
            !sourceStorageSym->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) &&
            !(codeGen.localStackBaseReg().isValid() && sourceStorageSym->hasExtraFlag(SymbolVariableFlagsE::FunctionLocal)))
            return false;

        argPayload.reg     = codeGen.runtimeStorageAddressReg(sourceRef);
        argPayload.typeRef = normalizedTypeRef;
        argPayload.setIsAddress();
        return true;
    }

    bool isTransparentCallResultParent(const AstNode& parent)
    {
        return (SemaHelpers::isTransparentExprNode(parent) && parent.isNot(AstNodeId::AsCastExpr)) ||
               parent.is(AstNodeId::InitializerExpr);
    }

    bool tryUseVarInitStorageForDirectCallResult(CodeGen& codeGen, AstNodeRef callRef, TypeRef returnTypeRef, MicroReg& outStorageReg, SymbolVariable*& outStorageSym)
    {
        outStorageReg = MicroReg::invalid();
        outStorageSym = nullptr;

        const AstNodeRef resolvedCallRef = codeGen.viewZero(callRef).nodeRef();
        if (resolvedCallRef.isInvalid())
            return false;
        if (!returnTypeRef.isValid())
            return false;

        const TypeInfo& returnType          = codeGen.typeMgr().get(returnTypeRef);
        const TypeRef   unwrappedReturnType = returnType.unwrap(codeGen.ctx(), returnTypeRef, TypeExpandE::Alias);
        const TypeRef   storageReturnType   = unwrappedReturnType.isValid() ? unwrappedReturnType : returnTypeRef;

        for (size_t parentIndex = 0;; ++parentIndex)
        {
            const AstNodeRef parentRef = codeGen.visit().parentNodeRef(parentIndex);
            if (parentRef.isInvalid())
                return false;

            const AstNode& parent = codeGen.node(parentRef);
            if (isTransparentCallResultParent(parent))
                continue;

            if (parent.isNot(AstNodeId::SingleVarDecl))
                return false;

            const auto& varDecl = parent.cast<AstSingleVarDecl>();
            if (varDecl.nodeInitRef.isInvalid())
                return false;

            Symbol* symbol = codeGen.viewSymbol(parentRef).sym();
            if (!symbol || !symbol->isVariable())
                return false;

            auto& symVar = symbol->cast<SymbolVariable>();
            if (!symVar.typeRef().isValid())
                return false;

            const TypeInfo& storageType          = codeGen.typeMgr().get(symVar.typeRef());
            const TypeRef   unwrappedStorageType = storageType.unwrap(codeGen.ctx(), symVar.typeRef(), TypeExpandE::Alias);
            const TypeRef   storageTypeRef       = unwrappedStorageType.isValid() ? unwrappedStorageType : symVar.typeRef();
            if (storageTypeRef != storageReturnType)
                return false;

            if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar))
            {
                const CodeGenNodePayload storagePayload = CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, symVar);
                SWC_ASSERT(storagePayload.isAddress());
                outStorageReg = storagePayload.reg;
                outStorageSym = &symVar;
                return outStorageReg.isValid();
            }

            if (!codeGen.localStackBaseReg().isValid() || !symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
                return false;

            const CodeGenNodePayload storagePayload = codeGen.resolveLocalStackPayload(symVar);
            SWC_ASSERT(storagePayload.isAddress());
            outStorageReg = storagePayload.reg;
            outStorageSym = &symVar;
            return outStorageReg.isValid();
        }
    }

    void materializePreparedIndirectCopyArg(CodeGen& codeGen, CodeGenNodePayload& argPayload, const CallConv& callConv, TypeRef normalizedTypeRef, const ABITypeNormalize::NormalizedType& normalizedArg, AstNodeRef argRef, uint32_t& outTransientStackSize)
    {
        if (!normalizedArg.isIndirect || !normalizedArg.needsIndirectCopy)
            return;

        SWC_ASSERT(normalizedArg.indirectSize != 0);
        tryResolvePreparedIndirectArgAddress(codeGen, argPayload, normalizedTypeRef, argRef);

        const MicroReg storageReg = reserveTransientCallStorage(codeGen, callConv, normalizedArg.indirectSize, outTransientStackSize);
        // Some indirect ABI arguments are materialized as immediate payloads that still
        // carry the address of their backing bytes in the register payload itself (for
        // example a constant string value). Spill through the generic payload helper
        // instead of requiring an l-value address here.
        CodeGenMemoryHelpers::storePayloadToAddress(codeGen, storageReg, argPayload, normalizedArg.indirectSize);

        argPayload.reg     = storageReg;
        argPayload.typeRef = normalizedTypeRef;
        argPayload.setIsValue();
    }

    TypeRef borrowedAggregateStorageTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& typeInfo            = codeGen.typeMgr().get(typeRef);
        const TypeRef   unwrappedTypeRef    = typeInfo.unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeRef   storageTypeRef      = unwrappedTypeRef.isValid() ? unwrappedTypeRef : typeRef;
        const TypeInfo& storageType         = codeGen.typeMgr().get(storageTypeRef);
        const bool      isBorrowedAggregate = storageType.isStruct() || storageType.isArray() || storageType.isAggregate() || (storageType.isFunction() && storageType.isLambdaClosure());
        return isBorrowedAggregate ? storageTypeRef : TypeRef::invalid();
    }

    void materializePreparedBorrowedAggregateArg(CodeGen& codeGen, CodeGenNodePayload& argPayload, const CallConv& callConv, TypeRef normalizedTypeRef, const ABITypeNormalize::NormalizedType& normalizedArg, AstNodeRef argRef, uint32_t& outTransientStackSize)
    {
        if (!normalizedArg.isIndirect || normalizedArg.needsIndirectCopy)
            return;
        if (argRef.isInvalid() || !argPayload.isValue())
            return;

        const TypeRef storageTypeRef = borrowedAggregateStorageTypeRef(codeGen, normalizedTypeRef);
        if (storageTypeRef.isInvalid())
            return;
        const CodeGenNodePayload sourcePayload = argPayload;

        if (!tryResolvePreparedIndirectArgAddress(codeGen, argPayload, normalizedTypeRef, argRef))
        {
            SWC_ASSERT(normalizedArg.indirectSize != 0);
            const MicroReg storageReg = reserveTransientCallStorage(codeGen, callConv, normalizedArg.indirectSize, outTransientStackSize);
            CodeGenMemoryHelpers::storePayloadToAddress(codeGen, storageReg, sourcePayload, normalizedArg.indirectSize);
            argPayload.reg = storageReg;
        }
        else
        {
            CodeGenMemoryHelpers::storePayloadToAddress(codeGen, argPayload.reg, sourcePayload, normalizedArg.indirectSize);
        }

        argPayload.typeRef = normalizedTypeRef;
        argPayload.setIsAddress();
    }

    void materializePreparedPointerDecayArg(CodeGen& codeGen, CodeGenNodePayload& argPayload, TypeRef normalizedTypeRef, AstNodeRef argRef)
    {
        if (argRef.isInvalid() || normalizedTypeRef.isInvalid())
            return;
        if (!argPayload.isAddress() || argPayload.hasMaterializedPointerLikeValue())
            return;

        TaskContext&    ctx            = codeGen.ctx();
        const TypeInfo& normalizedType = ctx.typeMgr().get(normalizedTypeRef);
        if (!normalizedType.isAnyPointer() && !normalizedType.isCString())
            return;

        const AstNodeRef sourceRef = resolvePreparedArgSourceRef(codeGen, argRef);
        if (sourceRef.isInvalid())
            return;

        const TypeRef sourceTypeRef = codeGen.sema().viewStored(sourceRef, SemaNodeViewPartE::Type).typeRef();
        if (!sourceTypeRef.isValid())
            return;

        const TypeInfo& sourceType = ctx.typeMgr().get(sourceTypeRef);
        if (!sourceType.isArray() && !sourceType.isAggregateArray())
            return;

        // Array-to-pointer decay passes the address itself as the runtime pointer value.
        // Keeping the payload address-backed makes ABI lowering load the first array bytes instead,
        // which turns zero-initialized buffers into null pointer arguments.
        argPayload.typeRef = normalizedTypeRef;
        argPayload.setIsValue();
        argPayload.markMaterializedPointerLikeValue();
    }

    void fillPreparedDirectArgType(ABICall::PreparedArg& outPreparedArg, CodeGen& codeGen, const CallConv& callConv, const CodeGenNodePayload& argPayload, TypeRef normalizedTypeRef, const ResolvedCallArgument& resolvedArg)
    {
        if (normalizedTypeRef.isInvalid())
            return;

        TaskContext&                           ctx            = codeGen.ctx();
        const TypeInfo&                        normalizedType = ctx.typeMgr().get(normalizedTypeRef);
        const ABITypeNormalize::NormalizedType normalizedArg  = ABITypeNormalize::normalize(ctx, callConv, normalizedTypeRef, ABITypeNormalize::Usage::Argument);
        SWC_ASSERT(!CodeGenFunctionHelpers::shouldMaterializeAddressBackedValue(codeGen, normalizedType, normalizedArg.isIndirect, normalizedArg.isFloat, normalizedArg.numBits));
        const bool passAddressRef = normalizedType.isReference() && resolvedArg.bindsReferenceToValue;

        outPreparedArg.isFloat     = normalizedArg.isFloat;
        outPreparedArg.isSigned    = normalizedArg.isSigned;
        outPreparedArg.numBits     = normalizedArg.numBits;
        outPreparedArg.isAddressed = argPayload.isAddress() && !normalizedArg.isIndirect && !passAddressRef;
    }

    MicroOpBits preparedArgDirectCopyBits(const ABICall::PreparedArg& arg)
    {
        if (!arg.numBits)
            return MicroOpBits::B64;

        const MicroOpBits bits = microOpBitsFromBitWidth(arg.numBits);
        SWC_ASSERT(bits != MicroOpBits::Zero);
        return bits;
    }

    void doIsolatePreparedRegisterArgSources(CodeGen& codeGen, const CallConv& callConv, SmallVector<ABICall::PreparedArg>& args)
    {
        MicroBuilder&  builder    = codeGen.builder();
        const uint32_t numRegArgs = std::min(static_cast<uint32_t>(args.size()), callConv.numArgRegisterSlots());
        for (uint32_t i = 0; i < numRegArgs; ++i)
        {
            ABICall::PreparedArg& arg = args[i];
            if (arg.kind == ABICall::PreparedArgKind::InterfaceObject)
            {
                if (!arg.srcReg.isVirtualInt())
                    continue;

                // Interface dispatch dereferences the runtime interface pair to recover the concrete
                // receiver object. Keep that source address pinned to this argument lane so earlier
                // argument materialization cannot clobber it before the dereference happens.
                const MicroReg argLaneSourceReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(argLaneSourceReg, arg.srcReg, MicroOpBits::B64);
                builder.preserveVirtualCopy(argLaneSourceReg);
                arg.srcReg             = argLaneSourceReg;
                arg.constrainToArgLane = true;
                continue;
            }

            if (arg.kind != ABICall::PreparedArgKind::Direct || arg.isAddressed)
                continue;

            MicroReg argLaneSourceReg = MicroReg::invalid();
            if (arg.isFloat)
            {
                if (!arg.srcReg.isVirtualFloat())
                    continue;

                argLaneSourceReg = codeGen.nextVirtualFloatRegister();
            }
            else
            {
                if (!arg.srcReg.isVirtualInt())
                    continue;

                argLaneSourceReg = codeGen.nextVirtualIntRegister();
            }

            builder.emitLoadRegReg(argLaneSourceReg, arg.srcReg, preparedArgDirectCopyBits(arg));
            builder.preserveVirtualCopy(argLaneSourceReg);
            arg.srcReg             = argLaneSourceReg;
            arg.constrainToArgLane = true;
        }
    }

    const SymbolFunction* currentLocationFunction(CodeGen& codeGen)
    {
        if (codeGen.frame().hasCurrentInlineContext())
        {
            const CodeGenFrame::InlineContext& inlineCtx = codeGen.frame().currentInlineContext();
            if (inlineCtx.payload && inlineCtx.payload->sourceFunction)
                return SemaRuntime::transparentLocationFunction(inlineCtx.payload->sourceFunction);
        }

        return SemaRuntime::transparentLocationFunction(&codeGen.function());
    }

    Result defaultArgumentConstantRef(CodeGen& codeGen, ConstantRef& outCstRef, AstNodeRef callRef, const ResolvedCallArgument& arg)
    {
        outCstRef = ConstantRef::invalid();

        switch (arg.defaultKind)
        {
            case CallArgumentDefaultKind::Constant:
                outCstRef = arg.defaultCstRef;
                return Result::Continue;

            case CallArgumentDefaultKind::CallerLocation:
            {
                const SourceCodeRange codeRange = codeGen.node(callRef).codeRangeWithChildren(codeGen.ctx(), codeGen.ast());
                return ConstantHelpers::makeSourceCodeLocation(codeGen.sema(), outCstRef, codeRange, currentLocationFunction(codeGen));
            }

            case CallArgumentDefaultKind::None:
                break;
        }

        return Result::Continue;
    }

    Result appendPreparedFixedArg(SmallVector<ABICall::PreparedArg>& outArgs, CodeGen& codeGen, AstNodeRef callRef, const CallConv& callConv, const SymbolVariable* param, const ResolvedCallArgument& arg, uint32_t& outTransientStackSize)
    {
        CodeGenNodePayload argPayload;
        TypeRef            normalizedTypeRef = TypeRef::invalid();
        const AstNodeRef   argRef            = arg.argRef;
        if (argRef.isValid())
        {
            const AstNodeRef                  resolvedArgRef = codeGen.resolvedNodeRef(argRef);
            SemaNodeView                      argView        = codeGen.viewType(argRef);
            SemaNodeView                      argConstView   = codeGen.viewTypeConstant(argRef);
            std::optional<CodeGenNodePayload> fallbackPayload;
            const CodeGenNodePayload*         payload = codeGen.safePayload(argRef);

            if (resolvedArgRef != argRef &&
                (!payload || !payload->reg.isValid()) &&
                !argConstView.cstRef().isValid())
            {
                argView      = codeGen.sema().viewStored(argRef, SemaNodeViewPartE::Type);
                argConstView = codeGen.sema().viewStored(argRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            }

            normalizedTypeRef               = resolveNormalizedArgTypeRef(codeGen, param, argView);
            const TypeRef constantTypeRef   = resolveConstantMaterializationTypeRef(codeGen, normalizedTypeRef, argConstView.cstRef());
            const bool    isNullConstantArg = argConstView.cst() && argConstView.cst()->isNull();

            if ((!payload || !payload->reg.isValid()) && resolvedArgRef == argRef)
            {
                SWC_RESULT(codeGen.emitNodeNow(argRef));
                payload = codeGen.safePayload(argRef);
            }

            if ((!payload || !payload->reg.isValid()) && argRef.isValid())
            {
                fallbackPayload = resolveVariableArgumentPayload(codeGen, argRef);
                if (fallbackPayload)
                    payload = &fallbackPayload.value();
            }

            if (payload && payload->reg.isValid())
            {
                argPayload = *payload;

                bool requiresTypedConstMaterialization = constantTypeRef.isValid() && isNullConstantArg;
                if (!requiresTypedConstMaterialization && constantTypeRef.isValid())
                {
                    const TaskContext& ctx             = codeGen.ctx();
                    const TypeRef      expectedTypeRef = ctx.typeMgr().get(constantTypeRef).unwrap(ctx, constantTypeRef, TypeExpandE::Alias);
                    const TypeRef      payloadTypeRef  = argPayload.typeRef.isValid() ? ctx.typeMgr().get(argPayload.typeRef).unwrap(ctx, argPayload.typeRef, TypeExpandE::Alias) : TypeRef::invalid();
                    requiresTypedConstMaterialization  = expectedTypeRef.isValid() && (payloadTypeRef.isInvalid() || expectedTypeRef != payloadTypeRef);
                }

                if (requiresTypedConstMaterialization)
                {
                    if (argConstView.cstRef().isValid())
                        SWC_INTERNAL_CHECK(CodeGenCallHelpers::materializeTypedConstantPayload(codeGen, argPayload, constantTypeRef, argConstView.cstRef()));
                }
            }
            else
            {
                SWC_ASSERT(argConstView.cstRef().isValid());
                SWC_INTERNAL_CHECK(CodeGenCallHelpers::materializeTypedConstantPayload(codeGen, argPayload, constantTypeRef, argConstView.cstRef()));
            }
        }
        else
        {
            SWC_ASSERT(param != nullptr);
            normalizedTypeRef         = param->typeRef();
            ConstantRef defaultCstRef = ConstantRef::invalid();
            SWC_RESULT(defaultArgumentConstantRef(codeGen, defaultCstRef, callRef, arg));
            SWC_ASSERT(defaultCstRef.isValid());
            const TypeRef constantTypeRef = resolveConstantMaterializationTypeRef(codeGen, normalizedTypeRef, defaultCstRef);
            SWC_INTERNAL_CHECK(CodeGenCallHelpers::materializeTypedConstantPayload(codeGen, argPayload, constantTypeRef, defaultCstRef));
        }

        ABICall::PreparedArg preparedArg;
        if (normalizedTypeRef.isValid())
        {
            if (arg.passUfcsAddressAsPointer && argPayload.isAddress())
            {
                argPayload.typeRef = normalizedTypeRef;
                argPayload.setIsValue();
            }

            materializePreparedReferenceArg(codeGen, argPayload, normalizedTypeRef, arg, argRef);
            materializePreparedPointerDecayArg(codeGen, argPayload, normalizedTypeRef, argRef);
            const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, normalizedTypeRef, ABITypeNormalize::Usage::Argument);
            materializePreparedIndirectCopyArg(codeGen, argPayload, callConv, normalizedTypeRef, normalizedArg, argRef, outTransientStackSize);
            materializePreparedBorrowedAggregateArg(codeGen, argPayload, callConv, normalizedTypeRef, normalizedArg, argRef, outTransientStackSize);
            materializePreparedDirectScalarArg(codeGen, argPayload, normalizedTypeRef, normalizedArg);
        }

        preparedArg.srcReg = argPayload.reg;
        fillPreparedDirectArgType(preparedArg, codeGen, callConv, argPayload, normalizedTypeRef, arg);
        preparedArg.kind = abiPreparedArgKind(arg.passKind);
        outArgs.push_back(preparedArg);
        return Result::Continue;
    }

    const CodeGenNodePayload* resolveCallPayload(CodeGen& codeGen, AstNodeRef calleeRef)
    {
        const CodeGenNodePayload* payload = codeGen.safePayload(calleeRef);
        if (payload && payload->reg.isValid())
            return payload;

        const AstNodeRef resolvedRef = codeGen.viewZero(calleeRef).nodeRef();
        if (resolvedRef.isValid() && resolvedRef != calleeRef)
        {
            const CodeGenNodePayload* resolvedPayload = codeGen.safePayload(resolvedRef);
            if (resolvedPayload && resolvedPayload->reg.isValid())
                return resolvedPayload;
        }

        return nullptr;
    }

    MicroReg materializeCallTargetReg(CodeGen& codeGen, const CodeGenNodePayload& calleePayload, const SymbolFunction& calledFunction, const CallConv& callConv, MicroReg& outClosureContextReg)
    {
        outClosureContextReg = MicroReg::invalid();

        MicroBuilder&  builder   = codeGen.builder();
        const MicroReg targetReg = codeGen.nextVirtualIntRegister();
        if (calledFunction.isClosure())
        {
            SWC_ASSERT(calleePayload.isAddress());
            builder.emitLoadRegMem(targetReg, calleePayload.reg, offsetof(Runtime::ClosureValue, invoke), MicroOpBits::B64);
            outClosureContextReg = codeGen.offsetAddressReg(calleePayload.reg, offsetof(Runtime::ClosureValue, capture));
        }
        else if (calleePayload.isAddress())
            builder.emitLoadRegMem(targetReg, calleePayload.reg, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(targetReg, calleePayload.reg, MicroOpBits::B64);

        builder.addVirtualRegForbiddenPhysRegs(targetReg, callConv.intArgRegs);
        builder.addVirtualRegForbiddenPhysReg(targetReg, callConv.intReturn);
        return targetReg;
    }

    void emitFunctionCall(CodeGen& codeGen, const SymbolFunction& calledFunction, const ABICall::PreparedCall& preparedCall, MicroReg callTargetReg)
    {
        MicroBuilder&      builder      = codeGen.builder();
        const CallConvKind callConvKind = calledFunction.callConvKind();

        if (callTargetReg.isValid())
        {
            ABICall::callReg(builder, callConvKind, callTargetReg, preparedCall);
            return;
        }

        if (calledFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &calledFunction, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &calledFunction, preparedCall);
    }

    void storeTypedVariadicElement(CodeGen& codeGen, MicroReg dstAddressReg, const CodeGenNodePayload& srcPayload, uint32_t elemSize)
    {
        MicroBuilder& builder = codeGen.builder();
        if (srcPayload.isAddress())
        {
            CodeGenMemoryHelpers::emitMemCopy(codeGen, dstAddressReg, srcPayload.reg, elemSize);
            return;
        }

        if (elemSize > 8)
        {
            CodeGenMemoryHelpers::emitMemCopy(codeGen, dstAddressReg, srcPayload.reg, elemSize);
            return;
        }

        if (elemSize == 1 || elemSize == 2 || elemSize == 4 || elemSize == 8)
        {
            builder.emitLoadMemReg(dstAddressReg, 0, srcPayload.reg, microOpBitsFromChunkSize(elemSize));
            return;
        }

        builder.emitLoadMemReg(dstAddressReg, 0, srcPayload.reg, MicroOpBits::B64);
    }

    bool isMatchingTypedVariadicForwardingArg(CodeGen& codeGen, const ResolvedCallArgument& arg, TypeRef variadicElemTypeRef)
    {
        if (arg.argRef.isInvalid() || !variadicElemTypeRef.isValid())
            return false;

        const SemaNodeView argView = codeGen.viewType(arg.argRef);
        return argView.type() && argView.type()->isTypedVariadic() && argView.type()->payloadTypeRef() == variadicElemTypeRef;
    }

    void packTypedVariadicArgument(ABICall::PreparedArg& outPreparedArg, uint32_t& outTransientStackSize, CodeGen& codeGen, const CallConv& callConv, std::span<const ResolvedCallArgument> args, TypeRef variadicElemTypeRef, const ABITypeNormalize::NormalizedType& normalizedVariadic)
    {
        MicroBuilder& builder = codeGen.builder();
        SWC_ASSERT(normalizedVariadic.numBits == 64);
        SWC_ASSERT(!normalizedVariadic.isIndirect);

        if (args.size() == 1 && isMatchingTypedVariadicForwardingArg(codeGen, args[0], variadicElemTypeRef))
        {
            const CodeGenNodePayload& argPayload = codeGen.payload(args[0].argRef);
            outPreparedArg.srcReg                = argPayload.reg;
            outPreparedArg.kind                  = ABICall::PreparedArgKind::Direct;
            outPreparedArg.isFloat               = normalizedVariadic.isFloat;
            outPreparedArg.isSigned              = normalizedVariadic.isSigned;
            outPreparedArg.numBits               = normalizedVariadic.numBits;
            outPreparedArg.isAddressed           = argPayload.isAddress();
            return;
        }

        TaskContext&    ctx          = codeGen.ctx();
        const TypeInfo& variadicType = ctx.typeMgr().get(variadicElemTypeRef);
        const uint64_t  rawElemSize  = variadicType.sizeOf(ctx);
        SWC_ASSERT(rawElemSize > 0 && rawElemSize <= std::numeric_limits<uint32_t>::max());

        const auto     elemSize      = static_cast<uint32_t>(rawElemSize);
        const uint32_t elemAlign     = std::max<uint32_t>(variadicType.alignOf(ctx), 1);
        const uint64_t variadicCount = args.size();

        uint64_t totalStorageSize = 0;
        for (uint64_t i = 0; i < variadicCount; ++i)
        {
            totalStorageSize = Math::alignUpU64(totalStorageSize, elemAlign);
            totalStorageSize += elemSize;
        }
        constexpr uint64_t sliceAlign     = alignof(Runtime::Slice<std::byte>);
        const uint64_t     sliceOffset    = Math::alignUpU64(totalStorageSize, sliceAlign);
        const uint64_t     totalFrameSize = sliceOffset + sizeof(Runtime::Slice<std::byte>);
        SWC_ASSERT(totalFrameSize <= std::numeric_limits<uint32_t>::max());

        const uint32_t frameSize    = alignTransientCallStackSize(callConv, totalFrameSize);
        const MicroReg frameBaseReg = codeGen.nextVirtualIntRegister();
        if (frameSize)
        {
            outTransientStackSize += frameSize;
            CodeGenFunctionHelpers::emitStackPointerSubtract(codeGen, callConv, frameSize, frameBaseReg);
        }

        builder.emitLoadRegReg(frameBaseReg, callConv.stackPointer, MicroOpBits::B64);

        uint64_t offset = 0;
        for (uint64_t i = 0; i < variadicCount; ++i)
        {
            const AstNodeRef argRef = args[i].argRef;
            if (argRef.isInvalid())
                continue;

            const CodeGenNodePayload& argPayload = codeGen.payload(argRef);
            offset                               = Math::alignUpU64(offset, elemAlign);
            MicroReg dstAddressReg               = frameBaseReg;
            if (offset)
            {
                dstAddressReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(dstAddressReg, frameBaseReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(dstAddressReg, ApInt(offset, 64), MicroOp::Add, MicroOpBits::B64);
            }
            storeTypedVariadicElement(codeGen, dstAddressReg, argPayload, elemSize);
            offset += elemSize;
        }

        MicroReg sliceAddrReg = frameBaseReg;
        if (sliceOffset)
        {
            sliceAddrReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(sliceAddrReg, frameBaseReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(sliceAddrReg, ApInt(sliceOffset, 64), MicroOp::Add, MicroOpBits::B64);
        }

        builder.emitLoadMemReg(sliceAddrReg, offsetof(Runtime::Slice<std::byte>, ptr), frameBaseReg, MicroOpBits::B64);
        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(countReg, ApInt(variadicCount, 64), MicroOpBits::B64);
        builder.emitLoadMemReg(sliceAddrReg, offsetof(Runtime::Slice<std::byte>, count), countReg, MicroOpBits::B64);

        outPreparedArg.srcReg      = sliceAddrReg;
        outPreparedArg.kind        = ABICall::PreparedArgKind::Direct;
        outPreparedArg.isFloat     = normalizedVariadic.isFloat;
        outPreparedArg.isSigned    = normalizedVariadic.isSigned;
        outPreparedArg.numBits     = normalizedVariadic.numBits;
        outPreparedArg.isAddressed = false;
    }

    struct UntypedVariadicArgInfo
    {
        AstNodeRef         argRef = AstNodeRef::invalid();
        CodeGenNodePayload argPayload;
        TypeRef            argTypeRef     = TypeRef::invalid();
        ConstantRef        typeInfoCstRef = ConstantRef::invalid();
        uint32_t           valueSize      = 0;
        uint32_t           valueAlign     = 1;
        bool               isAny          = false;
        bool               needsSpill     = false;
        uint64_t           spillOffset    = 0;
    };

    void packUntypedVariadicArgument(ABICall::PreparedArg& outPreparedArg, uint32_t& outTransientStackSize, CodeGen& codeGen, const CallConv& callConv, std::span<const ResolvedCallArgument> args, const ABITypeNormalize::NormalizedType& normalizedVariadic)
    {
        MicroBuilder& builder = codeGen.builder();
        SWC_ASSERT(normalizedVariadic.numBits == 64);
        SWC_ASSERT(!normalizedVariadic.isIndirect);

        TaskContext& ctx = codeGen.ctx();

        // Forwarding: a single argument whose type is variadic is already a packed slice.
        // Pass it through directly without re-packing.
        if (args.size() == 1 && args[0].argRef.isValid())
        {
            const SemaNodeView argView = codeGen.viewType(args[0].argRef);
            if (argView.type() && argView.type()->isVariadic())
            {
                const CodeGenNodePayload& argPayload = codeGen.payload(args[0].argRef);
                outPreparedArg.srcReg                = argPayload.reg;
                outPreparedArg.kind                  = ABICall::PreparedArgKind::Direct;
                outPreparedArg.isFloat               = normalizedVariadic.isFloat;
                outPreparedArg.isSigned              = normalizedVariadic.isSigned;
                outPreparedArg.numBits               = normalizedVariadic.numBits;
                outPreparedArg.isAddressed           = argPayload.isAddress();
                return;
            }
        }

        SmallVector<UntypedVariadicArgInfo> variadicInfos;
        variadicInfos.reserve(args.size());

        for (const ResolvedCallArgument& resolvedArg : args)
        {
            if (resolvedArg.argRef.isInvalid())
                continue;

            const CodeGenNodePayload& argPayload     = codeGen.payload(resolvedArg.argRef);
            const TypeRef             wrapperTypeRef = codeGen.viewType(resolvedArg.argRef).typeRef();
            const TypeRef             argTypeRef     = concretizeUntypedVariadicRuntimeTypeRef(codeGen, resolveUntypedVariadicArgTypeRef(codeGen, argPayload, resolvedArg.argRef));
            SWC_ASSERT(argTypeRef.isValid());
            const TypeInfo& argType            = ctx.typeMgr().get(argTypeRef);
            const TypeRef   resolvedArgTypeRef = ctx.typeMgr().unwrapAliasEnum(ctx, argTypeRef);
            const TypeInfo& resolvedArgType    = ctx.typeMgr().get(resolvedArgTypeRef.isValid() ? resolvedArgTypeRef : argTypeRef);
            const uint64_t  rawArgSize         = argType.sizeOf(ctx);
            SWC_ASSERT(rawArgSize > 0 && rawArgSize <= std::numeric_limits<uint32_t>::max());

            UntypedVariadicArgInfo info;
            info.argRef     = resolvedArg.argRef;
            info.argPayload = argPayload;
            info.argTypeRef = argTypeRef;
            info.valueSize  = static_cast<uint32_t>(rawArgSize);
            info.valueAlign = std::max<uint32_t>(argType.alignOf(ctx), 1);
            info.isAny      = resolvedArgType.isAny();

            if (!info.isAny)
            {
                if (argTypeRef == wrapperTypeRef)
                    info.typeInfoCstRef = resolvedArg.typeInfoCstRef;
                if (!info.typeInfoCstRef.isValid())
                {
                    ConstantRef  typeInfoCstRef = ConstantRef::invalid();
                    const Result typeInfoRes    = codeGen.cstMgr().makeTypeInfo(codeGen.sema(), typeInfoCstRef, info.argTypeRef, info.argRef);
                    SWC_INTERNAL_CHECK(typeInfoRes == Result::Continue);
                    info.typeInfoCstRef = typeInfoCstRef;
                }
            }

            if (info.argPayload.reg == callConv.stackPointer)
            {
                info.argPayload.reg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(info.argPayload.reg, callConv.stackPointer, MicroOpBits::B64);
            }

            const MicroOpBits scalarBits = CodeGenTypeHelpers::scalarStoreBits(argType, ctx);
            if (info.argPayload.isAddress() && scalarBits != MicroOpBits::Zero)
            {
                const MicroReg addressReg = info.argPayload.reg;
                info.argPayload.reg       = argType.isFloat() ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(info.argPayload.reg, addressReg, 0, scalarBits);
                info.argPayload.setIsValue();
            }

            info.needsSpill = info.valueSize <= 8 || info.isAny;
            SWC_ASSERT(info.isAny || info.typeInfoCstRef.isValid());
            variadicInfos.push_back(info);
        }

        uint64_t spillStorageSize = 0;
        for (uint64_t i = 0; i < variadicInfos.size(); ++i)
        {
            UntypedVariadicArgInfo& info = variadicInfos[i];
            if (!info.needsSpill && info.argPayload.isValue() && info.valueSize > 8 && i + 1 < variadicInfos.size())
                info.needsSpill = true;

            if (info.needsSpill)
            {
                spillStorageSize = Math::alignUpU64(spillStorageSize, info.valueAlign);
                info.spillOffset = spillStorageSize;
                spillStorageSize += info.valueSize;
            }
        }

        const uint64_t     variadicCount = variadicInfos.size();
        constexpr uint64_t anyAlign      = alignof(Runtime::Any);
        const uint64_t     anyOffset     = Math::alignUpU64(spillStorageSize, anyAlign);
        const uint64_t     anyStorage    = variadicCount * sizeof(Runtime::Any);

        constexpr uint64_t sliceAlign     = alignof(Runtime::Slice<std::byte>);
        const uint64_t     sliceOffset    = Math::alignUpU64(anyOffset + anyStorage, sliceAlign);
        const uint64_t     totalFrameSize = sliceOffset + sizeof(Runtime::Slice<std::byte>);
        SWC_ASSERT(totalFrameSize <= std::numeric_limits<uint32_t>::max());

        const uint32_t frameSize    = alignTransientCallStackSize(callConv, totalFrameSize);
        const MicroReg frameBaseReg = codeGen.nextVirtualIntRegister();
        if (frameSize)
        {
            outTransientStackSize += frameSize;
            CodeGenFunctionHelpers::emitStackPointerSubtract(codeGen, callConv, frameSize, frameBaseReg);
        }

        builder.emitLoadRegReg(frameBaseReg, callConv.stackPointer, MicroOpBits::B64);

        MicroReg anyBaseReg = frameBaseReg;
        if (anyOffset)
        {
            anyBaseReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(anyBaseReg, frameBaseReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(anyBaseReg, ApInt(anyOffset, 64), MicroOp::Add, MicroOpBits::B64);
        }

        for (uint64_t i = 0; i < variadicCount; ++i)
        {
            const UntypedVariadicArgInfo& info = variadicInfos[i];

            MicroReg anyEntryReg = anyBaseReg;
            if (i)
            {
                anyEntryReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(anyEntryReg, anyBaseReg, MicroOpBits::B64);
                builder.emitOpBinaryRegImm(anyEntryReg, ApInt(i * sizeof(Runtime::Any), 64), MicroOp::Add, MicroOpBits::B64);
            }

            MicroReg valuePtrReg;
            if (info.needsSpill)
            {
                valuePtrReg = frameBaseReg;
                if (info.spillOffset)
                {
                    valuePtrReg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegReg(valuePtrReg, frameBaseReg, MicroOpBits::B64);
                    builder.emitOpBinaryRegImm(valuePtrReg, ApInt(info.spillOffset, 64), MicroOp::Add, MicroOpBits::B64);
                }
                storeTypedVariadicElement(codeGen, valuePtrReg, info.argPayload, info.valueSize);
            }
            else if (info.argPayload.isAddress())
            {
                valuePtrReg = info.argPayload.reg;
            }
            else
            {
                valuePtrReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(valuePtrReg, info.argPayload.reg, MicroOpBits::B64);
            }

            if (info.isAny)
            {
                // Passing an any through "..." must preserve the boxed payload instead of boxing the any object itself.
                SWC_ASSERT(info.needsSpill);

                const MicroReg boxedValueReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(boxedValueReg, valuePtrReg, offsetof(Runtime::Any, value), MicroOpBits::B64);
                builder.emitLoadMemReg(anyEntryReg, offsetof(Runtime::Any, value), boxedValueReg, MicroOpBits::B64);

                const MicroReg boxedTypeReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(boxedTypeReg, valuePtrReg, offsetof(Runtime::Any, type), MicroOpBits::B64);
                builder.emitLoadMemReg(anyEntryReg, offsetof(Runtime::Any, type), boxedTypeReg, MicroOpBits::B64);
                continue;
            }

            builder.emitLoadMemReg(anyEntryReg, offsetof(Runtime::Any, value), valuePtrReg, MicroOpBits::B64);

            const ConstantValue& typeInfoCst = codeGen.cstMgr().get(info.typeInfoCstRef);
            SWC_ASSERT(typeInfoCst.isValuePointer());

            const MicroReg typeInfoReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegPtrReloc(typeInfoReg, typeInfoCst.getValuePointer(), info.typeInfoCstRef);
            builder.emitLoadMemReg(anyEntryReg, offsetof(Runtime::Any, type), typeInfoReg, MicroOpBits::B64);
        }

        MicroReg sliceAddrReg = frameBaseReg;
        if (sliceOffset)
        {
            sliceAddrReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(sliceAddrReg, frameBaseReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(sliceAddrReg, ApInt(sliceOffset, 64), MicroOp::Add, MicroOpBits::B64);
        }

        builder.emitLoadMemReg(sliceAddrReg, offsetof(Runtime::Slice<std::byte>, ptr), anyBaseReg, MicroOpBits::B64);
        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(countReg, ApInt(variadicCount, 64), MicroOpBits::B64);
        builder.emitLoadMemReg(sliceAddrReg, offsetof(Runtime::Slice<std::byte>, count), countReg, MicroOpBits::B64);

        outPreparedArg.srcReg      = sliceAddrReg;
        outPreparedArg.kind        = ABICall::PreparedArgKind::Direct;
        outPreparedArg.isFloat     = normalizedVariadic.isFloat;
        outPreparedArg.isSigned    = normalizedVariadic.isSigned;
        outPreparedArg.numBits     = normalizedVariadic.numBits;
        outPreparedArg.isAddressed = false;
    }

    Result buildPreparedABIArguments(CodeGen& codeGen, AstNodeRef callRef, const SymbolFunction& calledFunction, MicroReg closureContextReg, std::span<const ResolvedCallArgument> args, SmallVector<ABICall::PreparedArg>& outArgs, uint32_t& outTransientStackSize)
    {
        // Convert resolved semantic arguments into ABI-prepared argument descriptors.
        outArgs.clear();
        outArgs.reserve(args.size() + (closureContextReg.isValid() ? 1u : 0u));
        outTransientStackSize                            = 0;
        const CallConvKind                  callConvKind = calledFunction.callConvKind();
        const CallConv&                     callConv     = CallConv::get(callConvKind);
        const std::vector<SymbolVariable*>& params       = calledFunction.parameters();
        const size_t                        numParams    = params.size();

        if (closureContextReg.isValid())
            outArgs.push_back({.srcReg = closureContextReg, .numBits = 64});

        bool    hasVariadic           = false;
        bool    hasTypedVariadic      = false;
        size_t  variadicParamIdx      = 0;
        TypeRef typedVariadicElemType = TypeRef::invalid();

        if (!params.empty())
        {
            const SymbolVariable* lastParam = params.back();
            SWC_ASSERT(lastParam != nullptr);

            const TypeInfo& lastParamType = codeGen.ctx().typeMgr().get(lastParam->typeRef());
            if (lastParamType.isTypedVariadic())
            {
                hasVariadic           = true;
                hasTypedVariadic      = true;
                variadicParamIdx      = numParams - 1;
                typedVariadicElemType = lastParamType.payloadTypeRef();
            }
            else if (lastParamType.isVariadic())
            {
                hasVariadic      = true;
                hasTypedVariadic = false;
                variadicParamIdx = numParams - 1;
            }
        }

        size_t argIndex   = 0;
        size_t paramIndex = 0;
        while (argIndex < args.size())
        {
            const ResolvedCallArgument& resolvedArg = args[argIndex];
            if (resolvedArg.passKind == CallArgumentPassKind::InterfaceObject)
            {
                // Interface dispatch prepends the runtime receiver object, but the selected
                // interface method symbol only exposes the explicit user parameters.
                SWC_RESULT(appendPreparedFixedArg(outArgs, codeGen, callRef, callConv, nullptr, resolvedArg, outTransientStackSize));
                ++argIndex;
                continue;
            }

            if (hasVariadic && paramIndex >= variadicParamIdx)
                break;

            const SymbolVariable* param = paramIndex < params.size() ? params[paramIndex] : nullptr;
            SWC_RESULT(appendPreparedFixedArg(outArgs, codeGen, callRef, callConv, param, resolvedArg, outTransientStackSize));
            ++argIndex;
            ++paramIndex;
        }

        if (!hasVariadic)
            return Result::Continue;

        ABICall::PreparedArg variadicPreparedArg;
        SWC_ASSERT(params[variadicParamIdx] != nullptr);
        const TypeRef                               variadicParamTypeRef = params[variadicParamIdx]->typeRef();
        const ABITypeNormalize::NormalizedType      normalizedVariadic   = ABITypeNormalize::normalize(codeGen.ctx(), callConv, variadicParamTypeRef, ABITypeNormalize::Usage::Argument);
        const std::span<const ResolvedCallArgument> variadicArgs         = args.subspan(argIndex);
        if (hasTypedVariadic)
            packTypedVariadicArgument(variadicPreparedArg, outTransientStackSize, codeGen, callConv, variadicArgs, typedVariadicElemType, normalizedVariadic);
        else
            packUntypedVariadicArgument(variadicPreparedArg, outTransientStackSize, codeGen, callConv, variadicArgs, normalizedVariadic);
        outArgs.push_back(variadicPreparedArg);
        return Result::Continue;
    }
}

void CodeGenCallHelpers::isolatePreparedRegisterArgSources(CodeGen& codeGen, const CallConv& callConv, SmallVector<ABICall::PreparedArg>& args)
{
    doIsolatePreparedRegisterArgSources(codeGen, callConv, args);
}

Result CodeGenCallHelpers::emitRuntimeCallWithDirectArgsToReg(CodeGen& codeGen, const SymbolFunction& runtimeFunction, std::span<const MicroReg> argRegs, MicroReg resultReg)
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

    isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);
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

Result CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(CodeGen& codeGen, const SymbolFunction& runtimeFunction, std::span<const MicroReg> argRegs)
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

    isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);
    MicroBuilder&               builder      = codeGen.builder();
    const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
    if (runtimeFunction.isForeign())
        ABICall::callExtern(builder, callConvKind, &runtimeFunction, preparedCall);
    else
        ABICall::callLocal(builder, callConvKind, &runtimeFunction, preparedCall);

    return Result::Continue;
}
Result CodeGenCallHelpers::codeGenCallExprCommon(CodeGen& codeGen, AstNodeRef calleeRef)
{
    MicroBuilder&      builder         = codeGen.builder();
    const SemaNodeView currentTypeView = codeGen.curViewType();
    SymbolFunction*    calledFunction  = nullptr;
    SWC_RESULT(resolveSelectedCallFunction(codeGen, calleeRef, calledFunction));
    SWC_ASSERT(calledFunction != nullptr);
    const CallConvKind callConvKind = calledFunction->callConvKind();
    const CallConv&    callConv     = CallConv::get(callConvKind);
    // ABI return lowering must follow the callee signature. The expression type can be a
    // transformed view of that result and is not a reliable source for hidden sret decisions.
    const ABITypeNormalize::NormalizedType normalizedRet     = ABITypeNormalize::normalize(codeGen.ctx(), callConv, calledFunction->returnTypeRef(), ABITypeNormalize::Usage::Return);
    const CodeGenNodePayload*              calleePayload     = resolveCallPayload(codeGen, calleeRef);
    MicroReg                               callTargetReg     = MicroReg::invalid();
    MicroReg                               closureContextReg = MicroReg::invalid();

    if (calleePayload)
        callTargetReg = materializeCallTargetReg(codeGen, *calleePayload, *calledFunction, callConv, closureContextReg);

    SmallVector<ResolvedCallArgument> args;
    SmallVector<ABICall::PreparedArg> preparedArgs;
    codeGen.appendResolvedCallArguments(codeGen.curNodeRef(), args);
    uint32_t transientStackSize = 0;
    SWC_RESULT(buildPreparedABIArguments(codeGen, codeGen.curNodeRef(), *calledFunction, closureContextReg, args, preparedArgs, transientStackSize));
    isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);
    MicroReg        hiddenRetStorageReg              = MicroReg::invalid();
    SymbolVariable* directVarInitStorageSym          = nullptr;
    bool            usesCurrentFunctionReturnStorage = false;
    if (normalizedRet.isIndirect)
    {
        // Reuse the destination variable storage for indirect direct-call results whenever possible.
        // Otherwise the ABI helper falls back to compiler-segment scratch storage, which the native
        // backend cannot serialize into object-file relocations.
        tryUseVarInitStorageForDirectCallResult(codeGen, codeGen.curNodeRef(), calledFunction->returnTypeRef(), hiddenRetStorageReg, directVarInitStorageSym);

        if (!hiddenRetStorageReg.isValid())
            usesCurrentFunctionReturnStorage = CodeGenFunctionHelpers::tryUseCurrentFunctionReturnStorageForDirectExpr(codeGen, codeGen.curNodeRef(), hiddenRetStorageReg);

        const CodeGenNodePayload* nodePayload = codeGen.safePayload(codeGen.curNodeRef());
        if (!hiddenRetStorageReg.isValid() &&
            nodePayload &&
            nodePayload->runtimeStorageSym != nullptr &&
            ((nodePayload->runtimeStorageSym->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) && codeGen.localStackBaseReg().isValid()) ||
             CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, *nodePayload->runtimeStorageSym)))
            hiddenRetStorageReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
    }

    // prepareArgs handles register placement, stack slots, and hidden indirect return arg.
    const ABICall::PreparedCall preparedCall       = ABICall::prepareArgs(builder, callConvKind, preparedArgs, normalizedRet, hiddenRetStorageReg);
    TypeRef                     nodePayloadTypeRef = calledFunction->returnTypeRef();
    if (!nodePayloadTypeRef.isValid())
        nodePayloadTypeRef = currentTypeView.typeRef();
    CodeGenNodePayload& nodePayload = codeGen.setPayload(codeGen.curNodeRef(), nodePayloadTypeRef);
    if (!normalizedRet.isVoid)
        nodePayload.reg = normalizedRet.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
    if (directVarInitStorageSym)
        nodePayload.setRuntimeStorageSymbol(directVarInitStorageSym);
    else if (usesCurrentFunctionReturnStorage)
        nodePayload.setRuntimeStorageSymbol(nullptr);
    emitFunctionCall(codeGen, *calledFunction, preparedCall, callTargetReg);
    if (transientStackSize)
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(transientStackSize, 64), MicroOp::Add, MicroOpBits::B64);

    ABICall::materializeReturnToReg(builder, nodePayload.reg, callConvKind, normalizedRet);
    setPayloadStorageKind(nodePayload, normalizedRet.isIndirect);
    if (calledFunction->isThrowable())
        SWC_RESULT(emitThrowableFailureJumpIfHasError(codeGen));

    return Result::Continue;
}

Result CodeGenCallHelpers::emitCallWithResolvedArgsToReg(CodeGen& codeGen, AstNodeRef callRef, const SymbolFunction& calledFunction, std::span<const ResolvedCallArgument> args, MicroReg resultReg)
{
    codeGen.function().addCallDependency(&calledFunction);

    const CallConvKind                     callConvKind  = calledFunction.callConvKind();
    const CallConv&                        callConv      = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, calledFunction.returnTypeRef(), ABITypeNormalize::Usage::Return);
    SWC_ASSERT(!normalizedRet.isVoid);
    SWC_ASSERT(!normalizedRet.isIndirect);

    SmallVector<ABICall::PreparedArg> preparedArgs;
    uint32_t                          transientStackSize = 0;
    SWC_RESULT(buildPreparedABIArguments(codeGen, callRef, calledFunction, MicroReg::invalid(), args, preparedArgs, transientStackSize));
    isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);

    MicroBuilder&               builder      = codeGen.builder();
    const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
    if (calledFunction.isForeign())
        ABICall::callExtern(builder, callConvKind, &calledFunction, preparedCall);
    else
        ABICall::callLocal(builder, callConvKind, &calledFunction, preparedCall);

    if (transientStackSize)
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(transientStackSize, 64), MicroOp::Add, MicroOpBits::B64);

    ABICall::materializeReturnToReg(builder, resultReg, callConvKind, normalizedRet);
    return Result::Continue;
}

Result CodeGenCallHelpers::emitCallWithResolvedArgs(CodeGen& codeGen, AstNodeRef callRef, const SymbolFunction& calledFunction, std::span<const ResolvedCallArgument> args)
{
    codeGen.function().addCallDependency(&calledFunction);

    const CallConvKind                     callConvKind  = calledFunction.callConvKind();
    const CallConv&                        callConv      = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, calledFunction.returnTypeRef(), ABITypeNormalize::Usage::Return);
    SWC_ASSERT(normalizedRet.isVoid);

    SmallVector<ABICall::PreparedArg> preparedArgs;
    uint32_t                          transientStackSize = 0;
    SWC_RESULT(buildPreparedABIArguments(codeGen, callRef, calledFunction, MicroReg::invalid(), args, preparedArgs, transientStackSize));
    isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);

    MicroBuilder&               builder      = codeGen.builder();
    const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
    if (calledFunction.isForeign())
        ABICall::callExtern(builder, callConvKind, &calledFunction, preparedCall);
    else
        ABICall::callLocal(builder, callConvKind, &calledFunction, preparedCall);

    if (transientStackSize)
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(transientStackSize, 64), MicroOp::Add, MicroOpBits::B64);

    return Result::Continue;
}
SWC_END_NAMESPACE();
