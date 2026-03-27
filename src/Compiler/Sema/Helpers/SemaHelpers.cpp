#include "pch.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Helpers/SemaSymbolLookup.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbol.impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
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
        AstNodeRef    declRef    = AstNodeRef::invalid();
        AstNodeRef    typeRef    = AstNodeRef::invalid();
        bool          hasDefault = false;
        bool          isVariadic = false;
    };

    struct GenericCallArgEntry
    {
        AstNodeRef argRef       = AstNodeRef::invalid();
        uint32_t   callArgIndex = 0;
    };

    struct GenericCallArgMapping
    {
        SmallVector<GenericCallArgEntry> paramArgs;
        bool                             hasNamed = false;
    };

    using FunctionGenericArgKey = SymbolFunction::GenericArgKey;
    using StructGenericArgKey   = SymbolStruct::GenericArgKey;

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

    template<typename T>
    SymbolFlags clonedGenericSymbolFlags(const T& root)
    {
        SymbolFlags flags = SymbolFlagsE::Zero;
        if (root.isPublic())
            flags.add(SymbolFlagsE::Public);
        return flags;
    }

    bool hasGenericParams(const SymbolFunction& sym)
    {
        if (sym.isGenericInstance())
            return false;

        const auto* decl = sym.decl() ? sym.decl()->safeCast<AstFunctionDecl>() : nullptr;
        return decl && decl->spanGenericParamsRef.isValid();
    }

    bool hasGenericParams(const SymbolStruct& sym)
    {
        if (sym.isGenericInstance())
            return false;

        const auto* decl = sym.decl() ? sym.decl()->safeCast<AstStructDecl>() : nullptr;
        return decl && decl->spanGenericParamsRef.isValid();
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

    Result runGenericFunctionNode(Sema& sema, const SymbolFunction& root, AstNodeRef nodeRef)
    {
        Sema child(sema.ctx(), sema, nodeRef);
        child.prepareGenericInstantiationContext(const_cast<SymbolMap*>(root.ownerSymMap()), root.genericDeclImpl(), root.genericDeclInterface(), root.attributes());
        return child.execResult();
    }

    Result runGenericStructNode(Sema& sema, const SymbolStruct& root, AstNodeRef nodeRef)
    {
        Sema child(sema.ctx(), sema, nodeRef);
        child.prepareGenericInstantiationContext(const_cast<SymbolMap*>(root.ownerSymMap()), nullptr, nullptr, root.attributes());
        return child.execResult();
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

        outArg = {};
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

        if constexpr (std::is_same_v<RootSymbolT, SymbolFunction>)
            return runGenericFunctionNode(sema, root, outClonedRef);
        else
            return runGenericStructNode(sema, root, outClonedRef);
    }

    template<typename RootSymbolT>
    Result evalGenericDefaultArg(Sema& sema, const RootSymbolT& root, const std::vector<GenericParamDesc>& params, const std::vector<GenericResolvedArg>& resolvedArgs, size_t paramIndex, GenericResolvedArg& outArg)
    {
        outArg = {};
        const GenericParamDesc& param = params[paramIndex];
        if (param.defaultRef.isInvalid())
            return Result::Continue;

        SmallVector<SemaClone::ParamBinding> bindings;
        collectResolvedGenericBindings(params, resolvedArgs, paramIndex, bindings);

        AstNodeRef clonedRef = AstNodeRef::invalid();
        SWC_RESULT(evalGenericClonedNode(sema, root, param.defaultRef, bindings, clonedRef));
        if (clonedRef.isInvalid())
            return Result::Error;

        if (param.kind == GenericParamKind::Type)
            return resolveGenericTypeArg(sema, clonedRef, outArg);
        return normalizeGenericConstantArg(sema, clonedRef, outArg);
    }

    template<typename RootSymbolT>
    Result resolveGenericValueParamType(Sema& sema, const RootSymbolT& root, const std::vector<GenericParamDesc>& params, const std::vector<GenericResolvedArg>& resolvedArgs, size_t paramIndex, TypeRef& outTypeRef)
    {
        outTypeRef = TypeRef::invalid();
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

                ConstantRef castedRef = castRequest.outConstRef;
                arg.cstRef = castedRef;
            }
        }
        else if (arg.cstRef.isValid() && !arg.typeRef.isValid())
        {
            arg.typeRef = sema.cstMgr().get(arg.cstRef).typeRef();
        }

        return Result::Continue;
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
                    ConstantRef         cstRef = sema.cstMgr().addInt(ctx, argDims[i]);
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

            GenericFunctionParamDesc desc;
            desc.declRef = paramRef;

            if (paramNode->is(AstNodeId::SingleVarDecl))
            {
                const auto& varDecl = paramNode->cast<AstSingleVarDecl>();
                desc.idRef          = SemaHelpers::resolveIdentifier(sema, {varDecl.srcViewRef(), varDecl.tokNameRef});
                desc.typeRef        = varDecl.typeOrInitRef();
                desc.hasDefault     = varDecl.nodeInitRef.isValid();
                desc.isVariadic     = desc.typeRef.isValid() &&
                                  (sema.node(desc.typeRef).is(AstNodeId::VariadicType) || sema.node(desc.typeRef).is(AstNodeId::TypedVariadicType));
                outParams.push_back(desc);
            }
            else if (paramNode->is(AstNodeId::FunctionParamMe))
            {
                desc.idRef      = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
                desc.hasDefault = false;
                desc.isVariadic = false;
                outParams.push_back(desc);
            }
        }
    }

    bool buildGenericCallArgMapping(Sema& sema, const std::vector<GenericFunctionParamDesc>& params, std::span<AstNodeRef> args, AstNodeRef ufcsArg, bool prependUfcsArg, GenericCallArgMapping& outMapping)
    {
        outMapping = {};

        const uint32_t numParams  = static_cast<uint32_t>(params.size());
        const uint32_t paramStart = prependUfcsArg && ufcsArg.isValid() ? 1u : 0u;
        outMapping.paramArgs.resize(numParams);
        for (auto& entry : outMapping.paramArgs)
            entry.callArgIndex = 0;

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
                seenNamed           = true;
                outMapping.hasNamed = true;

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
                outMapping.paramArgs[found].callArgIndex = prependUfcsArg && ufcsArg.isValid() ? userIndex + 1 : userIndex;
                continue;
            }

            if (seenNamed)
                return false;

            while (nextPos < numParams && outMapping.paramArgs[nextPos].argRef.isValid())
                ++nextPos;

            if (nextPos >= numParams)
                return false;

            outMapping.paramArgs[nextPos].argRef       = argRef;
            outMapping.paramArgs[nextPos].callArgIndex = prependUfcsArg && ufcsArg.isValid() ? userIndex + 1 : userIndex;
            ++nextPos;
        }

        return true;
    }

    Result deduceGenericFunctionArgs(Sema& sema, const SymbolFunction& root, const std::vector<GenericParamDesc>& genericParams, std::vector<GenericResolvedArg>& ioResolvedArgs, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        const auto* decl = root.decl()->safeCast<AstFunctionDecl>();
        if (!decl)
            return Result::Continue;

        std::vector<GenericFunctionParamDesc> params;
        collectFunctionParamDescs(sema, *decl, params);

        GenericCallArgMapping mapping;
        const bool            prependUfcsArg = ufcsArg.isValid() && !root.isMethod();
        if (!buildGenericCallArgMapping(sema, params, args, ufcsArg, prependUfcsArg, mapping))
            return Result::Continue;

        for (uint32_t i = 0; i < mapping.paramArgs.size(); ++i)
        {
            const GenericCallArgEntry& entry = mapping.paramArgs[i];
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

    Result createGenericFunctionInstance(Sema& sema, SymbolFunction& root, const std::vector<GenericParamDesc>& params, const std::vector<GenericResolvedArg>& resolvedArgs, SymbolFunction*& outInstance)
    {
        outInstance = nullptr;

        std::vector<FunctionGenericArgKey> keys;
        buildGenericKeys(params, resolvedArgs, keys);

        outInstance = root.findGenericInstance(keys);
        if (!outInstance)
        {
            SmallVector<SemaClone::ParamBinding> bindings;
            buildGenericCloneBindings(params, resolvedArgs, bindings);

            const SemaClone::CloneContext cloneContext{bindings};
            const AstNodeRef              cloneRef = SemaClone::cloneAst(sema, root.declNodeRef(), cloneContext);
            if (cloneRef.isInvalid())
                return Result::Error;

            auto& cloneDecl = sema.node(cloneRef).cast<AstFunctionDecl>();
            cloneDecl.spanGenericParamsRef = SpanRef::invalid();

            auto* instance = Symbol::make<SymbolFunction>(sema.ctx(), &cloneDecl, cloneDecl.tokNameRef, root.idRef(), clonedGenericSymbolFlags(root));
            instance->extraFlags() = root.extraFlags();
            instance->setAttributes(root.attributes());
            instance->setRtAttributeFlags(root.rtAttributeFlags());
            instance->setSpecOpKind(root.specOpKind());
            instance->setCallConvKind(root.callConvKind());
            instance->setDeclNodeRef(cloneRef);
            instance->setOwnerSymMap(root.ownerSymMap());
            instance->setGenericInstance(&root);

            sema.setSymbol(cloneRef, instance);
            root.addGenericInstance(keys, instance);
            outInstance = instance;
        }

        if (!outInstance->isSemaCompleted())
            SWC_RESULT(runGenericFunctionNode(sema, root, outInstance->declNodeRef()));

        return Result::Continue;
    }

    Result createGenericStructInstance(Sema& sema, SymbolStruct& root, const std::vector<GenericParamDesc>& params, const std::vector<GenericResolvedArg>& resolvedArgs, SymbolStruct*& outInstance)
    {
        outInstance = nullptr;

        std::vector<StructGenericArgKey> keys;
        buildGenericKeys(params, resolvedArgs, keys);

        outInstance = root.findGenericInstance(keys);
        if (!outInstance)
        {
            SmallVector<SemaClone::ParamBinding> bindings;
            buildGenericCloneBindings(params, resolvedArgs, bindings);

            const SemaClone::CloneContext cloneContext{bindings};
            const AstNodeRef              cloneRef = SemaClone::cloneAst(sema, root.declNodeRef(), cloneContext);
            if (cloneRef.isInvalid())
                return Result::Error;

            auto& cloneDecl = sema.node(cloneRef).cast<AstStructDecl>();
            cloneDecl.spanGenericParamsRef = SpanRef::invalid();
            cloneDecl.spanWhereRef         = SpanRef::invalid();

            auto* instance = Symbol::make<SymbolStruct>(sema.ctx(), &cloneDecl, cloneDecl.tokNameRef, root.idRef(), clonedGenericSymbolFlags(root));
            instance->extraFlags() = root.extraFlags();
            instance->setAttributes(root.attributes());
            instance->setOwnerSymMap(root.ownerSymMap());
            instance->setDeclNodeRef(cloneRef);
            instance->setGenericInstance(&root);

            sema.setSymbol(cloneRef, instance);
            root.addGenericInstance(keys, instance);
            outInstance = instance;
        }

        if (!outInstance->isSemaCompleted())
            SWC_RESULT(runGenericStructNode(sema, root, outInstance->declNodeRef()));

        return Result::Continue;
    }
}

SymbolVariable* SemaHelpers::currentRuntimeStorage(Sema& sema)
{
    SymbolVariable* const sym     = sema.frame().currentRuntimeStorageSym();
    const AstNodeRef      nodeRef = sema.frame().currentRuntimeStorageNodeRef();
    if (!sym || !nodeRef.isValid())
        return nullptr;

    const AstNodeRef resolvedTargetRef  = sema.viewZero(nodeRef).nodeRef();
    const AstNodeRef resolvedCurrentRef = sema.viewZero(sema.curNodeRef()).nodeRef();
    if (resolvedTargetRef != resolvedCurrentRef)
        return nullptr;

    return sym;
}

Result SemaHelpers::instantiateGenericFunctionExplicit(Sema& sema, SymbolFunction& genericRoot, std::span<const AstNodeRef> genericArgNodes, SmallVector<Symbol*>& outInstances)
{
    outInstances.clear();
    if (!hasGenericParams(genericRoot))
        return Result::Continue;

    const auto* decl = genericRoot.decl()->safeCast<AstFunctionDecl>();
    if (!decl)
        return Result::Continue;

    std::vector<GenericParamDesc> params;
    collectGenericParams(sema, decl->spanGenericParamsRef, params);
    if (genericArgNodes.size() > params.size())
        return Result::Continue;

    std::vector<GenericResolvedArg> resolvedArgs(params.size());
    for (size_t i = 0; i < genericArgNodes.size(); ++i)
    {
        if (params[i].kind == GenericParamKind::Type)
            SWC_RESULT(resolveGenericTypeArg(sema, genericArgNodes[i], resolvedArgs[i]));
        else
            SWC_RESULT(normalizeGenericConstantArg(sema, genericArgNodes[i], resolvedArgs[i]));
    }

    for (size_t i = genericArgNodes.size(); i < params.size(); ++i)
    {
        if (resolvedArgs[i].present)
            continue;

        GenericResolvedArg defaultArg;
        SWC_RESULT(evalGenericDefaultArg(sema, genericRoot, params, resolvedArgs, i, defaultArg));
        if (!defaultArg.present)
            return Result::Continue;
        resolvedArgs[i] = defaultArg;
    }

    for (size_t i = 0; i < params.size(); ++i)
    {
        if (!resolvedArgs[i].present)
            return Result::Continue;
        if (params[i].kind == GenericParamKind::Value)
            SWC_RESULT(finalizeResolvedGenericValue(sema, genericRoot, params, resolvedArgs, i, genericArgNodes.empty() ? sema.curNodeRef() : genericArgNodes[std::min(i, genericArgNodes.size() - 1)]));
    }

    SymbolFunction* instance = nullptr;
    SWC_RESULT(createGenericFunctionInstance(sema, genericRoot, params, resolvedArgs, instance));
    if (instance)
        outInstances.push_back(instance);
    return Result::Continue;
}

Result SemaHelpers::instantiateGenericFunctionFromCall(Sema& sema, SymbolFunction& genericRoot, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SymbolFunction*& outInstance)
{
    outInstance = nullptr;
    if (!hasGenericParams(genericRoot))
        return Result::Continue;

    const auto* decl = genericRoot.decl()->safeCast<AstFunctionDecl>();
    if (!decl)
        return Result::Continue;

    std::vector<GenericParamDesc> params;
    collectGenericParams(sema, decl->spanGenericParamsRef, params);
    if (params.empty())
        return Result::Continue;

    std::vector<GenericResolvedArg> resolvedArgs(params.size());
    SWC_RESULT(deduceGenericFunctionArgs(sema, genericRoot, params, resolvedArgs, args, ufcsArg));

    for (size_t i = 0; i < params.size(); ++i)
    {
        if (resolvedArgs[i].present)
            continue;

        GenericResolvedArg defaultArg;
        SWC_RESULT(evalGenericDefaultArg(sema, genericRoot, params, resolvedArgs, i, defaultArg));
        if (!defaultArg.present)
            return Result::Continue;
        resolvedArgs[i] = defaultArg;
    }

    for (size_t i = 0; i < params.size(); ++i)
    {
        if (!resolvedArgs[i].present)
            return Result::Continue;
        if (params[i].kind == GenericParamKind::Value)
            SWC_RESULT(finalizeResolvedGenericValue(sema, genericRoot, params, resolvedArgs, i, sema.curNodeRef()));
    }

    return createGenericFunctionInstance(sema, genericRoot, params, resolvedArgs, outInstance);
}

Result SemaHelpers::instantiateGenericStructExplicit(Sema& sema, SymbolStruct& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolStruct*& outInstance)
{
    outInstance = nullptr;
    if (!hasGenericParams(genericRoot))
        return Result::Continue;

    const auto* decl = genericRoot.decl()->safeCast<AstStructDecl>();
    if (!decl)
        return Result::Continue;

    std::vector<GenericParamDesc> params;
    collectGenericParams(sema, decl->spanGenericParamsRef, params);
    if (genericArgNodes.size() > params.size())
        return Result::Continue;

    std::vector<GenericResolvedArg> resolvedArgs(params.size());
    for (size_t i = 0; i < genericArgNodes.size(); ++i)
    {
        if (params[i].kind == GenericParamKind::Type)
            SWC_RESULT(resolveGenericTypeArg(sema, genericArgNodes[i], resolvedArgs[i]));
        else
            SWC_RESULT(normalizeGenericConstantArg(sema, genericArgNodes[i], resolvedArgs[i]));
    }

    for (size_t i = genericArgNodes.size(); i < params.size(); ++i)
    {
        if (resolvedArgs[i].present)
            continue;

        GenericResolvedArg defaultArg;
        SWC_RESULT(evalGenericDefaultArg(sema, genericRoot, params, resolvedArgs, i, defaultArg));
        if (!defaultArg.present)
            return Result::Continue;
        resolvedArgs[i] = defaultArg;
    }

    for (size_t i = 0; i < params.size(); ++i)
    {
        if (!resolvedArgs[i].present)
            return Result::Continue;
        if (params[i].kind == GenericParamKind::Value)
            SWC_RESULT(finalizeResolvedGenericValue(sema, genericRoot, params, resolvedArgs, i, genericArgNodes.empty() ? sema.curNodeRef() : genericArgNodes[std::min(i, genericArgNodes.size() - 1)]));
    }

    return createGenericStructInstance(sema, genericRoot, params, resolvedArgs, outInstance);
}

void SemaHelpers::addCurrentFunctionCallDependency(Sema& sema, SymbolFunction* calleeSym)
{
    SWC_ASSERT(calleeSym);
    if (!sema.isCurrentFunction())
        return;

    sema.currentFunction()->addCallDependency(calleeSym);
}

Result SemaHelpers::addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
{
    if (!sema.isCurrentFunction() || !typeRef.isValid())
        return Result::Continue;

    const TypeInfo& symType = sema.typeMgr().get(typeRef);
    SWC_RESULT(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
    sema.currentFunction()->addLocalVariable(sema.ctx(), &symVar);
    return Result::Continue;
}

Result SemaHelpers::addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar)
{
    return addCurrentFunctionLocalVariable(sema, symVar, symVar.typeRef());
}

bool SemaHelpers::needsPersistentCompilerRunReturn(const Sema& sema, TypeRef typeRef)
{
    if (!typeRef.isValid())
        return false;

    const auto needsPersistent = [&](auto&& self, TypeRef rawTypeRef) -> bool {
        if (!rawTypeRef.isValid())
            return false;

        const TypeInfo& typeInfo = sema.typeMgr().get(rawTypeRef);
        if (typeInfo.isAlias())
        {
            return self(self, typeInfo.unwrap(sema.ctx(), rawTypeRef, TypeExpandE::Alias));
        }

        if (typeInfo.isEnum())
        {
            return self(self, typeInfo.unwrap(sema.ctx(), rawTypeRef, TypeExpandE::Enum));
        }

        if (typeInfo.isString() || typeInfo.isSlice() || typeInfo.isAny() || typeInfo.isInterface() || typeInfo.isCString())
            return true;

        if (typeInfo.isArray())
        {
            return self(self, typeInfo.payloadArrayElemTypeRef());
        }

        if (typeInfo.isStruct())
        {
            for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
            {
                if (field && self(self, field->typeRef()))
                    return true;
            }
        }

        return false;
    };

    return needsPersistent(needsPersistent, typeRef);
}

bool SemaHelpers::functionUsesIndirectReturnStorage(TaskContext& ctx, const SymbolFunction& function)
{
    const TypeRef returnTypeRef = function.returnTypeRef();
    if (!returnTypeRef.isValid())
        return false;

    const CallConv&                        callConv      = CallConv::get(function.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(ctx, callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
    return normalizedRet.isIndirect;
}

bool SemaHelpers::currentFunctionUsesIndirectReturnStorage(Sema& sema)
{
    const SymbolFunction* currentFn = sema.currentFunction();
    return currentFn && functionUsesIndirectReturnStorage(sema.ctx(), *currentFn);
}

bool SemaHelpers::usesCallerReturnStorage(TaskContext& ctx, const SymbolFunction& function, const SymbolVariable& symVar)
{
    return symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) &&
           functionUsesIndirectReturnStorage(ctx, function);
}

AstNodeRef SemaHelpers::unwrapCallCalleeRef(Sema& sema, AstNodeRef nodeRef)
{
    while (nodeRef.isValid())
    {
        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isValid() && resolvedRef != nodeRef)
        {
            nodeRef = resolvedRef;
            continue;
        }

        const AstNode& node = sema.node(nodeRef);
        if (node.is(AstNodeId::ParenExpr))
        {
            nodeRef = node.cast<AstParenExpr>().nodeExprRef;
            continue;
        }

        break;
    }

    return nodeRef;
}

const SymbolFunction* SemaHelpers::currentLocationFunction(const Sema& sema)
{
    const auto* inlinePayload = sema.frame().currentInlinePayload();
    if (inlinePayload && inlinePayload->sourceFunction)
        return SemaRuntime::transparentLocationFunction(inlinePayload->sourceFunction);

    return SemaRuntime::transparentLocationFunction(sema.currentFunction());
}

AstNodeRef SemaHelpers::defaultArgumentExprRef(const SymbolVariable& param)
{
    const AstNode* declNode = param.decl();
    if (!declNode)
        return AstNodeRef::invalid();

    if (const auto* singleVar = declNode->safeCast<AstSingleVarDecl>())
        return singleVar->nodeInitRef;

    if (const auto* multiVar = declNode->safeCast<AstMultiVarDecl>())
        return multiVar->nodeInitRef;

    return AstNodeRef::invalid();
}

bool SemaHelpers::isDirectCallerLocationDefault(const Sema& sema, const SymbolVariable& param)
{
    const AstNodeRef initRef = defaultArgumentExprRef(param);
    if (initRef.isInvalid())
        return false;

    const AstNode& initNode = sema.node(initRef);
    if (initNode.isNot(AstNodeId::CompilerLiteral))
        return false;

    return sema.token(initNode.codeRef()).id == TokenId::CompilerCallerLocation;
}

void SemaHelpers::pushConstExprRequirement(Sema& sema, AstNodeRef childRef)
{
    SWC_ASSERT(childRef.isValid());
    auto frame = sema.frame();
    frame.addContextFlag(SemaFrameContextFlagsE::RequireConstExpr);
    sema.pushFramePopOnPostChild(frame, childRef);
}

IdentifierRef SemaHelpers::getUniqueIdentifier(Sema& sema, const std::string_view& name)
{
    const uint32_t id = sema.compiler().atomicId().fetch_add(1);
    return sema.idMgr().addIdentifierOwned(std::format("{}_{}", name, id));
}

IdentifierRef SemaHelpers::resolveIdentifier(Sema& sema, const SourceCodeRef& codeRef)
{
    const Token& tok = sema.srcView(codeRef.srcViewRef).token(codeRef.tokRef);
    if (Token::isCompilerUniq(tok.id))
        return resolveUniqIdentifier(sema, tok.id);

    if (Token::isCompilerAlias(tok.id))
    {
        const IdentifierRef idRef = resolveAliasIdentifier(sema, tok.id);
        if (idRef.isValid())
            return idRef;
    }

    return sema.idMgr().addIdentifier(sema.ctx(), codeRef);
}

uint32_t SemaHelpers::aliasSlotIndex(const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerAlias(tokenId));
    return static_cast<uint32_t>(tokenId) - static_cast<uint32_t>(TokenId::CompilerAlias0);
}

