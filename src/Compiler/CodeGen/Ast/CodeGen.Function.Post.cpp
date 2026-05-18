#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    SymbolFunction* recoverFunctionExprSymbolFromDependencies(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid())
            return nullptr;

        const AstNode&               node = codeGen.node(nodeRef);
        SmallVector<SymbolFunction*> deps;
        codeGen.function().appendCallDependencies(deps);
        for (SymbolFunction* dep : deps)
        {
            SWC_ASSERT(dep != nullptr);
            if (dep->declNodeRef().isInvalid())
                continue;

            // Nested function expressions can be lowered before the symbol view is rebound, so recover the
            // callee by matching the declaration source location recorded in the dependency list.
            if (dep->srcViewRef() != node.srcViewRef())
                continue;
            if (dep->tokRef() != node.tokRef())
                continue;
            return dep;
        }

        return nullptr;
    }

    SymbolFunction& functionExprSymbol(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (Symbol* sym = codeGen.sema().viewStored(nodeRef, SemaNodeViewPartE::Symbol).sym())
            return sym->cast<SymbolFunction>();

        if (Symbol* sym = codeGen.viewSymbol(nodeRef).sym())
            return sym->cast<SymbolFunction>();

        if (auto* dep = recoverFunctionExprSymbolFromDependencies(codeGen, nodeRef))
            return *dep;

        const TypeRef typeRef = codeGen.viewType(nodeRef).typeRef();
        SWC_ASSERT(typeRef.isValid());
        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        SWC_ASSERT(typeInfo.isFunction());
        return typeInfo.payloadSymFunction();
    }

    enum class ThrowableHandlerKind : uint8_t
    {
        None,
        Catch,
        TryCatch,
        Assume,
    };

    struct ThrowableTarget
    {
        enum class Kind : uint8_t
        {
            Handler,
            FunctionReturn,
        };

        Kind          kind      = Kind::FunctionReturn;
        AstNodeRef    scopeRef  = AstNodeRef::invalid();
        MicroLabelRef failLabel = MicroLabelRef::invalid();
    };

    bool isThrowableWrapperOwnerNode(AstNodeId nodeId)
    {
        return nodeId == AstNodeId::TryCatchExpr || nodeId == AstNodeId::TryCatchStmt;
    }

    bool isThrowableWrapperBreadcrumbNode(AstNodeId nodeId)
    {
        return isThrowableWrapperOwnerNode(nodeId) || nodeId == AstNodeId::CallExpr || nodeId == AstNodeId::AliasCallExpr;
    }

    CodeGenNodePayload* throwableWrapperOwnerPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid())
            return nullptr;

        const AstNodeRef resolvedNodeRef = codeGen.viewZero(nodeRef).nodeRef();
        if (!resolvedNodeRef.isValid())
            return nullptr;

        if (!isThrowableWrapperOwnerNode(codeGen.node(resolvedNodeRef).id()))
            return nullptr;

        CodeGenNodePayload* payload = codeGen.safePayload(resolvedNodeRef);
        if (!payload || !payload->hasThrowableWrapper())
            return nullptr;
        return payload;
    }

    CodeGenNodePayload* throwableWrapperBreadcrumbPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid())
            return nullptr;

        const AstNodeRef resolvedNodeRef = codeGen.viewZero(nodeRef).nodeRef();
        if (!resolvedNodeRef.isValid())
            return nullptr;

        if (!isThrowableWrapperBreadcrumbNode(codeGen.node(resolvedNodeRef).id()))
            return nullptr;

        CodeGenNodePayload* payload = codeGen.safePayload(nodeRef);
        if (!payload || !payload->hasThrowableWrapper())
            return nullptr;
        return payload;
    }

    void clearThrowableWrapperPayload(CodeGenNodePayload& payload)
    {
        payload.clearThrowableWrapper();
    }

    CodeGenNodePayload* throwableFunctionPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safePayload(nodeRef);
    }

    CodeGenNodePayload& ensureThrowableFunctionPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.ensureNodePayload<CodeGenNodePayload>(nodeRef);
    }

    SymbolFunction* runtimeFunctionByKind(CodeGen& codeGen, IdentifierManager::RuntimeFunctionKind kind)
    {
        const IdentifierRef idRef = codeGen.idMgr().runtimeFunction(kind);
        if (idRef.isInvalid())
            return nullptr;

        return codeGen.compiler().runtimeFunctionSymbol(idRef);
    }

    ThrowableHandlerKind throwableHandlerKind(TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::KwdCatch:
                return ThrowableHandlerKind::Catch;

            case TokenId::KwdTryCatch:
                return ThrowableHandlerKind::TryCatch;

            case TokenId::KwdAssume:
                return ThrowableHandlerKind::Assume;

            default:
                return ThrowableHandlerKind::None;
        }
    }

    bool isHandledThrowableContext(TokenId tokenId)
    {
        return throwableHandlerKind(tokenId) != ThrowableHandlerKind::None;
    }

    bool tryResolveThrowableHandlerTarget(CodeGen& codeGen, AstNodeRef candidateRef, ThrowableTarget& outTarget)
    {
        const CodeGenNodePayload* breadcrumbPayload = throwableWrapperBreadcrumbPayload(codeGen, candidateRef);
        if (!breadcrumbPayload || !isHandledThrowableContext(breadcrumbPayload->throwableWrapperTokenId))
            return false;

        AstNodeRef ownerRef = breadcrumbPayload->throwableWrapperOwnerRef;
        if (!ownerRef.isValid())
            ownerRef = codeGen.viewZero(candidateRef).nodeRef();

        const CodeGenNodePayload* ownerPayload = throwableWrapperOwnerPayload(codeGen, ownerRef);
        if (!ownerPayload || !ownerPayload->throwableFailLabel.isValid())
            return false;

        outTarget = {
            .kind      = ThrowableTarget::Kind::Handler,
            .scopeRef  = codeGen.viewZero(ownerRef).nodeRef(),
            .failLabel = ownerPayload->throwableFailLabel,
        };
        return true;
    }

    MicroOpBits scalarStoreBitsForTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return MicroOpBits::Zero;

        const TypeInfo& typeInfo       = codeGen.typeMgr().get(typeRef);
        const TypeRef   storageTypeRef = typeInfo.unwrapAliasEnum(codeGen.ctx(), typeRef);
        const TypeRef   scalarTypeRef  = storageTypeRef.isValid() ? storageTypeRef : typeRef;
        return CodeGenTypeHelpers::scalarStoreBits(codeGen.typeMgr().get(scalarTypeRef), codeGen.ctx());
    }

    bool isEnumOrAliasEnum(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        if (typeInfo.isEnum())
            return true;
        if (!typeInfo.isAlias())
            return false;

        const TypeRef unwrappedTypeRef = typeInfo.unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
        return unwrappedTypeRef.isValid() && codeGen.typeMgr().get(unwrappedTypeRef).isEnum();
    }

    bool usesAddressBackedThrowableExprResult(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid() || typeRef == codeGen.typeMgr().typeVoid())
            return false;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        const uint64_t  sizeOf   = typeInfo.sizeOf(codeGen.ctx());
        if (sizeOf > sizeof(uint64_t))
            return true;

        return scalarStoreBitsForTypeRef(codeGen, typeRef) == MicroOpBits::Zero;
    }

    bool hasAssumeRuntimeSafety(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        const AstNodeRef resolvedNodeRef = codeGen.viewZero(nodeRef).nodeRef();
        if (!resolvedNodeRef.isValid())
            return false;

        const auto* payload = codeGen.loweringPayload(resolvedNodeRef);
        return payload && payload->hasRuntimeSafety(Runtime::SafetyWhat::Assume);
    }

    AstNodeRef resolveCodeGenErrorNodeRef(CodeGen& codeGen, AstNodeRef preferredNodeRef)
    {
        if (preferredNodeRef.isValid())
        {
            preferredNodeRef = codeGen.viewZero(preferredNodeRef).nodeRef();
            if (preferredNodeRef.isValid())
                return preferredNodeRef;
        }

        const AstNodeRef currentNodeRef = codeGen.viewZero(codeGen.curNodeRef()).nodeRef();
        if (currentNodeRef.isValid())
            return currentNodeRef;

        const AstNodeRef functionDeclRef = codeGen.viewZero(codeGen.function().declNodeRef()).nodeRef();
        SWC_ASSERT(functionDeclRef.isValid());
        return functionDeclRef;
    }

    Result raiseInternalCodeGenError(CodeGen& codeGen, std::string_view because, AstNodeRef nodeRef = AstNodeRef::invalid(), SemaError::ReportLocation location = SemaError::ReportLocation::Token)
    {
        SWC_ASSERT(!because.empty());

        const AstNodeRef errorNodeRef = resolveCodeGenErrorNodeRef(codeGen, nodeRef);
        SWC_ASSERT(errorNodeRef.isValid());

        auto diag = SemaError::report(codeGen.sema(), DiagnosticId::misc_err_internal_codegen_failure, errorNodeRef, location);
        diag.addArgument(Diagnostic::ARG_WHAT, codeGen.function().getFullScopedName(codeGen.ctx()));
        diag.addArgument(Diagnostic::ARG_BECAUSE, because);
        diag.report(codeGen.ctx());
        return Result::Error;
    }

    Result emitRuntimeHelperCallWithNoArgs(CodeGen& codeGen, IdentifierManager::RuntimeFunctionKind kind, std::string_view missingHelperName, AstNodeRef nodeRef)
    {
        const SymbolFunction* runtimeFn = runtimeFunctionByKind(codeGen, kind);
        SWC_ASSERT(runtimeFn != nullptr);
        if (!runtimeFn)
            return raiseInternalCodeGenError(codeGen, missingHelperName, nodeRef);

        return CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *runtimeFn, std::span<const MicroReg>{});
    }

    Result emitFailedAssumeRuntimeCall(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        SymbolFunction* runtimeFailedAssume = runtimeFunctionByKind(codeGen, IdentifierManager::RuntimeFunctionKind::FailedAssume);
        SWC_ASSERT(runtimeFailedAssume != nullptr);
        if (!runtimeFailedAssume)
            return raiseInternalCodeGenError(codeGen, "missing runtime helper '__failedAssume'", nodeRef);

        ConstantRef sourceLocCstRef = ConstantRef::invalid();
        SWC_RESULT(ConstantHelpers::makeSourceCodeLocation(codeGen.sema(), sourceLocCstRef, codeGen.node(nodeRef)));

        CodeGenNodePayload sourceLocPayload;
        const TypeRef      sourceLocTypeRef = runtimeFailedAssume->parameters().front()->typeRef();
        if (!CodeGenCallHelpers::materializeTypedConstantPayload(codeGen, sourceLocPayload, sourceLocTypeRef, sourceLocCstRef))
            return raiseInternalCodeGenError(codeGen, "failed to materialize the failed-assume source location payload", nodeRef);

        const std::array args = {sourceLocPayload.reg};
        return CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *runtimeFailedAssume, args);
    }

    Result emitPayloadToAddress(CodeGen& codeGen, MicroReg dstAddressReg, const CodeGenNodePayload& srcPayload, TypeRef typeRef);

    void assignThrowableExprResult(CodeGen& codeGen, const CodeGenNodePayload& dstPayload, const CodeGenNodePayload& srcPayload, TypeRef typeRef)
    {
        MicroBuilder& builder = codeGen.builder();
        if (dstPayload.isAddress())
        {
            const Result storeResult = emitPayloadToAddress(codeGen, dstPayload.reg, srcPayload, typeRef);
            SWC_INTERNAL_CHECK(storeResult == Result::Continue);
            return;
        }

        const TypeInfo& typeInfo  = codeGen.typeMgr().get(typeRef);
        MicroOpBits     storeBits = scalarStoreBitsForTypeRef(codeGen, typeRef);
        if (storeBits == MicroOpBits::Zero)
            storeBits = CodeGenTypeHelpers::bitsFromStorageSize(typeInfo.sizeOf(codeGen.ctx()));
        SWC_ASSERT(storeBits != MicroOpBits::Zero);
        if (srcPayload.isAddress())
            builder.emitLoadRegMem(dstPayload.reg, srcPayload.reg, 0, storeBits);
        else
            builder.emitLoadRegReg(dstPayload.reg, srcPayload.reg, storeBits);
    }

    Result makeZeroConstantRefForType(CodeGen& codeGen, ConstantRef& outCstRef, TypeRef typeRef)
    {
        outCstRef = ConstantRef::invalid();
        if (!typeRef.isValid() || typeRef == codeGen.typeMgr().typeVoid())
            return Result::Continue;

        TaskContext&    ctx            = codeGen.ctx();
        const TypeInfo& originalType   = codeGen.typeMgr().get(typeRef);
        TypeRef         storageTypeRef = originalType.unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (storageTypeRef.isInvalid())
            storageTypeRef = typeRef;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(storageTypeRef);
        const uint64_t  sizeOf   = typeInfo.sizeOf(codeGen.ctx());
        SWC_ASSERT(sizeOf && sizeOf <= std::numeric_limits<uint32_t>::max());
        if (!sizeOf || sizeOf > std::numeric_limits<uint32_t>::max())
            return raiseInternalCodeGenError(codeGen, "invalid zero constant storage size");

        SmallVector<std::byte> rawBytes;
        rawBytes.resize(sizeOf);
        std::memset(rawBytes.data(), 0, rawBytes.size());

        ConstantValue zeroValue;
        if (typeInfo.isStruct() || typeInfo.isAny() || typeInfo.isInterface())
            zeroValue = ConstantValue::makeStructBorrowed(ctx, storageTypeRef, ByteSpan{rawBytes.data(), rawBytes.size()});
        else if (typeInfo.isArray())
            zeroValue = ConstantValue::makeArrayBorrowed(ctx, storageTypeRef, ByteSpan{rawBytes.data(), rawBytes.size()});
        else
            zeroValue = ConstantValue::make(ctx, rawBytes.data(), storageTypeRef, ConstantValue::PayloadOwnership::Borrowed);
        if (zeroValue.kind() == ConstantKind::Invalid)
            return raiseInternalCodeGenError(codeGen, "failed to materialize the synthesized zero constant");

        if (isEnumOrAliasEnum(codeGen, typeRef))
        {
            const ConstantRef storageCstRef = codeGen.cstMgr().addConstant(ctx, zeroValue);
            if (storageCstRef.isInvalid())
                return raiseInternalCodeGenError(codeGen, "failed to cache the synthesized enum zero constant");

            zeroValue = ConstantValue::makeEnumValue(ctx, storageCstRef, typeRef);
        }
        else
        {
            zeroValue.setTypeRef(typeRef);
        }

        outCstRef = codeGen.cstMgr().addConstant(ctx, zeroValue);
        if (!outCstRef.isValid())
            return raiseInternalCodeGenError(codeGen, "failed to cache the synthesized zero constant");
        return Result::Continue;
    }

    Result emitZeroThrowableExprResult(CodeGen& codeGen, const CodeGenNodePayload& resultPayload, TypeRef typeRef)
    {
        if (!typeRef.isValid() || typeRef == codeGen.typeMgr().typeVoid())
            return Result::Continue;

        ConstantRef zeroCstRef = ConstantRef::invalid();
        SWC_RESULT(makeZeroConstantRefForType(codeGen, zeroCstRef, typeRef));

        CodeGenNodePayload zeroPayload;
        if (!CodeGenCallHelpers::materializeTypedConstantPayload(codeGen, zeroPayload, typeRef, zeroCstRef))
            return raiseInternalCodeGenError(codeGen, "failed to materialize the synthesized zero throwable result payload");

        assignThrowableExprResult(codeGen, resultPayload, zeroPayload, typeRef);
        return Result::Continue;
    }

    Result emitPayloadToAddress(CodeGen& codeGen, MicroReg dstAddressReg, const CodeGenNodePayload& srcPayload, TypeRef typeRef)
    {
        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        const uint32_t  sizeOf   = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, typeInfo);
        if (srcPayload.isAddress())
        {
            CodeGenMemoryHelpers::emitMemCopy(codeGen, dstAddressReg, srcPayload.reg, sizeOf);
            return Result::Continue;
        }

        const MicroOpBits storeBits = scalarStoreBitsForTypeRef(codeGen, typeRef);
        if (storeBits != MicroOpBits::Zero)
        {
            codeGen.builder().emitLoadMemReg(dstAddressReg, 0, srcPayload.reg, storeBits);
            return Result::Continue;
        }

        CodeGenMemoryHelpers::emitMemCopy(codeGen, dstAddressReg, srcPayload.reg, sizeOf);
        return Result::Continue;
    }

    Result emitThrowableCleanup(CodeGen& codeGen, ThrowableHandlerKind kind, AstNodeRef nodeRef, bool failurePath)
    {
        switch (kind)
        {
            case ThrowableHandlerKind::Catch:
                return emitRuntimeHelperCallWithNoArgs(codeGen, IdentifierManager::RuntimeFunctionKind::CatchErr, "missing runtime helper '__catchErr'", nodeRef);

            case ThrowableHandlerKind::TryCatch:
                return emitRuntimeHelperCallWithNoArgs(codeGen, IdentifierManager::RuntimeFunctionKind::PopErr, "missing runtime helper '__popErr'", nodeRef);

            case ThrowableHandlerKind::Assume:
            {
                if (failurePath && hasAssumeRuntimeSafety(codeGen, nodeRef))
                    SWC_RESULT(emitFailedAssumeRuntimeCall(codeGen, nodeRef));

                return emitRuntimeHelperCallWithNoArgs(codeGen, IdentifierManager::RuntimeFunctionKind::PopErr, "missing runtime helper '__popErr'", nodeRef);
            }

            case ThrowableHandlerKind::None:
                break;
        }

        return Result::Continue;
    }

    void emitLocalStackFrameEpilogue(CodeGen& codeGen, CallConvKind callConvKind)
    {
        if (!codeGen.hasLocalStackFrame())
            return;

        const CallConv& callConv = CallConv::get(callConvKind);
        MicroBuilder&   builder  = codeGen.builder();
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(codeGen.localStackFrameSize(), 64), MicroOp::Add, MicroOpBits::B64);
    }

    MicroReg inlineResultAddressReg(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        SWC_ASSERT(symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
        SWC_ASSERT(codeGen.localStackBaseReg().isValid());
        return codeGen.offsetAddressReg(codeGen.localStackBaseReg(), symVar.offset());
    }

    Result emitInlineResultStore(CodeGen& codeGen, const SemaInlinePayload& inlinePayload, AstNodeRef exprRef)
    {
        SWC_ASSERT(inlinePayload.resultVar != nullptr);
        SWC_ASSERT(exprRef.isValid());

        const SymbolVariable& resultVar  = *inlinePayload.resultVar;
        const MicroReg        resultAddr = inlineResultAddressReg(codeGen, resultVar);

        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        return emitPayloadToAddress(codeGen, resultAddr, exprPayload, inlinePayload.returnTypeRef);
    }

    Result emitInlineReturn(CodeGen& codeGen, const SemaInlinePayload& inlinePayload, AstNodeRef exprRef)
    {
        if (inlinePayload.returnTypeRef != codeGen.typeMgr().typeVoid())
        {
            SWC_ASSERT(exprRef.isValid());
            SWC_RESULT(emitInlineResultStore(codeGen, inlinePayload, exprRef));
        }

        SWC_RESULT(codeGen.emitDeferredActionsUntilScopeRef(inlinePayload.inlineRootRef));

        CodeGenFrame& frame     = codeGen.frame();
        MicroLabelRef doneLabel = frame.currentInlineContext().doneLabel;
        if (doneLabel == MicroLabelRef::invalid())
        {
            doneLabel = codeGen.builder().createLabel();
            frame.setCurrentInlineDoneLabel(doneLabel);
        }

        MicroBuilder& builder = codeGen.builder();
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
        return Result::Continue;
    }

    const SymbolVariable* resolveCanonicalParameter(const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
    {
        if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            return nullptr;

        const auto& params = symbolFunc.parameters();
        if (symVar.hasParameterIndex() && symVar.parameterIndex() < params.size())
        {
            const SymbolVariable* canonicalParam = params[symVar.parameterIndex()];
            if (canonicalParam && canonicalParam != &symVar)
                return canonicalParam;
        }

        if (!symVar.idRef().isValid())
            return nullptr;

        for (const SymbolVariable* param : params)
        {
            if (!param || param == &symVar)
                continue;
            if (param->idRef() == symVar.idRef())
                return param;
        }

        return nullptr;
    }

    CodeGenNodePayload resolveClosureCaptureSourcePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (symVar.isClosureCapture())
            return CodeGenFunctionHelpers::resolveClosureCapturePayload(codeGen, symVar);

        if (const SymbolVariable* canonicalParam = resolveCanonicalParameter(codeGen.function(), symVar))
            return resolveClosureCaptureSourcePayload(codeGen, *canonicalParam);

        if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar))
            return CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, symVar);

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            if (symVar.hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage) &&
                symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            {
                const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar);
                if (symbolPayload && symbolPayload->isAddress())
                    return *symbolPayload;
                return codeGen.resolveLocalStackPayload(symVar);
            }

            if (const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar))
                return *symbolPayload;

            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }

        if (const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar))
            return *symbolPayload;

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            return codeGen.resolveLocalStackPayload(symVar);
        if (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
            return codeGen.resolveLocalStackPayload(symVar);

        if (symVar.hasGlobalStorage())
        {
            CodeGenNodePayload globalPayload;
            globalPayload.typeRef = symVar.typeRef();
            globalPayload.setIsAddress();
            globalPayload.reg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegDataSegmentReloc(globalPayload.reg, symVar.globalStorageKind(), symVar.offset());
            return globalPayload;
        }

        SWC_UNREACHABLE();
    }

    void emitClosureCaptureStore(CodeGen& codeGen, const SymbolVariable& captureVar, MicroReg closureValueReg)
    {
        const CodeGenNodePayload* sourcePayload = nullptr;
        if (const auto* captureArg = captureVar.decl() ? captureVar.decl()->safeCast<AstClosureArgument>() : nullptr)
        {
            const CodeGenNodePayload* capturePayload = codeGen.safePayload(captureArg->nodeIdentifierRef);
            if (capturePayload && capturePayload->reg.isValid())
                sourcePayload = capturePayload;
        }

        CodeGenNodePayload resolvedSourcePayload;
        if (!sourcePayload)
        {
            const SymbolVariable* sourceVar = captureVar.closureCapturedSource();
            SWC_ASSERT(sourceVar != nullptr);
            resolvedSourcePayload = resolveClosureCaptureSourcePayload(codeGen, *sourceVar);
            sourcePayload         = &resolvedSourcePayload;
        }

        const TypeInfo& typeInfo      = codeGen.typeMgr().get(captureVar.typeRef());
        const uint32_t  captureOffset = offsetof(Runtime::ClosureValue, capture) + captureVar.closureCaptureOffset();
        const MicroReg  captureDstReg = codeGen.offsetAddressReg(closureValueReg, captureOffset);
        if (typeInfo.isAnyVariadic())
        {
            MicroReg sourceReg = sourcePayload->reg;
            if (sourcePayload->isAddress())
            {
                sourceReg = codeGen.nextVirtualIntRegister();
                codeGen.builder().emitLoadRegMem(sourceReg, sourcePayload->reg, 0, MicroOpBits::B64);
            }

            codeGen.builder().emitLoadMemReg(captureDstReg, 0, sourceReg, MicroOpBits::B64);
            return;
        }

        if (captureVar.closureCaptureByRef())
        {
            SWC_ASSERT(sourcePayload->isAddress());
            codeGen.builder().emitLoadMemReg(captureDstReg, 0, sourcePayload->reg, MicroOpBits::B64);
            return;
        }

        const uint32_t copySize = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, typeInfo);
        if (sourcePayload->isAddress())
        {
            CodeGenMemoryHelpers::emitMemCopy(codeGen, captureDstReg, sourcePayload->reg, copySize);
            return;
        }

        const MicroOpBits storeBits = microOpBitsFromChunkSize(copySize);
        SWC_ASSERT(storeBits != MicroOpBits::Zero);
        codeGen.builder().emitLoadMemReg(captureDstReg, 0, sourcePayload->reg, storeBits);
    }

    bool hasRuntimeStoragePayload(const CodeGen& codeGen, AstNodeRef nodeRef)
    {
        const auto* payload = codeGen.loweringPayload(nodeRef);
        return payload && payload->runtimeStorageSym != nullptr;
    }

    AstNodeRef resolveClosureExprStorageNodeRef(const CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (hasRuntimeStoragePayload(codeGen, nodeRef))
            return nodeRef;

        const AstNodeRef currentNodeRef = codeGen.curNodeRef();
        SWC_ASSERT(currentNodeRef.isValid());
        SWC_ASSERT(currentNodeRef != nodeRef);
        SWC_ASSERT(hasRuntimeStoragePayload(codeGen, currentNodeRef));
        return currentNodeRef;
    }

    Result emitClosureExprValue(CodeGen& codeGen, AstNodeRef nodeRef, const SymbolFunction& symFunc, TypeRef typeRef)
    {
        const AstNodeRef storageNodeRef = resolveClosureExprStorageNodeRef(codeGen, nodeRef);
        MicroBuilder&    builder        = codeGen.builder();
        MicroReg         dstReg         = MicroReg::invalid();
        if (!CodeGenFunctionHelpers::tryUseCurrentFunctionReturnStorageForDirectExpr(codeGen, storageNodeRef, dstReg))
            dstReg = codeGen.runtimeStorageAddressReg(storageNodeRef);
        constexpr auto dstSize = static_cast<uint32_t>(sizeof(Runtime::ClosureValue));
        CodeGenMemoryHelpers::emitMemZero(codeGen, dstReg, dstSize);

        const MicroReg invokeReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegPtrReloc(invokeReg, 0, ConstantRef::invalid(), &symFunc);
        builder.emitLoadMemReg(dstReg, offsetof(Runtime::ClosureValue, invoke), invokeReg, MicroOpBits::B64);

        std::vector<const Symbol*> symbols;
        symFunc.getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            const auto* captureVar = symbol ? symbol->safeCast<SymbolVariable>() : nullptr;
            if (!captureVar || !captureVar->isClosureCapture())
                continue;
            emitClosureCaptureStore(codeGen, *captureVar, dstReg);
        }

        codeGen.function().addCallDependency(&symFunc);
        codeGen.setPayloadAddressReg(nodeRef, dstReg, typeRef);
        if (storageNodeRef != nodeRef)
            codeGen.setPayloadAddressReg(storageNodeRef, dstReg, typeRef);
        return Result::Continue;
    }

    bool shouldDelayReturnMaterializationForDeferredActions(CodeGen& codeGen, AstNodeRef exprRef, const CodeGenNodePayload& exprPayload)
    {
        if (exprPayload.runtimeStorageSym && exprPayload.runtimeStorageSym->hasExtraFlag(SymbolVariableFlagsE::RetVal))
            return true;

        if (exprRef.isInvalid())
            return false;

        const SemaNodeView symbolView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Symbol);
        if (symbolView.sym() && symbolView.sym()->isVariable() && symbolView.sym()->cast<SymbolVariable>().hasExtraFlag(SymbolVariableFlagsE::RetVal))
            return true;

        return false;
    }

    void emitIndirectReturnValuePayload(CodeGen& codeGen, MicroReg outputStorageReg, MicroReg valueReg, uint32_t copySize)
    {
        SWC_ASSERT(copySize > 0);

        auto copyBits = MicroOpBits::Zero;
        if (copySize == 1 || copySize == 2 || copySize == 4 || copySize == 8)
            copyBits = microOpBitsFromChunkSize(copySize);

        if (copyBits != MicroOpBits::Zero)
            codeGen.builder().emitLoadMemReg(outputStorageReg, 0, valueReg, copyBits);
        else
            CodeGenMemoryHelpers::emitMemCopy(codeGen, outputStorageReg, valueReg, copySize);
    }

    Result emitPostCopyAfterIndirectReturnCopy(CodeGen& codeGen, TypeRef returnTypeRef, const CodeGenNodePayload& exprPayload, MicroReg outputStorageReg)
    {
        if (!exprPayload.isAddress() || exprPayload.reg == outputStorageReg)
            return Result::Continue;
        if (!codeGen.hasLifecycle(returnTypeRef, CodeGen::LifecycleKind::PostCopy))
            return Result::Continue;
        return codeGen.emitLifecycle(returnTypeRef, CodeGen::LifecycleKind::PostCopy, outputStorageReg);
    }

    bool isCompilerFunctionDecl(CodeGen& codeGen);

    Result emitFunctionReturn(CodeGen& codeGen, const SymbolFunction& symbolFunc, AstNodeRef exprRef)
    {
        MicroBuilder&                          builder                       = codeGen.builder();
        const CallConvKind                     callConvKind                  = symbolFunc.callConvKind();
        const CallConv&                        callConv                      = CallConv::get(callConvKind);
        const TypeRef                          returnTypeRef                 = symbolFunc.returnTypeRef();
        const ABITypeNormalize::NormalizedType normalizedRet                 = ABITypeNormalize::normalize(codeGen.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
        const bool                             needsPersistentCompilerReturn = isCompilerFunctionDecl(codeGen) && CodeGenFunctionHelpers::needsPersistentCompilerRunReturn(codeGen.sema(), returnTypeRef);

        if (normalizedRet.isVoid)
        {
            // Void returns only need control transfer; ABI return registers are irrelevant.
            SWC_RESULT(codeGen.emitDeferredActionsForReturn());
            const ScopedDebugNoStep noStep(builder, true);
            emitLocalStackFrameEpilogue(codeGen, callConvKind);
            builder.emitRet();
            return Result::Continue;
        }

        SWC_ASSERT(exprRef.isValid());

        const CodeGenNodePayload& exprPayload                = codeGen.payload(exprRef);
        const bool                delayReturnMaterialization = shouldDelayReturnMaterializationForDeferredActions(codeGen, exprRef, exprPayload);
        if (normalizedRet.isIndirect)
        {
            // Hidden first argument points to caller-provided return storage.
            const MicroReg outputStorageReg = codeGen.ensureCurrentFunctionIndirectReturnReg(callConvKind);
            if (!delayReturnMaterialization && needsPersistentCompilerReturn)
            {
                CodeGenFunctionHelpers::emitPersistCompilerRunValue(codeGen, returnTypeRef, outputStorageReg, exprPayload.reg, codeGen.localStackBaseReg(), codeGen.localStackFrameSize());
            }
            else if (!delayReturnMaterialization && exprPayload.isAddress())
            {
                if (exprPayload.reg != outputStorageReg)
                {
                    CodeGenMemoryHelpers::emitMemCopy(codeGen, outputStorageReg, exprPayload.reg, normalizedRet.indirectSize);
                    SWC_RESULT(emitPostCopyAfterIndirectReturnCopy(codeGen, returnTypeRef, exprPayload, outputStorageReg));
                }
            }
            else if (!delayReturnMaterialization)
            {
                emitIndirectReturnValuePayload(codeGen, outputStorageReg, exprPayload.reg, normalizedRet.indirectSize);
                SWC_RESULT(emitPostCopyAfterIndirectReturnCopy(codeGen, returnTypeRef, exprPayload, outputStorageReg));
            }

            SWC_RESULT(codeGen.emitDeferredActionsForReturn());
            if (delayReturnMaterialization && needsPersistentCompilerReturn)
                CodeGenFunctionHelpers::emitPersistCompilerRunValue(codeGen, returnTypeRef, outputStorageReg, exprPayload.reg, codeGen.localStackBaseReg(), codeGen.localStackFrameSize());
            else if (delayReturnMaterialization && exprPayload.isAddress() && exprPayload.reg != outputStorageReg)
            {
                CodeGenMemoryHelpers::emitMemCopy(codeGen, outputStorageReg, exprPayload.reg, normalizedRet.indirectSize);
                SWC_RESULT(emitPostCopyAfterIndirectReturnCopy(codeGen, returnTypeRef, exprPayload, outputStorageReg));
            }
            builder.emitLoadRegReg(callConv.intReturn, outputStorageReg, MicroOpBits::B64);
        }
        else
        {
            // Direct returns are normalized to ABI return registers (int/float lane).
            const TypeInfo& returnTypeInfo = codeGen.ctx().typeMgr().get(returnTypeRef);
            SWC_ASSERT(!CodeGenFunctionHelpers::shouldMaterializeAddressBackedValue(codeGen, returnTypeInfo, normalizedRet.isIndirect, normalizedRet.isFloat, normalizedRet.numBits));

            const MicroOpBits retBits = normalizedRet.numBits ? microOpBitsFromBitWidth(normalizedRet.numBits) : MicroOpBits::B64;
            SWC_ASSERT(retBits != MicroOpBits::Zero);

            const MicroReg returnValueReg = codeGen.nextVirtualRegisterForType(returnTypeRef);
            if (!delayReturnMaterialization)
            {
                if (exprPayload.isAddress())
                    builder.emitLoadRegMem(returnValueReg, exprPayload.reg, 0, retBits);
                else
                    builder.emitLoadRegReg(returnValueReg, exprPayload.reg, retBits);
            }

            SWC_RESULT(codeGen.emitDeferredActionsForReturn());
            if (delayReturnMaterialization)
            {
                if (exprPayload.isAddress())
                    builder.emitLoadRegMem(returnValueReg, exprPayload.reg, 0, retBits);
                else
                    builder.emitLoadRegReg(returnValueReg, exprPayload.reg, retBits);
            }
            ABICall::materializeValueToReturnRegs(builder, callConvKind, returnValueReg, false, normalizedRet);
        }

        {
            const ScopedDebugNoStep noStep(builder, true);
            emitLocalStackFrameEpilogue(codeGen, callConvKind);
            builder.emitRet();
        }
        return Result::Continue;
    }

    void emitCompilerRunBlockStackEpilogue(CodeGen& codeGen, CallConvKind callConvKind)
    {
        if (!codeGen.hasLocalStackFrame())
            return;

        const CallConv& callConv = CallConv::get(callConvKind);
        MicroBuilder&   builder  = codeGen.builder();
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(codeGen.localStackFrameSize(), 64), MicroOp::Add, MicroOpBits::B64);
    }

    bool canUseCompilerRunBlockDirectCallWriteBack(const AstNode& exprNode, const CodeGenNodePayload& payload, const ABITypeNormalize::NormalizedType& normalizedRet)
    {
        if (normalizedRet.isVoid || normalizedRet.isIndirect)
            return false;
        if (exprNode.isNot(AstNodeId::CallExpr))
            return false;
        return payload.isValue();
    }

    bool isCompilerFunctionDecl(CodeGen& codeGen)
    {
        const AstNodeRef declRef = codeGen.function().declNodeRef();
        return declRef.isValid() && codeGen.node(declRef).is(AstNodeId::CompilerFunc);
    }

    Result emitCompilerRunBlockReturn(CodeGen& codeGen, AstNodeRef exprRef)
    {
        const SymbolFunction&                  symbolFunc       = codeGen.function();
        const CallConvKind                     callConvKind     = symbolFunc.callConvKind();
        const CallConv&                        callConv         = CallConv::get(callConvKind);
        const TypeRef                          returnTypeRef    = symbolFunc.returnTypeRef();
        const ABITypeNormalize::NormalizedType normalizedRet    = ABITypeNormalize::normalize(codeGen.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
        const MicroReg                         outputStorageReg = codeGen.ensureCurrentFunctionIndirectReturnReg(callConvKind);
        MicroBuilder&                          builder          = codeGen.builder();

        if (exprRef.isValid() && !normalizedRet.isVoid)
        {
            const CodeGenNodePayload& exprPayload     = codeGen.payload(exprRef);
            const MicroReg            payloadReg      = exprPayload.reg;
            const bool                payloadLValue   = exprPayload.isAddress();
            const AstNode&            exprNode        = codeGen.node(exprRef);
            const bool                needsPersistent = CodeGenFunctionHelpers::needsPersistentCompilerRunReturn(codeGen.sema(), returnTypeRef);

            if (normalizedRet.isIndirect)
            {
                SWC_ASSERT(normalizedRet.indirectSize != 0);
                if (needsPersistent)
                    CodeGenFunctionHelpers::emitPersistCompilerRunValue(codeGen, returnTypeRef, outputStorageReg, payloadReg, codeGen.localStackBaseReg(), codeGen.localStackFrameSize());
                else
                    CodeGenMemoryHelpers::emitMemCopy(codeGen, outputStorageReg, payloadReg, normalizedRet.indirectSize);
            }
            else
            {
                if (canUseCompilerRunBlockDirectCallWriteBack(exprNode, exprPayload, normalizedRet))
                    ABICall::storeReturnRegsToReturnBuffer(builder, callConvKind, outputStorageReg, normalizedRet);
                else
                    ABICall::storeValueToReturnBuffer(builder, callConvKind, outputStorageReg, payloadReg, payloadLValue, normalizedRet);

                if (needsPersistent)
                {
                    // Compiler-run blocks also need persistence for direct register returns like `string`.
                    CodeGenFunctionHelpers::emitPersistCompilerRunValue(codeGen, returnTypeRef, outputStorageReg, outputStorageReg, codeGen.localStackBaseReg(), codeGen.localStackFrameSize());
                }
            }
        }

        SWC_RESULT(codeGen.emitDeferredActionsForReturn());
        {
            const ScopedDebugNoStep noStep(builder, true);
            emitCompilerRunBlockStackEpilogue(codeGen, callConvKind);
            builder.emitRet();
        }
        return Result::Continue;
    }

    bool isCompilerRunBlockFunction(CodeGen& codeGen)
    {
        const AstNodeRef declRef = codeGen.function().declNodeRef();
        return declRef.isValid() && codeGen.node(declRef).is(AstNodeId::CompilerRunBlock);
    }

    bool isActiveFunctionRoot(CodeGen& codeGen, AstNodeRef declRef)
    {
        const AstNodeRef currentDeclRef = codeGen.viewZero(codeGen.curNodeRef()).nodeRef();
        const AstNodeRef activeDeclRef  = codeGen.viewZero(codeGen.function().declNodeRef()).nodeRef();
        return currentDeclRef == declRef && activeDeclRef == declRef;
    }

    ThrowableTarget resolveThrowableTarget(CodeGen& codeGen)
    {
        ThrowableTarget handlerTarget;
        if (tryResolveThrowableHandlerTarget(codeGen, codeGen.curNodeRef(), handlerTarget))
            return handlerTarget;

        for (size_t parentIndex = 0;; ++parentIndex)
        {
            const AstNodeRef parentRef = codeGen.visit().parentNodeRef(parentIndex);
            if (!parentRef.isValid())
                break;

            if (tryResolveThrowableHandlerTarget(codeGen, parentRef, handlerTarget))
                return handlerTarget;
        }

        for (size_t frameIndex = codeGen.frames().size(); frameIndex != 0; --frameIndex)
        {
            const CodeGenFrame& frame = codeGen.frames()[frameIndex - 1];
            if (!frame.hasCurrentInlineContext())
                continue;

            const CodeGenFrame::InlineContext& inlineCtx = frame.currentInlineContext();
            if (inlineCtx.payload && tryResolveThrowableHandlerTarget(codeGen, inlineCtx.payload->callRef, handlerTarget))
                return handlerTarget;
        }

        const AstNodeRef functionDeclRef = codeGen.viewZero(codeGen.function().declNodeRef()).nodeRef();
        SWC_ASSERT(functionDeclRef.isValid());
        CodeGenNodePayload& payload = ensureThrowableFunctionPayload(codeGen, functionDeclRef);
        if (!payload.throwableFunctionFailLabel.isValid())
        {
            MicroBuilder& builder              = codeGen.builder();
            payload.throwableFunctionFailLabel = builder.createLabel();
            payload.throwableFunctionDoneLabel = builder.createLabel();
        }

        return {
            .kind      = ThrowableTarget::Kind::FunctionReturn,
            .scopeRef  = functionDeclRef,
            .failLabel = payload.throwableFunctionFailLabel,
        };
    }

    Result emitFunctionLikeReturnNoDefers(CodeGen& codeGen, const SymbolFunction& symbolFunc, const CodeGenNodePayload* exprPayload)
    {
        MicroBuilder&                          builder                            = codeGen.builder();
        const CallConvKind                     callConvKind                       = symbolFunc.callConvKind();
        const CallConv&                        callConv                           = CallConv::get(callConvKind);
        const TypeRef                          returnTypeRef                      = symbolFunc.returnTypeRef();
        const ABITypeNormalize::NormalizedType normalizedRet                      = ABITypeNormalize::normalize(codeGen.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
        const bool                             needsPersistentCompilerBlockReturn = isCompilerRunBlockFunction(codeGen) && CodeGenFunctionHelpers::needsPersistentCompilerRunReturn(codeGen.sema(), returnTypeRef);
        const bool                             needsPersistentCompilerReturn      = isCompilerFunctionDecl(codeGen) && CodeGenFunctionHelpers::needsPersistentCompilerRunReturn(codeGen.sema(), returnTypeRef);

        if (isCompilerRunBlockFunction(codeGen))
        {
            const MicroReg outputStorageReg = codeGen.ensureCurrentFunctionIndirectReturnReg(callConvKind);
            if (!normalizedRet.isVoid)
            {
                SWC_ASSERT(exprPayload != nullptr);
                if (normalizedRet.isIndirect)
                {
                    if (needsPersistentCompilerBlockReturn)
                        CodeGenFunctionHelpers::emitPersistCompilerRunValue(codeGen, returnTypeRef, outputStorageReg, exprPayload->reg, codeGen.localStackBaseReg(), codeGen.localStackFrameSize());
                    else if (exprPayload->isAddress())
                    {
                        CodeGenMemoryHelpers::emitMemCopy(codeGen, outputStorageReg, exprPayload->reg, normalizedRet.indirectSize);
                        SWC_RESULT(emitPostCopyAfterIndirectReturnCopy(codeGen, returnTypeRef, *exprPayload, outputStorageReg));
                    }
                    else
                    {
                        emitIndirectReturnValuePayload(codeGen, outputStorageReg, exprPayload->reg, normalizedRet.indirectSize);
                        SWC_RESULT(emitPostCopyAfterIndirectReturnCopy(codeGen, returnTypeRef, *exprPayload, outputStorageReg));
                    }
                }
                else
                {
                    ABICall::storeValueToReturnBuffer(builder, callConvKind, outputStorageReg, exprPayload->reg, exprPayload->isAddress(), normalizedRet);
                    if (needsPersistentCompilerBlockReturn)
                        CodeGenFunctionHelpers::emitPersistCompilerRunValue(codeGen, returnTypeRef, outputStorageReg, outputStorageReg, codeGen.localStackBaseReg(), codeGen.localStackFrameSize());
                }
            }

            const ScopedDebugNoStep noStep(builder, true);
            emitCompilerRunBlockStackEpilogue(codeGen, callConvKind);
            builder.emitRet();
            return Result::Continue;
        }

        if (normalizedRet.isVoid)
        {
            const ScopedDebugNoStep noStep(builder, true);
            emitLocalStackFrameEpilogue(codeGen, callConvKind);
            builder.emitRet();
            return Result::Continue;
        }

        SWC_ASSERT(exprPayload != nullptr);
        if (normalizedRet.isIndirect)
        {
            const MicroReg outputStorageReg = codeGen.ensureCurrentFunctionIndirectReturnReg(callConvKind);
            if (needsPersistentCompilerReturn)
                CodeGenFunctionHelpers::emitPersistCompilerRunValue(codeGen, returnTypeRef, outputStorageReg, exprPayload->reg, codeGen.localStackBaseReg(), codeGen.localStackFrameSize());
            else if (exprPayload->isAddress())
            {
                CodeGenMemoryHelpers::emitMemCopy(codeGen, outputStorageReg, exprPayload->reg, normalizedRet.indirectSize);
                SWC_RESULT(emitPostCopyAfterIndirectReturnCopy(codeGen, returnTypeRef, *exprPayload, outputStorageReg));
            }
            else
            {
                emitIndirectReturnValuePayload(codeGen, outputStorageReg, exprPayload->reg, normalizedRet.indirectSize);
                SWC_RESULT(emitPostCopyAfterIndirectReturnCopy(codeGen, returnTypeRef, *exprPayload, outputStorageReg));
            }

            builder.emitLoadRegReg(callConv.intReturn, outputStorageReg, MicroOpBits::B64);
        }
        else
        {
            const MicroReg    returnValueReg = codeGen.nextVirtualRegisterForType(returnTypeRef);
            const MicroOpBits retBits        = normalizedRet.numBits ? microOpBitsFromBitWidth(normalizedRet.numBits) : MicroOpBits::B64;
            SWC_ASSERT(retBits != MicroOpBits::Zero);
            if (exprPayload->isAddress())
                builder.emitLoadRegMem(returnValueReg, exprPayload->reg, 0, retBits);
            else
                builder.emitLoadRegReg(returnValueReg, exprPayload->reg, retBits);
            ABICall::materializeValueToReturnRegs(builder, callConvKind, returnValueReg, false, normalizedRet);
        }

        {
            const ScopedDebugNoStep noStep(builder, true);
            emitLocalStackFrameEpilogue(codeGen, callConvKind);
            builder.emitRet();
        }

        return Result::Continue;
    }

    Result emitThrowableFunctionFailureReturn(CodeGen& codeGen)
    {
        const SymbolFunction&                  symbolFunc    = codeGen.function();
        const CallConv&                        callConv      = CallConv::get(symbolFunc.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symbolFunc.returnTypeRef(), ABITypeNormalize::Usage::Return);
        if (normalizedRet.isVoid)
            return emitFunctionLikeReturnNoDefers(codeGen, symbolFunc, nullptr);

        ConstantRef zeroCstRef = ConstantRef::invalid();
        SWC_RESULT(makeZeroConstantRefForType(codeGen, zeroCstRef, symbolFunc.returnTypeRef()));

        CodeGenNodePayload zeroPayload;
        if (!CodeGenCallHelpers::materializeTypedConstantPayload(codeGen, zeroPayload, symbolFunc.returnTypeRef(), zeroCstRef))
            return raiseInternalCodeGenError(codeGen, "failed to materialize the synthesized throwable failure return payload");

        return emitFunctionLikeReturnNoDefers(codeGen, symbolFunc, &zeroPayload);
    }

    Result emitThrowableJump(CodeGen& codeGen)
    {
        const ThrowableTarget target = resolveThrowableTarget(codeGen);
        if (target.kind == ThrowableTarget::Kind::Handler)
            SWC_RESULT(codeGen.emitDeferredActionsUntilScopeRef(target.scopeRef));
        else
            SWC_RESULT(codeGen.emitDeferredActionsForReturn());

        codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, target.failLabel);
        return Result::Continue;
    }

    Result codeGenFunctionLikePostNode(CodeGen& codeGen, AstNodeRef declRef, AstNodeRef bodyRef, bool hasExpressionBody)
    {
        declRef = codeGen.viewZero(declRef).nodeRef();
        if (!isActiveFunctionRoot(codeGen, declRef))
            return Result::Continue;

        const SymbolFunction&                  symbolFunc    = codeGen.function();
        const CallConvKind                     callConvKind  = symbolFunc.callConvKind();
        const CallConv&                        callConv      = CallConv::get(callConvKind);
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symbolFunc.returnTypeRef(), ABITypeNormalize::Usage::Return);

        if (hasExpressionBody)
        {
            SWC_ASSERT(bodyRef.isValid());
            SWC_RESULT(emitFunctionReturn(codeGen, symbolFunc, bodyRef));
            SWC_RESULT(codeGen.popDeferScope());
        }
        else if (normalizedRet.isVoid)
        {
            SWC_RESULT(emitFunctionReturn(codeGen, symbolFunc, AstNodeRef::invalid()));
            SWC_RESULT(codeGen.popDeferScope());
        }
        else
        {
            SWC_RESULT(codeGen.popDeferScope());
        }

        CodeGenNodePayload* payload = throwableFunctionPayload(codeGen, declRef);
        if (payload && payload->throwableFunctionFailLabel.isValid())
        {
            MicroBuilder& builder = codeGen.builder();
            if (!codeGen.currentInstructionBlocksFallthrough())
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, payload->throwableFunctionDoneLabel);

            builder.placeLabel(payload->throwableFunctionFailLabel);
            SWC_RESULT(emitThrowableFunctionFailureReturn(codeGen));
            builder.placeLabel(payload->throwableFunctionDoneLabel);
            payload->clearThrowableFunctionTarget();
        }

        return Result::Continue;
    }
}

