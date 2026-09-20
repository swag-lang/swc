#include "pch.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/JIT/JIT.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Report/Assert.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class JITExecManager::ExecJob final : public Job
{
public:
    static constexpr auto K = JobKind::JitExec;

    ExecJob(const TaskContext& ctx, JITExecManager& manager) :
        Job(ctx, JobKind::JitExec),
        manager_(&manager)
    {
    }

    JobResult exec() override
    {
        manager_->executePendingWorker();
        return JobResult::Done;
    }

private:
    JITExecManager* manager_ = nullptr;
};

JITExecManager::JITExecManager(CompilerInstance& compiler) :
    compiler_(&compiler)
{
}

Result JITExecManager::executeItem(Item& item)
{
    SWC_ASSERT(item.ownerCtx != nullptr);
    SWC_ASSERT(item.request.function != nullptr);
    SWC_ASSERT(item.request.function->jitEntryAddress() != nullptr);

    TaskContext&          ctx = item.executionCtx;
    const SymbolFunction* fn  = item.request.function;

    const TaskScopedContext scopedContext(ctx);
    const TaskScopedState   scopedState(ctx);
    ctx.state().setRunJit(fn, item.request.nodeRef, item.request.codeRef);

    const Result patchResult = ctx.compiler().ensurePatchedGlobalFunctionBindings(ctx);
    if (patchResult != Result::Continue)
    {
        if (patchResult == Result::Pause)
            item.waitState = ctx.state();
        else
            item.waitState.setNone();
        return patchResult;
    }

    Result callResult;
    if (!item.request.jitArgs.empty() || item.request.hasJitReturn)
    {
        callResult = JIT::emitAndCall(ctx, fn->jitEntryAddress(), item.request.jitArgs, item.request.jitReturn, fn->callConvKind());
    }
    else
    {
        auto callErrorKind = JITCallErrorKind::None;
        callResult         = JIT::call(ctx, fn->jitEntryAddress(), item.request.hasArg0 ? &item.request.arg0 : nullptr, &callErrorKind, item.request.runtimeSetupMode);
    }

    if (callResult == Result::Pause)
        item.waitState = ctx.state();
    else
        item.waitState.setNone();

    if (callResult != Result::Pause &&
        item.request.onCompleted)
        item.request.onCompleted(callResult);

    return callResult;
}

Result JITExecManager::submit(TaskContext& ctx, const Request& request)
{
    SWC_ASSERT(request.function != nullptr);
    SWC_ASSERT(request.function->jitEntryAddress() != nullptr);
    SWC_ASSERT(!(request.hasArg0 && (!request.jitArgs.empty() || request.hasJitReturn)));

    if (request.runImmediate || strategy_ == Strategy::Immediate)
    {
        Item immediateItem(ctx, request);
        // Immediate callers share the same execution lock as the background lane.
        // This preserves the JIT runtime's single-threaded global-state contract.
        const std::scoped_lock lock(executionMutex_);
        return executeItem(immediateItem);
    }

    const SymbolFunction* function = request.function;
    const AstNodeRef      nodeRef  = request.nodeRef;
    const SourceCodeRef   codeRef  = request.codeRef;
    const ItemKey         key      = {.ownerCtx = &ctx, .nodeRef = nodeRef, .codeRef = codeRef};

    // Publish the sleeping state before exposing the item to the worker. The worker
    // owns a copy of this context, so it cannot race the semantic job as it parks.
    ctx.state().setSemaWaitMainThreadRunJit(function, nodeRef, codeRef);

    bool enqueueWorker = false;
    {
        const std::scoped_lock lock(mutex_);
        // The key is the suspended sema location, not just the function. The same
        // compile-time function can be requested from multiple nodes with different
        // completion payloads.
        auto& slot = items_[key];
        if (!slot)
        {
            slot = std::make_unique<Item>(ctx, request);
            slot->waitState.setNone();
        }

        Item& item = *slot;
        if (item.status == Status::Pending ||
            item.status == Status::Running ||
            item.status == Status::Waiting)
        {
            SWC_ASSERT(item.request.nodeRef == nodeRef);
            SWC_ASSERT(item.request.function == function);
        }
        else
        {
            item = Item(ctx, request);
            item.waitState.setNone();
        }

        if (!workerScheduled_)
        {
            workerScheduled_ = true;
            enqueueWorker    = true;
        }
    }

    if (enqueueWorker)
        this->enqueueWorker();
    return Result::Pause;
}

void JITExecManager::enqueueWorker()
{
    SWC_ASSERT(compiler_ != nullptr);
    auto* job = compiler_->makeJob<ExecJob>(TaskContext(*compiler_), *this);
    compiler_->global().jobMgr().enqueue(*job, JobPriority::High, compiler_->jobClientId());
}

void JITExecManager::executePendingWorker()
{
    SWC_DEV_LOOP_GUARD(loopGuard, 1000000, "JITExecManager::executePendingWorker");

    while (true)
    {
        SWC_DEV_LOOP_TICK(loopGuard);
        Item* itemToRun = nullptr;
        {
            const std::scoped_lock lock(mutex_);
            for (auto& item : items_ | std::views::values)
            {
                if (!item || item->status != Status::Pending)
                    continue;
                item->status = Status::Running;
                itemToRun    = item.get();
                break;
            }

            if (!itemToRun)
            {
                workerScheduled_ = false;
                return;
            }
        }

        Result result;
        {
            const std::scoped_lock lock(executionMutex_);
            result = executeItem(*itemToRun);
        }

        if (result == Result::Pause)
        {
            const std::scoped_lock lock(mutex_);
            itemToRun->status = Status::Waiting;
            continue;
        }

        {
            const std::scoped_lock lock(mutex_);
            itemToRun->result = result;
            itemToRun->status = Status::Completed;
        }

        // waitDone consumes this persistent progress signal after the worker lane
        // drains, so completion cannot be lost while the owner job is parking.
        compiler_->notifyAlive();
    }
}

