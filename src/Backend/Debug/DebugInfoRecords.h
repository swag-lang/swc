#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;
struct MachineCode;

struct DebugInfoTypedRecord
{
    Utf8    name;
    Utf8    linkageName;
    TypeRef typeRef = TypeRef::invalid();
    bool    isConst = false;
};

struct DebugInfoLocalRecord : DebugInfoTypedRecord
{
    uint32_t offset  = 0;
    MicroReg baseReg = MicroReg::invalid();
};

struct DebugInfoDataRecord : DebugInfoTypedRecord
{
    Utf8     symbolName;
    Utf8     sectionName;
    uint32_t symbolOffset = 0;
    bool     isGlobal     = true;
};

struct DebugInfoConstantRecord : DebugInfoTypedRecord
{
    ConstantRef valueRef = ConstantRef::invalid();
};

struct DebugInfoFunctionRecord
{
    Utf8    symbolName;
    Utf8    debugName;
    TypeRef returnTypeRef = TypeRef::invalid();

    const MachineCode* machineCode = nullptr;
    const SourceFile*  sourceFile  = nullptr;

    uint32_t frameSize    = 0;
    MicroReg frameBaseReg = MicroReg::invalid();

    std::span<const DebugInfoLocalRecord>    parameters;
    std::span<const DebugInfoLocalRecord>    locals;
    std::span<const DebugInfoConstantRecord> constants;
};

SWC_END_NAMESPACE();
