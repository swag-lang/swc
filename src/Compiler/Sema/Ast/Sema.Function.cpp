#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaPurity.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Helpers/SemaSymbolLookup.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool functionSignatureNeedsBody(const AstFunctionDecl& node)
    {
        return node.hasFlag(AstFunctionFlagsE::Short) && node.nodeReturnTypeRef.isInvalid();
    }

    SymbolFunction& registerFunctionSymbol(Sema& sema, const AstFunctionDecl& node)
    {
        if (!sema.curScope().isLocal())
            return SemaHelpers::registerSymbol<SymbolFunction>(sema, node, node.tokNameRef);

        const auto savedFrame = sema.frame();
        auto&      frame      = sema.frame();
        frame.setLookupScope(nullptr);
        frame.setLookupScopeOverrideNodes(nullptr);
        auto& sym    = SemaHelpers::registerSymbol<SymbolFunction>(sema, node, node.tokNameRef);
        sema.frame() = savedFrame;
        return sym;
    }

    SymbolMap* lazyGenericFunctionStartSymMap(const SymbolFunction& function)
    {
        return const_cast<SymbolMap*>(function.genericRootOrSelf()->ownerSymMap());
    }

    const SymbolImpl* functionDeclImplContext(Sema& sema, const SymbolFunction* symFunc = nullptr)
    {
        if (const auto* symImpl = sema.frame().currentImpl())
            return symImpl;

        if (symFunc)
        {
            if (const auto* symImpl = symFunc->declImplContext())
                return symImpl;
        }

        if (sema.curScopePtr())
        {
            for (SymbolMap* symMap = sema.curSymMap(); symMap; symMap = symMap->ownerSymMap())
            {
                if (symMap->isImpl())
                    return &symMap->cast<SymbolImpl>();
            }
        }

        return nullptr;
    }

    const SymbolInterface* functionDeclInterfaceContext(Sema& sema, const SymbolFunction* symFunc = nullptr)
    {
        if (const auto* symItf = sema.frame().currentInterface())
            return symItf;

        if (const auto* symImpl = sema.frame().currentImpl())
        {
            if (const auto* symItf = symImpl->symInterface())
                return symItf;
        }

        if (symFunc)
        {
            if (const auto* symItf = symFunc->declInterfaceContext())
                return symItf;
        }

        if (sema.curScopePtr())
        {
            for (SymbolMap* symMap = sema.curSymMap(); symMap; symMap = symMap->ownerSymMap())
            {
                if (symMap->isInterface())
                    return &symMap->cast<SymbolInterface>();

                if (symMap->isImpl())
                {
                    if (const auto* symItf = symMap->cast<SymbolImpl>().symInterface())
                        return symItf;
                }
            }
        }

        return nullptr;
    }

    Result isGenericRootImplFunction(Sema& sema, const SymbolFunction& sym, const SymbolImpl* declImpl, bool& outResult)
    {
        outResult = false;
        if (sym.isGenericInstance())
            return Result::Continue;

        const SymbolMap*    ownerMap = sym.ownerSymMap();
        const SymbolStruct* owner    = sym.ownerStruct();
        if (!owner && ownerMap && declImpl && declImpl->isForStruct())
            owner = declImpl->symStruct();
        if (!owner && ownerMap && declImpl)
        {
            MatchContext context;
            context.codeRef       = declImpl->codeRef();
            context.noWaitOnEmpty = true;
            SWC_RESULT(Match::match(sema, context, declImpl->idRef()));

            for (const Symbol* candidate : context.symbols())
            {
                if (!candidate || !candidate->isStruct())
                    continue;

                owner = &candidate->cast<SymbolStruct>();
                break;
            }
        }

        outResult = owner && owner->isGenericRoot() && !owner->isGenericInstance();
        return Result::Continue;
    }

    bool isGenericInstanceImplFunction(const SymbolFunction& sym, const SymbolImpl* declImpl)
    {
        const SymbolMap*    ownerMap = sym.ownerSymMap();
        const SymbolStruct* owner    = sym.ownerStruct();
        if (!owner && ownerMap && declImpl && declImpl->isForStruct())
            owner = declImpl->symStruct();

        return owner && owner->isGenericInstance();
    }

    bool isImplicitGeneratedLifecycleWrapper(Sema& sema, const SymbolFunction& sym)
    {
        if (!sym.attributes().hasRtFlag(RtAttributeFlagsE::Implicit))
            return false;

        return SemaSpecOp::isGeneratedLifecycleWrapperName(sym.name(sema.ctx()));
    }

    bool canDelayGenericInstanceFunctionBody(Sema& sema, const AstFunctionDecl& node, const SymbolFunction& sym, const SymbolImpl* declImpl)
    {
        if (sym.hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning))
            return false;
        if (sym.isGenericRoot() || sym.isGenericInstance() || sym.isEmpty())
            return false;
        if (sym.attributes().hasRtFlag(RtAttributeFlagsE::Macro) || sym.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
            return false;
        if (sym.specOpKind() != SpecOpKind::None)
            return false;
        if (!isGenericInstanceImplFunction(sym, declImpl))
            return false;
        if (isImplicitGeneratedLifecycleWrapper(sema, sym))
            return false;

        // Expression-bodied functions without an explicit return type need their body to
        // determine the signature, so they cannot participate in lazy body sema.
        if (node.hasFlag(AstFunctionFlagsE::Short) && node.nodeReturnTypeRef.isInvalid())
            return false;

        return node.nodeBodyRef.isValid();
    }

    struct LazyGenericBodyRun
    {
        const TaskContext*    ownerCtx = nullptr;
        bool                  running  = false;
        std::unique_ptr<Sema> sema;
    };

    bool isReentrantLazyGenericBodyRun(const Sema& sema, const SymbolFunction& calledFn, const LazyGenericBodyRun& run)
    {
        if (sema.currentFunction() == &calledFn)
            return true;

        if (sema.usesLocalLoweringPayloads())
            return false;

        // Semantic analysis can legitimately re-enter another lazy body owned by the same
        // task while generic dependencies are still being wired. Codegen uses a dedicated
        // Sema with local lowering mirrors, so it must never observe this "running means
        // good enough" shortcut.
        if (run.ownerCtx == &sema.ctx())
            return true;

        return run.sema.get() == &sema;
    }

    LazyGenericBodyRun* lazyGenericBodyRun(const SymbolFunction& calledFn)
    {
        const auto* state = calledFn.lazyGenericBodyRunState();
        if (!state || !(*state))
            return nullptr;

        return static_cast<LazyGenericBodyRun*>(state->get());
    }

    LazyGenericBodyRun& ensureLazyGenericBodyRun(const TaskContext& ctx, const SymbolFunction& calledFn)
    {
        auto& state = calledFn.ensureLazyGenericBodyRunState(ctx);
        if (!state)
        {
            // A paused lazy body is shared only between tasks waiting on the same
            // function, so keep it on that function instead of routing every lookup
            // through a compiler-wide mutex and map.
            state = std::make_shared<LazyGenericBodyRun>();
        }

        auto* run = static_cast<LazyGenericBodyRun*>(state.get());
        SWC_ASSERT(run != nullptr);
        return *run;
    }

    bool isCurrentLazyGenericBodySema(const Sema& sema, const SymbolFunction& calledFn)
    {
        const std::scoped_lock lock(calledFn.lazyGenericBodyRunMutex());
        const auto*            run = lazyGenericBodyRun(calledFn);
        if (!run)
            return false;

        return run->sema.get() == &sema;
    }

    Result waitForOtherLazyGenericBodyRunner(Sema& sema, const SymbolFunction& symbol)
    {
        if (!symbol.hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning))
            return Result::Continue;
        if (isCurrentLazyGenericBodySema(sema, symbol))
            return Result::Continue;

        return sema.waitSemaCompletedNoLazy(&symbol, symbol.codeRef());
    }

    std::unique_ptr<Sema> makeLazyGenericBodySema(Sema& sema, const SymbolFunction& calledFn, AstNodeRef declRef)
    {
        auto payloadContext = const_cast<NodePayload*>(calledFn.declNodePayloadContext());
        if (!payloadContext)
            payloadContext = sema.owningNodePayloadContext(calledFn.srcViewRef());

        std::unique_ptr<Sema> child;
        if (!payloadContext || payloadContext == &sema.currentNodePayloadContext())
        {
            child = std::make_unique<Sema>(sema.ctx(), sema, declRef);
        }
        else
        {
            if (declRef.isInvalid() && calledFn.decl())
            {
                declRef = sema.ownerDeclNodeRef(calledFn.srcViewRef(), calledFn.decl(), declRef);
            }
            SWC_ASSERT(declRef.isValid());
            child = std::make_unique<Sema>(sema.ctx(), sema, *payloadContext, declRef);
        }

        SemaGeneric::prepareGenericInstantiationContext(*child, lazyGenericFunctionStartSymMap(calledFn), functionDeclImplContext(sema, &calledFn), functionDeclInterfaceContext(sema, &calledFn), calledFn.attributes());
        return child;
    }

    void finishLazyGenericBodyRun(SymbolFunction& calledFn, Result result)
    {
        const std::scoped_lock lock(calledFn.lazyGenericBodyRunMutex());
        // Reset both run.running and LazyGenericBodyRunning atomically under the same
        // lock to prevent another task from seeing LazyGenericBodyRunning=false while
        // run.running is still true, which would cause it to wait on calledFn instead
        // of taking over the paused body — potentially deadlocking if that task is the
        // owner of a generic instance that calledFn's body is waiting for.
        calledFn.removeExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning);
        auto* state = calledFn.lazyGenericBodyRunState();
        if (!state || !(*state))
            return;

        auto* run = static_cast<LazyGenericBodyRun*>(state->get());
        SWC_ASSERT(run != nullptr);
        run->running = false;
        if (result != Result::Pause)
            state->reset();
    }

    Result completeLazyGenericFunctionImpl(Sema& sema, SymbolFunction& calledFn)
    {
        if (calledFn.isSemaCompleted())
            return Result::Continue;
        if (calledFn.isIgnored())
            return Result::Error;
        if (!calledFn.hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBody))
            return Result::Continue;
        if (calledFn.hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning))
        {
            const std::scoped_lock lock(calledFn.lazyGenericBodyRunMutex());
            const auto*            run = lazyGenericBodyRun(calledFn);
            if (run && run->running && isReentrantLazyGenericBodyRun(sema, calledFn, *run))
                return Result::Continue;
            return sema.waitSemaCompletedNoLazy(&calledFn, calledFn.codeRef());
        }

        const AstNodeRef declRef = calledFn.declNodeRef();
        if (declRef.isInvalid())
            return Result::Continue;

        Sema* child = nullptr;
        {
            const std::scoped_lock lock(calledFn.lazyGenericBodyRunMutex());
            auto&                  run = ensureLazyGenericBodyRun(sema.ctx(), calledFn);
            if (run.sema)
            {
                if (run.running)
                    return sema.waitSemaCompletedNoLazy(&calledFn, calledFn.codeRef());

                if (run.ownerCtx != &sema.ctx())
                {
                    // A paused child Sema carries the in-flight walk state for this lazy
                    // body. Transfer that state to the next waiting task instead of
                    // replaying the body on the shared AST and payload context.
                    run.ownerCtx = &sema.ctx();
                    run.sema->rebindTaskContext(sema.ctx());
                }
            }
            else
            {
                run.ownerCtx = &sema.ctx();
                run.sema     = makeLazyGenericBodySema(sema, calledFn, declRef);
            }

            run.running = true;
            child       = run.sema.get();
        }

        SWC_ASSERT(child);
        calledFn.addExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning);
        const Result result = child->execResult();
        finishLazyGenericBodyRun(calledFn, result);
        return result;
    }

    void registerRuntimeFunctionSymbol(Sema& sema, SymbolFunction& sym)
    {
        const SourceFile* file = sema.file();
        if (!file || !file->isRuntime())
            return;

        if (sym.isEmpty())
            return;

        const auto kind = sema.idMgr().runtimeFunctionKind(sym.idRef());
        if (kind == IdentifierManager::RuntimeFunctionKind::Count)
            return;

        sema.compiler().registerRuntimeFunctionSymbol(sym.idRef(), &sym);
    }

}

