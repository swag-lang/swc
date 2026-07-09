#include "pch.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Cast/CastRequest.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const SymbolFunction* genericFunctionInstanceOrNull(const SymbolFunction* function)
    {
        if (!function || !function->isGenericInstance())
            return nullptr;
        return function;
    }
}

namespace SemaGeneric
{
    namespace Internal
    {
        const AstFunctionDecl* genericFunctionDecl(const SymbolFunction& root)
        {
            return root.decl() ? root.decl()->safeCast<AstFunctionDecl>() : nullptr;
        }

        const AstNode* genericStructDeclNode(const SymbolStruct& root)
        {
            if (!root.decl())
                return nullptr;

            const AstNode* decl = root.decl();
            if (decl->is(AstNodeId::StructDecl) || decl->is(AstNodeId::UnionDecl))
                return decl;
            return nullptr;
        }

        SpanRef genericStructParamSpan(const SymbolStruct& root)
        {
            const AstNode* decl = genericStructDeclNode(root);
            if (!decl)
                return SpanRef::invalid();

            if (const auto* structDecl = decl->safeCast<AstStructDecl>())
                return structDecl->spanGenericParamsRef;
            return decl->cast<AstUnionDecl>().spanGenericParamsRef;
        }

        AstNodeRef genericDeclNodeRef(const Symbol& root)
        {
            if (const auto* function = root.safeCast<SymbolFunction>())
                return function->declNodeRef();
            return root.cast<SymbolStruct>().declNodeRef();
        }

        bool loadStructInstanceGenericArgs(Sema& sema, const SymbolStruct& instance, SmallVector<GenericParamDesc>& outParams, SmallVector<GenericInstanceKey>& outArgs)
        {
            if (!instance.isGenericInstance())
                return false;

            const SymbolStruct* root = instance.genericRootSym();
            if (!root)
                return false;

            const auto*   decl                 = genericStructDeclNode(*root);
            const SpanRef spanGenericParamsRef = genericStructParamSpan(*root);
            if (!decl || spanGenericParamsRef.isInvalid())
                return false;

            collectGenericParams(sema, *decl, spanGenericParamsRef, outParams);
            if (outParams.empty())
                return false;

            if (!instance.tryGetGenericInstanceArgs(outArgs))
                return false;
            if (outArgs.size() < outParams.size())
                return false;
            // Instance keys can carry bookkeeping beyond the user-declared generic
            // parameters. Diagnostics and ambient binding lookup must line up with
            // the declaration order, so trim the extra tail before pairing.
            if (outArgs.size() > outParams.size())
                outArgs.resize(outParams.size());
            return true;
        }

        bool loadFunctionInstanceGenericArgs(Sema& sema, const SymbolFunction& function, SmallVector<GenericParamDesc>& outParams, SmallVector<GenericInstanceKey>& outArgs)
        {
            if (!function.isGenericInstance())
                return false;

            const SymbolFunction* root = function.genericRootSym();
            if (!root)
                return false;

            const auto* decl = genericFunctionDecl(*root);
            if (!decl || decl->spanGenericParamsRef.isInvalid())
                return false;

            collectGenericParams(sema, *decl, decl->spanGenericParamsRef, outParams);
            if (outParams.empty())
                return false;

            if (!function.tryGetGenericInstanceArgs(sema.ctx(), outArgs))
                return false;
            if (outArgs.size() < outParams.size())
                return false;
            if (outArgs.size() > outParams.size())
                outArgs.resize(outParams.size());
            return true;
        }

        bool loadOwnerStructGenericArgs(Sema& sema, const SymbolFunction& function, SmallVector<GenericParamDesc>& outParams, SmallVector<GenericInstanceKey>& outArgs)
        {
            const SymbolStruct* ownerInstance = function.ownerStruct();
            if (!ownerInstance)
                return false;

            return loadStructInstanceGenericArgs(sema, *ownerInstance, outParams, outArgs);
        }

        void collectAmbientGenericFunctions(const Sema& sema, SmallVector<const SymbolFunction*>& outFunctions)
        {
            outFunctions.clear();
            std::unordered_set<const SymbolFunction*> seenFunctions;

            // Inline expansion can nest generic instances inside other generic
            // instances. Walk from the innermost frame outward so value/type
            // bindings prefer the most local instantiation context.
            for (size_t i = sema.frames().size(); i > 0; --i)
            {
                const SemaInlinePayload* inlinePayload = sema.frames()[i - 1].currentInlinePayload();
                while (inlinePayload)
                {
                    if (const SymbolFunction* function = genericFunctionInstanceOrNull(inlinePayload->sourceFunction))
                    {
                        if (seenFunctions.insert(function).second)
                            outFunctions.push_back(function);
                    }

                    inlinePayload = inlinePayload->parentInlinePayload;
                }
            }

            if (const SymbolFunction* function = genericFunctionInstanceOrNull(sema.currentFunction()))
            {
                if (seenFunctions.insert(function).second)
                    outFunctions.push_back(function);
            }
        }

