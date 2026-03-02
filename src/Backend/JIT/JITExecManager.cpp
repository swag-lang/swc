#include "pch.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/JIT/JIT.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

Result JITExecManager::executeItem(const Item& item)
{
    SWC_ASSERT(item.ownerCtx != nullptr);
    SWC_ASSERT(item.request.function != nullptr);
    SWC_ASSERT(item.request.function->jitEntryAddress() != nullptr);

    TaskContext&                ctx = *item.ownerCtx;
    const SymbolFunction* const fn  = item.request.function;

    const TaskScopedState scopedState(ctx);
    ctx.state().setRunJit(fn, item.request.nodeRef, item.request.codeRef);

    Result callResult;
    if (!item.request.jitArgs.empty() || item.request.hasJitReturn)
    {
        callResult = JIT::emitAndCall(ctx, fn->jitEntryAddress(), item.request.jitArgs, item.request.jitReturn);
    }
    else
    {
        auto callErrorKind = JITCallErrorKind::None;
        callResult         = JIT::call(ctx, fn->jitEntryAddress(), item.request.hasArg0 ? &item.request.arg0 : nullptr, &callErrorKind);
    }

    if (item.request.onCompleted)
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
        const Item immediateItem = {
            .ownerCtx = &ctx,
            .request  = request,
            .status   = Status::Completed,
            .result   = Result::Continue,
        };
        return executeItem(immediateItem);
    }

    const SymbolFunction* const function = request.function;
    const AstNodeRef            nodeRef  = request.nodeRef;
    const SourceCodeRef         codeRef  = request.codeRef;

    {
        const std::scoped_lock lock(mutex_);
        auto&                  slot = items_[&ctx];
        if (!slot)
        {
            slot           = std::make_unique<Item>();
            slot->ownerCtx = &ctx;
            slot->request  = request;
            slot->status   = Status::Pending;
            slot->result   = Result::Continue;
        }

        Item& item = *slot;
        if (item.status == Status::Pending || item.status == Status::Running)
        {
            SWC_ASSERT(item.request.nodeRef == nodeRef);
            SWC_ASSERT(item.request.function == function);
        }
        else
        {
            item.ownerCtx = &ctx;
            item.request  = request;
            item.status   = Status::Pending;
            item.result   = Result::Continue;
        }
    }

    ctx.state().setSemaWaitMainThreadRunJit(function, nodeRef, codeRef);
    return Result::Pause;
}

JITExecManager::Completion JITExecManager::consumeCompletion(const TaskContext& ctx, const AstNodeRef nodeRef)
{
    const std::scoped_lock lock(mutex_);
    const auto             it = items_.find(&ctx);
    if (it == items_.end() || !it->second)
        return {};

    const Item& item = *it->second;
    if (item.request.nodeRef != nodeRef)
        return {};

    if (item.status != Status::Completed)
        return {};

    const Result result = item.result;
    items_.erase(it);
    return {.hasValue = true, .result = result};
}

bool JITExecManager::executePendingMainThread()
{
    bool doneSomething = false;

    while (true)
    {
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
        }

        if (!itemToRun)
            break;

        const Result result = executeItem(*itemToRun);

        {
            const std::scoped_lock lock(mutex_);
            itemToRun->result = result;
            itemToRun->status = Status::Completed;
        }

        doneSomething = true;
    }

    return doneSomething;
}

SWC_END_NAMESPACE();
