# WorldClockSync

Petite app iOS (SwiftUI + CoreBluetooth) qui règle le fuseau horaire et active l'heure automatique (NTP) des horloges **WordClock Jupiter** de Build-Yours via Bluetooth Low Energy.

> ⚠️ Projet **non officiel**, sans lien avec Build-Yours. Écrit parce que l'app officielle n'arrivait pas à remettre l'horloge à l'heure depuis iOS (horloge bloquée avec 1 h d'avance).

## Protocole BLE observé

| Élément | Valeur |
|---|---|
| Nom annoncé | `WordClock_<numéro>` |
| Service | `0xABCD` |
| Caractéristique | `0x2025` (read / write / notify) |
| Format | commandes texte ASCII, écrites avec réponse |

Séquence qui a corrigé l'heure (horloge connectée au Wi-Fi) :

```
AT1                               # heure automatique (NTP)
TZCET-1CEST,M3.5.0,M10.5.0/3      # fuseau au format POSIX (ici Europe/Zurich, Paris, Berlin…)
SS                                # sauvegarde
```

L'horloge applique le changement après une à deux minutes (prochaine synchro NTP). Elle ne renvoie aucune notification à ces commandes.

Autres commandes repérées dans l'app officielle (non testées) : `AT0` (heure manuelle), `ST…` (régler l'heure en UTC), `NF`, `NB` (mode nuit), `BRS`, `BRL` (luminosité).

## Utilisation

1. `brew install xcodegen && xcodegen generate` (le `.xcodeproj` est déjà fourni)
2. Ouvrir `WorldClockSync.xcodeproj`, choisir son équipe dans *Signing & Capabilities*.
3. Lancer sur un iPhone (le simulateur n'a pas de Bluetooth).
4. Fermer l'app officielle avant : l'horloge n'accepte qu'une connexion BLE à la fois.

Le fuseau IANA choisi est converti en chaîne POSIX par `Sources/PosixTZ.swift` (testé dans `Tests/`).

## Licence

MIT
