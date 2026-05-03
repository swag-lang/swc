#include "pch.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Cast/CastFailure.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view K_ARG_PREV_INDEX = "{prev-index}";

    enum class DeductionMode
    {
        Normal,
        MissingOnly,
    };

    Sema& semaForFunctionDecl(Sema& sema, const SymbolFunction& fn, std::unique_ptr<Sema>& ownedSema)
    {
        const SourceView& srcView = sema.compiler().srcView(fn.srcViewRef());
        if (sema.ast().srcView().fileRef() == srcView.ownerFileRef())
            return sema;

        SourceFile& sourceFile = sema.compiler().file(srcView.ownerFileRef());
        AstNodeRef  declRef    = fn.declNodeRef();
        if (declRef.isInvalid() && fn.decl())
            declRef = fn.decl()->nodeRef(sourceFile.ast());
        SWC_ASSERT(declRef.isValid());

        ownedSema = std::make_unique<Sema>(sema.ctx(), sema, sourceFile.nodePayloadContext(), declRef);
        return *ownedSema;
    }

    Sema& semaForStructDecl(Sema& sema, const SymbolStruct& st, std::unique_ptr<Sema>& ownedSema)
    {
        const SourceView& srcView = sema.compiler().srcView(st.srcViewRef());
        if (sema.ast().srcView().fileRef() == srcView.ownerFileRef())
            return sema;

        SourceFile& sourceFile = sema.compiler().file(srcView.ownerFileRef());
        AstNodeRef  declRef    = st.declNodeRef();
        if (declRef.isInvalid() && st.decl())
            declRef = st.decl()->nodeRef(sourceFile.ast());
        SWC_ASSERT(declRef.isValid());

        ownedSema = std::make_unique<Sema>(sema.ctx(), sema, sourceFile.nodePayloadContext(), declRef);
        return *ownedSema;
    }

    const AstNode* genericStructDeclNode(const SymbolStruct& root)
    {
        if (!root.decl())
            return nullptr;

        const AstNode* decl = root.decl();
        if (decl->is(AstNodeId::StructDecl) || decl->is(AstNodeId::UnionDecl))
            return decl;
        return nullptr;
    }

    SpanRef genericStructParamSpan(const AstNode& declNode)
    {
        if (const auto* structDecl = declNode.safeCast<AstStructDecl>())
            return structDecl->spanGenericParamsRef;
        if (const auto* unionDecl = declNode.safeCast<AstUnionDecl>())
            return unionDecl->spanGenericParamsRef;
        return SpanRef::invalid();
    }

    AstNodeRef genericStructBodyRef(const AstNode& declNode)
    {
        if (const auto* structDecl = declNode.safeCast<AstStructDecl>())
            return structDecl->nodeBodyRef;
        if (const auto* unionDecl = declNode.safeCast<AstUnionDecl>())
            return unionDecl->nodeBodyRef;
        return AstNodeRef::invalid();
    }

    Result deduceFromTypePattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef patternRef, TypeRef rawArgTypeRef, AstNodeRef argExprRef, uint32_t callArgIndex, CastFailure* outFailure, DeductionMode mode);

    void setGenericTypeDeductionFailure(Sema& sema, CastFailure& outFailure, IdentifierRef idRef, const SemaGeneric::GenericResolvedArg& previousArg, TypeRef newTypeRef)
    {
        outFailure            = {};
        outFailure.diagId     = DiagnosticId::sema_err_generic_type_deduction_conflict;
        outFailure.srcTypeRef = previousArg.typeRef;
        outFailure.dstTypeRef = newTypeRef;
        outFailure.addArgument(Diagnostic::ARG_VALUE, Utf8{sema.idMgr().get(idRef).name});
        if (previousArg.callArgIndex != UINT32_MAX)
            outFailure.addArgument(K_ARG_PREV_INDEX, previousArg.callArgIndex + 1);
        if (previousArg.diagRef.isValid())
        {
            outFailure.noteId  = DiagnosticId::sema_note_generic_previous_deduction;
            outFailure.nodeRef = previousArg.diagRef;
        }
    }

    void setGenericValueDeductionFailure(Sema& sema, CastFailure& outFailure, IdentifierRef idRef, const SemaGeneric::GenericResolvedArg& previousArg, ConstantRef newCstRef)
    {
        outFailure        = {};
        outFailure.diagId = DiagnosticId::sema_err_generic_value_deduction_conflict;
        outFailure.addArgument(Diagnostic::ARG_VALUE, Utf8{sema.idMgr().get(idRef).name});
        outFailure.addArgument(Diagnostic::ARG_LEFT, sema.cstMgr().get(previousArg.cstRef).toString(sema.ctx()));
        outFailure.addArgument(Diagnostic::ARG_RIGHT, sema.cstMgr().get(newCstRef).toString(sema.ctx()));
        if (previousArg.callArgIndex != UINT32_MAX)
            outFailure.addArgument(K_ARG_PREV_INDEX, previousArg.callArgIndex + 1);
        if (previousArg.diagRef.isValid())
        {
            outFailure.noteId  = DiagnosticId::sema_note_generic_previous_deduction;
            outFailure.nodeRef = previousArg.diagRef;
        }
    }

    uint32_t callArgIndexFromUserIndex(uint32_t userArgIndex, AstNodeRef ufcsArg, bool prependUfcsArg)
    {
        return prependUfcsArg && ufcsArg.isValid() ? (userArgIndex + 1) : userArgIndex;
    }

    bool isVariadicTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return false;

        const TypeRef unwrappedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        const TypeRef effectiveTypeRef = unwrappedTypeRef.isValid() ? unwrappedTypeRef : typeRef;
        return sema.typeMgr().get(effectiveTypeRef).isAnyVariadic();
    }

    TypeRef typeRefFromTypeNode(Sema& sema, AstNodeRef typeNodeRef)
    {
        if (typeNodeRef.isInvalid())
            return TypeRef::invalid();

        const TypeRef typeRef = sema.viewType(typeNodeRef).typeRef();
        if (typeRef.isValid())
            return typeRef;

        const AstNode& typeNode = sema.node(typeNodeRef);
        if (const auto* namedType = typeNode.safeCast<AstNamedType>())
        {
            const SemaNodeView identView = sema.viewNodeTypeSymbol(namedType->nodeIdentRef);
            if (identView.typeRef().isValid())
                return identView.typeRef();
            if (identView.sym() && identView.sym()->isType())
                return identView.sym()->typeRef();

            if (const auto* ident = sema.node(namedType->nodeIdentRef).safeCast<AstIdentifier>())
            {
                MatchContext lookUpCxt;
                lookUpCxt.codeRef         = ident->codeRef();
                lookUpCxt.noWaitOnEmpty   = true;
                const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
                if (Match::match(sema, lookUpCxt, idRef) == Result::Continue)
                {
                    for (const Symbol* sym : lookUpCxt.symbols())
                    {
                        if (sym && sym->isType() && sym->typeRef().isValid())
                            return sym->typeRef();
                    }
                }
            }
        }

        return TypeRef::invalid();
    }

    bool isVariadicTypeNode(Sema& sema, AstNodeRef typeNodeRef)
    {
        if (typeNodeRef.isInvalid())
            return false;

        const AstNode& typeNode = sema.node(typeNodeRef);
        if (typeNode.is(AstNodeId::VariadicType) || typeNode.is(AstNodeId::TypedVariadicType))
            return true;

        return isVariadicTypeRef(sema, typeRefFromTypeNode(sema, typeNodeRef));
    }

    void appendFunctionParamNodes(Sema& sema, AstNodeRef nodeParamsRef, SmallVector<AstNodeRef>& outParams)
    {
        outParams.clear();
        if (nodeParamsRef.isInvalid())
            return;

        const AstNode& paramsNode = sema.node(nodeParamsRef);
        if (paramsNode.is(AstNodeId::FunctionParamList))
        {
            sema.ast().appendNodes(outParams, paramsNode.cast<AstFunctionParamList>().spanChildrenRef);
            return;
        }

        paramsNode.collectChildrenFromAst(outParams, sema.ast());
    }

    void appendFunctionParamDesc(Sema& sema, AstNodeRef paramRef, SmallVector<SemaGeneric::GenericFunctionParamDesc>& outParams)
    {
        if (paramRef.isInvalid())
            return;

        const AstNode* paramNode = &sema.node(paramRef);
        while (paramNode->is(AstNodeId::AttributeList))
        {
            paramRef  = paramNode->cast<AstAttributeList>().nodeBodyRef;
            paramNode = &sema.node(paramRef);
        }

        if (paramNode->is(AstNodeId::VarDeclList))
        {
            SmallVector<AstNodeRef> vars;
            sema.ast().appendNodes(vars, paramNode->cast<AstVarDeclList>().spanChildrenRef);
            for (const AstNodeRef varRef : vars)
                appendFunctionParamDesc(sema, varRef, outParams);
            return;
        }

        if (paramNode->is(AstNodeId::SingleVarDecl))
        {
            const auto&                           varDecl = paramNode->cast<AstSingleVarDecl>();
            SemaGeneric::GenericFunctionParamDesc desc;
            desc.idRef           = SemaHelpers::resolveIdentifier(sema, {varDecl.srcViewRef(), varDecl.tokNameRef});
            desc.typeRef         = varDecl.typeOrInitRef();
            desc.defaultRef      = varDecl.nodeInitRef;
            desc.isVariadic      = isVariadicTypeNode(sema, desc.typeRef);
            desc.hasExplicitType = varDecl.nodeTypeRef.isValid();
            outParams.push_back(desc);
            return;
        }

        if (paramNode->is(AstNodeId::MultiVarDecl))
        {
            const auto&           multiVar = paramNode->cast<AstMultiVarDecl>();
            SmallVector<TokenRef> tokNames;
            sema.ast().appendTokens(tokNames, multiVar.spanNamesRef);
            for (const TokenRef tokNameRef : tokNames)
            {
                SemaGeneric::GenericFunctionParamDesc desc;
                desc.idRef           = SemaHelpers::resolveIdentifier(sema, {multiVar.srcViewRef(), tokNameRef});
                desc.typeRef         = multiVar.typeOrInitRef();
                desc.defaultRef      = multiVar.nodeInitRef;
                desc.isVariadic      = isVariadicTypeNode(sema, desc.typeRef);
                desc.hasExplicitType = multiVar.nodeTypeRef.isValid();
                outParams.push_back(desc);
            }
            return;
        }

        if (paramNode->is(AstNodeId::FunctionParamMe))
        {
            SemaGeneric::GenericFunctionParamDesc desc;
            desc.idRef      = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
            desc.isVariadic = false;
            outParams.push_back(desc);
        }
    }

    bool genericFunctionParamsExposeReceiver(const Sema& sema, std::span<const SemaGeneric::GenericFunctionParamDesc> params)
    {
        return !params.empty() && params.front().idRef == sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
    }

    bool isMissingGenericParam(std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, IdentifierRef idRef)
    {
        for (size_t i = 0; i < params.size(); ++i)
        {
            if (params[i].idRef == idRef && !resolvedArgs[i].present)
                return true;
        }

        return false;
    }

    bool patternCanDeduceMissingGenericParam(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef patternRef)
    {
        if (patternRef.isInvalid())
            return false;

        const AstNode& patternNode = sema.node(patternRef);
        if (const auto* ident = patternNode.safeCast<AstIdentifier>())
        {
            const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
            return isMissingGenericParam(params, resolvedArgs, idRef);
        }

        SmallVector<AstNodeRef> children;
        patternNode.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
        {
            if (patternCanDeduceMissingGenericParam(sema, params, resolvedArgs, childRef))
                return true;
        }

        return false;
    }

    struct GenericCallArgMapping
    {
        SmallVector<SemaGeneric::GenericCallArgEntry> paramArgs;
        SmallVector<SemaGeneric::GenericCallArgEntry> variadicArgs;
    };

    bool tryBindGenericTypeParam(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, IdentifierRef idRef, AstNodeRef exprRef, uint32_t callArgIndex, TypeRef typeRef, CastFailure* outFailure, DeductionMode mode)
    {
        for (size_t i = 0; i < params.size(); ++i)
        {
            if (params[i].kind != SemaGeneric::GenericParamKind::Type || params[i].idRef != idRef)
                continue;

            SemaGeneric::GenericResolvedArg& arg = resolvedArgs[i];
            if (!arg.present)
            {
                arg.present      = true;
                arg.diagRef      = exprRef;
                arg.typeRef      = typeRef;
                arg.callArgIndex = callArgIndex;
                return true;
            }

            if (mode == DeductionMode::MissingOnly)
                return true;

            if (arg.typeRef == typeRef)
                return true;

            const TypeInfo& previousType = sema.typeMgr().get(arg.typeRef);
            const TypeInfo& newType      = sema.typeMgr().get(typeRef);
            if (previousType.isScalarUnsized() && !newType.isScalarUnsized())
            {
                arg.typeRef = typeRef;
                return true;
            }

            if (!previousType.isScalarUnsized() && newType.isScalarUnsized())
                return true;

            if (outFailure)
                setGenericTypeDeductionFailure(sema, *outFailure, idRef, arg, typeRef);
            return false;
        }

        return true;
    }

    bool tryBindGenericValueParam(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, IdentifierRef idRef, AstNodeRef exprRef, uint32_t callArgIndex, ConstantRef cstRef, TypeRef typeRef, CastFailure* outFailure, DeductionMode mode)
    {
        for (size_t i = 0; i < params.size(); ++i)
        {
            if (params[i].kind != SemaGeneric::GenericParamKind::Value || params[i].idRef != idRef)
                continue;

            SemaGeneric::GenericResolvedArg& arg = resolvedArgs[i];
            if (!arg.present)
            {
                arg.present      = true;
                arg.diagRef      = exprRef;
                arg.typeRef      = typeRef;
                arg.cstRef       = cstRef;
                arg.callArgIndex = callArgIndex;
                return true;
            }

            if (mode == DeductionMode::MissingOnly)
                return true;

            if (arg.cstRef == cstRef)
                return true;

            if (outFailure)
                setGenericValueDeductionFailure(sema, *outFailure, idRef, arg, cstRef);
            return false;
        }

        return true;
    }

    void collectQuotedGenericArgs(const AstQuotedExpr& node, SmallVector<AstNodeRef>& outArgs)
    {
        outArgs.clear();
        if (node.nodeSuffixRef.isValid())
            outArgs.push_back(node.nodeSuffixRef);
    }

    void collectQuotedGenericArgs(Sema& sema, const AstQuotedListExpr& node, SmallVector<AstNodeRef>& outArgs)
    {
        outArgs.clear();
        sema.ast().appendNodes(outArgs, node.spanChildrenRef);
    }

    bool tryGetStructPatternGenericArgs(Sema& sema, AstNodeRef identRef, const SymbolStruct*& outGenericRoot, IdentifierRef& outGenericRootIdRef, SmallVector<AstNodeRef>& outGenericArgs)
    {
        outGenericRoot      = nullptr;
        outGenericRootIdRef = IdentifierRef::invalid();
        outGenericArgs.clear();
        if (identRef.isInvalid())
            return false;

        AstNodeRef     exprRef   = AstNodeRef::invalid();
        const AstNode& identNode = sema.node(identRef);
        if (const auto* quotedExpr = identNode.safeCast<AstQuotedExpr>())
        {
            exprRef = quotedExpr->nodeExprRef;
            collectQuotedGenericArgs(*quotedExpr, outGenericArgs);
        }
        else if (const auto* quotedList = identNode.safeCast<AstQuotedListExpr>())
        {
            exprRef = quotedList->nodeExprRef;
            collectQuotedGenericArgs(sema, *quotedList, outGenericArgs);
        }
        else
        {
            return false;
        }

        if (const auto* ident = sema.node(exprRef).safeCast<AstIdentifier>())
            outGenericRootIdRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());

        SmallVector<Symbol*> baseSymbols;
        const SemaNodeView   baseView(sema, exprRef, SemaNodeViewPartE::Symbol, SemaNodeViewResolveE::Stored);
        baseView.getSymbols(baseSymbols);
        for (auto* sym : baseSymbols)
        {
            if (!sym || !sym->isStruct())
                continue;

            auto& symStruct = sym->cast<SymbolStruct>();
            if (!symStruct.isGenericRoot())
                continue;

            outGenericRoot      = &symStruct;
            outGenericRootIdRef = symStruct.idRef();
            break;
        }

        if (!outGenericRoot && outGenericRootIdRef.isValid())
        {
            MatchContext lookUpCxt;
            lookUpCxt.codeRef       = sema.node(exprRef).codeRef();
            lookUpCxt.noWaitOnEmpty = true;
            if (Match::match(sema, lookUpCxt, outGenericRootIdRef) == Result::Continue)
            {
                for (const Symbol* sym : lookUpCxt.symbols())
                {
                    if (!sym || !sym->isStruct())
                        continue;

                    const auto& symStruct = sym->cast<SymbolStruct>();
                    if (!symStruct.isGenericRoot())
                        continue;

                    outGenericRoot      = &symStruct;
                    outGenericRootIdRef = symStruct.idRef();
                    break;
                }
            }
        }

        return outGenericRoot != nullptr || outGenericRootIdRef.isValid();
    }

    Result deduceFromValuePattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef patternRef, ConstantRef cstRef, TypeRef typeRef, AstNodeRef argExprRef, uint32_t callArgIndex, CastFailure* outFailure, DeductionMode mode)
    {
        if (patternRef.isInvalid() || !cstRef.isValid())
            return Result::Continue;

        const AstNode& patternNode = sema.node(patternRef);
        if (const auto* ident = patternNode.safeCast<AstIdentifier>())
        {
            const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
            if (!tryBindGenericValueParam(sema, params, resolvedArgs, idRef, argExprRef, callArgIndex, cstRef, typeRef, outFailure, mode))
                return Result::Error;
            return Result::Continue;
        }

        const SemaNodeView patternView = sema.viewNodeTypeConstant(patternRef);
        if (patternView.cstRef().isValid())
            return patternView.cstRef() == cstRef ? Result::Continue : Result::Error;

        return Result::Continue;
    }

    bool buildAggregateFieldOrder(std::span<const SemaGeneric::GenericFunctionParamDesc> patternFields, const auto& actualAggregate, SmallVector<size_t>& outOrder, bool allowPartial = false)
    {
        if (actualAggregate.types.size() > patternFields.size())
            return false;
        if (!allowPartial && patternFields.size() != actualAggregate.types.size())
            return false;

        outOrder.resize(patternFields.size());
        for (size_t& index : outOrder)
            index = SIZE_MAX;
        SmallVector<bool> usedActualEntries(actualAggregate.types.size(), false);

        for (size_t actualIndex = 0; actualIndex < actualAggregate.types.size(); ++actualIndex)
        {
            const IdentifierRef actualIdRef = actualIndex < actualAggregate.names.size() ? actualAggregate.names[actualIndex] : IdentifierRef::invalid();
            if (!actualIdRef.isValid())
                continue;

            size_t patternIndex = 0;
            for (; patternIndex < patternFields.size(); ++patternIndex)
            {
                if (patternFields[patternIndex].idRef == actualIdRef)
                    break;
            }

            if (patternIndex == patternFields.size() || outOrder[patternIndex] != SIZE_MAX)
                return false;

            outOrder[patternIndex]         = actualIndex;
            usedActualEntries[actualIndex] = true;
        }

        size_t nextUnnamedActualIndex = 0;
        for (size_t patternIndex = 0; patternIndex < patternFields.size(); ++patternIndex)
        {
            if (outOrder[patternIndex] != SIZE_MAX)
                continue;

            while (nextUnnamedActualIndex < actualAggregate.types.size())
            {
                const IdentifierRef actualIdRef = nextUnnamedActualIndex < actualAggregate.names.size() ? actualAggregate.names[nextUnnamedActualIndex] : IdentifierRef::invalid();
                if (!usedActualEntries[nextUnnamedActualIndex] && !actualIdRef.isValid())
                    break;
                ++nextUnnamedActualIndex;
            }

            if (nextUnnamedActualIndex == actualAggregate.types.size())
            {
                if (allowPartial)
                    break;
                return false;
            }

            outOrder[patternIndex]                    = nextUnnamedActualIndex;
            usedActualEntries[nextUnnamedActualIndex] = true;
            ++nextUnnamedActualIndex;
        }

        return true;
    }

    void collectStructFieldDescs(Sema& sema, const SymbolStruct& root, const AstNode& declNode, SmallVector<SemaGeneric::GenericFunctionParamDesc>& outFields)
    {
        outFields.clear();
        const auto& symbolFields = root.fields();
        if (!symbolFields.empty())
        {
            outFields.reserve(symbolFields.size());
            for (const SymbolVariable* symField : symbolFields)
            {
                if (!symField || !symField->decl())
                    continue;

                if (const auto* varDecl = symField->decl()->safeCast<AstSingleVarDecl>())
                {
                    SemaGeneric::GenericFunctionParamDesc desc;
                    desc.idRef           = symField->idRef();
                    desc.typeRef         = varDecl->typeOrInitRef();
                    desc.defaultRef      = varDecl->nodeInitRef;
                    desc.isVariadic      = isVariadicTypeRef(sema, symField->typeRef()) || isVariadicTypeNode(sema, desc.typeRef);
                    desc.hasExplicitType = varDecl->nodeTypeRef.isValid();
                    outFields.push_back(desc);
                }
            }

            if (!outFields.empty())
                return;
        }

        const AstNodeRef bodyRef = genericStructBodyRef(declNode);
        if (bodyRef.isInvalid())
            return;

        SmallVector<AstNodeRef> fields;
        sema.node(bodyRef).collectChildrenFromAst(fields, sema.ast());
        outFields.reserve(fields.size());
        for (const AstNodeRef fieldRef : fields)
            appendFunctionParamDesc(sema, fieldRef, outFields);
    }

    Result deduceFromAggregateStructPattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, const AstNamedType& namedType, const TypeInfo& argType, AstNodeRef argExprRef, uint32_t callArgIndex, CastFailure* outFailure, DeductionMode mode)
    {
        if (!argType.isAggregateStruct())
            return Result::Continue;

        const SymbolStruct*     patternRoot      = nullptr;
        IdentifierRef           patternRootIdRef = IdentifierRef::invalid();
        SmallVector<AstNodeRef> patternArgs;
        if (!tryGetStructPatternGenericArgs(sema, namedType.nodeIdentRef, patternRoot, patternRootIdRef, patternArgs) || !patternRoot)
            return Result::Continue;

        const auto* rootDecl = genericStructDeclNode(*patternRoot);
        if (!rootDecl)
            return Result::Continue;

        std::unique_ptr<Sema> rootSemaHolder;
        Sema&                 rootSema = semaForStructDecl(sema, *patternRoot, rootSemaHolder);

        SmallVector<SemaGeneric::GenericParamDesc> rootParams;
        const SpanRef                              rootParamSpan = genericStructParamSpan(*rootDecl);
        SemaGeneric::collectGenericParams(rootSema, *rootDecl, rootParamSpan, rootParams);
        if (rootParams.size() != patternArgs.size())
            return Result::Continue;

        SmallVector<SemaGeneric::GenericFunctionParamDesc> rootFields;
        collectStructFieldDescs(rootSema, *patternRoot, *rootDecl, rootFields);
        const auto&         actualAggregate = argType.payloadAggregate();
        SmallVector<size_t> actualFieldOrder;
        if (!buildAggregateFieldOrder(rootFields.span(), actualAggregate, actualFieldOrder, patternRoot->isUnion()))
            return Result::Continue;

        SmallVector<SemaGeneric::GenericResolvedArg> rootResolvedArgs(rootParams.size());
        CastFailure                                  trialFailure{};
        for (size_t i = 0; i < rootFields.size(); ++i)
        {
            if (rootFields[i].typeRef.isInvalid())
                return Result::Continue;

            const size_t actualFieldIndex = actualFieldOrder[i];
            if (actualFieldIndex == SIZE_MAX)
                continue;
            if (deduceFromTypePattern(rootSema, rootParams.span(), rootResolvedArgs.span(), rootFields[i].typeRef, actualAggregate.types[actualFieldIndex], argExprRef, callArgIndex, outFailure ? &trialFailure : nullptr, mode) == Result::Error)
                return Result::Continue;
        }

        SmallVector<SemaGeneric::GenericResolvedArg> trialResolvedArgs;
        trialResolvedArgs.assign(resolvedArgs.begin(), resolvedArgs.end());
        for (size_t i = 0; i < rootResolvedArgs.size(); ++i)
        {
            const auto& rootArg = rootResolvedArgs[i];
            if (!rootArg.present)
                continue;

            auto result = Result::Continue;
            if (rootParams[i].kind == SemaGeneric::GenericParamKind::Value && rootArg.cstRef.isValid())
                result = deduceFromValuePattern(sema, params, trialResolvedArgs.span(), patternArgs[i], rootArg.cstRef, rootArg.typeRef, argExprRef, callArgIndex, outFailure ? &trialFailure : nullptr, mode);
            else if (rootArg.typeRef.isValid())
                result = deduceFromTypePattern(sema, params, trialResolvedArgs.span(), patternArgs[i], rootArg.typeRef, argExprRef, callArgIndex, outFailure ? &trialFailure : nullptr, mode);

            if (result == Result::Error)
                return Result::Continue;
        }

        std::ranges::copy(trialResolvedArgs, resolvedArgs.begin());
        return Result::Continue;
    }

    Result deduceFromStructPattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, const AstNamedType& namedType, const TypeInfo& argType, AstNodeRef argExprRef, uint32_t callArgIndex, CastFailure* outFailure, DeductionMode mode)
    {
        if (argType.isAggregateStruct())
            return deduceFromAggregateStructPattern(sema, params, resolvedArgs, namedType, argType, argExprRef, callArgIndex, outFailure, mode);

        if (!argType.isStruct())
            return Result::Continue;

        const SymbolStruct& argStruct = argType.payloadSymStruct();
        if (!argStruct.isGenericInstance())
            return Result::Continue;

        const SymbolStruct*     patternRoot      = nullptr;
        IdentifierRef           patternRootIdRef = IdentifierRef::invalid();
        SmallVector<AstNodeRef> patternArgs;
        if (!tryGetStructPatternGenericArgs(sema, namedType.nodeIdentRef, patternRoot, patternRootIdRef, patternArgs))
            return Result::Continue;

        const SymbolStruct* actualRoot = argStruct.genericRootSym();
        if (!actualRoot)
            return Result::Continue;
        if (patternRoot && actualRoot != patternRoot)
            return Result::Continue;
        if (!patternRoot && (!patternRootIdRef.isValid() || actualRoot->idRef() != patternRootIdRef))
            return Result::Continue;

        SmallVector<GenericInstanceKey> actualArgs;
        if (!actualRoot->tryGetGenericInstanceArgs(argStruct, actualArgs))
            return Result::Continue;
        if (patternArgs.size() != actualArgs.size())
            return Result::Continue;

        SmallVector<SemaGeneric::GenericResolvedArg> trialResolvedArgs;
        trialResolvedArgs.assign(resolvedArgs.begin(), resolvedArgs.end());
        CastFailure trialFailure{};
        for (size_t i = 0; i < actualArgs.size(); ++i)
        {
            auto result = Result::Continue;
            if (actualArgs[i].typeRef.isValid())
                result = deduceFromTypePattern(sema, params, trialResolvedArgs.span(), patternArgs[i], actualArgs[i].typeRef, argExprRef, callArgIndex, outFailure ? &trialFailure : nullptr, mode);
            else if (actualArgs[i].cstRef.isValid())
                result = deduceFromValuePattern(sema, params, trialResolvedArgs.span(), patternArgs[i], actualArgs[i].cstRef, actualArgs[i].typeRef, argExprRef, callArgIndex, outFailure ? &trialFailure : nullptr, mode);

            if (result == Result::Error)
                return Result::Continue;
        }

        std::ranges::copy(trialResolvedArgs, resolvedArgs.begin());
        return Result::Continue;
    }

    Result deduceFromFunctionPattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, const AstLambdaType& lambdaType, const TypeInfo& argType, AstNodeRef argExprRef, uint32_t callArgIndex, const CastFailure* outFailure, DeductionMode mode)
    {
        if (!argType.isFunction())
            return Result::Continue;

        const SymbolFunction& argFunction = argType.payloadSymFunction();

        SmallVector<AstNodeRef> patternParams;
        sema.ast().appendNodes(patternParams, lambdaType.spanParamsRef);
        const auto& argParams = argFunction.parameters();
        if (patternParams.size() != argParams.size())
            return Result::Continue;

        SmallVector<SemaGeneric::GenericResolvedArg> trialResolvedArgs;
        trialResolvedArgs.assign(resolvedArgs.begin(), resolvedArgs.end());
        CastFailure trialFailure{};

        for (size_t i = 0; i < patternParams.size(); ++i)
        {
            const AstLambdaParam& patternParam = sema.node(patternParams[i]).cast<AstLambdaParam>();
            if (patternParam.nodeTypeRef.isInvalid())
                continue;
            if (deduceFromTypePattern(sema, params, trialResolvedArgs.span(), patternParam.nodeTypeRef, argParams[i]->typeRef(), argExprRef, callArgIndex, outFailure ? &trialFailure : nullptr, mode) == Result::Error)
                return Result::Continue;
        }

        if (lambdaType.nodeReturnTypeRef.isValid())
        {
            if (deduceFromTypePattern(sema, params, trialResolvedArgs.span(), lambdaType.nodeReturnTypeRef, argFunction.returnTypeRef(), argExprRef, callArgIndex, outFailure ? &trialFailure : nullptr, mode) == Result::Error)
                return Result::Continue;
        }

        std::ranges::copy(trialResolvedArgs, resolvedArgs.begin());
        return Result::Continue;
    }

    void collectAnonymousAggregateFieldDescs(Sema& sema, AstNodeRef patternRef, SmallVector<SemaGeneric::GenericFunctionParamDesc>& outFields)
    {
        outFields.clear();

        AstNodeRef     bodyRef     = AstNodeRef::invalid();
        const AstNode& patternNode = sema.node(patternRef);
        if (const auto* structDecl = patternNode.safeCast<AstAnonymousStructDecl>())
            bodyRef = structDecl->nodeBodyRef;
        else if (const auto* unionDecl = patternNode.safeCast<AstAnonymousUnionDecl>())
            bodyRef = unionDecl->nodeBodyRef;
        if (bodyRef.isInvalid())
            return;

        SmallVector<AstNodeRef> fields;
        sema.node(bodyRef).collectChildrenFromAst(fields, sema.ast());
        outFields.reserve(fields.size());
        for (const AstNodeRef fieldRef : fields)
            appendFunctionParamDesc(sema, fieldRef, outFields);
    }

    Result deduceFromAnonymousStructPattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef patternRef, const TypeInfo& argType, AstNodeRef argExprRef, uint32_t callArgIndex, CastFailure* outFailure, DeductionMode mode)
    {
        SmallVector<SemaGeneric::GenericFunctionParamDesc> patternFields;
        collectAnonymousAggregateFieldDescs(sema, patternRef, patternFields);
        if (patternFields.empty())
            return Result::Continue;

        if (argType.isStruct())
        {
            SWC_RESULT(sema.waitSemaCompleted(&argType, argExprRef));
            const auto& actualFields = argType.payloadSymStruct().fields();
            if (patternFields.size() != actualFields.size())
                return Result::Continue;

            SmallVector<SemaGeneric::GenericResolvedArg> trialResolvedArgs;
            trialResolvedArgs.assign(resolvedArgs.begin(), resolvedArgs.end());
            CastFailure trialFailure{};
            for (size_t i = 0; i < patternFields.size(); ++i)
            {
                const SymbolVariable* actualField = actualFields[i];
                if (!actualField || patternFields[i].idRef != actualField->idRef() || patternFields[i].typeRef.isInvalid())
                    return Result::Continue;

                if (deduceFromTypePattern(sema, params, trialResolvedArgs.span(), patternFields[i].typeRef, actualField->typeRef(), argExprRef, callArgIndex, outFailure ? &trialFailure : nullptr, mode) == Result::Error)
                    return Result::Continue;
            }

            std::ranges::copy(trialResolvedArgs, resolvedArgs.begin());
            return Result::Continue;
        }

        if (!argType.isAggregateStruct())
            return Result::Continue;

        const auto&         actualAggregate = argType.payloadAggregate();
        SmallVector<size_t> actualFieldOrder;
        const bool          allowPartial = sema.node(patternRef).is(AstNodeId::AnonymousUnionDecl);
        if (!buildAggregateFieldOrder(patternFields.span(), actualAggregate, actualFieldOrder, allowPartial))
            return Result::Continue;

        SmallVector<SemaGeneric::GenericResolvedArg> trialResolvedArgs;
        trialResolvedArgs.assign(resolvedArgs.begin(), resolvedArgs.end());
        CastFailure trialFailure{};
        for (size_t i = 0; i < patternFields.size(); ++i)
        {
            if (patternFields[i].typeRef.isInvalid())
                return Result::Continue;

            const size_t actualFieldIndex = actualFieldOrder[i];
            if (actualFieldIndex == SIZE_MAX)
                continue;
            if (deduceFromTypePattern(sema, params, trialResolvedArgs.span(), patternFields[i].typeRef, actualAggregate.types[actualFieldIndex], argExprRef, callArgIndex, outFailure ? &trialFailure : nullptr, mode) == Result::Error)
                return Result::Continue;
        }

        std::ranges::copy(trialResolvedArgs, resolvedArgs.begin());
        return Result::Continue;
    }

    bool tryDeduceAggregateArrayDimension(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef dimRef, size_t actualSize, AstNodeRef argExprRef, uint32_t callArgIndex, CastFailure* outFailure, DeductionMode mode)
    {
        if (dimRef.isInvalid())
            return true;

        const ConstantRef actualSizeRef = sema.cstMgr().addInt(sema.ctx(), actualSize);
        const AstNode&    dimNode       = sema.node(dimRef);
        if (const auto* ident = dimNode.safeCast<AstIdentifier>())
        {
            const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
            return tryBindGenericValueParam(sema, params, resolvedArgs, idRef, argExprRef, callArgIndex, actualSizeRef, sema.cstMgr().get(actualSizeRef).typeRef(), outFailure, mode);
        }

        const SemaNodeView dimView = sema.viewNodeTypeConstant(dimRef);
        if (dimView.cstRef().isValid())
            return sema.cstMgr().get(dimView.cstRef()) == sema.cstMgr().get(actualSizeRef);

        return true;
    }

    bool deduceFromAggregateArrayPatternRec(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, std::span<const AstNodeRef> dims, size_t dimIndex, AstNodeRef elemPatternRef, const TypeInfo& argType, AstNodeRef argExprRef, uint32_t callArgIndex, CastFailure* outFailure, DeductionMode mode)
    {
        if (!argType.isAggregateArray())
            return false;

        const auto& aggregate = argType.payloadAggregate();
        if (aggregate.types.empty())
            return false;

        if (dimIndex < dims.size() && !tryDeduceAggregateArrayDimension(sema, params, resolvedArgs, dims[dimIndex], aggregate.types.size(), argExprRef, callArgIndex, outFailure, mode))
            return false;

        const bool hasNestedDims = dimIndex + 1 < dims.size();
        for (const TypeRef elemTypeRef : aggregate.types)
        {
            if (hasNestedDims)
            {
                const TypeInfo& elemType = sema.typeMgr().get(SemaGeneric::unwrapGenericDeductionType(sema.ctx(), elemTypeRef));
                if (!deduceFromAggregateArrayPatternRec(sema, params, resolvedArgs, dims, dimIndex + 1, elemPatternRef, elemType, argExprRef, callArgIndex, outFailure, mode))
                    return false;
                continue;
            }

            if (deduceFromTypePattern(sema, params, resolvedArgs, elemPatternRef, elemTypeRef, argExprRef, callArgIndex, outFailure, mode) == Result::Error)
                return false;
        }

        return true;
    }

    Result deduceFromAggregateArrayElementsPattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, std::span<const AstNodeRef> dims, AstNodeRef elemPatternRef, const TypeInfo& argType, AstNodeRef argExprRef, uint32_t callArgIndex, const CastFailure* outFailure, DeductionMode mode)
    {
        if (!argType.isAggregateArray())
            return Result::Continue;

        SmallVector<SemaGeneric::GenericResolvedArg> trialResolvedArgs;
        trialResolvedArgs.assign(resolvedArgs.begin(), resolvedArgs.end());
        CastFailure trialFailure{};
        if (!deduceFromAggregateArrayPatternRec(sema, params, trialResolvedArgs.span(), dims, 0, elemPatternRef, argType, argExprRef, callArgIndex, outFailure ? &trialFailure : nullptr, mode))
            return Result::Continue;

        std::ranges::copy(trialResolvedArgs, resolvedArgs.begin());
        return Result::Continue;
    }

    Result deduceFromAggregateArrayPattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, const AstArrayType& arrayType, const TypeInfo& argType, AstNodeRef argExprRef, uint32_t callArgIndex, const CastFailure* outFailure, DeductionMode mode)
    {
        SmallVector<AstNodeRef> dims;
        sema.ast().appendNodes(dims, arrayType.spanDimensionsRef);
        return deduceFromAggregateArrayElementsPattern(sema, params, resolvedArgs, dims.span(), arrayType.nodePointeeTypeRef, argType, argExprRef, callArgIndex, outFailure, mode);
    }

    Result deduceFromTypePattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef patternRef, TypeRef rawArgTypeRef, AstNodeRef argExprRef, uint32_t callArgIndex, CastFailure* outFailure, DeductionMode mode)
    {
        if (patternRef.isInvalid() || !rawArgTypeRef.isValid())
            return Result::Continue;

        const AstNode& patternNode = sema.node(patternRef);
        if (const auto* ident = patternNode.safeCast<AstIdentifier>())
        {
            const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
            if (!tryBindGenericTypeParam(sema, params, resolvedArgs, idRef, argExprRef, callArgIndex, rawArgTypeRef, outFailure, mode))
                return Result::Error;

            return Result::Continue;
        }

        const auto* namedType = patternNode.safeCast<AstNamedType>();
        if (namedType)
        {
            const AstNode& identNode = sema.node(namedType->nodeIdentRef);
            if (const auto* ident = identNode.safeCast<AstIdentifier>())
            {
                const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
                if (!tryBindGenericTypeParam(sema, params, resolvedArgs, idRef, argExprRef, callArgIndex, rawArgTypeRef, outFailure, mode))
                    return Result::Error;

                return Result::Continue;
            }
        }

        const TypeRef      argTypeRef = SemaGeneric::unwrapGenericDeductionType(sema.ctx(), rawArgTypeRef);
        const TypeInfo&    argType    = sema.typeMgr().get(argTypeRef);
        const TaskContext& ctx        = sema.ctx();

        if (namedType)
            return deduceFromStructPattern(sema, params, resolvedArgs, *namedType, argType, argExprRef, callArgIndex, outFailure, mode);

        if (const auto* lambdaType = patternNode.safeCast<AstLambdaType>())
            return deduceFromFunctionPattern(sema, params, resolvedArgs, *lambdaType, argType, argExprRef, callArgIndex, outFailure, mode);

        if (const auto* codeType = patternNode.safeCast<AstCodeType>())
        {
            if (!argType.isCodeBlock())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, codeType->nodeTypeRef, argType.payloadTypeRef(), argExprRef, callArgIndex, outFailure, mode);
        }

        if (patternNode.is(AstNodeId::AnonymousStructDecl) || patternNode.is(AstNodeId::AnonymousUnionDecl))
            return deduceFromAnonymousStructPattern(sema, params, resolvedArgs, patternRef, argType, argExprRef, callArgIndex, outFailure, mode);

        if (const auto* arrayType = patternNode.safeCast<AstArrayType>())
        {
            if (argType.isAggregateArray())
                return deduceFromAggregateArrayPattern(sema, params, resolvedArgs, *arrayType, argType, argExprRef, callArgIndex, outFailure, mode);

            if (!argType.isArray())
                return Result::Continue;

            SmallVector<AstNodeRef> dims;
            sema.ast().appendNodes(dims, arrayType->spanDimensionsRef);
            const auto& argDims = argType.payloadArrayDims();
            if (arrayType->spanDimensionsRef.isValid() && dims.size() != argDims.size())
                return Result::Continue;

            for (size_t i = 0; i < dims.size(); ++i)
            {
                const AstNode& dimNode = sema.node(dims[i]);
                if (const auto* ident = dimNode.safeCast<AstIdentifier>())
                {
                    const IdentifierRef idRef  = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
                    const ConstantRef   cstRef = sema.cstMgr().addInt(ctx, argDims[i]);
                    if (!tryBindGenericValueParam(sema, params, resolvedArgs, idRef, argExprRef, callArgIndex, cstRef, sema.cstMgr().get(cstRef).typeRef(), outFailure, mode))
                        return Result::Error;
                }
            }

            return deduceFromTypePattern(sema, params, resolvedArgs, arrayType->nodePointeeTypeRef, argType.payloadArrayElemTypeRef(), argExprRef, callArgIndex, outFailure, mode);
        }

        if (const auto* sliceType = patternNode.safeCast<AstSliceType>())
        {
            if (argType.isAggregateArray())
                return deduceFromAggregateArrayElementsPattern(sema, params, resolvedArgs, {}, sliceType->nodePointeeTypeRef, argType, argExprRef, callArgIndex, outFailure, mode);

            if (argType.isString())
                return deduceFromTypePattern(sema, params, resolvedArgs, sliceType->nodePointeeTypeRef, sema.typeMgr().typeU8(), argExprRef, callArgIndex, outFailure, mode);

            if (!argType.isSlice())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, sliceType->nodePointeeTypeRef, argType.payloadTypeRef(), argExprRef, callArgIndex, outFailure, mode);
        }

        if (const auto* refType = patternNode.safeCast<AstReferenceType>())
        {
            if (!argType.isReference())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, refType->nodePointeeTypeRef, argType.payloadTypeRef(), argExprRef, callArgIndex, outFailure, mode);
        }

        if (const auto* moveRefType = patternNode.safeCast<AstMoveRefType>())
        {
            if (!argType.isMoveReference())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, moveRefType->nodePointeeTypeRef, argType.payloadTypeRef(), argExprRef, callArgIndex, outFailure, mode);
        }

        if (const auto* valuePtrType = patternNode.safeCast<AstValuePointerType>())
        {
            if (!argType.isAnyPointer())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, valuePtrType->nodePointeeTypeRef, argType.payloadTypeRef(), argExprRef, callArgIndex, outFailure, mode);
        }

        if (const auto* blockPtrType = patternNode.safeCast<AstBlockPointerType>())
        {
            if (!argType.isAnyPointer())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, blockPtrType->nodePointeeTypeRef, argType.payloadTypeRef(), argExprRef, callArgIndex, outFailure, mode);
        }

        if (const auto* qualifiedType = patternNode.safeCast<AstQualifiedType>())
            return deduceFromTypePattern(sema, params, resolvedArgs, qualifiedType->nodeTypeRef, rawArgTypeRef, argExprRef, callArgIndex, outFailure, mode);

        if (const auto* variadicType = patternNode.safeCast<AstTypedVariadicType>())
        {
            if (!argType.isTypedVariadic())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, variadicType->nodeTypeRef, argType.payloadTypeRef(), argExprRef, callArgIndex, outFailure, mode);
        }

        return Result::Continue;
    }

    void collectFunctionParamDescs(Sema& sema, const SymbolFunction& root, const AstFunctionDecl& decl, SmallVector<SemaGeneric::GenericFunctionParamDesc>& outParams)
    {
        outParams.clear();
        std::unique_ptr<Sema> declSemaHolder;
        Sema&                 declSema     = semaForFunctionDecl(sema, root, declSemaHolder);
        const auto&           symbolParams = root.parameters();
        if (!symbolParams.empty())
        {
            outParams.reserve(symbolParams.size());
            for (const SymbolVariable* symParam : symbolParams)
            {
                if (!symParam || !symParam->decl())
                    continue;

                const AstNode* paramNode = symParam->decl();
                if (paramNode->is(AstNodeId::SingleVarDecl))
                {
                    const auto&                           varDecl = paramNode->cast<AstSingleVarDecl>();
                    SemaGeneric::GenericFunctionParamDesc desc;
                    desc.idRef           = symParam->idRef();
                    desc.typeRef         = varDecl.typeOrInitRef();
                    desc.defaultRef      = varDecl.nodeInitRef;
                    desc.isVariadic      = isVariadicTypeRef(declSema, symParam->typeRef()) || isVariadicTypeNode(declSema, desc.typeRef);
                    desc.hasExplicitType = varDecl.nodeTypeRef.isValid();
                    outParams.push_back(desc);
                }
                else if (paramNode->is(AstNodeId::FunctionParamMe))
                {
                    SemaGeneric::GenericFunctionParamDesc desc;
                    desc.idRef      = declSema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
                    desc.isVariadic = false;
                    outParams.push_back(desc);
                }
            }

            if (!outParams.empty())
                return;
        }

        if (decl.nodeParamsRef.isInvalid())
            return;

        SmallVector<AstNodeRef> params;
        appendFunctionParamNodes(declSema, decl.nodeParamsRef, params);
        outParams.reserve(params.size());

        for (const AstNodeRef paramRef : params)
            appendFunctionParamDesc(declSema, paramRef, outParams);
    }

    AstNodeRef typedVariadicElementTypeRef(Sema& sema, AstNodeRef typeRef)
    {
        if (typeRef.isInvalid())
            return AstNodeRef::invalid();

        if (const auto* variadicType = sema.node(typeRef).safeCast<AstTypedVariadicType>())
            return variadicType->nodeTypeRef;

        return AstNodeRef::invalid();
    }

    Result resolveCallArgTypeForGenericDeduction(Sema& sema, TypeRef& outTypeRef, AstNodeRef valueArgRef)
    {
        SemaNodeView argView = sema.viewNodeTypeConstant(valueArgRef);
        outTypeRef           = argView.typeRef();
        if (!argView.cstRef().isValid())
            return Result::Continue;

        if (!outTypeRef.isValid())
            outTypeRef = sema.cstMgr().get(argView.cstRef()).typeRef();

        if (!outTypeRef.isValid())
        {
            ConstantRef newCstRef = ConstantRef::invalid();
            SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, valueArgRef, argView.cstRef(), TypeInfo::Sign::Unknown));
            if (!newCstRef.isValid())
                return Result::Continue;

            sema.setConstant(valueArgRef, newCstRef);
            argView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            outTypeRef = argView.typeRef();
            return Result::Continue;
        }

        const TypeInfo& argType = sema.typeMgr().get(outTypeRef);
        if (!argType.isIntUnsized())
            return Result::Continue;

        ConstantRef newCstRef = ConstantRef::invalid();
        SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, valueArgRef, argView.cstRef(), TypeInfo::Sign::Unknown));
        if (!newCstRef.isValid())
            return Result::Continue;

        sema.setConstant(valueArgRef, newCstRef);
        outTypeRef = sema.cstMgr().get(newCstRef).typeRef();
        return Result::Continue;
    }

    bool buildGenericCallArgMapping(Sema& sema, std::span<const SemaGeneric::GenericFunctionParamDesc> params, std::span<AstNodeRef> args, AstNodeRef ufcsArg, bool prependUfcsArg, GenericCallArgMapping& outMapping)
    {
        outMapping = {};

        const uint32_t numParams  = static_cast<uint32_t>(params.size());
        const uint32_t paramStart = prependUfcsArg && ufcsArg.isValid() ? 1u : 0u;
        outMapping.paramArgs.resize(numParams);

        if (prependUfcsArg && ufcsArg.isValid() && numParams > 0)
        {
            outMapping.paramArgs[0].argRef       = ufcsArg;
            outMapping.paramArgs[0].callArgIndex = 0;
        }

        bool     seenNamed = false;
        uint32_t nextPos   = paramStart;

        for (uint32_t userIndex = 0; userIndex < args.size(); ++userIndex)
        {
            const AstNodeRef argRef  = args[userIndex];
            const AstNode&   argNode = sema.node(argRef);

            if (argNode.is(AstNodeId::NamedArgument))
            {
                seenNamed = true;

                const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), argNode.codeRef());
                int32_t             found = -1;
                for (uint32_t i = paramStart; i < numParams; ++i)
                {
                    if (params[i].idRef == idRef)
                    {
                        found = static_cast<int32_t>(i);
                        break;
                    }
                }

                if (found < 0 || outMapping.paramArgs[found].argRef.isValid())
                    return false;

                outMapping.paramArgs[found].argRef       = argRef;
                outMapping.paramArgs[found].callArgIndex = callArgIndexFromUserIndex(userIndex, ufcsArg, prependUfcsArg);
                continue;
            }

            if (seenNamed)
                return false;

            while (nextPos < numParams && outMapping.paramArgs[nextPos].argRef.isValid())
                ++nextPos;

            if (nextPos >= numParams)
            {
                if (numParams == 0 || !params[numParams - 1].isVariadic)
                    return false;
                outMapping.variadicArgs.push_back({argRef, callArgIndexFromUserIndex(userIndex, ufcsArg, prependUfcsArg)});
                continue;
            }

            outMapping.paramArgs[nextPos].argRef       = argRef;
            outMapping.paramArgs[nextPos].callArgIndex = callArgIndexFromUserIndex(userIndex, ufcsArg, prependUfcsArg);
            ++nextPos;
        }

        return true;
    }
}

