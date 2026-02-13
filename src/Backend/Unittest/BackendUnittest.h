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

#define SWC_BACKEND_TEST(__name)                                       \
    static void __name(swc::TaskContext& ctx);                         \
    static const swc::Backend::Unittest::BackendTestRegistrar reg_##__name{#__name, &__name}; \
    static void __name(swc::TaskContext& ctx)

SWC_END_NAMESPACE();
