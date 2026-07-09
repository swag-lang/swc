#include "pch.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Cast/CastFailure.h"
#include "Compiler/Sema/Cast/CastRequest.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace SemaGeneric
{
    namespace
    {
        using Internal::buildFunctionWhereInputs;
        using Internal::buildPartialGenericContextBindings;
        using Internal::buildResolvedGenericContextBindings;
        using Internal::checkFunctionWhereConstraints;
        using Internal::collectAmbientGenericFunctions;
        using Internal::evalGenericClonedNode;
        using Internal::FunctionWhereInputs;
        using Internal::genericDeclNodeRef;
        using Internal::GenericEvalReadyKind;
        using Internal::genericFunctionDecl;
        using Internal::genericStructDeclNode;
        using Internal::genericStructParamSpan;
        using Internal::instantiateGenericStructImpls;
        using Internal::loadFunctionInstanceGenericArgs;
        using Internal::loadOwnerStructGenericArgs;
        using Internal::loadStructInstanceGenericArgs;
        using Internal::ResolvedGenericBindingSource;
        using Internal::runGenericInstanceNode;
        using Internal::tryCreateSemaForGenericDecl;
        using Internal::validateGenericStructWhereConstraints;

        SpanRef genericParamSpan(const Symbol& root)
        {
            SWC_ASSERT(root.isFunction() || root.isStruct());
            if (const auto* function = root.safeCast<SymbolFunction>())
            {
                const auto* decl = genericFunctionDecl(*function);
                return decl ? decl->spanGenericParamsRef : SpanRef::invalid();
            }

            return genericStructParamSpan(root.cast<SymbolStruct>());
        }

        bool hasGenericParams(const Symbol& root)
        {
            if (const auto* function = root.safeCast<SymbolFunction>())
            {
                const auto* decl = genericFunctionDecl(*function);
                return !function->isGenericInstance() && decl && decl->spanGenericParamsRef.isValid();
            }

            const auto& st = root.cast<SymbolStruct>();
            return !st.isGenericInstance() && genericStructParamSpan(st).isValid();
        }

        void resolveStructArgsFromContext(Sema& sema, const SymbolStruct& genericRoot, std::span<const GenericParamDesc> targetParams, std::span<GenericResolvedArg> resolvedArgs);

        Result evalGenericDefaultArg(Sema& sema, const Symbol& root, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, size_t paramIndex, GenericResolvedArg& outArg)
        {
            outArg                        = {};
            const GenericParamDesc& param = params[paramIndex];
            if (param.defaultRef.isInvalid())
                return Result::Continue;

            // Defaults can depend only on parameters declared before them. Clone the
            // default expression with the prefix bindings resolved so later params do
            // not accidentally participate in evaluation.
            const ResolvedGenericBindingSource   source{params, resolvedArgs};
            SmallVector<SemaClone::ParamBinding> bindings;
            buildPartialGenericContextBindings(sema, root, source, paramIndex, bindings);

            AstNodeRef clonedRef = AstNodeRef::invalid();
            SWC_RESULT(evalGenericClonedNode(sema, root, param.defaultRef, bindings, GenericEvalReadyKind::Constant, clonedRef));
            if (clonedRef.isInvalid())
                return Result::Error;

            return resolveExplicitGenericArg(sema, param, clonedRef, outArg);
        }

        Result resolveGenericValueParamType(Sema& sema, const Symbol& root, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, size_t paramIndex, TypeRef& outTypeRef)
        {
            outTypeRef                    = TypeRef::invalid();
            const GenericParamDesc& param = params[paramIndex];
            if (param.explicitType.isInvalid())
                return Result::Continue;

            // A value generic's declared type may itself mention earlier generic
            // params. Evaluate it through the same partial binding context as a
            // default value, then read the stored semantic payload from the clone.
            const ResolvedGenericBindingSource   source{params, resolvedArgs};
            SmallVector<SemaClone::ParamBinding> bindings;
            buildPartialGenericContextBindings(sema, root, source, paramIndex, bindings);

            AstNodeRef clonedTypeRef = AstNodeRef::invalid();
            SWC_RESULT(evalGenericClonedNode(sema, root, param.explicitType, bindings, GenericEvalReadyKind::TypeOrSymbol, clonedTypeRef));
            if (clonedTypeRef.isInvalid())
                return Result::Error;

            const SemaNodeView storedTypeView = sema.viewStored(clonedTypeRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
            outTypeRef                        = storedTypeView.typeRef();
            if (!outTypeRef.isValid() && storedTypeView.hasSymbol() && storedTypeView.sym() && storedTypeView.sym()->isType())
                outTypeRef = storedTypeView.sym()->typeRef();

            if (!outTypeRef.isValid())
            {
                const AstNode& typeNode = sema.node(clonedTypeRef);
                if (const auto* namedType = typeNode.safeCast<AstNamedType>())
                {
                    const SemaNodeView identView = sema.viewStored(namedType->nodeIdentRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
                    outTypeRef                   = identView.typeRef();
                    if (!outTypeRef.isValid() && identView.hasSymbol() && identView.sym() && identView.sym()->isType())
                        outTypeRef = identView.sym()->typeRef();
                }
            }

            return Result::Continue;
        }

        Result finalizeResolvedGenericValue(Sema& sema, const Symbol& root, std::span<const GenericParamDesc> params, std::span<GenericResolvedArg> resolvedArgs, size_t paramIndex, AstNodeRef errorNodeRef)
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
                    // Value generic arguments are constants, but the instance key
                    // must store them in the declared type. Reuse normal implicit
                    // cast rules so diagnostics match a value expression context.
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

        Result finalizeResolvedGenericType(Sema& sema, GenericResolvedArg& ioArg)
        {
            if (!ioArg.typeRef.isValid())
                return Result::Continue;

            // Unsized float generic type arguments default to f64, unless the
            // diagnostic/value node carries a concrete constant that can dictate a
            // narrower precise type.
            const TypeInfo& typeInfo = sema.typeMgr().get(ioArg.typeRef);
            if (!typeInfo.isFloatUnsized())
                return Result::Continue;

            TypeRef concreteTypeRef = sema.typeMgr().typeF64();
            if (ioArg.diagRef.isValid())
            {
                const SemaNodeView diagView = sema.viewNodeTypeConstant(ioArg.diagRef);
                if (diagView.cstRef().isValid())
                {
                    ConstantRef newCstRef = ConstantRef::invalid();
                    SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, ioArg.diagRef, diagView.cstRef(), TypeInfo::Sign::Unknown));
                    if (newCstRef.isValid())
                    {
                        sema.setConstant(ioArg.diagRef, newCstRef);
                        concreteTypeRef = sema.cstMgr().get(newCstRef).typeRef();
                    }
                }
            }

            ioArg.typeRef = concreteTypeRef;
            return Result::Continue;
        }

        Result materializeGenericArgs(Sema& sema, const Symbol& root, std::span<const GenericParamDesc> params, std::span<GenericResolvedArg> ioResolvedArgs, std::span<const AstNodeRef> genericArgNodes, AstNodeRef fallbackNodeRef)
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
                if (params[i].kind == GenericParamKind::Type)
                    SWC_RESULT(finalizeResolvedGenericType(sema, ioResolvedArgs[i]));
                else
                    SWC_RESULT(finalizeResolvedGenericValue(sema, root, params, ioResolvedArgs, i, genericErrorNodeRef(genericArgNodes, i, fallbackNodeRef)));
            }

            return Result::Continue;
        }

        void buildGenericKeys(std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, SmallVector<GenericInstanceKey>& outKeys)
        {
            outKeys.clear();
            outKeys.reserve(params.size());
            // Instance identity is exactly the ordered list of declared generic
            // parameters. Type params and value params occupy the same slot index but
            // carry different payload kinds in GenericInstanceKey.
            for (size_t i = 0; i < params.size(); ++i)
            {
                GenericInstanceKey key;
                if (params[i].kind == GenericParamKind::Type)
                    key.typeRef = resolvedArgs[i].typeRef;
                else
                    key.cstRef = resolvedArgs[i].cstRef;
                outKeys.push_back(key);
            }
        }

        void appendOwnerStructGenericKeys(Sema& sema, const SymbolFunction& function, SmallVector<GenericInstanceKey>& outKeys)
        {
            SmallVector<GenericParamDesc>   ownerParams;
            SmallVector<GenericInstanceKey> ownerArgs;
            if (!loadOwnerStructGenericArgs(sema, function, ownerParams, ownerArgs))
                return;

            for (const GenericInstanceKey& arg : ownerArgs)
                outKeys.push_back(arg);
        }

        SymbolFlags clonedGenericSymbolFlags(const Symbol& root)
        {
            SymbolFlags flags = SymbolFlagsE::Zero;
            if (root.isPublic())
                flags.add(SymbolFlagsE::Public);
            return flags;
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
                instance->setDeclNodePayloadContext(&sema.currentNodePayloadContext());
                instance->setOwnerSymMap(function->ownerSymMap());
                instance->setGenericInstance(sema.ctx(), function);
                return instance;
            }

            auto& st = root.cast<SymbolStruct>();
            if (auto* cloneDecl = sema.node(cloneRef).safeCast<AstStructDecl>())
            {
                cloneDecl->spanGenericParamsRef = SpanRef::invalid();
                cloneDecl->spanWhereRef         = SpanRef::invalid();

                auto* instance         = Symbol::make<SymbolStruct>(sema.ctx(), cloneDecl, cloneDecl->tokNameRef, st.idRef(), clonedGenericSymbolFlags(root));
                instance->extraFlags() = st.extraFlags();
                instance->setAttributes(sema.ctx(), st.attributes());
                instance->setOwnerSymMap(st.ownerSymMap());
                instance->setDeclNodeRef(cloneRef);
                instance->setGenericInstance(&st);
                return instance;
            }

            auto& cloneDecl                = sema.node(cloneRef).cast<AstUnionDecl>();
            cloneDecl.spanGenericParamsRef = SpanRef::invalid();
            cloneDecl.spanWhereRef         = SpanRef::invalid();

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

        Symbol* findOrCreateGenericInstance(Sema& sema, Symbol& root, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs)
        {
            SmallVector<GenericInstanceKey> keys;
            buildGenericKeys(params, resolvedArgs, keys);
            if (const auto* function = root.safeCast<SymbolFunction>())
                appendOwnerStructGenericKeys(sema, *function, keys);

            GenericInstanceStorage& storage = root.isFunction() ? root.cast<SymbolFunction>().genericInstanceStorage(sema.ctx()) : root.cast<SymbolStruct>().genericInstanceStorage();
            if (auto* instance = storage.find(keys.span()))
                return instance;

            std::unique_lock lk(storage.getMutex());
            if (auto* instance = storage.findNoLock(keys.span()))
                return instance;

            const ResolvedGenericBindingSource   source{params, resolvedArgs};
            SmallVector<SemaClone::ParamBinding> bindings;
            buildResolvedGenericContextBindings(sema, root, source, bindings);

            const SemaClone::CloneContext cloneContext{bindings};
            const AstNodeRef              cloneRef = SemaClone::cloneAst(sema, genericDeclNodeRef(root), cloneContext);
            Symbol*                       created  = createGenericInstanceSymbol(sema, root, cloneRef);
            setGenericCompletionOwner(*created, sema.ctx());
            sema.setSymbol(cloneRef, created);
            return storage.addNoLock(keys.span(), created);
        }

        Result finalizeGenericInstance(Sema& sema, const Symbol& root, Symbol& instance, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs)
        {
            if (!instance.isStruct())
                return Result::Continue;

            if (sema.compiler().pendingImplRegistrations(root.idRef()) != 0)
                return sema.waitImplRegistrations(root.idRef(), root.codeRef());

            auto& rootStruct     = const_cast<SymbolStruct&>(root.cast<SymbolStruct>());
            auto& instanceStruct = instance.cast<SymbolStruct>();
            SWC_RESULT(sema.waitSemaCompleted(&rootStruct, rootStruct.codeRef()));
            SWC_RESULT(SemaSpecOp::ensureGeneratedOperators(sema, rootStruct));
            SWC_RESULT(instantiateGenericStructImpls(sema, rootStruct, instanceStruct, params, resolvedArgs));
            instanceStruct.removeIgnoredFields();
            SWC_RESULT(instanceStruct.canBeCompleted(sema));
            SWC_RESULT(instanceStruct.computeLayout(sema.ctx()));
            SWC_RESULT(SemaSpecOp::ensureGeneratedLifecycleFunctions(sema, instanceStruct));
            SWC_RESULT(instanceStruct.registerSpecOps(sema));
            instanceStruct.setSemaCompleted(sema.ctx());
            return Result::Continue;
        }

        Result createGenericInstance(Sema& sema, Symbol& root, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, Symbol*& outInstance, AstNodeRef errorNodeRef = AstNodeRef::invalid())
        {
            outInstance = findOrCreateGenericInstance(sema, root, params, resolvedArgs);
            if (!outInstance->isSemaCompleted())
            {
                if (!isGenericCompletionOwner(*outInstance, sema.ctx()))
                    return sema.waitSemaCompleted(outInstance, SourceCodeRef::invalid());

                if (outInstance->isIgnored())
                    return Result::Error;

                if (!tryStartGenericCompletion(*outInstance, sema.ctx()))
                    return Result::Continue;

                auto result = Result::Continue;
                if (!isGenericNodeCompleted(*outInstance))
                {
                    if (root.isStruct())
                        result = validateGenericStructWhereConstraints(sema, root.cast<SymbolStruct>(), params, resolvedArgs, errorNodeRef);
                    if (result == Result::Continue)
                        result = runGenericInstanceNode(sema, root, *outInstance);
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

        void setGenericParamNotDeducedFailure(Sema& sema, const GenericParamDesc& param, CastFailure& outFailure)
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

            std::unique_ptr<Sema> sourceSemaHolder;
            Sema*                 sourceSema = tryCreateSemaForGenericDecl(sema, genericRoot, sourceSemaHolder);
            if (!sourceSema)
                sourceSema = &sema;

            SmallVector<GenericParamDesc> params;
            if (genericRoot.decl())
                collectGenericParams(*sourceSema, *genericRoot.decl(), spanRef, params);
            else
                collectGenericParams(*sourceSema, spanRef, params);
            if (genericArgNodes.size() > params.size())
                return Result::Continue;

            const AstNodeRef                errorNodeRef = genericArgNodes.empty() ? sema.curNodeRef() : genericArgNodes.front();
            SmallVector<GenericResolvedArg> resolvedArgs(params.size());
            for (size_t i = 0; i < genericArgNodes.size(); ++i)
                SWC_RESULT(SemaGeneric::resolveExplicitGenericArg(sema, params[i], genericArgNodes[i], resolvedArgs[i]));
            const ResolvedGenericBindingSource source{params.span(), resolvedArgs.span()};

            if (const auto* genericStruct = genericRoot.safeCast<SymbolStruct>())
            {
                if (hasMissingGenericArgs(resolvedArgs.span()))
                    resolveStructArgsFromContext(sema, *genericStruct, params.span(), resolvedArgs.span());
            }

            SWC_RESULT(materializeGenericArgs(*sourceSema, genericRoot, params.span(), resolvedArgs.span(), genericArgNodes, errorNodeRef));
            if (hasMissingGenericArgs(resolvedArgs.span()))
                return Result::Continue;

            if (const auto* function = genericRoot.safeCast<SymbolFunction>())
            {
                FunctionWhereInputs whereInputs;
                buildFunctionWhereInputs(*sourceSema, *function, source, whereInputs);
                bool satisfied = true;
                SWC_RESULT(checkFunctionWhereConstraints(*sourceSema, satisfied, *function, whereInputs.bindings.span(), whereInputs.bindingText, nullptr, errorNodeRef));
                if (!satisfied)
                    return Result::Error;
            }

            return createGenericInstance(*sourceSema, genericRoot, params.span(), resolvedArgs.span(), outInstance, errorNodeRef);
        }

        void resolveArgsFromGenericContext(std::span<const GenericParamDesc> contextParams, std::span<const GenericInstanceKey> contextArgs, std::span<const GenericParamDesc> targetParams, std::span<GenericResolvedArg> resolvedArgs, bool allowKindFallback)
        {
            if (contextParams.size() != contextArgs.size())
                return;

            SmallVector usedContextParams(contextParams.size(), false);
            for (size_t targetIndex = 0; targetIndex < targetParams.size(); ++targetIndex)
            {
                if (resolvedArgs[targetIndex].present)
                    continue;

                if (targetParams[targetIndex].defaultRef.isValid())
                    continue;

                for (size_t contextIndex = 0; contextIndex < contextParams.size(); ++contextIndex)
                {
                    if (targetParams[targetIndex].idRef != contextParams[contextIndex].idRef ||
                        targetParams[targetIndex].kind != contextParams[contextIndex].kind)
                        continue;

                    resolvedArgs[targetIndex].present = true;
                    resolvedArgs[targetIndex].typeRef = contextArgs[contextIndex].typeRef;
                    resolvedArgs[targetIndex].cstRef  = contextArgs[contextIndex].cstRef;
                    usedContextParams[contextIndex]   = true;
                    break;
                }
            }

            if (!allowKindFallback)
                return;

            for (size_t targetIndex = 0; targetIndex < targetParams.size(); ++targetIndex)
            {
                if (!resolvedArgs[targetIndex].present)
                    continue;

                for (size_t contextIndex = 0; contextIndex < contextParams.size(); ++contextIndex)
                {
                    if (usedContextParams[contextIndex])
                        continue;

                    if (targetParams[targetIndex].kind != contextParams[contextIndex].kind)
                        continue;

                    const bool sameType = resolvedArgs[targetIndex].typeRef == contextArgs[contextIndex].typeRef;
                    const bool sameCst  = resolvedArgs[targetIndex].cstRef == contextArgs[contextIndex].cstRef;
                    if (!sameType || !sameCst)
                        continue;

                    usedContextParams[contextIndex] = true;
                    break;
                }
            }

            for (size_t targetIndex = 0; targetIndex < targetParams.size(); ++targetIndex)
            {
                if (resolvedArgs[targetIndex].present)
                    continue;

                if (targetParams[targetIndex].defaultRef.isValid())
                    continue;

                size_t contextIndex = 0;
                while (contextIndex < contextParams.size())
                {
                    if (!usedContextParams[contextIndex] && targetParams[targetIndex].kind == contextParams[contextIndex].kind)
                        break;
                    ++contextIndex;
                }
                if (contextIndex == contextParams.size())
                    continue;

                resolvedArgs[targetIndex].present = true;
                resolvedArgs[targetIndex].typeRef = contextArgs[contextIndex].typeRef;
                resolvedArgs[targetIndex].cstRef  = contextArgs[contextIndex].cstRef;
                usedContextParams[contextIndex]   = true;
            }
        }

        const SymbolStruct* genericStructInstanceFromImplFrames(const Sema& sema)
        {
            for (size_t i = sema.frames().size(); i > 0; --i)
            {
                const auto* impl = sema.frames()[i - 1].currentImpl();
                if (!impl || !impl->isForStruct())
                    continue;

                const auto* st = impl->symStruct();
                if (st && st->isGenericInstance())
                    return st;
            }

            return nullptr;
        }

        const SymbolStruct* genericStructInstanceFromScopes(Sema& sema)
        {
            for (const SemaScope* scope = sema.curScopePtr(); scope; scope = scope->parent())
            {
                const auto* symMap = scope->symMap();
                if (!symMap || !symMap->isStruct())
                    continue;

                const auto& st = symMap->cast<SymbolStruct>();
                if (st.isGenericInstance())
                    return &st;
            }

            return nullptr;
        }

        const SymbolStruct* matchingGenericStructInstance(const SymbolStruct& genericRoot, const SymbolStruct* instance)
        {
            if (!instance || !instance->isGenericInstance())
                return nullptr;

            return instance->sameGenericFamily(genericRoot) ? instance : nullptr;
        }

        const SymbolStruct* genericStructInstanceFromFunctionOwner(const SymbolStruct& genericRoot, const SymbolFunction* function)
        {
            if (!function)
                return nullptr;

            return matchingGenericStructInstance(genericRoot, function->ownerStruct());
        }

        const SymbolStruct* genericStructInstanceFromInlinePayload(const Sema& sema, const SymbolStruct& genericRoot)
        {
            for (size_t i = sema.frames().size(); i > 0; --i)
            {
                const SemaInlinePayload* inlinePayload = sema.frames()[i - 1].currentInlinePayload();
                while (inlinePayload)
                {
                    if (const SymbolStruct* instance = genericStructInstanceFromFunctionOwner(genericRoot, inlinePayload->sourceFunction))
                        return instance;

                    inlinePayload = inlinePayload->parentInlinePayload;
                }
            }

            return nullptr;
        }

        const SymbolStruct* genericStructInstanceFromCurrentFunction(const Sema& sema, const SymbolStruct& genericRoot)
        {
            return genericStructInstanceFromFunctionOwner(genericRoot, sema.currentFunction());
        }

        const SymbolStruct* enclosingGenericStructInstance(Sema& sema)
        {
            if (const SymbolStruct* instance = genericStructInstanceFromImplFrames(sema))
                return instance;
            return genericStructInstanceFromScopes(sema);
        }

        void resolveArgsFromFunction(Sema& sema, const SymbolFunction& function, std::span<const GenericParamDesc> targetParams, std::span<GenericResolvedArg> resolvedArgs, bool allowKindFallback)
        {
            SmallVector<GenericParamDesc>   functionParams;
            SmallVector<GenericInstanceKey> functionArgs;
            if (!loadFunctionInstanceGenericArgs(sema, function, functionParams, functionArgs))
                return;

            resolveArgsFromGenericContext(functionParams.span(), functionArgs.span(), targetParams, resolvedArgs, allowKindFallback);
        }

        void resolveArgsFromAmbientFunctions(Sema& sema, std::span<const GenericParamDesc> targetParams, std::span<GenericResolvedArg> resolvedArgs, bool allowKindFallback)
        {
            SmallVector<const SymbolFunction*> functions;
            collectAmbientGenericFunctions(sema, functions);
            for (const SymbolFunction* function : functions)
            {
                if (!hasMissingGenericArgs(resolvedArgs))
                    return;

                resolveArgsFromFunction(sema, *function, targetParams, resolvedArgs, allowKindFallback);
            }
        }

        void resolveArgsFromEnclosingStruct(Sema& sema, const SymbolStruct& enclosingInstance, std::span<const GenericParamDesc> targetParams, std::span<GenericResolvedArg> resolvedArgs)
        {
            SmallVector<GenericParamDesc>   enclosingParams;
            SmallVector<GenericInstanceKey> enclosingArgs;
            if (!loadStructInstanceGenericArgs(sema, enclosingInstance, enclosingParams, enclosingArgs))
                return;

            resolveArgsFromGenericContext(enclosingParams.span(), enclosingArgs.span(), targetParams, resolvedArgs, true);
        }

        void resolveStructArgsFromContext(Sema& sema, const SymbolStruct& genericRoot, std::span<const GenericParamDesc> targetParams, std::span<GenericResolvedArg> resolvedArgs)
        {
            const SymbolStruct* sourceInstance = genericStructInstanceFromInlinePayload(sema, genericRoot);
            if (sourceInstance)
                resolveArgsFromEnclosingStruct(sema, *sourceInstance, targetParams, resolvedArgs);

            const SymbolStruct* currentFunctionInstance = genericStructInstanceFromCurrentFunction(sema, genericRoot);
            const SymbolStruct* enclosingInstance       = enclosingGenericStructInstance(sema);
            if (hasMissingGenericArgs(resolvedArgs))
            {
                const bool allowKindFallback = !sourceInstance && !currentFunctionInstance && !enclosingInstance;
                resolveArgsFromAmbientFunctions(sema, targetParams, resolvedArgs, allowKindFallback);
            }

            if (hasMissingGenericArgs(resolvedArgs) && currentFunctionInstance)
                resolveArgsFromEnclosingStruct(sema, *currentFunctionInstance, targetParams, resolvedArgs);

            if (hasMissingGenericArgs(resolvedArgs) && enclosingInstance)
                resolveArgsFromEnclosingStruct(sema, *enclosingInstance, targetParams, resolvedArgs);
        }
    }
}

