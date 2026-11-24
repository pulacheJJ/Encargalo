param([switch]$Configured,[switch]$Deployed,[switch]$ReleaseOnly)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$evidence=Join-Path (Split-Path $root -Parent) 'encargalo_documentacion/evidencias/compilacion'
$versionMatch=Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\S+)'
if(!$versionMatch){throw 'No se encontro la version del proyecto.'}
$version=$versionMatch.Matches[0].Groups[1].Value
$compiled=Get-Content -Raw (Join-Path $evidence 'FUENTES_COMPILADAS.json') | ConvertFrom-Json
if($compiled.version -ne $version){throw 'La compilacion no corresponde a la version actual.'}
if($Configured -and !$compiled.cloudConfigured){throw 'La compilacion no acredita configuracion publica.'}
if($compiled.releaseOnly -and !$ReleaseOnly){throw 'La compilacion contiene solo APK release; usar -ReleaseOnly para no mezclar artefactos anteriores.'}
$delivery=Join-Path $root 'apk'
New-Item -ItemType Directory -Path $delivery -Force | Out-Null
$release=Join-Path $root 'build/app/outputs/flutter-apk/app-release.apk'
$debug=Join-Path $root 'build/app/outputs/flutter-apk/app-debug.apk'
$bundle=Join-Path $root 'build/app/outputs/bundle/release/app-release.aab'
$artifacts=@()
$items=,@($release,'Encargalo.apk')
if(!$ReleaseOnly){
 $items+=,@($debug,'Encargalo-debug.apk')
 $items+=,@($bundle,'Encargalo.aab')
}
foreach($item in $items){
 if(Test-Path $item[0]){
  $target=Join-Path $delivery $item[1]
  Copy-Item $item[0] $target -Force
  $file=Get-Item $target
  $artifacts+=@{file=$file.Name;path=$file.FullName;bytes=$file.Length;sha256=(Get-FileHash $target -Algorithm SHA256).Hash}
 }
}
$warning=if($Configured -and $Deployed){'La configuración/despliegue se declaran por el ejecutor; las verificaciones se documentan por separado en RESULTADOS.'}else{'Artefactos sin configuración cloud: no constituyen una entrega funcional conectada. Se recompilarán después de configurar las cuentas gratuitas.'}
$manifest=@{version=$version;applicationId='pe.edu.unp.encargalo';generatedAt=(Get-Date).ToString('o');cloudConfigured=[bool]$Configured;deployed=[bool]$Deployed;warning=$warning;artifacts=$artifacts}
$json=$manifest|ConvertTo-Json -Depth 6
[IO.File]::WriteAllText((Join-Path $evidence 'MANIFIESTO.json'),$json,(New-Object Text.UTF8Encoding $false))
$json