IdentifierRef SemaHelpers::resolveAliasIdentifier(Sema& sema, const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerAlias(tokenId));

    const auto* inlinePayload = sema.frame().currentInlinePayload();
    if (!inlinePayload)
        return IdentifierRef::invalid();

    const uint32_t slot = aliasSlotIndex(tokenId);
    if (slot >= inlinePayload->aliasIdentifiers.size())
        return IdentifierRef::invalid();

    return inlinePayload->aliasIdentifiers[slot];
}

uint32_t SemaHelpers::uniqSlotIndex(const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerUniq(tokenId));
    return static_cast<uint32_t>(tokenId) - static_cast<uint32_t>(TokenId::CompilerUniq0);
}

AstNodeRef SemaHelpers::uniqSyntaxScopeNodeRef(Sema& sema)
{
    if (sema.curNode().is(AstNodeId::FunctionBody) || sema.curNode().is(AstNodeId::EmbeddedBlock))
        return sema.curNodeRef();

    for (size_t parentIndex = 0;; parentIndex++)
    {
        const AstNodeRef parentRef = sema.visit().parentNodeRef(parentIndex);
        if (parentRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNodeId parentId = sema.node(parentRef).id();
        if (parentId == AstNodeId::FunctionBody || parentId == AstNodeId::EmbeddedBlock)
            return parentRef;
    }
}

SemaInlinePayload* SemaHelpers::mixinInlinePayloadForUniq(Sema& sema)
{
    auto* inlinePayload = const_cast<SemaInlinePayload*>(sema.frame().currentInlinePayload());
    if (!inlinePayload || !inlinePayload->sourceFunction)
        return nullptr;
    if (!inlinePayload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        return nullptr;
    if (uniqSyntaxScopeNodeRef(sema) != inlinePayload->inlineRootRef)
        return nullptr;
    return inlinePayload;
}

IdentifierRef SemaHelpers::ensureCurrentScopeUniqIdentifier(Sema& sema, const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerUniq(tokenId));
    const uint32_t slot = uniqSlotIndex(tokenId);
    if (auto* inlinePayload = mixinInlinePayloadForUniq(sema))
    {
        const IdentifierRef done = inlinePayload->uniqIdentifiers[slot];
        if (done.isValid())
            return done;

        const IdentifierRef idRef            = getUniqueIdentifier(sema, std::format("__uniq{}", slot));
        inlinePayload->uniqIdentifiers[slot] = idRef;
        return idRef;
    }

    auto&               scope = sema.curScope();
    const IdentifierRef done  = scope.uniqIdentifier(slot);
    if (done.isValid())
        return done;

    const IdentifierRef idRef = getUniqueIdentifier(sema, std::format("__uniq{}", slot));
    scope.setUniqIdentifier(slot, idRef);
    return idRef;
}

IdentifierRef SemaHelpers::resolveUniqIdentifier(Sema& sema, const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerUniq(tokenId));

    const uint32_t slot = uniqSlotIndex(tokenId);
    for (const SemaScope* scope = sema.lookupScope(); scope; scope = scope->lookupParent())
    {
        const IdentifierRef idRef = scope->uniqIdentifier(slot);
        if (idRef.isValid())
            return idRef;
    }

    if (const auto* inlinePayload = mixinInlinePayloadForUniq(sema))
    {
        const IdentifierRef idRef = inlinePayload->uniqIdentifiers[slot];
        if (idRef.isValid())
            return idRef;
    }

    return ensureCurrentScopeUniqIdentifier(sema, tokenId);
}

