#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMoveElision.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
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
#include "Support/Report/Assert.h"

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
            if (dep->declNodeRef() == nodeRef && dep->declNodePayloadContext() == &codeGen.sema().currentNodePayloadContext())
                return dep;
        }

        SymbolFunction* sourceLocationMatch = nullptr;
        for (SymbolFunction* dep : deps)
        {
            SWC_ASSERT(dep != nullptr);
            if (dep->declNodeRef().isInvalid())
                continue;

            // Nested function expressions can be lowered before the symbol view is rebound, so recover the
            // callee by matching the declaration source location recorded in the dependency list. Inline
            // clones can share source tokens, so this fallback is only valid when the match is unique.
            if (dep->srcViewRef() != node.srcViewRef())
                continue;
            if (dep->tokRef() != node.tokRef())
                continue;
            if (sourceLocationMatch)
                return nullptr;
            sourceLocationMatch = dep;
        }

        return sourceLocationMatch;
    }

    AstNodeRef resolvedCallableDeclRef(CodeGen& codeGen, AstNodeRef nodeRef, AstNodeId nodeId)
    {
        const AstNodeRef resolvedRef = codeGen.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isValid() && codeGen.node(resolvedRef).is(nodeId))
            return resolvedRef;
        return nodeRef;
    }

    AstNodeRef resolvedFunctionLikeDeclRef(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& node = codeGen.node(nodeRef);
        if (node.is(AstNodeId::FunctionExpr) || node.is(AstNodeId::ClosureExpr))
            return resolvedCallableDeclRef(codeGen, nodeRef, node.id());

        const AstNodeRef resolvedRef = codeGen.viewZero(nodeRef).nodeRef();
        return resolvedRef.isValid() ? resolvedRef : nodeRef;
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

    SymbolFunction* singleFunctionFromView(const SemaNodeView& view)
    {
        Symbol* symbol = view.singleSymbol();
        if (!symbol || !symbol->isFunction())
            return nullptr;
        return &symbol->cast<SymbolFunction>();
    }

    enum class FallibleHandlerKind : uint8_t
    {
        None,
        Catch,
        Expect,
    };

    struct FallibleTarget
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

    bool isFallibleWrapperOwnerNode(AstNodeId nodeId)
    {
        return nodeId == AstNodeId::ErrorManagementExpr || nodeId == AstNodeId::ErrorManagementStmt;
    }

    bool isFallibleWrapperBreadcrumbNode(AstNodeId nodeId)
    {
        return isFallibleWrapperOwnerNode(nodeId) || nodeId == AstNodeId::CallExpr;
    }

    CodeGenNodePayload* fallibleWrapperOwnerPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid())
            return nullptr;

        const AstNodeRef resolvedNodeRef = codeGen.viewZero(nodeRef).nodeRef();
        if (!resolvedNodeRef.isValid())
            return nullptr;

        if (!isFallibleWrapperOwnerNode(codeGen.node(resolvedNodeRef).id()))
            return nullptr;

        CodeGenNodePayload* payload = codeGen.safePayload(resolvedNodeRef);
        if (!payload || !payload->hasFallibleWrapper())
            return nullptr;
        return payload;
    }

    CodeGenNodePayload* fallibleWrapperBreadcrumbPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid())
            return nullptr;

        const AstNodeRef resolvedNodeRef = codeGen.viewZero(nodeRef).nodeRef();
        if (!resolvedNodeRef.isValid())
            return nullptr;

        if (!isFallibleWrapperBreadcrumbNode(codeGen.node(resolvedNodeRef).id()))
            return nullptr;

        CodeGenNodePayload* payload = codeGen.safePayload(nodeRef);
        if (!payload || !payload->hasFallibleWrapper())
            return nullptr;
        return payload;
    }

    void clearFallibleWrapperPayload(CodeGenNodePayload& payload)
    {
        payload.clearFallibleWrapper();
    }

    CodeGenNodePayload* fallibleFunctionPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safePayload(nodeRef);
    }

    CodeGenNodePayload& ensureFallibleFunctionPayload(CodeGen& codeGen, AstNodeRef nodeRef)
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

    FallibleHandlerKind fallibleHandlerKind(TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::KwdCatch:
                return FallibleHandlerKind::Catch;

            case TokenId::KwdExpect:
                return FallibleHandlerKind::Expect;

            default:
                return FallibleHandlerKind::None;
        }
    }

    bool isHandledFallibleContext(TokenId tokenId)
    {
        return fallibleHandlerKind(tokenId) != FallibleHandlerKind::None;
    }

    bool tryResolveFallibleHandlerTarget(CodeGen& codeGen, AstNodeRef candidateRef, FallibleTarget& outTarget)
    {
        const CodeGenNodePayload* breadcrumbPayload = fallibleWrapperBreadcrumbPayload(codeGen, candidateRef);
        if (!breadcrumbPayload || !isHandledFallibleContext(breadcrumbPayload->fallibleWrapperTokenId))
            return false;

        AstNodeRef ownerRef = breadcrumbPayload->fallibleWrapperOwnerRef;
        if (!ownerRef.isValid())
            ownerRef = codeGen.viewZero(candidateRef).nodeRef();

        const CodeGenNodePayload* ownerPayload = fallibleWrapperOwnerPayload(codeGen, ownerRef);
        if (!ownerPayload || !ownerPayload->fallibleFailLabel.isValid())
            return false;

        outTarget = {
            .kind      = FallibleTarget::Kind::Handler,
            .scopeRef  = codeGen.viewZero(ownerRef).nodeRef(),
            .failLabel = ownerPayload->fallibleFailLabel,
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

    TypeRef unwrapAliasTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeRef unwrappedTypeRef = codeGen.typeMgr().get(typeRef).unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
        return unwrappedTypeRef.isValid() ? unwrappedTypeRef : typeRef;
    }

    bool isReferenceValueType(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;
        return codeGen.typeMgr().get(unwrapAliasTypeRef(codeGen, typeRef)).isReference();
    }

    MicroReg materializeReferenceValueReg(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef sourceTypeRef)
    {
        if (payload.isValue())
            return payload.reg;

        const MicroReg resultReg = codeGen.nextVirtualIntRegister();
        if (isReferenceValueType(codeGen, sourceTypeRef))
            codeGen.builder().emitLoadRegMem(resultReg, payload.reg, 0, MicroOpBits::B64);
        else
            codeGen.builder().emitLoadRegReg(resultReg, payload.reg, MicroOpBits::B64);
        return resultReg;
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

    bool usesAddressBackedFallibleExprResult(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid() || typeRef == codeGen.typeMgr().typeVoid())
            return false;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        const uint64_t  sizeOf   = typeInfo.sizeOf(codeGen.ctx());
        if (sizeOf > sizeof(uint64_t))
            return true;

        return scalarStoreBitsForTypeRef(codeGen, typeRef) == MicroOpBits::Zero;
    }

    bool hasExpectRuntimeSafety(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        const AstNodeRef resolvedNodeRef = codeGen.viewZero(nodeRef).nodeRef();
        if (!resolvedNodeRef.isValid())
            return false;

        const auto* payload = codeGen.loweringPayload(resolvedNodeRef);
        return payload && payload->hasRuntimeSafety(Runtime::SafetyWhat::Expect);
    }

    bool isNotNullUnwrap(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        const AstNodeRef resolvedNodeRef = codeGen.viewZero(nodeRef).nodeRef();
        if (!resolvedNodeRef.isValid())
            return false;

        const auto* payload = codeGen.loweringPayload(resolvedNodeRef);
        return payload && payload->notNullUnwrap;
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

    Result emitFailedExpectRuntimeCall(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        SymbolFunction* runtimeFailedExpect = runtimeFunctionByKind(codeGen, IdentifierManager::RuntimeFunctionKind::FailedExpect);
        SWC_ASSERT(runtimeFailedExpect != nullptr);
        if (!runtimeFailedExpect)
            return raiseInternalCodeGenError(codeGen, "missing runtime helper '__failedExpect'", nodeRef);

        ConstantRef sourceLocCstRef = ConstantRef::invalid();
        SWC_RESULT(ConstantHelpers::makeSourceCodeLocation(codeGen.sema(), sourceLocCstRef, codeGen.node(nodeRef)));

        CodeGenNodePayload sourceLocPayload;
        const TypeRef      sourceLocTypeRef = runtimeFailedExpect->parameters().front()->typeRef();
        if (!CodeGenCallHelpers::materializeTypedConstantPayload(codeGen, sourceLocPayload, sourceLocTypeRef, sourceLocCstRef))
            return raiseInternalCodeGenError(codeGen, "cannot materialize the failed-expect source location payload", nodeRef);

        const std::array args = {sourceLocPayload.reg};
        return CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *runtimeFailedExpect, args);
    }

    MicroReg materializeNullablePresenceReg(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef typeRef, MicroOpBits& outBits)
    {
        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        const uint64_t  sizeOf   = typeInfo.sizeOf(codeGen.ctx());
        outBits                  = sizeOf > sizeof(uint64_t) ? MicroOpBits::B64 : CodeGenTypeHelpers::compareBits(typeInfo, codeGen.ctx());
        SWC_ASSERT(outBits != MicroOpBits::Zero);

        MicroBuilder&  builder   = codeGen.builder();
        const MicroReg resultReg = codeGen.nextVirtualIntRegister();
        if (sizeOf > sizeof(uint64_t) || payload.isAddress())
            builder.emitLoadRegMem(resultReg, payload.reg, 0, outBits);
        else
            builder.emitLoadRegReg(resultReg, payload.reg, outBits);
        return resultReg;
    }

    Result emitNotNullRuntimeSafety(CodeGen& codeGen, AstNodeRef ownerRef, AstNodeRef exprRef)
    {
        if (!isNotNullUnwrap(codeGen, ownerRef) || !hasExpectRuntimeSafety(codeGen, ownerRef))
            return Result::Continue;

        const AstNodeRef resolvedExprRef = codeGen.resolvedNodeRef(exprRef);
        if (!resolvedExprRef.isValid())
            return raiseInternalCodeGenError(codeGen, "cannot resolve the 'notnull' operand", ownerRef);

        TypeRef exprTypeRef = codeGen.viewType(resolvedExprRef).typeRef();
        if (!exprTypeRef.isValid())
            return raiseInternalCodeGenError(codeGen, "missing the 'notnull' operand type", ownerRef);

        const TypeRef unwrappedExprTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), exprTypeRef);
        if (unwrappedExprTypeRef.isValid())
            exprTypeRef = unwrappedExprTypeRef;

        auto                      presenceBits = MicroOpBits::Zero;
        const CodeGenNodePayload& exprPayload  = codeGen.payload(resolvedExprRef);
        const MicroReg            presenceReg  = materializeNullablePresenceReg(codeGen, exprPayload, exprTypeRef, presenceBits);
        MicroBuilder&             builder      = codeGen.builder();
        const MicroLabelRef       presentLabel = builder.createLabel();
        builder.emitCmpRegImm(presenceReg, ApInt(0, 64), presenceBits);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, presentLabel);
        SWC_RESULT(CodeGenSafety::emitNotNullCheck(codeGen, codeGen.node(ownerRef)));
        builder.placeLabel(presentLabel);
        return Result::Continue;
    }

    Result emitPayloadToAddress(CodeGen& codeGen, MicroReg dstAddressReg, const CodeGenNodePayload& srcPayload, TypeRef typeRef);

    void assignFallibleExprResult(CodeGen& codeGen, const CodeGenNodePayload& dstPayload, const CodeGenNodePayload& srcPayload, TypeRef typeRef)
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
            return raiseInternalCodeGenError(codeGen, "zero constant storage size is outside the supported range");

        SmallVector<std::byte> rawBytes;
        rawBytes.resize(sizeOf);
        std::memset(rawBytes.data(), 0, rawBytes.size());

        ConstantValue zeroValue;
        if (typeInfo.isStruct() || typeInfo.isAny() || typeInfo.isInterface())
            zeroValue = ConstantValue::makeStructBorrowed(ctx, storageTypeRef, std::span{rawBytes.data(), rawBytes.size()});
        else if (typeInfo.isArray())
            zeroValue = ConstantValue::makeArrayBorrowed(ctx, storageTypeRef, std::span{rawBytes.data(), rawBytes.size()});
        else
            zeroValue = ConstantValue::make(ctx, rawBytes.data(), storageTypeRef, ConstantValue::PayloadOwnership::Borrowed);
        if (zeroValue.kind() == ConstantKind::Invalid)
            return raiseInternalCodeGenError(codeGen, "cannot materialize the synthesized zero constant");

        if (isEnumOrAliasEnum(codeGen, typeRef))
        {
            const ConstantRef storageCstRef = codeGen.cstMgr().addConstant(ctx, zeroValue);
            if (storageCstRef.isInvalid())
                return raiseInternalCodeGenError(codeGen, "cannot cache the synthesized enum zero constant");

            zeroValue = ConstantValue::makeEnumValue(ctx, storageCstRef, typeRef);
        }
        else
        {
            zeroValue.setTypeRef(typeRef);
        }

        outCstRef = codeGen.cstMgr().addConstant(ctx, zeroValue);
        if (!outCstRef.isValid())
            return raiseInternalCodeGenError(codeGen, "cannot cache the synthesized zero constant");
        return Result::Continue;
    }

    Result emitZeroFallibleExprResult(CodeGen& codeGen, const CodeGenNodePayload& resultPayload, TypeRef typeRef)
    {
        if (!typeRef.isValid() || typeRef == codeGen.typeMgr().typeVoid())
            return Result::Continue;

        ConstantRef zeroCstRef = ConstantRef::invalid();
        SWC_RESULT(makeZeroConstantRefForType(codeGen, zeroCstRef, typeRef));

        CodeGenNodePayload zeroPayload;
        if (!CodeGenCallHelpers::materializeTypedConstantPayload(codeGen, zeroPayload, typeRef, zeroCstRef))
            return raiseInternalCodeGenError(codeGen, "cannot materialize the synthesized zero fallible result payload");

        assignFallibleExprResult(codeGen, resultPayload, zeroPayload, typeRef);
        return Result::Continue;
    }

    Result emitPayloadToAddress(CodeGen& codeGen, MicroReg dstAddressReg, const CodeGenNodePayload& srcPayload, TypeRef typeRef)
    {
        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        const uint32_t  sizeOf   = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, typeInfo);
        if (typeInfo.isReference())
        {
            const MicroReg referenceReg = materializeReferenceValueReg(codeGen, srcPayload, srcPayload.typeRef);
            codeGen.builder().emitLoadMemReg(dstAddressReg, 0, referenceReg, MicroOpBits::B64);
            return Result::Continue;
        }

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

    // A call result held in a compiler temporary owns its value: the return transfers
    // it with 'opPostMove' instead of deep-copying it, and nothing drops the abandoned
    // temporary. Caller-owned return storages ('retval') stay outside this rule, and so
    // does a reference-returning call: its address is a borrowed referee, not a temp.
    bool returnSourceIsOwnedTemporary(CodeGen& codeGen, AstNodeRef exprRef, const CodeGenNodePayload& exprPayload)
    {
        if (exprRef.isInvalid() || !exprPayload.isAddress())
            return false;
        if (exprPayload.runtimeStorageSym && exprPayload.runtimeStorageSym->hasExtraFlag(SymbolVariableFlagsE::RetVal))
            return false;

        const AstNodeRef resolvedExprRef = codeGen.viewZero(exprRef).nodeRef();
        if (resolvedExprRef.isInvalid() || codeGen.node(resolvedExprRef).isNot(AstNodeId::CallExpr))
            return false;

        const SymbolFunction* calledFunction = singleFunctionFromView(codeGen.sema().viewStored(resolvedExprRef, SemaNodeViewPartE::Symbol));
        if (!calledFunction)
            calledFunction = singleFunctionFromView(codeGen.viewSymbol(resolvedExprRef));
        if (!calledFunction || !calledFunction->returnTypeRef().isValid())
            return false;
        return !codeGen.typeMgr().get(calledFunction->returnTypeRef()).isReference();
    }

    // The local named by 'return exprRef' when the return can transfer its ownership:
    // the value moves to the caller and this return's deferred actions skip its drop.
    const SymbolVariable* returnMoveOutSource(CodeGen& codeGen, AstNodeRef exprRef)
    {
        const SymbolVariable* symVar = CodeGenMoveElision::directStructVariable(codeGen, exprRef);
        if (!symVar || !CodeGenMoveElision::canMoveOutAtReturn(codeGen, *symVar))
            return nullptr;
        return symVar;
    }

    Result emitFallibleCleanup(CodeGen& codeGen, FallibleHandlerKind kind, AstNodeRef nodeRef, bool failurePath)
    {
        switch (kind)
        {
            case FallibleHandlerKind::Catch:
                return emitRuntimeHelperCallWithNoArgs(codeGen, IdentifierManager::RuntimeFunctionKind::CatchErr, "missing runtime helper '__catchErr'", nodeRef);

            case FallibleHandlerKind::Expect:
            {
                if (failurePath && hasExpectRuntimeSafety(codeGen, nodeRef))
                    SWC_RESULT(emitFailedExpectRuntimeCall(codeGen, nodeRef));

                return emitRuntimeHelperCallWithNoArgs(codeGen, IdentifierManager::RuntimeFunctionKind::PopErr, "missing runtime helper '__popErr'", nodeRef);
            }

            case FallibleHandlerKind::None:
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

    bool tryEmitInlineDirectCallResultStore(CodeGen& codeGen, const SemaInlinePayload& inlinePayload, AstNodeRef exprRef)
    {
        if (exprRef.isInvalid())
            return false;

        const AstNodeRef resolvedExprRef = codeGen.viewZero(exprRef).nodeRef();
        if (!resolvedExprRef.isValid())
            return false;

        const AstNode& exprNode = codeGen.node(resolvedExprRef);
        if (exprNode.isNot(AstNodeId::CallExpr))
            return false;

        const SymbolFunction* calledFunction = singleFunctionFromView(codeGen.sema().viewStored(resolvedExprRef, SemaNodeViewPartE::Symbol));
        if (!calledFunction)
            calledFunction = singleFunctionFromView(codeGen.viewSymbol(resolvedExprRef));
        if (!calledFunction)
            return false;

        const CallConvKind                     callConvKind  = calledFunction->callConvKind();
        const CallConv&                        callConv      = CallConv::get(callConvKind);
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, calledFunction->returnTypeRef(), ABITypeNormalize::Usage::Return);
        if (normalizedRet.isVoid || normalizedRet.isIndirect)
            return false;

        const MicroReg resultAddr = inlineResultAddressReg(codeGen, *inlinePayload.resultVar);
        ABICall::storeReturnRegsToReturnBuffer(codeGen.builder(), callConvKind, resultAddr, normalizedRet);
        return true;
    }

    Result emitInlineResultStore(CodeGen& codeGen, const SemaInlinePayload& inlinePayload, AstNodeRef exprRef, const SymbolVariable* moveOutVar)
    {
        SWC_ASSERT(inlinePayload.resultVar != nullptr);
        SWC_ASSERT(exprRef.isValid());

        const SymbolVariable& resultVar  = *inlinePayload.resultVar;
        const MicroReg        resultAddr = inlineResultAddressReg(codeGen, resultVar);
        if (tryEmitInlineDirectCallResultStore(codeGen, inlinePayload, exprRef))
            return Result::Continue;

        AstNodeRef payloadExprRef = codeGen.viewZero(exprRef).nodeRef();
        if (payloadExprRef.isInvalid())
            payloadExprRef = exprRef;

        const CodeGenNodePayload& exprPayload = codeGen.payload(payloadExprRef);
        // The value was built straight in the result local, so storing it there would copy the
        // local onto itself. As in the return-slot case, the storage symbol is what proves the
        // aliasing: both sides derive their own register from the same local.
        if (exprPayload.isAddress() && exprPayload.runtimeStorageSym == &resultVar)
            return Result::Continue;

        SWC_RESULT(emitPayloadToAddress(codeGen, resultAddr, exprPayload, inlinePayload.returnTypeRef));

        // The inline result temporary must own its value, like a real return slot: a
        // moved-out local or an owned call temporary transfers with 'opPostMove'; any
        // other lifecycle source is deep-copied so the store does not alias a live value.
        if (codeGen.typeMgr().get(inlinePayload.returnTypeRef).isReference())
            return Result::Continue;
        const bool movesOwnership     = moveOutVar != nullptr || returnSourceIsOwnedTemporary(codeGen, exprRef, exprPayload);
        const auto storeLifecycleKind = movesOwnership ? CodeGen::LifecycleKind::PostMove : CodeGen::LifecycleKind::PostCopy;
        if (codeGen.hasLifecycle(inlinePayload.returnTypeRef, storeLifecycleKind))
            SWC_RESULT(codeGen.emitLifecycle(inlinePayload.returnTypeRef, storeLifecycleKind, resultAddr));

        if (movesOwnership)
        {
            const SymbolVariable* sourceStorage = codeGen.runtimeStorageSymbol(exprRef);
            if (sourceStorage && codeGen.hasTemporaryDrop(*sourceStorage))
                codeGen.cancelTemporaryDrop(*sourceStorage);
        }

        return Result::Continue;
    }

    Result emitInlineReturn(CodeGen& codeGen, const SemaInlinePayload& inlinePayload, AstNodeRef exprRef)
    {
        const SymbolVariable* moveOutVar = nullptr;
        if (inlinePayload.returnTypeRef != codeGen.typeMgr().typeVoid())
        {
            SWC_ASSERT(exprRef.isValid());
            if (!codeGen.typeMgr().get(inlinePayload.returnTypeRef).isReference())
                moveOutVar = returnMoveOutSource(codeGen, exprRef);
            SWC_RESULT(emitInlineResultStore(codeGen, inlinePayload, exprRef, moveOutVar));
        }

        const SymbolVariable* previousMoveOutVar = codeGen.returnMoveOutVar();
        codeGen.setReturnMoveOutVar(moveOutVar);
        const Result deferredResult = codeGen.emitDeferredActionsUntilScopeRef(inlinePayload.inlineRootRef);
        codeGen.setReturnMoveOutVar(previousMoveOutVar);
        SWC_RESULT(deferredResult);

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

    CodeGenNodePayload resolveClosureCaptureSourcePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (symVar.isClosureCapture())
            return CodeGenFunctionHelpers::resolveClosureCapturePayload(codeGen, symVar);

        if (const SymbolVariable* canonicalParam = CodeGenFunctionHelpers::resolveCanonicalParameter(codeGen.function(), symVar))
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
            CodeGenMemoryHelpers::emitGlobalVariableAddress(codeGen, globalPayload.reg, symVar);
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

    // The value was built straight in the caller's return slot, so copying it there again
    // would copy the slot onto itself. Register identity is not enough to detect this: the
    // expression and the epilogue each materialize their own virtual register from the
    // hidden return pointer, so the storage symbol is what actually proves they alias.
    bool returnValueAlreadyInCallerStorage(CodeGen& codeGen, const CodeGenNodePayload& exprPayload)
    {
        return exprPayload.isAddress() &&
               exprPayload.runtimeStorageSym != nullptr &&
               CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, *exprPayload.runtimeStorageSym);
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

    Result emitLifecycleAfterIndirectReturnCopy(CodeGen& codeGen, TypeRef returnTypeRef, const CodeGenNodePayload& exprPayload, MicroReg outputStorageReg, CodeGen::LifecycleKind lifecycleKind)
    {
        if (!exprPayload.isAddress() || exprPayload.reg == outputStorageReg)
            return Result::Continue;
        if (!codeGen.hasLifecycle(returnTypeRef, lifecycleKind))
            return Result::Continue;
        return codeGen.emitLifecycle(returnTypeRef, lifecycleKind, outputStorageReg);
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
        const bool                returnValueIsInPlace       = returnValueAlreadyInCallerStorage(codeGen, exprPayload);

        // Returning a dead local or an owned temporary transfers ownership: the copy runs
        // 'opPostMove' instead of 'opPostCopy', and the moved-out local is not dropped.
        // Compiler-run persisted returns keep the copy semantics their machinery expects,
        // and a reference return borrows the local rather than consuming it.
        const SymbolVariable* moveOutVar          = nullptr;
        bool                  movesOwnedTemporary = false;
        auto                  copyLifecycleKind   = CodeGen::LifecycleKind::PostCopy;
        if (!needsPersistentCompilerReturn && !codeGen.typeMgr().get(returnTypeRef).isReference())
        {
            moveOutVar          = returnMoveOutSource(codeGen, exprRef);
            movesOwnedTemporary = returnSourceIsOwnedTemporary(codeGen, exprRef, exprPayload);
            if (moveOutVar != nullptr || movesOwnedTemporary)
                copyLifecycleKind = CodeGen::LifecycleKind::PostMove;
        }

        const SymbolVariable* previousMoveOutVar = codeGen.returnMoveOutVar();
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
                if (exprPayload.reg != outputStorageReg && !returnValueIsInPlace)
                {
                    CodeGenMemoryHelpers::emitMemCopy(codeGen, outputStorageReg, exprPayload.reg, normalizedRet.indirectSize);
                    SWC_RESULT(emitLifecycleAfterIndirectReturnCopy(codeGen, returnTypeRef, exprPayload, outputStorageReg, copyLifecycleKind));
                }
            }
            else if (!delayReturnMaterialization)
            {
                emitIndirectReturnValuePayload(codeGen, outputStorageReg, exprPayload.reg, normalizedRet.indirectSize);
                SWC_RESULT(emitLifecycleAfterIndirectReturnCopy(codeGen, returnTypeRef, exprPayload, outputStorageReg, copyLifecycleKind));
            }

            codeGen.setReturnMoveOutVar(moveOutVar);
            const Result deferredResult = codeGen.emitDeferredActionsForReturn();
            codeGen.setReturnMoveOutVar(previousMoveOutVar);
            SWC_RESULT(deferredResult);
            if (delayReturnMaterialization && needsPersistentCompilerReturn)
                CodeGenFunctionHelpers::emitPersistCompilerRunValue(codeGen, returnTypeRef, outputStorageReg, exprPayload.reg, codeGen.localStackBaseReg(), codeGen.localStackFrameSize());
            else if (delayReturnMaterialization && exprPayload.isAddress() && exprPayload.reg != outputStorageReg && !returnValueIsInPlace)
            {
                CodeGenMemoryHelpers::emitMemCopy(codeGen, outputStorageReg, exprPayload.reg, normalizedRet.indirectSize);
                SWC_RESULT(emitLifecycleAfterIndirectReturnCopy(codeGen, returnTypeRef, exprPayload, outputStorageReg, copyLifecycleKind));
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
            const TypeRef  exprTypeRef    = codeGen.viewType(exprRef).typeRef();
            if (!delayReturnMaterialization)
            {
                if (returnTypeInfo.isReference())
                {
                    const MicroReg referenceReg = materializeReferenceValueReg(codeGen, exprPayload, exprTypeRef);
                    if (referenceReg != returnValueReg)
                        builder.emitLoadRegReg(returnValueReg, referenceReg, MicroOpBits::B64);
                }
                else if (exprPayload.isAddress())
                    builder.emitLoadRegMem(returnValueReg, exprPayload.reg, 0, retBits);
                else
                    builder.emitLoadRegReg(returnValueReg, exprPayload.reg, retBits);
            }

            codeGen.setReturnMoveOutVar(moveOutVar);
            const Result deferredResult = codeGen.emitDeferredActionsForReturn();
            codeGen.setReturnMoveOutVar(previousMoveOutVar);
            SWC_RESULT(deferredResult);
            if (delayReturnMaterialization)
            {
                if (returnTypeInfo.isReference())
                {
                    const MicroReg referenceReg = materializeReferenceValueReg(codeGen, exprPayload, exprTypeRef);
                    if (referenceReg != returnValueReg)
                        builder.emitLoadRegReg(returnValueReg, referenceReg, MicroOpBits::B64);
                }
                else if (exprPayload.isAddress())
                    builder.emitLoadRegMem(returnValueReg, exprPayload.reg, 0, retBits);
                else
                    builder.emitLoadRegReg(returnValueReg, exprPayload.reg, retBits);
            }
            ABICall::materializeValueToReturnRegs(builder, callConvKind, returnValueReg, false, normalizedRet);
        }

        if (movesOwnedTemporary)
        {
            const SymbolVariable* sourceStorage = codeGen.runtimeStorageSymbol(exprRef);
            if (sourceStorage && codeGen.hasTemporaryDrop(*sourceStorage))
                codeGen.cancelTemporaryDrop(*sourceStorage);
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
        const AstNodeRef currentDeclRef = resolvedFunctionLikeDeclRef(codeGen, codeGen.curNodeRef());
        const AstNodeRef activeDeclRef  = resolvedFunctionLikeDeclRef(codeGen, codeGen.function().declNodeRef());
        return currentDeclRef == declRef && activeDeclRef == declRef;
    }

    FallibleTarget resolveFallibleTarget(CodeGen& codeGen)
    {
        FallibleTarget handlerTarget;
        if (tryResolveFallibleHandlerTarget(codeGen, codeGen.curNodeRef(), handlerTarget))
            return handlerTarget;

        for (size_t parentIndex = 0;; ++parentIndex)
        {
            const AstNodeRef parentRef = codeGen.visit().parentNodeRef(parentIndex);
            if (!parentRef.isValid())
                break;

            if (tryResolveFallibleHandlerTarget(codeGen, parentRef, handlerTarget))
                return handlerTarget;
        }

        for (size_t frameIndex = codeGen.frames().size(); frameIndex != 0; --frameIndex)
        {
            const CodeGenFrame& frame = codeGen.frames()[frameIndex - 1];
            if (!frame.hasCurrentInlineContext())
                continue;

            const CodeGenFrame::InlineContext& inlineCtx = frame.currentInlineContext();
            if (inlineCtx.payload && tryResolveFallibleHandlerTarget(codeGen, inlineCtx.payload->callRef, handlerTarget))
                return handlerTarget;
        }

        const AstNodeRef functionDeclRef = codeGen.viewZero(codeGen.function().declNodeRef()).nodeRef();
        SWC_ASSERT(functionDeclRef.isValid());
        CodeGenNodePayload& payload = ensureFallibleFunctionPayload(codeGen, functionDeclRef);
        if (!payload.fallibleFunctionFailLabel.isValid())
        {
            MicroBuilder& builder             = codeGen.builder();
            payload.fallibleFunctionFailLabel = builder.createLabel();
            payload.fallibleFunctionDoneLabel = builder.createLabel();
        }

        return {
            .kind      = FallibleTarget::Kind::FunctionReturn,
            .scopeRef  = functionDeclRef,
            .failLabel = payload.fallibleFunctionFailLabel,
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
                        SWC_RESULT(emitLifecycleAfterIndirectReturnCopy(codeGen, returnTypeRef, *exprPayload, outputStorageReg, CodeGen::LifecycleKind::PostCopy));
                    }
                    else
                    {
                        emitIndirectReturnValuePayload(codeGen, outputStorageReg, exprPayload->reg, normalizedRet.indirectSize);
                        SWC_RESULT(emitLifecycleAfterIndirectReturnCopy(codeGen, returnTypeRef, *exprPayload, outputStorageReg, CodeGen::LifecycleKind::PostCopy));
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
                SWC_RESULT(emitLifecycleAfterIndirectReturnCopy(codeGen, returnTypeRef, *exprPayload, outputStorageReg, CodeGen::LifecycleKind::PostCopy));
            }
            else
            {
                emitIndirectReturnValuePayload(codeGen, outputStorageReg, exprPayload->reg, normalizedRet.indirectSize);
                SWC_RESULT(emitLifecycleAfterIndirectReturnCopy(codeGen, returnTypeRef, *exprPayload, outputStorageReg, CodeGen::LifecycleKind::PostCopy));
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

    Result emitFallibleFunctionFailureReturn(CodeGen& codeGen)
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
            return raiseInternalCodeGenError(codeGen, "cannot materialize the synthesized fallible error return payload");

        return emitFunctionLikeReturnNoDefers(codeGen, symbolFunc, &zeroPayload);
    }

    Result emitFallibleDeferredActions(CodeGen& codeGen, const FallibleTarget& target)
    {
        if (target.kind == FallibleTarget::Kind::Handler)
            return codeGen.emitDeferredActionsUntilScopeRef(target.scopeRef);
        return codeGen.emitDeferredActionsForReturn();
    }

    // Runs the deferred actions a propagating failure unwinds through, with that failure parked
    // for their duration.
    //
    // Cleanup routinely dismisses failures of its own -- 'discard catch close()' is the ordinary
    // shape -- and a 'catch' both consumes the error in flight and clears the flag every fallible
    // call is tested against. Left alone, the cleanup therefore swallows the very failure it is
    // unwinding for; restored too early, in the 'catch' itself, the test that follows the guarded
    // call reads it and jumps out, so everything after that 'catch' never runs. Parking the error
    // across the whole deferred block is what keeps both halves right: the cleanup runs on a clean
    // error state, and the failure is exactly as it was when the jump finally happens.
    Result emitFallibleJump(CodeGen& codeGen)
    {
        const FallibleTarget target = resolveFallibleTarget(codeGen);

        if (!codeGen.hasDeferredStatements())
        {
            SWC_RESULT(emitFallibleDeferredActions(codeGen, target));
            codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, target.failLabel);
            return Result::Continue;
        }

        const SymbolFunction* pushErr = runtimeFunctionByKind(codeGen, IdentifierManager::RuntimeFunctionKind::PushErr);
        const SymbolFunction* popErr  = runtimeFunctionByKind(codeGen, IdentifierManager::RuntimeFunctionKind::PopErr);
        SWC_ASSERT(pushErr != nullptr && popErr != nullptr);
        if (!pushErr || !popErr)
            return raiseInternalCodeGenError(codeGen, "missing runtime helper '__pushErr' or '__popErr'");

        SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *pushErr, std::span<const MicroReg>{}));
        SWC_RESULT(emitFallibleDeferredActions(codeGen, target));
        SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *popErr, std::span<const MicroReg>{}));

        codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, target.failLabel);
        return Result::Continue;
    }

    Result codeGenFunctionLikePostNode(CodeGen& codeGen, AstNodeRef declRef, AstNodeRef bodyRef, bool hasExpressionBody)
    {
        declRef = resolvedFunctionLikeDeclRef(codeGen, declRef);
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

        CodeGenNodePayload* payload = fallibleFunctionPayload(codeGen, declRef);
        if (payload && payload->fallibleFunctionFailLabel.isValid())
        {
            MicroBuilder& builder = codeGen.builder();
            if (!codeGen.currentInstructionBlocksFallthrough())
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, payload->fallibleFunctionDoneLabel);

            builder.placeLabel(payload->fallibleFunctionFailLabel);
            SWC_RESULT(emitFallibleFunctionFailureReturn(codeGen));
            builder.placeLabel(payload->fallibleFunctionDoneLabel);
            payload->clearFallibleFunctionTarget();
        }

        return Result::Continue;
    }
}