namespace SemaGeneric
{
    Result evalGenericFunctionParamDefault(Sema& sema, const SymbolFunction& root, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, AstNodeRef defaultRef, AstNodeRef& outClonedRef)
    {
        outClonedRef = AstNodeRef::invalid();
        if (defaultRef.isInvalid())
            return Result::Continue;

        const ResolvedGenericBindingSource   source{params, resolvedArgs};
        SmallVector<SemaClone::ParamBinding> bindings;
        buildPartialGenericContextBindings(sema, root, source, params.size(), bindings);

        return evalGenericClonedNode(sema, root, defaultRef, bindings, GenericEvalReadyKind::Constant, outClonedRef);
    }

    Result instantiateFunctionExplicit(Sema& sema, SymbolFunction& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolFunction*& outInstance)
    {
        Symbol* instance = nullptr;
        SWC_RESULT(instantiateGenericExplicit(sema, genericRoot, genericArgNodes, instance));
        outInstance = instance ? &instance->cast<SymbolFunction>() : nullptr;
        return Result::Continue;
    }

    Result instantiateFunctionFromCall(Sema& sema, SymbolFunction& genericRoot, std::span<AstNodeRef> args, AstNodeRef ufcsArg, std::span<const AstNodeRef> explicitGenericArgNodes, SymbolFunction*& outInstance, CastFailure* outFailure, uint32_t* outFailureArgIndex)
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

