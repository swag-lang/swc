#pragma once
#include "Backend/JIT/JIT.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

class JITExecManager
{
public:
    enum class Strategy : uint8_t
    {
        MainThreadQueued,
        Immediate,
    };

    struct Request
    {
        const SymbolFunction*        function = nullptr;
        AstNodeRef                   nodeRef  = AstNodeRef::invalid();
        SourceCodeRef                codeRef  = SourceCodeRef::invalid();
        uint64_t                     arg0     = 0;
        bool                         hasArg0  = false;
        std::span<const JITArgument> jitArgs;
        JITReturn                    jitReturn;
        bool                         hasJitReturn = false;
        bool                         runImmediate = false;
        std::function<void(Result)>  onCompleted;
    };

    struct Completion
    {
        bool   hasValue = false;
        Result result   = Result::Continue;
    };

    void       setStrategy(Strategy strategy) noexcept { strategy_ = strategy; }
    Strategy   strategy() const noexcept { return strategy_; }
    Result     submit(TaskContext& ctx, const Request& request);
    Completion consumeCompletion(const TaskContext& ctx, AstNodeRef nodeRef);
    bool       executePendingMainThread();

private:
    enum class Status : uint8_t
    {
        Pending,
        Running,
        Completed,
    };

    struct Item
    {
        TaskContext* ownerCtx = nullptr;
        Request      request;
        Status       status = Status::Pending;
        Result       result = Result::Continue;
    };

    static Result executeItem(const Item& item);

    mutable std::mutex                                            mutex_;
    std::unordered_map<const TaskContext*, std::unique_ptr<Item>> items_;
    Strategy                                                      strategy_ = Strategy::MainThreadQueued;
};

SWC_END_NAMESPACE();
