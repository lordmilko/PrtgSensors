# Install-WindowsFeature rsat-clustering-powershell

# PSx64 Get-ClusterStatus.ps1 (cluster cmdlets are 64-bit only)
# Grant permissions on cluster to PRTG account

function Main($cluster)
{
    try
    {
        $nodes = Get-ClusterNode -cluster $cluster
        $resources = get-clusterresource -cluster $cluster
    
        Prtg {
            foreach($node in $nodes)
            {
                Result {
                    Channel $node.Name
                    Value (GetNodeState $node.State)
                    ValueLookup prtg.customsensors.sql.nodestate
                }
            }

            foreach($resource in $resources)
            {
                Result {
                    Channel $resource.Name
                    Value (GetResourceState $resource.State)
                    ValueLookup prtg.customsensors.onlineoffline
                }
            }
        }
    }
    catch [exception]
    {
        ShowError $_.exception.Message
    }
    
}

function GetNodeState($value)
{
    switch($value)
    {
        "Up" { return 0 }
        "Joining" { return 1 }
        "Down" { return 2 }
    }
}

function GetResourceState($value)
{
    switch($value)
    {
        "Online" { return 0 }
        "Offline" { return 1 }
    }
}

function ShowError($msg)
{
    Prtg {
        Error 1
        Text $msg
    }
}

if(!$args[0])
{
    ShowError "Please specify a cluster name"
    Exit
}

Main $args[0]