Result Sema::completeLazyGenericFunction(SymbolFunction& calledFn)
{
    return completeLazyGenericFunctionImpl(*this, calledFn);
}

Result Sema::prepareFunctionSignature(AstNodeRef functionRef)
{
    const auto* functionDecl = node(functionRef).safeCast<AstFunctionDecl>();
    if (!functionDecl)
        return Result::Continue;

    Symbol* symbol = viewSymbol(functionRef).sym();
    if (!symbol || !symbol->isFunction())
        return Result::Continue;

    const auto& sym = symbol->cast<SymbolFunction>();
    if (sym.isTyped() || functionSignatureNeedsBody(*functionDecl))
        return Result::Continue;

    Sema     functionSema(ctx(), *this, functionRef);
    AstNode& functionNode = functionSema.node(functionRef);
    Result   result       = functionSema.preNode(functionNode);
    if (result == Result::SkipChildren || sym.isTyped())
        return Result::Continue;
    if (result != Result::Continue)
        return result;

    const auto prepareChild = [&](AstNodeRef childRef) -> Result {
        if (childRef.isInvalid())
            return Result::Continue;

        Result childResult = functionSema.preNodeChild(functionNode, childRef);
        if (childResult != Result::Continue && childResult != Result::SkipChildren)
            return childResult;

        if (childResult != Result::SkipChildren)
        {
            Sema child(ctx(), functionSema, childRef);
            childResult = child.execResult();
            if (childResult != Result::Continue)
                return childResult;
        }

        return functionSema.postNodeChild(functionNode, childRef);
    };

    result = prepareChild(functionDecl->nodeParamsRef);
    if (result != Result::Continue || sym.isTyped())
        return result;

    return prepareChild(functionDecl->nodeReturnTypeRef);
}

Result AstFunctionDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = registerFunctionSymbol(sema, *this);

    sym.setExtraFlags(flags());
    sym.setDeclNodeRef(sema.curNodeRef());
    sym.setDeclNodePayloadContext(&sema.currentNodePayloadContext());
    sym.setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, sym));

    if (sym.ownerSymMap() &&
        sym.ownerSymMap()->isImpl() &&
        sym.specOpKind() != SpecOpKind::None &&
        sym.specOpKind() != SpecOpKind::Invalid)
    {
        sym.ownerSymMap()->cast<SymbolImpl>().addFunction(sema.ctx(), &sym);
    }

    sym.setGenericRoot(spanGenericParamsRef.isValid());
    if (nodeBodyRef.isInvalid())
        sym.addExtraFlag(SymbolFunctionFlagsE::Empty);
    registerRuntimeFunctionSymbol(sema, sym);

    return Result::SkipChildren;
}

Result AstFunctionDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);

    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    if (sym.isForeign())
        sym.setCallConvKind(sym.foreignCallConvKind());

    if (sym.isSemaCompleted())
        return Result::SkipChildren;

    const Result waitResult = waitForOtherLazyGenericBodyRunner(sema, sym);
    if (waitResult != Result::Continue)
        return waitResult;

    const auto* declImpl = functionDeclImplContext(sema, &sym);
    const auto* declItf  = functionDeclInterfaceContext(sema, &sym);
    if (sym.isMethod() && !declImpl && !declItf)
    {
        const SourceView& srcView   = sema.srcView(srcViewRef());
        const TokenRef    mtdTokRef = srcView.findLeftFrom(tokNameRef, {TokenId::KwdMtd});
        return SemaError::raise(sema, DiagnosticId::sema_err_method_outside_impl, SourceCodeRef{srcViewRef(), mtdTokRef});
    }

    bool genericRootImplFunction = false;
    SWC_RESULT(isGenericRootImplFunction(sema, sym, declImpl, genericRootImplFunction));
    if (genericRootImplFunction)
    {
        SWC_RESULT(SemaSpecOp::validateSymbol(sema, sym));
        sym.setSemaCompleted(sema.ctx());
        return Result::SkipChildren;
    }

    if (sym.isGenericRoot() && !sym.isGenericInstance())
    {
        SWC_RESULT(SemaSpecOp::validateSymbol(sema, sym));
        sym.setSemaCompleted(sema.ctx());
        return Result::SkipChildren;
    }

    SemaFrame frame           = sema.frame();
    frame.currentAttributes() = sym.attributes();
    frame.setCurrentImpl(declImpl);
    frame.setCurrentInterface(declItf);
    frame.setEnclosingFunction(sema.currentFunction());
    frame.setCurrentFunction(&sym);
    frame.setCurrentInlinePayload(nullptr);
    frame.setInlineContextRootRef(AstNodeRef::invalid());
    frame.setCurrentErrorContext(AstNodeRef::invalid(), SemaFrame::ErrorContextMode::None);
    sema.pushFramePopOnPostNode(frame);
    return Result::Continue;
}

