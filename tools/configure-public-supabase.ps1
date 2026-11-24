param([Parameter(Mandatory=$true)][string]$ProjectRef)
$ErrorActionPreference='Stop'
if($ProjectRef -notmatch '^[a-z]{20}$'){throw 'Referencia de proyecto invalida.'}
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 $raw=& npm exec --yes --package=supabase@3.3.0 -- supabase projects api-keys "--remote=$ProjectRef" --output json
 if($LASTEXITCODE -ne 0){throw 'No se pudo obtener la configuracion publica.'}
 $keys=$raw | ConvertFrom-Json
 $public=$keys | Where-Object {$_.type -eq 'publishable' -and $_.api_key -like 'sb_publishable_*'} | Select-Object -First 1
 if(!$public){throw 'No hay clave publicable valida; no se usara una clave de servidor.'}
 $path=Join-Path $root 'config/public.json'
 if(!(Test-Path $path)){throw 'Falta config/public.json; primero se prepara Firebase.'}
 $config=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) | ConvertFrom-Json
 if($config.SUPABASE_URL -and $config.SUPABASE_URL -ne "https://$ProjectRef.supabase.co"){
  throw 'El archivo apunta a otro proyecto; se conserva sin sobrescribir.'
 }
 $config.SUPABASE_URL="https://$ProjectRef.supabase.co"
 $config.SUPABASE_ANON_KEY=$public.api_key
 [IO.File]::WriteAllText($path,($config|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding $false))
 Write-Output "Configuracion actualizada para $ProjectRef. Solo se guardo la clave PUBLICABLE; no se imprimen claves."
} finally {Pop-Location}
