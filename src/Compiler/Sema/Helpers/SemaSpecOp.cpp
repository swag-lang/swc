#include "pch.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Index.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
SWC_BEGIN_NAMESPACE();

namespace
{
    Result validateSpecOpSignature(Sema& sema, const SymbolStruct& owner, SymbolFunction& sym, SpecOpKind kind);
    Result collectSpecOpCandidates(Sema& sema, const SymbolStruct& ownerStruct, IdentifierRef idRef, std::span<const AstNodeRef> genericArgNodes, SmallVector<Symbol*>& outCandidates);

    std::string_view specOpSignatureHint(SpecOpKind kind)
    {
        switch (kind)
        {
            case SpecOpKind::OpDrop:
                return "mtd opDrop() -> void";
            case SpecOpKind::OpPostCopy:
                return "mtd opPostCopy() -> void";
            case SpecOpKind::OpPostMove:
                return "mtd opPostMove() -> void";
            case SpecOpKind::OpCount:
                return "mtd opCount() -> u64";
            case SpecOpKind::OpData:
                return "mtd opData() -> *<type>";
            case SpecOpKind::OpCast:
                return "mtd opCast() -> <type>";
            case SpecOpKind::OpEquals:
                return "mtd opEquals(value: <type>) -> bool";
            case SpecOpKind::OpCmp:
                return "mtd opCmp(value: <type>) -> s32";
            case SpecOpKind::OpBinary:
                return "mtd(op: string) const opBinary(other: <type>) -> <struct>";
            case SpecOpKind::OpUnary:
                return "mtd(op: string) const opUnary() -> <struct>";
            case SpecOpKind::OpAssign:
                return "mtd(op: string) opAssign(value: <type>) -> void";
            case SpecOpKind::OpAffect:
                return "mtd opAffect(value: <type>) -> void";
            case SpecOpKind::OpAffectLiteral:
                return "mtd(suffix: string) opAffectLiteral(value: <type>) -> void";
            case SpecOpKind::OpSlice:
                return "mtd opSlice(low: u64, up: u64) -> <string or slice>";
            case SpecOpKind::OpIndex:
                return "mtd opIndex(index: <type>) -> <type>";
            case SpecOpKind::OpIndexAssign:
                return "mtd(op: string) opIndexAssign(index: <type>, value: <type>) -> void";
            case SpecOpKind::OpIndexAffect:
                return "mtd opIndexAffect(index: <type>, value: <type>) -> void";
            case SpecOpKind::OpVisit:
                return "mtd(ptr: bool, back: bool) opVisit(stmt: #code) -> void";
            case SpecOpKind::None:
            case SpecOpKind::Invalid:
            default:
                return "valid special function signature";
        }
    }

    TypeRef unwrapAlias(TaskContext& ctx, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return typeRef;
        return ctx.typeMgr().get(typeRef).unwrap(ctx, typeRef, TypeExpandE::Alias);
    }