        std::unique_ptr<Sema> sourceSemaHolder;
        Sema*                 sourceSema = tryCreateSemaForGenericDecl(sema, genericRoot, sourceSemaHolder);
        if (!sourceSema)
            sourceSema = &sema;

        SmallVector<GenericParamDesc> params;
        collectGenericParams(*sourceSema, *decl, decl->spanGenericParamsRef, params);
        if (params.empty())
            return Result::Continue;
        if (explicitGenericArgNodes.size() > params.size())
            return Result::Continue;

        const AstNodeRef                errorNodeRef = sema.curNodeRef();
        SmallVector<GenericResolvedArg> resolvedArgs(params.size());
        for (size_t i = 0; i < explicitGenericArgNodes.size(); ++i)
            SWC_RESULT(resolveExplicitGenericArg(sema, params[i], explicitGenericArgNodes[i], resolvedArgs[i]));
        SWC_RESULT(deduceGenericFunctionArgs(sema, genericRoot, params.span(), resolvedArgs, args, ufcsArg, outFailure, outFailureArgIndex));
        if (outFailure && outFailure->diagId != DiagnosticId::None)
            return Result::Continue;
        if (hasMissingGenericArgs(resolvedArgs.span()))
            resolveArgsFromAmbientFunctions(sema, params.span(), resolvedArgs.span(), false);

