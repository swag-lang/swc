#global private

namespace Qualified
{
    struct(T) Box
    {
        value: T
    }

    struct(T, N: u32) Buffer
    {
        values: [N] T
    }
}

namespace OtherQualified
{
    struct(T) Box
    {
        value: T
    }
}

struct(T, N: u32) Holder
{
    box:    Qualified.Box'T
    buffer: Qualified.Buffer'(T, N)
}

func(T) read(box: const *Qualified.Box'T)->T => box.value
func(T) make(value: T)->Qualified.Box'T => {value}
func(Box) makeShadowed(value: Box)->Qualified.Box'Box => {value}
func(T) choose(box: const *Qualified.Box'T)->u32      => 1
func(T) choose(box: const *OtherQualified.Box'T)->u32 => 2

#test
{
    var holder: Holder'(u32, 3)
    holder.box = make'u32(42)
    holder.buffer.values = [1, 2, 3]
    Swag.require(read'u32(&holder.box) == 42)
    Swag.require(read(&holder.box) == 42)
    Swag.require(make(17'u32).value == 17)
    Swag.require(makeShadowed(19'u32).value == 19)
    Swag.require(holder.buffer.values[2] == 3)
    Swag.require(choose(&holder.box) == 1)
    var other: OtherQualified.Box'u32 = OtherQualified.Box'u32{12}
    Swag.require(choose(&other) == 2)
}
