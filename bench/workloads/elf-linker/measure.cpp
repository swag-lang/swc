#include "pch.h"
#include "Backend/Linker/ImageWriter.ELF.h"
#include "Backend/Linker/ELFObjectWriter.h"
#include "Backend/Linker/ELFSymbolTable.h"
#include "Backend/Linker/LinkJob.h"
#include "Main/FileSystem.h"
#include "Support/Memory/Allocator.h"
#include "Support/Os/Os.h"

int main(int argc, char** argv)
{
    using namespace swc;
    Allocator::configure();
    if (argc != 5)
        return 2;
    const fs::path root = fs::absolute(argv[1]);
    const size_t count = std::stoull(argv[2]), rounds = std::stoull(argv[3]);
    const bool shared = std::string_view(argv[4]) == "shared";
    fs::create_directories(root);
    LinkJob job;
    job.output = shared ? LinkJob::Output::SharedLibrary : LinkJob::Output::Executable;
    job.elfLibraries = {"c", "m", "dl"};
    for (size_t index = 0; index < count; ++index)
    {
        LinkImage image;
        LinkSection text;
        text.name = ".text";
        text.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
        if (index)
        {
            constexpr unsigned char code[] = {0xb8, 42, 0, 0, 0, 0xc3};
            text.bytes.append(std::as_bytes(std::span(code)));
        }
        else
        {
            // Both outputs must resolve a real libc import; abs(-42) returns 42.
            constexpr unsigned char code[] = {0x48,0x83,0xec,8,0xbf,0xd6,0xff,0xff,0xff,0xe8,0,0,0,0,0x83,0xe8,42,0x48,0x83,0xc4,8,0xc3};
            text.bytes.append(std::as_bytes(std::span(code)));
            text.relocs.push_back({.offset = 10, .kind = LinkRelocKind::Rel32, .symbolName = "abs"});
        }
        image.sections.push_back(std::move(text));
        image.symbols.push_back({.name = index ? Utf8(std::format("function_{}", index)) : Utf8("main")});
        LinkArchiveMember member;
        member.name = std::format("member_{:06}.o", index);
        Diagnostic diagnostic;
        if (!buildElfObject(member.bytes, diagnostic, image))
            return 3;
        job.archiveMembers.push_back(std::move(member));
    }
    for (size_t round = 0; round <= rounds; ++round)
    {
        for (size_t pass = 0; pass < 2; ++pass)
        {
            const bool external = (pass + round) % 2 == 0;
            const fs::path work = root / "work";
            job.outputPath = root / (external ? "baseline" : "internal");
            const auto start = std::chrono::steady_clock::now();
            ByteArray bytes;
            FileSystem::IoErrorInfo io;
            Utf8 error;
            if (external)
            {
                fs::create_directories(work / "objects");
                std::vector<Utf8> args = {"-Wl,--build-id=none", "-Wl,-z,noexecstack", "-Wl,-z,relro", "-Wl,-z,now", "-Wl,--eh-frame-hdr", "-Wl,--fatal-warnings", "-pthread"};
                if (shared)
                    args.insert(args.end(), {"-shared", "-Wl,-Bsymbolic", "-Wl,-z,text", "-Wl,-soname,baseline"});
                else
                    args.emplace_back("-no-pie");
                args.emplace_back("-Wl,-rpath,$ORIGIN");
                for (const LinkArchiveMember& member : job.archiveMembers)
                {
                    const fs::path path = work / "objects" / member.name.c_str();
                    if (FileSystem::writeBinaryFile(path, member.bytes.data(), member.bytes.size(), io) != Result::Continue)
                        return 4;
                    args.emplace_back(path.lexically_relative(work));
                }
                args.insert(args.end(), {"-Wl,--start-group", "-lc", "-lm", "-ldl", "-Wl,--end-group", "-o", "image"});
                ByteArray response;
                for (const Utf8& argument : args)
                {
                    response.append("\"");
                    for (const char character : argument.view())
                    {
                        if (character == '\\' || character == '"')
                            response.append("\\");
                        response.pushBack(static_cast<std::byte>(character));
                    }
                    response.append("\"\n");
                }
                if (FileSystem::writeBinaryFile(work / "arguments.rsp", response.data(), response.size(), io) != Result::Continue)
                    return 4;
                uint32_t exitCode = 0;
                std::string output;
                const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 120000};
                const std::array<Utf8, 1> arguments = {"@arguments.rsp"};
                if (Os::runProcess(exitCode, "cc", arguments, work, &options) != Os::ProcessRunResult::Ok || exitCode ||
                    FileSystem::readBinaryFile(work / "image", bytes, io) != Result::Continue)
                {
                    std::println(stderr, "GNU link: {}", output);
                    return 5;
                }
            }
            else if (!buildElfImage(bytes, error, job))
            {
                std::println(stderr, "internal link: {}", error);
                return 6;
            }
            if (!ELFSymbolTable::finalizeImage(bytes, error) || FileSystem::writeBinaryFileAtomic(job.outputPath, bytes.data(), bytes.size(), io, FileSystem::FileReplacement::Ordinary) != Result::Continue)
                return 7;
            fs::permissions(job.outputPath, fs::perms::owner_exec | fs::perms::group_exec | fs::perms::others_exec, fs::perm_options::add);
            const size_t size = bytes.size();
            bytes = ByteArray{};
            fs::remove_all(work);
            const double milliseconds = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
            if (round)
                std::println("{},{},{},{},{:.6f},{}", shared ? "shared" : "executable", count, round, external ? "gnu" : "internal", milliseconds, size);
        }
    }
    // Validate outside the timed region. Both programs must compute the same result.
    for (const char* name : {"baseline", "internal"})
    {
        if (shared)
        {
            void* module = nullptr;
            void* entry = nullptr;
            if (!Os::loadExternalModule(module, (root / name).string()) || !Os::getExternalSymbolAddress(entry, module, "main") || reinterpret_cast<int (*)()>(entry)() != 0)
                return 8;
        }
        else
        {
            uint32_t exitCode = 0;
            if (Os::runProcess(exitCode, root / name, {}, root) != Os::ProcessRunResult::Ok || exitCode)
                return 9;
        }
    }
}
