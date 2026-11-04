#include "pch.h"
#include "Backend/Linker/ELFObjectWriter.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Support/Memory/Allocator.h"
#include "Support/Report/Diagnostic.h"

// Link against the same objects as the compiler, replacing only its command entry point.
int main(int argc, char** argv)
{
    using namespace swc;
    Allocator::configure();
    if (argc != 4)
        return 2;
    const fs::path root = fs::absolute(argv[1]);
    const size_t count = std::stoull(argv[2]);
    const size_t rounds = std::stoull(argv[3]);
    fs::create_directories(root);
    std::vector<LinkArchiveMember> members;
    Diagnostic diagnostic;
    for (size_t index = 0; index < count; ++index)
    {
        LinkImage image;
        LinkSection text;
        text.name = ".text";
        text.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
        text.bytes.append(std::string_view("\xb8\x2a\x00\x00\x00\xc3", 6));
        image.sections.push_back(std::move(text));
        image.symbols.push_back({.name = std::format("function_{}", index)});
        LinkArchiveMember member;
        member.name = std::format("member_{:06}.o", index);
        if (!buildElfObject(member.bytes, diagnostic, image))
            return 3;
        members.push_back(std::move(member));
    }
    for (size_t round = 0; round <= rounds; ++round)
    {
        // Alternate order; round zero warms filesystem and executable pages for both paths.
        for (size_t pass = 0; pass < 2; ++pass)
        {
            const bool external = (pass + round) % 2 == 0;
            const auto start = std::chrono::steady_clock::now();
            const fs::path work = root / "work";
            ByteArray bytes;
            FileSystem::IoErrorInfo error;
            if (external)
            {
                fs::create_directories(work / "objects");
                std::vector<Utf8> paths;
                for (const LinkArchiveMember& member : members)
                {
                    const fs::path path = work / "objects" / std::format("member_{:06}.o", paths.size());
                    if (FileSystem::writeBinaryFile(path, member.bytes.data(), member.bytes.size(), error) != Result::Continue)
                        return 4;
                    paths.emplace_back(path.lexically_relative(work));
                }
                ByteArray script;
                script.append("CREATE archive.a\n");
                for (const Utf8& path : std::views::reverse(paths))
                {
                    script.append("ADDMOD ");
                    script.append(path.view());
                    script.append("\n");
                }
                script.append("SAVE\nEND\n");
                if (FileSystem::writeBinaryFile(work / "archive.mri", script.data(), script.size(), error) != Result::Continue)
                    return 4;
                uint32_t exitCode = 0;
                const std::array<Utf8, 2> args = {"-c", "exec ar -DM < archive.mri"};
                std::string captured;
                const Os::ProcessRunOptions options{.capturedOutput = &captured, .forwardOutput = false, .timeoutMs = 120000};
                if (Os::runProcess(exitCode, "sh", args, work, &options) != Os::ProcessRunResult::Ok || exitCode ||
                    FileSystem::readBinaryFile(work / "archive.a", bytes, error) != Result::Continue)
                    return 5;
            }
            else if (!buildElfStaticArchive(bytes, diagnostic, members))
                return 6;
            if (FileSystem::writeBinaryFileAtomic(root / (external ? "gnu.a" : "internal.a"), bytes.data(), bytes.size(), error, FileSystem::FileReplacement::Mapped) != Result::Continue)
                return 7;
            const size_t archiveSize = bytes.size();
            bytes = ByteArray{};
            fs::remove_all(work);
            const double milliseconds = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
            if (round)
                std::println("{},{},{},{:.6f},{}", count, round, external ? "ar" : "internal", milliseconds, archiveSize);
        }
    }
}
