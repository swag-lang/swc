#include "pch.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Constant/ConstantManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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