Result CodeGenCallHelpers::emitThrowableFailureJump(CodeGen& codeGen)
{
    return emitThrowableJump(codeGen);
}

Result CodeGenCallHelpers::emitThrowableFailureJumpIfHasError(CodeGen& codeGen)
{
    const SymbolFunction* runtimeHasErr = runtimeFunctionByKind(codeGen, IdentifierManager::RuntimeFunctionKind::HasErr);
    SWC_ASSERT(runtimeHasErr != nullptr);
    if (!runtimeHasErr)
        return raiseInternalCodeGenError(codeGen, "missing runtime helper '__hasErr'");

    const MicroReg hasErrReg = codeGen.nextVirtualIntRegister();
    SWC_RESULT(emitRuntimeCallWithDirectArgsToReg(codeGen, *runtimeHasErr, std::span<const MicroReg>{}, hasErrReg));

    MicroBuilder&       builder       = codeGen.builder();
    const MicroLabelRef continueLabel = builder.createLabel();
    builder.emitCmpRegImm(hasErrReg, ApInt(0, 64), MicroOpBits::B8);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, continueLabel);
    SWC_RESULT(emitThrowableJump(codeGen));
    builder.placeLabel(continueLabel);
    return Result::Continue;
}

Result CodeGenFunctionHelpers::emitThrowableWrapperPreNode(CodeGen& codeGen, AstNodeRef nodeRef)
{
    CodeGenNodePayload* payload = throwableWrapperOwnerPayload(codeGen, nodeRef);
    if (!payload || !isHandledThrowableContext(payload->throwableWrapperTokenId))
        return Result::Continue;

    MicroBuilder& builder       = codeGen.builder();
    payload->throwableFailLabel = builder.createLabel();
    payload->throwableDoneLabel = builder.createLabel();
    codeGen.pushDeferScope(nodeRef);

    const SymbolFunction* runtimePushErr = runtimeFunctionByKind(codeGen, IdentifierManager::RuntimeFunctionKind::PushErr);
    SWC_ASSERT(runtimePushErr != nullptr);
    if (!runtimePushErr)
        return raiseInternalCodeGenError(codeGen, "missing runtime helper '__pushErr'", nodeRef);

    return CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *runtimePushErr, std::span<const MicroReg>{});
}

