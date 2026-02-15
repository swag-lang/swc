#pragma once
SWC_BEGIN_NAMESPACE();

class TaskContext;

void swcAssert(const char* expr, const char* file, int line);
void swcInternalError(const char* file, int line);

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

template<typename T>
constexpr T* swcCheckNotNull(T* value, const char* expr, const char* file, int line) noexcept
{
#if SWC_HAS_ASSERT
    if (value == nullptr)
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
#define SWC_ASSERT(__expr) \
    do                     \
    {                      \
    } while (0)
#endif // SWC_HAS_ASSERT

#define SWC_INTERNAL_ERROR()                  \
    do                                        \
    {                                         \
        swcInternalError(__FILE__, __LINE__); \
        std::unreachable();                   \
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
#define SWC_CHECK_NOT_NULL(__expr)          swcCheckNotNull((__expr), #__expr " != nullptr", __FILE__, __LINE__)

SWC_END_NAMESPACE();
