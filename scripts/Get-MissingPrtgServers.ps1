################
# Configuration

$prtgServer = $null
$prtgUserName = $null
$prtgPassword = $null

################

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Main($path, $probeName, $exclusions)
{
    if(!(Get-Module -ListAvailable PrtgAPI))
    {
        Install-Package PrtgAPI -ForceBootstrap -Force | Out-Null
    }

    if(!(Get-Module -ListAvailable PrtgXml))
    {
        Install-Package PrtgXml -ForceBootstrap -Force | Out-Null
    }

    try
    {
        Connect-PrtgServer $prtgServer (New-Credential $prtgUserName $prtgPassword) -Force

        $scope = GetScope $path

        $missingServers = GetComputers $scope $probeName $exclusions

        if($missingServers.Count -eq 0)
        {
            Prtg {
                Result {
                    Channel "Missing Servers"
                    Value $missingServers.Count
                }
            }
        }
        else
        {
            $msg = [string]::Join(", ", $missingServers).ToLower()

            ShowError "The following servers are missing from PRTG: $msg."
        }
        }
    catch [exception]
    {
        ShowError $_.Exception.Message
    }    
}

function GetScope($path)
{
    $scope = ""

    $pathTokens = $path.Split("/")

    for($i = $pathTokens.Count - 1; $i -ge 0; $i--)
    {
        $scope += "OU=$($pathTokens[$i]),"
    }

    $domain = (gwmi win32_computersystem).domain

    $tokens = $domain.Split(".")    

    for($i = 0; $i -lt $tokens.Count; $i++)
    {
        $scope += "DC=$($tokens[$i])"

        if($i -lt $tokens.Count -1)
        {
            $scope += ","
        }
    }

    return $scope
}

function GetComputers($base, $probeName, $exclusions)
{
    $adComputers = get-adcomputer -searchbase $base -filter *|select -expand Name

    $prtgServers = get-probe $probeName|get-device|select -expand host

    $allMissing = $adComputers|where {$prtgServers -notcontains $_}

    $afterExclusions = $allMissing|where {$exclusions -notcontains $_}

    return $afterExclusions
}

function ShowError($msg)
{
    Prtg {
        Error 1
        Text $msg
    }

    Exit
}

#search the whole probe for our devices
#have a parameterset for probe id or probe name

if (!$prtgServer)
{
    ShowError "Please modify this script to specify the PRTG Server to monitor"
}

if (!$prtgUserName)
{
    ShowError "Please modify this script to specify the username to authenticate to PRTG with"
}

if (!$prtgPassword)
{
    ShowError "Please modify this script to specify the password to authenticate to PRTG with"
}

if(!$args[0])
{
    ShowError "Please specify an OU search path in the form of OU/SubOU"
}

if(!$args[1])
{
    ShowError "Please specify the probe to analyze"
}

$exclusions = @()

if($args[2])
{
    $exclusions = ($args[2]).Split(",")
}

#Main "Contoso/Servers" * "excluded-1","excluded-2"

Main $args[0] $args[1] $exclusions