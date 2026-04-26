#include "pch.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
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
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
SWC_BEGIN_NAMESPACE();

namespace
{
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
            case SpecOpKind::OpCompare:
                return "mtd opCompare(value: <type>) -> s32";
            case SpecOpKind::OpBinary:
                return "mtd(op: string) const opBinary(other: <type>) -> <struct>";
            case SpecOpKind::OpUnary:
                return "mtd(op: string) const opUnary() -> <struct>";
            case SpecOpKind::OpAssign:
                return "mtd(op: string) opAssign(value: <type>) -> void";
            case SpecOpKind::OpSet:
                return "mtd opSet(value: <type>) -> void";
            case SpecOpKind::OpSetLiteral:
                return "mtd(suffix: string) opSetLiteral(value: <type>) -> void";
            case SpecOpKind::OpSlice:
                return "mtd opSlice(low: u64, up: u64) -> <string or slice>";
            case SpecOpKind::OpIndex:
                return "mtd opIndex(index: <type>) -> <type>";
            case SpecOpKind::OpIndexAssign:
                return "mtd(op: string) opIndexAssign(index: <type>, value: <type>) -> void";
            case SpecOpKind::OpIndexSet:
                return "mtd opIndexSet(index: <type>, value: <type>) -> void";
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

    TypeRef resolveIndexOperandTypeRef(Sema& sema, const SemaNodeView& argView)
    {
        TypeRef       indexTypeRef = argView.typeRef();
        const TypeRef aliasTypeRef = argView.type()->unwrap(sema.ctx(), argView.typeRef(), TypeExpandE::Alias);
        if (aliasTypeRef.isValid())
            indexTypeRef = aliasTypeRef;

        const TypeInfo& indexType = sema.typeMgr().get(indexTypeRef);
        if (indexType.isEnum() && indexType.payloadSymEnum().attributes().hasRtFlag(RtAttributeFlagsE::EnumIndex))
            indexTypeRef = indexType.payloadSymEnum().underlyingTypeRef();

        return indexTypeRef;
    }

    ConstantRef resolveIndexOperandConstantRef(const SemaNodeView& argView)
    {
        if (argView.cstRef().isInvalid())
            return ConstantRef::invalid();
        if (!argView.cst() || !argView.cst()->isEnumValue())
            return argView.cstRef();
        return argView.cst()->getEnumValue();
    }

    Result checkSliceSpecOpBound(Sema& sema, AstNodeRef argRef, const SemaNodeView& argView, int64_t& constIndex, bool& hasConstIndex)
    {
        if (argRef.isInvalid())
            return Result::Continue;

        const TypeRef   indexTypeRef = resolveIndexOperandTypeRef(sema, argView);
        const TypeInfo* indexType    = &sema.typeMgr().get(indexTypeRef);
        if (indexType->isReference())
            indexType = &sema.typeMgr().get(indexType->payloadTypeRef());

        if (!indexType->isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_not_int, argRef);
            diag.addArgument(Diagnostic::ARG_TYPE, argView.typeRef());
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!argView.cst())
            return Result::Continue;

        const ConstantRef resolvedCstRef = resolveIndexOperandConstantRef(argView);
        SWC_ASSERT(resolvedCstRef.isValid());
        const auto& idxInt = sema.cstMgr().get(resolvedCstRef).getInt();
        if (!idxInt.fits64())
            return SemaError::raise(sema, DiagnosticId::sema_err_index_too_large, argRef);

