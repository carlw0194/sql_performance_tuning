<#
  automate_tuning.ps1
  One‑shot orchestrator: runs fixes, workload, and snapshots.
  Usage: pwsh -File automate_tuning.ps1 -Instance ".\SQL2022" -Db "AdventureWorks2022"
#>
Param(
  [string]$Instance = "Carlton-Njong\MSSQLSERVER01",
  [string]$Db       = "AdventureWorks2022",
  [int]   $LoopMax  = 30,  # Reduced from 100 to 30 for faster testing
  [switch]$Reset    = $false
)

$log = "tuning_run_{0:yyyyMMdd_HHmm}.log" -f (Get-Date)
"=== TUNING RUN {0} ===" -f (Get-Date) | Out-File $log

function Run-SqlFile($path, [string]$DbContext = $Db) {
    $ts = Get-Date -Format "HH:mm:ss"
    "$ts  ->  $path" | Tee-Object -FilePath $log -Append
    try {
        Invoke-Sqlcmd -ServerInstance $Instance -Database $DbContext -InputFile $path -Verbose -ErrorAction Stop -QueryTimeout 0 -ConnectionTimeout 15 `
            | Tee-Object -FilePath $log -Append
    }
    catch {
        "$ts  ❌  $path failed: $_" | Tee-Object -FilePath $log -Append
        throw
    }
}

function Capture-Snapshot($label) {
    $ts = Get-Date -Format "HH:mm:ss"
    "$ts  [SNAP]  Snapshot $label" | Tee-Object $log -Append
    Invoke-Sqlcmd -ServerInstance $Instance -Database $Db -QueryTimeout 0 -ConnectionTimeout 15 `
        -Query "EXEC dbo.Capture_PerfMetrics N'$label';" `
        | Tee-Object -FilePath $log -Append
}

# Optional DB reset: restore & mess injection before baseline
if ($Reset) {
    Write-Host "--- RESET: restoring database and injecting mess ---"
    Run-SqlFile 'setup\01_restore_verify.sql' 'master'
    Run-SqlFile 'setup\02_inject_mess.sql'
    # Create the stored procedure for parameter sniffing demo
    Run-SqlFile 'setup\sp_getSalesbyCustomer.sql'
    if (Test-Path 'setup\03_seed_heavy_load.sql') {
        Run-SqlFile 'setup\03_seed_heavy_load.sql'
    }
}

# 0. Ensure workload simulation knows LoopMax
(Get-Content 'diagnostics\workload_simulation.sql') -replace '(?<=@LoopMax\s*=\s*)\d+',$LoopMax |
    Set-Content 'workload_simulation_tmp.sql'

# Capture initial snapshot BEFORE any workload/fixes
Capture-Snapshot 'PreLoad'

# === Phase list ===
$phases = @(
  @{ Label="Baseline"; Fix=$null },
  @{ Label="MidFix_Stats"; Fix="fixes\12_enable_statistics.sql" },
  @{ Label="MidFix_Indexes"; Fix="fixes\14_reenable_good_indexes.sql" },
  @{ Label="MidFix_DropDupIX"; Fix="fixes\11_drop_bad_indexes.sql" },
  @{ Label="MidFix_AddMissingIX"; Fix="fixes\15_add_missing_indexes.sql" },
  @{ Label="MidFix_Param"; Fix="fixes\17_fix_param_sniff.sql" },
  @{ Label="MidFix_Rewrite"; Fix="fixes\18_rewrite_queries.sql" },
  @{ Label="MidFix_Defrag"; Fix="fixes\16_rebuild_fragmented.sql" },
  @{ Label="After"; Fix=$null }
)

# === Run phases ===
try {
    foreach ($p in $phases) {
        if ($p.Fix) { Run-SqlFile $p.Fix }
        Run-SqlFile "workload_simulation_tmp.sql"
        Capture-Snapshot $p.Label
    }
    "=== RUN COMPLETE ===" | Tee-Object $log -Append
}
finally {
    if (Test-Path 'workload_simulation_tmp.sql') { Remove-Item 'workload_simulation_tmp.sql' }
    Write-Host "DONE - All phases executed. See $log for details."
}
