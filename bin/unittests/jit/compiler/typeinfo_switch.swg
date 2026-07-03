#global private

#test
{
    func switchOnStoredLiteralTypeValue()->s32
    {
        let info = #typeof([1, 2.5])
        switch info
        {
            case #type const [2] f32:
                return 42
            case #type const [2] s32:
                return -1
            default:
                return 0
        }
    }

    const V = #run switchOnStoredLiteralTypeValue()
    #assert(V == 42)
}