        constIndex = idxInt.asI64();
        if (indexType->isIntSigned() && idxInt.isNegative())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_negative, argRef);
            diag.addArgument(Diagnostic::ARG_VALUE, constIndex);
            diag.report(sema.ctx());
            return Result::Error;
        }

        hasConstIndex = true;
        return Result::Continue;
    }

    bool isSpecOpReceiver(TaskContext& ctx, const SymbolStruct& owner, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isReference())
            typeRef = type.payloadTypeRef();

        const TypeRef receiverTypeRef = unwrapAlias(ctx, typeRef);
        if (receiverTypeRef == unwrapAlias(ctx, owner.typeRef()))
            return true;

        if (!receiverTypeRef.isValid())
            return false;

        const TypeInfo& receiverType = ctx.typeMgr().get(receiverTypeRef);
        if (!receiverType.isStruct())
            return false;

        const SymbolStruct& receiverStruct = receiverType.payloadSymStruct();
        if (receiverStruct.isGenericInstance() && receiverStruct.genericRootSym() == &owner)
            return true;
        if (owner.isGenericInstance() && owner.genericRootSym() == &receiverStruct)
            return true;
        const SymbolStruct* receiverRoot = receiverStruct.isGenericInstance() ? receiverStruct.genericRootSym() : &receiverStruct;
        const SymbolStruct* ownerRoot    = owner.isGenericInstance() ? owner.genericRootSym() : &owner;
        if (receiverRoot && ownerRoot && receiverRoot == ownerRoot)
            return true;
        return false;
    }

    bool isConstSpecOpReceiver(TaskContext& ctx, const SymbolStruct& owner, TypeRef typeRef)
    {
        if (!isSpecOpReceiver(ctx, owner, typeRef))
            return false;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        return type.isConst();
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
            case SpecOpKind::OpSetLiteral:
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

    bool hasSpecOpGenericValueType(const Sema& sema, const Ast& ast, AstNodeRef typeRef, TokenId expectedType)
    {
        if (typeRef.isInvalid())
            return false;

        const AstNode& typeNode = ast.node(typeRef);
        if (typeNode.isNot(AstNodeId::BuiltinType))
            return false;

        return sema.token(typeNode.codeRef()).id == expectedType;
    }

    bool hasSpecOpGenericSignature(Sema& sema, const SymbolFunction& sym, SpecOpKind kind)
    {
        const auto  expected = expectedSpecOpGenericValueTypes(kind);
        const auto* decl     = specOpDeclForGenericSignature(sym);

        if (sym.isGenericInstance() && !sym.isGenericRoot())
            return true;

        if (!decl)
            return expected.empty();

        if (!decl->spanGenericParamsRef.isValid())
            return expected.empty();

        if (expected.empty())
            return false;

        const SourceView&       declSrcView = sema.compiler().srcView(decl->srcViewRef());
        const Ast&              declAst     = declSrcView.file()->ast();
        SmallVector<AstNodeRef> params;
        declAst.appendNodes(params, decl->spanGenericParamsRef);
        if (params.size() != expected.size())
            return false;

        for (size_t i = 0; i < params.size(); ++i)
        {
            const auto* nodeValue = declAst.node(params[i]).safeCast<AstGenericParamValue>();
            if (!nodeValue)
                return false;
            if (nodeValue->nodeAssignRef.isValid())
                return false;
            if (!hasSpecOpGenericValueType(sema, declAst, nodeValue->nodeTypeRef, expected[i]))
                return false;
        }

        return true;
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

    AstNodeRef makeSyntheticBoolConstantArg(Sema& sema, const SourceCodeRef& codeRef, bool value)
    {
        const auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::BoolLiteral>(codeRef.tokRef);
        nodePtr->setCodeRef(codeRef);
        sema.setType(nodeRef, sema.typeMgr().typeBool());
        sema.setConstant(nodeRef, sema.cstMgr().cstBool(value));
        sema.setIsValue(*nodePtr);
        return nodeRef;
    }

    AstNodeRef makeSyntheticU64Arg(Sema& sema, const SourceCodeRef& codeRef, std::optional<uint64_t> value = std::nullopt)
    {
        const auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::IntegerLiteral>(codeRef.tokRef);
        nodePtr->setCodeRef(codeRef);
        sema.setType(nodeRef, sema.typeMgr().typeU64());

        if (value.has_value())
        {
            const TaskContext&  ctx      = sema.ctx();
            const ConstantValue constant = ConstantValue::makeIntSized<uint64_t>(ctx, *value);
            sema.setConstant(nodeRef, sema.cstMgr().addConstant(ctx, constant));
        }

        sema.setIsValue(*nodePtr);
        return nodeRef;
    }

    AstNodeRef makeForeachVisitBodyRef(Sema& sema, const AstForeachStmt& node)
    {
        if (node.nodeWhereRef.isInvalid())
            return node.nodeBodyRef;

        auto [ifRef, ifPtr]     = sema.ast().makeNode<AstNodeId::IfStmt>(node.tokRef());
        ifPtr->nodeConditionRef = node.nodeWhereRef;
        ifPtr->nodeIfBlockRef   = node.nodeBodyRef;
        ifPtr->nodeElseBlockRef = AstNodeRef::invalid();
        ifPtr->setCodeRef(node.codeRef());
        return ifRef;
    }

    AstNodeRef makeSyntheticCodeBlockArg(Sema& sema, const AstForeachStmt& node)
    {
        auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::CompilerCodeBlock>(node.tokRef());
        nodePtr->setCodeRef(node.codeRef());
        nodePtr->nodeBodyRef    = makeForeachVisitBodyRef(sema, node);
        nodePtr->payloadTypeRef = sema.typeMgr().typeVoid();
        return nodeRef;
    }

    IdentifierRef foreachVisitSpecializationId(Sema& sema, const AstForeachStmt& node)
    {
        if (node.tokSpecializationRef.isInvalid())
            return IdentifierRef::invalid();

        const SourceCodeRange tokenRange = sema.srcView(node.srcViewRef()).tokenCodeRange(sema.ctx(), node.tokSpecializationRef);
        if (!tokenRange.srcView || tokenRange.len <= 1)
            return IdentifierRef::invalid();

        Utf8 opVisitName = "opVisit";
        opVisitName += tokenRange.srcView->codeView(tokenRange.offset + 1, tokenRange.len - 1);
        return sema.idMgr().addIdentifierOwned(opVisitName);
    }

    AstNodeRef unwrapVisitFunctionDeclRef(Sema& sema, AstNodeRef childRef)
    {
        const AstNode& childNode = sema.node(childRef);
        if (const auto* accessNode = childNode.safeCast<AstAccessModifier>())
            return accessNode->nodeWhatRef;
        return childRef;
    }

    bool implDeclContainsFunctionId(Sema& sema, const SymbolImpl& symImpl, IdentifierRef idRef)
    {
        const auto* implDecl = symImpl.decl() ? symImpl.decl()->safeCast<AstImpl>() : nullptr;
        if (!implDecl)
            return false;

        SmallVector<AstNodeRef> children;
        sema.ast().appendNodes(children, implDecl->spanChildrenRef);
        for (const AstNodeRef childRef : children)
        {
            const AstNodeRef declRef  = unwrapVisitFunctionDeclRef(sema, childRef);
            const auto*      funcDecl = sema.node(declRef).safeCast<AstFunctionDecl>();
            if (!funcDecl || funcDecl->tokNameRef.isInvalid())
                continue;

            const IdentifierRef childId = sema.idMgr().addIdentifier(sema.ctx(), SourceCodeRef{funcDecl->srcViewRef(), funcDecl->tokNameRef});
            if (childId == idRef)
                return true;
        }

        return false;
    }

    Result waitVisitSpecOpRegistration(Sema& sema, const SymbolStruct& ownerStruct, IdentifierRef idRef, const SourceCodeRef& codeRef)
    {
        if (idRef.isInvalid())
            return Result::Continue;

        bool foundDecl       = false;
        bool foundRegistered = false;
        for (const SymbolImpl* symImpl : ownerStruct.impls())
        {
            if (!symImpl || symImpl->isIgnored())
                continue;
            if (!implDeclContainsFunctionId(sema, *symImpl, idRef))
                continue;

            foundDecl = true;
            if (symImpl->findFunction(idRef))
            {
                foundRegistered = true;
                break;
            }
        }

        if (foundDecl && !foundRegistered)
            return sema.waitIdentifier(idRef, codeRef);
        return Result::Continue;
    }

    Result waitPendingVisitSpecOp(Sema& sema, const SymbolStruct& ownerStruct, const AstForeachStmt& node)
    {
        const IdentifierRef specializedId = foreachVisitSpecializationId(sema, node);
        if (specializedId.isValid())
            return waitVisitSpecOpRegistration(sema, ownerStruct, specializedId, node.codeRef());

        if (node.modifierFlags.has(AstModifierFlagsE::Reverse))
        {
            const IdentifierRef reverseId = sema.idMgr().addIdentifier("opVisitReverse");
            SWC_RESULT(waitVisitSpecOpRegistration(sema, ownerStruct, reverseId, node.codeRef()));
        }

        const IdentifierRef opVisitId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpVisit);
        return waitVisitSpecOpRegistration(sema, ownerStruct, opVisitId, node.codeRef());
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

    bool canExplicitlySpecializeSpecOp(Sema& sema, const SymbolFunction& symFunc, std::span<const AstNodeRef> genericArgNodes)
    {
        if (!symFunc.isGenericRoot() || genericArgNodes.empty())
            return false;

        const auto* decl = symFunc.decl() ? symFunc.decl()->safeCast<AstFunctionDecl>() : nullptr;
        if (!decl || !decl->spanGenericParamsRef.isValid())
            return false;

        SmallVector<SemaGeneric::GenericParamDesc> params;
        SemaGeneric::collectGenericParams(sema, *decl, decl->spanGenericParamsRef, params);
        if (genericArgNodes.size() > params.size())
            return false;

        for (size_t i = 0; i < genericArgNodes.size(); ++i)
        {
            if (params[i].kind != SemaGeneric::GenericParamKind::Value)
                return false;
        }

        return true;
    }

    const Symbol* currentSpecOpWaiterSymbol(Sema& sema)
    {
        const AstNodeRef   rootRef  = sema.visit().root();
        const SemaNodeView rootView = sema.viewSymbol(rootRef);
        if (rootView.hasSymbol())
            return rootView.sym();
        return sema.topSymMap();
    }

    Result waitSpecOpCandidateReady(Sema& sema, const SymbolFunction& symFunc)
    {
        if (!symFunc.isGenericRoot())
        {
            SWC_RESULT(sema.waitTyped(&symFunc, symFunc.codeRef()));
            return Result::Continue;
        }

        // Literal special operators are published during pre-decl and can be specialized before
        // declaration finishes, which silently drops the candidate. Generic `opVisit` can also be
        // queried from `foreach` before the declaration is fully ready in some build modes, so make
        // both cases wait for declaration completion unless we are currently resolving that same
        // special operator.
        if (symFunc.specOpKind() != SpecOpKind::OpSetLiteral &&
            symFunc.specOpKind() != SpecOpKind::OpVisit)
            return Result::Continue;
        if (currentSpecOpWaiterSymbol(sema) == &symFunc)
            return Result::Continue;

        SWC_RESULT(sema.waitDeclared(&symFunc, symFunc.codeRef()));
        return Result::Continue;
    }

    Result reportSpecOpError(Sema& sema, const SymbolFunction& sym, SpecOpKind kind)
    {
        const auto& codeRef = sym.codeRef();
        Diagnostic  diag    = Diagnostic::get(DiagnosticId::sema_err_spec_op_signature, sema.srcView(codeRef.srcViewRef).fileRef());
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

            case SpecOpKind::OpCompare:
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

            case SpecOpKind::OpSet:
            case SpecOpKind::OpSetLiteral:
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
            case SpecOpKind::OpIndexSet:
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

    Result collectSpecOpCandidatesRec(Sema& sema, const SymbolStruct& ownerStruct, IdentifierRef idRef, std::span<const AstNodeRef> genericArgNodes, SmallVector<Symbol*>& outCandidates, SmallVector<const SymbolStruct*>& visited)
    {
        for (const SymbolStruct* visitedStruct : visited)
        {
            if (visitedStruct == &ownerStruct)
                return Result::Continue;
        }

        visited.push_back(&ownerStruct);

        for (const SymbolImpl* symImpl : ownerStruct.impls())
        {
            if (!symImpl || symImpl->isIgnored())
                continue;

            for (SymbolFunction* symFunc : symImpl->specOps())
            {
                if (!symFunc || symFunc->idRef() != idRef)
                    continue;

                SWC_RESULT(waitSpecOpCandidateReady(sema, *symFunc));

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

        for (const Symbol* field : ownerStruct.fields())
        {
            const auto& symVar = field->cast<SymbolVariable>();
            if (!symVar.isUsingField())
                continue;

            bool                isPointer = false;
            const SymbolStruct* target    = symVar.usingTargetStruct(sema.ctx(), isPointer);
            if (!target || isPointer)
                continue;

            SWC_RESULT(sema.waitSemaCompleted(target, sema.curNode().codeRef()));
            SWC_RESULT(collectSpecOpCandidatesRec(sema, *target, idRef, genericArgNodes, outCandidates, visited));
        }

        return Result::Continue;
    }

    Result collectSpecOpCandidates(Sema& sema, const SymbolStruct& ownerStruct, IdentifierRef idRef, std::span<const AstNodeRef> genericArgNodes, SmallVector<Symbol*>& outCandidates)
    {
        outCandidates.clear();

        SmallVector<const SymbolStruct*> visited;
        SWC_RESULT(collectSpecOpCandidatesRec(sema, ownerStruct, idRef, genericArgNodes, outCandidates, visited));
        return Result::Continue;
    }

    Result collectAssignSpecOpCandidates(Sema& sema, const SymbolStruct& ownerStruct, const SourceCodeRef& codeRef, TokenId tokId, SmallVector<Symbol*>& outCandidates)
    {
        outCandidates.clear();
        if (!isSupportedAssignSpecOp(tokId))
            return Result::Continue;

        const bool          isSimpleAssign = tokId == TokenId::SymEqual;
        const IdentifierRef opId           = isSimpleAssign ? sema.idMgr().predefined(IdentifierManager::PredefinedName::OpSet) : sema.idMgr().predefined(IdentifierManager::PredefinedName::OpAssign);
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

    SymbolFunction* selectReceiverOnlyCandidate(Sema& sema, std::span<Symbol*> candidates, bool receiverIsConst)
    {
        SmallVector<Symbol*> mutableCandidates;
        SmallVector<Symbol*> constCandidates;
        splitMutableReceiverCandidates(sema, candidates, mutableCandidates, constCandidates);

        const auto preferredCandidates = receiverIsConst || mutableCandidates.empty() ? constCandidates.span() : mutableCandidates.span();
        for (Symbol* sym : preferredCandidates)
        {
            if (auto* const symFunc = sym ? sym->safeCast<SymbolFunction>() : nullptr)
                return symFunc;
        }

        if (!receiverIsConst)
        {
            for (Symbol* sym : constCandidates)
            {
                if (auto* const symFunc = sym ? sym->safeCast<SymbolFunction>() : nullptr)
                    return symFunc;
            }
        }

        return nullptr;
    }

    Result collectIndexAssignSpecOpCandidates(Sema& sema, const SymbolStruct& ownerStruct, const SourceCodeRef& codeRef, TokenId tokId, SmallVector<Symbol*>& outCandidates)
    {
        outCandidates.clear();
        if (!isSupportedAssignSpecOp(tokId))
            return Result::Continue;

        const bool          isSimpleAssign = tokId == TokenId::SymEqual;
        const IdentifierRef opId           = isSimpleAssign ? sema.idMgr().predefined(IdentifierManager::PredefinedName::OpIndexSet) : sema.idMgr().predefined(IdentifierManager::PredefinedName::OpIndexAssign);
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

    Result matchSyntheticCall(Sema& sema, std::span<Symbol*> candidates, std::span<AstNodeRef> args, AstNodeRef ufcsArg, bool allowNoMatch, SmallVector<ResolvedCallArgument>& outResolvedArgs, bool& outMatched)
    {
        outResolvedArgs.clear();
        outMatched = false;

        const SemaNodeView calleeView(sema, sema.curNodeRef(), SemaNodeViewPartE::Node);
        if (allowNoMatch)
        {
            const bool savedSilent = sema.ctx().silentDiagnostic();
            sema.ctx().setSilentDiagnostic(true);
            const Result matchResult = Match::resolveFunctionCandidates(sema, calleeView, candidates, args, ufcsArg, &outResolvedArgs);
            sema.ctx().setSilentDiagnostic(savedSilent);
            if (matchResult == Result::Pause)
                return Result::Pause;
            if (matchResult != Result::Continue)
                return Result::Continue;
        }
        else
        {
            SWC_RESULT(Match::resolveFunctionCandidates(sema, calleeView, candidates, args, ufcsArg, &outResolvedArgs));
        }

        outMatched = true;
        return Result::Continue;
    }

    SymbolFunction* indexReadSpecOpFunction(const Sema& sema, AstNodeRef leftExprRef)
    {
        const auto* payloadBase = sema.semaPayload<IndexSpecOpPayloadBase>(leftExprRef);
        if (!payloadBase || payloadBase->kind != IndexSpecOpPayloadKind::Read)
            return nullptr;

        const auto* payload = reinterpret_cast<const IndexSpecOpSemaPayload*>(payloadBase);
        return payload->calledFn;
    }

    Result canAssignThroughIndexLValue(Sema& sema, const AstAssignStmt& node, AstNodeRef leftExprRef, const SemaNodeView& leftView, bool& outCanAssign)
    {
        outCanAssign = false;
        if (!leftView.type() || leftView.type()->isConst())
            return Result::Continue;

        const bool savedSilent = sema.ctx().silentDiagnostic();
        sema.ctx().setSilentDiagnostic(true);

        const Result assignableResult = SemaCheck::isAssignable(sema, sema.curNodeRef(), leftExprRef, leftView);
        if (assignableResult == Result::Pause)
        {
            sema.ctx().setSilentDiagnostic(savedSilent);
            return Result::Pause;
        }

        if (assignableResult != Result::Continue)
        {
            sema.ctx().setSilentDiagnostic(savedSilent);
            return Result::Continue;
        }

        const SemaNodeView rightView = sema.viewType(node.nodeRightRef);
        if (!rightView.type())
        {
            sema.ctx().setSilentDiagnostic(savedSilent);
            return Result::Continue;
        }

        CastRequest castRequest(CastKind::Assignment);
        castRequest.errorNodeRef = node.nodeRightRef;
        const Result castResult  = Cast::castAllowed(sema, castRequest, rightView.typeRef(), leftView.typeRef());
        sema.ctx().setSilentDiagnostic(savedSilent);
        if (castResult == Result::Pause)
            return Result::Pause;

        outCanAssign = castResult == Result::Continue;
        return Result::Continue;
    }

    Result probeIndexAssignSpecOp(Sema& sema, const AstAssignStmt& node, const AstIndexExpr& indexNode, std::span<Symbol*> candidates, SymbolFunction*& outCalledFn, bool& outMatched)
    {
        outCalledFn = nullptr;
        outMatched  = false;

        SmallVector<AstNodeRef> args;
        args.push_back(indexNode.nodeArgRef);
        args.push_back(node.nodeRightRef);

        SmallVector<ResolvedCallArgument> resolvedArgs;
        SWC_RESULT(matchSyntheticCall(sema, candidates, args.span(), indexNode.nodeExprRef, true, resolvedArgs, outMatched));
        if (!outMatched)
            return Result::Continue;

        const auto symView = sema.curViewSymbol();
        SWC_ASSERT(symView.sym() && symView.sym()->isFunction());
        outCalledFn = &symView.sym()->cast<SymbolFunction>();
        return Result::Continue;
    }

    Result raiseAmbiguousIndexWrite(Sema& sema, AstNodeRef atNodeRef, const SymbolFunction& readFn, const SymbolFunction& writeFn)
    {
        SmallVector<const Symbol*> ambiguous;
        ambiguous.push_back(&readFn);
        ambiguous.push_back(&writeFn);
        return SemaError::raiseAmbiguousSymbol(sema, atNodeRef, ambiguous.span());
    }

    Result collectVisitSpecOpCandidates(Sema& sema, const SymbolStruct& ownerStruct, const AstForeachStmt& node, std::span<const AstNodeRef> genericArgNodes, SmallVector<Symbol*>& outCandidates)
    {
        outCandidates.clear();

        const IdentifierRef specializedId = foreachVisitSpecializationId(sema, node);
        if (specializedId.isValid())
            return collectSpecOpCandidates(sema, ownerStruct, specializedId, genericArgNodes, outCandidates);

        if (node.modifierFlags.has(AstModifierFlagsE::Reverse))
        {
            const IdentifierRef reverseId = sema.idMgr().addIdentifier("opVisitReverse");
            SWC_RESULT(collectSpecOpCandidates(sema, ownerStruct, reverseId, genericArgNodes, outCandidates));
            if (!outCandidates.empty())
                return Result::Continue;
        }

        const IdentifierRef opVisitId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpVisit);
        return collectSpecOpCandidates(sema, ownerStruct, opVisitId, genericArgNodes, outCandidates);
    }

    bool foreachRequestsByAddress(const Sema& sema, const AstForeachStmt& node)
    {
        if (node.hasFlag(AstForeachStmtFlagsE::ByAddress))
            return true;

        SmallVector<TokenRef> foreachNames;
        sema.ast().appendTokens(foreachNames, node.spanNamesRef);
        if (foreachNames.empty())
            return false;

        const SourceView& srcView = sema.srcView(node.srcViewRef());
        for (uint32_t tokIndex = node.tokRef().get(); tokIndex < foreachNames.front().get(); ++tokIndex)
        {
            if (srcView.token(TokenRef{tokIndex}).id == TokenId::SymAmpersand)
                return true;
        }

        const SourceCodeRange codeRange = node.codeRangeWithChildren(sema.ctx(), sema.ast());
        if (codeRange.srcView && codeRange.len)
        {
            const std::string_view code   = codeRange.srcView->codeView(codeRange.offset, codeRange.len);
            const size_t           inPos  = code.find(" in ");
            const size_t           ampPos = code.find('&');
            if (ampPos != std::string_view::npos && (inPos == std::string_view::npos || ampPos < inPos))
                return true;
        }

        return false;
    }

    Result resolveSyntheticCall(Sema& sema, const AstNode& node, std::span<Symbol*> candidates, std::span<AstNodeRef> args, AstNodeRef ufcsArg, bool allowNoMatch = false, bool* outMatched = nullptr, bool allowConstEval = true, bool allowInline = true, SymbolFunction** outCalledFn = nullptr)
    {
        SmallVector<ResolvedCallArgument> resolvedArgs;
        bool                              matched = false;
        SWC_RESULT(matchSyntheticCall(sema, candidates, args, ufcsArg, allowNoMatch, resolvedArgs, matched));
        if (!matched)
            return Result::Continue;
        if (outMatched)
            *outMatched = true;
        sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);

        auto& calledFn = sema.curViewSymbol().sym()->cast<SymbolFunction>();
        if (outCalledFn)
            *outCalledFn = &calledFn;
        sema.setType(sema.curNodeRef(), calledFn.returnTypeRef());
        sema.setIsValue(sema.curNode());
        sema.unsetIsLValue(sema.curNodeRef());
        SemaHelpers::addCurrentFunctionCallDependency(sema, &calledFn);

        if (allowConstEval)
        {
            SWC_RESULT(SemaJIT::tryRunConstCall(sema, calledFn, sema.curNodeRef(), resolvedArgs.span()));
            if (sema.viewConstant(sema.curNodeRef()).hasConstant())
                return Result::Continue;
        }

        if (allowInline)
            SWC_RESULT(SemaInline::tryInlineCall(sema, sema.curNodeRef(), calledFn, args, ufcsArg));
        SWC_RESULT(SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(sema, node, calledFn, "__spec_op_runtime_storage"));
        return Result::Continue;
    }

    bool allowsSpecOpOverload(SpecOpKind kind)
    {
        switch (kind)
        {
            case SpecOpKind::OpCast:
            case SpecOpKind::OpEquals:
            case SpecOpKind::OpCompare:
            case SpecOpKind::OpBinary:
            case SpecOpKind::OpAssign:
            case SpecOpKind::OpSet:
            case SpecOpKind::OpSetLiteral:
            case SpecOpKind::OpIndex:
            case SpecOpKind::OpIndexAssign:
            case SpecOpKind::OpIndexSet:
                return true;
            default:
                return false;
        }
    }

    Result tryResolveReceiverOnlySpecOp(Sema& sema, SymbolFunction*& outCalledFn, bool& outHandled, AstNodeRef exprRef, IdentifierRef opId, bool allowConstEval)
    {
        outCalledFn = nullptr;
        outHandled  = false;

        const SemaNodeView  exprView(sema, exprRef, SemaNodeViewPartE::Type);
        const SymbolStruct* ownerStruct = structSpecOpOwner(sema, exprView);
        if (!ownerStruct)
            return Result::Continue;

        SWC_RESULT(sema.waitSemaCompleted(ownerStruct, sema.node(exprRef).codeRef()));

        SmallVector<Symbol*> candidates;
        SWC_RESULT(collectSpecOpCandidates(sema, *ownerStruct, opId, std::span<const AstNodeRef>{}, candidates));
        if (candidates.empty())
            return Result::Continue;

        SmallVector<AstNodeRef> args;
        bool                    matched = false;
        SWC_RESULT(resolveSyntheticCall(sema, sema.node(sema.curNodeRef()), candidates.span(), args.span(), exprRef, true, &matched, allowConstEval, false));
        if (!matched)
        {
            auto* const calledFn = candidates.size() == 1 ? candidates.front()->safeCast<SymbolFunction>() : nullptr;
            if (!calledFn)
                return Result::Continue;

            SmallVector<ResolvedCallArgument> resolvedArgs;
            ResolvedCallArgument              resolvedArg;
            resolvedArg.argRef = exprRef;

            const SymbolVariable* const receiver = calledFn->parameters().empty() ? nullptr : calledFn->parameters().front();
            if (receiver && sema.typeMgr().get(receiver->typeRef()).isReference())
            {
                resolvedArg.bindsReferenceToValue = true;

                bool               needsRuntimeStorage = !sema.isGlobalScope();
                const SemaNodeView operandView         = sema.viewNodeTypeSymbol(exprRef);
                if (operandView.sym() &&
                    operandView.sym()->isVariable() &&
                    operandView.type() &&
                    !operandView.type()->isReference() &&
                    !operandView.type()->isAnyPointer())
                {
                    auto& symVar = operandView.sym()->cast<SymbolVariable>();
                    if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
                    {
                        symVar.addExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);
                        needsRuntimeStorage = false;
                    }
                }

                if (needsRuntimeStorage)
                {
                    const TypeRef storageTypeRef = sema.typeMgr().get(receiver->typeRef()).payloadTypeRef();
                    SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, exprRef, sema.node(exprRef), storageTypeRef, "__call_arg_ref_storage"));
                }
            }

            resolvedArgs.push_back(resolvedArg);
            sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);
            sema.setSymbol(sema.curNodeRef(), calledFn);
            sema.setType(sema.curNodeRef(), calledFn->returnTypeRef());
            sema.setIsValue(sema.curNode());
            sema.unsetIsLValue(sema.curNodeRef());

            SemaHelpers::addCurrentFunctionCallDependency(sema, calledFn);
            if (allowConstEval)
            {
                SWC_RESULT(SemaJIT::tryRunConstCall(sema, *calledFn, sema.curNodeRef(), resolvedArgs.span()));
            }

            if (!allowConstEval || !sema.viewConstant(sema.curNodeRef()).hasConstant())
            {
                SWC_UNUSED(args);
                SWC_RESULT(SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(sema, sema.node(sema.curNodeRef()), *calledFn, "__spec_op_runtime_storage"));
            }

            outCalledFn = calledFn;
            outHandled  = true;
            return Result::Continue;
        }

        const SemaNodeView currentSymView = sema.curViewSymbol();
        if (currentSymView.sym() && currentSymView.sym()->isFunction())
            outCalledFn = &currentSymView.sym()->cast<SymbolFunction>();
        else if (candidates.size() == 1)
            outCalledFn = candidates.front()->safeCast<SymbolFunction>();

        if (outCalledFn && !sema.viewType(sema.curNodeRef()).typeRef().isValid() && outCalledFn->returnTypeRef().isValid())
        {
            sema.setType(sema.curNodeRef(), outCalledFn->returnTypeRef());
            sema.setIsValue(sema.curNode());
            sema.unsetIsLValue(sema.curNodeRef());
        }

        outHandled = true;
        return Result::Continue;
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
    const SymbolMap* ownerMap = sym.ownerSymMap();
    if (ownerMap && ownerMap->isImpl() && ownerMap->cast<SymbolImpl>().isForInterface())
        return SemaError::raise(sema, DiagnosticId::sema_err_spec_op_in_impl_for, sym);
    if ((sym.isGenericRoot() && !sym.isGenericInstance()) || (ownerStruct->isGenericRoot() && !ownerStruct->isGenericInstance()))
    {
        if (!hasSpecOpGenericSignature(sema, sym, kind))
        {
            if (kind == SpecOpKind::OpVisit)
                return Result::Continue;
            return reportSpecOpError(sema, sym, kind);
        }
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

Result SemaSpecOp::collectSetCandidates(Sema& sema, const SymbolStruct& ownerStruct, const SourceCodeRef& codeRef, AstNodeRef valueRef, SmallVector<Symbol*>& outCandidates)
{
    UserDefinedLiteralSuffixInfo suffixInfo;
    if (!Cast::resolveUserDefinedLiteralSuffix(sema, valueRef, suffixInfo))
        return collectAssignSpecOpCandidates(sema, ownerStruct, codeRef, TokenId::SymEqual, outCandidates);

    const IdentifierRef opSetLiteralId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpSetLiteral);
    const AstNodeRef    genericArg     = makeSyntheticStringConstantArg(sema, codeRef, suffixInfo.suffix);
    return collectSpecOpCandidates(sema, ownerStruct, opSetLiteralId, std::span{&genericArg, 1}, outCandidates);
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
        {Pn::OpCompare, SpecOpKind::OpCompare},
        {Pn::OpPostCopy, SpecOpKind::OpPostCopy},
        {Pn::OpPostMove, SpecOpKind::OpPostMove},
        {Pn::OpDrop, SpecOpKind::OpDrop},
        {Pn::OpCount, SpecOpKind::OpCount},
        {Pn::OpData, SpecOpKind::OpData},
        {Pn::OpSet, SpecOpKind::OpSet},
        {Pn::OpSetLiteral, SpecOpKind::OpSetLiteral},
        {Pn::OpSlice, SpecOpKind::OpSlice},
        {Pn::OpIndex, SpecOpKind::OpIndex},
        {Pn::OpIndexSet, SpecOpKind::OpIndexSet},
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
    if (tok.id == TokenId::SymEqual)
        SWC_RESULT(collectSetCandidates(sema, *ownerStruct, node.codeRef(), node.nodeRightRef, candidates));
    else
        SWC_RESULT(collectAssignSpecOpCandidates(sema, *ownerStruct, node.codeRef(), tok.id, candidates));
    if (candidates.empty())
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    args.push_back(node.nodeRightRef);

    bool            matched  = false;
    SymbolFunction* calledFn = nullptr;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeLeftRef, true, &matched, true, true, &calledFn));
    if (!matched)
        return Result::Continue;

    auto* assignPayload = sema.semaPayload<AssignSpecOpPayload>(sema.curNodeRef());
    if (!assignPayload)
    {
        assignPayload = sema.compiler().allocate<AssignSpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), assignPayload);
    }

    assignPayload->calledFn = calledFn;

    sema.setType(sema.curNodeRef(), sema.typeMgr().typeVoid());
    outHandled = true;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveVarInitSet(Sema& sema, AstNodeRef receiverRef, AstNodeRef valueRef, bool& outHandled)
{
    outHandled = false;

    const SemaNodeView  receiverView(sema, receiverRef, SemaNodeViewPartE::Type);
    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, receiverView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, sema.node(valueRef).codeRef()));

    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectSetCandidates(sema, *ownerStruct, sema.node(valueRef).codeRef(), valueRef, candidates));
    if (candidates.empty())
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    args.push_back(valueRef);

    Symbol* const savedSymbol = sema.curViewSymbol().sym();
    const bool    savedLValue = sema.isLValue(sema.curNodeRef());

    bool matched = false;
    SWC_RESULT(resolveSyntheticCall(sema, sema.node(sema.curNodeRef()), candidates.span(), args.span(), receiverRef, true, &matched));

    SymbolFunction* calledFn = nullptr;
    if (matched)
    {
        const SemaNodeView currentSymView = sema.curViewSymbol();
        if (currentSymView.sym() && currentSymView.sym()->isFunction())
            calledFn = &currentSymView.sym()->cast<SymbolFunction>();
    }

    if (savedSymbol)
        sema.setSymbol(sema.curNodeRef(), savedSymbol);
    if (savedLValue)
        sema.setIsLValue(sema.curNodeRef());
    else
        sema.unsetIsLValue(sema.curNodeRef());

    if (!matched)
        return Result::Continue;

    auto* payload = sema.semaPayload<VarInitSpecOpPayload>(sema.curNodeRef());
    if (!payload)
    {
        payload = sema.compiler().allocate<VarInitSpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), payload);
    }

    payload->calledFn = calledFn;

    outHandled = payload->calledFn != nullptr;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveCountOf(Sema& sema, AstNodeRef exprRef, SymbolFunction*& outCalledFn, bool& outHandled)
{
    const IdentifierRef opCountId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpCount);
    return tryResolveReceiverOnlySpecOp(sema, outCalledFn, outHandled, exprRef, opCountId, true);
}

