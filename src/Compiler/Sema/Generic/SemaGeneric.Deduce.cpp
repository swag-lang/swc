#include "pch.h"
#include "Compiler/Sema/Generic/SemaGeneric.Internals.h"

SWC_BEGIN_NAMESPACE();

namespace SemaGenericInternal
{
    static bool tryBindGenericTypeParam(std::span<const GenericParamDesc> params, std::span<GenericResolvedArg> resolvedArgs, IdentifierRef idRef, AstNodeRef exprRef, TypeRef typeRef)
    {
        for (size_t i = 0; i < params.size(); ++i)
        {
            if (params[i].kind != GenericParamKind::Type || params[i].idRef != idRef)
                continue;

            GenericResolvedArg& arg = resolvedArgs[i];
            if (!arg.present)
            {
                arg.present = true;
                arg.exprRef = exprRef;
                arg.typeRef = typeRef;
                return true;
            }

            return arg.typeRef == typeRef;
        }

        return true;
    }

    static bool tryBindGenericValueParam(std::span<const GenericParamDesc> params, std::span<GenericResolvedArg> resolvedArgs, IdentifierRef idRef, ConstantRef cstRef, TypeRef typeRef)
    {
        for (size_t i = 0; i < params.size(); ++i)
        {
            if (params[i].kind != GenericParamKind::Value || params[i].idRef != idRef)
                continue;

            GenericResolvedArg& arg = resolvedArgs[i];
            if (!arg.present)
            {
                arg.present = true;
                arg.typeRef = typeRef;
                arg.cstRef  = cstRef;
                return true;
            }

            return arg.cstRef == cstRef;
        }

        return true;
    }