        Utf8 formatResolvedGenericArg(Sema& sema, const GenericResolvedArg& arg)
        {
            if (arg.cstRef.isValid())
                return sema.cstMgr().get(arg.cstRef).toString(sema.ctx());
            if (arg.typeRef.isValid())
                return sema.typeMgr().get(arg.typeRef).toName(sema.ctx());
            return "?";
        }

        Utf8 formatGenericInstanceKey(Sema& sema, const GenericInstanceKey& key)
        {
            if (key.typeRef.isValid())
                return sema.typeMgr().get(key.typeRef).toName(sema.ctx());
            if (key.cstRef.isValid())
                return sema.cstMgr().get(key.cstRef).toString(sema.ctx());
            return "?";
        }

        void appendFormattedBinding(Utf8& out, const std::string_view name, const Utf8& value)
        {
            if (!out.empty())
                out += ", ";

            out += name;
            out += " = ";
            out += value;
        }

        Utf8 formatResolvedGenericBindings(Sema& sema, const ResolvedGenericBindingSource& source)
        {
            Utf8 result;
            if (source.params.size() != source.resolvedArgs.size())
                return result;

            for (size_t i = 0; i < source.params.size(); ++i)
            {
                if (!source.params[i].idRef.isValid())
                    continue;

                appendFormattedBinding(result, sema.idMgr().get(source.params[i].idRef).name, formatResolvedGenericArg(sema, source.resolvedArgs[i]));
            }

            return result;
        }

        Utf8 formatGenericInstanceBindings(Sema& sema, const std::span<const GenericParamDesc> params, const std::span<const GenericInstanceKey> args)
        {
            Utf8 result;
            if (params.size() != args.size())
                return result;

            for (size_t i = 0; i < params.size(); ++i)
            {
                if (!params[i].idRef.isValid())
                    continue;

                appendFormattedBinding(result, sema.idMgr().get(params[i].idRef).name, formatGenericInstanceKey(sema, args[i]));
            }

            return result;
        }
    }

    namespace
    {
        using Internal::appendFormattedBinding;
        using Internal::collectAmbientGenericFunctions;
        using Internal::formatGenericInstanceKey;
        using Internal::formatResolvedGenericArg;
        using Internal::loadFunctionInstanceGenericArgs;
        using Internal::loadOwnerStructGenericArgs;
        using Internal::ResolvedGenericBindingSource;

        const SymbolFunction* declContextRoot(const SymbolFunction& function)
        {
            return function.genericRootOrSelf();
        }

        SymbolMap* functionDeclStartSymMap(const SymbolFunction& function)
        {
            return const_cast<SymbolMap*>(declContextRoot(function)->ownerSymMap());
        }

        const SymbolImpl* functionDeclImplContext(Sema& sema, const SymbolFunction& function)
        {
            // Lazy and instantiated functions can be resolved outside their original
            // declaration frame. Prefer the stored declaration context, then fall
            // back through the active sema frame/symbol-map stack.
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
    }

    namespace
    {
        void buildGenericCloneBindings(std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, SmallVector<SemaClone::ParamBinding>& outBindings)
        {
            outBindings.clear();
            outBindings.reserve(params.size());
            for (size_t i = 0; i < params.size(); ++i)
                appendResolvedGenericBinding(params[i], resolvedArgs[i], outBindings);
        }

        void buildGenericCloneBindings(const ResolvedGenericBindingSource& source, SmallVector<SemaClone::ParamBinding>& outBindings)
        {
            buildGenericCloneBindings(source.params, source.resolvedArgs, outBindings);
        }

        void appendGenericInstanceCloneBindings(Sema& sema, std::span<const GenericParamDesc> params, std::span<const GenericInstanceKey> args, SmallVector<SemaClone::ParamBinding>& outBindings)
        {
            if (params.size() != args.size())
                return;

            for (size_t i = 0; i < args.size(); ++i)
            {
                GenericResolvedArg resolvedArg;
                resolvedArg.present = args[i].typeRef.isValid() || args[i].cstRef.isValid();
                resolvedArg.typeRef = args[i].typeRef;
                resolvedArg.cstRef  = args[i].cstRef;
                if (resolvedArg.cstRef.isValid() && !resolvedArg.typeRef.isValid())
                    resolvedArg.typeRef = sema.cstMgr().get(resolvedArg.cstRef).typeRef();
                appendResolvedGenericBinding(params[i], resolvedArg, outBindings);
            }
        }

