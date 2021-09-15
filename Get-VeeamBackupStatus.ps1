# Get-VeeamBackupStatus.ps1
# Copyright lordmilko, 2016

# Changelog
# #########
# v1.3.16: Fix [DateTime] cast using invariant culture instead of current culture, support Veeam 11
# v1.3.15: Update to use PrtgXml, Fix crash where NextRun is an empty string when backup job is disabled
# v1.3.14: Fixed a bug wherein script would fail to detect when job that hadn't run yet was disabled
# v1.3.13: Fixed a bug wherein Veeam 9.5u3 renamed $session.Progress.StartTime to StartTimeLocal
# v1.3.12: Refactored output format
# v1.3.11: Implemented Disabled Backup State
# v1.3.10: Fixed error handling when a job is disabled
# v1.3.9: Fixed a bug wherein a failed tape job might not display a failure message
# v1.3.8: Implemented custom database logic for Backup Copy session enumeration
# v1.3.7: Removed Endpoint Backup Event Viewer probing functionality
# v1.3.6: Replaced EXEXML generation with PrtgAPI.CustomSensors
# v1.3.5: Implemented backup status channel. Requires prtg.customlookups.veeam.backupstate.ovl be installed in PRTG Network Monitor\lookups\custom folder on PRTG Core Server
# v1.3.4: Fixed last backup start time detection
# v1.3.3: Fixed a bug wherein CBackupJob::Get didn't include a return statement
# v1.3.2: Fixed a bug wherein PRTG would treat a null last session as an empty string instead of null
# v1.3.1: Implemented Veeam Endpoint monitoring with localdb error message analysis
# v1.3: Refactored to use PowerShell 5 Classes
# v1.2.6: Fixed a bug where a disabled continuous Backup Copy job detected the second last instead of the last session that ran
# v1.2.5: Moved remote functions out of GetBackupStatus
# v1.2.4: Replaced PowerShell Remoting with Veeam 9 Support, modified script to force running in 64-bit process
# v1.2.3: Fixed a bug wherein running backups didn't detect whether their job was now disabled
# v1.2.2: Removed Veeam Endpoint compatibility, migrated functionality to a new script capable of reading email messages
# v1.2.1: Fixed an issue wherein the Veeam Endpoint NextTime displays in US format instead of AU
# v1.2: Refactored backup job/session acquisition using internal API
# v1.1.9: Replaced connecting directly to SQL Server with call to undocumented method CBackupSession::GetByJob
# v1.1.8: Updated Backup Copy jobs to use all warnings and errors log XML, rather than final error value
# v1.1.7: Continuous Backup Copy jobs now talk to the SQL Server to find the last backup session details when the current session is idle
# v1.1.6: Sensor now shows backup job completion percentage
# v1.1.5: Modified failure for multiple backups display reason for backup failures
# v1.1.4: Disabled check for "working" for running backups
# v1.1.3: Rewrote ProcessBackupSessionResult if-statements to remove implicit job status from session result
# v1.1.2: Fixed a bug where the server name was not passed to GetBackupJobResult
# v1.1.1: Fixed a bug where duration would display as null instead of 0 when job had just started
# v1.1: Veeam Endpoint Protection support
# v1.0: Initial release

#$invocationPath = "$($PSScriptRoot)\$($MyInvocation.MyCommand.Name)"

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if(!(Get-Module -ListAvailable PrtgXml))
{
    Install-Package PrtgXml -ForceBootstrap -Force | Out-Null
}

function Main($server, $jobName)
{
    $DebugPreference="Continue"

    [Logger]::Log("Entered Main")

    $ErrorActionPreference="SilentlyContinue"

    [VeeamBackupStatus]::new($server, $jobName).GetStatus()
}

function RunAs64Bit($server, $jobName)
{
    [Logger]::Log("Entered RunAs64Bit")

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo

    $startInfo.FileName = "C:\Windows\sysnative\WindowsPowerShell\v1.0\powershell.exe"
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.Arguments = "-file `"$($invocationPath)`" $($server) `"$($jobName)`""

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $process.Start()|Out-Null
    $process.WaitForExit()
    
    $output = $process.StandardOutput.ReadToEnd()
    $output += $process.StandardError.ReadToEnd()

    Write-Host $output
}

