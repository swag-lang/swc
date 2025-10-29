#pragma once

SWC_BEGIN_NAMESPACE()

struct Timer
{
    using Clock = std::chrono::steady_clock;
    using Tick  = Clock::time_point;

    explicit Timer(std::atomic<uint64_t>* dest) :
        destValue_{dest}
    {
        start();
    }

    ~Timer()
    {
        stop();
    }

    void start()
    {
        timeBefore_ = Clock::now();
    }

    void stop() const
    {
        if (started_)
        {
            const auto duration = Clock::now() - timeBefore_;
            *destValue_ += std::chrono::duration_cast<std::chrono::nanoseconds>(duration).count();
        }
    }

    static double toSeconds(uint64_t nanoseconds)
    {
        return static_cast<double>(nanoseconds) * 1e-9;
    }

private:
    std::atomic<uint64_t>* destValue_;
    Tick                   timeBefore_{};
    bool                   started_ = true;
};

SWC_END_NAMESPACE()