Result SemaHelpers::checkBinaryOperandTypes(Sema& sema, AstNodeRef nodeRef, TokenId op, AstNodeRef leftRef, AstNodeRef rightRef, const SemaNodeView& leftView, const SemaNodeView& rightView)
{
    switch (op)
    {
        case TokenId::SymPlus:
            if (leftView.type()->isValuePointer())
                return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, leftRef, leftView.typeRef());
            if (rightView.type()->isValuePointer())
                return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, rightRef, rightView.typeRef());

            if (leftView.type()->isBlockPointer() && leftView.type()->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, leftRef, leftView.typeRef());
            if (rightView.type()->isBlockPointer() && rightView.type()->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, rightRef, rightView.typeRef());

            if (leftView.type()->isBlockPointer() && rightView.type()->isScalarNumeric())
                return Result::Continue;
            if (leftView.type()->isBlockPointer() && rightView.type()->isBlockPointer())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef(), rightView.typeRef());
            if (leftView.type()->isScalarNumeric() && rightView.type()->isBlockPointer())
                return Result::Continue;
            break;

        case TokenId::SymMinus:
            if (leftView.type()->isValuePointer())
                return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, leftRef, leftView.typeRef());
            if (rightView.type()->isValuePointer())
                return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, rightRef, rightView.typeRef());

            if (leftView.type()->isBlockPointer() && leftView.type()->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, leftRef, leftView.typeRef());
            if (rightView.type()->isBlockPointer() && rightView.type()->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, rightRef, rightView.typeRef());

            if (leftView.type()->isBlockPointer() && rightView.type()->isScalarNumeric())
                return Result::Continue;
            if (leftView.type()->isBlockPointer() && rightView.type()->isBlockPointer())
                return Result::Continue;
            break;

        default:
            break;
    }

    switch (op)
    {
        case TokenId::SymSlash:
        case TokenId::SymPercent:
        case TokenId::SymPlus:
        case TokenId::SymMinus:
        case TokenId::SymAsterisk:
            if (!leftView.type()->isScalarNumeric())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, leftRef, leftView.typeRef(), rightView.typeRef());
            if (!rightView.type()->isScalarNumeric())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef(), rightView.typeRef());
            break;

        case TokenId::SymAmpersand:
        case TokenId::SymPipe:
        case TokenId::SymCircumflex:
        case TokenId::SymGreaterGreater:
        case TokenId::SymLowerLower:
            if (op == TokenId::SymAmpersand || op == TokenId::SymPipe || op == TokenId::SymCircumflex)
            {
                const bool leftEnumFlags  = leftView.type()->isEnumFlags();
                const bool rightEnumFlags = rightView.type()->isEnumFlags();
                if (leftEnumFlags && rightEnumFlags && leftView.typeRef() == rightView.typeRef())
                    break;
            }

            if (!leftView.type()->isInt())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, leftRef, leftView.typeRef(), rightView.typeRef());
            if (!rightView.type()->isInt())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef(), rightView.typeRef());
            break;

        default:
            break;
    }

    return Result::Continue;
}