        void appendOwnerStructCloneBindings(Sema& sema, const SymbolFunction& function, SmallVector<SemaClone::ParamBinding>& outBindings)
        {
            SmallVector<GenericParamDesc>   ownerParams;
            SmallVector<GenericInstanceKey> ownerArgs;
            if (!loadOwnerStructGenericArgs(sema, function, ownerParams, ownerArgs))
                return;

            appendGenericInstanceCloneBindings(sema, ownerParams.span(), ownerArgs.span(), outBindings);
        }

        SymbolFlags clonedGenericSymbolFlags(const Symbol& root)
        {
            SymbolFlags flags = SymbolFlagsE::Zero;
            if (root.isPublic())
                flags.add(SymbolFlagsE::Public);
            return flags;
        }

        void prepareGenericDeclSemaContext(Sema& child, Sema& sema, const Symbol& root)
        {
            if (const auto* function = root.safeCast<SymbolFunction>())
            {
                prepareGenericInstantiationContext(child, functionDeclStartSymMap(*function), functionDeclImplContext(sema, *function), functionDeclInterfaceContext(sema, *function), function->attributes());
            }
            else
            {
                prepareGenericInstantiationContext(child, const_cast<SymbolMap*>(root.ownerSymMap()), nullptr, nullptr, root.attributes());
                if (root.isPublic())
                    child.frame().setCurrentAccess(SymbolAccess::Public);
            }
        }

    }

    namespace Internal
    {
        Sema* tryCreateSemaForGenericDecl(Sema& sema, const Symbol& root, std::unique_ptr<Sema>& ownedSema)
        {
            Sema* result = sema.tryCreateDeclSema(ownedSema, root.srcViewRef(), root.decl(), genericDeclNodeRef(root));
            if (!result)
                return nullptr;

            prepareGenericDeclSemaContext(*ownedSema, sema, root);
            return result;
        }
    }

    namespace
    {
        Sema* tryCreateSemaForSymbolDecl(Sema& sema, const Symbol& symbol, std::unique_ptr<Sema>& ownedSema)
        {
            const AstNode* decl = symbol.decl();
            if (!decl)
                return nullptr;

            return sema.tryCreateDeclSema(ownedSema, decl->srcViewRef(), decl);
        }

        struct GenericNodeRunKey
        {
            const TaskContext* ctx      = nullptr;
            const Ast*         ownerAst = nullptr;
            uint32_t           nodeRef  = 0;

            bool operator==(const GenericNodeRunKey& other) const noexcept
            {
                return ctx == other.ctx && ownerAst == other.ownerAst && nodeRef == other.nodeRef;
            }
        };

        struct GenericNodeRunKeyHash
        {
            size_t operator()(const GenericNodeRunKey& key) const noexcept
            {
                size_t hash = std::hash<const TaskContext*>{}(key.ctx);
                hash ^= std::hash<const Ast*>{}(key.ownerAst) + 0x9e3779b97f4a7c15ull + (hash << 6) + (hash >> 2);
                hash ^= std::hash<uint32_t>{}(key.nodeRef) + 0x9e3779b97f4a7c15ull + (hash << 6) + (hash >> 2);
                return hash;
            }
        };

        struct GenericInstanceNodeRunKey
        {
            const TaskContext* ctx      = nullptr;
            const Symbol*      instance = nullptr;

            bool operator==(const GenericInstanceNodeRunKey& other) const noexcept
            {
                return ctx == other.ctx && instance == other.instance;
            }
        };

        struct GenericInstanceNodeRunKeyHash
        {
            size_t operator()(const GenericInstanceNodeRunKey& key) const noexcept
            {
                return std::hash<const TaskContext*>{}(key.ctx) ^ std::hash<const Symbol*>{}(key.instance);
            }
        };

        size_t combineHash(size_t lhs, size_t rhs)
        {
            return lhs ^ (rhs + 0x9e3779b97f4a7c15ull + (lhs << 6) + (lhs >> 2));
        }

        struct CachedSemaRun
        {
            bool                  running = false;
            std::unique_ptr<Sema> sema;
        };

        struct GenericImplBlockRunKey
        {
            const TaskContext* ctx      = nullptr;
            const SymbolImpl*  impl     = nullptr;
            bool               declPass = false;

            bool operator==(const GenericImplBlockRunKey& other) const noexcept
            {
                return ctx == other.ctx && impl == other.impl && declPass == other.declPass;
            }
        };