Result CodeGenCallHelpers::emitFallibleFailureJump(CodeGen& codeGen)
{
    return emitFallibleJump(codeGen);
}

Result CodeGenCallHelpers::emitFallibleFailureJumpIfHasError(CodeGen& codeGen)
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
    SWC_RESULT(emitFallibleJump(codeGen));
    builder.placeLabel(continueLabel);
    return Result::Continue;
}

Result CodeGenFunctionHelpers::emitFallibleWrapperPreNode(CodeGen& codeGen, AstNodeRef nodeRef)
{
    CodeGenNodePayload* payload = fallibleWrapperOwnerPayload(codeGen, nodeRef);
    if (!payload || !isHandledFallibleContext(payload->fallibleWrapperTokenId))
        return Result::Continue;

    MicroBuilder& builder      = codeGen.builder();
    payload->fallibleFailLabel = builder.createLabel();
    payload->fallibleDoneLabel = builder.createLabel();
    codeGen.pushDeferScope(nodeRef);

    const SymbolFunction* runtimePushErr = runtimeFunctionByKind(codeGen, IdentifierManager::RuntimeFunctionKind::PushErr);
    SWC_ASSERT(runtimePushErr != nullptr);
    if (!runtimePushErr)
        return raiseInternalCodeGenError(codeGen, "missing runtime helper '__pushErr'", nodeRef);
    SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *runtimePushErr, std::span<const MicroReg>{}));

    // 'catch e as err': reset the capture slot to null before the call, so a success leaves 'err'
    // null; the failure path overwrites it (see emitFallibleWrapperPostNode / __bindErr).
    const CodeGenLoweringPayload* lowering = codeGen.loweringPayload(nodeRef);
    if (lowering && lowering->errBindingSym)
    {
        const SymbolFunction* clearErr = runtimeFunctionByKind(codeGen, IdentifierManager::RuntimeFunctionKind::ClearErr);
        SWC_ASSERT(clearErr != nullptr);
        if (!clearErr)
            return raiseInternalCodeGenError(codeGen, "missing runtime helper '__clearErr'", nodeRef);
        const MicroReg dstReg  = codeGen.resolveLocalStackPayload(*lowering->errBindingSym).reg;
        const MicroReg args[1] = {dstReg};
        SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *clearErr, std::span{args, 1}));
    }

    return Result::Continue;
}

