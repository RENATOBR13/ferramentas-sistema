@echo off
title Solucao de problemas de instalacao e desinstalacao de programas
color 0B

:: --- Pede permissao de administrador automaticamente ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permissao de administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=Get-Content -Raw -LiteralPath '%~f0'; $i=$c.IndexOf('#PS1'+'START'); Invoke-Expression $c.Substring($i)"
exit /b

#PS1START
$ErrorActionPreference = 'SilentlyContinue'
$desk   = [Environment]::GetFolderPath('Desktop')
$log    = Join-Path $desk 'Solucao-Problemas-Programas.log'
$bkdir  = Join-Path $desk 'Backup-Registro-Programas'

function Log($m)  { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Add-Content -Path $log }
function Say($m, $c = 'White') { Write-Host $m -ForegroundColor $c; Log $m }
function Voltar   { Read-Host "`nPressione ENTER para voltar ao menu" | Out-Null }
function Sim($p)  { (Read-Host "$p (S/N)") -match '^[sS]' }

function Get-Apps {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
         'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
         'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $k | Where-Object { $_.DisplayName }
}
function Get-Guid($t) { if ("$t" -match '\{[0-9A-Fa-f\-]{36}\}') { $matches[0] } }

function Backup-Chave($pspath) {
    $rp = $pspath -replace '^.*Registry::', ''
    New-Item -ItemType Directory -Path $bkdir -Force | Out-Null
    $n = $rp -replace '[^A-Za-z0-9]', '_'
    if ($n.Length -gt 100) { $n = $n.Substring($n.Length - 100) }
    reg.exe export "$rp" "$bkdir\$n.reg" /y | Out-Null
}

