# PRTG Custom Sensors
Custom Sensors for use with PRTG Network Monitor

\* = Not yet uploaded

| Name                                                             | Product                    | Description                                          |
| :--------------------------------------------------------------- | :------------------------- | :--------------------------------------------------- |
| * [Get-CitrixConnectionsAllowed](#get-veeambackupstatusps1)      | Citrix XenApp/XenDesktop   | Monitors VDA Servers in Maintenance Mode             |
| [Get-CitrixRegistrationState](#get-citrixregistrationstateps1)   | Citrix XenApp/XenDesktop   | Monitors the registration state of VDA Servers       |
| [Get-DFSRBacklog](#get-dfsrbacklogps1)                           | DFS Replication            | Monitors DFS Backlog between two servers             |
| * [Get-ExchangeBackPressure](#get-exchangebackpressureps1)       | Exchange                   | Monitors Exchange Back Pressure                      |
| [Get-ClusterStatus.ps1](#get-clusterstatusps1)                   | Failover Clustering        | Monitors the health of cluster nodes/resources       |
| * [TCPing.ps1](#tcpingps1)                                       |                            | PowerShell port of [tcping](https://www.elifulkerson.com/projects/tcping.php) for use with PRTG          |
| [Get-MissingPrtgServers](#get-missingprtgserversps1)             | PRTG Network Monitor         | Monitors servers in AD missing from PRTG             |
| [PSx64](#psx64)                                                   | PRTG Network Monitor       | Elevates PowerShell scripts to run as 64-bit         |
| * [Get-RDSConnectionsAllowed](#get-rdsconnectionsallowedps1)     | Remote Desktop Services    | Monitors Terminal Servers denying new connections    |
| * [Get-RDSSessionHealth](#get-rdssessionhealthps1)               | Remote Desktop Services    | Monitors null sessions/locked profile disks          |
| [Get-SqlDatabaseHealth](#get-sqldatabasehealthps1)               | SQL Server                 | Monitors the health of SQL Server databases          |
| [Get-VeeamBackupStatus.ps1](#get-veeambackupstatusps1)           | Veeam Backup & Replication | Realtime monitoring of Veeam Backup Jobs             |
| * [Get-VeeamBackupCount.ps1](#get-veeambackupcountps1)           | Veeam Backup & Replication | Monitors the number of backups completed per day     |
| * [Get-MissingBackupVMs](#get-missingbackupvmsps1)               | Veeam Backup & Replication | Gets VMs in vCenter missing from any backup jobs in Veeam |
| * [Get-vCenterServiceStatus](#get-vcenterservicestatusps1)       | VMware vCenter (VCSA)      | Monitors vCenter services on VCSA 6.5+               |
| [Get-VMHostDatastoreHealth](#get-vmhostdatastorehealthps1)       | VMware vCenter             | Monitor latency spikes on a datastore for when its disk is on the fritz |

The following modules are used across these scripts, and will be automatically installed if they are found to be missing

* PrtgAPI
* PrtgXml
* PoSh-SSH
* SqlServer
* VMware PowerCLI

If you encounter any errors with any of the scripts that use these modules, it could be worth trying to install these modules manually yourself (note that for most scripts, these will need to be installed in the 32-bit version of PowerShell on your PRTG Probe).

Polishing scripts to meet the bare minimum of publishing to the internet is non-zero work; if any of the above missing scripts interest you please open an issue and I'll look at uploading them.

No guarantee is given as to the safety or reliability of any of the scripts in this repo.

## Get-CitrixRegistrationState.ps1

Monitors the registration state of machines in a specified machine catalog on a specified Citrix Delivery Controller. Tested with XenApp/XenDesktop 7.12 or so (it's been years since I used Citrix).

### Files

* Scripts\Get-CitrixRegistrationState.ps1
* Lookups\prtg.customlookups.citrix.registrationstate.ovl

### Installation

1. Copy **Get-CitrixRegistrationState.ps1** to *C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML*
2. Copy **prtg.customlookups.citrix.registrationstate.ovl** to *C:\Program Files (x86)\PRTG Network Monitor\lookups\custom*
3. Refresh the lookups in PRTG by going to Setup -> System Administration -> Administrative Tools -> Load Lookups and File Lists
4. Create a new EXEXML sensor, specifying
    * **Parameters:** The Citrix Delivery Controller address (e.g. `%host`) and the name of the machine catalog to monitor
    * **Security Context:** Use Windows credentials of the parent device

### Notes

This module uses remote PowerShell to execute the required commands on the specified Citrix Delivery Controller where the required Citrix PowerShell Module would be installed. As such considerations may need to be made to ensure the specified device can accept remote PowerShell requests from your PRTG Probe server (such as making sure you're connecting via the device's hostname rather than IP, that it can accept such remote connections in the first place, etc)

## Get-DFSRBacklog.ps1

Monitors the number of files waiting to be replicated in all DFS Replication groups present on a specified computer. This script is a significantly refactored version of the `Get-DFSRBacklog.ps1` script originally written by sgrinker and modified for PRTG by Tim Boothby. Contains additional bugfixes I encountered when trying to use their script for myself.

### Files

* Scripts\Get-DFSRBacklog.ps1

### Installation

1. Copy **Get-DFSRBacklog.ps1** to *C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML*
2. Create a new EXEXML sensor specifying
    * **Parameters:** The name of the device to monitor (e.g. `%host`)

You may also need to change the Security Context of the sensor to run in the context of the Windows credentials of the parent device, I'm not sure.

## Get-ClusterStatus.ps1

Monitors the status of all nodes and resources in a specified Windows Failover Cluster. This script was specifically designed for use with SQL Server Always On Availability groups (which integrates with Failover Clustering) however presumably it can be used with any other type of Failover Cluster as well. Custom lookups are used to make the status of each component look pretty.

### Files

* Scripts\Get-ClusterStatus.ps1
* Lookups\prtg.customlookups.onlineoffline.ovl
* Lookups\prtg.customlookups.sql.nodestate.ovl

### Installation

1. Install the Failover Clustering PowerShell module on your PRTG Probe of it isn't already installed (`Install-WindowsFeature rsat-clustering-powershell`)
2. Grant permissions to access the cluster to the user account the sensor will be scanned under (I don't remember how to do this, that's just what my notes say)
3. Compile and install [PSx64](#psx64) if you haven't already
4. Copy **Get-ClusterStatus.ps1** to *C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML*
5. Copy **prtg.customlookups.onlineoffline.ovl** and **prtg.customlookups.sql.nodestate.ovl** to *C:\Program Files (x86)\PRTG Network Monitor\lookups\custom*
6. Refresh the lookups in PRTG by going to Setup -> System Administration -> Administrative Tools -> Load Lookups and File Lists
7. Create a new EXEXML sensor specifying
    * **Script:** PSx64.exe
    * **Parameters:** `Get-ClusterStatus.ps1 <clusterName>` where **&lt;clusterName&gt;** is the name of the cluster to monitor

## Get-MissingPrtgServers.ps1

Alerts when devices in a specified OU in Active Directory do not exist in a specified probe within PRTG.

### Files

* Scripts\Get-MissingPrtgServers.ps1

### Installation

1. Copy **Get-MissingPrtgServers.ps1** to *C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML*
2. Modify the script to specify the server, username and password to authenticate to PRTG with at the top of the file. This should be a read-only API user you have created specifically for such purposes
3. Create a new EXEXML sensor specifying
    * **Parameters:** the path to the OU to monitor (e.g. if you have `contoso.local/Contoso/Servers`, then you should specify the value `Contoso/Servers`), a wildcard expression that matches the probe(s) to check for devices in, and a comma delimited list of devices to exclude from the monitoring

You may also need to change the Security Context of the sensor to run in the context of the Windows credentials of the parent device, I'm not sure.

### Notes

Devices are determined to be present or missing by comparing their Active Directory `Name` with their PRTG `Host`. If you're using FQDNs or IP Addresses for your hosts you'll need to modify the script to incorporate that logic (maybe use the Active Directory object's `DNSHostName` instead of `Name`)

## PSx64

Executes a specified EXEXML script within 64-bit PowerShell rather than 32-bit PowerShell. Since the PRTG Probe is (as of writing) a 32-bit process, when it attempts to execute your EXEXML scripts, it is forced to execute them in a 32-bit version of PowerShell. This is an issue however when utilizing third party modules that are exclusively 64-bit only. PSx64 allows you to work around this by instead specifying your script and all of its arguments to this simple utility, which then launches your script under PowerShell 64-bit and emits all of its output back to PRTG.

### Files

* PSx64\PSx64.sln (Open in Visual Studio)

This program needs to be compiled before use. Install the latest version of Visual Studio (the Community edition is free) and compile in Release mode. The resulting EXE will be in the `bin\Release` directory

### Installation

1. Copy **PSx64.exe** to *C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML*
2. Create a new EXEXML sensor, specifying
    * **Script:** PSx64.exe
    * **Parameters:** The name of your script (e.g. EpicScript.ps1) followed by any parameters that need to be passed to the script

## Get-SqlDatabaseHealth.ps1

Monitors the health of all databases within a given SQL Server. A custom lookup is used to identify the health status of each database.

### Files

* Scripts\Get-SqlDatabaseHealth.ps1
* Lookups\prtg.customlookups.sqlserver.databasehealth.ovl

### Installation

1. Copy **Get-SqlDatabaseHealth.ps1** to *C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML*
2. Copy **prtg.customlookups.sqlserver.databasehealth.ovl** to *C:\Program Files (x86)\PRTG Network Monitor\lookups\custom*
3. Refresh the lookups in PRTG by going to Setup -> System Administration -> Administrative Tools -> Load Lookups and File Lists
4. Create a new EXEXML sensor, specifying
    * **Parameters:** The SQL Server address (e.g. `%host`) and optional instance name (e.g. `sql-1 SQLEXPRESS`)
    * **Security Context:** Use Windows credentials of the parent device
    * **Timeout:** 3 minutes
5. Reduce the interval of the sensor to once every 5 minutes

## Get-VeeamBackupStatus.ps1

Monitors Veeam Backup & Replication jobs. Includes last backup status, time to next backup, how long backup has been running for and the time since the last backup. Custom status message shows pertinent data based on the current state of the job. A custom lookup enhances the Backup State channel to identify the state of the last backup. When warnings or errors occur, displays the status text of such messages on the sensor within PRTG.

Get-VeeamBackupStatus.ps1 should be compatible with all backup types, and has been tested with the following

* Backup
* Backup Copy
* Tape
* Replication
* Agent (requires Veeam Agent for Windows 2.0+)

### Files

* Scripts\Get-VeeamBackupStatus.ps1
* Lookups\prtg.customlookups.veeam.backupstate.ovl

### Installation

1. Install the Veeam Backup & Replication Console on your PRTG Probe Server
2. Copy **Get-VeeamBackupStatus.ps1** to *C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML*
3. Copy **prtg.customlookups.veeam.backupstate.ovl** to *C:\Program Files (x86)\PRTG Network Monitor\lookups\custom*
4. Refresh the lookups in PRTG by going to Setup -> System Administration -> Administrative Tools -> Load Lookups and File Lists
5. Create a new EXEXML sensor, specifying
    * **Parameters:** Veeam Server Hostname, backup job name
    * **Security Context:** Use Windows credentials of the parent device
6. Reduce the interval of the sensor. An interval of 1 hour is recommended

### Notes

Severe performance issues can arise when a large number of *continuous* backup jobs have been configured for use with Get-VeeamBackupStatus. To reduce the impact of these jobs, it is recommended to modify the Session history retention to a lower value from within Veeam Backup & Replication (Menu -> General Options -> History).

As of writing, works with Veeam Backup & Replication 11. To put it bluntly, this script is an epic abomination that attempts to bypass Veeam's crappy PowerShell library (some cmdlets actually retrieve *all objects* of a given type before filtering(!)) to achieve high performance per-job Veeam monitoring at an MSP doing backups every hour across 40 or so different backup jobs. This script (for the most part) completely bypasses Veeam's PowerShell library and tampers with the underlying .NET types directly. This script can and will break with any given Veeam update.

This script exposes bugs in the PowerShell ISE's handling of PowerShell classes - often setting a breakpoint inside of them will not work - you have to break on Main and step in all the way directly. This script does not require Veeam Enterprise Manager. No attempt is made at backwards compatibility; when Veeam breaks the script, I fix it to make it work. No guarantee is made that such corrections will be uploaded to GitHib; this script is great, but be prepared to get your hands dirty when it breaks.

### Known Issues

* Setting breakpoints and trying to debug issues in PowerShell ISE can be super annoying; that's just how it is - try to set a breakpoint on `Main` and step your way through
* `Disconnect-VBRServer` is mega slow in Veeam 11; make sure the sensor has a big enough timeout

## Get-VMHostDatastoreHealth.ps1

Monitors the health of a VMware datastore when its underlying physical hard drive appears to be malfunctioning. This sensor crudely monitors for any `esx.problem.scsi.device.io.latency.high` events that are being thrown on your system for a specified host, and if any are found the sensor enters an error state displaying the the last error that ESXi threw for one of your datastores.

### Files

* Scripts\Get-VMHostDatastoreHealth.ps1

### Installation

1. Copy **Get-VMHostDatastoreHealth.ps1** to *C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML*
2. Modify the script to specify the path to your vCenter server. If you want to use this with multiple servers you'll need to refactor this script to take the server name as an argument
3. Create a new EXEXML sensor, specifying
    * **Parameters:** The name of the ESXi host in vCenter whose datastores should be monitor
    * **Security Context:** Use Windows credentials of the parent device