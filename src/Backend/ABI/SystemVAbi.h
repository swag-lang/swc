#pragma once

SWC_BEGIN_NAMESPACE();

class TaskContext;
class TypeInfo;

namespace SystemVAbi
{
    enum class Class : uint8_t
    {
        None,
        Integer,
        Sse,
        SseUp,
        Memory,
    };

    struct Classification
    {
        std::array<Class, 2> classes{};
        uint32_t             size      = 0;
        uint32_t             alignment = 1;

        bool memory() const { return classes[0] == Class::Memory; }
        uint32_t integerRegisters() const;
        uint32_t vectorRegisters() const;
    };

    // Classify the value's storage. Language-level array-to-pointer decay happens
    // before this boundary; an array embedded in a struct retains its element classes.
    // Unsupported scalar formats (such as x87 long double) have no classification.
    std::optional<Classification> classify(TaskContext& ctx, const TypeInfo& type);

    struct ArgumentLocation
    {
        static constexpr uint8_t K_NO_REGISTER = UINT8_MAX;
        std::array<uint8_t, 2> registers{K_NO_REGISTER, K_NO_REGISTER};
        uint64_t               stackOffset = 0;
        bool                   onStack     = false;
    };

    class ArgumentAllocator
    {
    public:
        ArgumentLocation next(const Classification& type);
        uint32_t integerRegisters() const { return integers_; }
        uint32_t vectorRegisters() const { return vectors_; }
        uint64_t stackSize() const { return stackSize_; }
        uint32_t stackAlignment() const { return stackAlignment_; }

    private:
        uint32_t integers_       = 0;
        uint32_t vectors_        = 0;
        uint64_t stackSize_      = 0;
        uint32_t stackAlignment_ = 16;
    };
}

SWC_END_NAMESPACE();
