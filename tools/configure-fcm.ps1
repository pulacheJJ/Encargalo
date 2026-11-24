param([string]$SourceFile='.secrets/fcm-service-account.json')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 $source=Join-Path $root $SourceFile
 $destination=Join-Path $root '.secrets/fcm-service-account.json'
 if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw 'No se encontro el JSON privado indicado.'}
 $sid='*'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 & icacls $source /inheritance:r /grant:r "$($sid):F" 'SYSTEM:F' | Out-Null
 if($LASTEXITCODE -ne 0){throw 'No se pudo proteger el JSON.'}
 $account=[IO.File]::ReadAllText($source) | ConvertFrom-Json
 if($account.type -ne 'service_account' -or $account.project_id -ne 'encargalo-c54ec' -or
    $account.client_email -ne 'encargalo-fcm@encargalo-c54ec.iam.gserviceaccount.com' -or
    $account.private_key -notlike '*BEGIN PRIVATE KEY*' -or
    $account.token_uri -ne 'https://oauth2.googleapis.com/token'){
  throw 'El JSON no corresponde a la cuenta FCM autorizada o esta incompleto.'
 }
 if($source -ne $destination){
  if(Test-Path -LiteralPath $destination){throw 'Ya existe el archivo destino; no se sobrescribe.'}
  Move-Item -LiteralPath $source -Destination $destination
 }
 & git check-ignore --quiet .secrets/fcm-service-account.json
 if($LASTEXITCODE -ne 0){throw 'El archivo no esta excluido de Git.'}
 $upload=Join-Path $root ('.secrets/fcm-upload-'+[Guid]::NewGuid().ToString('N')+'.env')
 try {
  # Hereda los permisos privados del JSON antes de escribir material secreto.
  [IO.File]::WriteAllText($upload,'',(New-Object Text.UTF8Encoding $false))
  & icacls $upload /inheritance:r /grant:r "$($sid):F" 'SYSTEM:F' | Out-Null
  if($LASTEXITCODE -ne 0){throw 'No se pudo proteger el archivo temporal.'}
  $json=$account | ConvertTo-Json -Depth 6 -Compress
  [IO.File]::WriteAllText($upload,"FCM_SERVICE_ACCOUNT_JSON='$json'`n",(New-Object Text.UTF8Encoding $false))
  & npm exec --yes --package=supabase@3.3.0 -- supabase secrets set --remote=thptipcvzevxuysjqvyq --env-file $upload --yes
  if($LASTEXITCODE -ne 0){throw 'No se pudo cargar el secreto FCM en Supabase.'}
 } finally {
  if(Test-Path -LiteralPath $upload){Remove-Item -LiteralPath $upload -Force}
 }
 Write-Output 'FCM validado y cargado como secreto de servidor. JSON privado protegido y excluido de Git; no se imprimieron credenciales.'
} finally {Pop-Location}
