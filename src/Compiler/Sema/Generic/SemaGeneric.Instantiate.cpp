#include "pch.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Cast/CastFailure.h"
#include "Compiler/Sema/Cast/CastRequest.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const AstFunctionDecl* genericFunctionDecl(const SymbolFunction& root);
    const AstStructDecl*   genericStructDecl(const SymbolStruct& root);

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

    void appendGenericInstanceCloneBindings(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const GenericInstanceKey> args, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        if (params.size() != args.size())
            return;

        for (size_t i = 0; i < args.size(); ++i)
        {
            SemaGeneric::GenericResolvedArg resolvedArg;
            resolvedArg.present = args[i].typeRef.isValid() || args[i].cstRef.isValid();
            resolvedArg.typeRef = args[i].typeRef;
            resolvedArg.cstRef  = args[i].cstRef;
            if (resolvedArg.cstRef.isValid() && !resolvedArg.typeRef.isValid())
                resolvedArg.typeRef = sema.cstMgr().get(resolvedArg.cstRef).typeRef();
            SemaGeneric::appendResolvedGenericBinding(params[i], resolvedArg, outBindings);
        }
    }

    bool loadFunctionInstanceGenericArgs(Sema& sema, const SymbolFunction& function, SmallVector<SemaGeneric::GenericParamDesc>& outParams, SmallVector<GenericInstanceKey>& outArgs)
    {
        if (!function.isGenericInstance())
            return false;

        const SymbolFunction* root = function.genericRootSym();
        if (!root)
            return false;

        const auto* decl = genericFunctionDecl(*root);
        if (!decl || decl->spanGenericParamsRef.isInvalid())
            return false;

        SemaGeneric::collectGenericParams(sema, *decl, decl->spanGenericParamsRef, outParams);
        if (outParams.empty())
            return false;

        if (!root->genericInstanceStorage(sema.ctx()).tryGetArgs(function, outArgs))
            return false;
        if (outArgs.size() < outParams.size())
            return false;
        if (outArgs.size() > outParams.size())
            outArgs.resize(outParams.size());
        return true;
    }

    bool loadOwnerStructGenericArgs(Sema& sema, const SymbolFunction& function, SmallVector<SemaGeneric::GenericParamDesc>& outParams, SmallVector<GenericInstanceKey>& outArgs)
    {
        const SymbolStruct* ownerInstance = function.ownerStruct();
        if (!ownerInstance || !ownerInstance->isGenericInstance())
            return false;

        const SymbolStruct* ownerRoot = ownerInstance->genericRootSym();
        if (!ownerRoot)
            return false;

        const auto* decl = genericStructDecl(*ownerRoot);
        if (!decl || decl->spanGenericParamsRef.isInvalid())
            return false;

        SemaGeneric::collectGenericParams(sema, *decl, decl->spanGenericParamsRef, outParams);
        if (outParams.empty())
            return false;

        return ownerRoot->tryGetGenericInstanceArgs(*ownerInstance, outArgs);
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

    Sema& semaForGenericDecl(Sema& sema, const Symbol& root, std::unique_ptr<Sema>& ownedSema)
    {
        const SourceView& srcView = sema.compiler().srcView(root.srcViewRef());
        if (sema.ast().srcView().fileRef() == srcView.ownerFileRef())
            return sema;

        SourceFile& sourceFile = sema.compiler().file(srcView.ownerFileRef());
        AstNodeRef  declRef    = genericDeclNodeRef(root);
        if (declRef.isInvalid() && root.decl())
            declRef = root.decl()->nodeRef(sourceFile.ast());
        SWC_ASSERT(declRef.isValid());

        ownedSema = std::make_unique<Sema>(sema.ctx(), sema, sourceFile.nodePayloadContext(), declRef);
        return *ownedSema;
    }

    struct GenericNodeRunKey
    {
        const TaskContext* ctx     = nullptr;
        uint32_t           nodeRef = 0;

        bool operator==(const GenericNodeRunKey& other) const noexcept
        {
            return ctx == other.ctx && nodeRef == other.nodeRef;
        }
    };

    struct GenericNodeRunKeyHash
    {
        size_t operator()(const GenericNodeRunKey& key) const noexcept
        {
            return std::hash<const TaskContext*>{}(key.ctx) ^ std::hash<uint32_t>{}(key.nodeRef);
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

    std::mutex&                                                                                  genericNodeRunMutex();
    std::unordered_map<GenericNodeRunKey, CachedSemaRun, GenericNodeRunKeyHash>&                 genericNodeRuns();
    std::mutex&                                                                                  genericInstanceNodeRunMutex();
    std::unordered_map<GenericInstanceNodeRunKey, CachedSemaRun, GenericInstanceNodeRunKeyHash>& genericInstanceNodeRuns();

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

    std::mutex&                                                                            genericImplBlockRunMutex();
    std::unordered_map<GenericImplBlockRunKey, CachedSemaRun, GenericImplBlockRunKeyHash>& genericImplBlockRuns();

    template<typename RUN, typename K, typename I>
    Result runCachedSema(Sema& sema, std::mutex& mutex, RUN& runs, const K& key, const Symbol& waitSymbol, const I& initRun)
    {
        Sema* child = nullptr;
        {
            const std::scoped_lock lock(mutex);
            auto&                  run = runs[key];
            if (!run.sema)
                run.sema = initRun();
            if (run.running)
                return sema.waitSemaCompleted(&waitSymbol, waitSymbol.codeRef());
            run.running = true;
            child       = run.sema.get();
        }

        SWC_ASSERT(child);
        const Result result = child->execResult();
        {
            const std::scoped_lock lock(mutex);
            auto                   it = runs.find(key);
            if (it != runs.end())
            {
                it->second.running = false;
                if (result != Result::Pause)
                    runs.erase(it);
            }
        }

        return result;
    }

    void prepareGenericNodeRunContext(Sema& child, Sema& sema, const Symbol& root)
    {
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
    }

    Result runGenericNode(Sema& sema, const Symbol& root, AstNodeRef nodeRef)
    {
        SWC_ASSERT(root.isFunction() || root.isStruct());

        const GenericNodeRunKey key{&sema.ctx(), nodeRef.get()};
        auto                    initRun = [&] {
            auto child = std::make_unique<Sema>(sema.ctx(), sema, nodeRef);
            prepareGenericNodeRunContext(*child, sema, root);
            return child;
        };
        return runCachedSema(sema, genericNodeRunMutex(), genericNodeRuns(), key, root, initRun);
    }

    Result runGenericInstanceNode(Sema& sema, const Symbol& root, Symbol& instance)
    {
        SWC_ASSERT(root.isFunction() || root.isStruct());

        const AstNodeRef nodeRef = genericDeclNodeRef(instance);
        if (nodeRef.isInvalid())
            return Result::Error;

        const GenericInstanceNodeRunKey key{&sema.ctx(), &instance};
        auto                            initRun = [&] {
            auto child = std::make_unique<Sema>(sema.ctx(), sema, nodeRef);
            prepareGenericNodeRunContext(*child, sema, root);
            return child;
        };
        return runCachedSema(sema, genericInstanceNodeRunMutex(), genericInstanceNodeRuns(), key, instance, initRun);
    }

    void appendEnclosingFunctionGenericCloneBindings(Sema& sema, const SymbolFunction& root, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        SmallVector<SemaGeneric::GenericParamDesc> ownerParams;
        SmallVector<GenericInstanceKey>            ownerArgs;
        if (!loadOwnerStructGenericArgs(sema, root, ownerParams, ownerArgs))
            return;

        appendGenericInstanceCloneBindings(sema, ownerParams.span(), ownerArgs.span(), outBindings);
    }

    void appendFunctionInstanceCloneBindings(Sema& sema, const SymbolFunction& function, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        SmallVector<SemaGeneric::GenericParamDesc> params;
        SmallVector<GenericInstanceKey>            args;
        if (!loadFunctionInstanceGenericArgs(sema, function, params, args))
            return;

        appendGenericInstanceCloneBindings(sema, params.span(), args.span(), outBindings);
    }

    void appendEnclosingGenericCloneBindings(Sema& sema, const Symbol& root, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        if (const auto* function = root.safeCast<SymbolFunction>())
            appendEnclosingFunctionGenericCloneBindings(sema, *function, outBindings);
    }

    Result evalGenericClonedNode(Sema& sema, const Symbol& root, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef& outClonedRef);

    Utf8 formatResolvedGenericArg(Sema& sema, const SemaGeneric::GenericResolvedArg& arg)
    {
        if (arg.cstRef.isValid())
            return sema.cstMgr().get(arg.cstRef).toString(sema.ctx());
        if (arg.typeRef.isValid())
            return sema.typeMgr().get(arg.typeRef).toName(sema.ctx());
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
        if (const auto* function = root.safeCast<SymbolFunction>())
            return function->findGenericEvalNode(sema.ctx(), sourceRef, bindings);
        return root.cast<SymbolStruct>().findGenericEvalNode(sourceRef, bindings);
    }

    void cacheGenericEvalNode(Sema& sema, const Symbol& root, AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef evalRef)
    {
        if (const auto* function = root.safeCast<SymbolFunction>())
            function->cacheGenericEvalNode(sema.ctx(), sourceRef, bindings, evalRef);
        else
            root.cast<SymbolStruct>().cacheGenericEvalNode(sourceRef, bindings, evalRef);
    }

    std::recursive_mutex& genericEvalRunMutex()
    {
        static std::recursive_mutex mutex;
        return mutex;
    }

    std::mutex& genericNodeRunMutex()
    {
        static std::mutex mutex;
        return mutex;
    }

    std::unordered_map<GenericNodeRunKey, CachedSemaRun, GenericNodeRunKeyHash>& genericNodeRuns()
    {
        static std::unordered_map<GenericNodeRunKey, CachedSemaRun, GenericNodeRunKeyHash> runs;
        return runs;
    }

    std::mutex& genericInstanceNodeRunMutex()
    {
        static std::mutex mutex;
        return mutex;
    }

    std::unordered_map<GenericInstanceNodeRunKey, CachedSemaRun, GenericInstanceNodeRunKeyHash>& genericInstanceNodeRuns()
    {
        static std::unordered_map<GenericInstanceNodeRunKey, CachedSemaRun, GenericInstanceNodeRunKeyHash> runs;
        return runs;
    }

    std::mutex& genericImplBlockRunMutex()
    {
        static std::mutex mutex;
        return mutex;
    }

    std::unordered_map<GenericImplBlockRunKey, CachedSemaRun, GenericImplBlockRunKeyHash>& genericImplBlockRuns()
    {
        static std::unordered_map<GenericImplBlockRunKey, CachedSemaRun, GenericImplBlockRunKeyHash> runs;
        return runs;
    }

    Utf8 formatGenericInstanceKey(Sema& sema, const GenericInstanceKey& key)
    {
        if (key.typeRef.isValid())
            return sema.typeMgr().get(key.typeRef).toName(sema.ctx());
        if (key.cstRef.isValid())
            return sema.cstMgr().get(key.cstRef).toString(sema.ctx());
        return "?";
    }

    void appendFormattedBinding(Utf8& out, std::string_view name, const Utf8& value)
    {
        if (!out.empty())
            out += ", ";

        out += name;
        out += " = ";
        out += value;
    }

    void appendResolvedBindingText(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs, SmallVector<IdentifierRef>& seenIds, Utf8& out)
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

    void appendGenericInstanceBindingText(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const GenericInstanceKey> args, SmallVector<IdentifierRef>& seenIds, Utf8& out)
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
        SmallVector<SemaGeneric::GenericParamDesc> params;
        SmallVector<GenericInstanceKey>            args;
        if (!loadFunctionInstanceGenericArgs(sema, function, params, args))
            return;

        appendGenericInstanceBindingText(sema, params.span(), args.span(), seenIds, out);
    }

    void appendOwnerStructBindingText(Sema& sema, const SymbolFunction& function, SmallVector<IdentifierRef>& seenIds, Utf8& out)
    {
        SmallVector<SemaGeneric::GenericParamDesc> params;
        SmallVector<GenericInstanceKey>            args;
        if (!loadOwnerStructGenericArgs(sema, function, params, args))
            return;

        appendGenericInstanceBindingText(sema, params.span(), args.span(), seenIds, out);
    }

    Utf8 formatFunctionWhereBindings(Sema& sema, const SymbolFunction& function, std::span<const SemaGeneric::GenericParamDesc> params = {}, std::span<const SemaGeneric::GenericResolvedArg> resolvedArgs = {})
    {
        Utf8                       out;
        SmallVector<IdentifierRef> seenIds;

        if (!params.empty())
            appendResolvedBindingText(sema, params, resolvedArgs, seenIds, out);
        else
            appendFunctionInstanceBindingText(sema, function, seenIds, out);

        appendOwnerStructBindingText(sema, function, seenIds, out);
        return out;
    }

    bool isWhereConstraint(Sema& sema, AstNodeRef constraintRef)
    {
        if (!constraintRef.isValid())
            return false;

        const AstNode& constraintNode = sema.node(constraintRef);
        return sema.token(constraintNode.codeRef()).id == TokenId::KwdWhere;
    }

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

    Result evalGenericConstraintNode(Sema& sema, const Symbol& root, AstNodeRef constraintRef, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef& outEvalRef)
    {
        outEvalRef = AstNodeRef::invalid();
        if (constraintRef.isInvalid())
            return Result::Continue;

        if (const auto* constraintExpr = sema.node(constraintRef).safeCast<AstConstraintExpr>())
        {
            outEvalRef = findCachedGenericEvalNode(sema, root, constraintExpr->nodeExprRef, bindings);
            if (outEvalRef.isValid() && sema.viewStored(outEvalRef, SemaNodeViewPartE::Constant).cstRef().isValid())
                return Result::Continue;
            return evalGenericClonedNode(sema, root, constraintExpr->nodeExprRef, bindings, outEvalRef);
        }

        if (sema.node(constraintRef).is(AstNodeId::ConstraintBlock))
        {
            const std::scoped_lock lock(genericEvalRunMutex());
            outEvalRef = findCachedGenericEvalNode(sema, root, constraintRef, bindings);
            if (outEvalRef.isValid())
            {
                if (sema.viewStored(outEvalRef, SemaNodeViewPartE::Constant).cstRef().isValid())
                    return Result::Continue;
            }
            else
            {
                outEvalRef = makeConstraintBlockRunNode(sema, constraintRef, bindings);
                cacheGenericEvalNode(sema, root, constraintRef, bindings, outEvalRef);
            }
            if (outEvalRef.isInvalid())
                return Result::Error;
            return runGenericNode(sema, root, outEvalRef);
        }

        return Result::Continue;
    }

    Diagnostic reportFunctionConstraintDiag(Sema& sema, DiagnosticId diagId, const SymbolFunction& function, AstNodeRef errorNodeRef, AstNodeRef whereRef, const Utf8& bindings)
    {
        const AstNodeRef mainRef = errorNodeRef.isValid() ? errorNodeRef : function.declNodeRef();
        auto             diag    = SemaError::report(sema, diagId, mainRef);
        diag.addArgument(Diagnostic::ARG_SYM, function.name(sema.ctx()));

        if (!bindings.empty())
        {
            diag.addNote(DiagnosticId::sema_note_generic_instantiated_with);
            diag.last().addArgument(Diagnostic::ARG_VALUES, bindings);
        }

        if (whereRef.isValid())
        {
            diag.addNote(DiagnosticId::sema_note_generic_where_declared_here);
            SemaError::addSpan(sema, diag.last(), whereRef);
        }

        return diag;
    }

    void fillFunctionConstraintFailure(Sema& sema, CastFailure& outFailure, DiagnosticId diagId, AstNodeRef whereRef, TypeRef typeRef, const Utf8& bindings)
    {
        outFailure            = {};
        outFailure.diagId     = diagId;
        outFailure.srcTypeRef = typeRef;
        if (whereRef.isValid())
            outFailure.noteCodeRef = sema.node(whereRef).codeRef();
        if (!bindings.empty())
            outFailure.addArgument(Diagnostic::ARG_VALUES, bindings);
    }

    Result raiseFunctionConstraintNotBool(Sema& sema, const SymbolFunction& function, AstNodeRef errorNodeRef, AstNodeRef whereRef, TypeRef typeRef, const Utf8& bindings)
    {
        auto diag = reportFunctionConstraintDiag(sema, DiagnosticId::sema_err_function_where_not_bool, function, errorNodeRef, whereRef, bindings);
        diag.addArgument(Diagnostic::ARG_TYPE, typeRef.isValid() ? sema.typeMgr().get(typeRef).toName(sema.ctx()) : Utf8{"<invalid>"});
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result raiseFunctionConstraintNotConst(Sema& sema, const SymbolFunction& function, AstNodeRef errorNodeRef, AstNodeRef whereRef, const Utf8& bindings)
    {
        const auto diag = reportFunctionConstraintDiag(sema, DiagnosticId::sema_err_function_where_not_const, function, errorNodeRef, whereRef, bindings);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result raiseFunctionConstraintFailed(Sema& sema, const SymbolFunction& function, AstNodeRef errorNodeRef, AstNodeRef whereRef, const Utf8& bindings)
    {
        const auto diag = reportFunctionConstraintDiag(sema, DiagnosticId::sema_err_function_where_failed, function, errorNodeRef, whereRef, bindings);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkFunctionWhereConstraints(Sema& sema, bool& outSatisfied, const SymbolFunction& function, std::span<const SemaClone::ParamBinding> bindings, const Utf8& bindingText, CastFailure* outFailure, AstNodeRef errorNodeRef)
    {
        outSatisfied = true;

        const auto* decl = genericFunctionDecl(function);
        if (!decl || decl->spanConstraintsRef.isInvalid())
            return Result::Continue;

        SmallVector<AstNodeRef> constraintRefs;
        sema.ast().appendNodes(constraintRefs, decl->spanConstraintsRef);
        for (const AstNodeRef constraintRef : constraintRefs)
        {
            if (!isWhereConstraint(sema, constraintRef))
                continue;

            AstNodeRef evalRef = AstNodeRef::invalid();
            SWC_RESULT(evalGenericConstraintNode(sema, function, constraintRef, bindings, evalRef));
            if (evalRef.isInvalid())
                continue;

            const SemaNodeView whereView = sema.viewNodeTypeConstant(evalRef);
            if (!whereView.typeRef().isValid() || !whereView.type()->isBool())
            {
                outSatisfied = false;
                if (outFailure)
                {
                    fillFunctionConstraintFailure(sema, *outFailure, DiagnosticId::sema_err_function_where_not_bool, constraintRef, whereView.typeRef(), bindingText);
                    return Result::Continue;
                }

                return raiseFunctionConstraintNotBool(sema, function, errorNodeRef, constraintRef, whereView.typeRef(), bindingText);
            }

            if (!whereView.cstRef().isValid())
            {
                outSatisfied = false;
                if (outFailure)
                {
                    fillFunctionConstraintFailure(sema, *outFailure, DiagnosticId::sema_err_function_where_not_const, constraintRef, TypeRef::invalid(), bindingText);
                    return Result::Continue;
                }

                return raiseFunctionConstraintNotConst(sema, function, errorNodeRef, constraintRef, bindingText);
            }

            if (whereView.cstRef() != sema.cstMgr().cstTrue())
            {
                outSatisfied = false;
                if (outFailure)
                {
                    fillFunctionConstraintFailure(sema, *outFailure, DiagnosticId::sema_err_function_where_failed, constraintRef, TypeRef::invalid(), bindingText);
                    return Result::Continue;
                }

                return raiseFunctionConstraintFailed(sema, function, errorNodeRef, constraintRef, bindingText);
            }
        }

        return Result::Continue;
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
            AstNodeRef evalRef = AstNodeRef::invalid();
            SWC_RESULT(evalGenericConstraintNode(sema, root, whereRef, bindings.span(), evalRef));
            if (evalRef.isInvalid())
                continue;

            const SemaNodeView whereView = sema.viewNodeTypeConstant(evalRef);
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
        const GenericImplBlockRunKey key{&sema.ctx(), &impl, declPass};
        auto                         initRun = [&] {
            auto child = std::make_unique<Sema>(sema.ctx(), sema, blockRef, declPass);
            SemaGeneric::prepareGenericInstantiationContext(*child, impl.asSymMap(), &impl, itf, attrs);
            return child;
        };
        return runCachedSema(sema, genericImplBlockRunMutex(), genericImplBlockRuns(), key, impl, initRun);
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

        const std::scoped_lock lock(genericEvalRunMutex());
        outClonedRef = findCachedGenericEvalNode(sema, root, sourceRef, bindings);
        if (outClonedRef.isValid())
        {
            if (sema.viewStored(outClonedRef, SemaNodeViewPartE::Constant).cstRef().isValid())
                return Result::Continue;
        }
        else
        {
            const SemaClone::CloneContext cloneContext{bindings};
            outClonedRef = SemaClone::cloneAst(sema, sourceRef, cloneContext);
            if (outClonedRef.isInvalid())
                return Result::Error;

            cacheGenericEvalNode(sema, root, sourceRef, bindings, outClonedRef);
        }

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

    Result finalizeResolvedGenericType(Sema& sema, SemaGeneric::GenericResolvedArg& ioArg)
    {
        if (!ioArg.typeRef.isValid())
            return Result::Continue;

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
            if (params[i].kind == SemaGeneric::GenericParamKind::Type)
                SWC_RESULT(finalizeResolvedGenericType(sema, ioResolvedArgs[i]));
            else
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

    void appendOwnerStructGenericKeys(Sema& sema, const SymbolFunction& function, SmallVector<GenericInstanceKey>& outKeys)
    {
        SmallVector<SemaGeneric::GenericParamDesc> ownerParams;
        SmallVector<GenericInstanceKey>            ownerArgs;
        if (!loadOwnerStructGenericArgs(sema, function, ownerParams, ownerArgs))
            return;

        for (const GenericInstanceKey& arg : ownerArgs)
            outKeys.push_back(arg);
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
        if (const auto* function = root.safeCast<SymbolFunction>())
            appendOwnerStructGenericKeys(sema, *function, keys);

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

        std::unique_ptr<Sema> sourceSemaHolder;
        Sema&                 sourceSema = semaForGenericDecl(sema, genericRoot, sourceSemaHolder);

        SmallVector<SemaGeneric::GenericParamDesc> params;
        if (genericRoot.decl())
            SemaGeneric::collectGenericParams(sourceSema, *genericRoot.decl(), spanRef, params);
        else
            SemaGeneric::collectGenericParams(sourceSema, spanRef, params);
        if (genericArgNodes.size() > params.size())
            return Result::Continue;

        const AstNodeRef                             errorNodeRef = genericArgNodes.empty() ? sema.curNodeRef() : genericArgNodes.front();
        SmallVector<SemaGeneric::GenericResolvedArg> resolvedArgs(params.size());
        for (size_t i = 0; i < genericArgNodes.size(); ++i)
            SWC_RESULT(SemaGeneric::resolveExplicitGenericArg(sema, params[i], genericArgNodes[i], resolvedArgs[i]));

        SWC_RESULT(materializeGenericArgs(sourceSema, genericRoot, params.span(), resolvedArgs.span(), genericArgNodes, errorNodeRef));
        if (SemaGeneric::hasMissingGenericArgs(resolvedArgs.span()))
            return Result::Continue;

        if (const auto* function = genericRoot.safeCast<SymbolFunction>())
        {
            SmallVector<SemaClone::ParamBinding> cloneBindings;
            buildGenericCloneBindings(params.span(), resolvedArgs.span(), cloneBindings);
            appendEnclosingGenericCloneBindings(sourceSema, *function, cloneBindings);
            const Utf8 bindingText = formatFunctionWhereBindings(sourceSema, *function, params.span(), resolvedArgs.span());
            bool       satisfied   = true;
            SWC_RESULT(checkFunctionWhereConstraints(sourceSema, satisfied, *function, cloneBindings.span(), bindingText, nullptr, errorNodeRef));
            if (!satisfied)
                return Result::Error;
        }

        return createGenericInstance(sourceSema, genericRoot, params.span(), resolvedArgs.span(), outInstance, errorNodeRef);
    }

    bool functionTypeParamShadowsTarget(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> targetParams)
    {
        const auto* function = sema.currentFunction();
        if (!function || !function->decl())
            return false;

        const auto* functionDecl = function->decl()->safeCast<AstFunctionDecl>();
        if (!functionDecl || !functionDecl->spanGenericParamsRef.isValid())
            return false;

        SmallVector<SemaGeneric::GenericParamDesc> functionParams;
        SemaGeneric::collectGenericParams(sema, *functionDecl, functionDecl->spanGenericParamsRef, functionParams);
        for (const SemaGeneric::GenericParamDesc& functionParam : functionParams)
        {
            if (functionParam.kind != SemaGeneric::GenericParamKind::Type)
                continue;

            for (const SemaGeneric::GenericParamDesc& targetParam : targetParams)
            {
                if (targetParam.kind == SemaGeneric::GenericParamKind::Type && targetParam.idRef == functionParam.idRef)
                    return true;
            }
        }

        return false;
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

    const SymbolStruct* enclosingGenericStructInstance(Sema& sema)
    {
        if (const SymbolStruct* instance = genericStructInstanceFromImplFrames(sema))
            return instance;
        return genericStructInstanceFromScopes(sema);
    }

    void resolveArgsFromEnclosingStruct(Sema& sema, const SymbolStruct& enclosingInstance, std::span<const SemaGeneric::GenericParamDesc> targetParams, std::span<SemaGeneric::GenericResolvedArg> resolvedArgs)
    {
        const SymbolStruct* enclosingRoot = enclosingInstance.genericRootSym();
        if (!enclosingRoot)
            return;

        const auto* enclosingDecl = genericStructDecl(*enclosingRoot);
        if (!enclosingDecl || !enclosingDecl->spanGenericParamsRef.isValid())
            return;

        SmallVector<SemaGeneric::GenericParamDesc> enclosingParams;
        SemaGeneric::collectGenericParams(sema, *enclosingDecl, enclosingDecl->spanGenericParamsRef, enclosingParams);

        SmallVector<GenericInstanceKey> enclosingArgs;
        if (!enclosingRoot->tryGetGenericInstanceArgs(enclosingInstance, enclosingArgs) || enclosingArgs.size() != enclosingParams.size())
            return;

        for (size_t targetIndex = 0; targetIndex < targetParams.size(); ++targetIndex)
        {
            for (size_t enclosingIndex = 0; enclosingIndex < enclosingParams.size(); ++enclosingIndex)
            {
                if (targetParams[targetIndex].idRef != enclosingParams[enclosingIndex].idRef ||
                    targetParams[targetIndex].kind != enclosingParams[enclosingIndex].kind)
                    continue;

                resolvedArgs[targetIndex].present = true;
                resolvedArgs[targetIndex].typeRef = enclosingArgs[enclosingIndex].typeRef;
                resolvedArgs[targetIndex].cstRef  = enclosingArgs[enclosingIndex].cstRef;
                break;
            }
        }
    }
}

namespace SemaGeneric
{
    Result evaluateFunctionWhereConstraints(Sema& sema, bool& outSatisfied, const SymbolFunction& function, CastFailure* outFailure)
    {
        std::unique_ptr<Sema>                sourceSemaHolder;
        Sema&                                sourceSema  = semaForGenericDecl(sema, function, sourceSemaHolder);
        const Utf8                           bindingText = formatFunctionWhereBindings(sourceSema, function);
        SmallVector<SemaClone::ParamBinding> cloneBindings;
        appendFunctionInstanceCloneBindings(sourceSema, function, cloneBindings);
        appendEnclosingGenericCloneBindings(sourceSema, function, cloneBindings);
        return checkFunctionWhereConstraints(sourceSema, outSatisfied, function, cloneBindings.span(), bindingText, outFailure, genericDeclNodeRef(function));
    }

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

        std::unique_ptr<Sema> sourceSemaHolder;
        Sema&                 sourceSema = semaForGenericDecl(sema, genericRoot, sourceSemaHolder);

        SmallVector<GenericParamDesc> params;
        collectGenericParams(sourceSema, *decl, decl->spanGenericParamsRef, params);
        if (params.empty())
            return Result::Continue;

        const AstNodeRef                errorNodeRef = sema.curNodeRef();
        SmallVector<GenericResolvedArg> resolvedArgs(params.size());
        SWC_RESULT(deduceGenericFunctionArgs(sema, genericRoot, params.span(), resolvedArgs, args, ufcsArg, outFailure, outFailureArgIndex));
        if (outFailure && outFailure->diagId != DiagnosticId::None)
            return Result::Continue;

        SWC_RESULT(materializeGenericArgs(sourceSema, genericRoot, params.span(), resolvedArgs.span(), {}, errorNodeRef));
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

        bool whereSatisfied = true;
        if (outFailure)
            *outFailure = {};
        SmallVector<SemaClone::ParamBinding> cloneBindings;
        buildGenericCloneBindings(params.span(), resolvedArgs.span(), cloneBindings);
        appendEnclosingGenericCloneBindings(sourceSema, genericRoot, cloneBindings);
        const Utf8   bindingText = formatFunctionWhereBindings(sourceSema, genericRoot, params.span(), resolvedArgs.span());
        CastFailure  localFailure;
        CastFailure* whereFailure = outFailure ? outFailure : &localFailure;
        SWC_RESULT(checkFunctionWhereConstraints(sourceSema, whereSatisfied, genericRoot, cloneBindings.span(), bindingText, whereFailure, errorNodeRef));
        if (!whereSatisfied)
            return Result::Continue;

        Symbol* instance = nullptr;
        SWC_RESULT(createGenericInstance(sourceSema, genericRoot, params.span(), resolvedArgs.span(), instance, errorNodeRef));
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
        Sema&                 targetSema = semaForGenericDecl(sema, genericRoot, targetSemaHolder);

        if (!hasGenericParams(genericRoot))
            return Result::Continue;

        const auto* targetDecl = genericStructDecl(genericRoot);
        if (!targetDecl)
            return Result::Continue;

        SmallVector<GenericParamDesc> targetParams;
        collectGenericParams(targetSema, *targetDecl, targetDecl->spanGenericParamsRef, targetParams);

        SmallVector<GenericResolvedArg> resolvedArgs(targetParams.size());

        if (!functionTypeParamShadowsTarget(sema, targetParams.span()))
        {
            if (const SymbolStruct* enclosingInstance = enclosingGenericStructInstance(sema))
                resolveArgsFromEnclosingStruct(sema, *enclosingInstance, targetParams.span(), resolvedArgs.span());
        }

        SWC_RESULT(materializeGenericArgs(targetSema, genericRoot, targetParams.span(), resolvedArgs.span(), {}, genericDeclNodeRef(genericRoot)));
        if (hasMissingGenericArgs(resolvedArgs.span()))
            return Result::Continue;

        Symbol* instance = nullptr;
        SWC_RESULT(createGenericInstance(targetSema, genericRoot, targetParams.span(), resolvedArgs.span(), instance, genericDeclNodeRef(genericRoot)));
        outInstance = instance ? &instance->cast<SymbolStruct>() : nullptr;
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
