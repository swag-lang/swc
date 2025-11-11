#pragma once
SWC_BEGIN_NAMESPACE()

void swagAssert(const char* expr, const char* file, int line);

enum class Result : bool
{
    Error   = false,
    Success = true,
};

#define SWC_CHECK(__result)            \
    if ((__result) != Result::Success) \
    {                                  \
        do                             \
        {                              \
            return Result::Error;      \
        } while (0);                   \
    }

#define SWC_FORCE_ASSERT(__expr)                     \
    do                                               \
    {                                                \
        if (!(__expr))                               \
        {                                            \
            swagAssert(#__expr, __FILE__, __LINE__); \
        }                                            \
    } while (0)

// Only enable assertions in debug builds
#if SWC_HAS_ASSERT
#define SWC_ASSERT(__expr)                           \
    do                                               \
    {                                                \
        if (!(__expr))                               \
        {                                            \
            swagAssert(#__expr, __FILE__, __LINE__); \
        }                                            \
    } while (0)

#define SWC_UNREACHABLE() \
    SWC_ASSERT(false);    \
    std::unreachable();

#else

#define SWC_ASSERT(__expr) \
    do                     \
    {                      \
    } while (0)

#define SWC_UNREACHABLE() \
    std::unreachable();

#endif // SWC_HAS_ASSERT

SWC_END_NAMESPACE()
