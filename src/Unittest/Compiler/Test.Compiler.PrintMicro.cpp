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

    Result runPrintMicro(PrintMicroRun& run, const fs::path& directory, std::string_view source, std::string_view buildCfg, std::span<const std::string_view> requests)
    {
        const fs::path sourcePath = directory / "print_micro.swg";
        SWC_RESULT(CompilerTestFile::writeText(sourcePath, source));

        std::vector<Utf8> args = {"sema", "--num-cores", "6", "--no-log-color", "-f", Utf8(sourcePath.string())};
        if (!buildCfg.empty())
        {
            args.emplace_back("-bc");
            args.emplace_back(buildCfg);
        }
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

    // One parsed line of a listing: "NNN LLL <mnemonic and operands> | <comment>". A label line
    // has an id and no mnemonic.
    struct ListingLine
    {
        std::string_view id;
        std::string_view body;
    };

    bool isListingNumber(std::string_view text)
    {
        return text.size() == 3 && std::ranges::all_of(text, [](const char c) { return c >= '0' && c <= '9'; });
    }

    std::vector<ListingLine> parseListing(std::string_view listing)
    {
        std::vector<ListingLine> lines;
        for (size_t pos = 0; pos < listing.size();)
        {
            const size_t           end  = listing.find('\n', pos);
            const std::string_view line = listing.substr(pos, end == std::string_view::npos ? std::string_view::npos : end - pos);
            pos                         = end == std::string_view::npos ? listing.size() : end + 1;
            if (line.size() < 7 || line[3] != ' ' || !isListingNumber(line.substr(0, 3)) || !isListingNumber(line.substr(4, 3)))
                continue;

            std::string_view body = line.substr(7);
            if (const size_t comment = body.find('|'); comment != std::string_view::npos)
                body = body.substr(0, comment);
            while (!body.empty() && body.front() == ' ')
                body.remove_prefix(1);
            while (!body.empty() && (body.back() == ' ' || body.back() == '\r'))
                body.remove_suffix(1);
            lines.push_back({line.substr(4, 3), body});
        }

        return lines;
    }

    // The first loop of one function's listing: the lines between a label and the conditional
    // jump back to it. Counts the reads through a plain base-plus-offset memory operand in that
    // body; an element access uses the indexed addressing form and is not counted.
    struct ListingLoop
    {
        bool   found       = false;
        size_t memoryReads = 0;
    };

    ListingLoop loopOfListing(std::string_view output, std::string_view scopedName)
    {
        ListingLoop  loop;
        const size_t header = output.find(std::format("function : {}", scopedName));
        if (header == std::string_view::npos)
            return loop;
        const size_t                   next  = output.find("[micro]", header);
        const std::vector<ListingLine> lines = parseListing(output.substr(header, next == std::string_view::npos ? std::string_view::npos : next - header));

        for (size_t backEdge = 0; backEdge < lines.size(); backEdge++)
        {
            const std::string_view body = lines[backEdge].body;
            if (!body.starts_with("jump_cond"))
                continue;
            const std::string_view target = body.substr(body.rfind(' ') + 1);
            size_t                 head   = 0;
            while (head < backEdge && !(lines[head].body.empty() && lines[head].id == target))
                head++;
            if (head == backEdge)
                continue;

            loop.found = true;
            for (size_t i = head + 1; i < backEdge; i++)
            {
                if (lines[i].body.starts_with("load_reg_mem") || lines[i].body.starts_with("op_binary_reg_mem"))
                    loop.memoryReads++;
            }
            return loop;
        }

        return loop;
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
        SWC_RESULT(runPrintMicro(run, directory, PRINT_MICRO_SOURCE, {}, test.requests));
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
        SWC_RESULT(runPrintMicro(run, directory, PRINT_MICRO_SOURCE, {}, request));
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

// A library lowers only what it exports and reaches, yet a listing asked for by the attribute or
// by the command line names a function the user wants to see, reached or not.
SWC_FILESYSTEM_TEST_BEGIN(Compiler_PrintMicroListsUnreachedLibraryFunctions)
{
    constexpr std::string_view SOURCE = R"(#global internal
#[Swag.PrintMicro]
func listedByAttribute()->u32 => 17
func listedByCommandLine()->u32 => 19
func neverListed()->u32 => 29
public func exported()->u32 => 23
)";

    const fs::path  directory = (Os::getTemporaryPath() / "swc_unittest" / "print_micro_library" / std::format("p{}", Os::currentProcessId())).lexically_normal();
    std::error_code ec;
    fs::remove_all(directory, ec);
    const fs::path source = directory / "print_micro_library.swg";
    SWC_RESULT(CompilerTestFile::writeText(source, SOURCE));

    const std::vector<Utf8> args = {"build", "--num-cores", "6", "--no-log-color", "--artifact-kind", "static-library",
                                    "--out-dir", Utf8((directory / "out").string()), "--work-dir", Utf8((directory / "work").string()),
                                    "-f", Utf8(source.string()), "--print-micro", "listedByCommandLine"};
    PrintMicroRun           run;
    Os::ProcessRunOptions   options;
    options.capturedOutput = &run.output;
    options.forwardOutput  = false;
    options.timeoutMs      = 15000;
    run.process            = Os::runProcess(run.exitCode, Os::getExeFullName(), args, directory, &options);

    // A built library scopes its functions under the module name.
    const auto listings = [&](std::string_view name) {
        constexpr std::string_view HEADER = "function : ";
        const std::string_view     output = run.output;
        size_t                     count  = 0;
        for (size_t pos = output.find(HEADER); pos != std::string_view::npos; pos = output.find(HEADER, pos + HEADER.size()))
        {
            const size_t           start   = pos + HEADER.size();
            const size_t           end     = output.find_first_of("\r\n", start);
            const std::string_view listed  = output.substr(start, end == std::string_view::npos ? std::string_view::npos : end - start);
            const size_t           dot     = listed.rfind('.');
            const std::string_view unscope = dot == std::string_view::npos ? listed : listed.substr(dot + 1);
            if (unscope == name)
                count++;
        }

        return count;
    };

    Result result = Result::Continue;
    if (run.process != Os::ProcessRunResult::Ok || run.exitCode != 0 ||
        listings("listedByAttribute") != 1 || listings("listedByCommandLine") != 1 || listings("neverListed") != 0)
    {
        std::println(stderr, "[print micro library] {}", run.output);
        result = Result::Error;
    }

    fs::remove_all(directory, ec);
    if (result != Result::Continue)
        return result;
}
SWC_TEST_END()

// A struct parameter is a value: nothing changes the caller's storage while the call runs, so
// the pointer a field holds is read once, before the loop, although the body stores through
// another pointer that could alias anything. The same loop over a pointer parameter reads the
// field on every trip, because the store may well be writing it.
SWC_FILESYSTEM_TEST_BEGIN(Compiler_PrintMicroShowsValueParameterReadsLeavingTheLoop)
{
    constexpr std::string_view SOURCE = R"(#global private
struct View
{
    data:  const [*] s64
    count: u64
}

#[Swag.NoInline]
func sumValue(dst: [*] s64, view: View)->s64
{
    var total = 0's64
    for i in view.count
    {
        dst[i] = view.data[i]
        total += dst[i]
    }

    return total
}

#[Swag.NoInline]
func sumPointer(dst: [*] s64, view: const *View)->s64
{
    var total = 0's64
    for i in view.count
    {
        dst[i] = view.data[i]
        total += dst[i]
    }

    return total
}

#run
{
    let src: [4] s64 = [1, -2, 3, 40]
    var dst: [4] s64
    let view = View{&src[0], 4}
    Swag.assert(sumValue(&dst[0], view) == 42)
    Swag.assert(sumPointer(&dst[0], &view) == 42)
    Swag.assert(dst[3] == 40)
}
)";

    const fs::path  directory = (Os::getTemporaryPath() / "swc_unittest" / "print_micro_value_parameter" / std::format("p{}", Os::currentProcessId())).lexically_normal();
    std::error_code ec;
    fs::remove_all(directory, ec);

    PrintMicroRun          run;
    const std::string_view requests[] = {"sumValue:pre-emit", "sumPointer:pre-emit"};
    SWC_RESULT(runPrintMicro(run, directory, SOURCE, "release", requests));
    fs::remove_all(directory, ec);

    const ListingLoop value   = loopOfListing(run.output, "sumValue");
    const ListingLoop pointer = loopOfListing(run.output, "sumPointer");
    if (run.process != Os::ProcessRunResult::Ok || run.exitCode != 0 || !value.found || !pointer.found || value.memoryReads != 0 || pointer.memoryReads == 0)
    {
        std::println(stderr, "[print micro value parameter] value loop reads {} ({}), pointer loop reads {} ({})\n{}", value.memoryReads, value.found, pointer.memoryReads, pointer.found, run.output);
        return Result::Error;
    }
}
SWC_TEST_END()