#PowerShell 5 ISE may complain if unloaded types are referred to in classes

function CBackupJob::GetAll            { return [Veeam.Backup.Core.CBackupJob]::GetAll() }
function CBackupJob::Get($name)        { return [Veeam.Backup.Core.CBackupJob]::Get($name) }
function CBackupSession::GetByJob($id) { return [Veeam.Backup.Core.CBackupSession]::GetByJob($id) }

function CDBManager::GetSessionsForJob($id) { return [Veeam.Backup.DBManager.CDBManager]::Instance.BackupJobsSessions.GetSessionsForJob($id) }
function CBackupSession::Create($info) { return [Veeam.Backup.Core.CBackupSession]::Create($info, $null) }

function SessionManager::GetByJob($id) { return [VeeamBackupStatus.SessionManager]::GetByJob($id) }

#region Classes

class VeeamBackupStatus
{
    [string]$server
    [string]$jobName

    VeeamBackupStatus($server, $jobName)
    {
        $this.server = $server
        $this.jobName = $jobName
    }

    [void]GetStatus()
    {
        [Logger]::Log("Entered [VeeamBackupStatus]::GetStatus")

        try
        {
            $this.GetStatusInternal()
        }
        catch [exception]
        {
            $ex = "An exception occurred while trying to process backups: " + $_.Exception.message

            if($ex -like "*snap-ins have been registered*")
            {
                $ex = "Could not load Veeam PowerShell Module. Please check Veeam Backup & Replication Console is installed on PRTG Probe."
            }

            [PrtgLogger]::Error($ex)
        }
        finally
        {
            [VeeamBackupStatus]::Quit()
        }
    }

    hidden [void]GetStatusInternal()
    {
        [Logger]::Log("Entered [VeeamBackupStatus]::GetStatusInternal")

        $this.Init()

        $backup = $this.GetBackupsToProcess()

        $handler = $this.GetBackupHandler($backup)
        $handler.GetStatus()
    }

    hidden [void]Init()
    {
        [Logger]::Log("-Loading Veeam PSSnapIn")
        #Add-PSSnapin -Name VeeamPSSnapIn -ErrorAction Stop
        ipmo "C:\Program Files\Veeam\Backup and Replication\Console\Veeam.Backup.PowerShell\Veeam.Backup.PowerShell.psd1" -DisableNameChecking

        [Logger]::Log("-Connecting to Veeam Backup Server")
        Disconnect-VBRServer
        Connect-VBRServer -Server $this.server -Timeout 20
    }

    hidden [object]GetBackupsToProcess()
    {
        [Logger]::Log("Entered [VeeamBackupStatus]::GetBackupsToProcess")

        return CBackupJob::Get($this.jobName)
    }

    [object]GetBackupHandler($backup)
    {
        [Logger]::Log("Entered [VeeamBackupStatus]::GetBackupHandler")

        $handler = $null

        if($backup -eq $null)
        {
            $handler = [NullBackupHandler]::new($backup, $this.jobName)
        }
        else
        {
            switch($backup.JobType)
            {
                {$_ -in "Backup","Replica","BackupSync","EndpointBackup"} { $handler = [BackupHandler]::new($backup, $this.jobName) }
                {$_ -in "VmTapeBackup","FileTapeBackup"}                  { $handler = [TapeBackupHandler]::new($backup, $this.jobName) }
                default                                                   { $handler = [UnknownJobTypeBackupHandler]::new($backup, $this.jobName) }
            }
        }

        [Logger]::Log("-Using backup handler [$($handler.GetType())]")

        return $handler
    }

    static [void]Quit()
    {
        Disconnect-VBRServer
        try
        {
            #Exit
        }
        catch {}
    }
}

#region Backup Handlers

class BaseBackupHandler
{
    $job
    $jobName

    $STATE_SUCCESS = 0
    $STATE_RUNNING = 1
    $STATE_WARNING = 2
    $STATE_ERROR = 3
    $STATE_DISABLED = 4

    BaseBackupHandler($job, $jobName)
    {
        $this.job = $job
        $this.jobName = $jobName
    }

    [void]GetStatus()
    {
        throw "Missing implementation of [$($this.GetType())]::GetStatus()"
    }