        struct GenericImplBlockRunKeyHash
        {
            size_t operator()(const GenericImplBlockRunKey& key) const noexcept
            {
                size_t hash = std::hash<const TaskContext*>{}(key.ctx);
                hash        = combineHash(hash, std::hash<const SymbolImpl*>{}(key.impl));
                return combineHash(hash, std::hash<bool>{}(key.declPass));
            }
        };

        std::unordered_map<GenericNodeRunKey, CachedSemaRun, GenericNodeRunKeyHash>& genericNodeRuns(TaskContext& ctx)
        {
            auto& cache = ctx.genericNodeRunCache();
            if (!cache)
            {
                // TaskContext is job-owned and only one worker executes a given job at a
                // time. Keep this paused-child cache there instead of routing every
                // generic-node lookup through a global mutex.
                cache = std::make_shared<std::unordered_map<GenericNodeRunKey, CachedSemaRun, GenericNodeRunKeyHash>>();
            }

            return *std::static_pointer_cast<std::unordered_map<GenericNodeRunKey, CachedSemaRun, GenericNodeRunKeyHash>>(cache);
        }

        std::unordered_map<GenericInstanceNodeRunKey, CachedSemaRun, GenericInstanceNodeRunKeyHash>& genericInstanceNodeRuns(TaskContext& ctx)
        {
            auto& cache = ctx.genericInstanceNodeRunCache();
            if (!cache)
            {
                // Generic-instance runs are keyed by task context already, so keep their
                // paused-child cache with that owning task instead of funnelling every
                // lookup through a process-wide mutex.
                cache = std::make_shared<std::unordered_map<GenericInstanceNodeRunKey, CachedSemaRun, GenericInstanceNodeRunKeyHash>>();
            }

            return *std::static_pointer_cast<std::unordered_map<GenericInstanceNodeRunKey, CachedSemaRun, GenericInstanceNodeRunKeyHash>>(cache);
        }

        template<typename RUN, typename K, typename I>
        Result runCachedSema(Sema& sema, RUN& runs, const K& key, const Symbol& waitSymbol, const I& initRun)
        {
            SWC_UNUSED(sema);
            SWC_UNUSED(waitSymbol);

            auto& run = runs[key];
            if (!run.sema)
                run.sema = initRun();
            if (run.running)
            {
                // These caches live on the task context, so a running entry can only be
                // re-entered by the same job. Waiting on the symbol here would make that
                // job sleep on work that only it can resume.
                return Result::Continue;
            }

            run.running = true;
            Sema* child = run.sema.get();
            SWC_ASSERT(child);

            const Result result = child->execResult();
            run.running         = false;
            if (result != Result::Pause)
                runs.erase(key);
            return result;
        }

        void prepareGenericNodeRunContext(Sema& child, Sema& sema, const Symbol& root)
        {
            prepareGenericDeclSemaContext(child, sema, root);
            child.frame().addContextFlag(SemaFrameContextFlagsE::RequireConstExpr);
        }

        struct GenericNodeRunInitializer
        {
            Sema*         sema = nullptr;
            const Symbol* root = nullptr;
            AstNodeRef    nodeRef;

            std::unique_ptr<Sema> operator()() const
            {
                SWC_ASSERT(sema != nullptr);
                SWC_ASSERT(root != nullptr);
                auto child = std::make_unique<Sema>(sema->ctx(), *sema, nodeRef);
                prepareGenericNodeRunContext(*child, *sema, *root);
                return child;
            }
        };

        struct GenericInstanceNodeRunInitializer
        {
            Sema*         sema = nullptr;
            const Symbol* root = nullptr;
            AstNodeRef    nodeRef;

            std::unique_ptr<Sema> operator()() const
            {
                SWC_ASSERT(sema != nullptr);
                SWC_ASSERT(root != nullptr);
                auto child = std::make_unique<Sema>(sema->ctx(), *sema, nodeRef);
                prepareGenericNodeRunContext(*child, *sema, *root);
                return child;
            }
        };

        Result runGenericNode(Sema& sema, const Symbol& root, AstNodeRef nodeRef)
        {
            SWC_ASSERT(root.isFunction() || root.isStruct());

            const GenericNodeRunKey         key{&sema.ctx(), &sema.ast(), nodeRef.get()};
            const GenericNodeRunInitializer initRun{.sema = &sema, .root = &root, .nodeRef = nodeRef};
            return runCachedSema(sema, genericNodeRuns(sema.ctx()), key, root, initRun);
        }

    }

    namespace Internal
    {
        Result runGenericInstanceNode(Sema& sema, const Symbol& root, Symbol& instance)
        {
            SWC_ASSERT(root.isFunction() || root.isStruct());

            const AstNodeRef nodeRef = genericDeclNodeRef(instance);
            if (nodeRef.isInvalid())
                return Result::Error;

            const GenericInstanceNodeRunKey         key{&sema.ctx(), &instance};
            const GenericInstanceNodeRunInitializer initRun{.sema = &sema, .root = &root, .nodeRef = nodeRef};
            return runCachedSema(sema, genericInstanceNodeRuns(sema.ctx()), key, instance, initRun);
        }
    }