Result SemaSpecOp::tryResolveDataOf(Sema& sema, AstNodeRef exprRef, SymbolFunction*& outCalledFn, bool& outHandled)
{
    const IdentifierRef opDataId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpData);
    return tryResolveReceiverOnlySpecOp(sema, outCalledFn, outHandled, exprRef, opDataId, false);
}

Result SemaSpecOp::canResolveVisit(Sema& sema, const AstForeachStmt& node, bool& outMatched)
{
    outMatched = false;

    const SemaNodeView  exprView(sema, node.nodeExprRef, SemaNodeViewPartE::Type);
    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, exprView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));

    SmallVector<AstNodeRef> genericArgs;
    genericArgs.push_back(makeSyntheticBoolConstantArg(sema, node.codeRef(), foreachRequestsByAddress(sema, node)));
    genericArgs.push_back(makeSyntheticBoolConstantArg(sema, node.codeRef(), node.modifierFlags.has(AstModifierFlagsE::Reverse)));

    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectVisitSpecOpCandidates(sema, *ownerStruct, node, genericArgs.span(), candidates));
    if (candidates.empty())
        return waitPendingVisitSpecOp(sema, *ownerStruct, node);

    SmallVector<AstNodeRef> args;
    args.push_back(makeSyntheticCodeBlockArg(sema, node));
    SmallVector<ResolvedCallArgument> resolvedArgs;
    SWC_RESULT(matchSyntheticCall(sema, candidates.span(), args.span(), node.nodeExprRef, true, resolvedArgs, outMatched));
    return Result::Continue;
}

