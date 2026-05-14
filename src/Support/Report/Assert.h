#pragma once
SWC_BEGIN_NAMESPACE();

class TaskContext;

void swcPanic(const char* title, const char* file, int line, const char* expr = nullptr, std::string_view detail = {});
void swcAssert(const char* expr, const char* file, int line);
void swcInternalError(const char* file, int line, const char* expr = nullptr);

template<typename T>
constexpr T swcCheck(T value, const char* expr, const char* file, int line) noexcept
{
#if SWC_HAS_ASSERT
    if (!value)
        swcAssert(expr, file, line);
#endif
    return value;
}

template<typename T, typename U>
constexpr T swcCheckNot(T value, const U& passValue, const char* expr, const char* file, int line) noexcept
{
#if SWC_HAS_ASSERT
    if (value == passValue)
        swcAssert(expr, file, line);
#endif
    return value;
}

// Only enable assertions in debug builds
#if SWC_HAS_ASSERT
#define SWC_ASSERT(__expr)                          \
    do                                              \
    {                                               \
        if (!(__expr))                              \
        {                                           \
            swcAssert(#__expr, __FILE__, __LINE__); \
        }                                           \
    } while (0)
#else
#define SWC_ASSERT(__expr)                      \
    do                                          \
    {                                           \
        (void) sizeof((__expr) ? true : false); \
    } while (0)
#endif // SWC_HAS_ASSERT

#define SWC_INTERNAL_ERROR()                  \
    do                                        \
    {                                         \
        swcInternalError(__FILE__, __LINE__); \
        std::unreachable();                   \
    } while (0)

#define SWC_INTERNAL_CHECK(__expr)                         \
    do                                                     \
    {                                                      \
        if (!(__expr))                                     \
        {                                                  \
            swcInternalError(__FILE__, __LINE__, #__expr); \
            std::unreachable();                            \
        }                                                  \
    } while (0)

#define SWC_FORCE_ASSERT(__expr)                    \
    do                                              \
    {                                               \
        if (!(__expr))                              \
        {                                           \
            swcAssert(#__expr, __FILE__, __LINE__); \
        }                                           \
    } while (0)

#define SWC_UNREACHABLE()   \
    do                      \
    {                       \
        SWC_ASSERT(false);  \
        std::unreachable(); \
    } while (0)

#define SWC_CHECK(__expr)                   swcCheck((__expr), #__expr, __FILE__, __LINE__)
#define SWC_CHECK_NOT(__expr, __pass_value) swcCheckNot((__expr), (__pass_value), #__expr " != " #__pass_value, __FILE__, __LINE__)

#if SWC_DEV_MODE
class DevLoopGuard
{
public:
    DevLoopGuard(const char* label, const char* file, int line, const uint64_t maxIterations) noexcept :
        label_(label ? label : "<loop>"),
        file_(file),
        line_(line),
        maxIterations_(maxIterations)
    {
    }

    void tick() const
    {
        const uint64_t iteration = ++iteration_;
        if (iteration <= maxIterations_)
            return;

        const Utf8 detail = std::format("Loop: {}\nExceeded iteration budget: {}\nCurrent iteration: {}\n", label_, maxIterations_, iteration);
        swcPanic("DevMode loop guard triggered!", file_, line_, label_, detail.view());
    }

    void reset() const noexcept
    {
        iteration_.store(0, std::memory_order_release);
    }

private:
    const char*                   label_         = "<loop>";
    const char*                   file_          = nullptr;
    int                           line_          = 0;
    uint64_t                      maxIterations_ = 0;
    mutable std::atomic<uint64_t> iteration_{0};
};

#define SWC_DEV_LOOP_GUARD(__name, __max_iterations, __label) const swc::DevLoopGuard __name((__label), __FILE__, __LINE__, (__max_iterations))
#define SWC_DEV_LOOP_TICK(__name)                             (__name).tick()
#else
#define SWC_DEV_LOOP_GUARD(__name, __max_iterations, __label)
#define SWC_DEV_LOOP_TICK(__name) \
    do                            \
    {                             \
    } while (0)
#endif

SWC_END_NAMESPACE();
