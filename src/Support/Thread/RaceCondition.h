#pragma once

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_RACE_CONDITION
struct RaceCondition
{
    struct Instance
    {
        mutable std::mutex mu;
        std::thread::id    writer{};
        int                writeDepth = 0;
        int                readers    = 0;
    };

    enum class Mode
    {
        Read,
        Write
    };

    RaceCondition(Instance* inst, Mode mode);
    ~RaceCondition();

    RaceCondition(const RaceCondition&)            = delete;
    RaceCondition& operator=(const RaceCondition&) = delete;

    RaceCondition(RaceCondition&& other) noexcept :
        inst_(std::exchange(other.inst_, nullptr)),
        mode_(other.mode_)
    {
    }

    RaceCondition& operator=(RaceCondition&& other) noexcept
    {
        if (this != &other)
        {
            this->~RaceCondition();
            inst_ = std::exchange(other.inst_, nullptr);
            mode_ = other.mode_;
        }
        return *this;
    }

private:
    Instance* inst_{};
    Mode      mode_{Mode::Read};
};

#endif // SWC_HAS_RACE_CONDITION

// clang-format off
#if SWC_HAS_RACE_CONDITION
#define SWC_RACE_CONDITION_WRITE(__x)    RaceCondition _swc_rcg_write(&__x, RaceCondition::Mode::Write)
#define SWC_RACE_CONDITION_WRITE1(__x)   RaceCondition _swc_rcg_write1(&__x, RaceCondition::Mode::Write)
#define SWC_RACE_CONDITION_READ(__x)     RaceCondition _swc_rcg_read(&__x, RaceCondition::Mode::Read)
#define SWC_RACE_CONDITION_READ1(__x)    RaceCondition _swc_rcg_read1(&__x, RaceCondition::Mode::Read)
#define SWC_RACE_CONDITION_INSTANCE(__x) mutable RaceCondition::Instance __x
#else
#define SWC_RACE_CONDITION_WRITE(__x)    do { } while (0)
#define SWC_RACE_CONDITION_WRITE1(__x)   do { } while (0)
#define SWC_RACE_CONDITION_READ(__x)     do { } while (0)
#define SWC_RACE_CONDITION_READ1(__x)    do { } while (0)
#define SWC_RACE_CONDITION_INSTANCE(__x) using __dummy## __x = int
#endif
// clang-format on

SWC_END_NAMESPACE();
