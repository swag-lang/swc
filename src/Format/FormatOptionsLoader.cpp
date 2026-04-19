#include "pch.h"
#include "Format/FormatOptionsLoader.h"
#include "Main/FileSystem.h"
#include "Main/StructConfig.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view FORMAT_CONFIG_FILE = ".swc-format";

    void bindFormatOptionsSchema(StructConfigSchema& schema, FormatOptions& options)
    {
        schema.add("preserve-bom", &options.preserveBom, "Preserve UTF-8 BOM markers.");
        schema.add("preserve-trailing-whitespace", &options.preserveTrailingWhitespace, "Preserve trailing whitespace already present in source.");
        schema.add("insert-final-newline", &options.insertFinalNewline, "Ensure formatted files end with a newline.");
        schema.add("indent-width", &options.indentWidth, "Indent width used when formatting with spaces.");

        schema.addEnum("indent-style", &options.indentStyle,
                       {
                           {"preserve", FormatIndentStyle::Preserve},
                           {"spaces", FormatIndentStyle::Spaces},
                           {"tabs", FormatIndentStyle::Tabs},
                       },
                       "Indent style used by the formatter.");
        schema.addEnum("end-of-line-style", &options.endOfLineStyle,
                       {
                           {"preserve", FormatEndOfLineStyle::Preserve},
                           {"lf", FormatEndOfLineStyle::LF},
                           {"crlf", FormatEndOfLineStyle::CRLF},
                       },
                       "End-of-line style used by the formatter.");
    }
}

FormatOptionsLoader::FormatOptionsLoader(TaskContext& ctx) :
    ctx_(&ctx)
{
}

Result FormatOptionsLoader::applyConfigFile(FormatOptions& options, const fs::path& configPath) const
{
    StructConfigSchema schema;
    bindFormatOptionsSchema(schema, options);

    const StructConfigReader reader(schema);
    return reader.readFile(*ctx_, configPath);
}

Result FormatOptionsLoader::resolveDirectory(const fs::path& directory, FormatOptions& outOptions)
{
    const fs::path normalizedDirectory = FileSystem::normalizePath(directory);
    const auto     it                  = cache_.find(normalizedDirectory);
    if (it != cache_.end())
    {
        outOptions = it->second;
        return Result::Continue;
    }

    FormatOptions options;

    fs::path parent = normalizedDirectory.parent_path();
    if (!parent.empty())
    {
        parent = FileSystem::normalizePath(parent);
        if (!FileSystem::pathEquals(parent, normalizedDirectory))
            SWC_RESULT(resolveDirectory(parent, options));
    }

    const fs::path  configPath = normalizedDirectory / FORMAT_CONFIG_FILE;
    std::error_code ec;
    const bool      exists = fs::exists(configPath, ec);
    if (!ec && exists)
        SWC_RESULT(applyConfigFile(options, configPath));

    cache_[normalizedDirectory] = options;
    outOptions                  = options;
    return Result::Continue;
}

Result FormatOptionsLoader::resolve(const fs::path& sourcePath, FormatOptions& outOptions)
{
    const fs::path directory = sourcePath.parent_path();
    if (directory.empty())
    {
        outOptions = {};
        return Result::Continue;
    }

    return resolveDirectory(directory, outOptions);
}

SWC_END_NAMESPACE();