Result AstFunctionExpr::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
    {
        TaskContext& ctx = sema.ctx();
        auto*        sym = Symbol::make<SymbolFunction>(ctx, this, tokRef(), SemaHelpers::getUniqueIdentifier(sema, "__lambda"), sema.frame().flagsForCurrentAccess());
        SymbolMap*   map = SemaFrame::currentSymMap(sema);
        SWC_ASSERT(map != nullptr);
        map->addSymbol(ctx, sym, true);

        sym->setExtraFlags(flags());
        sym->setDeclNodeRef(sema.curNodeRef());
        sym->setDeclNodePayloadContext(&sema.currentNodePayloadContext());
        sym->setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, *sym));
        sym->setDeclared(ctx);
        sema.setSymbol(sema.curNodeRef(), sym);

        SemaHelpers::addCurrentFunctionCallDependency(sema, sym);
    }

    auto&     sym   = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    SemaFrame frame = sema.frame();
    frame.setEnclosingFunction(sema.currentFunction());
    frame.setCurrentFunction(&sym);
    frame.setCurrentInlinePayload(nullptr);
    frame.setInlineContextRootRef(AstNodeRef::invalid());
    frame.setCurrentErrorContext(AstNodeRef::invalid(), SemaFrame::ErrorContextMode::None);
    sema.pushFramePopOnPostNode(frame);
    return Result::Continue;
}

Result AstClosureExpr::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
    {
        TaskContext& ctx = sema.ctx();
        auto*        sym = Symbol::make<SymbolFunction>(ctx, this, tokRef(), SemaHelpers::getUniqueIdentifier(sema, "__closure"), sema.frame().flagsForCurrentAccess());
        SymbolMap*   map = SemaFrame::currentSymMap(sema);
        SWC_ASSERT(map != nullptr);
        map->addSymbol(ctx, sym, true);

        sym->setExtraFlags(flags());
        sym->setDeclNodeRef(sema.curNodeRef());
        sym->setDeclNodePayloadContext(&sema.currentNodePayloadContext());
        sym->setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, *sym));
        sym->setDeclared(ctx);
        sema.setSymbol(sema.curNodeRef(), sym);

        SemaHelpers::addCurrentFunctionCallDependency(sema, sym);
    }

    auto&     sym   = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    SemaFrame frame = sema.frame();
    frame.setEnclosingFunction(sema.currentFunction());
    frame.setCurrentFunction(&sym);
    frame.setCurrentInlinePayload(nullptr);
    frame.setInlineContextRootRef(AstNodeRef::invalid());
    frame.setCurrentErrorContext(AstNodeRef::invalid(), SemaFrame::ErrorContextMode::None);
    sema.pushFramePopOnPostNode(frame);
    return Result::Continue;
}

namespace
{

    SymbolFunction& functionExprSymbol(Sema& sema, AstNodeRef nodeRef)
    {
        if (Symbol* sym = sema.viewSymbol(nodeRef).sym())
            return sym->cast<SymbolFunction>();

        const TypeRef typeRef = sema.viewType(nodeRef).typeRef();
        SWC_ASSERT(typeRef.isValid());
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        SWC_ASSERT(typeInfo.isFunction());
        return typeInfo.payloadSymFunction();
    }

    using SemaHelpers::resolveLambdaBindingFunction;

    Result deduceLambdaParameterTypeFromDefault(Sema& sema, AstNodeRef defaultValueRef, TypeRef& outTypeRef)
    {
        return SemaHelpers::deduceDefaultValueType(sema, defaultValueRef, outTypeRef);
    }

    Result finalizeLambdaParameterDefault(Sema& sema, const AstLambdaParam& param, SymbolVariable& symVar)
    {
        return SemaHelpers::finalizeDefaultValue(sema, param.nodeDefaultValueRef, symVar);
    }

    Result findCompatibleReturnBindingType(Sema& sema, AstNodeRef exprRef, TypeRef& outTypeRef)
    {
        outTypeRef = TypeRef::invalid();
        if (exprRef.isInvalid())
            return Result::Continue;

        const SemaNodeView exprView = sema.viewNodeTypeConstant(exprRef);
        const auto         frames   = sema.frames();
        for (size_t frameIndex = frames.size(); frameIndex > 0; --frameIndex)
        {
            const std::span<const TypeRef> bindingTypes = frames[frameIndex - 1].bindingTypes();
            for (size_t bindingIndex = bindingTypes.size(); bindingIndex > 0; --bindingIndex)
            {
                const TypeRef bindingTypeRef = bindingTypes[bindingIndex - 1];
                if (!bindingTypeRef.isValid())
                    continue;

                CastRequest castRequest(CastKind::Implicit);
                castRequest.errorNodeRef = exprRef;
                const Result castResult  = Cast::castAllowed(sema, castRequest, exprView.typeRef(), bindingTypeRef);
                if (castResult == Result::Pause)
                    return Result::Pause;
                if (castResult != Result::Continue)
                    continue;

                outTypeRef = bindingTypeRef;
                return Result::Continue;
            }
        }

        return Result::Continue;
    }

    Result concretizeImplicitReturnTypeIfNeeded(Sema& sema, AstNodeRef exprRef, TypeRef& ioTypeRef)
    {
        if (exprRef.isInvalid() || !ioTypeRef.isValid())
            return Result::Continue;

        SWC_RESULT(SemaHelpers::tryMaterializeAggregateLiteralConstant(sema, exprRef, ioTypeRef));

        const TypeInfo& typeInfo = sema.typeMgr().get(ioTypeRef);
        if (typeInfo.isScalarUnsized() && sema.viewConstant(exprRef).hasConstant())
        {
            const ConstantRef exprCstRef = sema.viewConstant(exprRef).cstRef();
            SWC_ASSERT(exprCstRef.isValid());

            ConstantRef concretizedCstRef = ConstantRef::invalid();
            SWC_RESULT(Cast::concretizeConstant(sema, concretizedCstRef, exprRef, exprCstRef, TypeInfo::Sign::Unknown));
            if (concretizedCstRef.isValid())
            {
                sema.setConstant(exprRef, concretizedCstRef);
                ioTypeRef = sema.cstMgr().get(concretizedCstRef).typeRef();
            }
        }

        const TypeInfo& concretizedTypeInfo = sema.typeMgr().get(ioTypeRef);
        if (concretizedTypeInfo.isIntUnsized())
        {
            TypeInfo::Sign sign = concretizedTypeInfo.payloadIntSign();
            if (sign == TypeInfo::Sign::Unknown)
                sign = TypeInfo::Sign::Signed;

            const TypeRef concreteTypeRef = sema.typeMgr().typeInt(32, sign);
            SemaNodeView  castView        = sema.viewNodeTypeConstant(exprRef);
            SWC_RESULT(Cast::cast(sema, castView, concreteTypeRef, CastKind::Implicit));
            ioTypeRef = concreteTypeRef;
        }
        else if (concretizedTypeInfo.isFloatUnsized())
        {
            const TypeRef concreteTypeRef = sema.typeMgr().typeF64();
            SemaNodeView  castView        = sema.viewNodeTypeConstant(exprRef);
            SWC_RESULT(Cast::cast(sema, castView, concreteTypeRef, CastKind::Implicit));
            ioTypeRef = concreteTypeRef;
        }

        const ConstantRef exprCstRef         = sema.viewConstant(exprRef).cstRef();
        const TypeRef     concretizedTypeRef = SemaHelpers::deduceConcretizedAggregateLiteralType(sema, ioTypeRef, exprCstRef);
        if (concretizedTypeRef != ioTypeRef)
        {
            SemaNodeView castView = sema.viewNodeTypeConstant(exprRef);
            SWC_RESULT(Cast::cast(sema, castView, concretizedTypeRef, CastKind::Implicit));
            ioTypeRef = concretizedTypeRef;
        }

        const ConstantRef exprTypeLikeCstRef    = sema.viewConstant(exprRef).cstRef();
        const TypeRef     normalizedTypeLikeRef = SemaHelpers::normalizeTypeLikeValueTypeRef(sema, ioTypeRef, exprTypeLikeCstRef, exprRef);
        if (normalizedTypeLikeRef != ioTypeRef)
        {
            SemaNodeView castView = sema.viewNodeTypeConstant(exprRef);
            SWC_RESULT(Cast::cast(sema, castView, normalizedTypeLikeRef, CastKind::Implicit));
            ioTypeRef = normalizedTypeLikeRef;
        }

        return Result::Continue;
    }

