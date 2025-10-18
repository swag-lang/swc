#pragma once

struct CompilerInstance;

struct SourceFile
{
    Fs::path             path;
    std::vector<uint8_t> content;

    explicit SourceFile(Fs::path path);
    void loadContent(const CompilerInstance& ci);
};
