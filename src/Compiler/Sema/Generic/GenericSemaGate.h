#pragma once
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

class GenericSemaGate
{
public:
    bool begin(const Symbol& symbol)
    {
        std::unique_lock lock(mutex_);
        const auto       currentThread = std::this_thread::get_id();

        // Recursive sema of the same generic instance on the same thread must
        // bail out, otherwise the thread would wait on work it is already doing.
        if (running_ && ownerThread_ == currentThread)
            return false;

        cv_.wait(lock, [&] {
            return !running_ || symbol.isSemaCompleted() || symbol.isIgnored();
        });

        if (symbol.isSemaCompleted() || symbol.isIgnored())
            return false;

        running_     = true;
        ownerThread_ = currentThread;
        return true;
    }

    void end()
    {
        {
            const std::scoped_lock lock(mutex_);
            running_     = false;
            ownerThread_ = {};
        }

        cv_.notify_all();
    }

private:
    mutable std::mutex      mutex_;
    std::condition_variable cv_;
    bool                    running_ = false;
    std::thread::id         ownerThread_;
};

SWC_END_NAMESPACE();
