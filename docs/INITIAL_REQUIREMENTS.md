# BO3 Splitscreen QoL

Eine Offline-Multiplayer-Mod für **Call of Duty: Black Ops III**, die über das
Menü **Mods** geladen wird und die Bedienung von **Eigenes Spiel** im
Zweispieler-Splitscreen verbessert.

## Ziel der ersten Version

- Nach dem Beitritt des Gasts besitzen beide lokalen Spieler getrennten Zugriff
  auf Spezialisten, Klasseneditor und Punkteserien.
- Spieler 1 behält die Kontrolle über Karte, Spielregeln und Matchstart.
- Spieler 1 kann mit Tastatur/Maus oder Controller spielen.
- Spieler 2 wird unabhängig vom konkreten Gerät über den zweiten lokalen
  Gamepad-Slot bedient.
- Eine Klasse von Spieler 1 kann in eine frei gewählte Klasse des Gasts kopiert
  werden.
- Die Mod ist für Offline- und private 1-gegen-1-Spiele vorgesehen.

## Eingabeprinzip

Die Mod bindet Funktionen an logische BO3-Aktionen wie Bestätigen, Zurück,
Start, Schultertasten und Steuerkreuz. Sie speichert keine feste Hardware-ID.
Dadurch darf ein Controller ausgetauscht oder neu verbunden werden, solange BO3
ihn wieder dem richtigen lokalen Spieler-Slot zuordnet.

Unterstützte Zielkonfigurationen:

| Spieler 1 | Spieler 2 | Ziel |
| --- | --- | --- |
| Tastatur/Maus | Xbox-360-Controller | vollständig |
| Tastatur/Maus | PS4-/PS5-Controller über Steam Input | vollständig |
| Xbox-Controller | Xbox-Controller | vollständig |
| Xbox-Controller | PS4-/PS5-Controller über Steam Input | vollständig |
| PS4-/PS5-Controller über Steam Input | Xbox-Controller | vollständig |
| PS4-/PS5-Controller über Steam Input | PS4-/PS5-Controller über Steam Input | vollständig |

Controller, die Windows beziehungsweise Steam als XInput-kompatibles Gamepad
bereitstellt, sollen ebenfalls funktionieren. Für unbekannte DirectInput-Geräte
kann Steam Input oder eine XInput-Umsetzung erforderlich sein.

## Robustheitsanforderungen

- Menüfokus wird pro lokalem Spieler geführt; Eingaben von Spieler 1 dürfen das
  Gastmenü nicht bewegen und umgekehrt.
- Ein Gerätewechsel darf die gespeicherten Klassen nicht löschen.
- Nach Trennen und erneutem Verbinden eines Controllers muss die Bedienung ohne
  Neustart der Mod wiederherstellbar sein.
- Die Oberfläche verwendet neutrale Aktionsnamen oder automatisch passende
  Tastensymbole; die Logik hängt nicht von Xbox-, PlayStation- oder
  Tastaturbeschriftungen ab.
- Das Gastmenü darf Karte, Regeln und Matchstart nicht auslösen.

## Klassenkopie

Der Kopierdialog enthält:

1. Quellklasse von Spieler 1
2. Zielklasse des Gasts
3. Vorschau von Primärwaffe, Sekundärwaffe, Aufsätzen, Extras und Ausrüstung
4. Bestätigung vor dem Überschreiben der Gastklasse

Die Kopie betrifft nur die gewählte Gastklasse. Spezialist und Punkteserien
werden separat verwaltet.

## Benötigte Entwicklungsumgebung

- Steam-Version von Call of Duty: Black Ops III
- Call of Duty: Black Ops III - Mod Tools
- Zugriff auf die mitgelieferten Multiplayer-Skripte und die Script-API-Dokumentation
- Für eine eigene Lobby-Oberfläche voraussichtlich LUI-Unterstützung im Mod-Compiler

Die eigentliche Mod-Struktur und Build-Dateien werden ergänzt, sobald Spiel und
Mod Tools in der Entwicklungsumgebung verfügbar sind.
