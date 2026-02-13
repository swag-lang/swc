#pragma once
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace Unittest
{
    using TestFn  = void (*)(TaskContext&);
    using SetupFn = void (*)(TaskContext&);

    struct TestCase
    {
        const char* name = nullptr;
        TestFn      fn   = nullptr;
    };

    void registerTest(TestCase test);
    void registerSetup(SetupFn setupFn);
    void runAll(TaskContext& ctx);

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
        void                               __name(swc::TaskContext&);      \
        const swc::Unittest::TestRegistrar reg_##__name{#__name, &__name}; \
        void                               __name(swc::TaskContext& ctx)   \
        {
#define SWC_TEST_END() \
    }                  \
    }

SWC_END_NAMESPACE();
