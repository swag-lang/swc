#pragma once
SWC_BEGIN_NAMESPACE()

void swagAssert(const char* expr, const char* file, int line);

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

#define SWC_UNREACHABLE()   \
    do                      \
    {                       \
        SWC_ASSERT(false);  \
        std::unreachable(); \
    } while (0)

#else

#define SWC_ASSERT(__expr) \
    do                     \
    {                      \
    } while (0)

#define SWC_UNREACHABLE() \
    std::unreachable();

#endif // SWC_HAS_ASSERT

SWC_END_NAMESPACE()
