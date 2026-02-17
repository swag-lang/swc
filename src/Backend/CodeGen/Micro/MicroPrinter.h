#pragma once
#include "Backend/CodeGen/Micro/MicroInstr.h"
#include "Backend/CodeGen/Micro/MicroInstrStorage.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class Encoder;
class MicroInstrBuilder;

enum class MicroRegPrintMode : uint8_t
{
    Default,
    Virtual,
    Concrete,
};

class MicroPrinter
{
public:
    static Utf8 format(const TaskContext&         ctx,
                       const MicroInstrStorage&   instructions,
                       const MicroOperandStorage& operands,
                       MicroRegPrintMode          regPrintMode = MicroRegPrintMode::Default,
                       const Encoder*             encoder      = nullptr,
                       const MicroInstrBuilder*   builder      = nullptr);

    static void print(const TaskContext&         ctx,
                      const MicroInstrStorage&   instructions,
                      const MicroOperandStorage& operands,
                      MicroRegPrintMode          regPrintMode = MicroRegPrintMode::Default,
                      const Encoder*             encoder      = nullptr,
                      const MicroInstrBuilder*   builder      = nullptr);
};

SWC_END_NAMESPACE();