    [string]CleanFailedVMDetails($details)
    {
        return $details -replace "\.<br />",". " -replace "<br />",". " -replace "`n", ". " -replace "\.\.", "." -replace "<","&lt;" -replace ">","&gt;"
    }
}

class NullBackupHandler : BaseBackupHandler
{
    NullBackupHandler($job, $jobName) : base($job, $jobName)
    {
    }

    [void]GetStatus()
    {
        [Logger]::Log("Entered [NullBackupHandler]::GetStatus")

        [PrtgLogger]::Error("'$($this.job)' is not a valid Veeam Backup or Replication job")
    }
}

class BackupHandler : BaseBackupHandler
{
    BackupHandler($job, $jobName) : base($job, $jobName)
    {
    }

    [void]GetStatus()
    {
        [Logger]::Log("Entered [BackupHandler]::GetStatus")

        $session = $this.GetLastSession()

        if($session -ne $null)
        {
            $this.ProcessBackupSession($session)
        }
    }

    [object]GetLastSession() #need to figure out what the actual type is and then update this and basebackuphandlers return type
    {
        [Logger]::Log("Entered [BackupHandler]::GetLastSession")

        $lastSession = $this.job.FindLastSession()
    
        if($lastSession.IsWorking -eq $false -and $this.job.IsContinuous -and $this.job.CanRunByScheduler()) #If idling, continuous and not disabled
        {
            $secondLast = $this.GetSecondLastSession()

            if($secondLast -ne $null)
            {
                $lastSession = $secondLast
            }
        }

        if($lastSession -eq $null -or $lastSession -eq "")
        {
            [PrtgLogger]::Error("Backup job has not run yet. First Run:$([TimeFormatter]::GetNextBackupStartTimeText($this.job.GetScheduleOptions().NextRun))")
            return $null
        }

        [Logger]::Log("-Last Session is $($lastSession.Id) ($($lastSession.EndTime))")

        return $lastSession
    }

    [object]GetSecondLastSession()
    {
        [Logger]::Log("Entered [BackupHandler]::GetSecondLastSession")

        [Logger]::Log("-Getting backup sessions for job $($this.job.Id)")

        $info = (CDBManager::GetSessionsForJob $this.job.Id)|sort creationtime -Descending|select -first 2

        if($info.Count -eq 2)
        {
            $i = $info[$info.Count - 1]

            $session = CBackupSession::Create $i

            return $session
        }
        else
        {
            return $null
        }
    }

    [void]ProcessBackupSession($session)
    {
        [Logger]::Log("Entered [BackupHandler]::ProcessBackupSession")

        switch($session.Result)
        {
            "None"                       { $this.ProcessRunningSession2($session) }
            {$_ -in "Warning","Failed"}  { $this.ProcessFailedSession2($session) }
            {$_ -in "Success"}           { $this.ProcessSuccessSession2($session) }

            default
            {
                throw "Cannot process Backup Session. Unknown Session Type '$($_)'"
            }
        }
    }

    [string]ProcessFailedSessionSingleFailure($session, $failedJobs)
    {
        [Logger]::Log("Entered [BackupHandler]::ProcessFailedSessionSingleFailure")

        $vmErrorMsg = ""

        $records = $failedJobs.Logger.GetLog().GetAttentionRecords()|select -expand title|get-unique

        $vmErrorMsg = [string]::Join(". ", $records)

        if($vmErrorMsg -eq "")
        {
            $details = $session.GetTaskSessions().GetDetails() | Get-Unique

            if($details -ne "")
            {
                $vmErrorMsg = [string]::Join(" ", $details).Trim()
            }
            else
            {
                $logs = $session.Logger.GetLog().GetAttentionRecords()|select -expand title|get-unique

                foreach($log in $logs)
                {
                    $vmErrorMsg += $log
                }
            }
        }

        $vmErrorMsg = $vmErrorMsg -replace "`n", ". "
        $vmErrorMsg = $this.CleanFailedVMDetails($vmErrorMsg)

        $result = "failed"

        if($session.Result -eq "Warning")
        {
            $result = "completed with warnings"
        }

        $msg = "Backup of Virtual Machine '" + $failedJobs.Name + "' $($result): " + $vmErrorMsg

        return $msg
    }

