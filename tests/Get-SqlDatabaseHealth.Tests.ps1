Describe "Get-SqlDatabaseHealth.Tests" {

    Context "Parameter validation" {
        It "doesn't specify a server" {
            & "$PSScriptRoot\Get-SqlDatabaseHealth.ps1" | Should Be "<Prtg>`r`n    <Error>1</Error>`r`n    <Text>Please specify a SQL Server</Text>`r`n</Prtg>"
        }

        It "doesn't specify an instance" {

        }
    }

    Context "Server validation" {
        It "can't find the server" {

        }

        It "can't find the instance" {

        }
    }

    It "retrieves health successfully" {
        
    }

    It "requires 64-bit PowerShell" {

    }
}