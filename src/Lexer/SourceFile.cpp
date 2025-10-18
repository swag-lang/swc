#include "pch.h"
#include "Lexer/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Report/DiagReporter.h"
#include "Report/Diagnostic.h"

SourceFile::SourceFile(std::filesystem::path path) :
    path_(std::move(path))
{
}

Result SourceFile::checkFormat(CompilerInstance &ci, CompilerContext &ctx)
{
    // Read header
    const uint8_t c1 = content_[0];
    const uint8_t c2 = content_[1];
    const uint8_t c3 = content_[2];
    const uint8_t c4 = content_[3];

    if (c1 == 0xEF && c2 == 0xBB && c3 == 0xBF)
    {
        offsetStartBuffer_ = 3;
        return Result::Success;
    }

    if ((c1 == 0xFE && c2 == 0xFF)                                // UTF-16 BigEndian
        || (c1 == 0xFF && c2 == 0xFE)                             // UTF-16 LittleEndian
        || (c1 == 0x00 && c2 == 0x00 && c3 == 0xFE && c4 == 0xFF) // UTF-32 BigEndian
        || (c1 == 0xFF && c2 == 0xFE && c3 == 0x00 && c4 == 0x00) // UTF-32 BigEndian
        || (c1 == 0x0E && c2 == 0xFE && c3 == 0xFF)               // SCSU
        || (c1 == 0xDD && c2 == 0x73 && c3 == 0x66 && c4 == 0x73) // UTF-EBCDIC
        || (c1 == 0x2B && c2 == 0x2F && c3 == 0x76 && c4 == 0x38) // UTF-7
        || (c1 == 0x2B && c2 == 0x2F && c3 == 0x76 && c4 == 0x39) // UTF-7
        || (c1 == 0x2B && c2 == 0x2F && c3 == 0x76 && c4 == 0x2B) // UTF-7
        || (c1 == 0x2B && c2 == 0x2F && c3 == 0x76 && c4 == 0x2F) // UTF-7
        || (c1 == 0xFB && c2 == 0xEE && c3 == 0x28)               // BOCU-1
        || (c1 == 0xF7 && c2 == 0x64 && c3 == 0x4C)               // UTF-1 BigEndian
        || (c1 == 0x84 && c2 == 0x31 && c3 == 0x95 && c4 == 0x33) // GB-18030
    )
    {
        const auto diag = DiagReporter::error(DiagnosticId::FileNotUtf8);
        diag->addArgument(path_.string());
        ci.diagReporter().report(ci, ctx, *diag);
        return Result::Error;
    }

    return Result::Success;
}

Result SourceFile::loadContent(CompilerInstance &ci, CompilerContext &ctx)
{
    std::ifstream file(path_, std::ios::binary | std::ios::ate);

    if (!file)
    {
        const auto diag = DiagReporter::error(DiagnosticId::CannotOpenFile);
        diag->addArgument(path_.string());
        ci.diagReporter().report(ci, ctx, *diag);
        return Result::Error;
    }

    const auto fileSize = file.tellg();
    file.seekg(0, std::ios::beg);
    content_.resize(fileSize);
    
    if (!file.read(reinterpret_cast<char*>(content_.data()), fileSize))
    {
        const auto diag = DiagReporter::error(DiagnosticId::CannotReadFile);
        diag->addArgument(path_.string());
        ci.diagReporter().report(ci, ctx, *diag);
        return Result::Error;        
    }

    // Ensure we have at least 4 characters in the buffer
    content_.push_back(0);
    content_.push_back(0);
    content_.push_back(0);
    content_.push_back(0);
    
    SWAG_CHECK(checkFormat(ci, ctx));
    
    return Result::Success;
}
