param(
    $Server,
    $Instance = "Default"
)

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$ErrorActionPreference = "Stop"

function Main($server, $instance)
{
    try
    {
        InstallModule SqlServer
        InstallModule PrtgXml

        Import-Module SqlServer

        CD SQLSERVER:\SQL\$server\$instance\Databases -WarningAction SilentlyContinue

        $databases = ls

        Prtg {
            foreach($database in $databases)
            {
                Result {
                    Channel $database.Name
                    Value (StatusToValue $database.Status)
                    ValueLookup prtg.customlookups.sqlserver.databasehealth
                }
            }
        }
    }
    catch [exception]
    {
        ShowError $_.exception.message
        Exit
    }
}

function InstallModule($name)
{
    if(!(Get-Module -ListAvailable $name))
    {
        Install-Package $name -ForceBootstrap -Force -AllowClobber | Out-Null
    }
}

function StatusToValue($status)
{
    switch($status)
    {
        "Normal" { return 0 }
        "Standby" { return 1 }

        "Restoring" { return 2 }
        "AutoClosed" { return 3 }
        "Recovering" { return 4 }
        "RecoveryPending" { return 5 }
        "EmergencyMode" { return 6 }

        "Shutdown" { return 7 }
        "Suspect" { return 8 }
        "Offline" { return 9 }
        "Inaccessible" { return 10 }
    }
}

function ShowError($msg)
{
    Prtg {
        Error 1
        Text $msg
    }
}

if(!$Server)
{
    ShowError "Please specify a SQL Server"
    Exit
}

Main $Server $Instance