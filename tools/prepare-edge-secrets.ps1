param([Parameter(Mandatory=$true)][string]$ProjectRef)
$ErrorActionPreference='Stop'
if($ProjectRef -ne 'thptipcvzevxuysjqvyq'){throw 'Solo se prepara el proyecto autorizado de Encargalo.'}
$root=Split-Path $PSScriptRoot -Parent
$path=Join-Path $root '.secrets/edge.env'
if(Test-Path $path){
 Write-Output 'Se conserva el archivo privado existente; no se rotan secretos automaticamente.'
 exit 0
}
$bytes=New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$secret=([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
# URL publica de identificacion de esta app. No divulga el correo personal del propietario.
$contents="PUSH_DISPATCH_SECRET=$secret`nGEOCODER_CONTACT=https://$ProjectRef.supabase.co`n"
[IO.File]::WriteAllText($path,$contents,(New-Object Text.UTF8Encoding $false))
$sid='*'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls $path /inheritance:r /grant:r "$($sid):F" 'SYSTEM:F' | Out-Null
if($LASTEXITCODE -ne 0){throw 'No se pudo proteger el archivo privado.'}
Write-Output 'Secretos preparados con permisos restringidos. No se imprimen valores.'
