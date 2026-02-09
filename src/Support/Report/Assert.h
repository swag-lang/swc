#pragma once
SWC_BEGIN_NAMESPACE();

class TaskContext;

void              swcAssert(const char* expr, const char* file, int line);
[[noreturn]] void swcInternalError(const TaskContext& ctx, const char* file, int line);

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
#define SWC_ASSERT(__expr) \
    do                     \
    {                      \
    } while (0)
#endif // SWC_HAS_ASSERT

#define SWC_INTERNAL_ERROR(__ctx)                    \
    do                                               \
    {                                                \
        swcInternalError(__ctx, __FILE__, __LINE__); \
        std::unreachable();                          \
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

SWC_END_NAMESPACE();
