#global internal

namespace InlineRegressionBug13
{
    struct Vector3
    {
        x, y, z: s32 = 666
    }

    impl Vector3
    {
        mtd opPostMove()
        {
            .x, .y, .z += 2
        }

        mtd opDrop() {}
    }

    #[Swag.Inline]
    func assign(assignTo: &Vector3, from: &&Vector3)
    {
        assignTo = #move from
    }
}
