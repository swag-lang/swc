#include "pch.h"
#include "Compiler/Sema/Helpers/SemaGeneric.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class GenericParamKind : uint8_t
    {
        Type,
        Value,
    };

    struct GenericParamDesc
    {
        GenericParamKind kind         = GenericParamKind::Type;
        AstNodeRef       paramRef     = AstNodeRef::invalid();
        AstNodeRef       explicitType = AstNodeRef::invalid();
        AstNodeRef       defaultRef   = AstNodeRef::invalid();
        IdentifierRef    idRef        = IdentifierRef::invalid();
    };

    struct GenericResolvedArg
    {
        AstNodeRef  exprRef = AstNodeRef::invalid();
        TypeRef     typeRef = TypeRef::invalid();
        ConstantRef cstRef  = ConstantRef::invalid();
        bool        present = false;
    };

    struct GenericFunctionParamDesc
    {
        IdentifierRef idRef      = IdentifierRef::invalid();
        AstNodeRef    typeRef    = AstNodeRef::invalid();
        bool          isVariadic = false;
    };

    struct GenericCallArgEntry
    {
        AstNodeRef argRef = AstNodeRef::invalid();
    };

    template<typename RootSymbolT>
    SymbolFlags clonedGenericSymbolFlags(const RootSymbolT& root)
    {
        SymbolFlags flags = SymbolFlagsE::Zero;
        if (root.isPublic())
            flags.add(SymbolFlagsE::Public);
        return flags;
    }

    template<typename RootSymbolT>
    struct GenericRootTraits;

    template<>
    struct GenericRootTraits<SymbolFunction>
    {
        using DeclType       = AstFunctionDecl;
        using GenericArgKey  = SymbolFunction::GenericArgKey;
        using InstanceSymbol = SymbolFunction;

        static const DeclType* decl(const SymbolFunction& root)
        {
            return root.decl() ? root.decl()->safeCast<DeclType>() : nullptr;
        }

        static bool hasGenericParams(const SymbolFunction& root)
        {
            const auto* funcDecl = decl(root);
            return !root.isGenericInstance() && funcDecl && funcDecl->spanGenericParamsRef.isValid();
        }

        static Result runNode(Sema& sema, const SymbolFunction& root, AstNodeRef nodeRef)
        {
            Sema child(sema.ctx(), sema, nodeRef);
            child.prepareGenericInstantiationContext(const_cast<SymbolMap*>(root.ownerSymMap()), root.genericDeclImpl(), root.genericDeclInterface(), root.attributes());
            return child.execResult();
        }

        static InstanceSymbol* findInstance(const SymbolFunction& root, std::span<const GenericArgKey> keys)
        {
            return root.findGenericInstance(keys);
        }

        static void addInstance(SymbolFunction& root, std::span<const GenericArgKey> keys, InstanceSymbol* instance)
        {
            root.addGenericInstance(keys, instance);
        }

        static InstanceSymbol* createInstance(Sema& sema, SymbolFunction& root, AstNodeRef cloneRef)
        {
            auto& cloneDecl                = sema.node(cloneRef).cast<DeclType>();
            cloneDecl.spanGenericParamsRef = SpanRef::invalid();

            auto* instance         = Symbol::make<InstanceSymbol>(sema.ctx(), &cloneDecl, cloneDecl.tokNameRef, root.idRef(), clonedGenericSymbolFlags(root));
            instance->extraFlags() = root.extraFlags();
            instance->setAttributes(root.attributes());
            instance->setRtAttributeFlags(root.rtAttributeFlags());
            instance->setSpecOpKind(root.specOpKind());
            instance->setCallConvKind(root.callConvKind());
            instance->setDeclNodeRef(cloneRef);
            instance->setOwnerSymMap(root.ownerSymMap());
            instance->setGenericInstance(&root);
            return instance;
        }
    };

    template<>
    struct GenericRootTraits<SymbolStruct>
    {
        using DeclType       = AstStructDecl;
        using GenericArgKey  = SymbolStruct::GenericArgKey;
        using InstanceSymbol = SymbolStruct;

        static const DeclType* decl(const SymbolStruct& root)
        {
            return root.decl() ? root.decl()->safeCast<DeclType>() : nullptr;
        }

        static bool hasGenericParams(const SymbolStruct& root)
        {
            const auto* structDecl = decl(root);
            return !root.isGenericInstance() && structDecl && structDecl->spanGenericParamsRef.isValid();
        }

        static Result runNode(Sema& sema, const SymbolStruct& root, AstNodeRef nodeRef)
        {
            Sema child(sema.ctx(), sema, nodeRef);
            child.prepareGenericInstantiationContext(const_cast<SymbolMap*>(root.ownerSymMap()), nullptr, nullptr, root.attributes());
            return child.execResult();
        }

        static InstanceSymbol* findInstance(const SymbolStruct& root, std::span<const GenericArgKey> keys)
        {
            return root.findGenericInstance(keys);
        }

        static void addInstance(SymbolStruct& root, std::span<const GenericArgKey> keys, InstanceSymbol* instance)
        {
            root.addGenericInstance(keys, instance);
        }

        static InstanceSymbol* createInstance(Sema& sema, SymbolStruct& root, AstNodeRef cloneRef)
        {
            auto& cloneDecl                = sema.node(cloneRef).cast<DeclType>();
            cloneDecl.spanGenericParamsRef = SpanRef::invalid();
            cloneDecl.spanWhereRef         = SpanRef::invalid();

            auto* instance         = Symbol::make<InstanceSymbol>(sema.ctx(), &cloneDecl, cloneDecl.tokNameRef, root.idRef(), clonedGenericSymbolFlags(root));
            instance->extraFlags() = root.extraFlags();
            instance->setAttributes(root.attributes());
            instance->setOwnerSymMap(root.ownerSymMap());
            instance->setDeclNodeRef(cloneRef);
            instance->setGenericInstance(&root);
            return instance;
        }
    };

    TypeRef unwrapGenericDeductionType(TaskContext& ctx, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo  = ctx.typeMgr().get(typeRef);
            const TypeRef   unwrapped = typeInfo.unwrap(ctx, TypeRef::invalid(), TypeExpandE::Alias | TypeExpandE::Enum);
            if (!unwrapped.isValid() || unwrapped == typeRef)
                return typeRef;
            typeRef = unwrapped;
        }

        return typeRef;
    }

    void collectGenericParams(Sema& sema, SpanRef spanRef, std::vector<GenericParamDesc>& outParams)
    {
        outParams.clear();
        if (spanRef.isInvalid())
            return;

        SmallVector<AstNodeRef> params;
        sema.ast().appendNodes(params, spanRef);
        outParams.reserve(params.size());

        for (const AstNodeRef paramRef : params)
        {
            const AstNode& paramNode = sema.node(paramRef);

            GenericParamDesc desc;
            desc.paramRef = paramRef;
            desc.idRef    = SemaHelpers::resolveIdentifier(sema, paramNode.codeRef());

            if (const auto* nodeType = paramNode.safeCast<AstGenericParamType>())
            {
                desc.kind       = GenericParamKind::Type;
                desc.defaultRef = nodeType->nodeAssignRef;
            }
            else
            {
                const auto& nodeValue = paramNode.cast<AstGenericParamValue>();
                desc.kind             = GenericParamKind::Value;
                desc.explicitType     = nodeValue.nodeTypeRef;
                desc.defaultRef       = nodeValue.nodeAssignRef;
            }

            outParams.push_back(desc);
        }
    }

    void appendResolvedGenericBinding(const GenericParamDesc& param, const GenericResolvedArg& arg, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        if (!arg.present)
            return;

        SemaClone::ParamBinding binding;
        binding.idRef = param.idRef;
        if (param.kind == GenericParamKind::Type)
        {
            binding.exprRef = arg.exprRef;
            if (binding.exprRef.isInvalid())
                binding.typeRef = arg.typeRef;
        }
        else
        {
            binding.exprRef = arg.exprRef;
            binding.typeRef = arg.typeRef;
            binding.cstRef  = arg.cstRef;
        }

        outBindings.push_back(binding);
    }

    void collectResolvedGenericBindings(const std::vector<GenericParamDesc>& params, const std::vector<GenericResolvedArg>& resolvedArgs, size_t count, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        outBindings.clear();
        const size_t n = std::min(count, params.size());
        outBindings.reserve(n);
        for (size_t i = 0; i < n; ++i)
            appendResolvedGenericBinding(params[i], resolvedArgs[i], outBindings);
    }

    Result resolveGenericTypeArg(Sema& sema, AstNodeRef nodeRef, GenericResolvedArg& outArg)
    {
        outArg = {};

        const SemaNodeView view = sema.viewNodeTypeSymbol(nodeRef);
        if (view.sym() && view.sym()->isType())
        {
            TypeRef typeRef = view.typeRef();
            if (!typeRef.isValid())
                typeRef = view.sym()->typeRef();
            if (!typeRef.isValid())
                return SemaError::raise(sema, DiagnosticId::sema_err_not_type, nodeRef);

            outArg.exprRef = nodeRef;
            outArg.typeRef = typeRef;
            outArg.present = true;
            return Result::Continue;
        }

        if (view.typeRef().isValid() && !sema.isValue(nodeRef))
        {
            outArg.exprRef = nodeRef;
            outArg.typeRef = view.typeRef();
            outArg.present = true;
            return Result::Continue;
        }

        return SemaError::raise(sema, DiagnosticId::sema_err_not_type, nodeRef);
    }

    Result normalizeGenericConstantArg(Sema& sema, AstNodeRef nodeRef, GenericResolvedArg& outArg)
    {
        const SemaNodeView view = sema.viewNodeTypeConstant(nodeRef);
        if (!view.cstRef().isValid())
            return SemaError::raiseExprNotConst(sema, nodeRef);

        outArg         = {};
        outArg.exprRef = nodeRef;
        outArg.typeRef = view.typeRef();
        outArg.cstRef  = view.cstRef();
        outArg.present = true;

        if (outArg.typeRef.isValid())
        {
            const TypeInfo& typeInfo = sema.typeMgr().get(outArg.typeRef);
            if ((typeInfo.isIntUnsized() || typeInfo.isFloatUnsized()) && outArg.cstRef.isValid())
            {
                ConstantRef newCstRef = ConstantRef::invalid();
                SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, nodeRef, outArg.cstRef, TypeInfo::Sign::Unknown));
                if (newCstRef.isValid())
                {
                    sema.setConstant(nodeRef, newCstRef);
                    outArg.cstRef  = newCstRef;
                    outArg.typeRef = sema.cstMgr().get(newCstRef).typeRef();
                }
            }
        }

        return Result::Continue;
    }

    Result resolveExplicitGenericArg(Sema& sema, const GenericParamDesc& param, AstNodeRef nodeRef, GenericResolvedArg& outArg)
    {
        if (param.kind == GenericParamKind::Type)
            return resolveGenericTypeArg(sema, nodeRef, outArg);
        return normalizeGenericConstantArg(sema, nodeRef, outArg);
    }

    template<typename RootSymbolT>
    Result evalGenericClonedNode(Sema& sema, const RootSymbolT& root, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef& outClonedRef)
    {
        outClonedRef = AstNodeRef::invalid();
        if (sourceRef.isInvalid())
            return Result::Continue;

        const SemaClone::CloneContext cloneContext{bindings};
        outClonedRef = SemaClone::cloneAst(sema, sourceRef, cloneContext);
        if (outClonedRef.isInvalid())
            return Result::Error;

        return GenericRootTraits<RootSymbolT>::runNode(sema, root, outClonedRef);
    }

    template<typename RootSymbolT>
    Result evalGenericDefaultArg(Sema& sema, const RootSymbolT& root, const std::vector<GenericParamDesc>& params, const std::vector<GenericResolvedArg>& resolvedArgs, size_t paramIndex, GenericResolvedArg& outArg)
    {
        outArg                        = {};
        const GenericParamDesc& param = params[paramIndex];
        if (param.defaultRef.isInvalid())
            return Result::Continue;

        SmallVector<SemaClone::ParamBinding> bindings;
        collectResolvedGenericBindings(params, resolvedArgs, paramIndex, bindings);

        AstNodeRef clonedRef = AstNodeRef::invalid();
        SWC_RESULT(evalGenericClonedNode(sema, root, param.defaultRef, bindings, clonedRef));
        if (clonedRef.isInvalid())
            return Result::Error;

        return resolveExplicitGenericArg(sema, param, clonedRef, outArg);
    }

    template<typename RootSymbolT>
    Result resolveGenericValueParamType(Sema& sema, const RootSymbolT& root, const std::vector<GenericParamDesc>& params, const std::vector<GenericResolvedArg>& resolvedArgs, size_t paramIndex, TypeRef& outTypeRef)
    {
        outTypeRef                    = TypeRef::invalid();
        const GenericParamDesc& param = params[paramIndex];
        if (param.explicitType.isInvalid())
            return Result::Continue;

        SmallVector<SemaClone::ParamBinding> bindings;
        collectResolvedGenericBindings(params, resolvedArgs, paramIndex, bindings);

        AstNodeRef clonedTypeRef = AstNodeRef::invalid();
        SWC_RESULT(evalGenericClonedNode(sema, root, param.explicitType, bindings, clonedTypeRef));
        if (clonedTypeRef.isInvalid())
            return Result::Error;

        outTypeRef = sema.viewType(clonedTypeRef).typeRef();
        return Result::Continue;
    }

    template<typename RootSymbolT>
    Result finalizeResolvedGenericValue(Sema& sema, const RootSymbolT& root, const std::vector<GenericParamDesc>& params, std::vector<GenericResolvedArg>& resolvedArgs, size_t paramIndex, AstNodeRef errorNodeRef)
    {
        GenericResolvedArg& arg = resolvedArgs[paramIndex];
        if (!arg.present)
            return Result::Continue;

        TypeRef declaredTypeRef = TypeRef::invalid();
        SWC_RESULT(resolveGenericValueParamType(sema, root, params, resolvedArgs, paramIndex, declaredTypeRef));
        if (declaredTypeRef.isValid())
        {
            arg.typeRef = declaredTypeRef;
            if (arg.cstRef.isValid() && sema.cstMgr().get(arg.cstRef).typeRef() != declaredTypeRef)
            {
                CastRequest castRequest(CastKind::Implicit);
                castRequest.errorNodeRef = errorNodeRef;
                castRequest.srcConstRef  = arg.cstRef;

                const auto res = Cast::castAllowed(sema, castRequest, sema.cstMgr().get(arg.cstRef).typeRef(), declaredTypeRef);
                if (res != Result::Continue)
                {
                    if (res == Result::Error)
                        return Cast::emitCastFailure(sema, castRequest.failure);
                    return res;
                }

                arg.cstRef = castRequest.outConstRef;
            }
        }
        else if (arg.cstRef.isValid() && !arg.typeRef.isValid())
        {
            arg.typeRef = sema.cstMgr().get(arg.cstRef).typeRef();
        }

        return Result::Continue;
    }

    AstNodeRef genericErrorNodeRef(std::span<const AstNodeRef> genericArgNodes, size_t paramIndex, AstNodeRef fallbackNodeRef)
    {
        if (genericArgNodes.empty())
            return fallbackNodeRef;
        return genericArgNodes[std::min(paramIndex, genericArgNodes.size() - 1)];
    }

    template<typename RootSymbolT>
    Result materializeGenericArgs(Sema& sema, const RootSymbolT& root, const std::vector<GenericParamDesc>& params, std::vector<GenericResolvedArg>& ioResolvedArgs, std::span<const AstNodeRef> genericArgNodes, AstNodeRef fallbackNodeRef)
    {
        for (size_t i = 0; i < params.size(); ++i)
        {
            if (ioResolvedArgs[i].present)
                continue;

            GenericResolvedArg defaultArg;
            SWC_RESULT(evalGenericDefaultArg(sema, root, params, ioResolvedArgs, i, defaultArg));
            if (!defaultArg.present)
                return Result::Continue;
            ioResolvedArgs[i] = defaultArg;
        }

        for (size_t i = 0; i < params.size(); ++i)
        {
            if (!ioResolvedArgs[i].present)
                return Result::Continue;
            if (params[i].kind == GenericParamKind::Value)
                SWC_RESULT(finalizeResolvedGenericValue(sema, root, params, ioResolvedArgs, i, genericErrorNodeRef(genericArgNodes, i, fallbackNodeRef)));
        }

        return Result::Continue;
    }

    bool hasMissingGenericArgs(const std::vector<GenericResolvedArg>& resolvedArgs)
    {
        for (const auto& arg : resolvedArgs)
        {
            if (!arg.present)
                return true;
        }

        return false;
    }

    bool tryBindGenericTypeParam(std::span<const GenericParamDesc> params, std::span<GenericResolvedArg> resolvedArgs, IdentifierRef idRef, AstNodeRef exprRef, TypeRef typeRef)
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

    bool tryBindGenericValueParam(std::span<const GenericParamDesc> params, std::span<GenericResolvedArg> resolvedArgs, IdentifierRef idRef, ConstantRef cstRef, TypeRef typeRef)
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

    Result deduceFromTypePattern(Sema& sema, std::span<const GenericParamDesc> params, std::span<GenericResolvedArg> resolvedArgs, AstNodeRef patternRef, TypeRef rawArgTypeRef)
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

    void collectFunctionParamDescs(Sema& sema, const AstFunctionDecl& decl, std::vector<GenericFunctionParamDesc>& outParams)
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

    bool buildGenericCallArgMapping(Sema& sema, const std::vector<GenericFunctionParamDesc>& params, std::span<AstNodeRef> args, AstNodeRef ufcsArg, bool prependUfcsArg, SmallVector<GenericCallArgEntry>& outMapping)
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

    template<typename KeyT>
    void buildGenericKeys(const std::vector<GenericParamDesc>& params, const std::vector<GenericResolvedArg>& resolvedArgs, std::vector<KeyT>& outKeys)
    {
        outKeys.clear();
        outKeys.reserve(params.size());
        for (size_t i = 0; i < params.size(); ++i)
        {
            KeyT key;
            if (params[i].kind == GenericParamKind::Type)
                key.typeRef = resolvedArgs[i].typeRef;
            else
                key.cstRef = resolvedArgs[i].cstRef;
            outKeys.push_back(key);
        }
    }

    void buildGenericCloneBindings(const std::vector<GenericParamDesc>& params, const std::vector<GenericResolvedArg>& resolvedArgs, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        outBindings.clear();
        outBindings.reserve(params.size());
        for (size_t i = 0; i < params.size(); ++i)
            appendResolvedGenericBinding(params[i], resolvedArgs[i], outBindings);
    }

    template<typename RootSymbolT>
    Result createGenericInstance(Sema& sema, RootSymbolT& root, const std::vector<GenericParamDesc>& params, const std::vector<GenericResolvedArg>& resolvedArgs, RootSymbolT*& outInstance)
    {
        using Traits = GenericRootTraits<RootSymbolT>;
        using KeyT   = Traits::GenericArgKey;

        outInstance = nullptr;

        std::vector<KeyT> keys;
        buildGenericKeys(params, resolvedArgs, keys);

        outInstance = Traits::findInstance(root, keys);
        if (!outInstance)
        {
            SmallVector<SemaClone::ParamBinding> bindings;
            buildGenericCloneBindings(params, resolvedArgs, bindings);

            const SemaClone::CloneContext cloneContext{bindings};
            const AstNodeRef              cloneRef = SemaClone::cloneAst(sema, root.declNodeRef(), cloneContext);
            if (cloneRef.isInvalid())
                return Result::Error;

            outInstance = Traits::createInstance(sema, root, cloneRef);
            sema.setSymbol(cloneRef, outInstance);
            Traits::addInstance(root, keys, outInstance);
        }

        if (!outInstance->isSemaCompleted())
            SWC_RESULT(Traits::runNode(sema, root, outInstance->declNodeRef()));

        return Result::Continue;
    }

    template<typename RootSymbolT>
    Result instantiateGenericExplicit(Sema& sema, RootSymbolT& genericRoot, std::span<const AstNodeRef> genericArgNodes, RootSymbolT*& outInstance)
    {
        using Traits = GenericRootTraits<RootSymbolT>;

        outInstance = nullptr;
        if (!Traits::hasGenericParams(genericRoot))
            return Result::Continue;

        const auto* decl = Traits::decl(genericRoot);
        if (!decl)
            return Result::Continue;

        std::vector<GenericParamDesc> params;
        collectGenericParams(sema, decl->spanGenericParamsRef, params);
        if (genericArgNodes.size() > params.size())
            return Result::Continue;

        std::vector<GenericResolvedArg> resolvedArgs(params.size());
        for (size_t i = 0; i < genericArgNodes.size(); ++i)
            SWC_RESULT(resolveExplicitGenericArg(sema, params[i], genericArgNodes[i], resolvedArgs[i]));

        SWC_RESULT(materializeGenericArgs(sema, genericRoot, params, resolvedArgs, genericArgNodes, sema.curNodeRef()));
        if (hasMissingGenericArgs(resolvedArgs))
            return Result::Continue;

        return createGenericInstance(sema, genericRoot, params, resolvedArgs, outInstance);
    }
}