Result CodeGenFunctionHelpers::emitFallibleWrapperPostNode(CodeGen& codeGen, AstNodeRef nodeRef)
{
    CodeGenNodePayload* payload = fallibleWrapperOwnerPayload(codeGen, nodeRef);
    if (!payload || !payload->fallibleFailLabel.isValid() || !isHandledFallibleContext(payload->fallibleWrapperTokenId))
        return Result::Continue;

    const FallibleHandlerKind kind           = fallibleHandlerKind(payload->fallibleWrapperTokenId);
    const AstNodeRef          ownerRef       = payload->fallibleWrapperOwnerRef.isValid() ? payload->fallibleWrapperOwnerRef : nodeRef;
    const TypeRef             resultType     = codeGen.curViewType().typeRef();
    const bool                hasResult      = resultType.isValid() && resultType != codeGen.typeMgr().typeVoid();
    const bool                hasFallthrough = !codeGen.currentInstructionBlocksFallthrough();
    MicroBuilder&             builder        = codeGen.builder();
    SWC_ASSERT(kind != FallibleHandlerKind::None);

    if (hasFallthrough)
        SWC_RESULT(emitFallibleCleanup(codeGen, kind, ownerRef, false));

    SWC_RESULT(codeGen.popDeferScope());
    if (hasFallthrough && !codeGen.currentInstructionBlocksFallthrough())
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, payload->fallibleDoneLabel);

    builder.placeLabel(payload->fallibleFailLabel);
    SWC_RESULT(emitFallibleCleanup(codeGen, kind, ownerRef, true));
    if (hasResult)
    {
        const CodeGenNodePayload& resultPayload = codeGen.payload(nodeRef);

        // An address-backed result register is defined by the success path, and
        // when the managed expression never falls through — an inlined callee
        // whose only exit is 'fail' — that definition is never emitted at all.
        // Both this zeroing and every consumer after the join would then read an
        // undefined register. Define it on this path too, from the storage
        // symbol: the same address the success path computes, rooted at the
        // local stack base whose definition dominates both arms.
        if (resultPayload.isAddress() && resultPayload.runtimeStorageSym && codeGen.localStackBaseReg().isValid() &&
            resultPayload.runtimeStorageSym->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
        {
            builder.emitLoadAddressRegMem(resultPayload.reg, codeGen.localStackBaseReg(), resultPayload.runtimeStorageSym->offset(), MicroOpBits::B64);
        }

        SWC_RESULT(emitZeroFallibleExprResult(codeGen, resultPayload, resultType));
    }

    // 'catch e as err': seed the captured local from the still-valid curError (the Catch cleanup
    // retained it) on the failure path. The fat 'any' copy lives in '__bindErr'; here we only pass
    // the slot. Works for both the statement and the 'let x = catch f() as err' expression forms.
    const CodeGenLoweringPayload* lowering = codeGen.loweringPayload(ownerRef);
    const SymbolVariable* const   errSym   = lowering ? lowering->errBindingSym : nullptr;
    if (errSym)
    {
        const SymbolFunction* bindErr = runtimeFunctionByKind(codeGen, IdentifierManager::RuntimeFunctionKind::BindErr);
        SWC_ASSERT(bindErr != nullptr);
        if (!bindErr)
            return raiseInternalCodeGenError(codeGen, "missing runtime helper '__bindErr'", nodeRef);
        const MicroReg dstReg  = codeGen.resolveLocalStackPayload(*errSym).reg;
        const MicroReg args[1] = {dstReg};
        SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *bindErr, std::span{args, 1}));
    }

    // 'catch e else { H }': the anonymous lazy handler runs here (failure path only).
    if (codeGen.node(ownerRef).is(AstNodeId::ErrorManagementStmt))
    {
        const AstNodeRef handlerRef = codeGen.node(ownerRef).cast<AstErrorManagementStmt>().nodeHandlerRef;
        if (handlerRef.isValid())
            SWC_RESULT(codeGen.emitNodeNow(handlerRef));
    }

    // 'catch' always dismisses the error: it has been handled here, so it must no longer count as
    // in-flight for '#fail'/'#nofail' defers. The only way to keep the error is to capture its value
    // with 'as err' (which copied it above, via __bindErr, before this clear). There is no lingering
    // global error state to observe — the error is gone unless a local holds a copy.
    if (kind == FallibleHandlerKind::Catch)
        SWC_RESULT(emitRuntimeHelperCallWithNoArgs(codeGen, IdentifierManager::RuntimeFunctionKind::EndErr, "missing runtime helper '__endErr'", nodeRef));

    builder.placeLabel(payload->fallibleDoneLabel);
    clearFallibleWrapperPayload(*payload);
    return Result::Continue;
}

