#include "pch.h"
#include "Support/Thread/RaceCondition.h"
#if SWC_HAS_RACE_CONDITION
#include "Support/Report/Assert.h"
#endif

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_RACE_CONDITION

RaceCondition::RaceCondition(Instance* inst, Mode mode) :
    inst_(inst),
    mode_(mode)
{
    std::scoped_lock      lk(inst_->mu);
    const std::thread::id tid = std::this_thread::get_id();

    if (mode_ == Mode::Write)
    {
        // Writers are exclusive across threads; reentrancy by the same thread is OK.
        if (inst_->writer == std::thread::id{})
        {
            // The first writer requires all read guards to have been released.
            SWC_FORCE_ASSERT(inst_->readers == 0);

            inst_->writer     = tid;
            inst_->writeDepth = 1;
        }
        else
        {
            // Only the active writer can acquire a nested write guard.
            SWC_FORCE_ASSERT(inst_->writer == tid);
            ++inst_->writeDepth;
        }
    }
    else
    {
        // Reads are allowed if no writer, or if the current thread is the writer (re-entrant read).
        SWC_FORCE_ASSERT(inst_->writer == std::thread::id{} || inst_->writer == tid);
        ++inst_->readers;
    }
}

RaceCondition::~RaceCondition()
{
    if (!inst_)
        return;

    std::scoped_lock      lk(inst_->mu);
    const std::thread::id tid = std::this_thread::get_id();

    if (mode_ == Mode::Write)
    {
        // Only the owning writer thread should be destroying a writing guard.
        SWC_FORCE_ASSERT(inst_->writer == tid);
        SWC_FORCE_ASSERT(inst_->writeDepth > 0);

        if (--inst_->writeDepth == 0)
        {
            // Acquisition checks prevented foreign readers while the writer was active.
            inst_->writer = std::thread::id{};
        }
    }
    else
    {
        SWC_FORCE_ASSERT(inst_->readers > 0);
        --inst_->readers;
    }
}

#endif // SWC_HAS_RACE_CONDITION

SWC_END_NAMESPACE();
