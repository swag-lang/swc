#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Cast/CastRequest.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void buildGenericCloneBindings(const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        outBindings.clear();
        outBindings.reserve(params.size());
        for (size_t i = 0; i < params.size(); ++i)
            SemaGeneric::appendResolvedGenericBinding(params[i], resolvedArgs[i], outBindings);
    }

    SymbolFlags clonedGenericSymbolFlags(const Symbol& root)
    {
        SymbolFlags flags = SymbolFlagsE::Zero;
        if (root.isPublic())
            flags.add(SymbolFlagsE::Public);
        return flags;
    }

    const AstFunctionDecl* genericFunctionDecl(const SymbolFunction& root)
    {
        return root.decl() ? root.decl()->safeCast<AstFunctionDecl>() : nullptr;
    }

    const AstStructDecl* genericStructDecl(const SymbolStruct& root)
    {
        return root.decl() ? root.decl()->safeCast<AstStructDecl>() : nullptr;
    }

    SpanRef genericParamSpan(const Symbol& root)
    {
        SWC_ASSERT(root.isFunction() || root.isStruct());
        if (const auto* function = root.safeCast<SymbolFunction>())
        {
            const auto* decl = genericFunctionDecl(*function);
            return decl ? decl->spanGenericParamsRef : SpanRef::invalid();
        }

        const auto* decl = genericStructDecl(root.cast<SymbolStruct>());
        return decl ? decl->spanGenericParamsRef : SpanRef::invalid();
    }

    bool hasGenericParams(const Symbol& root)
    {
        if (const auto* function = root.safeCast<SymbolFunction>())
        {
            const auto* decl = genericFunctionDecl(*function);
            return !function->isGenericInstance() && decl && decl->spanGenericParamsRef.isValid();
        }

        const auto& st   = root.cast<SymbolStruct>();
        const auto* decl = genericStructDecl(st);
        return !st.isGenericInstance() && decl && decl->spanGenericParamsRef.isValid();
    }

    AstNodeRef genericDeclNodeRef(const Symbol& root)
    {
        if (const auto* function = root.safeCast<SymbolFunction>())
            return function->declNodeRef();
        return root.cast<SymbolStruct>().declNodeRef();
    }

    Result runGenericNode(Sema& sema, const Symbol& root, AstNodeRef nodeRef)
    {
        SWC_ASSERT(root.isFunction() || root.isStruct());

        Sema child(sema.ctx(), sema, nodeRef);
        if (const auto* function = root.safeCast<SymbolFunction>())
            child.prepareGenericInstantiationContext(const_cast<SymbolMap*>(function->ownerSymMap()), function->genericDeclImpl(), function->genericDeclInterface(), function->attributes());
        else
            child.prepareGenericInstantiationContext(const_cast<SymbolMap*>(root.ownerSymMap()), nullptr, nullptr, root.attributes());
        return child.execResult();
    }

    void appendEnclosingFunctionGenericCloneBindings(Sema& sema, const SymbolFunction& root, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        const SymbolStruct* ownerInstance = root.ownerStruct();
        if (!ownerInstance || !ownerInstance->isGenericInstance())
            return;

        const SymbolStruct* ownerRoot = ownerInstance->genericRootSym();
        if (!ownerRoot)
            return;

        const auto* structDecl = ownerRoot->decl() ? ownerRoot->decl()->safeCast<AstStructDecl>() : nullptr;
        if (!structDecl || !structDecl->spanGenericParamsRef.isValid())
            return;

        std::vector<SemaGeneric::GenericParamDesc> ownerParams;
        SemaGeneric::collectGenericParams(sema, structDecl->spanGenericParamsRef, ownerParams);
        if (ownerParams.empty())
            return;

        std::vector<SymbolStruct::GenericArgKey> ownerArgs;
        if (!ownerRoot->tryGetGenericInstanceArgs(*ownerInstance, ownerArgs))
            return;
        if (ownerArgs.size() != ownerParams.size())
            return;

        for (size_t i = 0; i < ownerArgs.size(); ++i)
        {
            SemaGeneric::GenericResolvedArg resolvedArg;
            resolvedArg.present = ownerArgs[i].typeRef.isValid() || ownerArgs[i].cstRef.isValid();
            resolvedArg.typeRef = ownerArgs[i].typeRef;
            resolvedArg.cstRef  = ownerArgs[i].cstRef;
            if (resolvedArg.cstRef.isValid() && !resolvedArg.typeRef.isValid())
                resolvedArg.typeRef = sema.cstMgr().get(resolvedArg.cstRef).typeRef();
            SemaGeneric::appendResolvedGenericBinding(ownerParams[i], resolvedArg, outBindings);
        }
    }

    void appendEnclosingGenericCloneBindings(Sema& sema, const Symbol& root, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        if (const auto* function = root.safeCast<SymbolFunction>())
            appendEnclosingFunctionGenericCloneBindings(sema, *function, outBindings);
    }

    Result runGenericImplBlockPass(Sema& sema, AstNodeRef blockRef, SymbolImpl& impl, SymbolInterface* itf, const AttributeList& attrs, bool declPass)
    {
        Sema child(sema.ctx(), sema, blockRef, declPass);
        child.prepareGenericInstantiationContext(impl.asSymMap(), &impl, itf, attrs);
        return child.execResult();
    }

    void completeGenericImplClone(TaskContext& ctx, SymbolImpl& implClone)
    {
        implClone.setDeclared(ctx);
        implClone.setTyped(ctx);
        implClone.setSemaCompleted(ctx);
    }

    Result runGenericImplBlockPasses(Sema& sema, AstNodeRef blockRef, SymbolImpl& implClone, const SymbolImpl& sourceImpl, const AttributeList& attrs)
    {
        SWC_RESULT(runGenericImplBlockPass(sema, blockRef, implClone, sourceImpl.symInterface(), attrs, true));
        implClone.setDeclared(sema.ctx());

        SWC_RESULT(runGenericImplBlockPass(sema, blockRef, implClone, sourceImpl.symInterface(), attrs, false));
        implClone.setTyped(sema.ctx());
        implClone.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    AstNodeRef cloneGenericImplBlock(Sema& sema, const AstImpl& implDecl, std::span<const SemaClone::ParamBinding> bindings)
    {
        SmallVector<AstNodeRef> children;
        sema.ast().appendNodes(children, implDecl.spanChildrenRef);
        if (children.empty())
            return AstNodeRef::invalid();

        SmallVector<AstNodeRef> clonedChildren;
        clonedChildren.reserve(children.size());
        const SemaClone::CloneContext cloneContext{bindings, {}, true};
        for (const AstNodeRef childRef : children)
        {
            const AstNodeRef clonedRef = SemaClone::cloneAst(sema, childRef, cloneContext);
            if (clonedRef.isInvalid())
                return AstNodeRef::invalid();

            clonedChildren.push_back(clonedRef);
        }

        auto [blockRef, blockPtr] = sema.ast().makeNode<AstNodeId::TopLevelBlock>(implDecl.tokRef());
        blockPtr->spanChildrenRef = sema.ast().pushSpan(clonedChildren.span());
        return blockRef;
    }

    Result createGenericImplClone(Sema& sema, SymbolImpl*& outClone, AstNodeRef& outBlockRef, const SymbolImpl& sourceImpl, std::span<const SemaClone::ParamBinding> bindings)
    {
        outClone    = nullptr;
        outBlockRef = AstNodeRef::invalid();

        const auto* implDecl = sourceImpl.decl()->safeCast<AstImpl>();
        SWC_ASSERT(implDecl != nullptr);
        if (!implDecl)
            return Result::Error;

        outBlockRef = cloneGenericImplBlock(sema, *implDecl, bindings);
        outClone    = Symbol::make<SymbolImpl>(sema.ctx(), sourceImpl.decl(), sourceImpl.tokRef(), sourceImpl.idRef(), clonedGenericSymbolFlags(sourceImpl));
        return Result::Continue;
    }

    Result instantiateGenericStructImpl(Sema& sema, const SymbolImpl& sourceImpl, SymbolStruct& instance, std::span<const SemaClone::ParamBinding> bindings)
    {
        SymbolImpl* implClone = nullptr;
        AstNodeRef  blockRef  = AstNodeRef::invalid();
        SWC_RESULT(createGenericImplClone(sema, implClone, blockRef, sourceImpl, bindings));

        instance.addImpl(sema, *implClone);
        if (blockRef.isInvalid())
        {
            completeGenericImplClone(sema.ctx(), *implClone);
            return Result::Continue;
        }

        return runGenericImplBlockPasses(sema, blockRef, *implClone, sourceImpl, instance.attributes());
    }

    Result instantiateGenericStructInterface(Sema& sema, const SymbolImpl& sourceImpl, SymbolStruct& instance, std::span<const SemaClone::ParamBinding> bindings)
    {
        SymbolImpl* implClone = nullptr;
        AstNodeRef  blockRef  = AstNodeRef::invalid();
        SWC_RESULT(createGenericImplClone(sema, implClone, blockRef, sourceImpl, bindings));

        implClone->addExtraFlag(SymbolImplFlagsE::ForInterface);
        implClone->setSymInterface(sourceImpl.symInterface());
        implClone->setTypeRef(sourceImpl.typeRef());
        SWC_RESULT(instance.addInterface(sema, *implClone));

        if (blockRef.isInvalid())
        {
            completeGenericImplClone(sema.ctx(), *implClone);
            return Result::Continue;
        }

        return runGenericImplBlockPasses(sema, blockRef, *implClone, sourceImpl, instance.attributes());
    }

    Result instantiateGenericStructImpls(Sema& sema, const SymbolStruct& root, SymbolStruct& instance, const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs)
    {
        if (!instance.impls().empty() || !instance.interfaces().empty())
            return Result::Continue;

        const auto rootImpls      = root.impls();
        const auto rootInterfaces = root.interfaces();
        if (rootImpls.empty() && rootInterfaces.empty())
            return Result::Continue;

        SmallVector<SemaClone::ParamBinding> bindings;
        buildGenericCloneBindings(params, resolvedArgs, bindings);

        for (const auto* sourceImpl : rootImpls)
        {
            if (!sourceImpl)
                continue;
            SWC_RESULT(instantiateGenericStructImpl(sema, *sourceImpl, instance, bindings.span()));
        }

        for (const auto* sourceImpl : rootInterfaces)
        {
            if (!sourceImpl)
                continue;
            SWC_RESULT(instantiateGenericStructInterface(sema, *sourceImpl, instance, bindings.span()));
        }

        return Result::Continue;
    }

    Result evalGenericClonedNode(Sema& sema, const Symbol& root, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef& outClonedRef)
    {
        outClonedRef = AstNodeRef::invalid();
        if (sourceRef.isInvalid())
            return Result::Continue;

        const SemaClone::CloneContext cloneContext{bindings};
        outClonedRef = SemaClone::cloneAst(sema, sourceRef, cloneContext);
        if (outClonedRef.isInvalid())
            return Result::Error;

        return runGenericNode(sema, root, outClonedRef);
    }

    Result evalGenericDefaultArg(Sema& sema, const Symbol& root, const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, size_t paramIndex, SemaGeneric::GenericResolvedArg& outArg)
    {
        outArg                                     = {};
        const SemaGeneric::GenericParamDesc& param = params[paramIndex];
        if (param.defaultRef.isInvalid())
            return Result::Continue;

        SmallVector<SemaClone::ParamBinding> bindings;
        SemaGeneric::collectResolvedGenericBindings(params, resolvedArgs, paramIndex, bindings);
        appendEnclosingGenericCloneBindings(sema, root, bindings);

        AstNodeRef clonedRef = AstNodeRef::invalid();
        SWC_RESULT(evalGenericClonedNode(sema, root, param.defaultRef, bindings, clonedRef));
        if (clonedRef.isInvalid())
            return Result::Error;

        return SemaGeneric::resolveExplicitGenericArg(sema, param, clonedRef, outArg);
    }

    Result resolveGenericValueParamType(Sema& sema, const Symbol& root, const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, size_t paramIndex, TypeRef& outTypeRef)
    {
        outTypeRef                                 = TypeRef::invalid();
        const SemaGeneric::GenericParamDesc& param = params[paramIndex];
        if (param.explicitType.isInvalid())
            return Result::Continue;

        SmallVector<SemaClone::ParamBinding> bindings;
        SemaGeneric::collectResolvedGenericBindings(params, resolvedArgs, paramIndex, bindings);
        appendEnclosingGenericCloneBindings(sema, root, bindings);

        AstNodeRef clonedTypeRef = AstNodeRef::invalid();
        SWC_RESULT(evalGenericClonedNode(sema, root, param.explicitType, bindings, clonedTypeRef));
        if (clonedTypeRef.isInvalid())
            return Result::Error;

        outTypeRef = sema.viewType(clonedTypeRef).typeRef();
        return Result::Continue;
    }

    Result finalizeResolvedGenericValue(Sema& sema, const Symbol& root, const std::vector<SemaGeneric::GenericParamDesc>& params, std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, size_t paramIndex, AstNodeRef errorNodeRef)
    {
        SemaGeneric::GenericResolvedArg& arg = resolvedArgs[paramIndex];
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

    Result materializeGenericArgs(Sema& sema, const Symbol& root, const std::vector<SemaGeneric::GenericParamDesc>& params, std::vector<SemaGeneric::GenericResolvedArg>& ioResolvedArgs, std::span<const AstNodeRef> genericArgNodes, AstNodeRef fallbackNodeRef)
    {
        for (size_t i = 0; i < params.size(); ++i)
        {
            if (ioResolvedArgs[i].present)
                continue;

            SemaGeneric::GenericResolvedArg defaultArg;
            SWC_RESULT(evalGenericDefaultArg(sema, root, params, ioResolvedArgs, i, defaultArg));
            if (!defaultArg.present)
                return Result::Continue;
            ioResolvedArgs[i] = defaultArg;
        }

        for (size_t i = 0; i < params.size(); ++i)
        {
            if (!ioResolvedArgs[i].present)
                return Result::Continue;
            if (params[i].kind == SemaGeneric::GenericParamKind::Value)
                SWC_RESULT(finalizeResolvedGenericValue(sema, root, params, ioResolvedArgs, i, genericErrorNodeRef(genericArgNodes, i, fallbackNodeRef)));
        }

        return Result::Continue;
    }

    struct GenericInstanceKey
    {
        TypeRef     typeRef = TypeRef::invalid();
        ConstantRef cstRef  = ConstantRef::invalid();
    };

    void buildGenericKeys(const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, std::vector<GenericInstanceKey>& outKeys)
    {
        outKeys.clear();
        outKeys.reserve(params.size());
        for (size_t i = 0; i < params.size(); ++i)
        {
            GenericInstanceKey key;
            if (params[i].kind == SemaGeneric::GenericParamKind::Type)
                key.typeRef = resolvedArgs[i].typeRef;
            else
                key.cstRef = resolvedArgs[i].cstRef;
            outKeys.push_back(key);
        }
    }

    Symbol* findGenericInstance(const SymbolFunction& root, std::span<const GenericInstanceKey> keys)
    {
        std::vector<SymbolFunction::GenericArgKey> typedKeys;
        typedKeys.reserve(keys.size());
        for (const auto& key : keys)
            typedKeys.push_back({key.typeRef, key.cstRef});
        return root.findGenericInstance(typedKeys);
    }

    Symbol* findGenericInstance(const SymbolStruct& root, std::span<const GenericInstanceKey> keys)
    {
        std::vector<SymbolStruct::GenericArgKey> typedKeys;
        typedKeys.reserve(keys.size());
        for (const auto& key : keys)
            typedKeys.push_back({key.typeRef, key.cstRef});
        return root.findGenericInstance(typedKeys);
    }

    Symbol* findGenericInstance(const Symbol& root, std::span<const GenericInstanceKey> keys)
    {
        if (const auto* function = root.safeCast<SymbolFunction>())
            return findGenericInstance(*function, keys);
        return findGenericInstance(root.cast<SymbolStruct>(), keys);
    }

    Symbol* addGenericInstance(SymbolFunction& root, std::span<const GenericInstanceKey> keys, SymbolFunction* instance)
    {
        std::vector<SymbolFunction::GenericArgKey> typedKeys;
        typedKeys.reserve(keys.size());
        for (const auto& key : keys)
            typedKeys.push_back({key.typeRef, key.cstRef});
        return root.addGenericInstance(typedKeys, instance);
    }

    Symbol* addGenericInstance(SymbolStruct& root, std::span<const GenericInstanceKey> keys, SymbolStruct* instance)
    {
        std::vector<SymbolStruct::GenericArgKey> typedKeys;
        typedKeys.reserve(keys.size());
        for (const auto& key : keys)
            typedKeys.push_back({key.typeRef, key.cstRef});
        return root.addGenericInstance(typedKeys, instance);
    }

    Symbol* addGenericInstance(Symbol& root, std::span<const GenericInstanceKey> keys, Symbol* instance)
    {
        if (auto* function = root.safeCast<SymbolFunction>())
            return addGenericInstance(*function, keys, &instance->cast<SymbolFunction>());
        return addGenericInstance(root.cast<SymbolStruct>(), keys, &instance->cast<SymbolStruct>());
    }

    Symbol* createGenericInstanceSymbol(Sema& sema, Symbol& root, AstNodeRef cloneRef)
    {
        if (auto* function = root.safeCast<SymbolFunction>())
        {
            auto& cloneDecl                = sema.node(cloneRef).cast<AstFunctionDecl>();
            cloneDecl.spanGenericParamsRef = SpanRef::invalid();

            auto* instance         = Symbol::make<SymbolFunction>(sema.ctx(), &cloneDecl, cloneDecl.tokNameRef, function->idRef(), clonedGenericSymbolFlags(root));
            instance->extraFlags() = function->extraFlags();
            instance->setAttributes(function->attributes());
            instance->setRtAttributeFlags(function->rtAttributeFlags());
            instance->setSpecOpKind(function->specOpKind());
            instance->setCallConvKind(function->callConvKind());
            instance->setDeclNodeRef(cloneRef);
            instance->setOwnerSymMap(function->ownerSymMap());
            instance->setGenericInstance(function);
            return instance;
        }

        auto& cloneDecl                = sema.node(cloneRef).cast<AstStructDecl>();
        cloneDecl.spanGenericParamsRef = SpanRef::invalid();
        cloneDecl.spanWhereRef         = SpanRef::invalid();

        auto& st               = root.cast<SymbolStruct>();
        auto* instance         = Symbol::make<SymbolStruct>(sema.ctx(), &cloneDecl, cloneDecl.tokNameRef, st.idRef(), clonedGenericSymbolFlags(root));
        instance->extraFlags() = st.extraFlags();
        instance->setAttributes(st.attributes());
        instance->setOwnerSymMap(st.ownerSymMap());
        instance->setDeclNodeRef(cloneRef);
        instance->setGenericInstance(&st);
        return instance;
    }

    bool beginGenericSema(const Symbol& instance)
    {
        if (const auto* function = instance.safeCast<SymbolFunction>())
            return function->beginGenericSema();
        return instance.cast<SymbolStruct>().beginGenericSema();
    }

    void endGenericSema(const Symbol& instance)
    {
        if (const auto* function = instance.safeCast<SymbolFunction>())
            function->endGenericSema();
        else
            instance.cast<SymbolStruct>().endGenericSema();
    }

    struct GenericSemaGuard
    {
        Symbol* instance = nullptr;

        ~GenericSemaGuard()
        {
            if (instance)
                endGenericSema(*instance);
        }
    };

    Result finalizeGenericInstance(Sema& sema, const Symbol& root, Symbol& instance, const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs)
    {
        if (!instance.isStruct())
            return Result::Continue;

        // Keep impl cloning under the same generic-instance gate. Otherwise two callers can
        // both observe a completed struct instance with no impls yet and clone the same impls
        // twice, which later makes methods shadow themselves.
        auto& rootStruct     = root.cast<SymbolStruct>();
        auto& instanceStruct = instance.cast<SymbolStruct>();
        SWC_RESULT(instantiateGenericStructImpls(sema, rootStruct, instanceStruct, params, resolvedArgs));
        SWC_RESULT(instanceStruct.registerSpecOps(sema));
        instanceStruct.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    Result createGenericInstance(Sema& sema, Symbol& root, const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, Symbol*& outInstance)
    {
        outInstance = nullptr;

        std::vector<GenericInstanceKey> keys;
        buildGenericKeys(params, resolvedArgs, keys);

        outInstance = findGenericInstance(root, keys);
        if (!outInstance)
        {
            SmallVector<SemaClone::ParamBinding> bindings;
            buildGenericCloneBindings(params, resolvedArgs, bindings);
            appendEnclosingGenericCloneBindings(sema, root, bindings);

            const SemaClone::CloneContext cloneContext{bindings};
            const AstNodeRef              cloneRef = SemaClone::cloneAst(sema, genericDeclNodeRef(root), cloneContext);
            if (cloneRef.isInvalid())
                return Result::Error;

            Symbol* created = createGenericInstanceSymbol(sema, root, cloneRef);
            sema.setSymbol(cloneRef, created);
            outInstance = addGenericInstance(root, keys, created);
        }

        if (!outInstance->isSemaCompleted())
        {
            if (beginGenericSema(*outInstance))
            {
                GenericSemaGuard guard{outInstance};
                const Result     runResult = runGenericNode(sema, root, genericDeclNodeRef(*outInstance));
                if (runResult != Result::Continue)
                    return runResult;
                SWC_RESULT(finalizeGenericInstance(sema, root, *outInstance, params, resolvedArgs));
            }
            if (outInstance->isIgnored())
                return Result::Error;
        }

        return Result::Continue;
    }

    Result instantiateGenericExplicit(Sema& sema, Symbol& genericRoot, std::span<const AstNodeRef> genericArgNodes, Symbol*& outInstance)
    {
        outInstance = nullptr;
        if (!hasGenericParams(genericRoot))
            return Result::Continue;

        const SpanRef spanRef = genericParamSpan(genericRoot);
        if (!spanRef.isValid())
            return Result::Continue;

        std::vector<SemaGeneric::GenericParamDesc> params;
        SemaGeneric::collectGenericParams(sema, spanRef, params);
        if (genericArgNodes.size() > params.size())
            return Result::Continue;

        std::vector<SemaGeneric::GenericResolvedArg> resolvedArgs(params.size());
        for (size_t i = 0; i < genericArgNodes.size(); ++i)
            SWC_RESULT(SemaGeneric::resolveExplicitGenericArg(sema, params[i], genericArgNodes[i], resolvedArgs[i]));

        SWC_RESULT(materializeGenericArgs(sema, genericRoot, params, resolvedArgs, genericArgNodes, sema.curNodeRef()));
        if (SemaGeneric::hasMissingGenericArgs(resolvedArgs))
            return Result::Continue;

        return createGenericInstance(sema, genericRoot, params, resolvedArgs, outInstance);
    }
}

namespace SemaGeneric
{
    Result instantiateFunctionExplicit(Sema& sema, SymbolFunction& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolFunction*& outInstance)
    {
        Symbol* instance = nullptr;
        SWC_RESULT(instantiateGenericExplicit(sema, genericRoot, genericArgNodes, instance));
        outInstance = instance ? &instance->cast<SymbolFunction>() : nullptr;
        return Result::Continue;
    }

    Result instantiateFunctionFromCall(Sema& sema, SymbolFunction& genericRoot, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SymbolFunction*& outInstance)
    {
        outInstance = nullptr;
        if (!hasGenericParams(genericRoot))
            return Result::Continue;

        const auto* decl = genericFunctionDecl(genericRoot);
        if (!decl)
            return Result::Continue;

        std::vector<GenericParamDesc> params;
        collectGenericParams(sema, decl->spanGenericParamsRef, params);
        if (params.empty())
            return Result::Continue;

        std::vector<GenericResolvedArg> resolvedArgs(params.size());
        SWC_RESULT(deduceGenericFunctionArgs(sema, genericRoot, params, resolvedArgs, args, ufcsArg));

        SWC_RESULT(materializeGenericArgs(sema, genericRoot, params, resolvedArgs, std::span<const AstNodeRef>{}, sema.curNodeRef()));
        if (hasMissingGenericArgs(resolvedArgs))
            return Result::Continue;

        Symbol* instance = nullptr;
        SWC_RESULT(createGenericInstance(sema, genericRoot, params, resolvedArgs, instance));
        outInstance = instance ? &instance->cast<SymbolFunction>() : nullptr;
        return Result::Continue;
    }

    Result instantiateStructExplicit(Sema& sema, SymbolStruct& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolStruct*& outInstance)
    {
        Symbol* instance = nullptr;
        SWC_RESULT(instantiateGenericExplicit(sema, genericRoot, genericArgNodes, instance));
        outInstance = instance ? &instance->cast<SymbolStruct>() : nullptr;
        return Result::Continue;
    }

    Result deduceStructFromContext(Sema& sema, SymbolStruct& genericRoot, SymbolStruct*& outInstance)
    {
        outInstance = nullptr;

        if (!hasGenericParams(genericRoot))
            return Result::Continue;

        // Find enclosing generic struct instance from impl context or struct declaration scope
        const SymbolStruct* enclosingInstance = nullptr;
        for (size_t i = sema.frames().size(); i > 0; --i)
        {
            const auto* impl = sema.frames()[i - 1].currentImpl();
            if (impl && impl->isForStruct())
            {
                const auto* st = impl->symStruct();
                if (st && st->isGenericInstance())
                {
                    enclosingInstance = st;
                    break;
                }
            }
        }

        // Also check scope chain for struct declaration context (field types during generic instantiation)
        if (!enclosingInstance)
        {
            for (const SemaScope* scope = sema.curScopePtr(); scope; scope = scope->parent())
            {
                const auto* symMap = scope->symMap();
                if (symMap && symMap->isStruct())
                {
                    const auto& st = symMap->cast<SymbolStruct>();
                    if (st.isGenericInstance())
                    {
                        enclosingInstance = &st;
                        break;
                    }
                }
            }
        }

        if (!enclosingInstance)
            return Result::Continue;

        const SymbolStruct* enclosingRoot = enclosingInstance->genericRootSym();
        if (!enclosingRoot)
            return Result::Continue;

        // Collect enclosing root's generic params and instance args
        const auto* enclosingDecl = genericStructDecl(*enclosingRoot);
        if (!enclosingDecl || !enclosingDecl->spanGenericParamsRef.isValid())
            return Result::Continue;

        std::vector<GenericParamDesc> enclosingParams;
        collectGenericParams(sema, enclosingDecl->spanGenericParamsRef, enclosingParams);

        std::vector<SymbolStruct::GenericArgKey> enclosingArgs;
        if (!enclosingRoot->tryGetGenericInstanceArgs(*enclosingInstance, enclosingArgs))
            return Result::Continue;
        if (enclosingArgs.size() != enclosingParams.size())
            return Result::Continue;

        // Collect target struct's generic params
        const auto* targetDecl = genericStructDecl(genericRoot);
        if (!targetDecl)
            return Result::Continue;

        std::vector<GenericParamDesc> targetParams;
        collectGenericParams(sema, targetDecl->spanGenericParamsRef, targetParams);

        // If the current function has generic type params that conflict with target params, skip deduction
        if (const auto* func = sema.currentFunction())
        {
            const auto* funcDecl = func->decl() ? func->decl()->safeCast<AstFunctionDecl>() : nullptr;
            if (funcDecl && funcDecl->spanGenericParamsRef.isValid())
            {
                std::vector<GenericParamDesc> funcParams;
                collectGenericParams(sema, funcDecl->spanGenericParamsRef, funcParams);
                for (const auto& fp : funcParams)
                {
                    if (fp.kind != GenericParamKind::Type)
                        continue;
                    for (const auto& tp : targetParams)
                    {
                        if (tp.kind == GenericParamKind::Type && tp.idRef == fp.idRef)
                            return Result::Continue;
                    }
                }
            }
        }

        // Match target params against enclosing params by name
        std::vector<GenericResolvedArg> resolvedArgs(targetParams.size());
        for (size_t i = 0; i < targetParams.size(); ++i)
        {
            bool found = false;
            for (size_t j = 0; j < enclosingParams.size(); ++j)
            {
                if (targetParams[i].idRef == enclosingParams[j].idRef &&
                    targetParams[i].kind == enclosingParams[j].kind)
                {
                    resolvedArgs[i].present = true;
                    resolvedArgs[i].typeRef = enclosingArgs[j].typeRef;
                    resolvedArgs[i].cstRef  = enclosingArgs[j].cstRef;
                    found                   = true;
                    break;
                }
            }

            if (!found)
                return Result::Continue;
        }

        // Materialize defaults and create instance
        SWC_RESULT(materializeGenericArgs(sema, genericRoot, targetParams, resolvedArgs, std::span<const AstNodeRef>{}, sema.curNodeRef()));
        if (hasMissingGenericArgs(resolvedArgs))
            return Result::Continue;

        Symbol* instance = nullptr;
        SWC_RESULT(createGenericInstance(sema, genericRoot, targetParams, resolvedArgs, instance));
        outInstance = instance ? &instance->cast<SymbolStruct>() : nullptr;
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
