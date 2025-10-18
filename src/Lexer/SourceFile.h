#pragma once

class CompilerInstance;

class SourceFile
{
    Fs::path             path_;
    std::vector<uint8_t> content_;

public:
    explicit SourceFile(Fs::path path);
    Result loadContent(CompilerInstance& ci);
};
