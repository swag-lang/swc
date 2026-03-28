#include "pch.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Generic/SemaGenericTraits.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void buildGenericCloneBindings(const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, SmallVector<SemaClone::ParamBinding>& outBindings);

    Result runGenericImplBlockPass(Sema& sema, AstNodeRef blockRef, SymbolImpl& impl, SymbolInterface* itf, const AttributeList& attrs, bool declPass)
    {
        Sema child(sema.ctx(), sema, blockRef, declPass);
        child.prepareGenericInstantiationContext(impl.asSymMap(), &impl, itf, attrs);
        return child.execResult();
    }

    AstNodeRef cloneGenericImplBlock(Sema& sema, const AstImpl& implDecl, std::span<const SemaClone::ParamBinding> bindings)
    {
        SmallVector<AstNodeRef> children;
        sema.ast().appendNodes(children, implDecl.spanChildrenRef);
        if (children.empty())
            return AstNodeRef::invalid();

        SmallVector<AstNodeRef> clonedChildren;
        clonedChildren.reserve(children.size());
        const SemaClone::CloneContext cloneContext{bindings};
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

        const auto instantiateImplGroup = [&](const auto& sourceImpls, const auto& attachImpl) -> Result {
            for (const auto* sourceImpl : sourceImpls)
            {
                if (!sourceImpl)
                    continue;

                const auto* implDecl = sourceImpl->decl()->template safeCast<AstImpl>();
                SWC_ASSERT(implDecl != nullptr);
                if (!implDecl)
                    return Result::Error;

                const AstNodeRef blockRef  = cloneGenericImplBlock(sema, *implDecl, bindings.span());
                auto*            implClone = Symbol::make<SymbolImpl>(sema.ctx(), sourceImpl->decl(), sourceImpl->tokRef(), sourceImpl->idRef(), SemaGeneric::clonedGenericSymbolFlags(*sourceImpl));
                SWC_RESULT(attachImpl(*implClone, *sourceImpl));

                if (blockRef.isInvalid())
                {
                    implClone->setDeclared(sema.ctx());
                    implClone->setTyped(sema.ctx());
                    implClone->setSemaCompleted(sema.ctx());
                    continue;
                }

                SWC_RESULT(runGenericImplBlockPass(sema, blockRef, *implClone, sourceImpl->symInterface(), instance.attributes(), true));
                implClone->setDeclared(sema.ctx());

                SWC_RESULT(runGenericImplBlockPass(sema, blockRef, *implClone, sourceImpl->symInterface(), instance.attributes(), false));
                implClone->setTyped(sema.ctx());
                implClone->setSemaCompleted(sema.ctx());
            }

            return Result::Continue;
        };

        SWC_RESULT(instantiateImplGroup(rootImpls, [&](SymbolImpl& implClone, const SymbolImpl&) -> Result {
            instance.addImpl(sema, implClone);
            return Result::Continue;
        }));

        SWC_RESULT(instantiateImplGroup(rootInterfaces, [&](SymbolImpl& implClone, const SymbolImpl& sourceImpl) -> Result {
            implClone.addExtraFlag(SymbolImplFlagsE::ForInterface);
            implClone.setSymInterface(sourceImpl.symInterface());
            implClone.setTypeRef(sourceImpl.typeRef());
            SWC_RESULT(instance.addInterface(sema, implClone));
            return Result::Continue;
        }));

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

    void buildGenericCloneBindings(const std::vector<SemaGeneric::GenericParamDesc>& params, const std::vector<SemaGeneric::GenericResolvedArg>& resolvedArgs, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        outBindings.clear();
        outBindings.reserve(params.size());
        for (size_t i = 0; i < params.size(); ++i)
            SemaGeneric::appendResolvedGenericBinding(params[i], resolvedArgs[i], outBindings);
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
                SWC_RESULT(Traits::runNode(sema, root, outInstance->declNodeRef()));
            }

            if (outInstance->isIgnored())
                return Result::Error;
        }

        if constexpr (std::is_same_v<T, SymbolStruct>)
            SWC_RESULT(instantiateGenericStructImpls(sema, root, *outInstance, params, resolvedArgs));

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
}

SWC_END_NAMESPACE();