Result SemaHelpers::castBinaryRightToLeft(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& leftView, SemaNodeView& rightView, CastKind castKind)
{
    SWC_UNUSED(nodeRef);
    switch (op)
    {
        case TokenId::SymPlus:
        case TokenId::SymMinus:
            if (leftView.type()->isBlockPointer() && rightView.type()->isScalarNumeric())
            {
                SWC_RESULT(Cast::cast(sema, rightView, sema.typeMgr().typeS64(), CastKind::Implicit));
                return Result::Continue;
            }
            if (leftView.type()->isScalarNumeric() && rightView.type()->isBlockPointer())
            {
                return Result::Continue;
            }
            if (leftView.type()->isBlockPointer() && rightView.type()->isBlockPointer())
            {
                return Result::Continue;
            }
            break;

        default:
            break;
    }

    SWC_RESULT(Cast::cast(sema, rightView, leftView.typeRef(), castKind));
    return Result::Continue;
}

Result SemaHelpers::resolveCountOfResult(Sema& sema, CountOfResultInfo& outResult, AstNodeRef exprRef)
{
    outResult               = {};
    auto               ctx  = sema.ctx();
    const SemaNodeView view = sema.viewTypeConstant(exprRef);

    if (!view.type())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, view.nodeRef());

    const auto setConstantResult = [&](ConstantRef cstRef) {
        outResult.cstRef  = cstRef;
        outResult.typeRef = sema.cstMgr().get(cstRef).typeRef();
        return Result::Continue;
    };

    if (view.cst())
    {
        if (view.cst()->isString())
            return setConstantResult(sema.cstMgr().addInt(ctx, view.cst()->getString().length()));

        if (view.cst()->isSlice())
        {
            const TypeInfo& elementType = sema.typeMgr().get(view.type()->payloadTypeRef());
            const uint64_t  elementSize = elementType.sizeOf(ctx);
            const uint64_t  count       = elementSize ? view.cst()->getSlice().size() / elementSize : 0;
            return setConstantResult(sema.cstMgr().addInt(ctx, count));
        }

        if (view.cst()->isInt())
        {
            if (view.cst()->getInt().isNegative())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_count_negative, view.nodeRef());
                diag.addArgument(Diagnostic::ARG_VALUE, view.cst()->toString(ctx));
                diag.report(ctx);
                return Result::Error;
            }

            ConstantRef newCstRef;
            SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, view.nodeRef(), view.cstRef(), TypeInfo::Sign::Unsigned));
            return setConstantResult(newCstRef);
        }
    }

    if (view.type()->isEnum())
    {
        SWC_RESULT(sema.waitSemaCompleted(view.type(), view.nodeRef()));
        outResult.cstRef  = sema.cstMgr().addInt(ctx, view.type()->payloadSymEnum().count());
        outResult.typeRef = sema.cstMgr().get(outResult.cstRef).typeRef();
        return Result::Continue;
    }

    if (view.type()->isCString())
    {
        outResult.typeRef = sema.typeMgr().typeU64();
        return Result::Continue;
    }

    if (view.type()->isString())
    {
        outResult.typeRef = sema.typeMgr().typeU64();
        return Result::Continue;
    }

    if (view.type()->isArray())
    {
        const uint64_t  sizeOf     = view.type()->sizeOf(ctx);
        const TypeRef   typeRef    = view.type()->payloadArrayElemTypeRef();
        const TypeInfo& ty         = sema.typeMgr().get(typeRef);
        const uint64_t  sizeOfElem = ty.sizeOf(ctx);
        SWC_ASSERT(sizeOfElem > 0);
        return setConstantResult(sema.cstMgr().addInt(ctx, sizeOf / sizeOfElem));
    }

    if (view.type()->isSlice() || view.type()->isAnyVariadic())
    {
        outResult.typeRef = sema.typeMgr().typeU64();
        return Result::Continue;
    }

    if (view.type()->isIntUnsigned())
    {
        outResult.typeRef = view.typeRef();
        return Result::Continue;
    }

    auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_countof_type, view.nodeRef());
    diag.addArgument(Diagnostic::ARG_TYPE, view.typeRef());
    diag.report(ctx);
    return Result::Error;
}