    Result inferCompilerRunBlockReturnType(Sema& sema, SymbolFunction& sym, AstNodeRef exprRef, TypeRef& outTypeRef)
    {
        outTypeRef = TypeRef::invalid();
        if (exprRef.isInvalid())
        {
            outTypeRef = sema.typeMgr().typeVoid();
            sym.setReturnTypeRef(outTypeRef);
            return Result::Continue;
        }

        SWC_RESULT(findCompatibleReturnBindingType(sema, exprRef, outTypeRef));
        if (!outTypeRef.isValid())
        {
            const SemaNodeView exprView = sema.viewNodeTypeConstant(exprRef);
            if (exprView.cstRef().isValid())
            {
                ConstantRef newCstRef = ConstantRef::invalid();
                SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, exprRef, exprView.cstRef(), TypeInfo::Sign::Unknown));
                if (newCstRef.isValid() && newCstRef != exprView.cstRef())
                    sema.setConstant(exprRef, newCstRef);
            }

            outTypeRef = sema.viewNodeTypeConstant(exprRef).typeRef();
            SWC_RESULT(concretizeImplicitReturnTypeIfNeeded(sema, exprRef, outTypeRef));
        }

        sym.setReturnTypeRef(outTypeRef);
        return Result::Continue;
    }

    bool canInferImplicitCompilerReturnType(const Sema& sema, const SymbolFunction& sym)
    {
        const AstNode* declNode = sym.decl();
        if (!declNode)
            return false;
        if (declNode->is(AstNodeId::CompilerRunBlock))
            return true;
        if (declNode->is(AstNodeId::CompilerFunc))
            return sema.token(declNode->codeRef()).id == TokenId::CompilerAst;
        return false;
    }

    bool payloadUsesCallerScope(const SemaInlinePayload* payload)
    {
        return payload &&
               payload->sourceFunction &&
               (payload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Macro) ||
                payload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin));
    }

    const SemaInlinePayload* resolveReturnContextPayload(const SemaInlinePayload* payload, const bool directInlineBody)
    {
        if (directInlineBody && payloadUsesCallerScope(payload) && !payload->returnsToCallerSite() && payload->returnTypeRef.isValid())
            return payload;

        return SemaInline::returnContextPayload(payload);
    }

    const SemaInlinePayload* nearestReturnContextPayload(Sema& sema)
    {
        const SemaInlinePayload* frameInlinePayload = sema.frame().currentInlinePayload();

        if (const auto* overridePayload = sema.inlineContextOverride<SemaInlineContextOverride>(sema.curNodeRef()))
            return SemaInline::returnContextPayload(overridePayload->targetInlinePayload);

        if (frameInlinePayload && sema.inlinePayload(sema.curNodeRef()) == frameInlinePayload)
            return resolveReturnContextPayload(frameInlinePayload, true);

        for (uint32_t i = 0;; ++i)
        {
            const AstNodeRef parentRef = sema.visit().parentNodeRef(i);
            if (parentRef.isInvalid())
                return resolveReturnContextPayload(frameInlinePayload, false);
            if (const auto* overridePayload = sema.inlineContextOverride<SemaInlineContextOverride>(parentRef))
                return SemaInline::returnContextPayload(overridePayload->targetInlinePayload);
            if (frameInlinePayload && sema.inlinePayload(parentRef) == frameInlinePayload)
                return resolveReturnContextPayload(frameInlinePayload, true);
        }
    }

    Result resolveReturnTypeRef(Sema& sema, AstNodeRef exprRef, TypeRef& outTypeRef)
    {
        outTypeRef                             = TypeRef::invalid();
        const SemaInlinePayload* inlinePayload = nearestReturnContextPayload(sema);
        if (inlinePayload)
        {
            outTypeRef = inlinePayload->returnTypeRef;
            return Result::Continue;
        }

        auto* sym = sema.currentFunction();
        SWC_ASSERT(sym);
        if (!sym)
            return Result::Error;

        outTypeRef = sym->returnTypeRef();
        if (!outTypeRef.isValid() && canInferImplicitCompilerReturnType(sema, *sym))
            return inferCompilerRunBlockReturnType(sema, *sym, exprRef, outTypeRef);

        return Result::Continue;
    }

    Result validateReturnStatementValue(Sema& sema, AstNodeRef returnRef, AstNodeRef exprRef, TypeRef returnTypeRef)
    {
        SWC_ASSERT(returnTypeRef.isValid());
        if (!returnTypeRef.isValid())
            return Result::Error;

        const TypeInfo& returnType = sema.typeMgr().get(returnTypeRef);
        if (exprRef.isValid())
        {
            const SemaNodeView exprTypeView = sema.viewType(exprRef);
            if (returnType.isVoid())
            {
                if (exprTypeView.type() && exprTypeView.type()->isVoid())
                    return Result::Continue;

                auto diag = SemaError::report(sema, DiagnosticId::sema_err_return_value_in_void, exprRef);
                if (const auto* currentFn = sema.currentFunction())
                {
                    diag.addArgument(Diagnostic::ARG_SYM, currentFn->name(sema.ctx()));
                    diag.addNote(DiagnosticId::sema_note_function_declared_here);
                    diag.last().addArgument(Diagnostic::ARG_SYM, currentFn->name(sema.ctx()));
                    diag.last().addSpan(currentFn->codeRange(sema.ctx()));
                }
                diag.report(sema.ctx());
                return Result::Error;
            }

            SemaNodeView view = sema.viewNodeTypeConstant(exprRef);
            if (returnType.isAnyTypeInfo(sema.ctx()))
                SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, view));
            SWC_RESULT(Cast::cast(sema, view, returnTypeRef, CastKind::Implicit));
            return Result::Continue;
        }

        if (!returnType.isVoid())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_return_missing_value, returnRef);
            diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, returnType.toName(sema.ctx()));
            if (const auto* currentFn = sema.currentFunction())
            {
                const auto* decl = currentFn->decl() ? currentFn->decl()->safeCast<AstFunctionDecl>() : nullptr;
                if (decl && decl->nodeReturnTypeRef.isValid())
                {
                    diag.addNote(DiagnosticId::sema_note_function_return_type_declared_here);
                    diag.last().addArgument(Diagnostic::ARG_REQUESTED_TYPE, returnType.toName(sema.ctx()));
                    SemaError::addSpan(sema, diag.last(), decl->nodeReturnTypeRef);
                }
                else
                {
                    diag.addNote(DiagnosticId::sema_note_function_declared_here);
                    diag.last().addArgument(Diagnostic::ARG_SYM, currentFn->name(sema.ctx()));
                    diag.last().addSpan(currentFn->codeRange(sema.ctx()));
                }
            }
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Continue;
    }

    bool lambdaHasExpressionBody(Sema& sema, AstNodeRef bodyRef)
    {
        return bodyRef.isValid() && sema.node(bodyRef).isNot(AstNodeId::EmbeddedBlock);
    }

    TypeRef resolveGroupedFunctionExprParameterType(Sema& sema, const SmallVector<AstNodeRef>& params, size_t paramIndex)
    {
        for (size_t nextParamIndex = paramIndex + 1; nextParamIndex < params.size(); nextParamIndex++)
        {
            const AstLambdaParam& nextParam = sema.node(params[nextParamIndex]).cast<AstLambdaParam>();
            if (nextParam.nodeTypeRef.isValid())
                return sema.viewType(nextParam.nodeTypeRef).typeRef();
        }

        return TypeRef::invalid();
    }

    void            addMeParameter(Sema& sema, SymbolFunction& sym);
    SymbolVariable* resolveBodyBindingReceiver(const Sema& sema, const SymbolFunction& sym);

    template<typename T>
    Result buildFunctionExprParameters(Sema& sema, const T& node, SymbolFunction& sym)
    {
        TaskContext&            ctx             = sema.ctx();
        const SymbolFunction*   bindingFunction = resolveLambdaBindingFunction(sema);
        SmallVector<AstNodeRef> params;
        sema.ast().appendNodes(params, node.spanArgsRef);

        if (sym.isMethod())
            addMeParameter(sema, sym);

        const IdentifierRef meId              = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
        const auto&         existingParams    = sym.parameters();
        const bool          hasReceiverParam  = !existingParams.empty() && existingParams.front() && existingParams.front()->idRef() == meId;
        const size_t        implicitParamSize = hasReceiverParam ? 1 : 0;
        if (existingParams.size() > implicitParamSize)
            return Result::Continue;

        size_t bindingParamOffset = 0;
        if (bindingFunction && hasReceiverParam)
        {
            const auto& bindingParams = bindingFunction->parameters();
            if (bindingParams.size() == params.size() + 1 &&
                bindingParams.front() &&
                bindingParams.front()->typeRef() == existingParams.front()->typeRef())
            {
                bindingParamOffset = 1;
            }
        }

        for (size_t paramIndex = 0; paramIndex < params.size(); paramIndex++)
        {
            const AstNodeRef      paramRef  = params[paramIndex];
            const AstLambdaParam& param     = sema.node(paramRef).cast<AstLambdaParam>();
            TypeRef               paramType = TypeRef::invalid();
            if (param.nodeTypeRef.isValid())
                paramType = sema.viewType(param.nodeTypeRef).typeRef();
            else if (bindingFunction)
            {
                const auto&  bindingParams = bindingFunction->parameters();
                const size_t bindingIndex  = paramIndex + bindingParamOffset;
                if (bindingIndex < bindingParams.size())
                    paramType = bindingParams[bindingIndex]->typeRef();
            }
            else if (param.nodeDefaultValueRef.isValid())
                SWC_RESULT(deduceLambdaParameterTypeFromDefault(sema, param.nodeDefaultValueRef, paramType));
            if (!paramType.isValid())
                paramType = resolveGroupedFunctionExprParameterType(sema, params, paramIndex);

            SWC_ASSERT(paramType.isValid());

            IdentifierRef idRef = IdentifierRef::invalid();
            if (param.hasFlag(AstLambdaParamFlagsE::Named))
            {
                const Token& tok = sema.token(param.codeRef());
                if (tok.id == TokenId::Identifier)
                    idRef = sema.idMgr().addIdentifier(ctx, param.codeRef());
            }

            auto* symVar = Symbol::make<SymbolVariable>(ctx, &param, param.tokRef(), idRef, SymbolFlagsE::Zero);
            symVar->setTypeRef(paramType);
            symVar->addExtraFlag(SymbolVariableFlagsE::Parameter);
            SWC_RESULT(finalizeLambdaParameterDefault(sema, param, *symVar));

            sym.addParameter(symVar);
            if (idRef.isValid())
                sym.addSymbol(ctx, symVar, false);

            symVar->setDeclared(ctx);
            symVar->setTyped(ctx);
            symVar->setSemaCompleted(ctx);
        }

        return Result::Continue;
    }

    template<typename T>
    Result prepareFunctionExprSignature(Sema& sema, const T& node, SymbolFunction& sym)
    {
        SWC_RESULT(buildFunctionExprParameters(sema, node, sym));

        if (sym.returnTypeRef().isValid())
            return Result::Continue;

        if (node.nodeReturnTypeRef.isValid())
        {
            const TypeRef returnTypeRef = sema.viewType(node.nodeReturnTypeRef).typeRef();
            SWC_RESULT(SemaCheck::noMoveRefType(sema, returnTypeRef, sema.node(node.nodeReturnTypeRef).codeRef()));
            sym.setReturnTypeRef(returnTypeRef);
            return Result::Continue;
        }

        if (const SymbolFunction* bindingFunction = resolveLambdaBindingFunction(sema))
        {
            sym.setReturnTypeRef(bindingFunction->returnTypeRef());
            return Result::Continue;
        }

        if (!lambdaHasExpressionBody(sema, node.nodeBodyRef))
            sym.setReturnTypeRef(sema.typeMgr().typeVoid());

        return Result::Continue;
    }

    template<typename T>
    Result finalizeFunctionExprSignature(Sema& sema, const T& node, SymbolFunction& sym)
    {
        SWC_RESULT(prepareFunctionExprSignature(sema, node, sym));

        if (!sym.returnTypeRef().isValid())
        {
            if (node.nodeBodyRef.isValid())
            {
                TypeRef returnTypeRef = sema.viewType(node.nodeBodyRef).typeRef();
                SWC_RESULT(concretizeImplicitReturnTypeIfNeeded(sema, node.nodeBodyRef, returnTypeRef));
                SWC_RESULT(SemaCheck::noMoveRefType(sema, returnTypeRef, sema.node(node.nodeBodyRef).codeRef()));
                sym.setReturnTypeRef(returnTypeRef);
            }
            else
                sym.setReturnTypeRef(sema.typeMgr().typeVoid());
        }

        sym.setVariadicParamFlag(sema.ctx());

        const TypeInfo ti      = TypeInfo::makeFunction(&sym, TypeInfoFlagsE::Zero);
        const TypeRef  typeRef = sema.typeMgr().addType(ti);
        sym.setTypeRef(typeRef);
        sym.setTyped(sema.ctx());

        SWC_RESULT(SemaCheck::isValidSignature(sema, sym.parameters(), false));
        SWC_RESULT(SemaSpecOp::validateSymbol(sema, sym));
        registerRuntimeFunctionSymbol(sema, sym);

        sema.setIsValue(sema.curNodeRef());
        sema.unsetIsLValue(sema.curNodeRef());
        return Result::Continue;
    }

    Result attachClosureExprRuntimeStorageIfNeeded(Sema& sema, const AstClosureExpr& node, const SymbolFunction& sym)
    {
        if (sema.isGlobalScope())
            return Result::Continue;
        if (!sym.typeRef().isValid())
            return Result::Continue;

        auto& payload = SemaHelpers::ensureCodeGenLoweringPayload(sema, sema.curNodeRef());
        if (payload.runtimeStorageSym == nullptr)
        {
            if (SymbolVariable* boundStorage = SemaHelpers::currentRuntimeStorage(sema))
            {
                payload.runtimeStorageSym = boundStorage;
                return Result::Continue;
            }

            payload.runtimeStorageSym = &SemaHelpers::registerUniqueRuntimeStorageSymbol(sema, node, "__closure_runtime_storage");
        }

        auto& storageSym = *payload.runtimeStorageSym;
        if (&storageSym == SemaHelpers::currentRuntimeStorage(sema))
            return Result::Continue;

        storageSym.addExtraFlag(SymbolVariableFlagsE::Initialized);
        if (!storageSym.typeRef().isValid())
            storageSym.setTypeRef(sym.typeRef());

        if (!storageSym.isDeclared())
        {
            storageSym.registerAttributes(sema);
            storageSym.setDeclared(sema.ctx());
            SWC_RESULT(Match::ghosting(sema, storageSym));
        }

        // Closure storage must live in the enclosing function, not the closure function
        // symbol currently being analysed.
        SymbolFunction* ownerFunction = sema.frame().enclosingFunction();
        if (!ownerFunction)
            ownerFunction = sema.currentFunction();
        if (!storageSym.isSemaCompleted() && ownerFunction)
        {
            const TypeInfo& symType = sema.typeMgr().get(sym.typeRef());
            SWC_RESULT(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
            ownerFunction->addLocalVariable(sema.ctx(), &storageSym);

            storageSym.setTyped(sema.ctx());
            storageSym.setSemaCompleted(sema.ctx());
        }

        return Result::Continue;
    }

    SymbolVariable* findClosureCaptureSymbol(const SymbolFunction& sym, const SymbolVariable& sourceVar)
    {
        std::vector<const Symbol*> symbols;
        sym.getAllSymbols(symbols, true);
        for (const Symbol* symbol : symbols)
        {
            const auto* captureSym = symbol ? symbol->safeCast<SymbolVariable>() : nullptr;
            if (!captureSym || !captureSym->isClosureCapture())
                continue;
            if (captureSym->closureCapturedSource() == &sourceVar)
                return const_cast<SymbolVariable*>(captureSym);
        }

        return nullptr;
    }

    IdentifierRef closureCaptureAliasIdentifier(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return IdentifierRef::invalid();

        const AstNode& node = sema.node(nodeRef);
        if (const auto* identifier = node.safeCast<AstIdentifier>())
            return SemaHelpers::resolveIdentifier(sema, identifier->codeRef());
        if (const auto* memberAccess = node.safeCast<AstMemberAccessExpr>())
            return closureCaptureAliasIdentifier(sema, memberAccess->nodeRightRef);
        if (const auto* ancestor = node.safeCast<AstAncestorIdentifier>())
            return closureCaptureAliasIdentifier(sema, ancestor->nodeIdentRef);

        return IdentifierRef::invalid();
    }

    IdentifierRef closureCaptureExplicitAliasIdentifier(Sema& sema, const AstClosureArgument& captureArg)
    {
        if (captureArg.tokAliasNameRef.isInvalid())
            return IdentifierRef::invalid();

        SourceCodeRef codeRef;
        codeRef.srcViewRef = captureArg.codeRef().srcViewRef;
        codeRef.tokRef     = captureArg.tokAliasNameRef;
        return sema.idMgr().addIdentifier(sema.ctx(), codeRef);
    }

    Result resolveClosureCaptureSourceSymbol(Sema& sema, AstNodeRef identifierRef, Symbol*& outSymbol)
    {
        outSymbol = sema.viewSymbol(identifierRef).sym();
        if (outSymbol)
            return Result::Continue;

        if (!SemaHelpers::effectiveInlinePayload(sema))
            return Result::Continue;

        const auto* identifier = sema.node(identifierRef).safeCast<AstIdentifier>();
        if (!identifier || !identifier->hasFlag(AstIdentifierFlagsE::InClosureCapture) || !identifier->codeRef().isValid())
            return Result::Continue;

        MatchContext lookupContext;
        lookupContext.codeRef = identifier->codeRef();
        SWC_RESULT(Match::match(sema, lookupContext, SemaHelpers::resolveIdentifier(sema, identifier->codeRef())));
        SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, identifierRef, false, lookupContext.symbols().span()));

        outSymbol = sema.viewSymbol(identifierRef).sym();
        return Result::Continue;
    }

    Result buildClosureCaptureSymbols(Sema& sema, const AstClosureExpr& node, SymbolFunction& sym)
    {
        TaskContext&            ctx = sema.ctx();
        SmallVector<AstNodeRef> captures;
        sema.ast().appendNodes(captures, node.nodeCaptureArgsRef);

        uint64_t captureOffset = 0;
        for (const AstNodeRef captureRef : captures)
        {
            const AstClosureArgument& captureArg = sema.node(captureRef).cast<AstClosureArgument>();
            Symbol*                   sourceSym  = nullptr;
            SymbolVariable*           sourceVar  = nullptr;
            TypeRef                   typeRef    = TypeRef::invalid();
            const bool                hasExplicitAlias = captureArg.tokAliasNameRef.isValid();

            if (hasExplicitAlias)
            {
                sourceSym = sema.viewSymbol(captureArg.nodeIdentifierRef).sym();
                if (sourceSym && sourceSym->isVariable())
                    sourceVar = &sourceSym->cast<SymbolVariable>();

                typeRef = sema.viewType(captureArg.nodeIdentifierRef).typeRef();
                SWC_ASSERT(typeRef.isValid());
            }
            else
            {
                SWC_RESULT(resolveClosureCaptureSourceSymbol(sema, captureArg.nodeIdentifierRef, sourceSym));
                if (!sourceSym)
                    return SemaError::raise(sema, DiagnosticId::sema_err_closure_capture_invalid, captureArg.nodeIdentifierRef);

                if (!sourceSym->isVariable())
                {
                    const auto diag = SemaError::report(sema, DiagnosticId::sema_err_closure_capture_invalid, captureArg.nodeIdentifierRef);
                    diag.report(sema.ctx());
                    return Result::Error;
                }

                sourceVar = &sourceSym->cast<SymbolVariable>();
                typeRef   = sourceVar->typeRef();
            }

            const TypeInfo& typeInfo  = sema.typeMgr().get(typeRef);
            SWC_RESULT(sema.waitSemaCompleted(&typeInfo, captureArg.nodeIdentifierRef));

            const bool captureByRef = captureArg.hasFlag(AstClosureArgumentFlagsE::Address);
            if (captureByRef && sourceVar && sourceVar->hasExtraFlag(SymbolVariableFlagsE::Let))
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_closure_capture_let_by_ref, captureArg.nodeIdentifierRef);
                diag.addArgument(Diagnostic::ARG_SYM, sourceVar->name(sema.ctx()));
                diag.report(sema.ctx());
                return Result::Error;
            }

            if (captureByRef && hasExplicitAlias && !sema.isLValue(captureArg.nodeIdentifierRef))
                return SemaError::raise(sema, DiagnosticId::sema_err_take_address_not_lvalue, captureArg.nodeIdentifierRef);

            // A by-value capture is a raw byte copy into the closure buffer: the environment never
            // runs 'opPostCopy' on the way in and never drops the captured value on the way out, so
            // only types without lifecycle operations can be captured by value.
            if (!captureByRef && !typeInfo.isAnyVariadic())
            {
                const TypeRef   unwrappedTypeRef = sema.typeMgr().unwrapAliasEnum(ctx, typeRef);
                const TypeRef   checkTypeRef     = unwrappedTypeRef.isValid() ? unwrappedTypeRef : typeRef;
                const TypeInfo& checkType        = sema.typeMgr().get(checkTypeRef);
                SWC_RESULT(sema.waitSemaCompleted(&checkType, captureArg.nodeIdentifierRef));

                const TypeGen::LifecycleFlags lifecycle = TypeGen::lifecycleFlagsOfTypeRef(ctx, checkTypeRef);
                if (lifecycle.hasDrop || lifecycle.hasPostCopy || lifecycle.hasPostMove || !lifecycle.canCopy)
                {
                    const DiagnosticId diagId = !lifecycle.canCopy ? DiagnosticId::sema_err_closure_capture_nocopy
                                                                   : DiagnosticId::sema_err_closure_capture_lifecycle;

                    auto diag = SemaError::report(sema, diagId, captureArg.nodeIdentifierRef);
                    diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
                    diag.report(ctx);
                    return Result::Error;
                }
            }

            uint32_t storageSize  = static_cast<uint32_t>(typeInfo.sizeOf(ctx));
            uint32_t storageAlign = typeInfo.alignOf(ctx);
            if (captureByRef || typeInfo.isAnyVariadic())
            {
                storageSize  = sizeof(void*);
                storageAlign = alignof(void*);
            }

            if (!storageAlign)
                storageAlign = 1;

            captureOffset = Math::alignUpU64(captureOffset, storageAlign);
            if (!hasExplicitAlias && sourceVar)
            {
                if (const SymbolVariable* existingCapture = findClosureCaptureSymbol(sym, *sourceVar))
                {
                    if (existingCapture->decl() == &captureArg)
                    {
                        captureOffset += storageSize;
                        continue;
                    }
                }
            }

            if (captureOffset + storageSize > Runtime::CLOSURE_CAPTURE_BUFFER_SIZE)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_closure_capture_too_large, captureArg.nodeIdentifierRef);
                diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
                diag.addArgument(Diagnostic::ARG_VALUE, Runtime::CLOSURE_CAPTURE_BUFFER_SIZE);
                diag.report(sema.ctx());
                return Result::Error;
            }

            IdentifierRef captureIdRef = hasExplicitAlias ? closureCaptureExplicitAliasIdentifier(sema, captureArg) : closureCaptureAliasIdentifier(sema, captureArg.nodeIdentifierRef);
            if (!captureIdRef.isValid())
            {
                SWC_ASSERT(sourceVar != nullptr);
                captureIdRef = sourceVar->idRef();
            }

            auto* captureSym = Symbol::make<SymbolVariable>(ctx, &captureArg, captureArg.tokRef(), captureIdRef, SymbolFlagsE::Zero);
            captureSym->setTypeRef(typeRef);
            captureSym->setClosureCapturedSource(sourceVar);
            captureSym->setClosureCaptureOffset(static_cast<uint32_t>(captureOffset));
            captureSym->setClosureCaptureByRef(captureByRef);

            if (captureByRef && sourceVar && sourceVar->hasExtraFlag(SymbolVariableFlagsE::Parameter))
                sourceVar->addExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);

            if (captureIdRef.isValid())
            {
                const Symbol* inserted = sym.addSingleSymbol(ctx, captureSym);
                if (inserted != captureSym)
                {
                    auto diag = SemaError::report(sema, DiagnosticId::sema_err_closure_capture_duplicate, captureArg.nodeIdentifierRef);
                    diag.addArgument(Diagnostic::ARG_SYM, captureIdRef);
                    diag.addNote(DiagnosticId::sema_note_previous_capture);
                    diag.last().addSpan(inserted->codeRange(ctx));
                    diag.report(ctx);
                    return Result::Error;
                }
            }

            captureSym->setDeclared(ctx);
            captureSym->setTyped(ctx);
            captureSym->setSemaCompleted(ctx);
            captureOffset += storageSize;
        }

        return Result::Continue;
    }

    TypeRef implOwnerTypeRef(const SymbolImpl& symImpl)
    {
        if (symImpl.isForStruct())
            return symImpl.symStruct()->typeRef();
        if (symImpl.isForEnum())
            return symImpl.symEnum()->typeRef();

        return TypeRef::invalid();
    }

    TypeRef implReceiverTypeRef(Sema& sema, const SymbolImpl& symImpl, bool isConstReceiver)
    {
        const TypeRef ownerType = implOwnerTypeRef(symImpl);
        if (!ownerType.isValid())
            return TypeRef::invalid();

        if (symImpl.isForEnum())
        {
            if (!isConstReceiver)
                return ownerType;

            TypeInfo typeInfo = sema.typeMgr().get(ownerType);
            typeInfo.addFlag(TypeInfoFlagsE::Const);
            return sema.typeMgr().addType(typeInfo);
        }

        TypeInfoFlags typeFlags = TypeInfoFlagsE::Zero;
        if (isConstReceiver)
            typeFlags.add(TypeInfoFlagsE::Const);
        return sema.typeMgr().addType(TypeInfo::makeReference(ownerType, typeFlags));
    }

    void addMeParameter(Sema& sema, SymbolFunction& sym)
    {
        const SymbolImpl* symImpl = sema.frame().currentImpl();
        if (!symImpl)
            return;

        const IdentifierRef meId = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
        if (!sym.parameters().empty())
        {
            const SymbolVariable* firstParam = sym.parameters().front();
            if (firstParam && firstParam->idRef() == meId)
            {
                return;
            }
        }

        const TypeRef receiverTypeRef = implReceiverTypeRef(sema, *symImpl, sym.hasExtraFlag(SymbolFunctionFlagsE::Const));
        if (!receiverTypeRef.isValid())
            return;

        TaskContext& ctx   = sema.ctx();
        auto*        symMe = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), meId, SymbolFlagsE::Zero);
        symMe->setTypeRef(receiverTypeRef);
        symMe->addExtraFlag(SymbolVariableFlagsE::Parameter);

        sym.addParameter(symMe);
        sym.addSymbol(ctx, symMe, true);
        symMe->setDeclared(ctx);
        symMe->setTyped(ctx);
    }

    SymbolVariable* resolveBodyBindingReceiver(const Sema& sema, const SymbolFunction& sym)
    {
        const auto& params = sym.parameters();
        if (params.empty())
            return nullptr;

        SymbolVariable* receiver = params[0];
        if (!receiver)
            return nullptr;

        if (receiver->idRef() != sema.idMgr().predefined(IdentifierManager::PredefinedName::Me))
            return nullptr;

        return receiver;
    }

}

