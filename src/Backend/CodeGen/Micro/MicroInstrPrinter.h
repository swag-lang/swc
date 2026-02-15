#pragma once
#include "Backend/CodeGen/Micro/MicroInstr.h"
#include "Backend/CodeGen/Micro/MicroInstrStorage.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class Encoder;
class MicroInstrBuilder;

enum class MicroInstrRegPrintMode : uint8_t
{
    Default,
    Virtual,
    Concrete,
};

class MicroInstrPrinter
{
public:
    static Utf8 format(const TaskContext&         ctx,
                       const MicroInstrStorage&   instructions,
                       const MicroOperandStorage& operands,
                       MicroInstrRegPrintMode     regPrintMode = MicroInstrRegPrintMode::Default,
                       const Encoder*             encoder      = nullptr,
                       bool                       colorize     = false,
                       const MicroInstrBuilder*   builder      = nullptr);

    static void print(const TaskContext&         ctx,
                      const MicroInstrStorage&   instructions,
                      const MicroOperandStorage& operands,
                      MicroInstrRegPrintMode     regPrintMode = MicroInstrRegPrintMode::Default,
                      const Encoder*             encoder      = nullptr,
                      bool                       colorize     = true,
                      const MicroInstrBuilder*   builder      = nullptr);
};

SWC_END_NAMESPACE();