namespace SemaGeneric
{
    Result deduceGenericFunctionArgs(Sema& sema, const SymbolFunction& root, std::span<const GenericParamDesc> genericParams, SmallVector<GenericResolvedArg>& ioResolvedArgs, std::span<AstNodeRef> args, AstNodeRef ufcsArg, CastFailure* outFailure, uint32_t* outFailureArgIndex)
    {
        if (outFailure)
            *outFailure = {};
        if (outFailureArgIndex)
            *outFailureArgIndex = UINT32_MAX;

        const auto* decl = root.decl() ? root.decl()->safeCast<AstFunctionDecl>() : nullptr;
        if (!decl)
            return Result::Continue;

        std::unique_ptr<Sema> declSemaHolder;
        Sema&                 declSema = semaForFunctionDecl(sema, root, declSemaHolder);

        SmallVector<GenericFunctionParamDesc> params;
        collectFunctionParamDescs(declSema, root, *decl, params);

        GenericCallArgMapping mapping;
        const bool            prependUfcsArg = ufcsArg.isValid() && (!root.isMethod() || genericFunctionParamsExposeReceiver(sema, params.span()));
        if (!buildGenericCallArgMapping(sema, params.span(), args, ufcsArg, prependUfcsArg, mapping))
            return Result::Continue;

        for (uint32_t i = 0; i < mapping.paramArgs.size(); ++i)
        {
            const GenericCallArgEntry& entry = mapping.paramArgs[i];
            if (entry.argRef.isInvalid() || params[i].typeRef.isInvalid())
                continue;

            const AstNodeRef valueArgRef = Match::resolveCallArgumentValueRef(sema, entry.argRef);
            TypeRef          argTypeRef  = TypeRef::invalid();
            SWC_RESULT(resolveCallArgTypeForGenericDeduction(sema, argTypeRef, valueArgRef));
            if (!argTypeRef.isValid())
                return Result::Continue;

            AstNodeRef patternRef = params[i].typeRef;
            if (params[i].isVariadic)
            {
                const TypeInfo& argType = sema.typeMgr().get(argTypeRef);
                if (!argType.isTypedVariadic())
                    patternRef = typedVariadicElementTypeRef(declSema, params[i].typeRef);
                if (patternRef.isInvalid())
                    continue;
            }

            if (deduceFromTypePattern(declSema, genericParams, ioResolvedArgs.span(), patternRef, argTypeRef, valueArgRef, entry.callArgIndex, outFailure, DeductionMode::Normal) == Result::Error)
            {
                if (outFailureArgIndex)
                    *outFailureArgIndex = entry.callArgIndex;
                return Result::Continue;
            }
        }

        if (!params.empty() && params.back().isVariadic)
        {
            const AstNodeRef patternRef = typedVariadicElementTypeRef(declSema, params.back().typeRef);
            if (patternRef.isValid())
            {
                for (const GenericCallArgEntry& entry : mapping.variadicArgs)
                {
                    const AstNodeRef valueArgRef = Match::resolveCallArgumentValueRef(sema, entry.argRef);
                    TypeRef          argTypeRef  = TypeRef::invalid();
                    SWC_RESULT(resolveCallArgTypeForGenericDeduction(sema, argTypeRef, valueArgRef));
                    if (!argTypeRef.isValid())
                        return Result::Continue;

                    if (deduceFromTypePattern(declSema, genericParams, ioResolvedArgs.span(), patternRef, argTypeRef, valueArgRef, entry.callArgIndex, outFailure, DeductionMode::Normal) == Result::Error)
                    {
                        if (outFailureArgIndex)
                            *outFailureArgIndex = entry.callArgIndex;
                        return Result::Continue;
                    }
                }
            }
        }

        for (uint32_t i = 0; i < mapping.paramArgs.size(); ++i)
        {
            const GenericCallArgEntry& entry = mapping.paramArgs[i];
            if (entry.argRef.isValid() || params[i].typeRef.isInvalid() || params[i].defaultRef.isInvalid() || params[i].isVariadic || !params[i].hasExplicitType)
                continue;
            if (!patternCanDeduceMissingGenericParam(declSema, genericParams, ioResolvedArgs.span(), params[i].typeRef))
                continue;

            AstNodeRef defaultRef = AstNodeRef::invalid();
            SWC_RESULT(SemaGeneric::evalGenericFunctionParamDefault(declSema, root, genericParams, ioResolvedArgs.span(), params[i].defaultRef, defaultRef));
            if (defaultRef.isInvalid())
                continue;

            TypeRef defaultTypeRef = TypeRef::invalid();
            SWC_RESULT(resolveCallArgTypeForGenericDeduction(declSema, defaultTypeRef, defaultRef));
            if (!defaultTypeRef.isValid())
                continue;

            if (deduceFromTypePattern(declSema, genericParams, ioResolvedArgs.span(), params[i].typeRef, defaultTypeRef, defaultRef, UINT32_MAX, outFailure, DeductionMode::MissingOnly) == Result::Error)
                return Result::Continue;
        }

        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