Result AstFunctionDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (spanConstraintsRef.isValid())
    {
        SmallVector<AstNodeRef> constraintRefs;
        sema.ast().appendNodes(constraintRefs, spanConstraintsRef);
        for (const AstNodeRef constraintRef : constraintRefs)
        {
            if (childRef == constraintRef)
                return Result::SkipChildren;
        }
    }

    if (childRef == nodeParamsRef)
    {
        auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Parameters, childRef);
        sema.curScope().setSymMap(&sym);
        if (sym.isMethod())
            addMeParameter(sema, sym);
    }
    else if (childRef == nodeBodyRef)
    {
        auto&       sym      = sema.curViewSymbol().sym()->cast<SymbolFunction>();
        const auto* declImpl = functionDeclImplContext(sema, &sym);
        if (sym.isSemaCompleted())
            return Result::SkipChildren;

        const Result waitResult = waitForOtherLazyGenericBodyRunner(sema, sym);
        if (waitResult != Result::Continue)
            return waitResult;

        if (sym.isTyped() && canDelayGenericInstanceFunctionBody(sema, *this, sym, declImpl))
        {
            sym.addExtraFlag(SymbolFunctionFlagsE::LazyGenericBody);
            return Result::SkipChildren;
        }

        const bool deferInlineBodySema = sym.attributes().hasRtFlag(RtAttributeFlagsE::Mixin) || sym.attributes().hasRtFlag(RtAttributeFlagsE::Macro);
        if (deferInlineBodySema)
        {
            const bool shortWithoutExplicitReturnType = hasFlag(AstFunctionFlagsE::Short) && nodeReturnTypeRef.isInvalid();
            if (!shortWithoutExplicitReturnType)
                return Result::SkipChildren;
        }

        bool        whereSatisfied = true;
        CastFailure whereFailure;
        SWC_RESULT(SemaGeneric::evaluateFunctionWhereConstraints(sema, whereSatisfied, sym, &whereFailure));
        if (!whereSatisfied)
        {
            if (whereFailure.diagId == DiagnosticId::sema_err_function_where_failed)
            {
                sym.addExtraFlag(SymbolFunctionFlagsE::WhereConstraintFailed);
                return Result::SkipChildren;
            }

            bool directSatisfied = true;
            return SemaGeneric::evaluateFunctionWhereConstraints(sema, directSatisfied, sym, nullptr);
        }

        auto frame = sema.frame();
        if (SymbolVariable* receiver = resolveBodyBindingReceiver(sema, sym))
            frame.pushBindingVar(receiver);

        // Lookup-scope overrides are expression-local. A fresh function body must
        // start from its lexical scope or local declarations can miss themselves.
        frame.setLookupScope(nullptr);
        frame.setUpLookupScope(nullptr);
        frame.setIgnoreRuntimeAccess(false);
        frame.setCurrentErrorContext(AstNodeRef::invalid(), SemaFrame::ErrorContextMode::None);
        frame.pushBindingType(sym.returnTypeRef());
        sema.pushFramePopOnPostNode(frame);

        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
        sema.curScope().setSymMap(&sym);
    }

    return Result::Continue;
}

