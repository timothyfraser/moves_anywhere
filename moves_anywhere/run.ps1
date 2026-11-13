# run.ps1: run MOVES on one folder of inputs with Docker, on Windows PowerShell.
#
#   powershell -ExecutionPolicy Bypass -File run.ps1 <inputs-folder> [-Image IMAGE] [-Cpus N] [-Memory SIZE]
#
# The folder needs rs_custom.xml, plus any custom input tables as <table>.csv. Results land in the same
# folder: data.csv, moveslog.txt, run_manifest.json. The exit status is 0 only when the run produced
# results. Defaults: 2 CPUs, 6 GB, the released image. MOVES uses about one core at a time.
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Inputs,
  [string]$Image = $(if ($env:MOVES_IMAGE) { $env:MOVES_IMAGE } else { "tmf77/moves-anywhere:v3" }),
  [string]$Cpus = "2",
  [string]$Memory = "6g"
)

if (-not (Test-Path -LiteralPath $Inputs -PathType Container)) {
  [Console]::Error.WriteLine("run.ps1: no such folder: $Inputs"); exit 2
}
if (-not (Test-Path -LiteralPath (Join-Path $Inputs "rs_custom.xml"))) {
  [Console]::Error.WriteLine("run.ps1: $Inputs has no rs_custom.xml"); exit 2
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("run.ps1: Docker is not installed or not on PATH"); exit 3
}
docker info *> $null
if ($LASTEXITCODE -ne 0) {
  [Console]::Error.WriteLine("run.ps1: Docker is not running"); exit 3
}

$abs = (Resolve-Path -LiteralPath $Inputs).Path
Write-Output "run.ps1: $Image on $abs ($Cpus CPUs, $Memory)"
docker run --rm --name "moves-run-$PID" --cpus $Cpus -m $Memory -v "${abs}:/cat/inputs" $Image
$rc = $LASTEXITCODE
if ($rc -eq 0) {
  Write-Output "run.ps1: finished. Results are in $Inputs"
} else {
  [Console]::Error.WriteLine("run.ps1: failed with exit $rc. See moveslog.txt and run_manifest.json in $Inputs")
}
exit $rc
