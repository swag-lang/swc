#include "pch.h"
#include "Lexer/SourceFile.h"

SourceFile::SourceFile(std::filesystem::path path) :
    path(std::move(path))
{
}

void SourceFile::loadContent(const CompilerInstance &ci)
{
    std::ifstream file(path, std::ios::binary | std::ios::ate);

    if (!file)
    {
        throw std::runtime_error("Failed to open file: " + path.string());
    }

    const auto fileSize = file.tellg();
    file.seekg(0, std::ios::beg);
    content.resize(fileSize);
    
    if (!file.read(reinterpret_cast<char*>(content.data()), fileSize))
    {
        throw std::runtime_error("Failed to read file: " + path.string());
    }
}