Result AstFunctionExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    SWC_RESULT(prepareFunctionExprSignature(sema, *this, sym));

    auto frame = sema.frame();
    frame.setLookupScope(nullptr);
    frame.setUpLookupScope(nullptr);
    frame.setIgnoreRuntimeAccess(false);
    frame.setCurrentErrorContext(AstNodeRef::invalid(), SemaFrame::ErrorContextMode::None);
    if (SymbolVariable* receiver = resolveBodyBindingReceiver(sema, sym))
        frame.pushBindingVar(receiver);
    if (sym.returnTypeRef().isValid())
        frame.pushBindingType(sym.returnTypeRef());
    sema.pushFramePopOnPostNode(frame);

    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    sema.curScope().setSymMap(&sym);
    return Result::Continue;
}

Result AstClosureExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    SWC_RESULT(prepareFunctionExprSignature(sema, *this, sym));
    SWC_RESULT(buildClosureCaptureSymbols(sema, *this, sym));

    auto frame = sema.frame();
    frame.setLookupScope(nullptr);
    frame.setUpLookupScope(nullptr);
    frame.setIgnoreRuntimeAccess(false);
    frame.setCurrentErrorContext(AstNodeRef::invalid(), SemaFrame::ErrorContextMode::None);
    if (SymbolVariable* receiver = resolveBodyBindingReceiver(sema, sym))
        frame.pushBindingVar(receiver);
    if (sym.returnTypeRef().isValid())
        frame.pushBindingType(sym.returnTypeRef());
    sema.pushFramePopOnPostNode(frame);

    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    sema.curScope().setSymMap(&sym);
    return Result::Continue;
}