Result AstFunctionDecl::codeGenPostNode(CodeGen& codeGen) const
{
    return codeGenFunctionLikePostNode(codeGen, codeGen.curNodeRef(), nodeBodyRef, hasFlag(AstFunctionFlagsE::Short));
}

Result AstFunctionExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const AstNodeRef declRef = resolvedFunctionLikeDeclRef(codeGen, codeGen.curNodeRef());
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
    const AstNodeRef declRef = resolvedFunctionLikeDeclRef(codeGen, codeGen.curNodeRef());
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

Result AstErrorManagementExpr::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef resolvedChildRef = codeGen.viewZero(childRef).nodeRef();
    const AstNodeRef managedExprRef   = codeGen.viewZero(nodeExprRef).nodeRef();
    if (resolvedChildRef == managedExprRef)
        SWC_RESULT(CodeGenFunctionHelpers::emitFallibleWrapperPreNode(codeGen, codeGen.curNodeRef()));

    return Result::Continue;
}

Result AstErrorManagementExpr::codeGenPostNode(CodeGen& codeGen) const
{
    SWC_RESULT(emitNotNullRuntimeSafety(codeGen, codeGen.curNodeRef(), nodeExprRef));
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeExprRef, codeGen.transparentPayloadTypeRef());
    return CodeGenFunctionHelpers::emitFallibleWrapperPostNode(codeGen, codeGen.curNodeRef());
}