Result SemaHelpers::intrinsicCountOf(Sema& sema, AstNodeRef targetRef, AstNodeRef exprRef)
{
    CountOfResultInfo result;
    SWC_RESULT(resolveCountOfResult(sema, result, exprRef));
    if (result.cstRef.isValid())
    {
        sema.setConstant(targetRef, result.cstRef);
        return Result::Continue;
    }

    sema.setType(targetRef, result.typeRef);
    sema.setIsValue(targetRef);
    return Result::Continue;
}

Result SemaHelpers::finalizeAggregateStruct(Sema& sema, const SmallVector<AstNodeRef>& children)
{
    SmallVector<TypeRef>       memberTypes;
    SmallVector<IdentifierRef> memberNames;
    memberTypes.reserve(children.size());
    memberNames.reserve(children.size());

    bool                     allConstant = true;
    SmallVector<ConstantRef> values;
    values.reserve(children.size());

    for (const AstNodeRef& child : children)
    {
        const AstNode& childNode = sema.node(child);
        if (childNode.is(AstNodeId::NamedArgument))
            memberNames.push_back(sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef()));
        else
            memberNames.push_back(IdentifierRef::invalid());

        SemaNodeView view = sema.viewTypeConstant(child);
        SWC_ASSERT(view.typeRef().isValid());
        memberTypes.push_back(view.typeRef());
        allConstant = allConstant && view.cstRef().isValid();
        values.push_back(view.cstRef());
    }

    if (allConstant)
    {
        const auto val = ConstantValue::makeAggregateStruct(sema.ctx(), memberNames, values);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), val));
    }
    else
    {
        const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeAggregateStruct(memberNames, memberTypes));
        sema.setType(sema.curNodeRef(), typeRef);
    }

    sema.setIsValue(sema.curNodeRef());
    return Result::Continue;
}

