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

static constexpr std::string_view SYN_CODE       = "SCde";
static constexpr std::string_view SYN_INST_INDEX = "SIdx";
static constexpr std::string_view SYN_MICRO_INST = "SMic";
static constexpr std::string_view SYN_COMMENT    = "SCmt";
static constexpr std::string_view SYN_COMPILER   = "SCmp";
static constexpr std::string_view SYN_FUNCTION   = "SFct";
static constexpr std::string_view SYN_CONSTANT   = "SCst";
static constexpr std::string_view SYN_INTRINSIC  = "SItr";
static constexpr std::string_view SYN_TYPE       = "STpe";
static constexpr std::string_view SYN_KEYWORD    = "SKwd";
static constexpr std::string_view SYN_LOGIC      = "SLgc";
static constexpr std::string_view SYN_NUMBER     = "SNum";
static constexpr std::string_view SYN_STRING     = "SStr";
static constexpr std::string_view SYN_ATTRIBUTE  = "SAtr";
static constexpr std::string_view SYN_DEFAULT    = "SDft";
static constexpr std::string_view SYN_INVALID    = "SInv";
static constexpr std::string_view SYN_REGISTER   = "SBcR";
static constexpr std::string_view SYN_REGISTER_V = "SBvR";
static constexpr std::string_view SYN_RELOCATION = "SRel";

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
