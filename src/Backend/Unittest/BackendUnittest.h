#pragma once
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace Backend::Unittest
{
    using BackendTestFn = void (*)(TaskContext&);

    struct BackendTestCase
    {
        const char*   name = nullptr;
        BackendTestFn fn   = nullptr;
    };

    void registerTest(BackendTestCase test);
    void runAll(TaskContext& ctx);

    class BackendTestRegistrar
    {
    public:
        BackendTestRegistrar(const char* name, BackendTestFn fn)
        {
            registerTest({name, fn});
        }
    };
}

#define SWC_BACKEND_TEST_BEGIN(__name)                                   \
    namespace                                                             \
    {                                                                     \
        void __name(swc::TaskContext& ctx);                               \
        const swc::Backend::Unittest::BackendTestRegistrar reg_##__name{#__name, &__name}; \
        void __name(swc::TaskContext& ctx)                                \
        {

#define SWC_BACKEND_TEST_END() \
    }                          \
    }

SWC_END_NAMESPACE();
