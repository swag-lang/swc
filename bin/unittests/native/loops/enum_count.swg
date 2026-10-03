#global private

enum Sparse { First = 10, Second = 50, Third = 100 }

enum Medium
{
    V00, V01, V02, V03, V04, V05,
    V06, V07, V08, V09, V10, V11
}

enum Large
{
    V00, V01, V02, V03, V04, V05, V06, V07, V08, V09,
    V10, V11, V12, V13, V14, V15, V16, V17, V18, V19,
    V20, V21, V22, V23, V24, V25, V26, V27, V28, V29,
    V30, V31, V32, V33, V34, V35, V36, V37, V38, V39,
    V40, V41, V42, V43, V44, V45, V46, V47, V48, V49,
    V50, V51, V52, V53, V54, V55, V56, V57, V58, V59,
    V60, V61, V62, V63, V64, V65, V66, V67, V68, V69
}

#test
{
    var visits = 0
    for Sparse do visits += 1
    Swag.assert(visits == 3)
}

#test
{
    var visits = 0
    for Medium do visits += 1
    Swag.assert(visits == 12)
}

#test
{
    var visits = 0
    for Large do visits += 1
    Swag.assert(visits == 70)
}