    namespace
    {
        void appendEnclosingFunctionGenericCloneBindings(Sema& sema, const SymbolFunction& root, SmallVector<SemaClone::ParamBinding>& outBindings)
        {
            SmallVector<GenericParamDesc>   ownerParams;
            SmallVector<GenericInstanceKey> ownerArgs;
            if (!loadOwnerStructGenericArgs(sema, root, ownerParams, ownerArgs))
                return;

            appendGenericInstanceCloneBindings(sema, ownerParams.span(), ownerArgs.span(), outBindings);
        }

        void appendFunctionInstanceCloneBindings(Sema& sema, const SymbolFunction& function, SmallVector<SemaClone::ParamBinding>& outBindings)
        {
            SmallVector<GenericParamDesc>   params;
            SmallVector<GenericInstanceKey> args;
            if (!loadFunctionInstanceGenericArgs(sema, function, params, args))
                return;

            appendGenericInstanceCloneBindings(sema, params.span(), args.span(), outBindings);
        }

        void appendFunctionContextCloneBindings(Sema& sema, const SymbolFunction& function, SmallVector<SemaClone::ParamBinding>& outBindings)
        {
            appendFunctionInstanceCloneBindings(sema, function, outBindings);
            appendEnclosingFunctionGenericCloneBindings(sema, function, outBindings);
        }

        void appendAmbientGenericCloneBindings(Sema& sema, SmallVector<SemaClone::ParamBinding>& outBindings)
        {
            SmallVector<const SymbolFunction*> functions;
            collectAmbientGenericFunctions(sema, functions);
            for (const SymbolFunction* function : functions)
                appendFunctionContextCloneBindings(sema, *function, outBindings);
        }

        void appendEnclosingGenericCloneBindings(Sema& sema, const Symbol& root, SmallVector<SemaClone::ParamBinding>& outBindings)
        {
            if (const auto* function = root.safeCast<SymbolFunction>())
                appendOwnerStructCloneBindings(sema, *function, outBindings);

            appendAmbientGenericCloneBindings(sema, outBindings);
        }
    }

    namespace Internal
    {
        void buildResolvedGenericContextBindings(Sema& sema, const Symbol& root, const ResolvedGenericBindingSource& source, SmallVector<SemaClone::ParamBinding>& outBindings)
        {
            buildGenericCloneBindings(source, outBindings);
            appendEnclosingGenericCloneBindings(sema, root, outBindings);
        }

        void buildPartialGenericContextBindings(Sema& sema, const Symbol& root, const ResolvedGenericBindingSource& source, size_t count, SmallVector<SemaClone::ParamBinding>& outBindings)
        {
            collectResolvedGenericBindings(source.params, source.resolvedArgs, count, outBindings);
            appendEnclosingGenericCloneBindings(sema, root, outBindings);
        }
    }

    namespace
    {
        using Internal::GenericEvalReadyKind;

        void buildFunctionInstanceContextBindings(Sema& sema, const SymbolFunction& function, SmallVector<SemaClone::ParamBinding>& outBindings)
        {
            outBindings.clear();
            appendFunctionInstanceCloneBindings(sema, function, outBindings);
            appendEnclosingGenericCloneBindings(sema, function, outBindings);
        }

        bool hasFormattedBinding(std::span<const IdentifierRef> ids, IdentifierRef idRef)
        {
            for (const IdentifierRef it : ids)
            {
                if (it == idRef)
                    return true;
            }

            return false;
        }

        AstNodeRef findCachedGenericEvalNode(Sema& sema, const Symbol& root, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings)
        {
            const NodePayload* payloadContext = &sema.currentNodePayloadContext();
            if (const auto* function = root.safeCast<SymbolFunction>())
                return function->findGenericEvalNode(sema.ctx(), payloadContext, sema.ast(), sourceRef, bindings);
            return root.cast<SymbolStruct>().findGenericEvalNode(payloadContext, sema.ast(), sourceRef, bindings);
        }

