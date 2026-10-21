#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
#if SWC_DEV_MODE
    void panicUnmaterializedCodeGenTarget(const TaskContext& ctx, const SymbolFunction& symbol)
    {
        const Utf8 detail = std::format("function: {}\ndeclaration node: {}\nsemantic analysis complete: {}\ncode generation pre-solved: {}\ncode generation complete: {}\nlazy body: {}\nlazy body running: {}\ngeneric root: {}\ngeneric instance: {}\nignored: {}\n",
                                        symbol.getFullScopedName(ctx),
                                        symbol.declNodeRef().isValid() ? symbol.declNodeRef().get() : 0,
                                        symbol.isSemaCompleted(),
                                        symbol.isCodeGenPreSolved(),
                                        symbol.isCodeGenCompleted(),
                                        symbol.hasExtraFlag(SymbolFunctionFlagsE::LazyBody),
                                        symbol.hasExtraFlag(SymbolFunctionFlagsE::LazyBodyRunning),
                                        symbol.isGenericRoot(),
                                        symbol.isGenericInstance(),
                                        symbol.isIgnored());
        swcPanic("code generation scheduled for an unmaterialized lazy body", __FILE__, __LINE__, "symbol.hasUnmaterializedLazyBody()", detail.view());
    }
#endif

    bool prepareWaitCodeGenPreSolved(TaskContext& ctx, const SymbolFunction& waiterSymbol, const Symbol& waitedSymbol, AstNodeRef nodeRef)
    {
        TaskState& wait   = ctx.state();
        wait.kind         = TaskStateKind::SemaWaitSymCodeGenPreSolved;
        wait.nodeRef      = nodeRef;
        wait.codeRef      = waiterSymbol.codeRef();
        wait.symbol       = &waitedSymbol;
        wait.waiterSymbol = &waiterSymbol;

        // Re-check after publishing the wait state: the dependency may finish
        // between the caller's check and the scheduler transition to Waiting.
        if (waitedSymbol.isCodeGenPreSolved() || waitedSymbol.isCodeGenCompleted())
        {
            ctx.state().setNone();
            return false;
        }

        return true;
    }

    JobResult abortCodeGen(TaskContext& ctx, SymbolFunction& symbolFunc, Result result)
    {
        if (result == Result::Error)
            symbolFunc.setIgnored(ctx);

        return Job::toJobResult(ctx, result);
    }
}

CodeGenJob::CodeGenJob(const TaskContext& ctx, Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root) :
    Job(ctx, JobKind::CodeGen),
    symbolFunc_(&symbolFunc),
    root_(root)
{
    // Generic clones retain source locations, so srcView alone can select the
    // wrong AST. Use the payload context that owns the function declaration.
    nodePayloadCtx_ = const_cast<NodePayload*>(symbolFunc.declNodePayloadContext());

    if (!nodePayloadCtx_)
        nodePayloadCtx_ = sema.owningNodePayloadContext(symbolFunc.srcViewRef());

    if (!nodePayloadCtx_)
    {
        const SourceFile* semaFile = sema.file();
        SWC_ASSERT(semaFile != nullptr);
        nodePayloadCtx_ = &sema.compiler().file(semaFile->ref()).nodePayloadContext();
    }
}

void CodeGenJob::initSemaAndCodeGen()
{
    SWC_ASSERT(nodePayloadCtx_ != nullptr);

    ownedSema_ = std::make_unique<Sema>(ctx(), *nodePayloadCtx_, false);
    ownedSema_->enableLocalLoweringPayloads();
    codeGen_ = std::make_unique<CodeGen>(*ownedSema_);
}

#if SWC_DEV_MODE
Utf8 CodeGenJob::statsLabel() const
{
    return symbolFunc_->getFullScopedName(ctx());
}
#endif

JobResult CodeGenJob::exec()
{
    const JobResult result = execImpl();

    // Finished jobs remain in the compiler until module end; release their
    // sema/codegen maps and stacks now. Sleeping jobs need them to resume.
    if (result != JobResult::Sleep)
        releaseSemaAndCodeGen();

    return result;
}

void CodeGenJob::releaseSemaAndCodeGen()
{
    codeGen_.reset();
    ownedSema_.reset();
}

