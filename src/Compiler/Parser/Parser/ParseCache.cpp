#include "pch.h"
#include "Compiler/Parser/Parser/ParseCache.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Main/Version.h"
#include "Main/WorkspaceLayout.h"
#include "Support/Core/ByteArray.h"
#include "Support/Math/Hash.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_MAGIC = 0x3245535241505753; // SWPARSE2

    struct Header
    {
        uint64_t magic       = K_MAGIC;
        uint32_t sourceBytes = 0;
        uint32_t tokens      = 0;
        uint32_t identifiers = 0;
        uint32_t lines       = 0;
        uint32_t nodes       = 0;
        uint32_t imageBytes  = 0;
        uint32_t root        = 0;
        uint32_t checksum    = 0;
        uint32_t sourceStart = 0;
        uint32_t reserved    = 0;
    };

    template<typename T>
    void append(std::vector<std::byte>& out, std::span<const T> values)
    {
        const auto bytes = std::as_bytes(values);
        out.insert(out.end(), bytes.begin(), bytes.end());
    }

    template<typename T>
    void consume(std::vector<T>& out, std::span<const std::byte>& bytes, const uint32_t count)
    {
        out.resize(count);
        if (count)
            std::memcpy(out.data(), bytes.data(), count * sizeof(T));
        bytes = bytes.subspan(count * sizeof(T));
    }

    Utf8 compilerIdentity()
    {
        const fs::path  exe = Os::getExeFullName();
        std::error_code ec;
        const auto      size = fs::file_size(exe, ec);
        if (ec)
            return {};
        const auto time = fs::last_write_time(exe, ec);
        if (ec)
            return {};
        return std::format("{}:{}:{}:{}.{}.{}:{}", exe.generic_string(), size, time.time_since_epoch().count(), SWC_VERSION, SWC_REVISION, SWC_BUILD_NUM, sizeof(AstNode));
    }
}

fs::path ParseCache::path(const TaskContext& ctx, const SourceFile& file, const ParserJobOptions options)
{
    // Debug references carry process addresses. Their layout is deliberately excluded
    // until the archive has a field-wise debug representation as well.
    if (SWC_HAS_REF_DEBUG_INFO || (!file.isRuntime() && !file.isImportedApi()) || file.ast().root().isValid())
        return {};
    const auto& cmd = ctx.cmdLine();
    if (!cmd.parseCache || options.emitTrivia || options.ignoreGlobalCompilerIfSkip || options.allowReservedIdentifiers ||
        cmd.lexOnly || cmd.syntaxOnly || cmd.semaOnly || isEditorServiceCommand(cmd.command))
        return {};
    static const Utf8 compiler = compilerIdentity();
    if (compiler.empty())
        return {};
    const Utf8 key = std::format("{}:{}:{}:{}:{}", compiler.view(), file.genericPathString().view(), file.isRuntime(), static_cast<uint32_t>(compilerCommandFromKind(cmd.command)), Math::hash(file.sourceView()));
    return WorkspaceLayout::parseCacheRoot() / std::format("{:08x}{:08x}.bin", Math::hash(key.view()), Math::hash(key.view(), 0x123456789abcdef0ULL));
}

bool ParseCache::read(TaskContext&, SourceFile& file, const fs::path& path)
{
    // Limit allocation before reading a damaged cache. Even token-dense sources have
    // far less than 256 bytes of syntax per input byte with the supported layout.
    std::error_code ec;
    const auto      size = fs::file_size(path, ec);
    if (ec || size < sizeof(Header) || size > 65536 + static_cast<uint64_t>(file.size()) * 256)
        return false;
    ByteArray               bytes;
    FileSystem::IoErrorInfo error;
    if (FileSystem::readBinaryFile(path, bytes, error) != Result::Continue || bytes.size() < sizeof(Header))
        return false;
    Header header;
    std::memcpy(&header, bytes.data(), sizeof(header));
    const uint64_t expected = sizeof(Header) + static_cast<uint64_t>(header.sourceBytes) +
                              static_cast<uint64_t>(header.tokens) * sizeof(Token) +
                              static_cast<uint64_t>(header.identifiers) * sizeof(SourceIdentifier) +
                              static_cast<uint64_t>(header.lines + static_cast<uint64_t>(header.nodes)) * sizeof(uint32_t) + header.imageBytes;
    if (header.magic != K_MAGIC || expected != bytes.size() || header.sourceBytes != file.size())
        return false;
    const auto checksum = header.checksum;
    header.checksum     = 0;
    std::memcpy(bytes.data(), &header, sizeof(header));
    auto payload = bytes.span().subspan(sizeof(Header));
    if (Math::hash(bytes.span()) != checksum || (file.size() && std::memcmp(payload.data(), file.sourceView().data(), file.size()) != 0))
        return false;
    std::span<const std::byte>    input = payload.subspan(header.sourceBytes);
    SourceView&                   view  = file.ast().srcView();
    std::vector<Token>            tokens;
    std::vector<SourceIdentifier> identifiers;
    std::vector<uint32_t>         lines;
    consume(tokens, input, header.tokens);
    consume(identifiers, input, header.identifiers);
    consume(lines, input, header.lines);
    std::vector<uint32_t> nodes;
    consume(nodes, input, header.nodes);
    if (tokens.empty() || tokens.back().id != TokenId::EndOfFile || lines.empty() || lines.front() != 0 || header.sourceStart > file.size())
        return false;
    auto previousTokens = std::move(view.tokens());
    view.tokens()       = std::move(tokens);
    if (!file.ast().loadParseImage(input, nodes, header.root))
    {
        view.tokens() = std::move(previousTokens);
        return false;
    }
    view.identifiers() = std::move(identifiers);
    view.lines()       = std::move(lines);
    view.setSourceStartOffset(header.sourceStart);
    Stats::get().numTokens.fetch_add(header.tokens, std::memory_order_relaxed);
    return true;
}

void ParseCache::write(SourceFile& file, const fs::path& path)
{
    Ast&              ast  = file.ast();
    const SourceView& view = ast.srcView();
    if (file.hasError() || file.hasWarning() || ast.root().isInvalid() || view.mustSkip() || !view.runsSema())
        return;
    std::vector<std::byte> image;
    std::vector<uint32_t>  nodes;
    ast.copyParseImage(image, nodes);
    Header header;
    header.sourceBytes = static_cast<uint32_t>(file.size());
    header.tokens      = view.numTokens();
    header.identifiers = static_cast<uint32_t>(view.identifiers().size());
    header.lines       = static_cast<uint32_t>(view.lines().size());
    header.nodes       = static_cast<uint32_t>(nodes.size());
    header.imageBytes  = static_cast<uint32_t>(image.size());
    header.root        = ast.root().get();
    header.sourceStart = view.sourceStartOffset();
    std::vector<std::byte> bytes(sizeof(Header));
    append(bytes, std::span(file.sourceView().data(), file.size()));
    append(bytes, std::span(view.tokens()));
    append(bytes, std::span(view.identifiers()));
    append(bytes, std::span(view.lines()));
    append(bytes, std::span<const uint32_t>(nodes));
    append(bytes, std::span<const std::byte>(image));
    std::memcpy(bytes.data(), &header, sizeof(header));
    header.checksum = Math::hash(std::span<const std::byte>(bytes));
    std::memcpy(bytes.data(), &header, sizeof(header));

    std::error_code ec;
    fs::create_directories(path.parent_path(), ec);
    if (ec)
        return;
    FileSystem::IoErrorInfo error;
    FileSystem::writeBinaryFileAtomic(path, bytes.data(), bytes.size(), error);
}

SWC_END_NAMESPACE();