    [string]ProcessFailedJobsMultipleFailures($session, $failedJobs)
    {
        [Logger]::Log("Entered [BackupHandler]::ProcessFailedJobsMultipleFailures")

        $details = ""

        $records = $session.Logger.GetLog().GetAttentionRecords()|select -expand title|get-unique

        foreach($record in $records)
        {
            $details += "; " + $record #we need to handle having a separator for multiple records
        }

        if($details -eq "")
        {
            $d = $session.GetTaskSessions().GetDetails() | Get-Unique

            $details = [string]::Join(" ", $d).Trim()
        }
        else
        {
            $details = $details -replace "`n", ". "
            $details = $details.Substring(2)
        }
        
        $details = $this.CleanFailedVMDetails($details)

        $msg = ""

        $result = "failed"

        if($session.Result -eq "Warning")
        {
            $result = "completed with warnings"
        }

        if($failedJobs.Length -gt 0)
        {
            $msg = $failedJobs.Length.ToString() + " Virtual Machine Backups $result. $details"
        }
        else
        {
            $msg = $details
        }

        return $msg
    }

    [void]ProcessRunningSession2($session)
    {
        [Logger]::Log("Entered [BackupHandler]::ProcessRunningSession2")

        $backupStartTime = [TimeFormatter]::GetLastBackupStartTimeText($session.Progress.StartTimeLocal)

        $progress = $session.BaseProgress

        if($backupStartTime -eq $null -or $backupStartTime -eq "")
        {
            $backupStartTime = " 0m"
        }

        if($backupStartTime -lt (New-TimeSpan -Hours 12).TotalSeconds -or $this.job.IsContinuous)
        {
            $msg = "Backup Running (Progress: $progress%, Duration:$backupStartTime)"

            $this.OutputMessage($session, $msg, $this.STATE_RUNNING)
        }
        else
        {
            $msg = "Backup has been running for more than 12 hours. Please confirm whether the backup is experiencing issues (Progress: $progress%, Duration:$backupStartTime)"

            [PrtgLogger]::Error($msg)
        }
    }
    [void]ProcessFailedSession2($session)
    {
        [Logger]::Log("Entered [BackupHandler]::ProcessFailedSession2")

        $vmJobs = $session.GetTaskSessions()
        $schedule = $this.job.GetScheduleOptions()
    
        $failedJobs = $vmJobs|where { $_.status -ne "Success" }

        if($failedJobs.Length -eq 1)
        {
            $msg = $this.ProcessFailedSessionSingleFailure($session, $failedJobs)
        }
        else
        {
            $msg = $this.ProcessFailedJobsMultipleFailures($session, $failedJobs)
        }

        if($this.job.IsContinuous)
        {
            $nextBackupText = " Continuous"
        }
        else
        {
            if($this.job.JobType -eq "EndpointBackup")
            {
                $epSchedule = $this.job.GetScheduleOptions()

                $nextBackupText = [TimeFormatter]::GetNextBackupStartTimeText($epSchedule.NextRun)
            }
            else
            {
                $nextBackupText += [TimeFormatter]::GetNextBackupStartTimeText($schedule.NextRun)
            }            
        }

        if(!$this.job.IsScheduleEnabled)
        {
            $msg = "Last Backup: Failed $($msg.Trim('.')). Next Backup (if enabled):$nextBackupText"
        }


        $state = $this.STATE_ERROR

        if($session.Result -eq "Warning")
        {
            $state = $this.STATE_WARNING
        }

        if(!$this.job.IsScheduleEnabled)
        {
            $state = $this.STATE_DISABLED
        }

        $this.OutputMessage($session, $msg, $state)
    }

    [void]ProcessSuccessSession2($session)
    {
        [Logger]::Log("Entered [BackupHandler]::ProcessSuccessSession2")

        $schedule = $this.job.GetScheduleOptions()
        $msg = $this.GetSuccessMessage($schedule, $session)

        $state = $this.STATE_SUCCESS

        if(!$this.job.IsScheduleEnabled)
        {
            $state = $this.STATE_DISABLED
        }

        $this.OutputMessage($session, $msg, $state)
    }

