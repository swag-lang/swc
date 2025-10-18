#include "pch.h"
#include "Lexer/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Report/DiagReporter.h"
#include "Report/Diagnostic.h"

SourceFile::SourceFile(std::filesystem::path path) :
    path_(std::move(path))
{
}

Result SourceFile::loadContent(CompilerInstance &ci)
{
    std::ifstream file(path_, std::ios::binary | std::ios::ate);

    if (!file)
    {
        const auto diag = DiagReporter::diagnostic(DiagnosticId::ErrFileOpen);
        diag->addArgument(path_.string());
        ci.diagReporter().get()->report(diag);
        return Result::Error;
    }

    const auto fileSize = file.tellg();
    file.seekg(0, std::ios::beg);
    content_.resize(fileSize);
    
    if (!file.read(reinterpret_cast<char*>(content_.data()), fileSize))
    {
        const auto diag = DiagReporter::diagnostic(DiagnosticId::ErrFileRead);
        diag->addArgument(path_.string());
        ci.diagReporter().get()->report(diag);
        return Result::Error;        
    }

    return Result::Success;
}