Result AstErrorManagementStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    // 'catch e else { H }': skip the handler in the normal traversal so it is not emitted
    // on the success path; it is generated lazily inside the failure block instead.
    if (nodeHandlerRef.isValid() && childRef == nodeHandlerRef)
        return Result::SkipChildren;

    const AstNodeRef resolvedChildRef = codeGen.viewZero(childRef).nodeRef();
    const AstNodeRef managedBodyRef   = codeGen.viewZero(nodeBodyRef).nodeRef();
    if (resolvedChildRef == managedBodyRef)
        SWC_RESULT(CodeGenFunctionHelpers::emitFallibleWrapperPreNode(codeGen, codeGen.curNodeRef()));

    return Result::Continue;
}

Result AstErrorManagementStmt::codeGenPostNode(CodeGen& codeGen)
{
    return CodeGenFunctionHelpers::emitFallibleWrapperPostNode(codeGen, codeGen.curNodeRef());
}

Result AstFailExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const TypeRef resultTypeRef = codeGen.curViewType().typeRef();
    if (resultTypeRef.isValid() && resultTypeRef != codeGen.typeMgr().typeVoid())
    {
        const CodeGenNodePayload& resultPayload = usesAddressBackedFallibleExprResult(codeGen, resultTypeRef)
                                                      ? codeGen.setPayloadAddressReg(codeGen.curNodeRef(), codeGen.runtimeStorageAddressReg(codeGen.curNodeRef()), resultTypeRef)
                                                      : codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        SWC_RESULT(emitZeroFallibleExprResult(codeGen, resultPayload, resultTypeRef));
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
        return raiseInternalCodeGenError(codeGen, "cannot materialize the 'fail' value type info payload", codeGen.curNodeRef());

    const std::array args = {storageReg, typeInfoPayload.reg};
    SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *runtimeSetErrRaw, args));
    return CodeGenCallHelpers::emitFallibleFailureJump(codeGen);
}

SWC_END_NAMESPACE();