JITExecManager::Completion JITExecManager::consumeCompletion(const TaskContext& ctx, const AstNodeRef nodeRef, const SourceCodeRef& codeRef)
{
    const ItemKey          key = {.ownerCtx = &ctx, .nodeRef = nodeRef, .codeRef = codeRef};
    const std::scoped_lock lock(mutex_);
    const auto             it = items_.find(key);
    if (it == items_.end() || !it->second)
        return {};

    const Item& item = *it->second;
    if (item.status != Status::Completed)
        return {};

    Completion completion = {
        .hasValue          = true,
        .result            = item.result,
        .completionPayload = item.request.completionPayload,
    };
    items_.erase(it);
    return completion;
}

bool JITExecManager::hasItem(const TaskContext& ctx, const AstNodeRef nodeRef, const SourceCodeRef& codeRef) const
{
    const ItemKey          key = {.ownerCtx = &ctx, .nodeRef = nodeRef, .codeRef = codeRef};
    const std::scoped_lock lock(mutex_);
    const auto             it = items_.find(key);
    return it != items_.end() && it->second != nullptr;
}

bool JITExecManager::executePendingMainThread()
{
    bool processedAny = false;
    SWC_DEV_LOOP_GUARD(loopGuard, 1000000, "JITExecManager::executePendingMainThread");

    while (true)
    {
        SWC_DEV_LOOP_TICK(loopGuard);
        Item* itemToRun = nullptr;
        {
            const std::scoped_lock lock(mutex_);
            // Claim one item under the lock, then run it without holding the mutex:
            // JIT execution can re-enter compiler services and would otherwise deadlock
            // producers/consumers of the same queue.
            for (auto& item : items_ | std::views::values)
            {
                if (!item || item->status != Status::Pending)
                    continue;
                item->status = Status::Running;
                itemToRun    = item.get();
                break;
            }
        }

        if (!itemToRun)
            break;
        Result result;
        {
            const std::scoped_lock lock(executionMutex_);
            result = executeItem(*itemToRun);
        }

        {
            const std::scoped_lock lock(mutex_);
            if (result == Result::Pause)
            {
                // Retry only after the compiler reports fresh progress.
                itemToRun->status = Status::Waiting;
            }
            else
            {
                itemToRun->result = result;
                itemToRun->status = Status::Completed;
            }
        }

        if (result != Result::Pause)
            compiler_->notifyAlive();

        processedAny = true;
    }

    return processedAny;
}

bool JITExecManager::completeWaitingOnIgnoredDependency()
{
    bool completedAny = false;

    {
        const std::scoped_lock lock(mutex_);
        for (const auto& item : items_ | std::views::values)
        {
            if (!item || item->status != Status::Waiting)
                continue;

            const TaskState& waitState = item->waitState;
            if ((waitState.symbol && waitState.symbol->isIgnored()) ||
                (waitState.waiterSymbol && waitState.waiterSymbol->isIgnored()))
            {
                item->waitState.setNone();
                item->result = Result::Error;
                item->status = Status::Completed;
                completedAny = true;
            }
        }
    }

    if (completedAny)
        compiler_->notifyAlive();

    return completedAny;
}

bool JITExecManager::wakeWaiting()
{
    bool woken = false;
    bool enqueueWorker = false;

    {
        const std::scoped_lock lock(mutex_);
        for (const auto& item : items_ | std::views::values)
        {
            if (!item || item->status != Status::Waiting)
                continue;

            // The scheduler only tells us that compiler progress happened. Requeue every
            // waiting item and let executeItem re-check its exact dependency.
            item->status = Status::Pending;
            woken        = true;
        }

        if (woken && !workerScheduled_)
        {
            workerScheduled_ = true;
            enqueueWorker    = true;
        }
    }

    if (enqueueWorker)
        this->enqueueWorker();

    return woken;
}

#if SWC_DEV_MODE
Utf8 JITExecManager::debugDescribeState() const
{
    const std::scoped_lock lock(mutex_);

    Utf8 detail;
    for (const auto& item : items_ | std::views::values)
    {
        if (!item)
            continue;

        auto statusName = "Unknown";
        switch (item->status)
        {
            case Status::Pending:
                statusName = "Pending";
                break;
            case Status::Running:
                statusName = "Running";
                break;
            case Status::Waiting:
                statusName = "Waiting";
                break;
            case Status::Completed:
                statusName = "Completed";
                break;
        }

        detail += std::format("jit-item status={} function={}", statusName, item->request.function ? item->request.function->name(*item->ownerCtx) : "<null>");
        if (item->waitState.hasPauseReason())
        {
            detail += std::format(" wait={}", TaskState::kindName(item->waitState.kind));
            if (item->waitState.symbol)
                detail += std::format(" dependency={}", item->waitState.symbol->name(*item->ownerCtx));
            if (item->waitState.waiterSymbol)
                detail += std::format(" waiter={}", item->waitState.waiterSymbol->name(*item->ownerCtx));
        }

        detail += "\n";
    }

    return detail;
}
#endif

SWC_END_NAMESPACE();
