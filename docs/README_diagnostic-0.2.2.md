# BO3 Splitscreen QoL – Diagnosetest 0.2.2

Dieser Diagnosetest ergänzt die bislang fehlende core_mod-Zone entsprechend
Treyarchs offizieller Mod-Vorlage. mod.cfg, cp_mod.cfg, mp_mod.cfg und zm_mod.cfg
sind jetzt bereits im Frontend verfügbar. Die Vorlage warnt ausdrücklich vor
Ladehängern bei fehlenden Konfigurationen. Recovery 0.2.1 zeigte auf dem Host
weiterhin den schwarzen Bildschirm; ohne Mod funktioniert das Spiel.
Ob 0.2.2 diesen Fehler beseitigt, ist noch nicht im Spiel bestätigt.
BO3 verwendet seine eigenen Lobby-Menüs. Enthalten sind core_mod und mp_mod
mit jeweils deutscher und englischer Sprachzone und einem Gameplay-Ladehinweis.
Auf dem Spiel-PC werden keine Mod Tools, DLLs oder Zusatzprogramme benötigt.

## Noch nicht implementiert

Unabhängige Gast-Menüs, Klassenkopierer und die Korrektur der Controller-
Menübedienung sind noch nicht fertig. Die vorige Beschreibung von Beta 0.2
war zu weitgehend: Ein erfolgreicher Build belegt keine funktionierenden Menüs.

## Installation auf dem Host

1. BO3 vollständig schließen (bei hängendem Menü über Alt+F4).
2. Den bisherigen Ordner dieser Beta aus dem BO3-Verzeichnis `mods` in einen
   Sicherungsordner verschieben. Im Video heißt die geladene Mod
   `BO3-Splitscreen-QoL-beta-0.2`; der Ordner kann auch
   `bo3_splitscreen_qol` heißen. Andere Mods behalten.
3. Den Ordner `bo3_splitscreen_qol` aus diesem ZIP direkt nach
   `Call of Duty Black Ops III\mods` entpacken.
   Erwarteter Pfad: `mods\bo3_splitscreen_qol\zone\mp_mod.ff`.
4. BO3 normal starten und die Mod unter **Mods** laden.

Alternativ die alte Beta aus dem mods-Ordner nehmen und ohne Mod spielen.
Falls eigene Steam-Startoptionen die alte Mod erzwingen, diesen fs_game-
Eintrag entfernen.

## Prüfstand

Das Host-Video zeigt eine schwarze, zeitweise teilweise aufgebaute Lobby.
Der alte Lua-Ersatz enthält Scope-Fehler und nicht übernommene Zombies-
Abhängigkeiten. Der genaue erste Laufzeitfehler ist ohne Lua-Protokoll offen.
Der Diagnosetest enthält keinen Menü-Ersatz. Build und Paket wurden geprüft;
Laufzeit und Controllerbedienung auf dem Host sind unbestätigt.

## Entwicklung

`build.ps1` baut mit den lokal konfigurierten Mod Tools beide Sprachen.
Ausgabe: `dist\recovery-0.2.1\bo3_splitscreen_qol`.
Die experimentelle Datei `ui\t6\lobby\lobbymenus.lua` wird nicht ausgeliefert.

Credit für L3akMod: D3V Team (DTZxPorter, SE2Dev, Nukem).
Die verworfene Lobby-Rekonstruktion stammt aus Scobalulas Bo3Mutators:
https://github.com/Scobalula/Bo3Mutators.