Result AstFunctionDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();

    bool setIsTyped = false;
    if (hasFlag(AstFunctionFlagsE::Short))
    {
        if (nodeReturnTypeRef.isValid())
        {
            if (childRef == nodeReturnTypeRef)
            {
                sym.setReturnTypeRef(sema.viewType(nodeReturnTypeRef).typeRef());
                setIsTyped = true;
            }
            else if (childRef == nodeBodyRef)
            {
                SWC_RESULT(validateReturnStatementValue(sema, nodeBodyRef, nodeBodyRef, sym.returnTypeRef()));
            }
        }
        else if (childRef == nodeBodyRef)
        {
            TypeRef returnTypeRef = sema.viewType(nodeBodyRef).typeRef();
            SWC_RESULT(concretizeImplicitReturnTypeIfNeeded(sema, nodeBodyRef, returnTypeRef));
            sym.setReturnTypeRef(returnTypeRef);
            setIsTyped = true;
        }
    }
    else if (childRef == nodeReturnTypeRef || (childRef == nodeParamsRef && nodeReturnTypeRef.isInvalid()))
    {
        TypeRef returnType = sema.typeMgr().typeVoid();
        if (nodeReturnTypeRef.isValid())
            returnType = sema.viewType(nodeReturnTypeRef).typeRef();
        sym.setReturnTypeRef(returnType);
        setIsTyped = true;
    }

    if (setIsTyped)
    {
        if (sym.returnTypeRef().isValid() && sema.typeMgr().get(sym.returnTypeRef()).isCodeBlock())
            return SemaError::raiseCodeTypeRestricted(sema, nodeReturnTypeRef.isValid() ? nodeReturnTypeRef : childRef, sym.returnTypeRef());
        SWC_RESULT(SemaCheck::noMoveRefType(sema, sym.returnTypeRef(), sema.node(nodeReturnTypeRef.isValid() ? nodeReturnTypeRef : childRef).codeRef()));

        sym.setVariadicParamFlag(sema.ctx());

        const TypeInfo ti      = TypeInfo::makeFunction(&sym, TypeInfoFlagsE::Zero);
        const TypeRef  typeRef = sema.typeMgr().addType(ti);
        sym.setTypeRef(typeRef);
        sym.setTyped(sema.ctx());

        SWC_RESULT(SemaCheck::isValidSignature(sema, sym.parameters(), false));
        SWC_RESULT(SemaSpecOp::validateSymbol(sema, sym));
        if (!sym.isEmpty() && !sym.isGenericInstance())
            SWC_RESULT(Match::ghosting(sema, sym));

        registerRuntimeFunctionSymbol(sema, sym);
    }

    return Result::Continue;
}