void SemaHelpers::handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym)
{
    SWC_ASSERT(symbolMap != nullptr);
    SWC_ASSERT(sym != nullptr);

    if (sym->isVariable())
    {
        auto& symVar = sym->cast<SymbolVariable>();
        if (symbolMap->isStruct())
            symbolMap->cast<SymbolStruct>().addField(&symVar);

        if (sema.curScope().isParameters())
        {
            symVar.addExtraFlag(SymbolVariableFlagsE::Parameter);
            if (symbolMap->isFunction())
                symbolMap->cast<SymbolFunction>().addParameter(&symVar);
        }
    }

    if (sym->isFunction())
    {
        auto& symFunc = sym->cast<SymbolFunction>();
        if (symbolMap->isInterface())
            symbolMap->cast<SymbolInterface>().addFunction(&symFunc);
        if (symbolMap->isImpl())
            symbolMap->cast<SymbolImpl>().addFunction(sema.ctx(), &symFunc);
    }
}

namespace
{
    TypeRef memberRuntimeStorageTypeRef(Sema& sema)
    {
        SmallVector<uint64_t> dims;
        dims.push_back(8);
        return sema.typeMgr().addType(TypeInfo::makeArray(dims.span(), sema.typeMgr().typeU8()));
    }

    Result completeMemberRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        SWC_RESULT(SemaHelpers::addCurrentFunctionLocalVariable(sema, symVar, typeRef));

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    bool needsStructMemberRuntimeStorage(Sema& sema, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView)
    {
        if (sema.isGlobalScope())
            return false;
        if (!nodeLeftView.type())
            return false;
        if (nodeLeftView.type()->isReference())
            return false;
        if (!sema.isLValue(node.nodeLeftRef))
            return true;

        const SemaNodeView leftSymbolView = sema.viewSymbol(node.nodeLeftRef);
        if (!leftSymbolView.sym() || !leftSymbolView.sym()->isVariable())
            return false;

        const auto& leftSymVar = leftSymbolView.sym()->cast<SymbolVariable>();
        return leftSymVar.hasExtraFlag(SymbolVariableFlagsE::Parameter);
    }

