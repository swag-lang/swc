#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    JobResult waitCodeGenPreSolved(TaskContext& ctx, const SymbolFunction& waiterSymbol, const Symbol& waitedSymbol, AstNodeRef nodeRef)
    {
        TaskState& wait   = ctx.state();
        wait.kind         = TaskStateKind::SemaWaitSymCodeGenPreSolved;
        wait.nodeRef      = nodeRef;
        wait.codeRef      = waiterSymbol.codeRef();
        wait.symbol       = &waitedSymbol;
        wait.waiterSymbol = &waiterSymbol;
        return JobResult::Sleep;
    }
}

CodeGenJob::CodeGenJob(const TaskContext& ctx, Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root) :
    Job(ctx, JobKind::CodeGen),
    sema_(&sema),
    symbolFunc_(&symbolFunc),
    root_(root)
{
    func = [this] {
        return exec();
    };
}

JobResult CodeGenJob::exec()
{
    SWC_ASSERT(sema_);
    SWC_ASSERT(symbolFunc_);
    ctx().state().reset();

    SmallVector<SymbolFunction*> deps;
    symbolFunc_->appendCallDependencies(deps);

    // Wait for sema completion on this function and all direct codegen dependencies.
    ///////////////////////////////////////////
    const Result selfWaitResult = sema_->waitSemaCompleted(symbolFunc_, symbolFunc_->codeRef());
    if (selfWaitResult != Result::Continue)
        return toJobResult(selfWaitResult);
    for (const auto* dep : deps)
    {
        const Result depWaitResult = sema_->waitSemaCompleted(dep, dep->codeRef());
        if (depWaitResult != Result::Continue)
            return toJobResult(depWaitResult);
    }

    // Schedule codegen jobs for dependencies that are not scheduled yet.
    ///////////////////////////////////////////
    for (auto* dep : deps)
    {
        if (!dep->tryMarkCodeGenJobScheduled())
            continue;
        const AstNodeRef depRoot = dep->declNodeRef();
        SWC_ASSERT(depRoot.isValid());
        CodeGenJob* depJob = heapNew<CodeGenJob>(ctx(), *sema_, *dep, depRoot);
        sema_->compiler().global().jobMgr().enqueue(*depJob, JobPriority::Normal, sema_->compiler().jobClientId());
    }

    // Generate micro instructions for this function and mark codegen as pre-solved.
    ///////////////////////////////////////////
    SWC_ASSERT(root_.isValid());
    CodeGen      codeGen(*sema_);
    const Result codeGenResult = codeGen.exec(*symbolFunc_, root_);
    if (codeGenResult != Result::Continue)
        return toJobResult(codeGenResult);
    symbolFunc_->setCodeGenPreSolved(ctx());

    // Lowered microcode persisted on the symbol for later materialization.
    ///////////////////////////////////////////
    symbolFunc_->emit(ctx());

    // Finalize only when dependency codegen is already pre-solved or completed.
    ///////////////////////////////////////////
    for (const auto* dep : deps)
    {
        if (!dep->isCodeGenPreSolved())
            return waitCodeGenPreSolved(ctx(), *symbolFunc_, *dep, root_);
    }

    symbolFunc_->setCodeGenCompleted(ctx());
    return JobResult::Done;
}

SWC_END_NAMESPACE();
