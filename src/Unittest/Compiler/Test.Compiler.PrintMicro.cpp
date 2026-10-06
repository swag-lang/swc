#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Os/Os.h"
#include "Unittest/Compiler/CompilerTestFile.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view PRINT_MICRO_SOURCE = R"(#global private
func addOne(value: s32)->s32 => value + 1
func subOne(value: s32)->s32 => value - 1
namespace Inner { func addTwo(value: s32)->s32 => value + 2 }

#run
{
    Swag.assert(addOne(1) == 2)
    Swag.assert(subOne(1) == 0)
    Swag.assert(Inner.addTwo(1) == 3)
}
)";

    struct PrintMicroRun
    {
        Os::ProcessRunResult process  = Os::ProcessRunResult::StartFailed;
        uint32_t             exitCode = UINT32_MAX;
        std::string          output;
    };

    Result runPrintMicro(PrintMicroRun& run, const fs::path& directory, std::span<const std::string_view> requests)
    {
        const fs::path source = directory / "print_micro.swg";
        SWC_RESULT(CompilerTestFile::writeText(source, PRINT_MICRO_SOURCE));

        std::vector<Utf8> args = {"sema", "--num-cores", "6", "--no-log-color", "-f", Utf8(source.string())};
        for (const std::string_view request : requests)
        {
            args.emplace_back("--print-micro");
            args.emplace_back(request);
        }

        Os::ProcessRunOptions options;
        options.capturedOutput = &run.output;
        options.forwardOutput  = false;
        options.timeoutMs      = 15000;
        run.process            = Os::runProcess(run.exitCode, Os::getExeFullName(), args, directory, &options);
        return Result::Continue;
    }

    // Each listing names its function, fully scoped, on a header line of its own.
    size_t countListings(std::string_view output, std::string_view scopedName)
    {
        constexpr std::string_view HEADER = "function : ";
        size_t                     count  = 0;
        for (size_t pos = output.find(HEADER); pos != std::string_view::npos; pos = output.find(HEADER, pos + HEADER.size()))
        {
            const size_t start = pos + HEADER.size();
            const size_t end   = output.find_first_of("\r\n", start);
            if (output.substr(start, end == std::string_view::npos ? std::string_view::npos : end - start) == scopedName)
                count++;
        }

        return count;
    }
}

SWC_FILESYSTEM_TEST_BEGIN(Compiler_PrintMicroSelectsFunctionsFromTheCommandLine)
{
    const fs::path  directory = (Os::getTemporaryPath() / "swc_unittest" / "print_micro" / std::format("p{}", Os::currentProcessId())).lexically_normal();
    std::error_code ec;
    fs::remove_all(directory, ec);

    struct Case
    {
        std::vector<std::string_view> requests;
        size_t                        addOneListings = 0;
        size_t                        subOneListings = 0;
        size_t                        addTwoListings = 0;
        std::string_view              stage;
    };

    const Case cases[] = {
        {{"addOne"}, 1, 0, 0, "pre-emit"},
        {{"Inner.addTwo"}, 0, 0, 1, "pre-emit"},
        {{"addTwo"}, 0, 0, 1, "pre-emit"},
        {{"nner.addTwo"}, 0, 0, 0, {}},
        {{"*One"}, 1, 1, 0, "pre-emit"},
        {{"add*"}, 1, 0, 1, "pre-emit"},
        {{"subOne:post-emit"}, 0, 1, 0, "post-emit"},
        {{"addOne", "addOne:post-emit"}, 2, 0, 0, "post-emit"},
        {{"missing"}, 0, 0, 0, {}},
    };

    Result result = Result::Continue;
    for (const Case& test : cases)
    {
        PrintMicroRun run;
        SWC_RESULT(runPrintMicro(run, directory, test.requests));
        if (run.process != Os::ProcessRunResult::Ok || run.exitCode != 0 ||
            countListings(run.output, "addOne") != test.addOneListings ||
            countListings(run.output, "subOne") != test.subOneListings ||
            countListings(run.output, "Inner.addTwo") != test.addTwoListings ||
            (!test.stage.empty() && run.output.find(test.stage) == std::string::npos))
        {
            std::println(stderr, "[print micro {}] {}", test.requests.front(), run.output);
            result = Result::Error;
            break;
        }
    }

    for (const std::string_view invalid : {std::string_view{":pre-emit"}, std::string_view{"addOne:emit"}})
    {
        if (result != Result::Continue)
            break;

        PrintMicroRun          run;
        const std::string_view request[] = {invalid};
        SWC_RESULT(runPrintMicro(run, directory, request));
        if (run.process != Os::ProcessRunResult::Ok || run.exitCode == 0 ||
            run.output.find("argument '--print-micro' does not accept value") == std::string::npos)
        {
            std::println(stderr, "[print micro {}] {}", invalid, run.output);
            result = Result::Error;
        }
    }

    fs::remove_all(directory, ec);
    if (result != Result::Continue)
        return result;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