    SymbolVariable& registerUniqueMemberRuntimeStorageSymbol(Sema& sema, const AstNode& node)
    {
        TaskContext&        ctx         = sema.ctx();
        const auto          privateName = Utf8("__member_runtime_storage");
        const IdentifierRef idRef       = SemaHelpers::getUniqueIdentifier(sema, privateName);
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();

        auto* sym = Symbol::make<SymbolVariable>(ctx, &node, node.tokRef(), idRef, flags);
        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(sym);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            symMap->addSymbol(ctx, sym, true);
        }

        return *(sym);
    }

    Result bindMatchedMemberSymbols(Sema& sema, AstNodeRef targetNodeRef, AstNodeRef rightNodeRef, bool allowOverloadSet, std::span<const Symbol*> matchedSymbols)
    {
        SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, targetNodeRef, allowOverloadSet, matchedSymbols));
        SWC_RESULT(SemaSymbolLookup::bindSymbolList(sema, rightNodeRef, allowOverloadSet, matchedSymbols));
        return Result::Continue;
    }

    Result lookupScopedMember(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SymbolMap& symMap, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{node.srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &symMap;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        SWC_RESULT(bindMatchedMemberSymbols(sema, targetNodeRef, node.nodeRightRef, allowOverloadSet, lookUpCxt.symbols().span()));
        return Result::SkipChildren;
    }

    Result memberNamespace(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolNamespace& namespaceSym = nodeLeftView.sym()->cast<SymbolNamespace>();
        return lookupScopedMember(sema, targetNodeRef, node, namespaceSym, idRef, tokNameRef, allowOverloadSet);
    }

    Result memberEnum(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolEnum& enumSym = nodeLeftView.type()->payloadSymEnum();
        SWC_RESULT(sema.waitSemaCompleted(&enumSym, {node.srcViewRef(), tokNameRef}));
        return lookupScopedMember(sema, targetNodeRef, node, enumSym, idRef, tokNameRef, allowOverloadSet);
    }

    Result memberInterface(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolInterface& symInterface = nodeLeftView.type()->payloadSymInterface();
        SWC_RESULT(sema.waitSemaCompleted(&symInterface, {node.srcViewRef(), tokNameRef}));

        const SymbolMap& lookupMap = nodeLeftView.sym() && nodeLeftView.sym()->isImpl() ? *nodeLeftView.sym()->asSymMap() : static_cast<const SymbolMap&>(symInterface);
        return lookupScopedMember(sema, targetNodeRef, node, lookupMap, idRef, tokNameRef, allowOverloadSet);
    }

    Result memberStruct(Sema& sema, AstNodeRef targetNodeRef, AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet, const TypeInfo& typeInfo)
    {
        const SymbolStruct& symStruct = typeInfo.payloadSymStruct();
        SWC_RESULT(sema.waitSemaCompleted(&symStruct, {node.srcViewRef(), tokNameRef}));

        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{node.srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &symStruct;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));

        // Bind member-access node (curNodeRef) and RHS identifier.
        SWC_RESULT(bindMatchedMemberSymbols(sema, targetNodeRef, node.nodeRightRef, allowOverloadSet, lookUpCxt.symbols().span()));

        // Constant struct member access
        const SemaNodeView       nodeRightView = sema.viewSymbolList(node.nodeRightRef);
        const std::span<Symbol*> symbols       = nodeRightView.symList();
        const size_t             finalSymCount = symbols.size();
        if (nodeLeftView.cst() && finalSymCount == 1 && symbols[0]->isVariable())
        {
            const SymbolVariable& symVar = symbols[0]->cast<SymbolVariable>();
            SWC_RESULT(ConstantExtract::structMember(sema, *nodeLeftView.cst(), symVar, targetNodeRef, node.nodeRightRef));
            return Result::SkipChildren;
        }

        if (nodeLeftView.type()->isAnyPointer() || nodeLeftView.type()->isReference() || sema.isLValue(node.nodeLeftRef))
            sema.setIsLValue(node);

        if (finalSymCount == 1 && symbols[0]->isVariable() && needsStructMemberRuntimeStorage(sema, node, nodeLeftView))
        {
            auto* payload = sema.codeGenPayload<CodeGenNodePayload>(targetNodeRef);
            if (!payload)
            {
                payload = sema.compiler().allocate<CodeGenNodePayload>();
                sema.setCodeGenPayload(targetNodeRef, payload);
            }

            if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
            {
                payload->runtimeStorageSym = boundStorage;
            }
            else
            {
                auto& storageSym = registerUniqueMemberRuntimeStorageSymbol(sema, node);
                storageSym.registerAttributes(sema);
                storageSym.setDeclared(sema.ctx());
                SWC_RESULT(Match::ghosting(sema, storageSym));
                SWC_RESULT(completeMemberRuntimeStorageSymbol(sema, storageSym, memberRuntimeStorageTypeRef(sema)));
                payload->runtimeStorageSym = &storageSym;
            }
        }

        return Result::SkipChildren;
    }

    Result memberAggregateStruct(Sema& sema, AstNodeRef targetNodeRef, AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, IdentifierRef idRef, TokenRef tokNameRef, const TypeInfo& typeInfo)
    {
        const auto& aggregate = typeInfo.payloadAggregate();
        const auto& types     = aggregate.types;
        SWC_ASSERT(aggregate.names.size() == types.size());

        size_t memberIndex = 0;
        if (!SemaHelpers::resolveAggregateMemberIndex(sema, typeInfo, idRef, memberIndex))
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_unknown_symbol, SourceCodeRef{node.srcViewRef(), tokNameRef});
            diag.addArgument(Diagnostic::ARG_SYM, idRef);
            diag.report(sema.ctx());
            return Result::SkipChildren;
        }

        const TypeRef memberTypeRef = types[memberIndex];
        sema.setType(targetNodeRef, memberTypeRef);
        sema.setType(node.nodeRightRef, memberTypeRef);
        sema.setIsValue(node);
        sema.setIsValue(node.nodeRightRef);
        if (sema.isLValue(node.nodeLeftRef))
            sema.setIsLValue(node);

        if (nodeLeftView.cst() && nodeLeftView.cst()->isAggregateStruct())
        {
            const auto& values = nodeLeftView.cst()->getAggregateStruct();
            SWC_ASSERT(memberIndex < values.size());
            sema.setConstant(targetNodeRef, values[memberIndex]);
        }
        return Result::SkipChildren;
    }
}