Result CodeGenFunctionHelpers::emitThrowableWrapperPostNode(CodeGen& codeGen, AstNodeRef nodeRef)
{
    CodeGenNodePayload* payload = throwableWrapperOwnerPayload(codeGen, nodeRef);
    if (!payload || !payload->throwableFailLabel.isValid() || !isHandledThrowableContext(payload->throwableWrapperTokenId))
        return Result::Continue;

    const ThrowableHandlerKind kind           = throwableHandlerKind(payload->throwableWrapperTokenId);
    const AstNodeRef           ownerRef       = payload->throwableWrapperOwnerRef.isValid() ? payload->throwableWrapperOwnerRef : nodeRef;
    const TypeRef              resultType     = codeGen.curViewType().typeRef();
    const bool                 hasResult      = resultType.isValid() && resultType != codeGen.typeMgr().typeVoid();
    const bool                 hasFallthrough = !codeGen.currentInstructionBlocksFallthrough();
    MicroBuilder&              builder        = codeGen.builder();
    SWC_ASSERT(kind != ThrowableHandlerKind::None);

    if (hasFallthrough)
        SWC_RESULT(emitThrowableCleanup(codeGen, kind, ownerRef, false));

    SWC_RESULT(codeGen.popDeferScope());
    if (hasFallthrough && !codeGen.currentInstructionBlocksFallthrough())
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, payload->throwableDoneLabel);

    builder.placeLabel(payload->throwableFailLabel);
    SWC_RESULT(emitThrowableCleanup(codeGen, kind, ownerRef, true));
    if (hasResult)
    {
        const CodeGenNodePayload& resultPayload = codeGen.payload(nodeRef);
        SWC_RESULT(emitZeroThrowableExprResult(codeGen, resultPayload, resultType));
    }

    builder.placeLabel(payload->throwableDoneLabel);
    clearThrowableWrapperPayload(*payload);
    return Result::Continue;
}

