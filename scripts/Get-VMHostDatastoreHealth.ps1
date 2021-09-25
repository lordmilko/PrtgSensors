################
# Configuration

$viServer = $null

################

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if(!(Get-Module -ListAvailable vmware.vimautomation.core))
{
    Install-Package VMware.PowerCLI -ForceBootstrap -Force | Out-Null
}

function ShowError($msg)
{
    Write-Host "<prtg><error>1</error><text>$msg</text></prtg>"
}

if(!($args[0]))
{
    ShowError "Please specify a hostname"
    Exit
}
else
{
    $hostname = $args[0]

    import-module vmware.vimautomation.core

    connect-viserver $viServer -ErrorAction SilentlyContinue|Out-Null
    $events = get-vievent|where {$_.eventtypeid -eq "esx.problem.scsi.device.io.latency.high" -and $_.objectname.startswith($hostname)}|sort createdtime

    if($events.Count -gt 0)
    {
        $last = $events|select -last 1

        ShowError "$([int]((get-date) - $last.CreatedTime).TotalMinutes)m ago: $($last.FullFormattedMessage)"
    }
    else
    {
        Write-host "<prtg><result><channel>Value</channel><value>0</value></result></prtg>"
    }

    disconnect-viserver -Confirm:$false
}