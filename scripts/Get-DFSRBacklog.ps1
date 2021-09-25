# Get-DFSRBacklog.ps1

# v3.0.2: Uses PrtgXml
# v3.0.1: Ping now checks multiple times
# v3.0: Script refactored for PowerShell 5/misc bugfixes by lordmilko
# v2.0: Script by Tim Boothby modified for PRTG
# v1.0: Original script by sgrinker

param(
    [string]$computer = "localhost"
)

$DebugPreference = "Continue"

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if(!(Get-Module -ListAvailable PrtgXml))
{
    Install-Package PrtgXml -ForceBootstrap -Force | Out-Null
}

function Main($computerName)
{
    try
    {
        $checker = [DFSRBacklog]::new($computerName)

        $pingable = $checker.Ping()

        if($pingable)
        {
            $namespaceExists = $checker.WMINamespaceExists("MicrosoftDFS")

            if($namespaceExists)
            {
                $checker.GetDFSRGroups()
                $checker.GetDFSRFolders()
                $checker.GetDFSRConnections()

                $checker.GetDFSRBacklogInfo()

                ShowOutput $checker.output
            }
            else
            {
                ShowError "MicrosoftDFS WMI Namespace does not exist on '$computer'.  Run locally on a system with the Namespace, or provide computer parameter of that system to run remotely."
            }
        }
        else
        {
            ShowError "The computer '$computer' did not respond to ping."
        }
    }
    catch [exception]
    {
        ShowError $_.Exception.Message
    }
    
}

function ShowOutput($msg)
{
    Prtg {
        $msg
    }
}

function ShowError($msg)
{
    Prtg {
        Error 1
        Text $msg
    }

    Exit
}

class DFSRBacklog
{
    $computerName
    $output

    $replicationGroups
    $replicationFolders
    $replicationConnections

    DFSRBacklog($computerName)
    {
        $this.computerName = $computerName
    }

    [bool]Ping()
    {
        $ping = New-Object System.Net.NetworkInformation.Ping

        for($i = 0; $i -lt 5; $i++)
        {
            trap
            {
                ShowError "The computer $($this.computerName) could not be resolved."
                continue
            }

            $reply = $ping.Send($this.computerName, 10)

            if($reply.Status -eq "Success")
            {
                return $true
            }

            Sleep 1
        }

        return $false
    }

    [bool]WMINamespaceExists($namespace)
    {
        Write-Debug "Checking WMI DFS Namespace exists"

        $namespaces = gwmi -class __Namespace -Namespace root -ComputerName $this.computerName | where name -eq $namespace

        if($namespaces.Name -eq $namespace)
        {
            return $true
        }
        else
        {
            return $false
        }
    }

    GetDFSRGroups()
    {
        Write-Debug "Retrieving replication groups"

        $this.replicationGroups = gwmi -ComputerName $this.computerName -Namespace "root\MicrosoftDFS" -Query "SELECT * FROM DfsrReplicationGroupConfig"
    }

    GetDFSRFolders()
    {
        Write-Debug "Retrieving replication folders"

        $this.replicationFolders = gwmi -ComputerName $this.computerName -Namespace "root\MicrosoftDFS" -Query "SELECT * FROM DfsrReplicatedFolderConfig"
    }

    GetDFSRConnections()
    {
        Write-Debug "Retrieving replication connections"

        $this.replicationConnections = gwmi -ComputerName $this.computerName -Namespace "root\MicrosoftDFS" -Query "SELECT * FROM DfsrConnectionConfig"
    }

    GetDFSRBacklogInfo()
    {
        Write-Debug "Retrieving backlog info"

        $this.output = ""

        foreach($replicationGroup in $this.replicationGroups)
        {
            $applicableFolders = $this.replicationFolders|where ReplicationGroupGUID -eq $replicationGroup.ReplicationGroupGUID

            foreach($folder in $applicableFolders)
            {
                $applicableConnections = $this.replicationConnections|where ReplicationGroupGUID -eq $replicationGroup.ReplicationGroupGUID

                foreach($connection in $applicableConnections)
                {
                    if($folder.Enabled -and $connection.Enabled)
                    {
                        $sourceMember = $null
                        $replicationMember = $null
                        $direction = $null

                        if($connection.Inbound)
                        {
                            $sourceMember = $connection.PartnerName.Trim()
                            $replicationMember = $this.computerName.ToUpper()
                            $direction = "In"                        
                        }
                        else
                        {
                            $replicationMember = $connection.PartnerName.Trim()
                            $sourceMember = $this.computerName.ToUpper()

                            $direction = "Out"
                        }

                        $this.GetMemberBacklog($sourceMember, $replicationMember, $direction, $replicationGroup.ReplicationGroupGUID, $folder.ReplicatedFolderName)
                    }
                }
            }
        }
    }

    GetMemberBacklog($sourceMember, $replicationMember, $direction, $replicationGroupGUID, $replicatedFolderName)
    {
        Write-Debug "Retrieving backlog from $($sourceMember.ToLower()) to $($replicationMember.ToLower()) for $replicatedFolderName"
        #$sourceMember = $connection.PartnerName.Trim()
        #$replicationMember = $this.computerName.ToUpper()

        $inboundPartner = $this.GetPartner($replicationMember, $replicationGroupGUID, $replicatedFolderName)
        $partnerFolder = gwmi -ComputerName $sourceMember -Namespace "root\MicrosoftDFS" -Query "SELECT * FROM DfsrReplicatedFolderConfig WHERE ReplicationGroupGUID = '$replicationGroupGUID' AND ReplicatedFolderName = '$replicatedFolderName'"

        if($partnerFolder.Enabled)
        {
            $outboundPartner = $this.GetPartner($sourceMember, $replicationGroupGUID, $replicatedFolderName)

            Write-Debug "Calculating backlog"
            $versionVector = $inboundPartner.GetVersionVector().VersionVector
            $backlogCount = $outboundPartner.GetOutboundBacklogFileCount($versionVector).BacklogFileCount

            $this.output += Result {
                Channel "$replicatedFolderName $direction"
                Value $backlogCount
                LimitMode 1
                LimitMaxError 0
            }
        }
    }

    [object]GetPartner($name, $replicationGroupGUID, $replicatedFolderName)
    {
        Write-Debug "Resolving partner $($name.ToLower())"

        $partner = gwmi -ComputerName $name -Namespace "root\MicrosoftDFS" -Query "SELECT * FROM DfsrReplicatedFolderInfo WHERE ReplicationGroupGUID = '$replicationGroupGUID' AND ReplicatedFolderName = '$replicatedFolderName'"|select -first 1

        if($partner -eq $null)
        {
            ShowError "Could not retrieve DFS Replication info from partner '$($name.ToLower())'; member may have experienced a dirty shutdown. Check Event Logs on server for further info."
        }

        if($partner.State -eq 5)
        {
            ShowError "Partner '$($name.ToLower())' reported DFS Replication has failed. Check Event Logs on the server for further info."
        }

        return $partner
    }
}

Main $computer