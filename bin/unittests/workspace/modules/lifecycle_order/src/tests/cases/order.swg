#global private

var sequence: u32

#init
{
    Swag.require(sequence == 0)
    sequence = 1
}

#init
{
    Swag.require(sequence == 1)
    sequence = 2
}

#test
{
    Swag.require(sequence == 2)
}

#drop
{
    Swag.require(sequence == 3)
    sequence = 4
}

#drop
{
    Swag.require(sequence == 2)
    sequence = 3
}