        SWC_RESULT(materializeGenericArgs(*sourceSema, genericRoot, params.span(), resolvedArgs.span(), {}, errorNodeRef));
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

        const ResolvedGenericBindingSource source{params.span(), resolvedArgs.span()};
        bool                               whereSatisfied = true;
        if (outFailure)
            *outFailure = {};
        FunctionWhereInputs whereInputs;
        buildFunctionWhereInputs(*sourceSema, genericRoot, source, whereInputs);
        CastFailure  localFailure;
        CastFailure* whereFailure = outFailure ? outFailure : &localFailure;
        SWC_RESULT(Internal::checkFunctionWhereConstraints(*sourceSema, whereSatisfied, genericRoot, whereInputs.bindings.span(), whereInputs.bindingText, whereFailure, errorNodeRef));
        if (!whereSatisfied)
            return Result::Continue;

        Symbol* instance = nullptr;
        SWC_RESULT(createGenericInstance(*sourceSema, genericRoot, params.span(), resolvedArgs.span(), instance, errorNodeRef));
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

        std::unique_ptr<Sema> targetSemaHolder;
        Sema*                 targetSema = tryCreateSemaForGenericDecl(sema, genericRoot, targetSemaHolder);
        if (!targetSema)
            targetSema = &sema;

        if (!hasGenericParams(genericRoot))
            return Result::Continue;

        const auto*   targetDecl           = genericStructDeclNode(genericRoot);
        const SpanRef spanGenericParamsRef = genericStructParamSpan(genericRoot);
        if (!targetDecl || spanGenericParamsRef.isInvalid())
            return Result::Continue;

        SmallVector<GenericParamDesc> targetParams;
        collectGenericParams(*targetSema, *targetDecl, spanGenericParamsRef, targetParams);

        SmallVector<GenericResolvedArg> resolvedArgs(targetParams.size());
        resolveStructArgsFromContext(sema, genericRoot, targetParams.span(), resolvedArgs.span());

        SWC_RESULT(materializeGenericArgs(*targetSema, genericRoot, targetParams.span(), resolvedArgs.span(), {}, genericDeclNodeRef(genericRoot)));
        if (hasMissingGenericArgs(resolvedArgs.span()))
            return Result::Continue;

        Symbol* instance = nullptr;
        SWC_RESULT(createGenericInstance(*targetSema, genericRoot, targetParams.span(), resolvedArgs.span(), instance, genericDeclNodeRef(genericRoot)));
        outInstance = instance ? &instance->cast<SymbolStruct>() : nullptr;
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
