#global public

using Core, Gui

// Visible strings of sCrypt.
//
// The declared values are the reference English wording, and each field is one
// translatable key. Translations live in `datas/lang/<tag>/scrypt.tweak`; a key a
// language file omits keeps its reference value. Read the active table through
// [[appStrings]]; never keep a copy across a language switch.
struct AppStrings
{
    ui_WindowTitle: string = "sCrypt — Private virtual drives"
    ui_Badge: string = "PORTABLE  |  PASSWORD-LOCKED  |  NO SETUP"
    ui_Subtitle: string = "Encrypted storage that looks and behaves like a regular Windows drive."
    ui_CreateCardTitle: string = "Create a new vault"
    ui_CreateCardHelp: string = "Choose a fixed capacity. The complete container is randomized before it is ready."
    ui_MountCardTitle: string = "Mount an existing vault"
    ui_MountCardHelp: string = "Unlock a container and expose it on any currently available drive letter."
    ui_ContainerFile: string = "CONTAINER FILE"
    ui_Browse: string = "Browse"
    ui_FixedCapacity: string = "FIXED CAPACITY"
    ui_Password: string = "PASSWORD"
    ui_ConfirmPassword: string = "CONFIRM PASSWORD"
    ui_RequiredPassword: string = "Required password"
    ui_EnterAgain: string = "Enter the password again"
    ui_ContainerPassword: string = "Container password"
    ui_ExistingContainer: string = "Existing encrypted container"
    ui_DriveLetter: string = "DRIVE LETTER"
    ui_DriveHelp: string = "The drive is available to Windows while sCrypt runs, then disappears when the app closes."
    ui_CreateVault: string = "Create encrypted vault"
    ui_MountDrive: string = "Mount drive"
    ui_Unmount: string = "Unmount"
    ui_Desktop: string = "Desktop"
    dlg_TitleCreate: string = "Create an sCrypt container"
    dlg_TitleOpen: string = "Open an encrypted container"
    dlg_BtnCreate: string = "Create"
    dlg_BtnOpen: string = "Open"
    msg_Ready: string = "Ready — create a vault or choose one to mount."
    msg_OperationStopped: string = "The operation stopped."
    msg_SystemError: string = "System error."
    msg_SizeInvalid: string = "The container size is invalid."
    msg_SizeTooLarge: string = "The container size is too large."
    msg_SizeMinimum: string = "The minimum container size is % MiB."
    msg_ChooseCreateFile: string = "Choose the container file to create."
    msg_FileExists: string = "This file already exists. Choose a new name to avoid data loss."
    msg_PasswordRequired: string = "A password is required."
    msg_PasswordMismatch: string = "The passwords do not match."
    msg_CreateFailed: string = "Could not create the container."
    msg_Randomizing: string = "Creating and randomizing the container..."
    msg_ChooseExisting: string = "Choose an existing container."
    msg_NoDriveLetter: string = "No drive letter is available."
    msg_StartingDriver: string = "Starting the portable filesystem driver..."
    msg_Unmounting: string = "Synchronizing and unmounting the encrypted drive..."
    msg_CreateStopped: string = "Container creation stopped."
    msg_Created: string = "Container created. It is ready to mount."
    msg_MountFailed: string = "Could not mount the virtual disk."
    msg_MountStopped: string = "Mount stopped."
    msg_Mounted: string = "Encrypted drive mounted on %. It will unmount when sCrypt closes."
    msg_UnmountSyncStopped: string = "The drive was unmounted, but final synchronization stopped."
    msg_Unmounted: string = "Drive unmounted safely."
}

private const FrenchStringsName = "lang/fr/scrypt.tweak"
private const FrenchStrings = #include("../datas/lang/fr/scrypt.tweak")

private var g_AppStrings: AppStrings

// Returns the visible strings of sCrypt in the active language.
func appStrings()->const &AppStrings => &g_AppStrings

// Registers the sCrypt string table and its embedded translations.
func registerAppStrings(bundle: *Core.Resources.Bundle)
{
    Gui.registerStrings'AppStrings(&g_AppStrings, "scrypt")
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)
}

// Build-time validation of the embedded translations: a mistyped key in a language
// file is a compile error with its line number, not a runtime fallback.
#run
{
    expect Gui.validateStrings'AppStrings(cast(string) FrenchStrings)
}