        bool hasCachedGenericEvalResult(Sema& sema, AstNodeRef nodeRef, GenericEvalReadyKind readyKind)
        {
            if (nodeRef.isInvalid())
                return false;

            switch (readyKind)
            {
                case GenericEvalReadyKind::Constant:
                    return sema.viewStored(nodeRef, SemaNodeViewPartE::Constant).cstRef().isValid();

                case GenericEvalReadyKind::TypeOrSymbol:
                {
                    const SemaNodeView storedView = sema.viewStored(nodeRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
                    return storedView.typeRef().isValid() || (storedView.hasSymbol() && storedView.sym() && storedView.sym()->isType());
                }
            }

            SWC_UNREACHABLE();
        }

        void cacheGenericEvalNode(Sema& sema, const Symbol& root, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef evalRef)
        {
            const NodePayload* payloadContext = &sema.currentNodePayloadContext();
            if (const auto* function = root.safeCast<SymbolFunction>())
                function->cacheGenericEvalNode(sema.ctx(), payloadContext, sema.ast(), sourceRef, bindings, evalRef);
            else
                root.cast<SymbolStruct>().cacheGenericEvalNode(payloadContext, sema.ast(), sourceRef, bindings, evalRef);
        }

        std::recursive_mutex& genericEvalRunMutex(Sema& sema, const Symbol& root)
        {
            if (const auto* function = root.safeCast<SymbolFunction>())
                return function->genericEvalRunMutex(sema.ctx());
            return root.cast<SymbolStruct>().genericEvalRunMutex();
        }

        std::unordered_map<GenericImplBlockRunKey, CachedSemaRun, GenericImplBlockRunKeyHash>& genericImplBlockRuns(TaskContext& ctx)
        {
            auto& cache = ctx.genericImplBlockRunCache();
            if (!cache)
            {
                // Generic impl-block runs are keyed by task context, so keep their
                // paused-child cache on that owning task instead of serializing every
                // lookup behind a process-wide mutex.
                cache = std::make_shared<std::unordered_map<GenericImplBlockRunKey, CachedSemaRun, GenericImplBlockRunKeyHash>>();
            }

            return *std::static_pointer_cast<std::unordered_map<GenericImplBlockRunKey, CachedSemaRun, GenericImplBlockRunKeyHash>>(cache);
        }

        void appendResolvedBindingText(Sema& sema, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, SmallVector<IdentifierRef>& seenIds, Utf8& out)
        {
            if (params.size() != resolvedArgs.size())
                return;

            for (size_t i = 0; i < params.size(); ++i)
            {
                if (!params[i].idRef.isValid() || hasFormattedBinding(seenIds.span(), params[i].idRef))
                    continue;

                seenIds.push_back(params[i].idRef);
                appendFormattedBinding(out, sema.idMgr().get(params[i].idRef).name, formatResolvedGenericArg(sema, resolvedArgs[i]));
            }
        }

        void appendGenericInstanceBindingText(Sema& sema, std::span<const GenericParamDesc> params, std::span<const GenericInstanceKey> args, SmallVector<IdentifierRef>& seenIds, Utf8& out)
        {
            if (params.size() != args.size())
                return;

            for (size_t i = 0; i < params.size(); ++i)
            {
                if (!params[i].idRef.isValid() || hasFormattedBinding(seenIds.span(), params[i].idRef))
                    continue;

                seenIds.push_back(params[i].idRef);
                appendFormattedBinding(out, sema.idMgr().get(params[i].idRef).name, formatGenericInstanceKey(sema, args[i]));
            }
        }

        void appendFunctionInstanceBindingText(Sema& sema, const SymbolFunction& function, SmallVector<IdentifierRef>& seenIds, Utf8& out)
        {
            SmallVector<GenericParamDesc>   params;
            SmallVector<GenericInstanceKey> args;
            if (!loadFunctionInstanceGenericArgs(sema, function, params, args))
                return;

            appendGenericInstanceBindingText(sema, params.span(), args.span(), seenIds, out);
        }

        void appendOwnerStructBindingText(Sema& sema, const SymbolFunction& function, SmallVector<IdentifierRef>& seenIds, Utf8& out)
        {
            SmallVector<GenericParamDesc>   params;
            SmallVector<GenericInstanceKey> args;
            if (!loadOwnerStructGenericArgs(sema, function, params, args))
                return;

            appendGenericInstanceBindingText(sema, params.span(), args.span(), seenIds, out);
        }

        void appendFunctionContextBindingText(Sema& sema, const SymbolFunction& function, SmallVector<IdentifierRef>& seenIds, Utf8& out)
        {
            appendFunctionInstanceBindingText(sema, function, seenIds, out);
            appendOwnerStructBindingText(sema, function, seenIds, out);
        }

        void appendAmbientBindingText(Sema& sema, SmallVector<IdentifierRef>& seenIds, Utf8& out)
        {
            SmallVector<const SymbolFunction*> functions;
            collectAmbientGenericFunctions(sema, functions);
            for (const SymbolFunction* function : functions)
                appendFunctionContextBindingText(sema, *function, seenIds, out);
        }

        Utf8 formatFunctionWhereBindings(Sema& sema, const SymbolFunction& function, std::span<const GenericParamDesc> params = {}, std::span<const GenericResolvedArg> resolvedArgs = {})
        {
            Utf8                       out;
            SmallVector<IdentifierRef> seenIds;

            if (!params.empty())
                appendResolvedBindingText(sema, params, resolvedArgs, seenIds, out);
            else
                appendFunctionInstanceBindingText(sema, function, seenIds, out);

            appendAmbientBindingText(sema, seenIds, out);
            return out;
        }

    }

