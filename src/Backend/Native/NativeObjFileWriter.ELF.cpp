#include "pch.h"
#include "Backend/Native/NativeObjFileWriter.ELF.h"
#include "Backend/Linker/ObjectWriter.ELF.h"
#include "Backend/Linker/SymbolTable.ELF.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeImageBuilder.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

Result NativeObjFileWriterElf::buildObjectFile(ByteArray& outBytes, const NativeObjDescription& description)
{
    outBytes.clear();
    LinkImage image;
    SWC_RESULT(NativeImageBuilder::buildObject(image, *builder_, description));
    std::vector<SymbolTable::Entry> symbols;
    symbols.reserve(description.functions.size());
    for (const NativeFunctionInfo* function : description.functions)
    {
        if (function->exported && !function->exportName.empty())
            image.exports.push_back({.name = function->exportName, .symbolName = function->symbolName});
        SymbolTable::Entry entry;
        if (SymbolTable::makeEntry(entry, builder_->ctx(), *function))
            symbols.push_back(std::move(entry));
    }
    ELFSymbolTable::appendObject(image, symbols);
    Diagnostic diagnostic;
    if (!buildElfObject(outBytes, diagnostic, image))
        return builder_->reportError(diagnostic);
    return Result::Continue;
}

SWC_END_NAMESPACE();
