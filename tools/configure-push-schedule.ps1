$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
 $evidence=Get-Content -Raw '../encargalo_documentacion/evidencias/push-servidor.json' | ConvertFrom-Json
 if($evidence.result -ne 'PASS' -or $evidence.project -ne 'thptipcvzevxuysjqvyq' -or
    $evidence.validation.validated -ne $true -or $evidence.validation.validate_only -ne $true){
  throw 'Primero debe aprobar la validacion cloud del emisor FCM.'
 }
 $config=Get-Content -Raw 'config/public.json' | ConvertFrom-Json
 if($config.SUPABASE_URL -ne 'https://thptipcvzevxuysjqvyq.supabase.co'){throw 'Proyecto no autorizado.'}
 $envText=[IO.File]::ReadAllText((Join-Path $root '.secrets/edge.env'))
 $match=[regex]::Match($envText,'(?m)^PUSH_DISPATCH_SECRET=([a-f0-9]+)\s*$')
 if(!$match.Success){throw 'Falta secreto de despacho valido.'}
 $secret=$match.Groups[1].Value
 $url=$config.SUPABASE_URL+'/functions/v1/dispatch-push'
 # Solo almacena URL y secreto de despacho en Vault, no la clave privada FCM.
 # Nunca rota ni sobrescribe un secreto previo con distinto valor.
 $sql=@"
do `$vault`$
declare existing record;
begin
 select id,decrypted_secret into existing from vault.decrypted_secrets where name='encargalo_push_url';
 if found then
  if existing.decrypted_secret <> '$url' then raise exception 'Vault URL existente diferente; se conserva'; end if;
 else
  perform vault.create_secret('$url','encargalo_push_url','Endpoint cloud de Encargalo');
 end if;
 select id,decrypted_secret into existing from vault.decrypted_secrets where name='encargalo_push_secret';
 if found then
  if existing.decrypted_secret <> '$secret' then raise exception 'Vault secreto existente diferente; se conserva'; end if;
 else
  perform vault.create_secret('$secret','encargalo_push_secret','Autorizacion privada del emisor de Encargalo');
 end if;
end
`$vault`$;
"@
 $sql+=[IO.File]::ReadAllText((Join-Path $root 'supabase/setup_push_schedule.sql'))
 $path=Join-Path $root ('.secrets/push-schedule-'+[Guid]::NewGuid().ToString('N')+'.sql')
 try {
  [IO.File]::WriteAllText($path,'',(New-Object Text.UTF8Encoding $false))
  $sid='*'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  & icacls $path /inheritance:r /grant:r "$($sid):F" 'SYSTEM:F' | Out-Null
  if($LASTEXITCODE -ne 0){throw 'No se pudo proteger SQL temporal.'}
  [IO.File]::WriteAllText($path,$sql,(New-Object Text.UTF8Encoding $false))
  # Captura salida para evitar revelar SQL privado en mensajes de error de CLI.
  try {
   $ErrorActionPreference='Continue'
   $output=& npm exec --yes --package=supabase@3.3.0 -- supabase db query --remote=thptipcvzevxuysjqvyq --file $path --yes 2>&1
   $code=$LASTEXITCODE
  } finally {$ErrorActionPreference='Stop'}
  if($code -ne 0){throw 'No se pudo activar cron/Vault; revisar estado sin imprimir SQL privado.'}
 } finally {
  if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}
 }
 Write-Output 'Vault y cron configurados para Encargalo. Sin credenciales en salida ni archivos temporales restantes.'
} finally {Pop-Location}
