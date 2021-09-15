# PRTG Custom Sensors
Custom Sensors for use with PRTG Network Monitor

\* = Not yet uploaded

| Name                                                             | Product                    | Description                                          |
| :--------------------------------------------------------------- | :------------------------- | :--------------------------------------------------- |
| * [Get-CitrixConnectionsAllowed](#get-veeambackupstatusps1)      | Citrix XenApp/XenDesktop   | Monitors VDA Servers in Maintenance Mode             |
| * [Get-CitrixRegistrationState](#get-citrixregistrationstateps1) | Citrix XenApp/XenDesktop   | Monitors the registration state of VDA Servers       |
| * [Get-DFSRBacklog](#get-dfsrbacklogps1)                         | DFS Replication            | Monitors DFS Backlog between two servers             |
| * [Get-ExchangeBackPressure](#get-exchangebackpressureps1)       | Exchange                   | Monitors Exchange Back Pressure                      |
| * [Get-ClusterStatus.ps1](#get-clusterstatusps1)                 | Failover Clustering        | Monitors the health of cluster nodes/resources       |
| * [TCPing.ps1](#tcpingps1)                                       |                            | PowerShell port of [tcping](https://www.elifulkerson.com/projects/tcping.php) for use with PRTG          |
| * [Get-MissingPrtgServers](#get-missingprtgserversps1)           | PRTG Network Monitor       | Monitors servers in AD missing from PRTG             |
| * [PSx64](psx64)                                                 | PRTG Network Monitor       | Elevates PowerShell scripts to run as 64-bit         |
| * [Get-RDSConnectionsAllowed](#get-rdsconnectionsallowedps1)     | Remote Desktop Services    | Monitors Terminal Servers denying new connections    |
| * [Get-RDSSessionHealth](#get-rdssessionhealthps1)               | Remote Desktop Services    | Monitors null sessions/locked profile disks          |
| [Get-SqlDatabaseHealth](#get-sqldatabasehealthps1)               | SQL Server                 | Monitors the health of SQL Server databases          |
| [Get-VeeamBackupStatus.ps1](#get-veeambackupstatusps1)           | Veeam Backup & Replication | Realtime monitoring of Veeam Backup Jobs             |
| * [Get-VeeamBackupCount.ps1](#get-veeambackupcountps1)           | Veeam Backup & Replication | Monitors the number of backups completed per day     |
| * [Get-MissingBackupVMs](#get-missingbackupvmsps1)               | Veeam Backup & Replication | Gets VMs in vCenter missing from any backup jobs in Veeam |
| * [Get-vCenterServiceStatus](#get-vcenterservicestatusps1)       | VMware vCenter (VCSA)      | Monitors vCenter services on VCSA 6.5+               |
| * [Get-HostDatastoreHealth](#get-hostdatastorehealthps1)         | VMware vCenter             | Monitor latency spikes on a datastore for when its disk is on the fritz |


sqlserverhealth: 3 minute timeout, 5 minute interval
sqlserver module requires psx64

The following modules are used across these scripts, and will be automatically installed if they are found to be missing

* PrtgAPI
* PrtgXml
* PoSh-SSH
* SqlServer

Polishing scripts to meet the bare minimum of publishing to the internet is non-zero work; if any of the above missing scripts interest you please open an issue and I'll look at uploading them.

No guarantee is given as to the safety or reliability of any of the scripts in this repo.

## Get-VeeamBackupStatus.ps1

Monitors Veeam Backup & Replication jobs. Includes last backup status, time to next backup, how long backup has been running for and the time since the last backup. Custom status message shows pertinent data based on the current state of the job. Custom lookup enhances the Backup State channel to identify the state of the last backup.

Get-VeeamBackupStatus.ps1 should be compatible with all backup types, and has been tested with the following

* Backup
* Backup Copy
* Tape
* Replication
* Agent (requires Veeam Agent for Windows 2.0)

### Files

* Scripts\Get-VeeamBackupStatus.ps1
* Lookups\prtg.customlookups.veeam.backupstate.ovl

### Installation

1. Install the Veeam Backup & Replication Console on your PRTG Probe Server
2. Copy **Get-VeeamBackupStatus.ps1** to *C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML*
3. Copy **prtg.customlookups.veeam.backupstate.ovl** to *C:\Program Files (x86)\PRTG Network Monitor\lookups\custom*
4. Create a new EXEXML sensor, specifying
    * **Parameters:** Veeam Server Hostname, backup job name
    * **Security Context:** Use Windows credentials of the parent device
5. Reduce the interval of the sensor. An interval of 1 hour is recommended

### Notes

Severe performance issues can arise when a large number of *continuous* backup jobs have been configured for use with Get-VeeamBackupStatus. To reduce the impact of these jobs, it is recommended to modify the Session history retention to a lower value from within Veeam Backup & Replication (Menu -> General Options -> History).

As of writing, works with Veeam Backup & Replication 11. To put it bluntly, this script is an epic abomination that attempts to bypass Veeam's crappy PowerShell library (some cmdlets actually retrieve *all objects* of a given type before filtering(!)) to achieve high performance per-job Veeam monitoring at an MSP doing backups every hour across 40 or so different backup jobs. This script (for the most part) completely bypasses Veeam's PowerShell library and tampers with the underlying .NET types directly. This script can and will break with any given Veeam update.

This script exposes bugs in the PowerShell ISE's handling of PowerShell classes - often setting a breakpoint inside of them will not work - you have to break on Main and step in all the way directly. This script does not require Veeam Enterprise Manager. No attempt is made at backwards compatibility; when Veeam breaks the script, I fix it to make it work. No guarantee is made that such corrections will be uploaded to GitHib; this script is great, but be prepared to get your hands dirty when it breaks.

### Known Issues

* Setting breakpoints and trying to debug issues in PowerShell ISE can be super annoying; that's just how it is - try to set a breakpoint on `Main` and step your way through
* `Disconnect-VBRServer` is mega slow in Veeam 11; make sure the sensor has a big enough timeout
