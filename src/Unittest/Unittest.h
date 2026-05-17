#pragma once
#include "Main/TaskContext.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace Unittest
{
    enum class TestKind : uint8_t
    {
        Fast,
        Filesystem,
    };

    using TestFn  = Result (*)(TaskContext&);
    using SetupFn = void (*)(TaskContext&);

    struct TestCase
    {
        const char* name = nullptr;
        TestFn      fn   = nullptr;
        TestKind    kind = TestKind::Fast;
    };

    void   registerTest(TestCase test);
    void   registerSetup(SetupFn setupFn);
    Result runAll(const TaskContext& ctx);

    class TestRegistrar
    {
    public:
        TestRegistrar(const char* name, TestFn fn, TestKind kind)
        {
            registerTest({name, fn, kind});
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

#ifndef SWC_TEST_KIND
#define SWC_TEST_KIND swc::Unittest::TestKind::Fast
#endif

// Fast DevMode unit tests run on every compiler launch. By design they must never touch the filesystem:
// no creating/removing directories, no reading/writing files, and no depending on materialized build outputs.
// Any test that needs filesystem access must opt into SWC_FILESYSTEM_TEST_BEGIN so it only runs with --dev-full.
#define SWC_TEST_BEGIN(__name)                                                            \
    namespace                                                                             \
    {                                                                                     \
        swc::Result                        __name(swc::TaskContext&);                     \
        const swc::Unittest::TestRegistrar reg_##__name{#__name, &__name, SWC_TEST_KIND}; \
        swc::Result                        __name(swc::TaskContext& ctx)                  \
        {
#define SWC_FILESYSTEM_TEST_BEGIN(__name)                                                                       \
    namespace                                                                                                   \
    {                                                                                                           \
        swc::Result                        __name(swc::TaskContext&);                                           \
        const swc::Unittest::TestRegistrar reg_##__name{#__name, &__name, swc::Unittest::TestKind::Filesystem}; \
        swc::Result                        __name(swc::TaskContext& ctx)                                        \
        {
#define SWC_TEST_END()            \
    return swc::Result::Continue; \
    }                             \
    }

#endif

SWC_END_NAMESPACE();