// A function's own locals are not storage any value argument can borrow while the function writes
// them, so a guarded build checks only the store that goes through a pointer.
SWC_FILESYSTEM_TEST_BEGIN(Compiler_PrintMicroChecksOnlyBorrowableValueWrites)
{
    constexpr std::string_view SOURCE = R"(#global private
struct Pair { first, second: u64 }

#[Swag.NoInline]
func writeLocals(value: u64)->u64
{
    var scalar = value
    scalar = scalar * 3 + 1
    var pair: Pair
    pair = {scalar, value}
    return pair.first + pair.second
}

#[Swag.NoInline]
func writeThroughPointer(target: *u64, value: u64)
{
    target[] = value
}

#[Swag.NoInline]
func writeBorrowingLocals(value: Pair)->u64
{
    var total = value.first
    for 16 do
        total += value.second
    return total
}

#[Swag.NoInline]
func readSecond(value: Pair)->u64 => value.second

#[Swag.NoInline]
func writeAfterBorrowingCall(value: Pair)->u64
{
    var total = readSecond(value)
    total += value.first
    return total
}

#run
{
    Swag.assert(writeLocals(2) == 9)
    var value: u64
    writeThroughPointer(&value, 5)
    Swag.assert(value == 5)
    var pair = Pair{2, 3}
    Swag.assert(writeBorrowingLocals(pair) == 50)
    Swag.assert(writeAfterBorrowingCall(pair) == 5)
}
)";

    const fs::path  directory = (Os::getTemporaryPath() / "swc_unittest" / "print_micro_value_borrow_writes" / std::format("p{}", Os::currentProcessId())).lexically_normal();
    std::error_code ec;
    fs::remove_all(directory, ec);

    PrintMicroRun          run;
    const std::string_view requests[] = {"writeLocals", "writeThroughPointer", "writeBorrowingLocals", "writeAfterBorrowingCall"};
    SWC_RESULT(runPrintMicro(run, directory, SOURCE, "devmode", requests));
    fs::remove_all(directory, ec);

    const auto checkedWrites = [&](std::string_view scopedName) {
        const std::string_view output = run.output;
        const size_t           header = output.find(std::format("function : {}", scopedName));
        if (header == std::string_view::npos)
            return SIZE_MAX;
        const size_t           next    = output.find("[micro]", header);
        const std::string_view listing = output.substr(header, next == std::string_view::npos ? std::string_view::npos : next - header);
        size_t                 count   = 0;
        for (size_t pos = listing.find("__valueBorrowWrite"); pos != std::string_view::npos; pos = listing.find("__valueBorrowWrite", pos + 1))
            count++;
        return count;
    };

    const size_t locals          = checkedWrites("writeLocals");
    const size_t pointer         = checkedWrites("writeThroughPointer");
    const size_t borrowingLocals = checkedWrites("writeBorrowingLocals");
    const size_t afterCall       = checkedWrites("writeAfterBorrowingCall");
    if (run.process != Os::ProcessRunResult::Ok || run.exitCode != 0 || locals != 0 || pointer != 1 || borrowingLocals != 0 || afterCall != 0)
    {
        std::println(stderr, "[print micro value borrow writes] locals {}, pointer {}, borrowed parameter {}, after call {}\n{}", locals, pointer, borrowingLocals, afterCall, run.output);
        return Result::Error;
    }
}
SWC_TEST_END()