Result AstFunctionDecl::codeGenPostNode(CodeGen& codeGen) const
{
    return codeGenFunctionLikePostNode(codeGen, codeGen.curNodeRef(), nodeBodyRef, hasFlag(AstFunctionFlagsE::Short));
}

Result AstFunctionExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const AstNodeRef declRef = codeGen.viewZero(codeGen.curNodeRef()).nodeRef();
    if (!isActiveFunctionRoot(codeGen, declRef))
    {
        const auto&               symFunc = functionExprSymbol(codeGen, declRef);
        const SemaNodeView        view    = codeGen.curViewType();
        const CodeGenNodePayload& payload = codeGen.setPayloadValue(declRef, view.typeRef());
        MicroBuilder&             builder = codeGen.builder();
        builder.emitLoadRegPtrReloc(payload.reg, 0, ConstantRef::invalid(), &symFunc);
        return Result::Continue;
    }

    const bool hasExpressionBody = nodeBodyRef.isValid() && codeGen.node(nodeBodyRef).isNot(AstNodeId::EmbeddedBlock);
    return codeGenFunctionLikePostNode(codeGen, declRef, nodeBodyRef, hasExpressionBody);
}

Result AstClosureExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const AstNodeRef declRef = codeGen.viewZero(codeGen.curNodeRef()).nodeRef();
    if (!isActiveFunctionRoot(codeGen, declRef))
    {
        const auto&        symFunc = functionExprSymbol(codeGen, declRef);
        const SemaNodeView view    = codeGen.curViewType();
        return emitClosureExprValue(codeGen, declRef, symFunc, view.typeRef());
    }

    const bool hasExpressionBody = nodeBodyRef.isValid() && codeGen.node(nodeBodyRef).isNot(AstNodeId::EmbeddedBlock);
    return codeGenFunctionLikePostNode(codeGen, declRef, nodeBodyRef, hasExpressionBody);
}

