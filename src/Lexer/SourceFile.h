#pragma once

class CompilerContext;
class CompilerInstance;

class SourceFile
{
    Fs::path             path_;
    std::vector<uint8_t> content_;
    uint32_t             offsetStartBuffer_ = 0;

    Result checkFormat(CompilerInstance& ci, CompilerContext& ctx);

public:
    explicit SourceFile(Fs::path path);
    Result loadContent(CompilerInstance& ci, CompilerContext& ctx);
};