// A write the backend proves lands in the function's frame loses its check while the function
// has no borrow of its own open, whatever pointer the source wrote through. A borrow the function
// opens itself, here an inline binding, keeps the check of every write made while it is open.
SWC_FILESYSTEM_TEST_BEGIN(Compiler_PrintMicroDropsFrameWriteChecks)
{
    constexpr std::string_view SOURCE = R"(#global private
struct Pair { first, second: u64 }

#[Swag.Inline]
func bump(table: *[4] u32, index: u32)
{
    table[][index] = table[][index] + 7
}

#[Swag.NoInline]
func writeFrameThroughPointer(count: u32)->u32
{
    var table: [4] u32
    for i in count
    {
        bump(&table, 1)
        bump(&table, i & 3)
    }
    return table[1] + table[2]
}

#[Swag.Inline]
func readAlongsideWrite(value: Pair, destination: *Pair)->u64
{
    destination.first = 53
    return value.first
}

#[Swag.NoInline]
func writeFrameWhileBorrowed(seed: u64)->u64
{
    var value = Pair{seed, seed + 1}
    var other = Pair{seed + 2, seed + 3}
    return readAlongsideWrite(value, &other) + other.first
}

#run
{
    Swag.assert(writeFrameThroughPointer(8) == 84)
    Swag.assert(writeFrameWhileBorrowed(5) == 58)
}
)";

    const fs::path  directory = (Os::getTemporaryPath() / "swc_unittest" / "print_micro_frame_write_checks" / std::format("p{}", Os::currentProcessId())).lexically_normal();
    std::error_code ec;
    fs::remove_all(directory, ec);

    PrintMicroRun          run;
    const std::string_view requests[] = {"writeFrameThroughPointer", "writeFrameWhileBorrowed"};
    SWC_RESULT(runPrintMicro(run, directory, SOURCE, "devmode", requests));
    fs::remove_all(directory, ec);

    const auto checkedWrites = [&](std::string_view scopedName) {
        const std::string_view output = run.output;
        const size_t           header = output.find(std::format("function : {}", scopedName));
        if (header == std::string_view::npos)
            return SIZE_MAX;
        const size_t           next    = output.find("[micro]", header);
        const std::string_view listing = output.substr(header, next == std::string_view::npos ? std::string_view::npos : next - header);
        size_t                 count   = 0;
        for (size_t pos = listing.find("__valueBorrowWrite"); pos != std::string_view::npos; pos = listing.find("__valueBorrowWrite", pos + 1))
            count++;
        return count;
    };

    const size_t frame    = checkedWrites("writeFrameThroughPointer");
    const size_t borrowed = checkedWrites("writeFrameWhileBorrowed");
    if (run.process != Os::ProcessRunResult::Ok || run.exitCode != 0 || frame != 0 || borrowed == 0 || borrowed == SIZE_MAX)
    {
        std::println(stderr, "[print micro frame write checks] frame {}, while borrowed {}\n{}", frame, borrowed, run.output);
        return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
