param([string]$PublicConfig='', [switch]$SkipBundle, [string]$StagePath='', [switch]$ReleaseOnly)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$documentation=Join-Path (Split-Path $root -Parent) 'encargalo_documentacion'
$logs=Join-Path $documentation 'registros'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$prefix=Join-Path $env:LOCALAPPDATA 'Temp/opencode/encargalo-android-'
if($StagePath){
 $temp=(Resolve-Path $StagePath).Path
 if(!$temp.StartsWith($prefix.Replace('/','\'),[StringComparison]::OrdinalIgnoreCase) -or
    !(Test-Path (Join-Path $temp 'pubspec.yaml')) -or
    !(Select-String -Path (Join-Path $temp 'pubspec.yaml') -Pattern '^name: encargalo$' -Quiet)){
  throw 'La ruta no es una copia ASCII de compilación de Encárgalo.'
 }
}else{
 $temp=Join-Path $env:LOCALAPPDATA ('Temp/opencode/encargalo-android-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
 if(Test-Path $temp){throw 'La carpeta temporal ya existe; no se sobrescribe.'}
 New-Item -ItemType Directory -Path $temp | Out-Null
}
# Copia de compilación del proyecto nuevo, no de una aplicación anterior.
# No se arrastran caches, historial, secretos cloud ni herramientas ajenas.
& robocopy $root $temp /E /XD .git .dart_tool .gradle build .secrets node_modules backend-tests supabase docs entrega apk /XF *.log *.apk *.aab /NFL /NDL /NJH /NJS /NP | Out-Null
if($LASTEXITCODE -ge 8){throw 'No se pudo preparar la copia ASCII de compilación.'}
# The owned compiler copy may contain paths from before a feature refactor.
# Mirror only its lib subtree, never purge the project or an unrelated folder.
& robocopy (Join-Path $root 'lib') (Join-Path $temp 'lib') /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if($LASTEXITCODE -ge 8){throw 'No se pudo sincronizar lib en la copia de compilacion.'}
# AGP también calcula hashes nativos del keystore: su ruta debe ser ASCII.
# Se copia la MISMA firma, no se genera otra. La copia queda privada y fuera de Git.
$keySource=Join-Path $root '.secrets/encargalo-release.jks'
$keyProperties=Join-Path $root 'android/key.properties'
if(!(Test-Path $keySource) -or !(Test-Path $keyProperties)){throw 'Falta la firma original. Se conserva la identidad: no se crea otra automáticamente.'}
$signingDir=Join-Path $temp '.signing'
New-Item -ItemType Directory -Path $signingDir -Force | Out-Null
$account='*'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls $signingDir /inheritance:r /grant:r "$($account):(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
if($LASTEXITCODE -ne 0){throw 'No se pudo restringir el acceso a la copia de firma.'}
$keyCopy=Join-Path $signingDir 'encargalo-release.jks'
Copy-Item $keySource $keyCopy -Force
& icacls $keyCopy /inheritance:r /grant:r "$($account):F" 'SYSTEM:F' | Out-Null
if($LASTEXITCODE -ne 0){throw 'No se pudo proteger el archivo de firma temporal.'}
$text=[IO.File]::ReadAllText($keyProperties,[Text.Encoding]::UTF8)
$text=[Text.RegularExpressions.Regex]::Replace($text,'(?m)^storeFile=.*$',('storeFile='+$keyCopy.Replace('\','/')))
$stageProperties=Join-Path $temp 'android/key.properties'
[IO.File]::WriteAllText($stageProperties,$text,(New-Object Text.UTF8Encoding $false))
& icacls $stageProperties /inheritance:r /grant:r "$($account):F" 'SYSTEM:F' | Out-Null
if($LASTEXITCODE -ne 0){throw 'No se pudo restringir key.properties temporal.'}
$defines=@()
if($PublicConfig){
 $configPath=(Resolve-Path (Join-Path $root $PublicConfig)).Path
 $public=Get-Content -Raw $configPath | ConvertFrom-Json
 if($public.SUPABASE_URL -ne 'https://thptipcvzevxuysjqvyq.supabase.co' -or
    $public.SUPABASE_ANON_KEY -notlike 'sb_publishable_*' -or
    $public.FIREBASE_PROJECT_ID -ne 'encargalo-c54ec'){
  throw 'La compilacion conectada requiere las claves publicas de los proyectos autorizados.'
 }
 foreach($property in $public.PSObject.Properties){
  if($property.Name -match 'SERVICE_ACCOUNT|SERVICE_ROLE|PRIVATE_KEY|DISPATCH_SECRET' -or $property.Value -like '*BEGIN PRIVATE KEY*'){
   throw 'Se detecto un campo privado en la configuracion de cliente.'
  }
 }
 $dest=Join-Path $temp 'config/build-public.json'
 Copy-Item $configPath $dest
 $defines=@('--dart-define-from-file=config/build-public.json')
}
$flutter=(Get-Command flutter).Source
$sourceHashes=@()
$sourceFiles=@(Get-ChildItem (Join-Path $temp 'lib') -Recurse -File -Filter '*.dart')
if(Test-Path (Join-Path $temp 'assets')){$sourceFiles+=Get-ChildItem (Join-Path $temp 'assets') -Recurse -File}
foreach($relative in @('pubspec.yaml','pubspec.lock','android/app/build.gradle.kts','android/settings.gradle.kts','android/gradle.properties','android/app/src/main/AndroidManifest.xml')){
 $sourceFiles+=Get-Item (Join-Path $temp $relative)
}
foreach($file in $sourceFiles){
 $sourceHashes+=@{file=$file.FullName.Substring($temp.Length+1).Replace('\','/');sha256=(Get-FileHash $file.FullName -Algorithm SHA256).Hash}
}
$version=(Select-String -Path (Join-Path $temp 'pubspec.yaml') -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
if($PublicConfig){
 $sourceHashes+=@{file=$configPath.Substring($root.Length+1).Replace('\','/');sha256=(Get-FileHash $configPath -Algorithm SHA256).Hash}
}
Push-Location $temp
try {
 $ErrorActionPreference='Continue'
 & $flutter pub get *> (Join-Path $logs 'build-pub-get.log')
 if($LASTEXITCODE -ne 0){throw 'flutter pub get falló; revisar build-pub-get.log.'}
 if(!$ReleaseOnly){
  & $flutter build apk --debug @defines *> (Join-Path $logs 'build-debug-ascii.log')
  $debugCode=$LASTEXITCODE
  Get-Content (Join-Path $logs 'build-debug-ascii.log') -Tail 24
  if($debugCode -ne 0){throw 'La compilación debug falló.'}
 }
 & $flutter build apk --release @defines *> (Join-Path $logs 'build-release-ascii.log')
 $releaseCode=$LASTEXITCODE
 Get-Content (Join-Path $logs 'build-release-ascii.log') -Tail 30
 if($releaseCode -ne 0){throw 'La compilación release falló.'}
 if(!$SkipBundle -and !$ReleaseOnly){
  & $flutter build appbundle --release @defines *> (Join-Path $logs 'build-aab-ascii.log')
  $bundleCode=$LASTEXITCODE
  Get-Content (Join-Path $logs 'build-aab-ascii.log') -Tail 20
  if($bundleCode -ne 0){throw 'La compilación AAB falló.'}
 }
 $ErrorActionPreference='Stop'
 $apkDir=Join-Path $root 'build/app/outputs/flutter-apk'
 New-Item -ItemType Directory -Path $apkDir -Force | Out-Null
 if(!$ReleaseOnly){Copy-Item (Join-Path $temp 'build/app/outputs/flutter-apk/app-debug.apk') $apkDir}
 Copy-Item (Join-Path $temp 'build/app/outputs/flutter-apk/app-release.apk') $apkDir
 if(!$SkipBundle -and !$ReleaseOnly){
  $aabDir=Join-Path $root 'build/app/outputs/bundle/release'
  New-Item -ItemType Directory -Path $aabDir -Force | Out-Null
  Copy-Item (Join-Path $temp 'build/app/outputs/bundle/release/app-release.aab') $aabDir
 }
 Write-Output "Compilaciones realizadas en la copia ASCII: $temp"
 $sourceManifest=@{version=$version;cloudConfigured=[bool]$PublicConfig;releaseOnly=[bool]$ReleaseOnly;compiledAt=(Get-Date).ToString('o');compiledFrom=$temp;source=$root;files=$sourceHashes}|ConvertTo-Json -Depth 6
 $delivery=Join-Path $documentation 'evidencias/compilacion'
 New-Item -ItemType Directory -Path $delivery -Force | Out-Null
 [IO.File]::WriteAllText((Join-Path $delivery 'FUENTES_COMPILADAS.json'),$sourceManifest,(New-Object Text.UTF8Encoding $false))
} finally {
 Pop-Location
 # Solo las dos copias privadas creadas por este script, nunca la firma original.
 Remove-Item -LiteralPath $keyCopy -Force -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $stageProperties -Force -ErrorAction SilentlyContinue
}