    [void]OutputMessage($session, $msg, $state)
    {
        $schedule = $this.job.GetScheduleOptions()

        $lastBackupSeconds = [TimeFormatter]::GetLastBackupStartTimeInSeconds($session.Progress.StartTimeLocal)

        $nextBackupSeconds = -1

        if($this.job.JobType -eq "EndpointBackup" -and $this.job.IsScheduleEnabled)
        {
            $epSchedule = $this.job.GetScheduleOptions()

            $nextBackupSeconds = [TimeFormatter]::GetNextBackupStartTimeInSeconds($epSchedule.NextRun)
        }
        else
        {
            if(!$this.job.IsContinuous -and $this.job.CanRunByScheduler())
            {
                $nextBackupSeconds = [TimeFormatter]::GetNextBackupStartTimeInSeconds($schedule.NextRun)
            }
        }

        $duration = -1

        if($state -eq $this.STATE_RUNNING)
        {
            $duration = $lastBackupSeconds
        }

        [PrtgLogger]::Success($msg, $lastBackupSeconds, $nextBackupSeconds, $duration, $state)
    }

    [string]GetSuccessMessage($schedule, $session)
    {
        [Logger]::Log("Entered [BackupHandler]::GetSuccessMessage")

        $lastBackupText = "Last Backup:$([TimeFormatter]::GetLastBackupStartTimeText($session.Progress.StartTimeLocal))"

        $nextBackupText = "Next Backup:"

        if($this.job.IsContinuous)
        {
            $nextBackupText += " Continuous"
        }
        else
        {
            if($this.job.JobType -eq "EndpointBackup")
            {
                $epSchedule = $this.job.GetScheduleOptions()
                $nextBackupText += [TimeFormatter]::GetNextBackupStartTimeText($epSchedule.NextRun)
            }
            else
            {
                $nextBackupText += [TimeFormatter]::GetNextBackupStartTimeText($schedule.NextRun)
            }
        }

        if(!$this.job.IsScheduleEnabled)
        {
            return "$lastBackupText, $($nextBackupText.Replace("Next Backup", "Next Backup (if enabled)"))"
        }
        else
        {
            return "$lastBackupText, $nextBackupText"
        }
    }
}

class UnknownJobTypeBackupHandler : BaseBackupHandler
{
    UnknownJobTypeBackupHandler($job, $jobName) : base($job, $jobName)
    {
    }

    [void]GetStatus()
    {
        [Logger]::Log("Entered [UnknownJobTypeHandler]::GetStatus")

        [Logger]::Log("-Testing Backup as Tape Job")
        $tapeJob = TapeJob::GetAll|where{$_.name -eq $jobName}

        if($tapeJob -ne $null)
        {
            [TapeBackupHandler]::new($tapeJob).GetStatus()
        }
        else
        {
            [PrtgLogger]::Error("Could not find a handler for job type '$($this.backup.jobType)'")
        }
    }
}

class TapeBackupHandler : BackupHandler
{
    TapeBackupHandler($job, $jobName) : base($job, $jobName)
    {
    }

    [void]ProcessRunningSession($session)
    {
        if($session.State -eq "WaitingTape")
        {
            [PrtgLogger]::Error("Backup Job is stalled waiting for a second tape")
        }
        else
        {
            ([BackupHandler]$this).ProcessRunningSession($session)
        }
    }
}

class ClientModeBackupHandler
{
    [void]GetStatus()
    {
        #get the content from the file
        #write it to the screen
    }
}

#endregion

#region Helpers

class Logger
{
    static [void]Enable()
    {
        $DebugPreference="Continue"
    }

    static [void]Log($msg)
    {
        Write-Debug $msg
        
        $jobName = $script:args[1]

        #Add-Content "C:\veeamlogs\backup\$jobName.log" "$(get-date) $global:pid $msg"
    }   
}

class PrtgLogger
{
    static [void]Error($msg)
    {
        [PrtgLogger]::LogError($msg)
        [VeeamBackupStatus]::Quit()
    }

    static [void]InitError($msg)
    {
        [PrtgLogger]::LogError($msg) #this isnt going to work or be needed if we're doing a file logger
        #we can have veeambackupstatus in client, server or single mode. if in client, read the backup file. if in server, generate files for everyone
        Exit
    }

    hidden static [void] LogError($msg)
    {
        if($msg.Length -gt 1000)
        {
            $msg = $msg.Substring(0, 1000)
        }

        Write-Host (Prtg {
            Error 1
            Text $msg
        })
    }

