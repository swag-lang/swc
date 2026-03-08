#global fileprivate
var g = false

//#[Swag.PrintBc]
#run
{
    g = false; @assert(g == false)
    g = true; @assert(g == true)
    //@print(g);
}