Result SemaGeneric::instantiateFunctionExplicit(Sema& sema, SymbolFunction& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolFunction*& outInstance)
{
    return instantiateGenericExplicit(sema, genericRoot, genericArgNodes, outInstance);
}

Result SemaGeneric::instantiateFunctionFromCall(Sema& sema, SymbolFunction& genericRoot, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SymbolFunction*& outInstance)
{
    outInstance = nullptr;
    if (!GenericRootTraits<SymbolFunction>::hasGenericParams(genericRoot))
        return Result::Continue;

    const auto* decl = GenericRootTraits<SymbolFunction>::decl(genericRoot);
    if (!decl)
        return Result::Continue;

    std::vector<GenericParamDesc> params;
    collectGenericParams(sema, decl->spanGenericParamsRef, params);
    if (params.empty())
        return Result::Continue;

    std::vector<GenericResolvedArg> resolvedArgs(params.size());
    SWC_RESULT(deduceGenericFunctionArgs(sema, genericRoot, params, resolvedArgs, args, ufcsArg));

    SWC_RESULT(materializeGenericArgs(sema, genericRoot, params, resolvedArgs, {}, sema.curNodeRef()));
    if (hasMissingGenericArgs(resolvedArgs))
        return Result::Continue;

    return createGenericInstance(sema, genericRoot, params, resolvedArgs, outInstance);
}

Result SemaGeneric::instantiateStructExplicit(Sema& sema, SymbolStruct& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolStruct*& outInstance)
{
    return instantiateGenericExplicit(sema, genericRoot, genericArgNodes, outInstance);
}

SWC_END_NAMESPACE();
