#pragma once

SWC_BEGIN_NAMESPACE();

class TaskContext;

enum class SyntaxColor
{
    Code,
    InstructionIndex,
    MicroInstruction,
    Comment,
    Compiler,
    Function,
    Constant,
    Intrinsic,
    Type,
    Keyword,
    Logic,
    Number,
    String,
    Attribute,
    Default,
    Register,
    RegisterVirtual,
    Relocation,
    Invalid,
};

static constexpr const char* SYN_CODE       = "SCde";
static constexpr const char* SYN_INST_INDEX = "SIdx";
static constexpr const char* SYN_MICRO_INST = "SMic";
static constexpr const char* SYN_COMMENT    = "SCmt";
static constexpr const char* SYN_COMPILER   = "SCmp";
static constexpr const char* SYN_FUNCTION   = "SFct";
static constexpr const char* SYN_CONSTANT   = "SCst";
static constexpr const char* SYN_INTRINSIC  = "SItr";
static constexpr const char* SYN_TYPE       = "STpe";
static constexpr const char* SYN_KEYWORD    = "SKwd";
static constexpr const char* SYN_LOGIC      = "SLgc";
static constexpr const char* SYN_NUMBER     = "SNum";
static constexpr const char* SYN_STRING     = "SStr";
static constexpr const char* SYN_ATTRIBUTE  = "SAtr";
static constexpr const char* SYN_DEFAULT    = "SDft";
static constexpr const char* SYN_INVALID    = "SInv";
static constexpr const char* SYN_REGISTER   = "SBcR";
static constexpr const char* SYN_REGISTER_V = "SBvR";
static constexpr const char* SYN_RELOCATION = "SRel";

enum class SyntaxColorMode
{
    ForDoc,
    ForLog,
};

namespace SyntaxColorHelper
{
    Utf8 toAnsi(const TaskContext& ctx, SyntaxColor color, SyntaxColorMode mode = SyntaxColorMode::ForLog);
    Utf8 colorize(const TaskContext& ctx, SyntaxColorMode mode, const std::string_view& line, bool force = false);
}

SWC_END_NAMESPACE();