    TypeRef unwrapPointerOrRef(TaskContext& ctx, TypeRef typeRef)
    {
        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isReference() || type.isAnyPointer())
            return unwrapAlias(ctx, type.payloadTypeRef());
        return unwrapAlias(ctx, typeRef);
    }

    bool isSpecOpReceiver(TaskContext& ctx, const SymbolStruct& owner, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (!type.isReference())
            return false;

        return unwrapAlias(ctx, type.payloadTypeRef()) == unwrapAlias(ctx, owner.typeRef());
    }

    bool isConstSpecOpReceiver(TaskContext& ctx, const SymbolStruct& owner, TypeRef typeRef)
    {
        if (!isSpecOpReceiver(ctx, owner, typeRef))
            return false;

        return ctx.typeMgr().get(typeRef).isConst();
    }

    bool isOpBinarySecondParamImmutable(TaskContext& ctx, const SymbolFunction& sym, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isReference() || type.isPointerLike())
            return type.isConst();

        if (sym.isGenericRoot())
            return false;

        if (!type.isStruct() && !type.isArray() && !type.isAggregate())
            return true;

        const CallConv&                        callConv   = CallConv::get(sym.callConvKind());
        const ABITypeNormalize::NormalizedType normalized = ABITypeNormalize::normalize(ctx, callConv, typeRef, ABITypeNormalize::Usage::Argument);
        return !normalized.isIndirect;
    }

    std::span<const TokenId> expectedSpecOpGenericValueTypes(SpecOpKind kind)
    {
        static constexpr TokenId K_STRING[] = {TokenId::TypeString};
        static constexpr TokenId K_BOOL2[]  = {TokenId::TypeBool, TokenId::TypeBool};

        switch (kind)
        {
            case SpecOpKind::OpBinary:
            case SpecOpKind::OpUnary:
            case SpecOpKind::OpAssign:
            case SpecOpKind::OpAffectLiteral:
            case SpecOpKind::OpIndexAssign:
                return K_STRING;

            case SpecOpKind::OpVisit:
                return K_BOOL2;

            default:
                return {};
        }
    }

    const AstFunctionDecl* specOpDeclForGenericSignature(const SymbolFunction& sym)
    {
        const SymbolFunction* root = &sym;
        if (sym.isGenericInstance() && sym.genericRootSym())
            root = sym.genericRootSym();

        return root->decl() ? root->decl()->safeCast<AstFunctionDecl>() : nullptr;
    }

    bool hasSpecOpGenericValueType(Sema& sema, AstNodeRef typeRef, TokenId expectedType)
    {
        if (typeRef.isInvalid())
            return false;

        const AstNode& typeNode = sema.node(typeRef);
        if (typeNode.isNot(AstNodeId::BuiltinType))
            return false;

        return sema.token(typeNode.codeRef()).id == expectedType;
    }

    bool hasSpecOpGenericSignature(Sema& sema, const SymbolFunction& sym, SpecOpKind kind)
    {
        const auto                                 expected = expectedSpecOpGenericValueTypes(kind);
        const auto*                                decl     = specOpDeclForGenericSignature(sym);
        SmallVector<SemaGeneric::GenericParamDesc> params;

        if (!decl)
            return expected.empty();

        if (!decl->spanGenericParamsRef.isValid())
            return expected.empty();

        SemaGeneric::collectGenericParams(sema, decl->spanGenericParamsRef, params);
        if (expected.empty())
            return false;
        if (params.size() != expected.size())
            return false;

        for (size_t i = 0; i < params.size(); ++i)
        {
            if (params[i].kind != SemaGeneric::GenericParamKind::Value)
                return false;
            if (params[i].defaultRef.isValid())
                return false;
            if (!hasSpecOpGenericValueType(sema, params[i].explicitType, expected[i]))
                return false;
        }

        return true;
    }

    CodeGenNodePayload& ensureCodeGenNodePayload(Sema& sema, AstNodeRef nodeRef)
    {
        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(nodeRef);
        if (payload)
            return *payload;

        payload = sema.compiler().allocate<CodeGenNodePayload>();
        sema.setCodeGenPayload(nodeRef, payload);
        return *payload;
    }

    Result completeRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        if (auto* ownerFunction = sema.currentFunction(); ownerFunction && typeRef.isValid())
        {
            const TypeInfo& symType = sema.typeMgr().get(typeRef);
            SWC_RESULT(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
            ownerFunction->addLocalVariable(sema.ctx(), &symVar);
        }

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    SymbolVariable& registerUniqueRuntimeStorageSymbol(Sema& sema, const AstNode& node, std::string_view privateName)
    {
        TaskContext&        ctx         = sema.ctx();
        const IdentifierRef idRef       = SemaHelpers::getUniqueIdentifier(sema, privateName);
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();
        auto*               symVariable = Symbol::make<SymbolVariable>(ctx, &node, node.tokRef(), idRef, flags);

        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(symVariable);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            SWC_ASSERT(symMap != nullptr);
            symMap->addSymbol(ctx, symVariable, true);
        }

        return *symVariable;
    }

    Result attachRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, TypeRef storageTypeRef)
    {
        const auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (payload && payload->runtimeStorageSym != nullptr)
            return Result::Continue;
        if (storageTypeRef.isInvalid())
            return Result::Continue;

        if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
        {
            ensureCodeGenNodePayload(sema, sema.curNodeRef()).runtimeStorageSym = boundStorage;
            return Result::Continue;
        }

        auto& storageSym = registerUniqueRuntimeStorageSymbol(sema, node, "__spec_op_runtime_storage");
        storageSym.registerAttributes(sema);
        storageSym.setDeclared(sema.ctx());
        SWC_RESULT(Match::ghosting(sema, storageSym));
        SWC_RESULT(completeRuntimeStorageSymbol(sema, storageSym, storageTypeRef));

        ensureCodeGenNodePayload(sema, sema.curNodeRef()).runtimeStorageSym = &storageSym;
        return Result::Continue;
    }

    TypeRef syntheticCallRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn)
    {
        if (sema.isGlobalScope())
            return TypeRef::invalid();

        const TypeRef returnTypeRef = calledFn.returnTypeRef();
        if (!returnTypeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& returnType = sema.typeMgr().get(returnTypeRef);
        if (returnType.isVoid())
            return TypeRef::invalid();

        const CallConv&                        callConv      = CallConv::get(calledFn.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(sema.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
        if (!normalizedRet.isIndirect)
            return TypeRef::invalid();

        const TypeRef storageTypeRef = returnType.unwrap(sema.ctx(), returnTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (storageTypeRef.isValid())
            return storageTypeRef;

        return returnTypeRef;
    }

    AstNodeRef makeSyntheticStringConstantArg(Sema& sema, const SourceCodeRef& codeRef, std::string_view value)
    {
        const auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::StringLiteral>(codeRef.tokRef);
        nodePtr->setCodeRef(codeRef);

        const TaskContext&  ctx         = sema.ctx();
        const ConstantValue constant    = ConstantValue::makeString(ctx, value);
        const ConstantRef   constantRef = sema.cstMgr().addConstant(ctx, constant);
        sema.setType(nodeRef, sema.typeMgr().typeString());
        sema.setConstant(nodeRef, constantRef);
        sema.setIsValue(*nodePtr);
        return nodeRef;
    }

    std::string_view assignGenericOpString(TokenId tokId)
    {
        if (tokId == TokenId::SymEqual)
            return {};

        return Token::toName(tokId);
    }

    bool isSupportedAssignSpecOp(TokenId tokId)
    {
        switch (tokId)
        {
            case TokenId::SymEqual:
            case TokenId::SymPlusEqual:
            case TokenId::SymMinusEqual:
            case TokenId::SymAsteriskEqual:
            case TokenId::SymSlashEqual:
            case TokenId::SymAmpersandEqual:
            case TokenId::SymPipeEqual:
            case TokenId::SymCircumflexEqual:
            case TokenId::SymPercentEqual:
            case TokenId::SymLowerLowerEqual:
            case TokenId::SymGreaterGreaterEqual:
                return true;

            default:
                return false;
        }
    }

    const SymbolStruct* structSpecOpOwner(Sema& sema, const SemaNodeView& view)
    {
        if (!view.type())
            return nullptr;

        TypeRef         unwrappedTypeRef = view.typeRef();
        const TypeInfo& valueType        = sema.typeMgr().get(unwrappedTypeRef);
        if (valueType.isReference())
            unwrappedTypeRef = unwrapAlias(sema.ctx(), valueType.payloadTypeRef());
        else
            unwrappedTypeRef = unwrapAlias(sema.ctx(), unwrappedTypeRef);
        if (!unwrappedTypeRef.isValid())
            unwrappedTypeRef = view.typeRef();

        const TypeInfo& type = sema.typeMgr().get(unwrappedTypeRef);
        if (!type.isStruct())
            return nullptr;

        return &type.payloadSymStruct();
    }

    Result collectAssignSpecOpCandidates(Sema& sema, const SymbolStruct& ownerStruct, const SourceCodeRef& codeRef, TokenId tokId, SmallVector<Symbol*>& outCandidates)
    {
        outCandidates.clear();
        if (!isSupportedAssignSpecOp(tokId))
            return Result::Continue;

        const bool          isSimpleAssign = tokId == TokenId::SymEqual;
        const IdentifierRef opId           = isSimpleAssign ? sema.idMgr().predefined(IdentifierManager::PredefinedName::OpAffect) : sema.idMgr().predefined(IdentifierManager::PredefinedName::OpAssign);
        AstNodeRef          genericArg     = AstNodeRef::invalid();
        if (!isSimpleAssign)
        {
            const std::string_view opString = assignGenericOpString(tokId);
            SWC_ASSERT(!opString.empty());
            genericArg = makeSyntheticStringConstantArg(sema, codeRef, opString);
        }

        if (genericArg.isValid())
            return collectSpecOpCandidates(sema, ownerStruct, opId, std::span{&genericArg, 1}, outCandidates);
        return collectSpecOpCandidates(sema, ownerStruct, opId, std::span<const AstNodeRef>{}, outCandidates);
    }

    void splitMutableReceiverCandidates(Sema& sema, std::span<Symbol*> inCandidates, SmallVector<Symbol*>& outMutableCandidates, SmallVector<Symbol*>& outConstCandidates)
    {
        outMutableCandidates.clear();
        outConstCandidates.clear();

        for (Symbol* sym : inCandidates)
        {
            auto* const symFunc = sym ? sym->safeCast<SymbolFunction>() : nullptr;
            if (!symFunc || symFunc->parameters().empty())
            {
                outConstCandidates.push_back(sym);
                continue;
            }

            const SymbolVariable* const receiver = symFunc->parameters().front();
            if (receiver && !sema.typeMgr().get(receiver->typeRef()).isConst())
                outMutableCandidates.push_back(sym);
            else
                outConstCandidates.push_back(sym);
        }
    }

    Result collectIndexAssignSpecOpCandidates(Sema& sema, const SymbolStruct& ownerStruct, const SourceCodeRef& codeRef, TokenId tokId, SmallVector<Symbol*>& outCandidates)
    {
        outCandidates.clear();
        if (!isSupportedAssignSpecOp(tokId))
            return Result::Continue;

        const bool          isSimpleAssign = tokId == TokenId::SymEqual;
        const IdentifierRef opId           = isSimpleAssign ? sema.idMgr().predefined(IdentifierManager::PredefinedName::OpIndexAffect) : sema.idMgr().predefined(IdentifierManager::PredefinedName::OpIndexAssign);
        AstNodeRef          genericArg     = AstNodeRef::invalid();
        if (!isSimpleAssign)
        {
            const std::string_view opString = assignGenericOpString(tokId);
            SWC_ASSERT(!opString.empty());
            genericArg = makeSyntheticStringConstantArg(sema, codeRef, opString);
        }

        if (genericArg.isValid())
            return collectSpecOpCandidates(sema, ownerStruct, opId, std::span{&genericArg, 1}, outCandidates);
        return collectSpecOpCandidates(sema, ownerStruct, opId, std::span<const AstNodeRef>{}, outCandidates);
    }

    bool canExplicitlySpecializeSpecOp(Sema& sema, const SymbolFunction& symFunc, std::span<const AstNodeRef> genericArgNodes)
    {
        if (!symFunc.isGenericRoot() || genericArgNodes.empty())
            return false;

        const auto* decl = symFunc.decl() ? symFunc.decl()->safeCast<AstFunctionDecl>() : nullptr;
        if (!decl || !decl->spanGenericParamsRef.isValid())
            return false;

        SmallVector<SemaGeneric::GenericParamDesc> params;
        SemaGeneric::collectGenericParams(sema, decl->spanGenericParamsRef, params);
        if (genericArgNodes.size() > params.size())
            return false;

        for (size_t i = 0; i < genericArgNodes.size(); ++i)
        {
            if (params[i].kind != SemaGeneric::GenericParamKind::Value)
                return false;
        }

        return true;
    }

    Result collectSpecOpCandidates(Sema& sema, const SymbolStruct& ownerStruct, IdentifierRef idRef, std::span<const AstNodeRef> genericArgNodes, SmallVector<Symbol*>& outCandidates)
    {
        outCandidates.clear();

        for (const SymbolImpl* symImpl : ownerStruct.impls())
        {
            if (!symImpl || symImpl->isIgnored())
                continue;

            for (SymbolFunction* symFunc : symImpl->specOps())
            {
                if (!symFunc || symFunc->idRef() != idRef)
                    continue;

                // Parallel sema can expose special operator methods before their signature is typed.
                // Wait for concrete overloads here so operator resolution never ranks half-built methods.
                if (!symFunc->isGenericRoot())
                    SWC_RESULT(sema.waitTyped(symFunc, symFunc->codeRef()));

                if (!canExplicitlySpecializeSpecOp(sema, *symFunc, genericArgNodes))
                {
                    outCandidates.push_back(symFunc);
                    continue;
                }

                // When specializing overloaded operators, a failed specialization (e.g. an #error
                // directive for an unsupported operation) means this overload does not handle the
                // requested operator.  Suppress diagnostics and skip the candidate instead of
                // aborting the entire resolution.
                SymbolFunction* specialized = nullptr;
                const bool      savedSilent = sema.ctx().silentDiagnostic();
                sema.ctx().setSilentDiagnostic(true);
                const Result specResult = SemaGeneric::instantiateFunctionExplicit(sema, *symFunc, genericArgNodes, specialized);
                sema.ctx().setSilentDiagnostic(savedSilent);
                if (specResult == Result::Pause)
                    return Result::Pause;
                if (specResult != Result::Continue)
                    continue;
                if (specialized)
                {
                    SWC_RESULT(sema.waitSemaCompleted(specialized, specialized->codeRef()));
                    SWC_RESULT(validateSpecOpSignature(sema, ownerStruct, *specialized, specialized->specOpKind()));
                    outCandidates.push_back(specialized);
                }
            }
        }

        return Result::Continue;
    }

    Result resolveSyntheticCall(Sema&                 sema,
                                const AstNode&        node,
                                std::span<Symbol*>    candidates,
                                std::span<AstNodeRef> args,
                                AstNodeRef            ufcsArg,
                                bool                  allowNoMatch = false,
                                bool*                 outMatched   = nullptr)
    {
        if (outMatched)
            *outMatched = false;

        SmallVector<ResolvedCallArgument> resolvedArgs;
        const SemaNodeView                calleeView(sema, sema.curNodeRef(), SemaNodeViewPartE::Node);
        if (allowNoMatch)
        {
            const bool savedSilent = sema.ctx().silentDiagnostic();
            sema.ctx().setSilentDiagnostic(true);
            const Result matchResult = Match::resolveFunctionCandidates(sema, calleeView, candidates, args, ufcsArg, &resolvedArgs);
            sema.ctx().setSilentDiagnostic(savedSilent);
            if (matchResult == Result::Pause)
                return Result::Pause;
            if (matchResult != Result::Continue)
                return Result::Continue;
        }
        else
        {
            SWC_RESULT(Match::resolveFunctionCandidates(sema, calleeView, candidates, args, ufcsArg, &resolvedArgs));
        }

        if (outMatched)
            *outMatched = true;
        sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);

        auto& calledFn = sema.curViewSymbol().sym()->cast<SymbolFunction>();
        SemaHelpers::addCurrentFunctionCallDependency(sema, &calledFn);

        SWC_RESULT(SemaJIT::tryRunConstCall(sema, calledFn, sema.curNodeRef(), resolvedArgs.span()));
        if (sema.viewConstant(sema.curNodeRef()).hasConstant())
            return Result::Continue;

        SWC_RESULT(SemaInline::tryInlineCall(sema, sema.curNodeRef(), calledFn, args, ufcsArg));
        SWC_RESULT(attachRuntimeStorageIfNeeded(sema, node, syntheticCallRuntimeStorageTypeRef(sema, calledFn)));
        return Result::Continue;
    }

    Result reportSpecOpError(Sema& sema, const SymbolFunction& sym, SpecOpKind kind)
    {
        const auto& codeRef = sym.codeRef();
        Diagnostic  diag    = Diagnostic::get(DiagnosticId::sema_err_spec_op_signature, sema.ast().srcView().fileRef());
        diag.last().addSpan(sema.srcView(codeRef.srcViewRef).tokenCodeRange(sema.ctx(), codeRef.tokRef), "", DiagnosticSeverity::Error);
        SemaError::setReportArguments(sema, diag, codeRef);
        SemaError::setReportArguments(sema, diag, &sym);
        diag.addNote(DiagnosticId::sema_note_expected_signature);
        diag.last().addArgument(Diagnostic::ARG_VALUE, specOpSignatureHint(kind));
        diag.report(sema.ctx());
        return Result::Continue;
    }

    Result validateSpecOpSignature(Sema& sema, const SymbolStruct& owner, SymbolFunction& sym, SpecOpKind kind)
    {
        TaskContext&       ctx     = sema.ctx();
        const TypeManager& typeMgr = sema.typeMgr();
        const auto&        params  = sym.parameters();

        if (!hasSpecOpGenericSignature(sema, sym, kind))
            return reportSpecOpError(sema, sym, kind);

        if (params.empty())
            return reportSpecOpError(sema, sym, kind);

        if (!isSpecOpReceiver(ctx, owner, params[0]->typeRef()))
            return reportSpecOpError(sema, sym, kind);

        const TypeRef returnTypeRef = unwrapAlias(ctx, sym.returnTypeRef());
        if (returnTypeRef.isInvalid())
            return reportSpecOpError(sema, sym, kind);

        const TypeInfo& returnType       = typeMgr.get(returnTypeRef);
        const bool      receiverIsConst  = isConstSpecOpReceiver(ctx, owner, params[0]->typeRef());
        const bool      returnIsVoid     = returnType.isVoid();
        const bool      returnIsStruct   = returnType.isStruct() && &returnType.payloadSymStruct() == &owner;
        const bool      returnIsPointer  = returnType.isAnyPointer();
        const bool      returnIsNotVoid  = !returnIsVoid;
        const bool      returnIsStrSlice = returnType.isString() || returnType.isSlice();
        const TypeRef   u64TypeRef       = unwrapAlias(ctx, typeMgr.typeU64());
        const TypeRef   boolTypeRef      = unwrapAlias(ctx, typeMgr.typeBool());
        const TypeRef   s32TypeRef       = unwrapAlias(ctx, typeMgr.typeS32());

        switch (kind)
        {
            case SpecOpKind::None:
                return Result::Continue;
            case SpecOpKind::Invalid:
                return reportSpecOpError(sema, sym, kind);
            case SpecOpKind::OpDrop:
            case SpecOpKind::OpPostCopy:
            case SpecOpKind::OpPostMove:
                if (params.size() != 1 || !returnIsVoid)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpCount:
                if (params.size() != 1 || returnTypeRef != u64TypeRef)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpData:
                if (params.size() != 1 || !returnIsPointer)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpCast:
                if (params.size() != 1 || !returnIsNotVoid)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpEquals:
                if (params.size() != 2 || returnTypeRef != boolTypeRef)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpCmp:
                if (params.size() != 2 || returnTypeRef != s32TypeRef)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpBinary:
                if (params.size() != 2 || !receiverIsConst || !isOpBinarySecondParamImmutable(ctx, sym, params[1]->typeRef()) || !returnIsStruct)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpUnary:
                if (params.size() != 1 || !receiverIsConst || !returnIsStruct)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpAssign:
                if (params.size() != 2 || !returnIsVoid)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpAffect:
            case SpecOpKind::OpAffectLiteral:
            {
                if (params.size() != 2 || !returnIsVoid)
                    return reportSpecOpError(sema, sym, kind);

                const TypeRef   underlying = unwrapPointerOrRef(ctx, params[1]->typeRef());
                const TypeInfo& type       = typeMgr.get(underlying);
                if (type.isStruct() && &type.payloadSymStruct() == &owner)
                    return reportSpecOpError(sema, sym, kind);

                break;
            }

            case SpecOpKind::OpSlice:
                if (params.size() != 3 || !returnIsStrSlice || unwrapAlias(ctx, params[1]->typeRef()) != u64TypeRef || unwrapAlias(ctx, params[2]->typeRef()) != u64TypeRef)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpIndex:
                if (params.size() < 2 || !returnIsNotVoid)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpIndexAssign:
            case SpecOpKind::OpIndexAffect:
                if (params.size() < 3 || !returnIsVoid)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpVisit:
                if (params.size() != 2 || !returnIsVoid)
                    return reportSpecOpError(sema, sym, kind);
                break;
        }

        return Result::Continue;
    }

    bool allowsSpecOpOverload(SpecOpKind kind)
    {
        switch (kind)
        {
            case SpecOpKind::OpCast:
            case SpecOpKind::OpEquals:
            case SpecOpKind::OpCmp:
            case SpecOpKind::OpBinary:
            case SpecOpKind::OpAssign:
            case SpecOpKind::OpAffect:
            case SpecOpKind::OpAffectLiteral:
            case SpecOpKind::OpIndex:
            case SpecOpKind::OpIndexAssign:
            case SpecOpKind::OpIndexAffect:
                return true;
            default:
                return false;
        }
    }

    bool isSpecOpInImplFor(const SymbolFunction& sym)
    {
        const SymbolMap* symMap = sym.ownerSymMap();
        if (!symMap)
            return false;
        if (!symMap->isImpl())
            return false;
        return symMap->cast<SymbolImpl>().isForInterface();
    }

}

Result SemaSpecOp::validateSymbol(Sema& sema, SymbolFunction& sym)
{
    const IdentifierRef      idRef = sym.idRef();
    const IdentifierManager& idMgr = sema.idMgr();

    const SpecOpKind kind = sym.specOpKind();
    if (kind == SpecOpKind::None)
        return Result::Continue;
    if (kind == SpecOpKind::Invalid)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_spec_op_unknown, sym);
        diag.addNote(DiagnosticId::sema_note_spec_op_reserved);
        diag.report(sema.ctx());
        return Result::Error;
    }

    const std::string_view name = idMgr.get(idRef).name;
    if (kind == SpecOpKind::OpVisit && name.size() > std::string_view("opVisit").size())
    {
        const char variantStart = name[std::string_view("opVisit").size()];
        if (std::isupper(static_cast<unsigned char>(variantStart)) == 0)
            return reportSpecOpError(sema, sym, kind);
    }

    const SymbolStruct* ownerStruct = sym.ownerStruct();
    if (!ownerStruct)
        return SemaError::raise(sema, DiagnosticId::sema_err_spec_op_outside_impl, sym);
    if (isSpecOpInImplFor(sym))
        return SemaError::raise(sema, DiagnosticId::sema_err_spec_op_in_impl_for, sym);
    if (sym.isGenericRoot() && !sym.isGenericInstance())
    {
        if (!hasSpecOpGenericSignature(sema, sym, kind))
            return reportSpecOpError(sema, sym, kind);
        return Result::Continue;
    }

    return validateSpecOpSignature(sema, *ownerStruct, sym, kind);
}

