$remoteCommands = {

    param($catalogName)

    function MainRemote($catalogName)
    {
        asnp citrix*
        $catalog = get-brokercatalog|where name -eq $catalogName

        if($catalog -eq $null)
        {
            throw "'$catalogName' is not a valid catalog"
        }

        $machines = get-brokermachine|where catalogname -eq $catalogName

        if($machines -eq $null)
        {
            throw "Catalog '$catalogName' does not contain any machines"
        }
    
        ProcessMachines $machines    
    }

    function ProcessMachines($machines)
    {
        Write-Host "<prtg>"

        foreach($machine in $machines)
        {
            $state = GetRegistrationState $machine

            Write-Host "<result>"
            Write-Host "<channel>$($machine.DNSName.Substring(0, $machine.DNSName.Indexof($env:userdnsdomain.ToLower()) - 1))</channel>"
            Write-Host "<value>$state</value>"
            Write-Host "<unit>Custom</unit>"
            Write-Host "<valuelookup>prtg.customlookups.citrix.registrationstate</valuelookup>"
            Write-Host "</result>"
        }

        Write-Host "</prtg>"
    }

    function GetRegistrationState($machine)
    {
        $state = -1

        if($machine.RegistrationState -eq "Registered")
        {
            $state = 0
        }
        elseif($machine.RegistrationState -eq "Initializing")
        {
            $state = 1
        }
        elseif($machine.RegistrationState -eq "Unregistered")
        {
            $state = 2
        }
        else
        {
            $state = 3
        }

        return $state
    }

    function ShowError($msg)
    {
        Write-Host "<prtg><error>1</error><text>$msg</text></prtg>"
        Exit
    }

    try
    {
        MainRemote $catalogName
    }
    catch [exception]
    {
        Write-Host "yes"

        if($_.exception.message -eq "Insufficient administrative privilege")
        {
            ShowError "Could not retrieve machine registration state: user $env:username did not have sufficient permissions to connect to Citrix. Please configure user as a Read-Only Administrator within Citrix Studio"
        }
        else
        {
            ShowError $_.exception.message
        }
    }
}

function Main($hostname, $catalogName)
{
    try
    {
        Invoke-Command -ComputerName $hostname -ErrorAction Stop -ScriptBlock $remoteCommands -Args @($catalogName)
    }
    catch [exception]
    {
        ShowError $_.exception.message
    }
}

function ShowError($msg)
{
    Write-Host "<prtg><error>1</error><text>$msg</text></prtg>"
    Exit
}

if(!$args[0])
{
    ShowError "Please specify a Citrix Delivery Controller"
}

if(!$args[1])
{
    ShowError "Please specify the machine catalog to retrieve the registration state of"
}

Main $args[0] $args[1]