    namespace Internal
    {
        void buildFunctionWhereInputs(Sema& sema, const SymbolFunction& function, FunctionWhereInputs& outInputs)
        {
            buildFunctionInstanceContextBindings(sema, function, outInputs.bindings);
            outInputs.bindingText = formatFunctionWhereBindings(sema, function);
        }

        void buildFunctionWhereInputs(Sema& sema, const SymbolFunction& function, const ResolvedGenericBindingSource& source, FunctionWhereInputs& outInputs)
        {
            buildResolvedGenericContextBindings(sema, function, source, outInputs.bindings);
            outInputs.bindingText = formatFunctionWhereBindings(sema, function, source.params, source.resolvedArgs);
        }
    }

    namespace
    {
        AstNodeRef makeConstraintBlockRunNode(Sema& sema, AstNodeRef constraintBlockRef, std::span<const SemaClone::ParamBinding> bindings)
        {
            const auto&             constraintBlock = sema.node(constraintBlockRef).cast<AstConstraintBlock>();
            SmallVector<AstNodeRef> sourceChildren;
            sema.ast().appendNodes(sourceChildren, constraintBlock.spanChildrenRef);

            SmallVector<AstNodeRef> clonedChildren;
            clonedChildren.reserve(sourceChildren.size());
            const SemaClone::CloneContext cloneContext{bindings};
            for (const AstNodeRef childRef : sourceChildren)
            {
                const AstNodeRef clonedChildRef = SemaClone::cloneAst(sema, childRef, cloneContext);
                if (clonedChildRef.isInvalid())
                    return AstNodeRef::invalid();
                clonedChildren.push_back(clonedChildRef);
            }

            TokenRef bodyTokRef = constraintBlock.tokRef();
            if (!clonedChildren.empty())
                bodyTokRef = sema.node(clonedChildren[0]).tokRef();

            auto [bodyRef, bodyPtr]  = sema.ast().makeNode<AstNodeId::EmbeddedBlock>(bodyTokRef);
            bodyPtr->spanChildrenRef = sema.ast().pushSpan(clonedChildren.span());

            auto [runRef, runPtr] = sema.ast().makeNode<AstNodeId::CompilerRunBlock>(constraintBlock.tokRef());
            runPtr->nodeBodyRef   = bodyRef;
            runPtr->addFlag(AstCompilerRunBlockFlagsE::Immediate);
            return runRef;
        }
    }

    namespace Internal
    {
        Result evalGenericConstraintNode(Sema& sema, const Symbol& root, AstNodeRef constraintRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef& outEvalRef)
        {
            outEvalRef = AstNodeRef::invalid();
            if (constraintRef.isInvalid())
                return Result::Continue;

            if (const auto* constraintExpr = sema.node(constraintRef).safeCast<AstConstraintExpr>())
            {
                outEvalRef = findCachedGenericEvalNode(sema, root, constraintExpr->nodeExprRef, bindings);
                if (hasCachedGenericEvalResult(sema, outEvalRef, GenericEvalReadyKind::Constant))
                    return Result::Continue;
                return evalGenericClonedNode(sema, root, constraintExpr->nodeExprRef, bindings, GenericEvalReadyKind::Constant, outEvalRef);
            }

            if (sema.node(constraintRef).is(AstNodeId::ConstraintBlock))
            {
                const std::scoped_lock lock(genericEvalRunMutex(sema, root));
                outEvalRef = findCachedGenericEvalNode(sema, root, constraintRef, bindings);
                if (hasCachedGenericEvalResult(sema, outEvalRef, GenericEvalReadyKind::Constant))
                    return Result::Continue;

                if (outEvalRef.isInvalid())
                {
                    outEvalRef = makeConstraintBlockRunNode(sema, constraintRef, bindings);
                    if (outEvalRef.isInvalid())
                        return Result::Error;

                    cacheGenericEvalNode(sema, root, constraintRef, bindings, outEvalRef);
                }

                return runGenericNode(sema, root, outEvalRef);
            }

            return Result::Continue;
        }
    }