Result AstFunctionExpr::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    return finalizeFunctionExprSignature(sema, *this, sym);
}

Result AstClosureExpr::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    SWC_RESULT(finalizeFunctionExprSignature(sema, *this, sym));
    return attachClosureExprRuntimeStorageIfNeeded(sema, *this, sym);
}

Result AstFunctionDecl::semaPostNode(Sema& sema)
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    if (sym.isGenericRoot() && !sym.isGenericInstance())
        return Result::Continue;

    if (sym.isSemaCompleted())
        return Result::Continue;

    const Result waitResult = waitForOtherLazyGenericBodyRunner(sema, sym);
    if (waitResult != Result::Continue)
        return waitResult;

    if (sym.hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBody) && !sym.hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning))
        return Result::Continue;

    if (sym.isForeign() && !sym.isEmpty())
        return SemaError::raise(sema, DiagnosticId::sema_err_foreign_cannot_have_body, sema.curNodeRef());

    if (sym.hasExtraFlag(SymbolFunctionFlagsE::WhereConstraintFailed))
    {
        sym.removeExtraFlag(SymbolFunctionFlagsE::LazyGenericBody);
        sym.removeExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning);
        sym.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    SemaPurity::computePurityFlag(sema, sym);
    sym.removeExtraFlag(SymbolFunctionFlagsE::LazyGenericBody);
    sym.removeExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning);
    sym.setSemaCompleted(sema.ctx());
    if (!sym.attributes().hasRtFlag(RtAttributeFlagsE::Macro) && !sym.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        sema.compiler().registerNativeCodeFunction(&sym);
    return Result::Continue;
}

Result AstFunctionExpr::semaPostNode(Sema& sema) const
{
    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    if (!sym.isTyped())
        SWC_RESULT(finalizeFunctionExprSignature(sema, *this, sym));

    SemaPurity::computePurityFlag(sema, sym);
    sym.setSemaCompleted(sema.ctx());
    if (!sym.attributes().hasRtFlag(RtAttributeFlagsE::Macro) && !sym.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        sema.compiler().registerNativeCodeFunction(&sym);
    return Result::Continue;
}

Result AstClosureExpr::semaPostNode(Sema& sema) const
{
    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    if (!sym.isTyped())
        SWC_RESULT(finalizeFunctionExprSignature(sema, *this, sym));

    SWC_RESULT(attachClosureExprRuntimeStorageIfNeeded(sema, *this, sym));
    SemaPurity::computePurityFlag(sema, sym);
    sym.setSemaCompleted(sema.ctx());
    if (!sym.attributes().hasRtFlag(RtAttributeFlagsE::Macro) && !sym.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        sema.compiler().registerNativeCodeFunction(&sym);
    return Result::Continue;
}

Result AstFunctionParamMe::semaPreNode(Sema& sema) const
{
    if (!sema.enteringState())
        return Result::Continue;

    // Generic specialization can pause and restart while walking the signature.
    // Reuse the receiver symbol already attached to this node instead of
    // registering a second `me` parameter on resume.
    if (sema.curViewSymbol().sym())
        return Result::Continue;

    const SymbolImpl* symImpl = sema.frame().currentImpl();
    if (!symImpl)
        return SemaError::raise(sema, DiagnosticId::sema_err_tok_outside_impl, sema.curNodeRef());

    TaskContext&        ctx       = sema.ctx();
    const TypeRef       ownerType = implOwnerTypeRef(*symImpl);
    const IdentifierRef idRef     = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
    const SymbolFlags   flags     = sema.frame().flagsForCurrentAccess();
    auto*               sym       = Symbol::make<SymbolVariable>(ctx, this, tokRef(), idRef, flags);
    SymbolMap*          symbolMap = SemaFrame::currentSymMap(sema);
    SWC_ASSERT(ownerType.isValid());

    if (SemaHelpers::currentLocalSymbolScope(sema))
        SemaHelpers::addCurrentScopeSymbol(sema, sym);
    else
        symbolMap->addSymbol(ctx, sym, true);

    SemaHelpers::handleSymbolRegistration(sema, symbolMap, sym);
    sym->registerCompilerIf(sema);
    sema.setSymbol(sema.curNodeRef(), sym);

    sym->setTypeRef(implReceiverTypeRef(sema, *symImpl, hasFlag(AstFunctionParamMeFlagsE::Const)));
    sym->setDeclared(ctx);
    sym->setTyped(ctx);
    sym->setSemaCompleted(ctx);

    return Result::Continue;
}

Result AstReturnStmt::semaPostNode(Sema& sema) const
{
    TypeRef returnTypeRef = TypeRef::invalid();
    SWC_RESULT(resolveReturnTypeRef(sema, nodeExprRef, returnTypeRef));
    return validateReturnStatementValue(sema, sema.curNodeRef(), nodeExprRef, returnTypeRef);
}

Result AstReturnStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeExprRef || childRef.isInvalid())
        return Result::Continue;

    TypeRef                  returnTypeRef = TypeRef::invalid();
    const SemaInlinePayload* inlinePayload = nearestReturnContextPayload(sema);
    if (inlinePayload)
    {
        returnTypeRef = inlinePayload->returnTypeRef;
    }
    else if (const SymbolFunction* currentFn = sema.currentFunction())
    {
        returnTypeRef = currentFn->returnTypeRef();
    }

    if (!returnTypeRef.isValid())
        return Result::Continue;

    auto frame = sema.frame();
    frame.pushBindingType(returnTypeRef);
    sema.pushFramePopOnPostChild(frame, childRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
