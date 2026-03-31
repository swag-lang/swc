#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Cast/CastRequest.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Generic/SemaGenericTraits.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"

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

    template<typename T>
    void appendEnclosingGenericCloneBindings(Sema& sema, const T& root, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        SWC_UNUSED(sema);
        SWC_UNUSED(root);
        SWC_UNUSED(outBindings);
    }

    void appendEnclosingGenericCloneBindings(Sema& sema, const SymbolFunction& root, SmallVector<SemaClone::ParamBinding>& outBindings)
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
        outClone    = Symbol::make<SymbolImpl>(sema.ctx(), sourceImpl.decl(), sourceImpl.tokRef(), sourceImpl.idRef(), SemaGeneric::clonedGenericSymbolFlags(sourceImpl));
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

    template<typename T>
    Result evalGenericClonedNode(Sema& sema, const T& root, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef& outClonedRef)
    {
        outClonedRef = AstNodeRef::invalid();
        if (sourceRef.isInvalid())
            return Result::Continue;

        const SemaClone::CloneContext cloneContext{bindings};
        outClonedRef = SemaClone::cloneAst(sema, sourceRef, cloneContext);
        if (outClonedRef.isInvalid())
            return Result::Error;

        return SemaGeneric::GenericRootTraits<T>::runNode(sema, root, outClonedRef);
    }

    template<typename T>
    Result evalGenericDefaultArg(Sema& sema, const T& root, const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, size_t paramIndex, SemaGeneric::GenericResolvedArg& outArg)
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

    template<typename T>
    Result resolveGenericValueParamType(Sema& sema, const T& root, const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, size_t paramIndex, TypeRef& outTypeRef)
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

    template<typename T>
    Result finalizeResolvedGenericValue(Sema& sema, const T& root, const std::vector<SemaGeneric::GenericParamDesc>& params, std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, size_t paramIndex, AstNodeRef errorNodeRef)
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

    template<typename T>
    Result materializeGenericArgs(Sema& sema, const T& root, const std::vector<SemaGeneric::GenericParamDesc>& params, std::vector<SemaGeneric::GenericResolvedArg>& ioResolvedArgs, std::span<const AstNodeRef> genericArgNodes, AstNodeRef fallbackNodeRef)
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

    template<typename T>
    void buildGenericKeys(const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, std::vector<T>& outKeys)
    {
        outKeys.clear();
        outKeys.reserve(params.size());
        for (size_t i = 0; i < params.size(); ++i)
        {
            T key;
            if (params[i].kind == SemaGeneric::GenericParamKind::Type)
                key.typeRef = resolvedArgs[i].typeRef;
            else
                key.cstRef = resolvedArgs[i].cstRef;
            outKeys.push_back(key);
        }
    }

    template<typename T>
    struct GenericSemaGuard
    {
        T* instance = nullptr;

        ~GenericSemaGuard()
        {
            if (instance)
                instance->endGenericSema();
        }
    };

    template<typename T>
    Result createGenericInstance(Sema& sema, T& root, const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, T*& outInstance)
    {
        using Traits = SemaGeneric::GenericRootTraits<T>;
        using KeyT   = Traits::GenericArgKey;

        outInstance = nullptr;

        std::vector<KeyT> keys;
        buildGenericKeys(params, resolvedArgs, keys);

        outInstance = Traits::findInstance(root, keys);
        if (!outInstance)
        {
            SmallVector<SemaClone::ParamBinding> bindings;
            buildGenericCloneBindings(params, resolvedArgs, bindings);
            appendEnclosingGenericCloneBindings(sema, root, bindings);

            const SemaClone::CloneContext cloneContext{bindings};
            const AstNodeRef              cloneRef = SemaClone::cloneAst(sema, root.declNodeRef(), cloneContext);
            if (cloneRef.isInvalid())
                return Result::Error;

            T* created = Traits::createInstance(sema, root, cloneRef);
            sema.setSymbol(cloneRef, created);
            outInstance = Traits::addInstance(root, keys, created);
        }

        if (!outInstance->isSemaCompleted())
        {
            if (outInstance->beginGenericSema())
            {
                GenericSemaGuard<T> guard{outInstance};
                const Result        runResult = Traits::runNode(sema, root, outInstance->declNodeRef());
                if (runResult != Result::Continue)
                    return runResult;

                if constexpr (std::is_same_v<T, SymbolStruct>)
                {
                    // Keep impl cloning under the same generic-instance gate. Otherwise two callers can
                    // both observe a completed struct instance with no impls yet and clone the same impls
                    // twice, which later makes methods shadow themselves.
                    SWC_RESULT(instantiateGenericStructImpls(sema, root, *outInstance, params, resolvedArgs));
                    SWC_RESULT(outInstance->registerSpecOps(sema));
                    outInstance->setSemaCompleted(sema.ctx());
                }
            }
            if (outInstance->isIgnored())
                return Result::Error;
        }

        return Result::Continue;
    }

    template<typename T>
    Result instantiateGenericExplicit(Sema& sema, T& genericRoot, std::span<const AstNodeRef> genericArgNodes, T*& outInstance)
    {
        using Traits = SemaGeneric::GenericRootTraits<T>;

        outInstance = nullptr;
        if (!Traits::hasGenericParams(genericRoot))
            return Result::Continue;

        const auto* decl = Traits::decl(genericRoot);
        if (!decl)
            return Result::Continue;

        std::vector<SemaGeneric::GenericParamDesc> params;
        SemaGeneric::collectGenericParams(sema, decl->spanGenericParamsRef, params);
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
        return instantiateGenericExplicit(sema, genericRoot, genericArgNodes, outInstance);
    }

    Result instantiateFunctionFromCall(Sema& sema, SymbolFunction& genericRoot, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SymbolFunction*& outInstance)
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

        SWC_RESULT(materializeGenericArgs(sema, genericRoot, params, resolvedArgs, std::span<const AstNodeRef>{}, sema.curNodeRef()));
        if (hasMissingGenericArgs(resolvedArgs))
            return Result::Continue;

        return createGenericInstance(sema, genericRoot, params, resolvedArgs, outInstance);
    }

    Result instantiateStructExplicit(Sema& sema, SymbolStruct& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolStruct*& outInstance)
    {
        return instantiateGenericExplicit(sema, genericRoot, genericArgNodes, outInstance);
    }

    Result deduceStructFromContext(Sema& sema, SymbolStruct& genericRoot, SymbolStruct*& outInstance)
    {
        outInstance = nullptr;

        if (!GenericRootTraits<SymbolStruct>::hasGenericParams(genericRoot))
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
        const auto* enclosingDecl = GenericRootTraits<SymbolStruct>::decl(*enclosingRoot);
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
        const auto* targetDecl = GenericRootTraits<SymbolStruct>::decl(genericRoot);
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

        return createGenericInstance(sema, genericRoot, targetParams, resolvedArgs, outInstance);
    }
}

SWC_END_NAMESPACE();