Result AstReturnStmt::codeGenPostNode(CodeGen& codeGen) const
{
    if (codeGen.frame().hasCurrentInlineContext())
    {
        const CodeGenFrame::InlineContext& inlineCtx = codeGen.frame().currentInlineContext();
        SWC_ASSERT(inlineCtx.payload != nullptr);
        if (!inlineCtx.payload->returnsToCallerSite())
            return emitInlineReturn(codeGen, *inlineCtx.payload, nodeExprRef);
    }

    if (isCompilerRunBlockFunction(codeGen))
        return emitCompilerRunBlockReturn(codeGen, nodeExprRef);

    return emitFunctionReturn(codeGen, codeGen.function(), nodeExprRef);
}

Result AstTryCatchExpr::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef resolvedChildRef = codeGen.viewZero(childRef).nodeRef();
    const AstNodeRef managedExprRef   = codeGen.viewZero(nodeExprRef).nodeRef();
    if (resolvedChildRef == managedExprRef)
        SWC_RESULT(CodeGenFunctionHelpers::emitThrowableWrapperPreNode(codeGen, codeGen.curNodeRef()));

    return Result::Continue;
}

Result AstTryCatchExpr::codeGenPostNode(CodeGen& codeGen) const
{
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeExprRef, codeGen.transparentPayloadTypeRef());
    return CodeGenFunctionHelpers::emitThrowableWrapperPostNode(codeGen, codeGen.curNodeRef());
}