Result SemaSpecOp::tryResolveVisit(Sema& sema, const AstForeachStmt& node, bool& outHandled)
{
    outHandled = false;

    const SemaNodeView  exprView(sema, node.nodeExprRef, SemaNodeViewPartE::Type);
    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, exprView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));

    SmallVector<AstNodeRef> genericArgs;
    genericArgs.push_back(makeSyntheticBoolConstantArg(sema, node.codeRef(), foreachRequestsByAddress(sema, node)));
    genericArgs.push_back(makeSyntheticBoolConstantArg(sema, node.codeRef(), node.modifierFlags.has(AstModifierFlagsE::Reverse)));

    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectVisitSpecOpCandidates(sema, *ownerStruct, node, genericArgs.span(), candidates));
    if (candidates.empty())
        return waitPendingVisitSpecOp(sema, *ownerStruct, node);

    SmallVector<AstNodeRef> args;
    args.push_back(makeSyntheticCodeBlockArg(sema, node));
    bool matched = false;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeExprRef, true, &matched, false));
    outHandled = matched;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveSlice(Sema& sema, const AstIndexExpr& node, const SemaNodeView& indexedView, bool& outHandled)
{
    outHandled = false;

    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, indexedView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));

    const auto&        range        = sema.node(node.nodeArgRef).cast<AstRangeExpr>();
    const SemaNodeView nodeDownView = sema.viewTypeConstant(range.nodeExprDownRef);
    const SemaNodeView nodeUpView   = sema.viewTypeConstant(range.nodeExprUpRef);
    int64_t            constDown    = 0;
    int64_t            constUp      = 0;
    bool               hasConstDown = false;
    bool               hasConstUp   = false;
    SWC_RESULT(checkSliceSpecOpBound(sema, range.nodeExprDownRef, nodeDownView, constDown, hasConstDown));
    SWC_RESULT(checkSliceSpecOpBound(sema, range.nodeExprUpRef, nodeUpView, constUp, hasConstUp));

    if (hasConstDown && hasConstUp)
    {
        const bool ok = range.hasFlag(AstRangeExprFlagsE::Inclusive) ? constDown <= constUp : constDown < constUp;
        if (!ok)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_range_invalid_bounds, node.nodeArgRef);
            diag.addArgument(Diagnostic::ARG_LEFT, nodeDownView.cstRef());
            diag.addArgument(Diagnostic::ARG_RIGHT, nodeUpView.cstRef());
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    SmallVector<Symbol*> candidates;
    const IdentifierRef  opSliceId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpSlice);
    SWC_RESULT(collectSpecOpCandidates(sema, *ownerStruct, opSliceId, std::span<const AstNodeRef>{}, candidates));
    if (candidates.empty())
        return Result::Continue;

    SymbolFunction* countFn = nullptr;
    if (!range.nodeExprUpRef.isValid())
    {
        SmallVector<Symbol*> countCandidates;
        const IdentifierRef  opCountId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpCount);
        SWC_RESULT(collectSpecOpCandidates(sema, *ownerStruct, opCountId, std::span<const AstNodeRef>{}, countCandidates));
        countFn = selectReceiverOnlyCandidate(sema, countCandidates.span(), indexedView.type()->isConst());
        if (!countFn)
            return Result::Continue;
    }

    std::optional<uint64_t> lowerConst;
    if (!range.nodeExprDownRef.isValid())
        lowerConst = 0;
    else if (hasConstDown)
        lowerConst = static_cast<uint64_t>(constDown);

    std::optional<uint64_t> upperConst;
    if (range.nodeExprUpRef.isValid() && hasConstUp)
    {
        const uint64_t adjustedUpper = range.hasFlag(AstRangeExprFlagsE::Inclusive) ? static_cast<uint64_t>(constUp) : static_cast<uint64_t>(constUp - 1);
        upperConst                   = adjustedUpper;
    }
    else if (!range.nodeExprUpRef.isValid())
    {
        upperConst = 0;
    }

    const AstNodeRef lowerArgRef = makeSyntheticU64Arg(sema, node.codeRef(), lowerConst);
    const AstNodeRef upperArgRef = makeSyntheticU64Arg(sema, node.codeRef(), upperConst);

    SmallVector<AstNodeRef> args;
    args.push_back(lowerArgRef);
    args.push_back(upperArgRef);

    SmallVector<ResolvedCallArgument> resolvedArgs;
    bool                              matched = false;
    if (!indexedView.type()->isConst())
    {
        SmallVector<Symbol*> mutableCandidates;
        SmallVector<Symbol*> constCandidates;
        splitMutableReceiverCandidates(sema, candidates.span(), mutableCandidates, constCandidates);

        if (!mutableCandidates.empty())
        {
            SWC_RESULT(matchSyntheticCall(sema, mutableCandidates.span(), args.span(), node.nodeExprRef, true, resolvedArgs, matched));
            if (matched)
                candidates = std::move(mutableCandidates);
            else if (!constCandidates.empty())
                candidates = std::move(constCandidates);
        }
    }

    if (!matched)
        SWC_RESULT(matchSyntheticCall(sema, candidates.span(), args.span(), node.nodeExprRef, true, resolvedArgs, matched));
    if (!matched)
        return Result::Continue;

    sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);

    const auto symView = sema.curViewSymbol();
    SWC_ASSERT(symView.sym() && symView.sym()->isFunction());
    auto& calledFn = symView.sym()->cast<SymbolFunction>();
    SemaHelpers::addCurrentFunctionCallDependency(sema, &calledFn);
    if (countFn)
        SemaHelpers::addCurrentFunctionCallDependency(sema, countFn);

    const TypeRef    returnTypeRef = calledFn.returnTypeRef();
    const AstNodeRef resultNodeRef = sema.viewZero(sema.curNodeRef()).nodeRef();
    auto*            payload       = sema.compiler().allocate<SliceSpecOpSemaPayload>();
    payload->calledFn              = &calledFn;
    payload->countFn               = countFn;
    payload->lowerArgRef           = lowerArgRef;
    payload->upperArgRef           = upperArgRef;
    payload->lowerBoundRef         = range.nodeExprDownRef;
    payload->upperBoundRef         = range.nodeExprUpRef;
    payload->inclusive             = range.hasFlag(AstRangeExprFlagsE::Inclusive);
    sema.setSemaPayload(sema.curNodeRef(), payload);

    sema.setSymbol(sema.curNodeRef(), &calledFn);
    sema.setType(sema.curNodeRef(), returnTypeRef);
    sema.setType(resultNodeRef, returnTypeRef);
    sema.setIsValue(sema.curNode());
    sema.setIsValue(resultNodeRef);
    sema.unsetIsLValue(sema.curNodeRef());
    sema.unsetIsLValue(resultNodeRef);
    SWC_RESULT(SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(sema, node, calledFn, "__spec_op_runtime_storage"));

    outHandled = true;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveIndex(Sema& sema, const AstIndexExpr& node, const SemaNodeView& indexedView, bool& outHandled)
{
    outHandled                    = false;
    const AstNodeRef indexExprRef = sema.curNodeRef();

    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, indexedView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));

    bool             deferToSimpleAssignWriteSpecOp = false;
    const AstNodeRef parentRef                      = sema.visit().parentNodeRef();
    if (parentRef.isValid() && sema.node(parentRef).is(AstNodeId::AssignStmt))
    {
        const auto& assignNode = sema.node(parentRef).cast<AstAssignStmt>();
        if (assignNode.nodeLeftRef == sema.curNodeRef())
        {
            const Token&         tok = sema.token(assignNode.codeRef());
            SmallVector<Symbol*> candidates;
            SWC_RESULT(collectIndexAssignSpecOpCandidates(sema, *ownerStruct, assignNode.codeRef(), tok.id, candidates));
            if (tok.id == TokenId::SymEqual)
            {
                deferToSimpleAssignWriteSpecOp = !candidates.empty();
            }
            else if (!candidates.empty())
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
    {
        if (deferToSimpleAssignWriteSpecOp)
        {
            auto* payload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
            sema.setSemaPayload(sema.curNodeRef(), payload);
            outHandled = true;
        }
        return Result::Continue;
    }

    SmallVector<AstNodeRef> args;
    args.push_back(node.nodeArgRef);

    bool            matched  = false;
    SymbolFunction* calledFn = nullptr;
    if (!indexedView.type()->isConst())
    {
        SmallVector<Symbol*> mutableCandidates;
        SmallVector<Symbol*> constCandidates;
        splitMutableReceiverCandidates(sema, candidates.span(), mutableCandidates, constCandidates);

        if (!mutableCandidates.empty())
        {
            SWC_RESULT(resolveSyntheticCall(sema, node, mutableCandidates.span(), args.span(), node.nodeExprRef, true, &matched, true, true, &calledFn));
            if (matched)
                candidates = std::move(mutableCandidates);
            else if (!constCandidates.empty())
                candidates = std::move(constCandidates);
        }
    }

    if (!matched)
        SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeExprRef, true, &matched, true, true, &calledFn));
    if (!matched)
    {
        if (deferToSimpleAssignWriteSpecOp)
        {
            auto* payload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
            sema.setSemaPayload(sema.curNodeRef(), payload);
            outHandled = true;
        }
        return Result::Continue;
    }
    if (sema.hasSubstitute(indexExprRef))
    {
        outHandled = true;
        return Result::Continue;
    }

    SWC_ASSERT(calledFn);

    const TypeRef    returnTypeRef = calledFn->returnTypeRef();
    const TypeInfo&  returnType    = sema.typeMgr().get(returnTypeRef);
    const AstNodeRef resultNodeRef = sema.viewZero(sema.curNodeRef()).nodeRef();

    if (deferToSimpleAssignWriteSpecOp && !returnType.isReference())
    {
        auto* payload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), payload);
        outHandled = true;
        return Result::Continue;
    }

    if (!sema.viewConstant(sema.curNodeRef()).hasConstant())
    {
        auto* payload     = sema.compiler().allocate<IndexSpecOpSemaPayload>();
        payload->calledFn = calledFn;
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

    const AstNodeRef leftNodeRef = node.nodeLeftRef;
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
    SWC_RESULT(SemaCheck::isAssignable(sema, sema.curNodeRef(), indexNode.nodeExprRef, sema.viewNodeTypeSymbol(indexNode.nodeExprRef)));

    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectIndexAssignSpecOpCandidates(sema, *ownerStruct, node.codeRef(), tok.id, candidates));
    if (candidates.empty())
        return Result::Continue;

    if (tok.id == TokenId::SymEqual)
    {
        const SemaNodeView leftView            = sema.viewNodeTypeSymbol(leftNodeRef);
        bool               canAssignThroughRef = false;
        SWC_RESULT(canAssignThroughIndexLValue(sema, node, leftNodeRef, leftView, canAssignThroughRef));

        SymbolFunction* setFn      = nullptr;
        bool            setMatched = false;
        SWC_RESULT(probeIndexAssignSpecOp(sema, node, indexNode, candidates.span(), setFn, setMatched));

        if (setMatched && canAssignThroughRef)
        {
            if (const SymbolFunction* readFn = indexReadSpecOpFunction(sema, leftNodeRef))
                return raiseAmbiguousIndexWrite(sema, sema.curNodeRef(), *readFn, *setFn);
            return Result::Continue;
        }

        if (!setMatched)
        {
            if (!canAssignThroughRef)
            {
                SmallVector<AstNodeRef> args;
                args.push_back(indexNode.nodeArgRef);
                args.push_back(node.nodeRightRef);
                sema.clearSemaPayload(leftNodeRef);
                auto* deferredPayload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
                sema.setSemaPayload(leftNodeRef, deferredPayload);
                SymbolFunction* calledFn = nullptr;
                SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), indexNode.nodeExprRef, false, nullptr, true, true, &calledFn));

                auto* assignPayload = sema.semaPayload<AssignSpecOpPayload>(sema.curNodeRef());
                if (!assignPayload)
                {
                    assignPayload = sema.compiler().allocate<AssignSpecOpPayload>();
                    sema.setSemaPayload(sema.curNodeRef(), assignPayload);
                }

                assignPayload->calledFn = calledFn;

                sema.setType(sema.curNodeRef(), sema.typeMgr().typeVoid());
                outHandled = true;
            }

            return Result::Continue;
        }
    }

    SmallVector<AstNodeRef> args;
    args.push_back(indexNode.nodeArgRef);
    args.push_back(node.nodeRightRef);
    sema.clearSemaPayload(leftNodeRef);
    auto* deferredPayload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
    sema.setSemaPayload(leftNodeRef, deferredPayload);
    SymbolFunction* calledFn = nullptr;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), indexNode.nodeExprRef, false, nullptr, true, true, &calledFn));

    auto* assignPayload = sema.semaPayload<AssignSpecOpPayload>(sema.curNodeRef());
    if (!assignPayload)
    {
        assignPayload = sema.compiler().allocate<AssignSpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), assignPayload);
    }

    assignPayload->calledFn = calledFn;

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
    SymbolFunction*         calledFn = nullptr;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeExprRef, false, nullptr, true, true, &calledFn));

    auto* unaryPayload = sema.semaPayload<UnarySpecOpPayload>(sema.curNodeRef());
    if (!unaryPayload)
    {
        unaryPayload = sema.compiler().allocate<UnarySpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), unaryPayload);
    }

    unaryPayload->calledFn = calledFn;
    outHandled             = true;
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
    SymbolFunction* calledFn = nullptr;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeLeftRef, false, nullptr, true, true, &calledFn));

    auto* binaryPayload = sema.semaPayload<BinarySpecOpPayload>(sema.curNodeRef());
    if (!binaryPayload)
    {
        binaryPayload = sema.compiler().allocate<BinarySpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), binaryPayload);
    }

    binaryPayload->calledFn = calledFn;
    outHandled              = true;
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
            opIdRef = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpCompare);
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
    SymbolFunction* calledFn = nullptr;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeLeftRef, false, nullptr, true, true, &calledFn));

    auto* relationalPayload = sema.semaPayload<RelationalSpecOpPayload>(sema.curNodeRef());
    if (!relationalPayload)
    {
        relationalPayload = sema.compiler().allocate<RelationalSpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), relationalPayload);
    }

    relationalPayload->calledFn = calledFn;

    switch (tok.id)
    {
        case TokenId::SymEqualEqual:
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
            break;

        case TokenId::SymBangEqual:
        {
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
            const SemaNodeView negResultView = sema.curViewConstant();
            if (negResultView.cstRef().isValid())
                sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstNegBool(negResultView.cstRef()));
            break;
        }

        case TokenId::SymLess:
        case TokenId::SymLessEqual:
        case TokenId::SymGreater:
        case TokenId::SymGreaterEqual:
        {
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
            const SemaNodeView resultView = sema.curViewConstant();
            if (resultView.cstRef().isValid())
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
        }

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