    namespace
    {
        struct GenericImplBlockRunInitializer
        {
            Sema*                  sema = nullptr;
            AstNodeRef             blockRef;
            SymbolImpl*            impl     = nullptr;
            const SymbolInterface* itf      = nullptr;
            const AttributeList*   attrs    = nullptr;
            bool                   declPass = false;

            std::unique_ptr<Sema> operator()() const
            {
                SWC_ASSERT(sema != nullptr);
                SWC_ASSERT(impl != nullptr);
                SWC_ASSERT(attrs != nullptr);
                auto child = std::make_unique<Sema>(sema->ctx(), *sema, blockRef, declPass);
                prepareGenericInstantiationContext(*child, impl->asSymMap(), impl, itf, *attrs);
                return child;
            }
        };

        Result runGenericImplBlockPass(Sema& sema, AstNodeRef blockRef, SymbolImpl& impl, const SymbolInterface* itf, const AttributeList& attrs, bool declPass)
        {
            const GenericImplBlockRunKey         key{&sema.ctx(), &impl, declPass};
            const GenericImplBlockRunInitializer initRun{.sema = &sema, .blockRef = blockRef, .impl = &impl, .itf = itf, .attrs = &attrs, .declPass = declPass};
            return runCachedSema(sema, genericImplBlockRuns(sema.ctx()), key, impl, initRun);
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

            outBlockRef      = cloneGenericImplBlock(sema, *implDecl, bindings);
            outClone         = Symbol::make<SymbolImpl>(sema.ctx(), sourceImpl.decl(), sourceImpl.tokRef(), sourceImpl.idRef(), clonedGenericSymbolFlags(sourceImpl));
            auto ownerSymMap = const_cast<SymbolMap*>(sourceImpl.ownerSymMap());
            if (!ownerSymMap)
            {
                if (sourceImpl.isForStruct())
                    ownerSymMap = sourceImpl.symStruct()->ownerSymMap();
                else if (sourceImpl.isForEnum())
                    ownerSymMap = sourceImpl.symEnum()->ownerSymMap();
            }
            outClone->setOwnerSymMap(ownerSymMap);
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
            if (result == Result::Error && created && !implClone->isSemaCompleted())
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
    }

    namespace Internal
    {
        Result instantiateGenericStructImpls(Sema& sema, const SymbolStruct& root, SymbolStruct& instance, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs)
        {
            const auto rootImpls      = root.impls();
            const auto rootInterfaces = root.interfaces();
            if (rootImpls.empty() && rootInterfaces.empty())
                return Result::Continue;

            const ResolvedGenericBindingSource   source{params, resolvedArgs};
            SmallVector<SemaClone::ParamBinding> bindings;
            buildGenericCloneBindings(source, bindings);

            for (const auto* sourceImpl : rootImpls)
            {
                if (!sourceImpl)
                    continue;

                std::unique_ptr<Sema> implSemaHolder;
                Sema*                 implSema = tryCreateSemaForSymbolDecl(sema, *sourceImpl, implSemaHolder);
                if (!implSema)
                    implSema = &sema;
                SWC_RESULT(instantiateGenericStructImpl(*implSema, *sourceImpl, instance, bindings.span()));
            }

            for (const auto* sourceImpl : rootInterfaces)
            {
                if (!sourceImpl)
                    continue;

                std::unique_ptr<Sema> implSemaHolder;
                Sema*                 implSema = tryCreateSemaForSymbolDecl(sema, *sourceImpl, implSemaHolder);
                if (!implSema)
                    implSema = &sema;
                SWC_RESULT(instantiateGenericStructInterface(*implSema, *sourceImpl, instance, bindings.span()));
            }

            return Result::Continue;
        }

        Result evalGenericClonedNode(Sema& sema, const Symbol& root, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, GenericEvalReadyKind readyKind, AstNodeRef& outClonedRef)
        {
            outClonedRef = AstNodeRef::invalid();
            if (sourceRef.isInvalid())
                return Result::Continue;

            const std::scoped_lock lock(genericEvalRunMutex(sema, root));
            outClonedRef = findCachedGenericEvalNode(sema, root, sourceRef, bindings);
            if (hasCachedGenericEvalResult(sema, outClonedRef, readyKind))
                return Result::Continue;

            if (outClonedRef.isInvalid())
            {
                const SemaClone::CloneContext cloneContext{bindings};
                outClonedRef = SemaClone::cloneAst(sema, sourceRef, cloneContext);
                if (outClonedRef.isInvalid())
                    return Result::Error;

                cacheGenericEvalNode(sema, root, sourceRef, bindings, outClonedRef);
            }

            return runGenericNode(sema, root, outClonedRef);
        }
    }
}

SWC_END_NAMESPACE();
