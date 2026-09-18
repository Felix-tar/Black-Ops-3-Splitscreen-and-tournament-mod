# Wie die Mod funktioniert

Entwicklerdokumentation zu **BO3 Splitscreen QoL**: welche Software nötig ist, wie die Mod aufgebaut ist, wie sie ins
Spiel eingreift, wo die Daten liegen und wie man sie erweitert. Für die Bedienung siehe [README.md](README.md).

## Inhalt

- [Kurzfassung](#kurzfassung)
- [Benötigte Software](#benötigte-software)
- [Wie BO3 die Mod lädt](#wie-bo3-die-mod-lädt)
- [Bauen](#bauen)
- [Aufbau der Module](#aufbau-der-module)
- [UI-Baukasten](#ui-baukasten)
- [Geteilter Bildschirm](#geteilter-bildschirm)
- [Eingabegeräte](#eingabegeräte)
- [Speichern ohne Dateizugriff](#speichern-ohne-dateizugriff)
- [Vom Match zurück ins Menü](#vom-match-zurück-ins-menü)
- [Turniere und Regeln](#turniere-und-regeln)
- [Prüfen und Testen](#prüfen-und-testen)
- [Regeln für Änderungen](#regeln-für-änderungen)
- [Erweitern](#erweitern)
- [Offene Fragen](#offene-fragen)

## Kurzfassung

Black Ops III lädt seine Menüs aus Lua-Dateien (LUI) und die Spiellogik aus GSC-Skripten. Beides steckt in
Fastfiles (`.ff`). Eine Mod ist ein Ordner mit eigenen Fastfiles, die das Spiel **zusätzlich** lädt; gleichnamige
Dateien aus der Mod haben Vorrang vor denen des Spiels.

Diese Mod nutzt genau das:

- `core_mod.ff` enthält unsere Lua-Dateien und **zwei Originaldateien mit einer zusätzlichen Zeile**. Über die
  bekommt die Mod ihren Einstiegspunkt, ohne irgendein Menü zu ersetzen.
- `mp_mod.ff` enthält ein Spielskript, das im Match Kills mitzählt und am Ende ein Ergebnis zurückgibt.
- `en_*.ff` und `ge_*.ff` sind leere Sprachzonen. Ohne sie bricht das Spiel mit „Could not find zone …“ ab.

Alles läuft offline. Es gibt keine DLL, keinen Hook ins Spiel, keinen Dateizugriff außerhalb der Engine-Funktionen.

## Benötigte Software

| Zweck | Software | Hinweise |
| --- | --- | --- |
| Spielen | *Call of Duty: Black Ops III* (PC, Steam) | Mods nur offline/LAN |
| Bauen | *Black Ops III Mod Tools* (Steam → Bibliothek → Tools) | liefert `bin\linker_modtools.exe` und den Launcher |
| Lua in Mods bauen | **L3akMod** (The D3V Team) | Die offiziellen Tools linken keine Lua-Rawfiles in Mods. Beim Bauen meldet sich L3akMod im Linker-Log. |
| Bauen automatisieren | Windows PowerShell 5.1 | `build-dev.ps1` |
| Lua prüfen | Python 3 | `tools/lua_lint.py`, optional aber empfohlen |
| Originalskripte lesen | *Atian Cod Tools* (ate47) + *CoDLuaDecompiler* | nur zur Recherche, nichts davon gehört ins Repository |

Auf dem **Spiel-PC** wird nichts davon gebraucht: dort liegt nur der Mod-Ordner.

## Wie BO3 die Mod lädt

Beim Start des Multiplayer-Menüs lädt BO3 eine feste Liste von Lua-Dateien. Die letzte davon ist
`ui/uieditor/menus/core_frontend_patch_require.lua` – eine reine Liste von `require`-Aufrufen. Die Mod liefert
diese Datei mit **derselben Liste plus einer Zeile** aus:

```lua
pcall( require, "ui.qol.main" )
```

`ui/qol/main.lua` lädt danach alle Module einzeln, jedes in einem `pcall`. Scheitert ein Modul, laufen die anderen
weiter und der Fehler erscheint in der Statuszeile der Lobby, statt das Menü schwarz zu machen.

Im Match gilt dasselbe über `ui/uieditor/menus/core_patch_require.lua` → `ui.qol.ingame` (Namen in der Punkteliste,
eigener Killfeed). Diese Datei wird erst im Match geladen, kurz bevor das HUD entsteht.

Wichtig: Nach dem Laden des Frontends ruft BO3 `DisableGlobals()` auf. Danach lassen sich **keine neuen globalen
Variablen** mehr anlegen. Alles der Mod hängt deshalb an einer Tabelle: `CoD.QoL` (kurz `QoL`).

Die Mod verändert keine Originalmenüs, sondern legt sich um deren Funktionen (Wrapper):

| Hook | Zweck |
| --- | --- |
| `CoD.LobbyMenus.AddButtonsForTarget` | zusätzliche Einträge in der linken Lobby-Liste |
| `LUI.createMenu.Lobby` | Spieler-2-Karte, Statuszeile, Datenstart, Auswertung nach dem Match |
| `CoD.Menu.HandleButtonPress` | Tasten des zweiten Controllers für die Spieler-2-Karte abfangen |
| `DataSources.OptionGamepadSettingsPC.prepare` | Zeile „Eingabegerät Spieler 1“, Tauschlogik für Spieler 2 |
| `CoD.LobbyButtons.MP_CAC / MP_SPECIALISTS / MP_SCORESTREAKS` | diese Menüs im geteilten Bildschirm öffnen |
| `CoD.LobbyUtility.UpdateLobbyList` | Profilnamen in der Party-Liste |
| `GetClientNameAndClanTag`, `LUI.createMenu.T7Hud` | Namen in der Punkteliste, eigener Killfeed |
| `CoD.GameMessages.ObituaryWindowUpdateVisibility` | Original-Killfeed ausblenden, solange eigene Namen aktiv sind |

## Bauen

`build-dev.ps1` macht alles in einem Durchgang:

1. **Prüfen:** Jede Lua-Datei muss im Zonenrezept stehen und umgekehrt; keine Datei darf ein UTF-8-BOM haben;
   `tools/lua_lint.py` parst alle Dateien.
2. **Staging:** `development\` wird nach `<Mod Tools>\mods\<modname>\` kopiert. Im Release-Modus werden dabei in
   `util.lua` die Zeilen `QoL.VERSION` und `QoL.DEV` ersetzt.
3. **Linken:** je Sprache (englisch, deutsch) und Zone (`core_mod`, `mp_mod`):

   ```text
   bin\linker_modtools.exe -language english -fs_game <modname> -modsource core_mod
   ```

   Das Log wird auf „error/failed“ geprüft, Fehler brechen den Build ab.
4. **Kontrolle:** alle sechs `.ff` vorhanden und nicht leer, jede Lua-Datei steht in der Assetliste des Pakets.
5. **Ausliefern:** Kopie nach `dist\`, im Release zusätzlich als ZIP; mit `-Install` in den Spielordner.

Die Zonenrezepte liegen in `development/zone_source/`:

```text
core_mod.zone   >mode,core   alle Lua-Rawfiles + die cfg-Dateien des Spiels
mp_mod.zone     >mode,mp     scriptparsetree scripts/mp/gametypes/_clientids.gsc
loc/*.zone                   leere Sprachzonen (en_/ge_)
```

`mod.cfg`, `dummy.cfg` usw. im Rezept sind Dateien der Mod Tools, keine eigenen.

Entwicklungs- und Release-Build unterscheiden sich nur in zwei Zeilen:

| | Entwicklung (`bo3_qol_dev`) | Release (`bo3_splitscreen_qol`) |
| --- | --- | --- |
| `QoL.DEV` | `true` | `false` |
| Statuszeile oben | immer (Version, Controller, Speicher, Selbsttest) | nur bei Fehlern |
| Konsolenlog | `logfile 2` beim Start | nur beim Export von Turniervorlagen |

## Aufbau der Module

Alle Module liegen in `development/ui/qol/` und hängen an `CoD.QoL`. Ladereihenfolge steht in `main.lua`; Module
greifen zur Laufzeit über `QoL.<name>` aufeinander zu, damit ein fehlendes Modul nicht alles mitreißt.

| Modul | Aufgabe |
| --- | --- |
| `util.lua` | `CoD.QoL`, Version/DEV-Schalter, Log, Fehlerbehandlung (`QoL.safe`), Controller-Zuordnung, Sitzungswerte (Dvars) |
| `lang.lua` | alle Texte in sechs Sprachen, `QoL.L(key, ...)`, Sprachwahl |
| `ui.lua` | Baukasten: Menüs, Tastenbelegung, Listen, Texte, Bilder, Maus, Texteingabe |
| `input.lua` | Eingabegerät Spieler 1, Controller-Tausch, Wächter |
| `lobbybuttons.lua` | Einträge in der linken Lobby-Liste |
| `splitlobby.lua` | Lobby-Hook: Spieler-2-Karte, Statuszeile, Start der Daten, Auswertung nach dem Match |
| `splitmenu.lua` | geteilter Bildschirm, Hälften-Menü (Hub) |
| `profiles.lua` | „Wer spielt?“ als einbettbare Seite, Namen in der Party-Liste |
| `classcopy.lua` | Klassen kopieren samt Bild-Vorschau |
| `leaderboard.lua` | lokale Bestenliste, Profilverwaltung |
| `storage.lua` | kleiner dauerhafter Textspeicher (Profile) |
| `bigstore.lua` | großer dauerhafter Speicher (Turniervorlagen) |
| `data.lua` | Datenmodell: Profile, Duelle, Zuordnung, Eingabegerät; Serialisierung; verzögertes Speichern |
| `stats.lua` | Match-Ergebnis auswerten → Profile, Duelle, Turnier |
| `names.lua` | Namenstabelle Gamertag → Anzeigename (Lobby ↔ Match) |
| `rules.lua` | Spielregeln: Katalog, Text-Format, Anwenden (Einstellungen, Bots, Beschränkungen) |
| `presets.lua` | Turniervorlagen, Speicher, Export/Import |
| `tournament.lua` | Turnierzustand, Wertung, Rundenstart |
| `tournamentmenu.lua` | Turnier-Oberfläche |
| `ingame.lua` | im Match: Namen in der Punkteliste, eigener Killfeed |
| `selftest.lua` | Selbsttest der reinen Logik |

Dazu `development/scripts/mp/gametypes/_clientids.gsc`: die Originaldatei des Spiels plus Kill-Zählung,
Killfeed-Ereignisse und Ergebnisbericht.

## Sprachen

Jeder Text, den die Mod anzeigt, steht in `lang.lua`. Englisch ist die Vorgabe und die Referenzliste; fehlt ein
Schlüssel in einer anderen Sprache, greift automatisch Englisch.

```lua
QoL.L("cc_copied_one", name)     -- "Copied: {1}" -> "Copied: Sturmgewehr"
```

- Ohne eigene Wahl richtet sich die Mod nach dem Spiel: `Engine.GetLanguage()` liefert z. B. `german` oder
  `simplifiedchinese`, eine Tabelle in `lang.lua` bildet das auf unsere Codes ab.
- Die gewählte Sprache steht im Sitzungs-Dvar `qol_lang` und dauerhaft im Profilspeicher (Satz `L`).
- `Lang.version` zählt Wechsel mit. Der 500-ms-Timer der Lobby vergleicht den Zähler, schreibt die Texte der
  Spieler-2-Karte neu und baut die Lobby-Liste über `LuaUtils.ForceLobbyButtonUpdate()` neu auf. Nach dem Laden des
  Profilspeichers ruft die Lobby `Lang.reset()`, weil die gespeicherte Sprache erst dann bekannt ist.
- Umgeschaltet wird in den Spieleinstellungen: `input.lua` hängt neben der Zeile für das Eingabegerät eine zweite
  Zeile mit der Sprachauswahl in die Liste `OptionGamepadSettingsPC`.
- Texte werden immer **beim Aufbau eines Menüs** übersetzt, nie beim Laden der Datei. Tabellen wie die
  Beschränkungs-Kategorien speichern deshalb nur Schlüssel (`r_cat_smg`), keine fertigen Texte. Der Zwischenspeicher
  der Regelgruppen enthält die Sprache im Schlüssel.
- Der Selbsttest prüft, dass jede Sprache genau die Schlüssel der englischen Liste hat.

**Eine Sprache ergänzen:** in `lang.lua` `Lang.ORDER` und `Lang.NAMES` erweitern und eine Tabelle
`Lang.strings.<code>` mit allen Schlüsseln anlegen (am einfachsten die englische kopieren und übersetzen).
Der Selbsttest meldet danach jeden vergessenen Schlüssel.

**Schriftarten:** Die Mod zeichnet mit `fonts/default.ttf` des Spiels. Chinesische und indische Zeichen sind darin
je nach Installation nicht enthalten; dann bleibt der Text leer. Eine eigene Schriftart müsste als Asset in die
Fastfile aufgenommen werden.

## UI-Baukasten

BO3-Menüs rechnen in einem Raster von **1280 × 720**; die echte Breite hängt vom Seitenverhältnis ab
(`QoL.rootWidth() = 720 × Seitenverhältnis`). `ui.lua` verankert Texte deshalb an der Bildmitte, damit
Layouts auch bei 16:10 oder 21:9 stimmen.

```lua
local menu = UI.newMenu("QoLBeispiel", controller)   -- Menü, das einem Controller gehört
UI.fullscreenGround(menu, 0.95)                      -- dunkler Hintergrund
UI.text(menu, "TITEL", 110, 60, 900, 40, UI.ORANGE)  -- x in 1280er-Koordinaten
local list = UI.newList(menu, 110, 120, 640, 32, 12) -- Liste mit 12 sichtbaren Zeilen
list.setItems({ { text = "Zeile", color = UI.GREEN } })
UI.bindButtons(menu, controller, handlers)           -- up/down/left/right/confirm/back/extra
UI.button(menu, "ZURÜCK", 1000, 672, 170, handlers.back)
```

- **Tasten:** `AddButtonCallbackFunction` hängt sich an die Tastenbits **nur des eigenen Controllers**. Deshalb
  kann jede Bildschirmhälfte unabhängig bedient werden. Zusätzlich werden Tastaturkürzel registriert
  (`UPARROW`, `ENTER`, `ESCAPE`, `SPACE`), die immer bei Spieler 1 landen.
- **Maus:** `UI.onClick` hängt `leftmouseup`/`rightmouseup` an ein Element. LUI schickt diese Ereignisse nur an
  Elemente mit `setHandleMouse(true)` und nur, wenn der Druck im Element begann.
- **Texteingabe:** `UI.askText(menu, controller, fn, typ)` ruft `ShowKeyboard`; die Eingabe kommt als Ereignis
  `ui_keyboard_input` zurück.

## Geteilter Bildschirm

Das Herzstück ist `splitmenu.lua`:

1. `QoLSplitScreen` ist ein Overlay über der Lobby. Solange es offen ist, nimmt die Lobby keine Eingaben an.
2. Jede Hälfte ist ein Element mit **Stencil-Clipping** (`setUseStencil(true)`). Darin liegt eine „Bühne“ von
   1280 × 720, skaliert auf die echte Halbbreite (`Skalierung = Halbbreite / 853`) und so verschoben, dass der
   linke Rand des Menüinhalts am Rand der Hälfte sitzt. Ein Timer prüft alle 500 ms die Breite und legt das
   Layout bei Fenster- oder Auflösungsänderung neu.
3. Auf jeder Bühne liegt ein kleines Menü (`QoLSplitHub`), das dem Controller dieses Spielers gehört. Es hat zwei
   Seiten: Profilwahl und Menüliste.
4. Öffnet der Hub ein Originalmenü, hängt BO3 das neue Menü an das Elternelement des Öffners – also in dieselbe
   Bühne. So bleibt die ganze Menükette in ihrer Hälfte.
5. Geschlossen wird, wenn beide Hälften FERTIG melden. Vorher wird `SaveLoadout` aufgerufen und jedes offene
   Originalmenü von oben nach unten geschlossen.
6. Verliert ein Controller die Verbindung, passiert erst einmal nichts außer einem Hinweis. Erst wenn Spieler 2
   zehn Sekunden abgemeldet ist, wird sauber geschlossen. Früher führte sofortiges Schließen zu einem Absturz.

Grenzen: Die 3D-Szene des Menüs gibt es nur einmal, deshalb haben die Hälften einen deckenden Hintergrund
(keine zwei Spezialisten-Figuren nebeneinander).

## Eingabegeräte

Die PC-Fassung hat eine Engine-Schnittstelle für die Zuordnung Controller → Spieler:

```lua
Engine.GamepadsConnectedPortMapping()      -- { Anzeigename = "Port" }
Engine.GamepadsConnectedPort(localPlayer)  -- aktueller Port
Engine.GamepadsConnectedMap(localPlayer, port)
Engine.GamepadsConnectedUnMap(localPlayer)
Engine.GamepadsConnectedIsActive(localPlayer)
```

Die Originaloption „Eingabegerät Spieler 2“ nutzt dieselben Aufrufe. `input.lua` baut daneben die Zeile für
Spieler 1, ersetzt den Setzer der Spieler-2-Zeile durch eine Tauschlogik (erst den anderen abmelden, dann neu
zuordnen) und prüft jede Sekunde, ob die Zuordnung noch zur Einstellung passt. „Verbunden“ heißt dabei „steht im
Port-Mapping“ – `GamepadsConnectedValidPort` meldet einen vom anderen Spieler belegten Port als ungültig, was
früher den Tausch verhindert hat.

## Speichern ohne Dateizugriff

Mods dürfen keine eigenen Dateien schreiben. BO3 schreibt im Multiplayer aber seine eigenen Profildateien nach
`players\mods\<mod>\` (bzw. `players\311210\<Workshop-ID>\`). Die Mod nutzt Felder dieser Dateien, die offline
nie gebraucht werden: die Klassensätze für private und Liga-**Online**-Matches
(`customMatchCacLoadouts`, `leagueCacLoadouts`) in `loadouts_mp_offline_0.cgp`. Offline benutzt das Spiel nur
`cacLoadouts` – die echten Klassen bleiben also unangetastet.

**Textspeicher (`storage.lua`)** – Profile, rund 300 Zeichen:

- Ablage: die Klassennamen der beiden ungenutzten Sätze (20 Felder × 16 Zeichen).
- Inhalt: `Q2|<Länge>|<Daten>`, verteilt über alle Felder.
- Format der Daten (`data.lua`), Sätze mit `;` getrennt:

  ```text
  B3;P1,120,98,20,15,7,Anna;P2,80,110,12,15,8,Ben;V1,2,34;V2,1,28;A1,2;I-1
  B = Startzähler   P = Profil (id,Kills,Tode,Kopfschüsse,Spiele,Siege,Name)
  V = Duell (Angreifer,Opfer,Kills)   A = Zuordnung Spieler 1/2   I = Eingabegerät Spieler 1
  ```

- Wird es eng, verwirft `Data.fit` zuerst die Duelle mit den wenigsten Kills; passt es dann immer noch nicht,
  schlägt das Anlegen eines Profils fehl (statt still Daten zu verlieren).
- Geschrieben wird verzögert (`Data.saveSoon` / `Data.tick` / `Data.flush`), damit mehrere Klicks nicht jedes Mal
  eine Datei schreiben.

**Zusatzspeicher (`bigstore.lua`)** – Turniervorlagen, mehrere Hundert Zeichen:

- Ablage: die Item-Felder derselben ungenutzten Klassensätze (`customclass[0..9].<slot>`).
- Die Bitbreite jedes Feldes ist nicht dokumentiert und wird beim Start ermittelt: Wert `2^n-1` schreiben und
  zurücklesen, dazu ein Muster zur Gegenprobe; der Originalwert wird sofort wiederhergestellt.
- Die Daten werden als Bitstrom über alle Felder verteilt, mit Kopf: Magic, Länge, Fletcher-16-Prüfsumme.
  Stimmt etwas nicht, gilt der Speicher als leer, statt Müll zu lesen.

**Sitzungswerte** sind Dvars: Sie überleben den Wechsel Lobby ↔ Match (die Lua-Menüs werden dabei neu geladen),
aber keinen Neustart des Spiels:

| Dvar | Inhalt |
| --- | --- |
| `qol_names` | `gamertag=Anzeigename|…` für Punkteliste und Killfeed |
| `qol_tournament` | Turnierstand (Format, Runde, Spieler, Ergebnisse, Regeln) |
| `qol_round_info` | Hinweistext, den das Match beim Spawnen zeigt |
| `qol_last_match` | Ergebnisbericht des Matches (vom GSC geschrieben) |

## Vom Match zurück ins Menü

`_clientids.gsc` ist die Originaldatei plus drei Ergänzungen:

1. `level.callbackPlayerKilled` wird umhüllt: Jeder Kill zählt in `level.qol_kills` (Angreifer_Opfer → Anzahl),
   solange nicht beide Bots sind.
2. Für den Killfeed geht pro Kill ein Ereignis ans Menü:
   `LUINotifyEvent( &"qol_obit", 3, Angreifer, Opfer, Flags )` (Flags: 1 Kopfschuss, 2 Nahkampf, 4 Selbstmord).
   In Lua kommt das als Modell `scriptNotify` an, gelesen mit `CoD.GetScriptNotifyData`.
3. Bei `game_ended` schreibt das Skript einen Bericht in den Dvar `qol_last_match`:

   ```text
   v1;t=<Zeit>;gt=<Modus>;map=<Karte>
   ts=<Team>,<Punkte>
   p=<Ent>,<Team>,<Kills>,<Tode>,<Kopfschüsse>,<Punkte>,<Bot 0/1>,<Name>
   k=<Angreifer>_<Opfer>,<Anzahl>
   ```

Zurück in der Lobby liest `stats.lua` den Dvar, leert ihn, ordnet die Berichtseinträge den lokalen Spielern zu
(zuerst über den Gamertag, sonst über die Reihenfolge) und schreibt Statistiken, Duelle und Turnierwertung.

Es gibt in BO3 keine Möglichkeit, Spieler im Match umzubenennen. Deshalb zeigt die Mod die Namen nur dort, wo das
Menü zeichnet: Punkteliste (`GetClientNameAndClanTag`) und ein eigener Killfeed.

## Turniere und Regeln

- **Zustand:** `tournament.lua` hält alles im Dvar `qol_tournament` (Format, aktuelle Runde, Spieler mit Team und
  Anzeigename, Runden mit Modus, Karte, Regeln, Ergebnis).
- **Wertung:** `Tournament.score(t, report)` ist absichtlich frei von Engine-Aufrufen – so kann der Selbsttest sie
  prüfen. Sie liefert zurück, ob gewertet wurde, einen Text fürs Menü und ob die nächste Runde zu laden ist.
- **Runde laden** (`applyRound`): Modus setzen → Karte setzen → **Regeln anwenden** → Teams zuweisen →
  `OnGametypeSettingsChange`. Die Reihenfolge ist wichtig, weil das Setzen des Modus die Voreinstellungen lädt.
- **Regeln** (`rules.lua`) sind ein kompakter Text:

  ```text
  timeLimit:10,onlyHeadshots:1,bot_maxAxis:3,bot_difficulty:2,res:smg+ar+cqb+lmg+pst+lnc+spw
  ```

  - Spieleinstellungen kommen aus der Tabelle des Spiels (`CoD.GameOptions.GameSettings`) – dieselbe Quelle, aus
    der „Spiel einrichten“ seine Listen baut. Gesetzt wird mit `Engine.SetGametypeSetting`.
  - Nicht genannte Einstellungen bedeuten „Standard“. Beim Anwenden setzt die Mod erst **alle** Einstellungen auf
    ihren Vorgabewert (`Engine.GetGametypeSetting(key, true)`) und danach die Abweichungen. Das ist nötig, weil
    das Kommando `resetCustomGametype`, das BO3 beim Moduswechsel aufruft, in dieser Fassung nicht existiert.
  - Bots sind Dvars (`bot_maxAllies`, `bot_maxAxis`, `bot_maxFree`, `bot_difficulty`).
  - Beschränkungen (`res:`) sperren Gegenstandsgruppen: Für alle Item-Indizes 0..255 liefert
    `Engine.GetUnlockableInfoByIndex` Slot und Gruppe; gesperrt wird mit `Engine.SetItemRestrictionState`.
- **Vorlagen** (`presets.lua`) sind eine Zeile Text und liegen im Zusatzspeicher:

  ```text
  T1~Scharfschützen~bo3~a~res:smg+ar+cqb+lmg+pst+lnc+spw~tdm/mp_biodome/^conf/mp_spire/^tdm/mp_apartments/
  ```

  Export schreibt daraus `;set qol_vorlage_N "…"`-Zeilen ins Konsolenlog (das Spiel kann keine Dateien schreiben,
  aber es schreibt sein Log). Import führt `exec qol_turniere.cfg` aus und liest die Dvars wieder ein.

## Prüfen und Testen

Es gibt keinen Lua-Interpreter für BO3 außerhalb des Spiels, deshalb zwei Netze:

1. **`tools/lua_lint.py`** – ein vollständiger Lua-5.1-Parser in Python. Er findet Syntaxfehler, unbekannte
   globale Namen (typisch: eine lokale Funktion vor ihrer Deklaration benutzt) und versehentlich neu angelegte
   Globals, die zur Laufzeit an `DisableGlobals()` scheitern würden. Bekannte Namen des Spiels zieht er aus den
   dekompilierten Originaldateien, wenn sie vorliegen.

   ```bash
   python tools/lua_lint.py development/ui
   ```

2. **Selbsttest im Spiel** (`selftest.lua`) – läuft bei jedem Laden des Menüs und prüft die reine Logik:
   Speicherformat hin und zurück, Namenstabelle, Bitpacken des Zusatzspeichers, Match-Bericht, Turnierwertung
   (Sieg, Unentschieden, fremdes Match, Jeder-gegen-jeden), Regel- und Vorlagen-Codes. Ergebnis steht im
   Entwicklungs-Build in der Statuszeile („Selbsttest OK (n)“), Fehler erscheinen in jedem Build.

Alles, was die Engine anfasst, lässt sich nur im Spiel prüfen. Dafür gilt: **getestet ≠ kompiliert** – in der
README sind die im Spiel bestätigten Funktionen von den ungetesteten getrennt.

## Regeln für Änderungen

- **Keine neuen Globals.** Alles hängt an `CoD.QoL`.
- **Alles absichern.** Hooks und Button-Aktionen laufen über `QoL.safe(...)` bzw. `pcall`, damit ein Fehler nie das
  Originalmenü lahmlegt.
- **Lua-Dateien als UTF-8 ohne BOM** speichern (der Build bricht sonst ab). `build-dev.ps1` selbst braucht das BOM.
- **Neue Lua-Datei** → in `development/zone_source/core_mod.zone` eintragen **und** in `main.lua` laden.
- **Originalfunktionen nie ohne ihre Argumente aufrufen.** `CoD.LobbyUtility.UpdateLobbyList()` ohne Listen-Widget
  baut alle Einträge mit Steam-Namen neu auf und wirft danach einen Fehler – das war die Ursache eines
  Namens-Bugs.
- **Offline bleiben.** Mit geladener Mod nicht in den Online-Bereich wechseln.
- **Reine Logik von Engine-Aufrufen trennen**, damit der Selbsttest sie prüfen kann.
- **Keine Texte fest im Code.** Jeder sichtbare Text kommt über `QoL.L` aus `lang.lua`; Log- und Diagnosetexte
  bleiben auf Englisch.

## Erweitern

**Neuer Eintrag in der Lobby-Liste** (`lobbybuttons.lua`):

```lua
table.insert(entries, overlayEntry("btnQoLMeins", "MEIN MENÜ", "meins"))
```

Der letzte Wert ist der Modulname unter `QoL`; beim Drücken ruft die Mod `QoL.meins.open(menu)`.

**Neues Menü:** Datei in `development/ui/qol/` anlegen, `LUI.createMenu.QoLMeins = function(controller) … end` mit
dem UI-Baukasten bauen und mit `OpenOverlay(menu, "QoLMeins", controller)` öffnen.

**Neue Einstellung im Turnier:** Steht sie in `CoD.GameOptions.GameSettings`, reicht es, ihren Namen in
`rules.lua` in die passende Gruppe aufzunehmen. Für etwas anderes (z. B. einen Dvar) einen Eintrag mit
`kind = "dvar"` ergänzen und in `Rules.apply` behandeln.

**Neues Turnierformat:** In `tournament.lua` einen Eintrag in `Tournament.formats` anlegen (Rundenzahl, nötige
Siege oder Punktwertung) und in `Tournament.score` die Auswertung ergänzen.

**Mehr Speicher:** Erst `Data.fit` (kürzen) und das Format prüfen; der Zusatzspeicher lässt sich über weitere
Felder in `bigstore.lua` erweitern, wenn sie offline wirklich ungenutzt sind.

## Offene Fragen

- Ob BO3 die Gegenstands-Sperren offline in jedem Modus durchsetzt, ist nicht bestätigt.
- Ob der Zusatzspeicher einen Neustart zuverlässig übersteht, muss der Dauertest zeigen (Statuszeile „Vorlagen ok“).
- Von wo genau `exec` Dateien liest, wird im Entwicklungs-Build gemessen (Statuszeile „Datei …“).
- Teams per `Engine.LobbyHostAssignTeamToClient` werden gesetzt, die Wirkung im Match ist noch nicht bestätigt.
- LAN mit zwei Rechnern ist gebaut, aber nie zu zweit getestet. Statistiken entstehen nur auf dem Host.
