#include "pch.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Cast/CastFailure.h"
#include "Compiler/Sema/Cast/CastRequest.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const SymbolFunction* declContextRoot(const SymbolFunction& function)
    {
        if (const auto* root = function.genericRootSym())
            return root;
        return &function;
    }

    SymbolMap* functionDeclStartSymMap(const SymbolFunction& function)
    {
        return const_cast<SymbolMap*>(declContextRoot(function)->ownerSymMap());
    }

    const SymbolImpl* functionDeclImplContext(Sema& sema, const SymbolFunction& function)
    {
        if (const SymbolImpl* symImpl = function.declImplContext())
            return symImpl;

        if (const SymbolImpl* symImpl = sema.frame().currentImpl())
            return symImpl;

        for (SymbolMap* symMap = sema.curSymMap(); symMap; symMap = symMap->ownerSymMap())
        {
            if (symMap->isImpl())
                return &symMap->cast<SymbolImpl>();
        }

        return nullptr;
    }

    const SymbolInterface* functionDeclInterfaceContext(Sema& sema, const SymbolFunction& function)
    {
        if (const SymbolInterface* symItf = function.declInterfaceContext())
            return symItf;

        if (const SymbolInterface* symItf = sema.frame().currentInterface())
            return symItf;

        if (const SymbolImpl* symImpl = sema.frame().currentImpl())
        {
            if (const SymbolInterface* symItf = symImpl->symInterface())
                return symItf;
        }

        for (SymbolMap* symMap = sema.curSymMap(); symMap; symMap = symMap->ownerSymMap())
        {
            if (symMap->isInterface())
                return &symMap->cast<SymbolInterface>();

            if (symMap->isImpl())
            {
                if (const SymbolInterface* symItf = symMap->cast<SymbolImpl>().symInterface())
                    return symItf;
            }
        }

        return nullptr;
    }

    void buildGenericCloneBindings(std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, SmallVector<SemaClone::ParamBinding>& outBindings)
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
        {
            SemaGeneric::prepareGenericInstantiationContext(child,
                                                            functionDeclStartSymMap(*function),
                                                            functionDeclImplContext(sema, *function),
                                                            functionDeclInterfaceContext(sema, *function),
                                                            function->attributes());
        }
        else
            SemaGeneric::prepareGenericInstantiationContext(child, const_cast<SymbolMap*>(root.ownerSymMap()), nullptr, nullptr, root.attributes());
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

        SmallVector<SemaGeneric::GenericParamDesc> ownerParams;
        SemaGeneric::collectGenericParams(sema, structDecl->spanGenericParamsRef, ownerParams);
        if (ownerParams.empty())
            return;

        SmallVector<GenericInstanceKey> ownerArgs;
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

    Result evalGenericClonedNode(Sema& sema, const Symbol& root, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef& outClonedRef);

    Utf8 formatResolvedGenericArg(Sema& sema, const SemaGeneric::GenericResolvedArg& arg)
    {
        if (arg.typeRef.isValid())
            return sema.typeMgr().get(arg.typeRef).toName(sema.ctx());
        if (arg.cstRef.isValid())
            return sema.cstMgr().get(arg.cstRef).toString(sema.ctx());
        return "?";
    }

    Utf8 formatResolvedGenericBindings(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs)
    {
        Utf8 result;
        for (size_t i = 0; i < params.size(); ++i)
        {
            if (!result.empty())
                result += ", ";

            result += sema.idMgr().get(params[i].idRef).name;
            result += " = ";
            result += formatResolvedGenericArg(sema, resolvedArgs[i]);
        }

        return result;
    }

    AstNodeRef genericStructConstraintExprRef(Sema& sema, AstNodeRef whereRef)
    {
        if (!whereRef.isValid())
            return AstNodeRef::invalid();

        if (const auto* constraintExpr = sema.node(whereRef).safeCast<AstConstraintExpr>())
            return constraintExpr->nodeExprRef;
        return AstNodeRef::invalid();
    }

    Diagnostic reportGenericStructConstraintDiag(Sema& sema, DiagnosticId diagId, const SymbolStruct& root, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef errorNodeRef, AstNodeRef whereRef)
    {
        const AstNodeRef mainRef = errorNodeRef.isValid() ? errorNodeRef : root.declNodeRef();
        auto             diag    = SemaError::report(sema, diagId, mainRef);
        diag.addArgument(Diagnostic::ARG_SYM, root.name(sema.ctx()));

        if (!params.empty())
        {
            diag.addNote(DiagnosticId::sema_note_generic_instantiated_with);
            diag.last().addArgument(Diagnostic::ARG_VALUES, formatResolvedGenericBindings(sema, params, resolvedArgs));
        }

        if (whereRef.isValid())
        {
            diag.addNote(DiagnosticId::sema_note_generic_where_declared_here);
            SemaError::addSpan(sema, diag.last(), whereRef);
        }

        return diag;
    }

    Result raiseGenericStructConstraintNotBool(Sema& sema, const SymbolStruct& root, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef errorNodeRef, AstNodeRef whereRef, TypeRef typeRef)
    {
        auto diag = reportGenericStructConstraintDiag(sema, DiagnosticId::sema_err_generic_struct_where_not_bool, root, params, resolvedArgs, errorNodeRef, whereRef);
        diag.addArgument(Diagnostic::ARG_TYPE, typeRef.isValid() ? sema.typeMgr().get(typeRef).toName(sema.ctx()) : Utf8{"<invalid>"});
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result raiseGenericStructConstraintNotConst(Sema& sema, const SymbolStruct& root, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef errorNodeRef, AstNodeRef whereRef)
    {
        const auto diag = reportGenericStructConstraintDiag(sema, DiagnosticId::sema_err_generic_struct_where_not_const, root, params, resolvedArgs, errorNodeRef, whereRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result raiseGenericStructConstraintFailed(Sema& sema, const SymbolStruct& root, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef errorNodeRef, AstNodeRef whereRef)
    {
        const auto diag = reportGenericStructConstraintDiag(sema, DiagnosticId::sema_err_generic_struct_where_failed, root, params, resolvedArgs, errorNodeRef, whereRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result validateGenericStructWhereConstraints(Sema& sema, const SymbolStruct& root, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, AstNodeRef errorNodeRef)
    {
        const auto* decl = genericStructDecl(root);
        if (!decl || decl->spanWhereRef.isInvalid())
            return Result::Continue;

        SmallVector<SemaClone::ParamBinding> bindings;
        buildGenericCloneBindings(params, resolvedArgs, bindings);
        appendEnclosingGenericCloneBindings(sema, root, bindings);

        SmallVector<AstNodeRef> whereRefs;
        sema.ast().appendNodes(whereRefs, decl->spanWhereRef);
        for (const AstNodeRef whereRef : whereRefs)
        {
            const AstNodeRef whereExprRef = genericStructConstraintExprRef(sema, whereRef);
            if (whereExprRef.isInvalid())
                continue;

            AstNodeRef clonedExprRef = AstNodeRef::invalid();
            SWC_RESULT(evalGenericClonedNode(sema, root, whereExprRef, bindings.span(), clonedExprRef));

            const SemaNodeView whereView = sema.viewNodeTypeConstant(clonedExprRef);
            if (!whereView.typeRef().isValid() || !whereView.type()->isBool())
                return raiseGenericStructConstraintNotBool(sema, root, params, resolvedArgs, errorNodeRef, whereRef, whereView.typeRef());

            if (!whereView.cstRef().isValid())
                return raiseGenericStructConstraintNotConst(sema, root, params, resolvedArgs, errorNodeRef, whereRef);

            if (whereView.cstRef() != sema.cstMgr().cstTrue())
                return raiseGenericStructConstraintFailed(sema, root, params, resolvedArgs, errorNodeRef, whereRef);
        }

        return Result::Continue;
    }

    Result runGenericImplBlockPass(Sema& sema, AstNodeRef blockRef, SymbolImpl& impl, const SymbolInterface* itf, const AttributeList& attrs, bool declPass)
    {
        Sema child(sema.ctx(), sema, blockRef, declPass);
        SemaGeneric::prepareGenericInstantiationContext(child, impl.asSymMap(), &impl, itf, attrs);
        return child.execResult();
    }

    void completeGenericImplClone(TaskContext& ctx, SymbolImpl& implClone)
    {
        implClone.setDeclared(ctx);
        implClone.setTyped(ctx);
        implClone.setSemaCompleted(ctx);
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
        outClone->setGenericBlockRef(outBlockRef);
        return Result::Continue;
    }

    SymbolImpl* findGenericImplClone(std::span<SymbolImpl* const> impls, const SymbolImpl& sourceImpl)
    {
        for (SymbolImpl* implClone : impls)
        {
            if (!implClone || implClone->isIgnored() || implClone->decl() != sourceImpl.decl())
                continue;
            return implClone;
        }

        return nullptr;
    }

    Result runGenericImplClonePasses(Sema& sema, SymbolImpl& implClone, const SymbolImpl& sourceImpl, const AttributeList& attrs)
    {
        const AstNodeRef blockRef = implClone.genericBlockRef();
        if (blockRef.isInvalid())
        {
            completeGenericImplClone(sema.ctx(), implClone);
            return Result::Continue;
        }

        if (!implClone.isDeclared())
        {
            SWC_RESULT(runGenericImplBlockPass(sema, blockRef, implClone, sourceImpl.symInterface(), attrs, true));
            implClone.setDeclared(sema.ctx());
        }

        if (!implClone.isTyped() || !implClone.isSemaCompleted())
        {
            SWC_RESULT(runGenericImplBlockPass(sema, blockRef, implClone, sourceImpl.symInterface(), attrs, false));
            implClone.setTyped(sema.ctx());
            implClone.setSemaCompleted(sema.ctx());
        }

        return Result::Continue;
    }

    Result instantiateGenericStructImpl(Sema& sema, const SymbolImpl& sourceImpl, SymbolStruct& instance, std::span<const SemaClone::ParamBinding> bindings)
    {
        SymbolImpl* implClone = findGenericImplClone(instance.impls(), sourceImpl);
        bool        created   = false;
        if (!implClone)
        {
            AstNodeRef blockRef = AstNodeRef::invalid();
            SWC_RESULT(createGenericImplClone(sema, implClone, blockRef, sourceImpl, bindings));
            instance.addImpl(sema, *implClone);
            created = true;
        }

        const Result result = runGenericImplClonePasses(sema, *implClone, sourceImpl, instance.attributes());
        if (result != Result::Continue && created && !implClone->isSemaCompleted())
            implClone->setIgnored(sema.ctx());
        return result;
    }

    Result instantiateGenericStructInterface(Sema& sema, const SymbolImpl& sourceImpl, SymbolStruct& instance, std::span<const SemaClone::ParamBinding> bindings)
    {
        SymbolImpl* implClone = findGenericImplClone(instance.interfaces(), sourceImpl);
        if (!implClone)
        {
            AstNodeRef blockRef = AstNodeRef::invalid();
            SWC_RESULT(createGenericImplClone(sema, implClone, blockRef, sourceImpl, bindings));
            implClone->setSymStruct(&instance);
            implClone->addExtraFlag(SymbolImplFlagsE::ForInterface);
            implClone->setSymInterface(sourceImpl.symInterface());
            implClone->setTypeRef(sourceImpl.typeRef());
            SWC_RESULT(runGenericImplClonePasses(sema, *implClone, sourceImpl, instance.attributes()));
            SWC_RESULT(instance.addInterface(sema, *implClone));
            return Result::Continue;
        }

        return runGenericImplClonePasses(sema, *implClone, sourceImpl, instance.attributes());
    }

    Result instantiateGenericStructImpls(Sema& sema, const SymbolStruct& root, SymbolStruct& instance, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs)
    {
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

    Result evalGenericDefaultArg(Sema& sema, const Symbol& root, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, size_t paramIndex, SemaGeneric::GenericResolvedArg& outArg)
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

    Result resolveGenericValueParamType(Sema& sema, const Symbol& root, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, size_t paramIndex, TypeRef& outTypeRef)
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

    Result finalizeResolvedGenericValue(Sema& sema, const Symbol& root, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs, size_t paramIndex, AstNodeRef errorNodeRef)
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

    Result materializeGenericArgs(Sema& sema, const Symbol& root, std::span<const SemaGeneric::GenericParamDesc> params, std::span<SemaGeneric::GenericResolvedArg> ioResolvedArgs, std::span<const AstNodeRef> genericArgNodes, AstNodeRef fallbackNodeRef)
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

    void buildGenericKeys(std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, SmallVector<GenericInstanceKey>& outKeys)
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

    Symbol* createGenericInstanceSymbol(Sema& sema, Symbol& root, AstNodeRef cloneRef)
    {
        if (auto* function = root.safeCast<SymbolFunction>())
        {
            auto& cloneDecl                = sema.node(cloneRef).cast<AstFunctionDecl>();
            cloneDecl.spanGenericParamsRef = SpanRef::invalid();

            auto* instance         = Symbol::make<SymbolFunction>(sema.ctx(), &cloneDecl, cloneDecl.tokNameRef, function->idRef(), clonedGenericSymbolFlags(root));
            instance->extraFlags() = function->semanticFlags();
            instance->setAttributes(sema.ctx(), function->attributes());
            instance->setRtAttributeFlags(function->rtAttributeFlags());
            instance->setSpecOpKind(function->specOpKind());
            instance->setCallConvKind(function->callConvKind());
            instance->setDeclNodeRef(cloneRef);
            instance->setOwnerSymMap(function->ownerSymMap());
            instance->setGenericInstance(sema.ctx(), function);
            return instance;
        }

        auto& cloneDecl                = sema.node(cloneRef).cast<AstStructDecl>();
        cloneDecl.spanGenericParamsRef = SpanRef::invalid();
        cloneDecl.spanWhereRef         = SpanRef::invalid();

        auto& st               = root.cast<SymbolStruct>();
        auto* instance         = Symbol::make<SymbolStruct>(sema.ctx(), &cloneDecl, cloneDecl.tokNameRef, st.idRef(), clonedGenericSymbolFlags(root));
        instance->extraFlags() = st.extraFlags();
        instance->setAttributes(sema.ctx(), st.attributes());
        instance->setOwnerSymMap(st.ownerSymMap());
        instance->setDeclNodeRef(cloneRef);
        instance->setGenericInstance(&st);
        return instance;
    }

    void setGenericCompletionOwner(Symbol& instance, const TaskContext& ctx)
    {
        if (const auto* function = instance.safeCast<SymbolFunction>())
            function->setGenericCompletionOwner(ctx);
        else
            instance.cast<SymbolStruct>().setGenericCompletionOwner(ctx);
    }

    bool isGenericCompletionOwner(const Symbol& instance, const TaskContext& ctx)
    {
        if (const auto* function = instance.safeCast<SymbolFunction>())
            return function->isGenericCompletionOwner(ctx);
        return instance.cast<SymbolStruct>().isGenericCompletionOwner(ctx);
    }

    bool tryStartGenericCompletion(const Symbol& instance, const TaskContext& ctx)
    {
        if (const auto* function = instance.safeCast<SymbolFunction>())
            return function->tryStartGenericCompletion(ctx);
        return instance.cast<SymbolStruct>().tryStartGenericCompletion(ctx);
    }

    void finishGenericCompletion(const Symbol& instance)
    {
        if (const auto* function = instance.safeCast<SymbolFunction>())
            function->finishGenericCompletion();
        else
            instance.cast<SymbolStruct>().finishGenericCompletion();
    }

    bool isGenericNodeCompleted(const Symbol& instance)
    {
        if (const auto* function = instance.safeCast<SymbolFunction>())
            return function->isGenericNodeCompleted();
        return instance.cast<SymbolStruct>().isGenericNodeCompleted();
    }

    void setGenericNodeCompleted(const Symbol& instance)
    {
        if (const auto* function = instance.safeCast<SymbolFunction>())
            function->setGenericNodeCompleted();
        else
            instance.cast<SymbolStruct>().setGenericNodeCompleted();
    }

    Symbol* findOrCreateGenericInstance(Sema& sema, Symbol& root, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs)
    {
        SmallVector<GenericInstanceKey> keys;
        buildGenericKeys(params, resolvedArgs, keys);

        GenericInstanceStorage& storage = root.isFunction() ? root.cast<SymbolFunction>().genericInstanceStorage(sema.ctx()) : root.cast<SymbolStruct>().genericInstanceStorage();

        std::unique_lock lk(storage.getMutex());
        if (auto* instance = storage.findNoLock(keys.span()))
            return instance;

        SmallVector<SemaClone::ParamBinding> bindings;
        buildGenericCloneBindings(params, resolvedArgs, bindings);
        appendEnclosingGenericCloneBindings(sema, root, bindings);

        const SemaClone::CloneContext cloneContext{bindings};
        const AstNodeRef              cloneRef = SemaClone::cloneAst(sema, genericDeclNodeRef(root), cloneContext);
        Symbol*                       created  = createGenericInstanceSymbol(sema, root, cloneRef);
        setGenericCompletionOwner(*created, sema.ctx());
        sema.setSymbol(cloneRef, created);
        return storage.addNoLock(keys.span(), created);
    }

    Result finalizeGenericInstance(Sema& sema, const Symbol& root, Symbol& instance, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs)
    {
        if (!instance.isStruct())
            return Result::Continue;

        // Generic instances must observe the same impl-registration barrier as regular structs.
        // Otherwise the creator job can snapshot an incomplete root impl list and complete the
        // instance before later `impl` jobs have attached everything to the generic root.
        if (sema.compiler().pendingImplRegistrations() != 0)
            return sema.waitImplRegistrations(root.idRef(), root.codeRef());

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

    Result createGenericInstance(Sema& sema, Symbol& root, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, Symbol*& outInstance, AstNodeRef errorNodeRef = AstNodeRef::invalid())
    {
        outInstance = findOrCreateGenericInstance(sema, root, params, resolvedArgs);
        if (!outInstance->isSemaCompleted())
        {
            if (!isGenericCompletionOwner(*outInstance, sema.ctx()))
                return sema.waitSemaCompleted(outInstance, SourceCodeRef::invalid());

            if (outInstance->isIgnored())
                return Result::Error;

            // The creator job keeps ownership across pauses, but nested requests for the same
            // instance inside that job must still bail out to avoid recursing on in-flight work.
            if (!tryStartGenericCompletion(*outInstance, sema.ctx()))
                return Result::Continue;

            auto result = Result::Continue;
            if (!isGenericNodeCompleted(*outInstance))
            {
                if (root.isStruct())
                    result = validateGenericStructWhereConstraints(sema, root.cast<SymbolStruct>(), params, resolvedArgs, errorNodeRef);
                if (result == Result::Continue)
                    result = runGenericNode(sema, root, genericDeclNodeRef(*outInstance));
                if (result == Result::Continue)
                    setGenericNodeCompleted(*outInstance);
            }

            if (result == Result::Continue)
                result = finalizeGenericInstance(sema, root, *outInstance, params, resolvedArgs);
            finishGenericCompletion(*outInstance);
            if (result != Result::Continue)
            {
                if (result == Result::Error && !outInstance->isIgnored() && !outInstance->isSemaCompleted())
                    outInstance->setIgnored(sema.ctx());
                return result;
            }

            if (outInstance->isIgnored())
                return Result::Error;
        }

        return Result::Continue;
    }

    void setGenericParamNotDeducedFailure(Sema& sema, const SemaGeneric::GenericParamDesc& param, CastFailure& outFailure)
    {
        outFailure        = {};
        outFailure.diagId = DiagnosticId::sema_err_generic_parameter_not_deduced;
        outFailure.addArgument(Diagnostic::ARG_VALUE, Utf8{sema.idMgr().get(param.idRef).name});
    }

    Result instantiateGenericExplicit(Sema& sema, Symbol& genericRoot, std::span<const AstNodeRef> genericArgNodes, Symbol*& outInstance)
    {
        outInstance = nullptr;
        if (!hasGenericParams(genericRoot))
            return Result::Continue;

        const SpanRef spanRef = genericParamSpan(genericRoot);
        if (!spanRef.isValid())
            return Result::Continue;

        SmallVector<SemaGeneric::GenericParamDesc> params;
        SemaGeneric::collectGenericParams(sema, spanRef, params);
        if (genericArgNodes.size() > params.size())
            return Result::Continue;

        SmallVector<SemaGeneric::GenericResolvedArg> resolvedArgs(params.size());
        for (size_t i = 0; i < genericArgNodes.size(); ++i)
            SWC_RESULT(SemaGeneric::resolveExplicitGenericArg(sema, params[i], genericArgNodes[i], resolvedArgs[i]));

        SWC_RESULT(materializeGenericArgs(sema, genericRoot, params.span(), resolvedArgs.span(), genericArgNodes, sema.curNodeRef()));
        if (SemaGeneric::hasMissingGenericArgs(resolvedArgs.span()))
            return Result::Continue;

        return createGenericInstance(sema, genericRoot, params.span(), resolvedArgs.span(), outInstance, sema.curNodeRef());
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

    Result instantiateFunctionFromCall(Sema& sema, SymbolFunction& genericRoot, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SymbolFunction*& outInstance, CastFailure* outFailure, uint32_t* outFailureArgIndex)
    {
        outInstance = nullptr;
        if (outFailure)
            *outFailure = {};
        if (outFailureArgIndex)
            *outFailureArgIndex = UINT32_MAX;
        if (!hasGenericParams(genericRoot))
            return Result::Continue;

        const auto* decl = genericFunctionDecl(genericRoot);
        if (!decl)
            return Result::Continue;

        SmallVector<GenericParamDesc> params;
        collectGenericParams(sema, decl->spanGenericParamsRef, params);
        if (params.empty())
            return Result::Continue;

        SmallVector<GenericResolvedArg> resolvedArgs(params.size());
        SWC_RESULT(deduceGenericFunctionArgs(sema, genericRoot, params.span(), resolvedArgs, args, ufcsArg, outFailure, outFailureArgIndex));
        if (outFailure && outFailure->diagId != DiagnosticId::None)
            return Result::Continue;

        SWC_RESULT(materializeGenericArgs(sema, genericRoot, params.span(), resolvedArgs.span(), std::span<const AstNodeRef>{}, sema.curNodeRef()));
        if (hasMissingGenericArgs(resolvedArgs.span()))
        {
            if (outFailure)
            {
                for (size_t i = 0; i < resolvedArgs.size(); ++i)
                {
                    if (!resolvedArgs[i].present)
                    {
                        setGenericParamNotDeducedFailure(sema, params[i], *outFailure);
                        break;
                    }
                }
            }
            return Result::Continue;
        }

        Symbol* instance = nullptr;
        SWC_RESULT(createGenericInstance(sema, genericRoot, params.span(), resolvedArgs.span(), instance, sema.curNodeRef()));
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

    Result instantiateStructFromContext(Sema& sema, SymbolStruct& genericRoot, SymbolStruct*& outInstance)
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

        SmallVector<GenericParamDesc> enclosingParams;
        collectGenericParams(sema, enclosingDecl->spanGenericParamsRef, enclosingParams);

        SmallVector<GenericInstanceKey> enclosingArgs;
        if (!enclosingRoot->tryGetGenericInstanceArgs(*enclosingInstance, enclosingArgs))
            return Result::Continue;
        if (enclosingArgs.size() != enclosingParams.size())
            return Result::Continue;

        // Collect target struct's generic params
        const auto* targetDecl = genericStructDecl(genericRoot);
        if (!targetDecl)
            return Result::Continue;

        SmallVector<GenericParamDesc> targetParams;
        collectGenericParams(sema, targetDecl->spanGenericParamsRef, targetParams);

        // If the current function has generic type params that conflict with target params, skip deduction
        if (const auto* func = sema.currentFunction())
        {
            const auto* funcDecl = func->decl() ? func->decl()->safeCast<AstFunctionDecl>() : nullptr;
            if (funcDecl && funcDecl->spanGenericParamsRef.isValid())
            {
                SmallVector<GenericParamDesc> funcParams;
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
        SmallVector<GenericResolvedArg> resolvedArgs(targetParams.size());
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
        SWC_RESULT(materializeGenericArgs(sema, genericRoot, targetParams.span(), resolvedArgs.span(), std::span<const AstNodeRef>{}, sema.curNodeRef()));
        if (hasMissingGenericArgs(resolvedArgs.span()))
            return Result::Continue;

        Symbol* instance = nullptr;
        SWC_RESULT(createGenericInstance(sema, genericRoot, targetParams.span(), resolvedArgs.span(), instance, sema.curNodeRef()));
        outInstance = instance ? &instance->cast<SymbolStruct>() : nullptr;
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
