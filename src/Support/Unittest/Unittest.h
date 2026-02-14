#pragma once
#include "Main/TaskContext.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace Unittest
{
    using TestFn  = Result (*)(TaskContext&);
    using SetupFn = void (*)(TaskContext&);

    struct TestCase
    {
        const char* name = nullptr;
        TestFn      fn   = nullptr;
    };

    void   registerTest(TestCase test);
    void   registerSetup(SetupFn setupFn);
    Result runAll(TaskContext& ctx);

    class TestRegistrar
    {
    public:
        TestRegistrar(const char* name, TestFn fn)
        {
            registerTest({name, fn});
        }
    };

    class TestSetupRegistrar
    {
    public:
        explicit TestSetupRegistrar(SetupFn setupFn)
        {
            registerSetup(setupFn);
        }
    };
}

#define SWC_TEST_BEGIN(__name)                                             \
    namespace                                                              \
    {                                                                      \
        swc::Result                        __name(swc::TaskContext&);      \
        const swc::Unittest::TestRegistrar reg_##__name{#__name, &__name}; \
        swc::Result                        __name(swc::TaskContext& ctx)   \
        {
#define SWC_TEST_END()            \
    return swc::Result::Continue; \
    }                             \
    }

#endif

SWC_END_NAMESPACE();