Result SemaSpecOp::registerSymbol(Sema& sema, SymbolFunction& sym)
{
    const SpecOpKind kind = sym.specOpKind();
    if (kind == SpecOpKind::None)
        return Result::Continue;
    if (kind == SpecOpKind::Invalid)
        return Result::Continue;

    SymbolStruct* ownerStruct = sym.ownerStruct();
    if (!ownerStruct)
        return Result::Continue;

    const auto here = ownerStruct->getSpecOp(sym.idRef());
    if (std::ranges::find(here, &sym) != here.end())
        return Result::Continue;

    if (!allowsSpecOpOverload(kind))
    {
        if (!here.empty())
            return SemaError::raiseAlreadyDefined(sema, &sym, here.front());
    }

    return ownerStruct->registerSpecOp(sym, kind);
}

SpecOpKind SemaSpecOp::computeSymbolKind(const Sema& sema, const SymbolFunction& sym)
{
    const IdentifierRef      idRef = sym.idRef();
    const IdentifierManager& idMgr = sema.idMgr();

    const std::string_view name = idMgr.get(idRef).name;
    if (!LangSpec::isSpecOpName(name))
        return SpecOpKind::None;

    auto kind = SpecOpKind::Invalid;
    using Pn  = IdentifierManager::PredefinedName;
    struct Entry
    {
        Pn         pn;
        SpecOpKind kind;
    };

    static constexpr Entry K_MAP[] = {
        {Pn::OpVisit, SpecOpKind::OpVisit},
        {Pn::OpBinary, SpecOpKind::OpBinary},
        {Pn::OpUnary, SpecOpKind::OpUnary},
        {Pn::OpAssign, SpecOpKind::OpAssign},
        {Pn::OpIndexAssign, SpecOpKind::OpIndexAssign},
        {Pn::OpCast, SpecOpKind::OpCast},
        {Pn::OpEquals, SpecOpKind::OpEquals},
        {Pn::OpCmp, SpecOpKind::OpCmp},
        {Pn::OpPostCopy, SpecOpKind::OpPostCopy},
        {Pn::OpPostMove, SpecOpKind::OpPostMove},
        {Pn::OpDrop, SpecOpKind::OpDrop},
        {Pn::OpCount, SpecOpKind::OpCount},
        {Pn::OpData, SpecOpKind::OpData},
        {Pn::OpAffect, SpecOpKind::OpAffect},
        {Pn::OpAffectLiteral, SpecOpKind::OpAffectLiteral},
        {Pn::OpSlice, SpecOpKind::OpSlice},
        {Pn::OpIndex, SpecOpKind::OpIndex},
        {Pn::OpIndexAffect, SpecOpKind::OpIndexAffect},
    };

    for (const auto& e : K_MAP)
    {
        if (idRef == idMgr.predefined(e.pn))
        {
            kind = e.kind;
            return kind;
        }
    }

    if (LangSpec::isOpVisitName(name))
        return SpecOpKind::OpVisit;
    return SpecOpKind::Invalid;
}

