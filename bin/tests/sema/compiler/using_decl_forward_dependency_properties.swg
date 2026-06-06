#global public

interface IUsingDeclForwardProperties
{
    mtd configure(properties: *UsingDeclForwardProperties);
}

struct UsingDeclForwardProperties
{
    app: *UsingDeclForwardApplication
}