    static Result deduceFromTypePattern(Sema& sema, std::span<const GenericParamDesc> params, std::span<GenericResolvedArg> resolvedArgs, AstNodeRef patternRef, TypeRef rawArgTypeRef)
    {
        if (patternRef.isInvalid() || !rawArgTypeRef.isValid())
            return Result::Continue;

        const AstNode& patternNode = sema.node(patternRef);
        if (const auto* namedType = patternNode.safeCast<AstNamedType>())
        {
            const AstNode& identNode = sema.node(namedType->nodeIdentRef);
            if (const auto* ident = identNode.safeCast<AstIdentifier>())
            {
                const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
                if (!tryBindGenericTypeParam(params, resolvedArgs, idRef, AstNodeRef::invalid(), rawArgTypeRef))
                    return Result::Error;
            }

            return Result::Continue;
        }

        const TypeRef      argTypeRef = unwrapGenericDeductionType(sema.ctx(), rawArgTypeRef);
        const TypeInfo&    argType    = sema.typeMgr().get(argTypeRef);
        const TaskContext& ctx        = sema.ctx();

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
                    if (!tryBindGenericValueParam(params, resolvedArgs, idRef, cstRef, sema.cstMgr().get(cstRef).typeRef()))
                        return Result::Error;
                }
            }

            return deduceFromTypePattern(sema, params, resolvedArgs, arrayType->nodePointeeTypeRef, argType.payloadArrayElemTypeRef());
        }

        if (const auto* sliceType = patternNode.safeCast<AstSliceType>())
        {
            if (!argType.isSlice())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, sliceType->nodePointeeTypeRef, argType.payloadTypeRef());
        }

        if (const auto* refType = patternNode.safeCast<AstReferenceType>())
        {
            if (!argType.isReference())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, refType->nodePointeeTypeRef, argType.payloadTypeRef());
        }

        if (const auto* moveRefType = patternNode.safeCast<AstMoveRefType>())
        {
            if (!argType.isMoveReference())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, moveRefType->nodePointeeTypeRef, argType.payloadTypeRef());
        }

        if (const auto* valuePtrType = patternNode.safeCast<AstValuePointerType>())
        {
            if (!argType.isValuePointer())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, valuePtrType->nodePointeeTypeRef, argType.payloadTypeRef());
        }

        if (const auto* blockPtrType = patternNode.safeCast<AstBlockPointerType>())
        {
            if (!argType.isBlockPointer())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, blockPtrType->nodePointeeTypeRef, argType.payloadTypeRef());
        }

        if (const auto* qualifiedType = patternNode.safeCast<AstQualifiedType>())
            return deduceFromTypePattern(sema, params, resolvedArgs, qualifiedType->nodeTypeRef, rawArgTypeRef);

        if (const auto* variadicType = patternNode.safeCast<AstTypedVariadicType>())
        {
            if (!argType.isTypedVariadic())
                return Result::Continue;
            return deduceFromTypePattern(sema, params, resolvedArgs, variadicType->nodeTypeRef, argType.payloadTypeRef());
        }

        return Result::Continue;
    }

    static void collectFunctionParamDescs(Sema& sema, const AstFunctionDecl& decl, std::vector<GenericFunctionParamDesc>& outParams)
    {
        outParams.clear();
        if (decl.nodeParamsRef.isInvalid())
            return;

        SmallVector<AstNodeRef> params;
        sema.node(decl.nodeParamsRef).collectChildrenFromAst(params, sema.ast());
        outParams.reserve(params.size());

        for (AstNodeRef paramRef : params)
        {
            const AstNode* paramNode = &sema.node(paramRef);
            while (paramNode->is(AstNodeId::AttributeList))
            {
                paramRef  = paramNode->cast<AstAttributeList>().nodeBodyRef;
                paramNode = &sema.node(paramRef);
            }

            if (paramNode->is(AstNodeId::SingleVarDecl))
            {
                const auto&              varDecl = paramNode->cast<AstSingleVarDecl>();
                GenericFunctionParamDesc desc;
                desc.idRef      = SemaHelpers::resolveIdentifier(sema, {varDecl.srcViewRef(), varDecl.tokNameRef});
                desc.typeRef    = varDecl.typeOrInitRef();
                desc.isVariadic = desc.typeRef.isValid() &&
                                  (sema.node(desc.typeRef).is(AstNodeId::VariadicType) || sema.node(desc.typeRef).is(AstNodeId::TypedVariadicType));
                outParams.push_back(desc);
            }
            else if (paramNode->is(AstNodeId::FunctionParamMe))
            {
                GenericFunctionParamDesc desc;
                desc.idRef      = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
                desc.isVariadic = false;
                outParams.push_back(desc);
            }
        }
    }

    static bool buildGenericCallArgMapping(Sema& sema, const std::vector<GenericFunctionParamDesc>& params, std::span<AstNodeRef> args, AstNodeRef ufcsArg, bool prependUfcsArg, SmallVector<GenericCallArgEntry>& outMapping)
    {
        outMapping.clear();

        const uint32_t numParams  = static_cast<uint32_t>(params.size());
        const uint32_t paramStart = prependUfcsArg && ufcsArg.isValid() ? 1u : 0u;
        outMapping.resize(numParams);

        if (prependUfcsArg && ufcsArg.isValid() && numParams > 0)
            outMapping[0].argRef = ufcsArg;

        bool     seenNamed = false;
        uint32_t nextPos   = paramStart;

        for (const auto argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);

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

                outMapping[found].argRef = argRef;
                continue;
            }

            if (seenNamed)
                return false;

            while (nextPos < numParams && outMapping[nextPos].argRef.isValid())
                ++nextPos;

            if (nextPos >= numParams)
                return false;

            outMapping[nextPos].argRef = argRef;
            ++nextPos;
        }

        return true;
    }

    Result deduceGenericFunctionArgs(Sema& sema, const SymbolFunction& root, const std::vector<GenericParamDesc>& genericParams, std::vector<GenericResolvedArg>& ioResolvedArgs, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        const auto* decl = GenericRootTraits<SymbolFunction>::decl(root);
        if (!decl)
            return Result::Continue;

        std::vector<GenericFunctionParamDesc> params;
        collectFunctionParamDescs(sema, *decl, params);

        SmallVector<GenericCallArgEntry> mapping;
        const bool                       prependUfcsArg = ufcsArg.isValid() && !root.isMethod();
        if (!buildGenericCallArgMapping(sema, params, args, ufcsArg, prependUfcsArg, mapping))
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

            if (deduceFromTypePattern(sema, genericParams, ioResolvedArgs, params[i].typeRef, argTypeRef) == Result::Error)
                return Result::Continue;
        }

        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
