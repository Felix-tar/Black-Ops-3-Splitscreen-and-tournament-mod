# Fertige Angaben für den Steam-Workshop-Eintrag

Alles in diesem Ordner ist zum Kopieren gedacht. Im Mod-Tools-Launcher auf **Publish** klicken und die Felder
ausfüllen.

| Feld im Dialog | Wert |
| --- | --- |
| **Title** | `BO3 Splitscreen QoL` |
| **Thumbnail** | `workshop\thumbnail.png` (512×512, liegt neben dieser Datei) |
| **Tags** | `Mod`, `Multiplayer` |
| **Description** | der Text unten (deutscher Block, darunter der englische) |

---

## Description (zum Kopieren)

```text
Komfort-Mod für lokalen Splitscreen zu zweit - offline und im LAN.

WAS DIE MOD MACHT

- Eingabegerät für Spieler 1 frei wählbar (Tastatur oder ein bestimmter Controller), zuverlässige Zuordnung
  beider Controller; die Tastatur bleibt für Spieler 1 immer zusätzlich aktiv.
- "Splitscreen aktivieren" als normaler Eintrag in der linken Lobby-Liste, mit dem Steuerkreuz erreichbar.
- Geteilter Bildschirm: Klasseneditor, Spezialisten und Punkteserien für beide Spieler gleichzeitig,
  jeder navigiert mit seinem eigenen Controller in seiner Hälfte.
- Klassen zwischen beiden Spielern kopieren, einzeln oder alle, mit Bild-Vorschau vorher.
- Lokale Profile: Beim Beitritt fragt die Mod "Wer spielt?". Namen bleiben gespeichert und stehen in der
  Party-Liste, in der Punkteliste und im Killfeed - statt zweimal derselbe Steam-Name.
- Statistiken je Profil (Spiele, Siege, Kills, Tode, K/D, Kopfschüsse) und Duelle gegeneinander,
  dazu eine lokale Bestenliste mit Profilverwaltung.
- Turniere: Best of 3, Best of 5 oder Jeder gegen jeden, Modus und Karte je Runde, eigene Spielregeln
  (alles aus "Spiel einrichten", dazu Bots und Waffenbeschränkungen wie "Nur Scharfschützengewehre"),
  speicherbare Turniervorlagen und automatische Wertung nach jedem Match.
- Alle Menüs der Mod lassen sich mit Controller, Tastatur und Maus bedienen.

SO GEHT ES LOS

Mods-Menü -> Mod laden -> Mehrspieler -> offline oder LAN -> Eigenes Spiel.
In der linken Liste unter CODCASTER steht "SPLITSCREEN AKTIVIEREN".

HINWEISE

- Nur offline und im LAN. Black Ops III erlaubt Mods nicht online.
- Menüsprache der Mod: Deutsch.
- Statistiken werden auf dem Rechner gezählt, der das Spiel hostet.
- Die Mod ändert keine Original-Menüs, sie ergänzt sie. Klassen und Statistiken des normalen Spiels
  bleiben unberührt, da Mods eigene Spielstände nutzen.

Quellcode, ausführliche Anleitung und Fehlermeldungen:
https://github.com/<deinName>/BO3-Splitscreen-QoL

----------------------------------------------------------------

English

Quality-of-life mod for local two-player splitscreen - offline and LAN.

- Free choice of input device for player 1 (keyboard or a specific controller) and reliable assignment of
  both controllers; the keyboard always stays available for player 1.
- "Activate splitscreen" as a normal entry in the left lobby list, reachable with the D-pad.
- Split screen: class editor, specialists and scorestreaks for both players at the same time, each one
  navigating their own half with their own controller.
- Copy classes between both players, one or all, with a picture preview.
- Local profiles: when player 2 joins, the mod asks who is playing. Names are stored and shown in the party
  list, the scoreboard and the killfeed instead of the same Steam name twice.
- Per-profile statistics (matches, wins, kills, deaths, K/D, headshots), head-to-head records and a local
  leaderboard with profile management.
- Tournaments: best of 3, best of 5 or free for all, mode and map per round, custom game rules (everything
  from the game settings plus bots and weapon restrictions such as snipers only), saveable presets and
  automatic scoring after every match.
- Every menu of the mod works with controller, keyboard and mouse.

Note: offline and LAN only - Black Ops III does not allow mods online. The mod's menu texts are German.

Source code and documentation:
https://github.com/<deinName>/BO3-Splitscreen-QoL
```

---

## Änderungshinweise für die Workshop-Seite (Version 0.7.0)

```text
0.7.0
- Profilwahl "Wer spielt?" läuft jetzt getrennt in beiden Bildschirmhälften
- Klassen kopieren mit Bild-Vorschau beider Klassen
- Turnier: Spielregeln je Runde (inkl. Bots und Waffenbeschränkungen), Kartenbilder,
  speicherbare Turniervorlagen, Export und Import als Datei
- Lokale Bestenliste: Profile umbenennen, zurücksetzen, löschen
- Mausbedienung in allen Menüs der Mod
```

## Vor dem Veröffentlichen prüfen

- Im Launcher ist **`bo3_splitscreen_qol`** angehakt (nicht `bo3_qol_dev`).
- Der Release-Build ist aktuell: `build-dev.ps1 -Release -Version 0.7.0 -Install`, danach einmal im Spiel laden.
- Im Beschreibungstext `<deinName>` durch deinen GitHub-Namen ersetzen (zwei Stellen).
- Sichtbarkeit auf der Workshop-Seite zuerst auf privat stellen, testen, dann öffentlich schalten.

## Nach dem Veröffentlichen

Der Launcher legt `...\Call of Duty Black Ops III 455130\mods\bo3_splitscreen_qol\zone\workshop.json` mit deiner
Workshop-ID an. Diese Datei sichern (der Build kopiert sie automatisch nach `workshop\bo3_splitscreen_qol\`), aber
nicht öffentlich hochladen: Sie enthält den vollständigen Pfad zu deinem Vorschaubild.