    static [void]Success($msg, $lastBackup, $nextBackup, $backupDuration, $state)
    {
        Write-Host (Prtg {
            Text $msg

            Result {
                Channel "Backup State"
                Value $state
                Unit Custom
                ValueLookup prtg.customlookups.veeam.backupstate
            }

            Result {
                Channel "Last Backup"
                Value $lastBackup
                Unit TimeSeconds
            }

            Result {
                Channel "Next Backup"
                Value $nextBackup
                Unit TimeSeconds
            }

            Result {
                Channel "Backup Duration"
                Value $backupDuration
                Unit TimeSeconds
            }            
        })
    }
}

class TimeFormatter
{
    static [int]GetLastBackupStartTimeInSeconds($lastRun)
    { 
        if($lastRun -ne "1/01/0001 12:00:00 AM")
        {
            $lastBackup = (get-date).Subtract($lastRun)

            #PRTG does not let us return TotalMinutes - only TotalHours or TotalSeconds. These values are then rounded appropriately
            #into minutes, hours, days, etc. We can simulate TotalMinutes and prevent seconds from being displayed by ensuring
            #TotalSeconds is a multiple of 60
            $lastBackupMinutes = [Math]::Floor($lastBackup.TotalMinutes)

            return $lastBackupMinutes * 60
        }
        else
        {
            return -1
        }
    }

    static [int]GetNextBackupStartTimeInSeconds($nextRun)
    {
        if($nextRun -eq "01/01/0001 00:00:00")
        {
            return -1
        }

        $nextBackup = ([DateTime]::Parse(($nextRun))).Subtract([DateTime]::Now)

        $nextBackupMinutes = [Math]::Floor($nextBackup.TotalMinutes)

        return $nextBackupMinutes * 60
    }
   
    static [string]GetLastBackupStartTimeText($lastRun)
    {
        if($lastRun -ne "1/01/0001 12:00:00 AM")
        {
            $lastBackup = (get-date).Subtract($lastRun)

            $lastDays = [Math]::Floor($lastBackup.TotalDays)
            $lastHours = $lastBackup.Hours
            $lastMinutes = $lastBackup.Minutes

            return [TimeFormatter]::FormatBackupTimeString($lastDays, $lastHours, $lastMinutes)
        }
        else
        {
            return " First Run"
        }
    }

    static [string]GetNextBackupStartTimeText($nextRun)
    {
        if($nextRun -eq "01/01/0001 00:00:00" -or [string]::IsNullOrEmpty($nextRun))
        {
            return " Unknown"
        }

        $nextBackup = ([DateTime]::Parse($nextRun)).Subtract([DateTime]::Now)

        $nextDays = [Math]::Floor($nextBackup.TotalDays)
        $nextHours = $nextBackup.Hours
        $nextMinutes = $nextBackup.Minutes

        return [TimeFormatter]::FormatBackupTimeString($nextDays, $nextHours, $nextMinutes)
    }

    static [string]FormatBackupTimeString($days, $hours, $minutes)
    {
        $returnText = ""

        if($days -ne 0)
        {
            $returnText += " " + $days.ToString() + "d"
        }

        if($hours -ne 0)
        {
            $returnText += " " + $hours.ToString() + "h"
        }

        if($minutes -ne 0)
        {
            $returnText += " " + $minutes.ToString() + "m"
        }
	
	    if($returnText -eq $null)
	    {
		    $returnText = "0m"
	    }

        return $returnText
    }
}

#endregion

#endregion

if(!$args[0])
{
    [PrtgLogger]::Error("Please specify the Veeam Backup and Replication Server backups run on.")
    Exit
}

if(!$args[1])
{
    [PrtgLogger]::Error("Please specify the name of a backup job. If the job name contains spaces, surround the name in double quotation marks.")
    Exit
}

if([Environment]::Is64BitProcess -eq $false)
{
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo

    $startInfo.FileName = "C:\Windows\sysnative\WindowsPowerShell\v1.0\powershell.exe"
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.Arguments = "-file `"$($PSScriptRoot)\$($MyInvocation.MyCommand.Name)`" $($args[0]) `"$($args[1])`""

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $process.Start()|Out-Null
    $process.WaitForExit()

    $output = $process.StandardOutput.ReadToEnd()
    $output += $process.StandardError.ReadToEnd()

    Write-Host $output
}
else
{
    Main $args[0] $args[1]
}