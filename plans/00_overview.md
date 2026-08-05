# Populous-TheEnd — Umsetzungs-Gesamtplan (Overview)

Dieses Dokument ist der Einstiegspunkt für alle Umsetzungssitzungen. Die Spezifikation des
Spiels steht in [../CLAUDE.md](../CLAUDE.md) — sie ist maßgeblich für *was* gebaut wird;
dieses Dokument und die Phasenpläne legen fest, *wie* und *in welcher Reihenfolge*.

## Phasen & Status

Nach Abschluss einer Phase: Checkbox abhaken, committen, pushen.

- [x] **Phase 1** — [01_project_terrain_camera.md](01_project_terrain_camera.md): Projektgerüst, verformbares Terrain, RTS-Kamera
- [x] **Phase 2** — [02_units_selection_movement.md](02_units_selection_movement.md): Pathfinding, Unit-Basis, Selektion & Bewegung
- [x] **Phase 3** — [03_buildings_economy_hud.md](03_buildings_economy_hud.md): Gebäude, Wirtschaft (Holz/Hütten/Mana), HUD
- [x] **Phase 4** — [04_ui.md](04_ui.md): Original-nahes UI (Sidebar, Minimap, Zauber-/Bau-Panels)
- [x] **Phase 5** — [05_training_combat_preacher.md](05_training_combat_preacher.md): Training, Rally Points, Kampf, Prediger *(Sub-Phasen 5a–5d, siehe Plandatei)*
- [x] **Phase 6** — [06_shaman_spells.md](06_shaman_spells.md): Schamanin, Reinkarnation, alle 5 Zauber, Panik/Schleuderphysik, Gebäudezerstörung *(überarbeitet 2026-07-06)*
- [x] **Phase 7** — [07_ai_win_conditions.md](07_ai_win_conditions.md): Hauptmenü (Vollbild, Skirmish-Setup), Multi-KI (bis zu 3 KIs / 4 Spieler), Siegbedingungen *(abgeschlossen 2026-07-06)*
- [x] **Phase 7b** — [07b_unit_control_behavior.md](07b_unit_control_behavior.md): Steuerung & Einheitenverhalten (Move/Attack-Split + Hotkey F, Fliehen, Brave-Idle-Aggro, Idle-6er-Gruppen, Warteschlangen, Anti-Stacking, Doppelklick-Selektion) *(abgeschlossen 2026-07-06)*
- [x] **Phase 7c** — [07c_new_spells.md](07c_new_spells.md): Neue Zauber Erdbeben, Vulkan, Feuerregen, Ebene, Absinken (+ Terrain-Integritätsregeln für Gebäude/Einheiten, Lava-/Brandmechanik, Zauberleiste auf 10 Slots, KI-Heuristik) *(abgeschlossen 2026-07-06)*
- [x] **Phase 7d** — [07d_economy_forester.md](07d_economy_forester.md): Wirtschaft — Försterei (4 Arbeiterplätze, Mana-Upkeep, pflanzt Setzlinge), Baum-Ertrag 1/2/3/4 + Setzling-Stufe, randomisiertes Wachstum, brennende Bäume/Holzstapel, Tornado-Baumschaden *(abgeschlossen 2026-07-06; manuelle Prüfung ausstehend)*
- [x] **Phase 7e** — [07e_sprite_directions.md](07e_sprite_directions.md): 8 Sprite-Blickrichtungen (Diagonalen) *(abgeschlossen 2026-07-07; manuelle Optik-Prüfung bestanden, inkl. Diagonal-Deko Krieger/Feuerkrieger/Prediger)*
- [x] **Phase 7g** — [07g_building_assault.md](07g_building_assault.md): Gebäudezerstörung durch Einheiten (Sturmangriff durch den Eingang, Insassen-Auswurf + Sturm-Kampfzyklus, Feuerkrieger-Fernbeschuss, 15/5-Nahkampf-Limits, Gebäude = niedrigste Scan-Priorität, Reinkarnationsplatz nur per Zauber/Katapult zerstörbar) *(abgeschlossen + manuelle Prüfung bestanden 2026-07-07)*
- [x] **Phase 7h** — [07h_watchtower.md](07h_watchtower.md): Wachturm (4 Holz, 2 Besatzungsplätze für Kampfeinheiten/Schamanin; +3 m Reichweite für Fernkampf/Bekehrung/Zauber — Krieger ohne Bonus, nur geschützte Reserve) *(abgeschlossen + manuelle Prüfung bestanden 2026-07-07)*
- [x] **Phase 7f** — [07f_siege_workshop.md](07f_siege_workshop.md): Belagerungswaffe + Werkstatt (Crew-System, Fahrzeug-Navigation, Werkstatt-Produktion) *(abgeschlossen 2026-07-07 — auf Nutzerentscheidung VOR 7g eigenständig umgesetzt: eigenes Siege-Gebäude-Targeting statt 7g-Basis; manuelle Prüfung ausstehend)*
- [x] **Phase 7i** — [07i_balancing_maps_economy.md](07i_balancing_maps_economy.md): Zwischenphase (Balancing/Features VOR 8) — Prediger-Verteilung + Bekehrte-kein-Ziel (Katapult-Ausnahme), Kartenauswahl + 3 neue Karten (2× doppelt groß → variable Terraingröße), Einheiten-Hardcap 1500/Spieler, Hütten billiger/kleiner (12 Holz/40 Platz) + bemannbar mit Wachstumsregler, Feuertempel/Tempel größer & teurer, Mana-Zuwachs als Zahl, höhere Kosten der hohen Zauber *(abgeschlossen 2026-07-07; manuelle Prüfung ausstehend)*
- [ ] **Phase 8** — [08_performance.md](08_performance.md): **Nur Performance.** FPS-Anzeige (über Optionen schaltbar), reproduzierbares Früh-Lag-Szenario (Bergpass, 3 KIs + Spieler, reiner Aufbau < 100/Spieler) als Profiling-Ziel beheben, Bewegung/Kampf skalieren (Ziel 6000, min. 2000 Einheiten), Ausbildung/Holzwirtschaft entlasten. Zauber-Performance vorerst ausgeklammert. *(Balance/Komfort/Feinschliff bewusst nach Phase 9 verschoben)* ⚠️ *(2026-07-12 **weitgehend zurückgerollt**: Wegfindungs-Regression im Langzeittest — Einheiten ignorierten Befehle. Behalten wurden nur Schatten-Umbau, Messwerkzeuge (FPS-/Draw-Call-Anzeige, lagtest, F9-Ausbau, Benchmarks, Pfad-Telemetrie) und der Aufholspiralen-Cap. Details + Täter-Hypothese: PROGRESS.md „Rückabwicklung". Neuanlauf über Phase 8.1.)*
- [x] **Phase 8.2** — [08c_combat_groups_reachability.md](08c_combat_groups_reachability.md): Kampfgruppen nach Original-Vorbild mit **1-gegen-N-Paarungsregeln (Nutzer-Vorgabe 2026-07-12)**: Normalfall 1v1; Überzahl verteilt sich auf bestehende Kämpfe bis max. 1v3; weitere Überzahl wartet in der zweiten Reihe; Nachzügler der unterlegenen Seite ziehen Angreifer aus vollen Gruppen ab (1v3 → 1v2 + 1v1); Wartende füllen Slots jederzeit; **nie 2v2/2v4** (immer in 1-gegen-N aufteilen). Dazu Gruppen-Mindestabstand statt „Ballbildung", Scan-Fixes gegen „alle stehen rum"/Nord-Drift, **Kampf-Performance-Optimierung** (Benchmark Debugschlacht: 60 FPS vor Kontakt → 12 FPS im Nah-+Fernkampf ohne Zauber; headless: units-Phase ~37 ms/Tick bei combat 2000) + Bergpass-KI-Fixes (keine Gebäude auf unerreichbaren Plateaus, keine Krieger-Trauben am Bergsockel). *(Nutzertest 2026-07-12: Wegpunkt-Bug nach Rollback bestätigt weg)* *(abgeschlossen 2026-07-12: CombatGroup-System (1-gegen-N, Flip/Pull/zweite Reihe) + Gruppen-Mindestabstand, Gegner-Scan ohne Freundes-Cap/NW-Bias (Nord-Drift −35 m → ~−4 m, Melee-Quote ~25 % → 50-66 %), Kampf headless: combat 2000 Ø 26,5 → 15,6 ms (units 19,5 → 9,6 ms), Partial-Paths für Attack-Move, Unreachable-Target-Bann, KI-Plot-Erreichbarkeits-Gate + Session-Cache; Suite 1591 grün, lagtest 2500 Frames sauber; manuelle Prüfung (Debugschlacht-FPS/-Optik, Bergpass lang) durch Nutzer ausstehend — Details PROGRESS.md)*
- [x] **Phase 8.1** — [08b_parallelization.md](08b_parallelization.md): Performance-Neuanlauf über **Parallelisierung (Multi-Core)**: Stufe A = Pfad-Worker-Thread (eigene A*-Grid-Klone, FIFO-Grid-Deltas, Ergebnis-Queue — beseitigt Wegfindungs-Spikes UND die Rückstau-Bug-Klasse strukturell), Stufe B = Separation-Fan-out via WorkerThreadPool (messgesteuert), plus Langzeit-Wächtertests gegen die Phase-8-Regression (Hypothese in PROGRESS.md „Rückabwicklung"). **Nutzer-Vorgabe: akkurate 30-Hz-Berechnung — keine Reduktion der Sim-Frequenz.** Der alte 20-Hz-Plan [08a_sim_20hz_interpolation.md](08a_sim_20hz_interpolation.md) ist **verworfen**; Render-/Physik-Thread-Settings sind nach Recherche ebenfalls verworfen (Begründung in 08b). *(abgeschlossen 2026-07-12: **Stufe A umgesetzt** — PathWorker-Thread, NavGrid-Deltas, UnitManager-Async-Integration, A/B-Schalter, 17 neue Tests + Regression-Wächter, Suite 1509 grün, Langzeit-lagtest 2500 Frames sauber. **Stufe B gemessen und laut Plan-Kriterium VERWORFEN** — Gewinn 0,6–3,4 ms/Tick < 4-ms-Schwelle, O(n)-GDScript-Snapshot als strukturelles Limit; Implementierung konserviert in Commit `305f73a`, Begründung + Lehren in PROGRESS.md. Nutzertest 2026-07-12 auf zwei Rechnern bestätigt: Bauphase ohne Lags; verbleibender FPS-Einbruch im Massenkampf ist Gegenstand von Phase 8.2.)*
- [x] **Phase 8.d (Stufe C1)** — [08d_perf_soa_stufe_c.md](08d_perf_soa_stufe_c.md): **Kampf-Performance Stufe C (data-oriented / SoA)** — Ziel Debugschlacht ≥ 30 FPS. *(2026-07-20: **Leichen-Early-out umgesetzt**; Chase-A\*-Async / Sub-Tick-Guards / ATTACK-Drossel / Render-Slicing **gemessen & verworfen**. 2026-07-22, Tag 0.9.5: **C1 umgesetzt** — SoA-Arrays autoritativ (`soa_pos` als ein `PackedVector3Array` + Flags), Doppelschreiben an allen Writer-Sites, Dictionary-Hash → CSR-Bucket-Grid, Separation/Scans als Array-Kernels. Benchmark-A/B: Kampf-Fenster **−24…−28 %** (krieger 27,3→20,1 ms, feuerkrieger 32,2→23,2 ms, prediger 35,2→26,6 ms), Suite 2223/2223 grün. **Offen:** In-Game-FPS-Test Debugschlacht (2026-07-22 bestätigt: ~50 FPS); **C2** (Kampf-Kernels) nur falls das 30-FPS-Ziel in-game noch verfehlt wird — Details PROGRESS.md.)*
- [ ] **Phase 8.e** — [08e_perf_combat_kernels_stufe_c2.md](08e_perf_combat_kernels_stufe_c2.md): **Kampf-Kernels data-oriented (Stufe C2)** — Ziel **Stresstest ≥ 30 FPS** (Ist ~10; Peak-Sim-Tick ~58 ms, davon warrior/firewarrior-ATTACK 30 ms + MOVE 6 ms = Objekt-Tick-Bulk). *(2026-07-22: Mess-Harness `benchmark_stress` + `diag_stress_*` gebaut; Scan-Masken/Prediger-Query/Spawn-Rebuild umgesetzt (Idle-Phase −19 %, Prediger-Listen-Loch >30 ms/Tick gestopft).)* *(2026-07-23: **C2.1–C2.4 umgesetzt** — soa_target-Generation-Handles, Hold-Kernels für Melee-Stand/Feuer-Stand/Marsch/Kampf-Anmarsch + Zusatz-Kernels Waiter/Leichen/Panik/Knockback-Decay; gehaltene Einheiten überspringen ihren Objekt-Tick komplett. Peak-Block **59,1 → 46,6 ms (−21 %)**, Marschphase −33 %; Suite 2697 grün ×3, benchmark_mass ohne Regression. Nutzertest: **15–20 FPS in-game** (vorher ~10).)* *(2026-07-23 **Fortsetzung „C3"**: Block-Scan-Cache mit Density-Gate + Index-/Array-Scoring der Scans, Direct-Step-Chase-Hold über flache Walkability-Map, Combat-Group-Prune gestaffelt, Prediger `_claimed_by_peer` O(1) + CAST-Stand-Hold. Peak **~44 ms (gesamt −25 % zur C2-Baseline)**, benchmark_mass im Selben-Tages-A/B überall besser (combat 4000 −24 %, prediger-Schlacht −21 %); Suite 2697 grün ×3. **30-FPS-Ziel weiter offen** — Restposten + Ideen (Thread-Fan-out, GDExtension) im Plan; In-Game-FPS-Test durch Nutzer ausstehend.)*
- [ ] **Bugfix-Backlog** — [bugs_backlog.md](bugs_backlog.md): offene Bugs aus Nutzertests (~~UI-Skalierung 1080p/1440p + Auflösungs-Option~~ *(behoben 2026-07-18)*, unfertige Gebäude durch Einheiten zerstörbar, Holzsuche nach Laufweg statt Luftlinie) *(gesammelt 2026-07-13; Behebung vor/zu Beginn von Phase 9)*
- [ ] **Phase 9** — [09_comfort_balance_polish.md](09_comfort_balance_polish.md): Bedienkomfort (Kontrollgruppen, HUD-Ausbau), `balance.gd` (zentrale Konstanten), Balancing-Pass, Feinschliff (Sound-Hooks/Effekte), Testsuite-Kantenfälle, README *(aus der alten Phase 8 herausgelöst)*
- [x] **Phase 10a** — [10a_water_animations_drowning.md](10a_water_animations_drowning.md): Undurchsichtiges Populous-Wasser, neue Animationen `airborne`/`drown`, echte Ertrink-Mechanik (Einheiten stoppen nicht mehr an der Wasserkante), 2D-Feuereffekt der Feuerramme, Politur des Gebäude-Versinkens *(umgesetzt 2026-08-02: Suite 2977 grün, Ladecheck sauber. **Manuelle Prüfung durch den Nutzer am 2026-08-05 bestanden** („Ertrinken klappt") — Details PROGRESS.md)*
- [x] **Phase 10b** — [10b_sound_priority_spell_voices.md](10b_sound_priority_spell_voices.md): Zauberformel der Schamanin beim Cast-Beginn + Effektsound beim Einschlag (Cast-Zeit 1,0 s), Sound-Prioritätensystem (1 Zauberformeln/Schamanentod, 2 Fahrzeug-/Zeppelintode, 3 Rest) inkl. Behebung des Slot-Verwurf-Bugs im AudioManager *(umgesetzt 2026-08-03: Suite 3068 grün, Ladecheck sauber. **Manuelle Prüfung durch den Nutzer am 2026-08-05 bestanden** — mit der bekannten Einschränkung, dass `assets\` **keine** Audiodateien enthält: geprüft ist damit das Prioritäts-/Slot-Verhalten, nicht der Klang. Sobald echte Sounds dazukommen, ist ein Hör-Test nachzuholen — Details PROGRESS.md)*
- [x] **Phase 10c** — [10c_lava_knockback_lift.md](10c_lava_knockback_lift.md): Lava rot, zäh, geländefolgend (gemeinsames Modell `LavaCommon`, Lebensdauer in `Balance`, Vulkan 4 → 2 Stöße, Erdbeben-Lavateppich an der oberen Bruchkante) mit verbindlicher Perf-Abnahme; Rückstoß-/Anhebe-System für Feuerball, Feuerregen, Blitz und Feuerkrieger *(**abgeschlossen 2026-08-03**, Suite 3229 grün, Ladecheck sauber, manuelle Prüfung durch den Nutzer bestanden. Umfang wuchs über 7 Nachträge aus Nutzertests: Flughöhen-Deckel `LIFT_MAX_HEIGHT` 8 m + Seitwärtsübertrag, Luftbonus des Feuerkriegers 2× → +20 %, **Ragdoll** für in der Luft tödlich Getroffene (`Unit.doomed`), Feuerball-Beschleunigung gegen Luftziele, **Weltgrenze als unsichtbare Mauer** mit Rückprall, Cast-Immunität der Schamanin (nur Tod/Wirbelsturm brechen sie), **neues Zauber-Aufladesystem** (parallel statt Round-Robin, per Rechtsklick abschaltbar, kein Mana-Banking, Beten entfällt), Lava-Clipping und Erdbeben-Verlauf korrigiert, Zustands-Overlays ohne Schatten. **Perf:** Lava-Code isoliert **44 % billiger** (neuer `tests/benchmark_lava.gd`), Stresstest im verschränkten A/B auf Parität bei **57 722 statt 65 237 Pfaden** — Details und Messmethodik in PROGRESS.md)*
- [x] **Phase 10d** — [10d_buildings_win_conditions_ui.md](10d_buildings_win_conditions_ui.md): Siegbedingungen (Schamanenkreis unverwundbar + Selbstzerstörung, Ausscheiden des Stammes), Gebäudeabriss per `Entf` (100 %/75 % Erstattung), Bauverfall nach 2 min, Erreichbarkeits-Gate für Bauarbeiter, Bau mit selektierten Braves, UI-Bugfixes (Angriffs-Cursor, bekehrte Einheiten) *(umgesetzt 2026-08-04: Suite 3273 grün und wieder deterministisch, Ladecheck sauber, `benchmark_earlygame` ohne Insel-Regress. Nutzerentscheidungen: Hütten-Klausel in der Niederlage entfällt (0 Einheiten = besiegt), Abriss endgültig und über den vorhandenen — beim Abriss roten — Fortschrittsbalken angezeigt (kein `Label3D` im Projekt), Sofort-Abriss bleibt bei `build_progress == 0`. Nebenbei: Suite-Drift in `test_tree_types` behoben. **Manuelle Prüfung durch den Nutzer am 2026-08-04 bestanden** — Details PROGRESS.md)*
- [x] **Phase 10e** — [10e_wood_area_ai_overhaul.md](10e_wood_area_ai_overhaul.md): Holzfäll-Rechteck für Braves (`B`, `Shift+B` = alle Hütten) inkl. weißem Bestätigungs-Blinken um beauftragte Bäume, und KI-Überarbeitung (Tick-Cache, aktive Holzlogistik mit Fäll-Trupps und vorgeschobenen Lagern, Bauplatz-Abstände/Ausrichtung, mehr Prediger, skalierende Fahrzeuglimits, Spätspiel-Skalierung) *(umgesetzt 2026-08-04 in zwei Commits, Suite 3438 grün, Ladecheck sauber. Vier verifizierte Planabweichungen: **A1** `claim_area_tree` sucht vom Walker statt vom Flächenmittelpunkt (sonst tötet das Gehbudget `radius * PATH_RADIUS_FACTOR` jeden Auftrag auf einen entfernten Hain), **A2** `Shift+B` braucht `exact_match` + `InputSettings._SHIFT_ACTIONS` (sonst matcht plain B beide Actions und „Zurücksetzen" zerstört die Belegung), **A3** der vorgezogene Wohnraumdruck-Zweig braucht `housing_capacity > 0` (Baustellen zählen nicht → die KI hätte nur noch Hütten gebaut), **A4** Armee-Mix 40/30/30 braucht einen Tiebreak (`sort_custom` ist nicht stabil). Zusätzlich mussten die skalierenden Förstereien hinter den Wohnraum, sonst hungern sie ihn aus. Nutzerentscheidung: `TRIBE_MAX_UNITS` bleibt 1000, CLAUDE.md §4 korrigiert. **Manuelle Prüfung durch den Nutzer ausstehend** — Details PROGRESS.md)*

- [x] **Phase 10f** — [10f_hut_upgrades.md](10f_hut_upgrades.md): Hüttenüberarbeitung — kleinere, billigere Hütte (8 Holz, 10 Plätze, 2 Arbeiter) mit **vier Ausbaustufen bis zum Wohnpalast** (10/18/26/34/45 Plätze, 2–6 Arbeiter, je 5 Holz). Timer macht ein Upgrade fällig, die eigene Besatzung holt Holz und baut aus (produziert dabei nichts), stammweite Ausbau-Sperre im UI, KI-Schwellwerte mitgezogen *(umgesetzt 2026-08-04, Suite 3546 grün, Ladecheck sauber. Nutzerentscheidungen: nur die eigene Besatzung baut aus (+ 2-min-Abbruch mit Erstattung, kein Recruiter), der Pause-Knopf sperrt den Ausbau pro Hütte, reiner Timer als Auslöser. Fünf vom Plan nicht genannte Bruchstellen mit angefasst (`Brave._job_active`/`_job_wants_wood`, eigener Ausbau-Absorb, Balken- und Pip-Cache) plus ein neuer `_rebuild_visuals()`-Einsprung. Im Test gefunden und behoben: Abbruch/Neustart-Schleife des Stillstands-Abbruchs (`cancel_upgrade(restart_delay)`). **Gemessen:** KI-Bevölkerung bei t=150 s 242 → 153 (gewollt), Bauplatzsuche −56 % Zellen, aber `best_tree` 4,4 × (billige Bucket-Lookups, ~6 ms/s je Stamm). **Manuelle Prüfung durch den Nutzer ausstehend** — Details PROGRESS.md)*

- [x] **Phase 10g** — [10g_ai_logistics.md](10g_ai_logistics.md): KI-Logistik in **sieben** Teilen, alle aus Nutzertests. **(6)** Reinkarnationsplatz ist kein Angriffsziel mehr (`is_attackable`, sieben ungeprüfte Zielpfade); **(7)** Bauordnung — Wohnraum und Ausbildung **vor** Werkstätten, Lagerzahl aus dem **Bravestrom**, Hütten-Rally-Points auf die Ausbildungszentren; **(1)** aktive Bauarbeiter-Zuweisung mit Budget (`order_build` wurde nie gerufen) + Versorgungs-Tor; **(5)** Arena-Enge statt fixem `DEFEND_RADIUS` (Insel/4 Stämme: Nachbarbasis 36 Zellen ⇒ Dauerbedrohung) + zwei Baumuster; **(2)** Erreichbarkeit als *eine* Wahrheit (`Building.approach_cell_for`, Inselvergleich statt A\*, Bann mit Ablauf, Nachkontrolle); **(3)** Fahrzeuge werden bemannt (Militär zuerst), Werkstattausgang wird frei; **(4)** gezielter Holznachschub + Regale im Absorptionsradius der Werkstätten *(umgesetzt 2026-08-05 in sieben Commits, Suite 3809 grün, Ladecheck sauber. Sechs Fehler fand erst die Messung — u. a. der Wohnraumdeckel im Bravestrom, eine Diagnose ohne `tick_units` und ein falsch-grüner Test. Gemessen: Miliz-Befehle 61 → 2, Fahrzeuge 3 → 8-12, Lager 1/1/1 → 2/1/2. **Manuelle Prüfung ausstehend** — Details PROGRESS.md)*

- [x] **Phase 10h** — [10h_wood_logistics_expansion.md](10h_wood_logistics_expansion.md): Holzlogistik aus dem Nutzertest — **(1)** neues Trageverhalten für Spieler *und* KI (Rechtsklick auf einen Stapel = aufnehmen und **halten**, zweiter Rechtsklick legt ab; `BRAVE_CARRY_HOLD_TIMEOUT` 30 s, Nahkampf/Tod lassen sofort fallen), **(1b)** Baukosten gesenkt (Hütte 7, Ausbaustufe 4, Feuertempel 18, Werkstätten 12/10), **(2)** Holzregale an den Hütten als Ausbau-Depots, **(3)** mehr Fäll-Trupps (9/6 statt 12/4) und Ablieferung nach **offenem Bedarf** statt nach Nähe, **(4→)** Bauplatz geht nie aus, **(5)** 20 % mehr Startholz auf kleinen Karten *(umgesetzt 2026-08-05 in sechs Commits, Suite 3874 grün, Ladecheck sauber. Die offene Nutzerfrage „Just-in-time oder Holzlager?" wurde **am Code entschieden**: `_tick_upgrade_absorb` holt sich Holz per `take_from_radius` selbst, ein Regal finanziert jeden Ausbau mit **null KI-Befehlen** — Regale sind die Standardmechanik, JIT bleibt Notfallpfad. **Teil 4 (breitere Expansion) entfiel auf Nutzeransage** und wurde ersetzt: eine Sonde zeigte, dass die KI stehenbleiben kann, aber nicht wegen vollem Bauplatz — `_find_supplied_plot` verlangte Bäume ohne Rückfallebene (mit Bäumen `(47, 47)`, abgeholzt `(-1, -1)`). Gemessen: unausgebaute Hütten 10/18 → 0, Holz in der Wirtschaft 6 → 109 bei 3,7 % frei liegend, pop 452 → 499. **Manuelle Prüfung ausstehend** — Details PROGRESS.md)*
- [ ] **Phase 10i** — [10i_construction_bugfix_combat_balance.md](10i_construction_bugfix_combat_balance.md): Zwei Bugs aus dem Nutzertest + drei Balance-Mechaniken. **(F1–F7)** Baustellen, an denen nichts passiert — Ursache am Code belegt: `delivery_point()` ist **nicht persistiert** und springt (Ringsuche nimmt die *erste* Zelle in Rasterordnung), womit Holzbuchung, `wood_incoming`, Lieferziel, Erstattung *und* `approach_island` gegeneinander laufen → endlose Holzschleife (der „riesige Stapel"), `progress_cap` bleibt 0, Arbeiter hämmern ins Leere, `approach_island == -1` legt Rekrutierung **und** manuelle Zuweisung still. Dazu Eingangs-Planierzelle optional, Anlaufpunkt-Prüfung in `can_place_at` (nutzt das mit 10g extrahierte `approach_cell_for`), Fluchtweg für eingeschlossene Braves, Planierkante abflachen, Bauverfall härten. **(F8)** `State.TRAIN` fehlt in **beiden** `_anim_base()` → Braves laufen in der **Idle**-Animation zum Trainingslager. **(Balance)** Kämpfende feindliche Schamanin **stört die Predigt** (6 m — Gegenmittel gegen die im Balance-Labor belegte Prediger-Dominanz: 20 Prediger bekehren zeitgleiche 33 Krieger verlustfrei), Feuerkrieger-Feuerball erhält **Flächenschaden** (2 m, 50 %, nur Feinde, kein Rückstoß — sie teilen 36 % des Pools aus und töten fast nichts), **Anhebe-Chance skaliert invers mit den HP** (4 % → 12 %), Balance-Labor besetzt Luftschiffe endlich mit Feuerkriegern *(Plan 2026-08-05; der frühere Luftschiff-Befund „0 HP Schaden" war ungültig — gemessen wurden brave-besetzte, also unbewaffnete Zeppeline)*
- [ ] **Phase 10j** — [10j_disc_world.md](10j_disc_world.md): **Scheibenwelt im Weltall** — alle Karten rund, Sternenhimmel statt flacher Hintergrundfarbe, über den Rand Geschleuderte stürzen ins All und sterben **lautlos offscreen** (Ausnahme Schamanin: hörbar, Mana-Bonus, Respawn), Wasserfall am Rand wo Wasser liegt (nackte Felskante sonst). Hebel ist eine Scheibenmaske in `TerrainData.is_walkable()` — über `NavGrid.update_region()` als einzigen Solidity-Writer zieht das A-Stern, PathWorker, Inseln, Baum-/Einheiten-Spawns und `can_place_at` automatisch mit. **Löst den Widerspruch zu `95b0e73` auf:** die unsichtbare Mauer fällt weg, weil der eigentliche Bug war, dass `get_height()` draußen die Randhöhe fortsetzt — es gibt künftig einfach keinen Boden mehr. **Blocker:** die Startanker von Seenland und Plateau liegen in den Ecken, also außerhalb der Scheibe — drei der vier Karten brauchen echten Neuentwurf *(Plan 2026-08-05)*

Die Phasen sind **strikt sequenziell** — jede baut auf den Artefakten der vorherigen auf.
Jede Phase endet mit einem **lauffähigen, manuell spielbaren Zwischenstand** und
**grünen Headless-Tests**.

## Arbeitsanweisung pro Sitzung

1. Diese Datei + **[PROGRESS.md](PROGRESS.md)** (Ist-Stand inkl. Extras/Erkenntnissen der
   bisherigen Phasen) + den Phasenplan der nächsten offenen Phase lesen.
2. Phase umsetzen (Deliverables + Umsetzungsschritte des Phasenplans).
3. Nach **jeder** neuen/geänderten Skriptdatei: Syntax-Check (`--check-only`), nach neuen
   Dateien: `--headless --import` (wegen `.uid`-Erzeugung, siehe Risiken).
4. Testsuite headless ausführen — muss mit Exit-Code 0 enden.
5. Projekt-Ladecheck `--headless --quit` — Output muss frei von Fehlern sein.
6. Manuelle Prüfschritte des Phasenplans per Spielstart durchführen (bzw. den Nutzer
   bitten, wenn Interaktion nötig ist, die headless nicht prüfbar ist).
7. **[PROGRESS.md](PROGRESS.md) ergänzen:** Gebaut (Dateien + Kern-APIs), Extras/
   Abweichungen vom Plan, Erkenntnisse/Stolpersteine, Verifikationsstand.
8. Checkbox oben abhaken, committen, pushen:
   `git add -A && git commit -m "Phase N: <Titel>" && git push`
   (Repo ist eingerichtet: `main` → `origin/main`, SSH-Alias `github-privat`,
   lokale Commit-Identität nicht ändern, nie `--global`.)

## Verifikations-Befehle

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'

# Nach dem Anlegen neuer Dateien (erzeugt .uid-Dateien, aktualisiert Import-Cache):
& $GODOT --path D:\game\Populous-TheEnd --headless --import

# Syntax-Check einer einzelnen Datei (prüft NUR Einzeldatei-Syntax!):
& $GODOT --path D:\game\Populous-TheEnd --headless --check-only --script <pfad>.gd

# Testsuite (Exit-Code 0 = grün, 1 = Fehlschlag):
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd

# Projekt-Ladecheck (fängt class_name-/Szenen-Referenzfehler, die --check-only nicht sieht):
& $GODOT --path D:\game\Populous-TheEnd --headless --quit

# Spiel starten (manuelle Prüfung):
& $GODOT --path D:\game\Populous-TheEnd
```

## Architektur-Kernentscheidungen (verbindlich für alle Phasen)

### 1. Terrain: Heightmap-Datenmodell als Single Source of Truth
- `TerrainData` (RefCounted, `scripts/core/terrain_data.gd`): `PackedFloat32Array`-Heightmap,
  **128×128 Zellen, 1.0 Weltmeter pro Zelle** (129×129 Vertices). Mesh, Kollision und
  Navigation werden daraus abgeleitet.
- API: `get_height(world_x, world_z) -> float` (bilineare Interpolation — zentral für
  Y-Snapping von Einheiten/Gebäuden, kein Raycast), `raise_area(center, radius, amount)
  -> Rect2i` (Smoothstep-Falloff, gibt geändertes Zellrechteck für partielle Updates
  zurück), `is_walkable(cell) -> bool` (über Wasserlinie `sea_level` + Hangneigung unter
  Schwellwert).
- Mesh: **chunked ArrayMesh** (Chunks à 16×16 Zellen als eigene `MeshInstance3D`), gebaut
  direkt über `ArrayMesh.add_surface_from_arrays()` (kein SurfaceTool). Bei Verformung nur
  die vom `Rect2i` berührten Chunks neu bauen. Vertex-Farben nach Höhe (Sand/Gras/Fels).
- Kollision: **ein** `StaticBody3D` + `HeightMapShape3D`; nach Verformung `shape.map_data`
  neu zuweisen. Nur für Maus-Raycasts (Klickziel, Platzierung, Zauberziel) — Einheiten
  laufen ohne Physik.

### 2. Navigation: AStarGrid2D, KEIN NavMesh
- `NavGrid` (`scripts/core/nav_grid.gd`) kapselt `AStarGrid2D`:
  `find_path(from: Vector3, to: Vector3) -> PackedVector3Array`,
  `update_region(rect: Rect2i)`, `fill_solid_region()` für Gebäude-Footprints.
- Nach `raise_area()` genügt `set_point_solid()` für die betroffenen Zellen — sofort
  wirksam, kein Bake. Diagonalen: `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`. Y der Pfadpunkte
  aus `TerrainData.get_height()`.
- **Begründung:** NavigationRegion3D-Re-Bake nach jeder Landbridge kostet hunderte ms,
  läuft asynchron und NavigationAgent3D skaliert schlecht auf 200+ Einheiten. Das Grid
  macht die Landbridge trivial und ist headless deterministisch testbar.

### 3. Einheiten: Node3D ohne Physik
- `Unit` (class_name, `scripts/units/unit.gd`) extends **Node3D**. Bewegung: Pfad per
  `move_toward()` abschreiten, Y jeden Frame aus `TerrainData.get_height()`.
- Kein CharacterBody3D, kein NavigationAgent3D, kein Physik-Body pro Einheit.
- Zielsuche/weiche Separation über **Spatial-Hash** (`UnitManager`,
  `Dictionary[Vector2i, Array]`), Zielsuche per Timer alle 0.2–0.3 s mit Zufalls-Offset
  gestaffelt — nie pro Frame, nie O(n²).
- Visuals: Kind-`AnimatedSprite3D`, `billboard = BILLBOARD_ENABLED`, `shaded = false`,
  `alpha_cut = ALPHA_CUT_DISCARD` (gegen Transparenz-Sortierflackern). Stammfarbe via
  `modulate`. Animationen: Idle, Walk, Attack, Cast (Cast nur Schamanin/Prediger).
- State-Machine als `enum State` + `match` in `_tick()` — Logik testbar ohne Szenenbaum.

### 4. Spielzustand & Symmetrie
- Autoloads: `GameState` (Tribes, Match-Phase, Sieg/Niederlage-Signale) und `Events`
  (reiner Signal-Bus: `unit_died`, `building_destroyed`, `wood_changed`, `mana_changed`).
  Keine weiteren Autoloads.
- `Tribe` (`scripts/core/tribe.gd`): id, color, wood, mana, units, buildings,
  population/housing, shaman. **Spieler und KI sind identische Tribe-Instanzen.**
- **`TribeCommands` (`scripts/core/tribe_commands.gd`) ist die EINZIGE Mutations-API:**
  `place_building()`, `order_move()`, `order_train()`, `cast_spell()` — alle mit
  Kosten-/Gültigkeitsprüfung. UI ruft sie auf, KI ruft sie auf. Direkte Mutationen wie
  `tribe.wood += x` außerhalb von TribeCommands sind verboten (Ausnahme: TribeCommands
  selbst und Tests).
- Mana-Tick zentral: `Tribe.tick(delta)`:
  `mana += (population * BASE_RATE + praying_braves * PRAY_BONUS) * delta`.
- **Zauber-Ladungssystem (wie Original):** Mana wird automatisch in Zauber-Ladungen
  umgewandelt (je Zauber `charge_cost`/`max_charges`); Casts verbrauchen Ladungen,
  kein separater Cooldown. Details in Phase 6, Anzeige (Pips) in Phase 4.

### 5. Selektion & Input
- Terrain-/Gebäudeklick: Raycast (`project_ray_origin/normal` →
  `direct_space_state.intersect_ray()`), eigene Collision-Layer.
- Einheiten-Selektion **screen-space**: Box-Rect aus Drag, pro eigener Einheit
  `camera.unproject_position()` + `rect.has_point()` (+ `is_position_behind()`-Guard).
  Einzelklick = nächste Einheit im Pixelradius. Keine Physik-Shapes pro Einheit.
- Rechtsklick: Bewegung via `TribeCommands.order_move()`; Shift+Rechtsklick = Wegpunkt
  anhängen; Rechtsklick bei selektiertem Gebäude = `rally_point` setzen (Property der
  `Building`-Basisklasse → gilt automatisch für ALLE Gebäude).

### 6. Testbarkeits-Regel (wichtig!)
Spiellogik (Timer, Spawns, Mana, Kampf, KI) in **`tick(delta)`-Methoden** implementieren,
die von `_process`/`_physics_process` aufgerufen werden — Tests rufen `tick()` manuell mit
künstlichen Deltas auf. Keine Godot-`Timer`-Nodes für Kernlogik.

### 7. Placeholder-Assets: rein prozedural
- Einheiten-Sprites: `PlaceholderSprites.make_frames(color) -> SpriteFrames` — Frames per
  `Image.create()` + `fill_rect()`-Pixelmuster, `ImageTexture.create_from_image()`.
  Einheitentyp = Silhouette, Stamm = `modulate` (Blau = Spieler, Rot = KI).
- Gebäude: BoxMesh/CylinderMesh/PrismMesh + `StandardMaterial3D.albedo_color`
  (Hütte = brauner Prism, Lager = graue Box, Tempel = weißer Zylinder,
  Reinkarnationsplatz = flacher Ring); Stammfarben-Fahne als kleines Zweitmesh.
- Bäume: Zylinder-Stamm + Kegel (`CylinderMesh` mit `top_radius = 0`).
- Alles in `_ready()` erzeugt — **keine externen Asset-Dateien**, `assets\` bleibt leer.
- **Auch die UI-Optik ist prozedural:** Gold/Braun-StyleBoxes + generierte
  Pixel-Art-Icons in `scripts/ui/ui_theme.gd` (Phase 4) — echte Grafiken können
  später dieselben Slots ersetzen.
- UI-Sprache Deutsch, Code/Identifier Englisch, typisiertes GDScript (siehe CLAUDE.md §8).

## Test-Strategie

- **Eigener minimaler Runner, kein GUT-Addon:** `tests/run_tests.gd` extends `SceneTree`
  (Pflicht für `-s`). In `_initialize()`: alle `res://tests/test_*.gd` laden, pro
  Testklasse alle Methoden mit Präfix `test_` per Reflection (`get_method_list()`)
  aufrufen, Ergebnis auf stdout, `quit(0)` bei Erfolg / `quit(1)` bei Fehlschlag.
- `tests/test_base.gd`: Basisklasse mit `check(cond: bool, msg: String)` — sammelt Fehler
  statt hart abzubrechen (`assert()` ist in Release-Builds no-op → nicht verwenden).
- Testklassen extends RefCounted (oder Node, wenn Szenenbaum nötig — dann via
  `root.add_child()` im Runner).
- **Headless testbar:** Terrain-Mathe, NavGrid-Pfade/Region-Updates, Wirtschaft, Mana-Formel,
  Spawn-/Trainings-Timer, Rally-Zuweisung, Kampf-/Schadensrechnung, Konvertierung,
  Zauberkosten/-effekte auf Datenebene, Landbridge-Walkability, KI-State-Übergänge,
  Schamanin-Respawn, Siegbedingung.
- **Nur manuell testbar:** Rendering/Billboards, Kamera-Feel, Box-Select-Optik, HUD-Layout,
  Maus-Raycasts, Partikel.

## Bekannte Godot-4.x-Risiken (bei Umsetzung beachten)

1. **`HeightMapShape3D` ist origin-zentriert** mit festem 1.0-Raster → StaticBody3D um
   `(width/2, 0, depth/2)` versetzen; früh per Testklick-Marker verifizieren, sonst
   „Klicks landen daneben".
2. **`--check-only` prüft nur Einzeldatei-Syntax**, keine projektweiten
   `class_name`-Referenzen → immer zusätzlich `--headless --quit`. Achtung: dabei läuft
   `_ready()` der Hauptszene → Main muss headless-robust sein.
3. **`.uid`-Dateien:** Extern angelegte `.gd`/`.tscn` bekommen erst nach
   `--headless --import` ihre UID; vorher können Szenen-Referenzen brechen. Nach jedem
   Anlegen neuer Dateien einmal importieren; `.uid`-Dateien nie manuell löschen/umbenennen.
4. **Headless = Dummy-RenderingServer:** `Image`/`ImageTexture` funktionieren, alles
   Viewport-/Shader-abhängige nicht. Tests dürfen keine Texturinhalte prüfen;
   Sprite-Erzeugung nur in `_ready()` von Szenen, nicht in testbarer Kernlogik.
5. **200+ Einheiten:** verboten sind per-Frame-`get_nodes_in_group` + Distanzschleifen,
   NavigationAgent3D pro Einheit, Physik-Body pro Einheit. Massen-Pfadberechnungen ggf.
   über Frames verteilen (Queue im NavGrid).
6. **Einheiten ohne Physik laufen durch Gebäude** → Footprints als solid-Zellen im NavGrid;
   nach Blast/Tornado-Würfen Landeposition auf begehbare Zelle clampen.
7. **Skriptete Flugbahnen:** Würfe (Blast/Tornado) als Tween/manuelle Parabel, Einheit
   dabei in Sonder-State ohne Y-Snapping, bei Landung Snap.
8. **Chunk-Rebuild-Hitches:** nie das ganze Terrain neu vernetzen; `Rect2i` aus
   `raise_area()` strikt nutzen. `map_data`-Neuzuweisung einmal pro Verformung (bzw.
   gedrosselt), nicht pro Frame.
9. **KI-Symmetrie:** keine Abkürzungen an TribeCommands vorbei — der Symmetrie-Test in
   Phase 7 prüft das.
10. **API-Drift Godot 4.7:** bei Unsicherheit exakte Signaturen gegen die lokale 4.7-Doku
    prüfen statt älteren Tutorials zu vertrauen.

## Zielstruktur (aus CLAUDE.md §8, wächst über die Phasen)

```
D:\game\Populous-TheEnd\
├── project.godot
├── plans\                 # diese Pläne
├── scenes\                # main, terrain, ui, units, buildings
├── scripts\core|units|buildings|spells|ai|ui
├── tests\                 # run_tests.gd, test_base.gd, test_*.gd
└── assets\                # bleibt leer (prozedurale Placeholder)
```