function Pasta-Segura($p) {
    if (-not $p) { return $false }
    $p = "$p".Trim('"').TrimEnd('\')
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    $proibidas = 'Common Files','Microsoft','Windows NT','WindowsApps','Windows Defender','Internet Explorer','Packages','Temp'
    foreach ($r in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA)) {
        if (-not $r) { continue }
        $r = $r.TrimEnd('\')
        if ($p.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $primeira = $p.Substring($r.Length + 1).Split('\')[0]
            if ($proibidas -notcontains $primeira) { return $true }
        }
    }
    return $false
}

# ---------------------------------------------------------------
function Diagnostico {
    Say "`n=== DIAGNOSTICO ===" Cyan
    $s = Get-Service msiserver
    if ($s) { Say "Servico Windows Installer: $($s.Status) (inicio: $($s.StartType))" }
    else    { Say "PROBLEMA: servico Windows Installer nao encontrado. Use a opcao 2." Red }

    if (Test-Path "$env:windir\System32\msiexec.exe") { Say "msiexec.exe encontrado." Green }
    else { Say "PROBLEMA: msiexec.exe ausente. Use a opcao 7 (SFC/DISM)." Red }

    $m = $null
    if ([System.Threading.Mutex]::TryOpenExisting('Global\_MSIExecute', [ref]$m)) {
        Say "ATENCAO: outra instalacao esta em andamento (causa comum do erro 1618). Aguarde ou use a opcao 2." Yellow
        $m.Dispose()
    } else { Say "Nenhuma outra instalacao em andamento." Green }

    $q = @(Get-Process msiexec).Count
    if ($q -gt 0) { Say "Processos msiexec em execucao: $q" Yellow }

    $pend = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
            (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
            ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager').PendingFileRenameOperations)
    if ($pend) { Say "ATENCAO: ha reinicio pendente. Reinicie o computador antes de instalar/desinstalar." Yellow }
    else { Say "Sem reinicio pendente." Green }

    $d = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
    $gb = [math]::Round($d.Free / 1GB, 1)
    if ($gb -lt 2) { Say "PROBLEMA: pouco espaco livre em $env:SystemDrive ($gb GB)." Red }
    else { Say "Espaco livre em $env:SystemDrive : $gb GB" Green }

    $t = Join-Path $env:TEMP "teste_$(Get-Random).tmp"
    try { 'x' | Set-Content $t -ErrorAction Stop; Remove-Item $t -Force; Say "Pasta TEMP com permissao de escrita." Green }
    catch { Say "PROBLEMA: sem permissao de escrita na pasta TEMP ($env:TEMP)." Red }
}

# ---------------------------------------------------------------
function Reparar-Installer {
    Say "`n=== REPARAR WINDOWS INSTALLER ===" Cyan
    Stop-Service msiserver -Force
    Get-Process msiexec | Stop-Process -Force
    foreach ($exe in "$env:windir\System32\msiexec.exe", "$env:windir\SysWOW64\msiexec.exe") {
        if (Test-Path $exe) {
            Start-Process $exe -ArgumentList '/unregister' -Wait
            Start-Process $exe -ArgumentList '/regserver' -Wait
            Say "Re-registrado: $exe" Green
        }
    }
    Set-Service msiserver -StartupType Manual
    Start-Service msiserver
    $s = Get-Service msiserver
    Say "Servico Windows Installer agora: $($s.Status)" Green
    Say "Pronto. Tente instalar/desinstalar novamente." Green
}

# ---------------------------------------------------------------
function Desinstalar {
    Say "`n=== DESINSTALAR PROGRAMA COM PROBLEMA ===" Cyan
    $busca = Read-Host "Digite parte do nome do programa (ex.: Apple, Office, Adobe)"
    if (-not $busca) { return }
    $lista = @()
    foreach ($a in (Get-Apps | Where-Object { $_.DisplayName -like "*$busca*" })) {
        $lista += [pscustomobject]@{ Tipo='Classico'; Nome=$a.DisplayName; Versao=$a.DisplayVersion; Un=$a.UninstallString; Quiet=$a.QuietUninstallString; Chave=$a.PSPath; Pasta=$a.InstallLocation; Pkg=$null }
    }
    foreach ($p in (Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*$busca*" })) {
        $lista += [pscustomobject]@{ Tipo='Store'; Nome=$p.Name; Versao="$($p.Version)"; Un=$null; Quiet=$null; Chave=$null; Pasta=$null; Pkg=$p.PackageFullName }
    }
    if ($lista.Count -eq 0) { Say "Nenhum programa encontrado com '$busca'." Yellow; return }

    for ($i = 0; $i -lt $lista.Count; $i++) {
        Write-Host ("[{0}] {1}  {2}  ({3})" -f ($i + 1), $lista[$i].Nome, $lista[$i].Versao, $lista[$i].Tipo)
    }
    $n = Read-Host "`nNumero do programa a remover (ENTER para cancelar)"
    if ($n -notmatch '^\d+$' -or [int]$n -lt 1 -or [int]$n -gt $lista.Count) { return }
    $alvo = $lista[[int]$n - 1]
    if (-not (Sim "Remover '$($alvo.Nome)'?")) { return }
    Say "Removendo: $($alvo.Nome)"

    if ($alvo.Tipo -eq 'Store') {
        Remove-AppxPackage -Package $alvo.Pkg -AllUsers
        if (Get-AppxPackage -AllUsers | Where-Object { $_.PackageFullName -eq $alvo.Pkg }) { Say "Nao foi possivel remover o app da Store." Red }
        else { Say "App da Store removido." Green }
        return
    }

    # Tenta parar processos relacionados
    $exeBase = $alvo.Nome -replace '[^A-Za-z0-9]', ''
    Get-Process | Where-Object { $_.Name -like "*$($exeBase.Substring(0, [math]::Min(6, $exeBase.Length)))*" } | Stop-Process -Force

    $guid = Get-Guid $alvo.Un
    $cod  = $null
    if ($guid) {
        $ml = Join-Path $desk "log-desinstalacao-msi.txt"
        $pr = Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart /l*v `"$ml`"" -Wait -PassThru
        $cod = $pr.ExitCode
        Say "msiexec retornou o codigo $cod (log em $ml)"
    } elseif ($alvo.Quiet) {
        $pr = Start-Process cmd.exe -ArgumentList "/c $($alvo.Quiet)" -Wait -PassThru
        $cod = $pr.ExitCode
        Say "Desinstalador silencioso retornou o codigo $cod"
    } elseif ($alvo.Un) {
        Say "Abrindo o desinstalador do programa. Conclua a janela que aparecer..."
        $pr = Start-Process cmd.exe -ArgumentList "/c $($alvo.Un)" -Wait -PassThru
        $cod = $pr.ExitCode
    }

    Start-Sleep -Seconds 2
    $aindaTem = Get-Apps | Where-Object { $_.DisplayName -eq $alvo.Nome -and $_.PSPath -eq $alvo.Chave }
    if (-not $aindaTem -and ($cod -eq 0 -or $cod -eq 3010 -or $null -eq $cod)) {
        Say "Programa removido com sucesso." Green
        return
    }

    Say "A desinstalacao normal falhou ou a entrada ainda existe." Yellow
    Say "Codigos comuns: 1605 = produto nao instalado (entrada orfa); 1603 = erro fatal; 1618 = outra instalacao em andamento (use opcao 2)." Yellow
    if (Sim "Forcar a remocao? (apaga a entrada do registro e a pasta de instalacao, com backup .reg)") {
        Backup-Chave $alvo.Chave
        Remove-Item -LiteralPath $alvo.Chave -Recurse -Force
        Say "Entrada do registro removida (backup em $bkdir)." Green
        if (Pasta-Segura $alvo.Pasta) {
            Remove-Item -LiteralPath $alvo.Pasta -Recurse -Force
            Say "Pasta removida: $($alvo.Pasta)" Green
        } elseif ($alvo.Pasta) {
            Say "Pasta de instalacao nao removida por seguranca: $($alvo.Pasta)" Yellow
        }
    }
}

# ---------------------------------------------------------------
function Orfas {
    Say "`n=== ENTRADAS ORFAS NA LISTA DE PROGRAMAS ===" Cyan
    $wi = New-Object -ComObject WindowsInstaller.Installer
    $orf = @()
    foreach ($a in (Get-Apps)) {
        $un = "$($a.UninstallString)"
        if (-not $un) { continue }
        $g = Get-Guid $un
        if ($g -and $un -match 'msiexec') {
            if ($wi.ProductState($g) -eq -1) { $orf += $a }
        } else {
            $exe = $null
            if ($un.Trim().StartsWith('"')) { $exe = $un.Trim().Split('"')[1] }
            elseif ($un -match '^(.*?\.exe)') { $exe = $matches[1] }
            if ($exe -and -not (Test-Path -LiteralPath $exe)) { $orf += $a }
        }
    }
    if ($orf.Count -eq 0) { Say "Nenhuma entrada orfa encontrada." Green; return }
    Say "Encontradas $($orf.Count) entrada(s) orfa(s) (o programa nao existe mais, mas continua na lista):" Yellow
    $orf | ForEach-Object { Write-Host "  - $($_.DisplayName)" }
    if (Sim "Remover estas entradas? (backup .reg sera salvo)") {
        foreach ($a in $orf) { Backup-Chave $a.PSPath; Remove-Item -LiteralPath $a.PSPath -Recurse -Force; Log "Removida entrada: $($a.DisplayName)" }
        Say "Entradas removidas. Backup em $bkdir" Green
    }
}

# ---------------------------------------------------------------
function Limpar-Temp {
    Say "`n=== LIMPAR ARQUIVOS TEMPORARIOS ===" Cyan
    $livre0 = (Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free
    $limite = (Get-Date).AddDays(-2)
    foreach ($pasta in $env:TEMP, "$env:windir\Temp") {
        Get-ChildItem -LiteralPath $pasta -Recurse -Force -File | Where-Object { $_.LastWriteTime -lt $limite } | Remove-Item -Force
        Say "Limpo: $pasta (arquivos com mais de 2 dias)"
    }
    $livre1 = (Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free
    Say ("Espaco liberado: {0} MB" -f [math]::Round(($livre1 - $livre0) / 1MB, 1)) Green
}

# ---------------------------------------------------------------
function Reparar-Store {
    Say "`n=== REPARAR APPS DA MICROSOFT STORE ===" Cyan
    if (-not (Sim "Re-registrar todos os apps da Store? Pode levar alguns minutos")) { return }
    Get-AppxPackage -AllUsers | ForEach-Object {
        $mf = Join-Path $_.InstallLocation 'AppXManifest.xml'
        if (Test-Path $mf) { Add-AppxPackage -DisableDevelopmentMode -Register $mf }
    }
    Start-Process wsreset.exe -ArgumentList '-i' -Wait
    Say "Apps da Store re-registrados." Green
}

function Reparar-Windows {
    Say "`n=== REPARAR ARQUIVOS DO WINDOWS (DISM + SFC) ===" Cyan
    if (-not (Sim "Isso pode levar 15 a 40 minutos. Continuar")) { return }
    Say "Executando DISM..."
    DISM.exe /Online /Cleanup-Image /RestoreHealth
    Say "Executando SFC..."
    sfc.exe /scannow
    Say "Concluido. Reinicie o computador." Green
}

# ---------------------------------------------------------------
$sair = $false
while (-not $sair) {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  SOLUCAO DE PROBLEMAS DE INSTALACAO E DESINSTALACAO" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  1  Diagnostico (verifica o que esta impedindo)"
    Write-Host "  2  Reparar o Windows Installer"
    Write-Host "  3  Desinstalar programa que nao sai (com remocao forcada)"
    Write-Host "  4  Remover entradas orfas da lista de programas"
    Write-Host "  5  Limpar arquivos temporarios"
    Write-Host "  6  Reparar apps da Microsoft Store"
    Write-Host "  7  Reparar arquivos do Windows (DISM + SFC)"
    Write-Host "  0  Sair"
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Registro das acoes: $log" -ForegroundColor DarkGray
    $op = Read-Host "`nEscolha uma opcao"
    switch ($op) {
        '1' { Diagnostico;      Voltar }
        '2' { Reparar-Installer; Voltar }
        '3' { Desinstalar;      Voltar }
        '4' { Orfas;            Voltar }
        '5' { Limpar-Temp;      Voltar }
        '6' { Reparar-Store;    Voltar }
        '7' { Reparar-Windows;  Voltar }
        '0' { $sair = $true }
    }
}