Result SemaSpecOp::tryResolveAssign(Sema& sema, const AstAssignStmt& node, const SemaNodeView& leftView, bool& outHandled)
{
    outHandled = false;

    const Token& tok = sema.token(node.codeRef());
    if (!tok.isAny({TokenId::SymEqual,
                    TokenId::SymPlusEqual,
                    TokenId::SymMinusEqual,
                    TokenId::SymAsteriskEqual,
                    TokenId::SymSlashEqual,
                    TokenId::SymAmpersandEqual,
                    TokenId::SymPipeEqual,
                    TokenId::SymCircumflexEqual,
                    TokenId::SymPercentEqual,
                    TokenId::SymLowerLowerEqual,
                    TokenId::SymGreaterGreaterEqual}))
        return Result::Continue;

    if (!leftView.type())
        return Result::Continue;

    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, leftView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));

    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectAssignSpecOpCandidates(sema, *ownerStruct, node.codeRef(), tok.id, candidates));
    if (candidates.empty())
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    args.push_back(node.nodeRightRef);

    bool matched = false;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeLeftRef, true, &matched));
    if (!matched)
        return Result::Continue;

    auto* assignPayload = sema.semaPayload<AssignSpecOpPayload>(sema.curNodeRef());
    if (!assignPayload)
    {
        assignPayload = sema.compiler().allocate<AssignSpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), assignPayload);
    }

    if (const SemaNodeView symView = sema.curViewSymbol(); symView.sym() && symView.sym()->isFunction())
        assignPayload->calledFn = &symView.sym()->cast<SymbolFunction>();

    sema.setType(sema.curNodeRef(), sema.typeMgr().typeVoid());
    outHandled = true;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveIndex(Sema& sema, const AstIndexExpr& node, const SemaNodeView& indexedView, bool& outHandled)
{
    outHandled = false;

    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, indexedView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));

    const AstNodeRef parentRef = sema.visit().parentNodeRef();
    if (parentRef.isValid() && sema.node(parentRef).is(AstNodeId::AssignStmt))
    {
        const auto& assignNode = sema.node(parentRef).cast<AstAssignStmt>();
        if (assignNode.nodeLeftRef == sema.curNodeRef())
        {
            const Token&         tok = sema.token(assignNode.codeRef());
            SmallVector<Symbol*> candidates;
            SWC_RESULT(collectIndexAssignSpecOpCandidates(sema, *ownerStruct, assignNode.codeRef(), tok.id, candidates));
            if (!candidates.empty())
            {
                auto* payload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
                sema.setSemaPayload(sema.curNodeRef(), payload);
                outHandled = true;
                return Result::Continue;
            }
        }
    }

    SmallVector<Symbol*> candidates;
    const IdentifierRef  opIndexId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpIndex);
    SWC_RESULT(collectSpecOpCandidates(sema, *ownerStruct, opIndexId, std::span<const AstNodeRef>{}, candidates));
    if (candidates.empty())
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    args.push_back(node.nodeArgRef);

    bool matched = false;
    if (!indexedView.type()->isConst())
    {
        SmallVector<Symbol*> mutableCandidates;
        SmallVector<Symbol*> constCandidates;
        splitMutableReceiverCandidates(sema, candidates.span(), mutableCandidates, constCandidates);

        if (!mutableCandidates.empty())
        {
            SWC_RESULT(resolveSyntheticCall(sema, node, mutableCandidates.span(), args.span(), node.nodeExprRef, true, &matched));
            if (matched)
                candidates = std::move(mutableCandidates);
            else if (!constCandidates.empty())
                candidates = std::move(constCandidates);
        }
    }

    if (!matched)
        SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeExprRef, true, &matched));
    if (!matched)
        return Result::Continue;

    const auto symView = sema.curViewSymbol();
    SWC_ASSERT(symView.sym() && symView.sym()->isFunction());
    auto& calledFn = symView.sym()->cast<SymbolFunction>();

    const TypeRef    returnTypeRef = calledFn.returnTypeRef();
    const TypeInfo&  returnType    = sema.typeMgr().get(returnTypeRef);
    const AstNodeRef resultNodeRef = sema.viewZero(sema.curNodeRef()).nodeRef();

    if (!sema.viewConstant(sema.curNodeRef()).hasConstant())
    {
        auto* payload     = sema.compiler().allocate<IndexSpecOpSemaPayload>();
        payload->calledFn = &calledFn;
        sema.setSemaPayload(sema.curNodeRef(), payload);

        if (returnType.isReference())
        {
            sema.setType(sema.curNodeRef(), returnType.payloadTypeRef());
            sema.setType(resultNodeRef, returnType.payloadTypeRef());
            sema.setIsValue(sema.curNodeRef());
            sema.setIsValue(resultNodeRef);
            sema.setIsLValue(sema.curNodeRef());
            sema.setIsLValue(resultNodeRef);
        }
        else
        {
            sema.setType(sema.curNodeRef(), returnTypeRef);
            sema.setType(resultNodeRef, returnTypeRef);
            sema.setIsValue(sema.curNodeRef());
            sema.setIsValue(resultNodeRef);
            sema.unsetIsLValue(sema.curNodeRef());
            sema.unsetIsLValue(resultNodeRef);
        }
    }

    outHandled = true;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveIndexAssign(Sema& sema, const AstAssignStmt& node, bool& outHandled)
{
    outHandled = false;

    const Token& tok = sema.token(node.codeRef());
    if (!isSupportedAssignSpecOp(tok.id))
        return Result::Continue;

    const AstNodeRef leftNodeRef = sema.viewZero(node.nodeLeftRef).nodeRef();
    if (leftNodeRef.isInvalid())
        return Result::Continue;
    if (sema.node(leftNodeRef).isNot(AstNodeId::IndexExpr))
        return Result::Continue;

    const auto& indexNode = sema.node(leftNodeRef).cast<AstIndexExpr>();
    if (sema.node(indexNode.nodeArgRef).is(AstNodeId::RangeExpr))
        return Result::Continue;

    const SemaNodeView  indexedView = sema.viewType(indexNode.nodeExprRef);
    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, indexedView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));
    SWC_RESULT(SemaCheck::isAssignable(sema, sema.curNodeRef(), sema.viewNodeTypeSymbol(indexNode.nodeExprRef)));

    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectIndexAssignSpecOpCandidates(sema, *ownerStruct, node.codeRef(), tok.id, candidates));
    if (candidates.empty())
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    args.push_back(indexNode.nodeArgRef);
    args.push_back(node.nodeRightRef);
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), indexNode.nodeExprRef));

    auto* assignPayload = sema.semaPayload<AssignSpecOpPayload>(sema.curNodeRef());
    if (!assignPayload)
    {
        assignPayload = sema.compiler().allocate<AssignSpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), assignPayload);
    }

    if (const SemaNodeView symView = sema.curViewSymbol(); symView.sym() && symView.sym()->isFunction())
        assignPayload->calledFn = &symView.sym()->cast<SymbolFunction>();

    sema.setType(sema.curNodeRef(), sema.typeMgr().typeVoid());
    outHandled = true;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveUnary(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& operandView, bool& outHandled)
{
    outHandled = false;

    const Token& tok = sema.token(node.codeRef());
    if (!tok.isAny({TokenId::SymPlus,
                    TokenId::SymMinus,
                    TokenId::SymBang,
                    TokenId::SymTilde}))
        return Result::Continue;

    if (!operandView.type())
        return Result::Continue;

    TypeRef         unwrappedTypeRef = operandView.typeRef();
    const TypeInfo& operandValueType = sema.typeMgr().get(unwrappedTypeRef);
    if (operandValueType.isReference())
        unwrappedTypeRef = unwrapAlias(sema.ctx(), operandValueType.payloadTypeRef());
    else
        unwrappedTypeRef = unwrapAlias(sema.ctx(), unwrappedTypeRef);
    if (!unwrappedTypeRef.isValid())
        unwrappedTypeRef = operandView.typeRef();

    const TypeInfo& operandType = sema.typeMgr().get(unwrappedTypeRef);
    if (!operandType.isStruct())
        return Result::Continue;

    const auto& ownerStruct = operandType.payloadSymStruct();
    SWC_RESULT(sema.waitSemaCompleted(&ownerStruct, node.codeRef()));

    const SourceView&      srcView    = sema.compiler().srcView(node.srcViewRef());
    const std::string_view opString   = tok.string(srcView);
    const AstNodeRef       genericArg = makeSyntheticStringConstantArg(sema, node.codeRef(), opString);
    const IdentifierRef    opUnaryId  = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpUnary);
    SmallVector<Symbol*>   candidates;
    SWC_RESULT(collectSpecOpCandidates(sema, ownerStruct, opUnaryId, std::span{&genericArg, 1}, candidates));
    if (candidates.empty())
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeExprRef));
    outHandled = true;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveBinary(Sema& sema, const AstBinaryExpr& node, const SemaNodeView& leftView, bool& outHandled)
{
    outHandled = false;

    const Token& tok = sema.token(node.codeRef());
    if (!tok.isAny({TokenId::SymPlus,
                    TokenId::SymMinus,
                    TokenId::SymAsterisk,
                    TokenId::SymSlash,
                    TokenId::SymPercent,
                    TokenId::SymAmpersand,
                    TokenId::SymPipe,
                    TokenId::SymCircumflex,
                    TokenId::SymLowerLower,
                    TokenId::SymGreaterGreater}))
        return Result::Continue;

    if (!leftView.type())
        return Result::Continue;

    TypeRef         unwrappedTypeRef = leftView.typeRef();
    const TypeInfo& leftValueType    = sema.typeMgr().get(unwrappedTypeRef);
    if (leftValueType.isReference())
        unwrappedTypeRef = unwrapAlias(sema.ctx(), leftValueType.payloadTypeRef());
    else
        unwrappedTypeRef = unwrapAlias(sema.ctx(), unwrappedTypeRef);
    if (!unwrappedTypeRef.isValid())
        unwrappedTypeRef = leftView.typeRef();

    const TypeInfo& leftType = sema.typeMgr().get(unwrappedTypeRef);
    if (!leftType.isStruct())
        return Result::Continue;

    const auto& ownerStruct = leftType.payloadSymStruct();
    SWC_RESULT(sema.waitSemaCompleted(&ownerStruct, node.codeRef()));

    const SourceView&      srcView    = sema.compiler().srcView(node.srcViewRef());
    const std::string_view opString   = tok.string(srcView);
    const AstNodeRef       genericArg = makeSyntheticStringConstantArg(sema, node.codeRef(), opString);
    const IdentifierRef    opBinaryId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpBinary);
    SmallVector<Symbol*>   candidates;
    SWC_RESULT(collectSpecOpCandidates(sema, ownerStruct, opBinaryId, std::span{&genericArg, 1}, candidates));
    if (candidates.empty())
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    args.push_back(node.nodeRightRef);
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeLeftRef));
    outHandled = true;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveRelational(Sema& sema, const AstRelationalExpr& node, const SemaNodeView& leftView, bool& outHandled)
{
    outHandled = false;

    const Token&  tok     = sema.token(node.codeRef());
    IdentifierRef opIdRef = IdentifierRef::invalid();
    switch (tok.id)
    {
        case TokenId::SymEqualEqual:
        case TokenId::SymBangEqual:
            opIdRef = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpEquals);
            break;

        case TokenId::SymLess:
        case TokenId::SymLessEqual:
        case TokenId::SymGreater:
        case TokenId::SymGreaterEqual:
        case TokenId::SymLessEqualGreater:
            opIdRef = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpCmp);
            break;

        default:
            return Result::Continue;
    }

    if (!leftView.type())
        return Result::Continue;

    TypeRef         unwrappedTypeRef = leftView.typeRef();
    const TypeInfo& leftValueType    = sema.typeMgr().get(unwrappedTypeRef);
    if (leftValueType.isReference())
        unwrappedTypeRef = unwrapAlias(sema.ctx(), leftValueType.payloadTypeRef());
    else
        unwrappedTypeRef = unwrapAlias(sema.ctx(), unwrappedTypeRef);
    if (!unwrappedTypeRef.isValid())
        unwrappedTypeRef = leftView.typeRef();

    const TypeInfo& leftType = sema.typeMgr().get(unwrappedTypeRef);
    if (!leftType.isStruct())
        return Result::Continue;

    const auto& ownerStruct = leftType.payloadSymStruct();
    SWC_RESULT(sema.waitSemaCompleted(&ownerStruct, node.codeRef()));

    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectSpecOpCandidates(sema, ownerStruct, opIdRef, std::span<const AstNodeRef>{}, candidates));
    if (candidates.empty())
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    args.push_back(node.nodeRightRef);
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeLeftRef));

    auto* relationalPayload = sema.semaPayload<RelationalSpecOpPayload>(sema.curNodeRef());
    if (!relationalPayload)
    {
        relationalPayload = sema.compiler().allocate<RelationalSpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), relationalPayload);
    }

    if (const SemaNodeView symView = sema.curViewSymbol(); symView.sym() && symView.sym()->isFunction())
        relationalPayload->calledFn = &symView.sym()->cast<SymbolFunction>();

    switch (tok.id)
    {
        case TokenId::SymEqualEqual:
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
            break;

        case TokenId::SymBangEqual:
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
            if (const SemaNodeView resultView = sema.curViewConstant(); resultView.cstRef().isValid())
                sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstNegBool(resultView.cstRef()));
            break;

        case TokenId::SymLess:
        case TokenId::SymLessEqual:
        case TokenId::SymGreater:
        case TokenId::SymGreaterEqual:
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
            if (const SemaNodeView resultView = sema.curViewConstant(); resultView.cstRef().isValid())
            {
                const int ordering = sema.cstMgr().get(resultView.cstRef()).getInt().compare(ApsInt::makeSigned32(0));
                bool      cmpRes   = false;
                switch (tok.id)
                {
                    case TokenId::SymLess:
                        cmpRes = ordering < 0;
                        break;
                    case TokenId::SymLessEqual:
                        cmpRes = ordering <= 0;
                        break;
                    case TokenId::SymGreater:
                        cmpRes = ordering > 0;
                        break;
                    case TokenId::SymGreaterEqual:
                        cmpRes = ordering >= 0;
                        break;
                    default:
                        SWC_UNREACHABLE();
                }

                sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(cmpRes));
            }
            break;

        case TokenId::SymLessEqualGreater:
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeS32());
            break;

        default:
            break;
    }

    outHandled = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