bool SemaHelpers::resolveAggregateMemberIndex(Sema& sema, const TypeInfo& aggregateType, IdentifierRef idRef, size_t& outIndex)
{
    if (!aggregateType.isAggregateStruct())
        return false;

    const auto&            names  = aggregateType.payloadAggregate().names;
    const std::string_view idName = sema.idMgr().get(idRef).name;
    for (size_t i = 0; i < names.size(); ++i)
    {
        if (names[i].isValid() && names[i] == idRef)
        {
            outIndex = i;
            return true;
        }

        if (!names[i].isValid() && idName == ("item" + std::to_string(i)))
        {
            outIndex = i;
            return true;
        }
    }

    return false;
}

Result SemaHelpers::resolveMemberAccess(Sema& sema, AstNodeRef memberRef, AstMemberAccessExpr& node, bool allowOverloadSet)
{
    SemaNodeView        nodeLeftView  = sema.viewNodeTypeConstantSymbol(node.nodeLeftRef);
    const SemaNodeView  nodeRightView = sema.viewNode(node.nodeRightRef);
    const TokenRef      tokNameRef    = nodeRightView.node()->tokRef();
    const IdentifierRef idRef         = sema.idMgr().addIdentifier(sema.ctx(), nodeRightView.node()->codeRef());
    SWC_ASSERT(nodeRightView.node()->is(AstNodeId::Identifier));

    // Namespace
    if (nodeLeftView.sym() && nodeLeftView.sym()->isNamespace())
        return memberNamespace(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    SWC_ASSERT(nodeLeftView.type());

    // Enum
    if (nodeLeftView.type()->isEnum())
        return memberEnum(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Interface
    if (nodeLeftView.type()->isInterface())
        return memberInterface(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Aggregate struct
    if (nodeLeftView.type()->isAggregateStruct())
        return memberAggregateStruct(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, *nodeLeftView.type());

    // Dereference pointer
    const TypeInfo* typeInfo = nodeLeftView.type();
    if (typeInfo->isTypeValue())
    {
        const TypeRef typeInfoRef = sema.typeMgr().typeTypeInfo();
        SWC_RESULT(Cast::cast(sema, nodeLeftView, typeInfoRef, CastKind::Explicit));
        typeInfo = &sema.typeMgr().get(sema.typeMgr().structTypeInfo());
    }
    else if (typeInfo->isTypeInfo())
    {
        TypeRef typeInfoRef = TypeRef::invalid();
        SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::TypeInfo, typeInfoRef, {node.srcViewRef(), tokNameRef}));
        typeInfo = &sema.typeMgr().get(typeInfoRef);
    }
    else if (typeInfo->isAnyPointer() || typeInfo->isReference())
    {
        typeInfo = &sema.typeMgr().get(typeInfo->payloadTypeRef());
    }

    // Struct
    if (typeInfo->isStruct())
        return memberStruct(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet, *typeInfo);

    // Pointer/Reference
    if (nodeLeftView.type()->isAnyPointer() || nodeLeftView.type()->isReference())
    {
        sema.setType(memberRef, nodeLeftView.type()->payloadTypeRef());
        sema.setIsValue(node);
        return Result::SkipChildren;
    }

    SWC_INTERNAL_ERROR();
}

SWC_END_NAMESPACE();