Result AstTryCatchStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef resolvedChildRef = codeGen.viewZero(childRef).nodeRef();
    const AstNodeRef managedBodyRef   = codeGen.viewZero(nodeBodyRef).nodeRef();
    if (resolvedChildRef == managedBodyRef)
        SWC_RESULT(CodeGenFunctionHelpers::emitThrowableWrapperPreNode(codeGen, codeGen.curNodeRef()));

    return Result::Continue;
}

Result AstTryCatchStmt::codeGenPostNode(CodeGen& codeGen)
{
    return CodeGenFunctionHelpers::emitThrowableWrapperPostNode(codeGen, codeGen.curNodeRef());
}

Result AstThrowExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const TypeRef resultTypeRef = codeGen.curViewType().typeRef();
    if (resultTypeRef.isValid() && resultTypeRef != codeGen.typeMgr().typeVoid())
    {
        const CodeGenNodePayload& resultPayload = usesAddressBackedThrowableExprResult(codeGen, resultTypeRef)
                                                      ? codeGen.setPayloadAddressReg(codeGen.curNodeRef(), codeGen.runtimeStorageAddressReg(codeGen.curNodeRef()), resultTypeRef)
                                                      : codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        SWC_RESULT(emitZeroThrowableExprResult(codeGen, resultPayload, resultTypeRef));
    }

    const SemaNodeView        exprView    = codeGen.viewType(nodeExprRef);
    const CodeGenNodePayload& exprPayload = codeGen.payload(nodeExprRef);
    const TypeRef             exprTypeRef = exprView.typeRef();
    const MicroReg            storageReg  = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
    SWC_RESULT(emitPayloadToAddress(codeGen, storageReg, exprPayload, exprTypeRef));

    SymbolFunction* runtimeSetErrRaw = runtimeFunctionByKind(codeGen, IdentifierManager::RuntimeFunctionKind::SetErrRaw);
    SWC_ASSERT(runtimeSetErrRaw != nullptr);
    if (!runtimeSetErrRaw)
        return raiseInternalCodeGenError(codeGen, "missing runtime helper '__setErrRaw'", codeGen.curNodeRef());

    ConstantRef typeInfoCstRef = ConstantRef::invalid();
    SWC_RESULT(codeGen.cstMgr().makeTypeInfo(codeGen.sema(), typeInfoCstRef, exprTypeRef, nodeExprRef));

    CodeGenNodePayload typeInfoPayload;
    const TypeRef      typeInfoTypeRef = runtimeSetErrRaw->parameters()[1]->typeRef();
    if (!CodeGenCallHelpers::materializeTypedConstantPayload(codeGen, typeInfoPayload, typeInfoTypeRef, typeInfoCstRef))
        return raiseInternalCodeGenError(codeGen, "failed to materialize the thrown-value type info payload", codeGen.curNodeRef());

    const std::array args = {storageReg, typeInfoPayload.reg};
    SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *runtimeSetErrRaw, args));
    return CodeGenCallHelpers::emitThrowableFailureJump(codeGen);
}

SWC_END_NAMESPACE();
