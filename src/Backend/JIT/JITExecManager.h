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

    struct ItemKey
    {
        const TaskContext* ownerCtx = nullptr;
        AstNodeRef         nodeRef  = AstNodeRef::invalid();

        bool operator==(const ItemKey& other) const noexcept
        {
            return ownerCtx == other.ownerCtx && nodeRef == other.nodeRef;
        }
    };

    struct ItemKeyHash
    {
        size_t operator()(const ItemKey& key) const noexcept
        {
            size_t h = std::hash<const TaskContext*>{}(key.ownerCtx);
            h ^= std::hash<uint32_t>{}(key.nodeRef.get()) + 0x9e3779b9u + (h << 6) + (h >> 2);
            return h;
        }
    };

    struct Item
    {
        TaskContext* ownerCtx = nullptr;
        Request      request;
        Status       status = Status::Pending;
        Result       result = Result::Continue;
    };

    static Result executeItem(const Item& item);

    mutable std::mutex                                              mutex_;
    std::unordered_map<ItemKey, std::unique_ptr<Item>, ItemKeyHash> items_;
    Strategy                                                        strategy_ = Strategy::MainThreadQueued;
};

SWC_END_NAMESPACE();
