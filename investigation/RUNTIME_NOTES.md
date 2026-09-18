# Laufzeituntersuchung 2026-09-15

## Direkte Beobachtungen per Computer Use
- Stock-Hauptmenü vollständig sichtbar nach Start/Ladephase.
- 0.2.2 geladen, gelbe Mod-Kennung sichtbar, Hauptmenü und Offline-Modus funktionsfähig.
- SHA256: alle sechs FF in der VM entsprechen diagnostic-0.2.2; README und alte .zone-Textdateien im installierten Ordner sind Reste früherer Pakete.
- Entwicklungsmod 2: Bootstrap-Kennung sichtbar; rechte Gastkarte in Offline-MP sichtbar.
- Gastkarte zeigt Controller 1 bei aktivem zweitem lokalen Spieler, Beitrittshinweis nach dessen Austritt.
- Entwicklungsmod 3 kompiliert und zum Laufzeittest geladen. Weiteres Testergebnis folgt.

## Technische Erkenntnisse aus lokal extrahierten Originalen
- core_frontend_patch_require.lua eignet sich als Einstieg: Original-Require-Liste plus zusätzliches eigenes Modul. Vollständiges Ersetzen der Lobby ist nicht nötig.
- CoD.Menu.AddButtonCallbackFunction abonniert ButtonBits aller Controller bei anyControllerAllowed.
- CoD.Menu.HandleButtonPress ist der gemeinsame Verteiler vor dem Aufruf des fokussierten Widgets. Root-processEvent allein schützt die Host-Auswahl nicht vor allen Gast-Eingaben.
- CoD.LobbyBase.OpenCAC/OpenScorestreaks/OpenChooseCharacterLoadout akzeptieren einen Controller für den Profilzugriff.
- CoD.GetLocalClientAdjustedNum liefert im Frontend immer 0, sonst Engine.GetLocalClientNum(controller). Hintergrund-/Kamerameldungen verwenden daher einen gemeinsamen Kanal.
- Die Klassen- und Spezialisteneditoren öffnen als Popup/Overlay und belegen weiterhin die gemeinsame Menüebene. Gleichzeitige Halbseiten-Editoren benötigen zusätzliche Arbeit.
- Decompiler-Ausgabe kann unter deutscher Kultur Dezimalkommas enthalten (beispielsweise 0,5 als mehrere Lua-Argumente). Originaldateien nicht ungeprüft als Ersatz kompilieren. DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 beim Auslesen setzen; eine erfolgreiche Dekompilierung beweist keine semantische Gleichheit.
- Entwicklungsbuild mit mod-eigenem zone_source funktioniert; globale Zonen müssen nicht überschrieben werden.

## Noch kein Nachweis
Unabhängige Controllerbedienung der Gasteditoren, Speichern im korrekten Profil, zwei 3D-Figuren, gleichzeitige Halbseiten-Editoren, Klassenkopie, Ingame-Fix.
