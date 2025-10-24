#pragma once
#include "Os/Os.h"

SWC_BEGIN_NAMESPACE()

struct Timer
{
    explicit Timer(std::atomic<uint64_t>* dest) :
        destValue{dest}
    {
        start();
    }

    ~Timer()
    {
        stop();
    }

    void start()
    {
        timeBefore = Os::timerNow();
    }

    void stop() const
    {
        if (timeBefore)
            *destValue += Os::timerNow() - timeBefore;
    }

    std::atomic<uint64_t>* destValue;
    uint64_t               timeBefore = 0;
};

SWC_END_NAMESPACE()
