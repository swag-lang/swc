#include "pch.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Cast/CastFailure.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result deduceFromTypePattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef patternRef, TypeRef rawArgTypeRef, CastFailure* outFailure);

    void setGenericTypeDeductionFailure(Sema& sema, CastFailure& outFailure, IdentifierRef idRef, TypeRef previousTypeRef, TypeRef newTypeRef)
    {
        outFailure            = {};
        outFailure.diagId     = DiagnosticId::sema_err_generic_type_deduction_conflict;
        outFailure.srcTypeRef = previousTypeRef;
        outFailure.dstTypeRef = newTypeRef;
        outFailure.addArgument(Diagnostic::ARG_VALUE, Utf8{sema.idMgr().get(idRef).name});
    }

    void setGenericValueDeductionFailure(Sema& sema, CastFailure& outFailure, IdentifierRef idRef, ConstantRef previousCstRef, ConstantRef newCstRef)
    {
        outFailure        = {};
        outFailure.diagId = DiagnosticId::sema_err_generic_value_deduction_conflict;
        outFailure.addArgument(Diagnostic::ARG_VALUE, Utf8{sema.idMgr().get(idRef).name});
        outFailure.addArgument(Diagnostic::ARG_LEFT, sema.cstMgr().get(previousCstRef).toString(sema.ctx()));
        outFailure.addArgument(Diagnostic::ARG_RIGHT, sema.cstMgr().get(newCstRef).toString(sema.ctx()));
    }

    uint32_t callArgIndexFromUserIndex(uint32_t userArgIndex, AstNodeRef ufcsArg, bool prependUfcsArg)
    {
        return prependUfcsArg && ufcsArg.isValid() ? (userArgIndex + 1) : userArgIndex;
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
            desc.idRef      = SemaHelpers::resolveIdentifier(sema, {varDecl.srcViewRef(), varDecl.tokNameRef});
            desc.typeRef    = varDecl.typeOrInitRef();
            desc.isVariadic = desc.typeRef.isValid() &&
                              (sema.node(desc.typeRef).is(AstNodeId::VariadicType) || sema.node(desc.typeRef).is(AstNodeId::TypedVariadicType));
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
                desc.idRef      = SemaHelpers::resolveIdentifier(sema, {multiVar.srcViewRef(), tokNameRef});
                desc.typeRef    = multiVar.typeOrInitRef();
                desc.isVariadic = desc.typeRef.isValid() &&
                                  (sema.node(desc.typeRef).is(AstNodeId::VariadicType) || sema.node(desc.typeRef).is(AstNodeId::TypedVariadicType));
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

    bool tryBindGenericTypeParam(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, IdentifierRef idRef, AstNodeRef exprRef, TypeRef typeRef, CastFailure* outFailure)
    {
        for (size_t i = 0; i < params.size(); ++i)
        {
            if (params[i].kind != SemaGeneric::GenericParamKind::Type || params[i].idRef != idRef)
                continue;

            SemaGeneric::GenericResolvedArg& arg = resolvedArgs[i];
            if (!arg.present)
            {
                arg.present = true;
                arg.exprRef = exprRef;
                arg.typeRef = typeRef;
                return true;
            }

            if (arg.typeRef == typeRef)
                return true;

            if (outFailure)
                setGenericTypeDeductionFailure(sema, *outFailure, idRef, arg.typeRef, typeRef);
            return false;
        }

        return true;
    }

    bool tryBindGenericValueParam(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, IdentifierRef idRef, ConstantRef cstRef, TypeRef typeRef, CastFailure* outFailure)
    {
        for (size_t i = 0; i < params.size(); ++i)
        {
            if (params[i].kind != SemaGeneric::GenericParamKind::Value || params[i].idRef != idRef)
                continue;

            SemaGeneric::GenericResolvedArg& arg = resolvedArgs[i];
            if (!arg.present)
            {
                arg.present = true;
                arg.typeRef = typeRef;
                arg.cstRef  = cstRef;
                return true;
            }

            if (arg.cstRef == cstRef)
                return true;

            if (outFailure)
                setGenericValueDeductionFailure(sema, *outFailure, idRef, arg.cstRef, cstRef);
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

        return outGenericRoot != nullptr || outGenericRootIdRef.isValid();
    }

    Result deduceFromValuePattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef patternRef, ConstantRef cstRef, TypeRef typeRef, CastFailure* outFailure)
    {
        if (patternRef.isInvalid() || !cstRef.isValid())
            return Result::Continue;

        const AstNode& patternNode = sema.node(patternRef);
        if (const auto* ident = patternNode.safeCast<AstIdentifier>())
        {
            const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
            if (!tryBindGenericValueParam(sema, params, resolvedArgs, idRef, cstRef, typeRef, outFailure))
                return Result::Error;
            return Result::Continue;
        }

        const SemaNodeView patternView = sema.viewNodeTypeConstant(patternRef);
        if (patternView.cstRef().isValid())
            return patternView.cstRef() == cstRef ? Result::Continue : Result::Error;

        return Result::Continue;
    }

    Result deduceFromStructPattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, const AstNamedType& namedType, const TypeInfo& argType, CastFailure* outFailure)
    {
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
                result = deduceFromTypePattern(sema, params, trialResolvedArgs.span(), patternArgs[i], actualArgs[i].typeRef, outFailure ? &trialFailure : nullptr);
            else if (actualArgs[i].cstRef.isValid())
                result = deduceFromValuePattern(sema, params, trialResolvedArgs.span(), patternArgs[i], actualArgs[i].cstRef, actualArgs[i].typeRef, outFailure ? &trialFailure : nullptr);

            if (result == Result::Error)
                return Result::Continue;
        }

        std::ranges::copy(trialResolvedArgs, resolvedArgs.begin());
        return Result::Continue;
    }

    Result deduceFromTypePattern(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef patternRef, TypeRef rawArgTypeRef, CastFailure* outFailure)
    {
        if (patternRef.isInvalid() || !rawArgTypeRef.isValid())
            return Result::Continue;

        const AstNode& patternNode = sema.node(patternRef);
        if (const auto* ident = patternNode.safeCast<AstIdentifier>())
        {
            const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
            if (!tryBindGenericTypeParam(sema, params, resolvedArgs, idRef, AstNodeRef::invalid(), rawArgTypeRef, outFailure))
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
                if (!tryBindGenericTypeParam(sema, params, resolvedArgs, idRef, AstNodeRef::invalid(), rawArgTypeRef, outFailure))
                    return Result::Error;

                return Result::Continue;
            }
        }

        const TypeRef      argTypeRef = SemaGeneric::unwrapGenericDeductionType(sema.ctx(), rawArgTypeRef);
        const TypeInfo&    argType    = sema.typeMgr().get(argTypeRef);
        const TaskContext& ctx        = sema.ctx();

        if (namedType)
            return deduceFromStructPattern(sema, params, resolvedArgs, *namedType, argType, outFailure);

        if (const auto* arrayType = patternNode.safeCast<AstArrayType>())
        {
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
                    if (!tryBindGenericValueParam(sema, params, resolvedArgs, idRef, cstRef, sema.cstMgr().get(cstRef).typeRef(), outFailure))
                        return Result::Error;
                }
            }

            return deduceFromTypePattern(sema, params, resolvedArgs, arrayType->nodePointeeTypeRef, argType.payloadArrayElemTypeRef(), outFailure);
        }

        if (const auto* sliceType = patternNode.safeCast<AstSliceType>())
        {
            if (!argType.isSlice())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, sliceType->nodePointeeTypeRef, argType.payloadTypeRef(), outFailure);
        }

        if (const auto* refType = patternNode.safeCast<AstReferenceType>())
        {
            if (!argType.isReference())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, refType->nodePointeeTypeRef, argType.payloadTypeRef(), outFailure);
        }

        if (const auto* moveRefType = patternNode.safeCast<AstMoveRefType>())
        {
            if (!argType.isMoveReference())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, moveRefType->nodePointeeTypeRef, argType.payloadTypeRef(), outFailure);
        }

        if (const auto* valuePtrType = patternNode.safeCast<AstValuePointerType>())
        {
            if (!argType.isValuePointer())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, valuePtrType->nodePointeeTypeRef, argType.payloadTypeRef(), outFailure);
        }

        if (const auto* blockPtrType = patternNode.safeCast<AstBlockPointerType>())
        {
            if (!argType.isBlockPointer())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, blockPtrType->nodePointeeTypeRef, argType.payloadTypeRef(), outFailure);
        }

        if (const auto* qualifiedType = patternNode.safeCast<AstQualifiedType>())
            return deduceFromTypePattern(sema, params, resolvedArgs, qualifiedType->nodeTypeRef, rawArgTypeRef, outFailure);

        if (const auto* variadicType = patternNode.safeCast<AstTypedVariadicType>())
        {
            if (!argType.isTypedVariadic())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, variadicType->nodeTypeRef, argType.payloadTypeRef(), outFailure);
        }

        return Result::Continue;
    }

    void collectFunctionParamDescs(Sema& sema, const SymbolFunction& root, const AstFunctionDecl& decl, SmallVector<SemaGeneric::GenericFunctionParamDesc>& outParams)
    {
        outParams.clear();
        const auto& symbolParams = root.parameters();
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
                    desc.idRef      = symParam->idRef();
                    desc.typeRef    = varDecl.typeOrInitRef();
                    desc.isVariadic = desc.typeRef.isValid() &&
                                      (sema.node(desc.typeRef).is(AstNodeId::VariadicType) || sema.node(desc.typeRef).is(AstNodeId::TypedVariadicType));
                    outParams.push_back(desc);
                }
                else if (paramNode->is(AstNodeId::FunctionParamMe))
                {
                    SemaGeneric::GenericFunctionParamDesc desc;
                    desc.idRef      = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
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
        appendFunctionParamNodes(sema, decl.nodeParamsRef, params);
        outParams.reserve(params.size());

        for (const AstNodeRef paramRef : params)
            appendFunctionParamDesc(sema, paramRef, outParams);
    }

    bool buildGenericCallArgMapping(Sema& sema, std::span<const SemaGeneric::GenericFunctionParamDesc> params, std::span<AstNodeRef> args, AstNodeRef ufcsArg, bool prependUfcsArg, SmallVector<SemaGeneric::GenericCallArgEntry>& outMapping)
    {
        outMapping.clear();

        const uint32_t numParams  = static_cast<uint32_t>(params.size());
        const uint32_t paramStart = prependUfcsArg && ufcsArg.isValid() ? 1u : 0u;
        outMapping.resize(numParams);

        if (prependUfcsArg && ufcsArg.isValid() && numParams > 0)
        {
            outMapping[0].argRef       = ufcsArg;
            outMapping[0].callArgIndex = 0;
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

                if (found < 0 || outMapping[found].argRef.isValid())
                    return false;

                outMapping[found].argRef       = argRef;
                outMapping[found].callArgIndex = callArgIndexFromUserIndex(userIndex, ufcsArg, prependUfcsArg);
                continue;
            }

            if (seenNamed)
                return false;

            while (nextPos < numParams && outMapping[nextPos].argRef.isValid())
                ++nextPos;

            if (nextPos >= numParams)
                return false;

            outMapping[nextPos].argRef       = argRef;
            outMapping[nextPos].callArgIndex = callArgIndexFromUserIndex(userIndex, ufcsArg, prependUfcsArg);
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

        SmallVector<GenericFunctionParamDesc> params;
        collectFunctionParamDescs(sema, root, *decl, params);

        SmallVector<GenericCallArgEntry> mapping;
        const bool                       prependUfcsArg = ufcsArg.isValid() && !root.isMethod();
        if (!buildGenericCallArgMapping(sema, params.span(), args, ufcsArg, prependUfcsArg, mapping))
            return Result::Continue;

        for (uint32_t i = 0; i < mapping.size(); ++i)
        {
            const GenericCallArgEntry& entry = mapping[i];
            if (entry.argRef.isInvalid() || params[i].typeRef.isInvalid() || params[i].isVariadic)
                continue;

            const AstNodeRef valueArgRef = Match::resolveCallArgumentValueRef(sema, entry.argRef);
            TypeRef          argTypeRef  = sema.viewTypeConstant(valueArgRef).typeRef();
            if (!argTypeRef.isValid())
                return Result::Continue;

            const SemaNodeView argView = sema.viewNodeTypeConstant(valueArgRef);
            if (argView.cstRef().isValid())
            {
                const TypeInfo& argType = sema.typeMgr().get(argTypeRef);
                if (argType.isIntUnsized() || argType.isFloatUnsized())
                {
                    ConstantRef newCstRef = ConstantRef::invalid();
                    SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, valueArgRef, argView.cstRef(), TypeInfo::Sign::Unknown));
                    if (newCstRef.isValid())
                    {
                        sema.setConstant(valueArgRef, newCstRef);
                        argTypeRef = sema.cstMgr().get(newCstRef).typeRef();
                    }
                }
            }

            if (deduceFromTypePattern(sema, genericParams, ioResolvedArgs.span(), params[i].typeRef, argTypeRef, outFailure) == Result::Error)
            {
                if (outFailureArgIndex)
                    *outFailureArgIndex = entry.callArgIndex;
                return Result::Continue;
            }
        }

        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