JobResult CodeGenJob::execImpl()
{
    SWC_ASSERT(symbolFunc_);
    ctx().state().setNone();

    if (symbolFunc_->isIgnored())
        return abortCodeGen(ctx(), *symbolFunc_, Result::Error);
    if (symbolFunc_->isCodeGenCompleted())
        return JobResult::Done;

    if (symbolFunc_->attributes().hasMacroOrMixin())
    {
        symbolFunc_->setCodeGenPreSolved(ctx());
        symbolFunc_->setCodeGenCompleted(ctx());
        return JobResult::Done;
    }

    if (!ownedSema_)
        initSemaAndCodeGen();

    const Result selfWaitResult = sema().waitSemaCompleted(symbolFunc_, symbolFunc_->codeRef());
    if (selfWaitResult != Result::Continue)
        return abortCodeGen(ctx(), *symbolFunc_, selfWaitResult);

#if SWC_DEV_MODE
    if (symbolFunc_->hasUnmaterializedGenericBody())
        panicUnmaterializedCodeGenTarget(ctx(), *symbolFunc_);
#endif
    SWC_ASSERT(!symbolFunc_->hasUnmaterializedGenericBody());

    // Lifecycle intrinsics select operators after conditional impls have settled. A
    // rejected candidate means there is no hook; it is not a failed ordinary call.
    SmallVector<SymbolFunction*> lifecycleDependencies;
    symbolFunc_->appendLifecycleDependencies(lifecycleDependencies);
    for (const SymbolFunction* dependency : lifecycleDependencies)
    {
        if (dependency->isExcludedByCondition())
            continue;

        const Result waitResult = sema().waitSemaCompleted(dependency, dependency->codeRef());
        if (dependency->isExcludedByCondition())
        {
            ctx().state().setNone();
            continue;
        }

        if (waitResult != Result::Continue)
            return abortCodeGen(ctx(), *symbolFunc_, waitResult);
    }

    for (const SymbolFunction* dependency : lifecycleDependencies)
    {
        if (!dependency->isExcludedByCondition())
            symbolFunc_->addCallDependency(dependency);
    }

    SmallVector<SymbolFunction*> deps;
    symbolFunc_->appendCallDependencies(deps);

    // Sema can grow the call graph until completion. Codegen can discover more
    // helpers, so refresh dependencies again before declaring completion.
    for (const SymbolFunction* dep : deps)
    {
        const Result depWaitResult = sema().waitSemaCompleted(dep, dep->codeRef());
        if (depWaitResult != Result::Continue)
            return abortCodeGen(ctx(), *symbolFunc_, depWaitResult);

        if (dep->isIgnored())
            return abortCodeGen(ctx(), *symbolFunc_, Result::Error);
    }

    // Schedule dependencies before generating this body.
    for (SymbolFunction* dep : deps)
    {
        sema().compiler().tryEnqueueCodeGenJob(sema(), *dep, dep->declNodeRef());
    }

    // Sleeping jobs resume here without regenerating an already lowered body.
    if (!symbolFunc_->isCodeGenPreSolved())
    {
        // An optimized body reads the final clobbers of the leaf candidates it calls. Joining them
        // before lowering keeps nothing alive meanwhile: the body is then lowered and emitted in
        // one go. Only the dependencies analysis found count, since lowering adds the helpers it
        // calls and a lowering paused halfway resumes here.
        if (!loweringStarted_)
        {
            if (sema().compiler().buildCfg().backend.runsCostlyOptimizations())
            {
                const JobResult waitResult = waitLeafCalleesLowered(deps.span());
                if (waitResult != JobResult::Done)
                    return waitResult;
            }

            loweringStarted_ = true;
        }

        SWC_ASSERT(root_.isValid());
        const Result codeGenResult = codeGen_->exec(*symbolFunc_, root_);
        if (codeGenResult != Result::Continue)
            return abortCodeGen(ctx(), *symbolFunc_, codeGenResult);

        const MicroBuilder* builder = symbolFunc_->microInstrBuilder();
        readsCalleeClobbers_        = builder && builder->backendBuildCfg().runsCostlyOptimizations();
        symbolFunc_->classifyLoweredBody(directCallees_);
        symbolFunc_->setCodeGenPreSolved(ctx());
    }

    if (!bodyEmitted_)
    {
        // Lowering may call leaf helpers analysis did not see.
        if (readsCalleeClobbers_)
        {
            const JobResult waitResult = waitLeafCalleesLowered(directCallees_.span());
            if (waitResult != JobResult::Done)
                return waitResult;
        }

        const Result emitResult = symbolFunc_->emitOrReuse(ctx());
        if (emitResult != Result::Continue)
            return abortCodeGen(ctx(), *symbolFunc_, emitResult);
        bodyEmitted_ = true;
    }

    SmallVector<SymbolFunction*> finalDeps;
    symbolFunc_->appendCallDependencies(finalDeps);

    // Join every dependency seen after codegen, including newly discovered
    // helpers. Each must be lowered before this function is complete.
    for (SymbolFunction* dep : finalDeps)
    {
        const Result depWaitResult = sema().waitSemaCompleted(dep, dep->codeRef());
        if (depWaitResult != Result::Continue)
            return abortCodeGen(ctx(), *symbolFunc_, depWaitResult);

        if (dep->isIgnored())
            return abortCodeGen(ctx(), *symbolFunc_, Result::Error);

        sema().compiler().tryEnqueueCodeGenJob(sema(), *dep, dep->declNodeRef());

        if (!dep->isCodeGenPreSolved() && !dep->isCodeGenCompleted())
        {
            if (prepareWaitCodeGenPreSolved(ctx(), *symbolFunc_, *dep, root_))
                return JobResult::Sleep;
        }
    }

    symbolFunc_->setCodeGenCompleted(ctx());
    return JobResult::Done;
}

// A leaf candidate waits on no other function before its own lowering, since its analysis found
// nothing to call, so joining candidates adds no cycle. Their analysis is joined first: whether a
// callee is a candidate is only known once it is complete.
JobResult CodeGenJob::waitLeafCalleesLowered(const std::span<SymbolFunction* const> callees)
{
    for (SymbolFunction* callee : callees)
    {
        if (callee == symbolFunc_ || callee->isCodeGenPreSolved() || callee->isCodeGenCompleted())
            continue;

        const Result semaWaitResult = sema().waitSemaCompleted(callee, callee->codeRef());
        if (semaWaitResult != Result::Continue)
            return abortCodeGen(ctx(), *symbolFunc_, semaWaitResult);
        if (callee->isIgnored())
            return abortCodeGen(ctx(), *symbolFunc_, Result::Error);
        if (!callee->isSemaLeaf())
            continue;

        sema().compiler().tryEnqueueCodeGenJob(sema(), *callee, callee->declNodeRef());
        if (prepareWaitCodeGenPreSolved(ctx(), *symbolFunc_, *callee, root_))
            return JobResult::Sleep;
    }

    return JobResult::Done;
}

SWC_END_NAMESPACE();
