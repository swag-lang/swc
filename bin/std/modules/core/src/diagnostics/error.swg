#global public

namespace Console
{
    // Prints the formatted message `msg` and a new line, then exits the process with code -1.
    func fatal(msg: string, args: ...)
    {
        Console.printf(msg, args)
        Console.println()
        Env.exit(-1)
    }
}
