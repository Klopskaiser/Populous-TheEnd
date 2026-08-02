# Phase 10a — Wasser, Animationen, Ertrinken, 2D-Feuer

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Präsentations-Block: **undurchsichtiges Populous-Wasser**, zwei neue
Einheiten-Animationen (**airborne** = durch die Luft fliegen, **drown** =
ertrinken), eine echte **Ertrink-Mechanik** (Einheiten stoppen nicht mehr an
der Wasserkante, sondern rollen/fliegen hinein und versinken), sowie ein
**2D-Feuereffekt** für die Feuerramme. Das Versinken zerstörter Gebäude
existiert bereits und wird nur poliert.

## Bestandsaufnahme (vor Umsetzung verifiziert)

- **`cast`-Animation existiert bereits** für Schamanin und Prediger:
  `PlaceholderSprites.CASTER_KINDS` (:48), `_frame_cast` (:694),
  `Unit._anim_base` (:3398), `Shaman._anim_base` (shaman.gd:185). **Kein
  Neubau nötig** — nur eine Regressionsprüfung im Atlas-Test.
- **Gebäude-Versinken existiert bereits:** `Building._begin_sinking` (:1313)
  + `_process` (:1331), `SINK_DURATION 2.0`, `SINK_DEPTH 5.0`, dazu
  `slide_into_water(dir)` (:1305) für geflutete Wracks.
- `THROWN` und `ROLL` rendern heute beide `roll` (unit.gd:3402).
- Ertrinken ist heute `health = 0; _die()` ohne jede Darstellung
  (`Unit.drown()` unit.gd:1760).
- Rückstoß/Rollen werden heute **an der Wasserkante gestoppt**
  (`_tick_knockback` :1450 bricht bei nicht begehbarer Zelle ab,
  `_cliff_drop_ahead` :1485 liefert über Wasser 0, `_end_roll` :1641 snappt auf
  die nächste begehbare Zelle zurück).
- Feuerramme-Flamme = 3 emissive `BoxMesh`-Segmente
  (`FireRam._show_flame_cone` :779, `_tick_visual` :817).

## Dokumentierte Auslegungen

- **Kein neuer `Unit.State`.** Ertrinken ist `State.DEAD` + Flagge
  `_drowning`. Begründung: `State.DEAD` wird an ~200 Stellen geprüft und
  kodiert exakt die gewünschte Semantik (nicht anvisierbar, nicht
  selektierbar, außerhalb der Bevölkerung, von Separation/Scans/KI
  ignoriert); vier bestehende Tests prüfen `state == DEAD` direkt nach
  `drown()`.
- **Wegfindung darf weiterhin NIE ins Wasser routen.** `NavGrid` und
  `TerrainData.is_walkable` bleiben unangetastet. Nur *erzwungene* Bewegung
  (Rückstoß, Rollen, Wurf, Tornado, Klippensturz) überschreitet die
  Wasserkante — und endet dort immer im Ertrinken.
- **Der Meeresboden bleibt als Geometrie erhalten** (wird von `get_height`,
  `HeightMapShape3D`-Kollision und allen Terrainzaubern gebraucht) — er ist
  künftig nur nicht mehr sichtbar.
- **Undurchsichtiges Wasser löst „keine treibende Leiche" geometrisch**: die
  ertrinkende Figur sinkt durch die Wasserfläche und ist danach verdeckt.
  Keine zusätzliche Alpha-Logik im Renderer.
- **Fahrzeuge und Luftschiff bleiben unverändert**: `CrewedVehicle` hat sein
  eigenes `_sinking`, `Airship.drown()` ist ein No-op. Diskriminator ist
  `Unit.renders_as_sprite()`.

## Deliverables

| Bereich | Datei(en) | Inhalt |
|---|---|---|
| **Animationen** | `scripts/ui/placeholder_sprites.gd` | `_anims_for()` (:74) um `airborne` + `drown` für **alle** Kinds erweitern; `_anim_fps()` (:141) `airborne` 5.0 / `drown` 6.0; `_build_frames()` (:169) zwei neue `match`-Zweige — `airborne` 2 Frames (Arme/Beine gespreizt, bewusst **nicht** die Kugelform von `_frame_roll`, damit THROWN und ROLL unterscheidbar bleiben), `drown` 3 Frames (Arme über dem Kopf, wechselseitig winkend, Beine unterhalb y=18 weggelassen); Dekorations-Ausschlussliste (:246) um `drown` erweitern (`airborne` behält Accessoires) |
| **Anim-Auswahl** | `scripts/units/unit.gd` | `_anim_base()` (:3388): `THROWN → &"airborne"`, `ROLL → &"roll"` (Aufsplittung), `DEAD → &"drown"` wenn `_drowning`, sonst `&"dead"` |
| **Wasser** | `scripts/core/terrain.gd`, `shaders/water.gdshader` (neu) | `_ensure_water()` (:91) undurchsichtig; neue Konstanten `COLOR_WATER = Color(0.055, 0.16, 0.40)`, `COLOR_WATER_HIGHLIGHT = Color(0.13, 0.30, 0.58)`, `WATER_SURFACE_LIFT = 0.03`, `COLOR_SHORE = Color(0.62, 0.55, 0.38)`, `SHORE_BAND = 0.9`. Neuer Shader: opaque, zwei `sin()`, keine Textur, keine Vertex-Verschiebung. Texturpfad `assets/textures/terrain/water.png` bleibt als Override (dann `StandardMaterial3D` **ohne** Alpha). Küstensaum gratis über `_color_for_height()` (:132) |
| **Minimap** | `scripts/ui/minimap.gd` | Wasserfarben an `Terrain.COLOR_WATER` angleichen; Tiefenrampe (`height_to_color` :93) **behalten** (Lesbarkeit von Kanälen/Seen; `tests/test_ui_logic.gd:57` hängt daran) |
| **Ertrinken** | `scripts/units/unit.gd`, `scripts/core/balance.gd` | Neue Flagge `_drowning`; gemeinsame Wasserprobe `_is_water_at(x, z)` ersetzt die drei Literalkopien (:1488, :1575, :1852); `drown()` (:1760) mit Pose-Reihenfolge, Auftrieb, `_sync_soa_pos()`, Splash-SFX; drei Leichen-Timing-Helfer; **Kernel-Hold-Guard** in `_tick_dead` (:1393); Freigabe der erzwungenen Bewegung ins Wasser an fünf Stellen (siehe Umsetzungsschritte) |
| **Fahrzeuge** | `scripts/units/crewed_vehicle.gd` | `drown()` (:255): vor `super.drown()` `position.y` auf mindestens `SEA_LEVEL` heben, damit das Wrack sein Absinken sichtbar beginnt statt unsichtbar auf dem Meeresboden |
| **Feuerramme 2D** | `scripts/units/fire_ram.gd`, `scripts/ui/status_fx_renderer.gd` | `StatusFxRenderer` bekommt `static flame_textures()` (analog `UnitRenderer.blob_texture()`); `_show_flame_cone()` (:779) baut **eine** `MultiMeshInstance3D` mit `FLAME_QUADS = 7` aufrechten Billboard-Quads (Material-Rezept aus `StatusFxRenderer`: unshaded, `BILLBOARD_ENABLED`, `TRANSPARENCY_ALPHA_SCISSOR` → bleibt im Opaque-Pass); `_tick_visual()` (:817) marschiert die Quads entlang der Rumpfachse über `FIRE_RANGE`, Größe `FLAME_QUAD_MIN 0.9 → FLAME_QUAD_MAX 1.7`, Hangneigungs-Basis (:835-838) entfällt |
| **Gebäude-Versinken** | `scripts/buildings/building.gd` | *(optional, zuletzt)* `_process` (:1331) Zerstörungszweig: `_mesh_root` kippt über `SINK_TILT 0.14` rad mit langsamem Wippen (`SINK_TILT_HZ 0.8`), bei gleitenden Wracks in Gleitrichtung |
| **Doku** | `assets/README.md` | Animationsliste um `airborne`, `drown` ergänzen (Sheet-Override `assets/units/<kind>/<anim>.png` funktioniert automatisch, weil `UnitSpriteLibrary` über `_anims_for()` iteriert) |
| **Tests** | `tests/test_drowning.gd` (neu), `tests/test_combat.gd`, `tests/test_spells.gd` | siehe unten |

## Neue Balance-Konstanten

```gdscript
# --- Ertrinken ---
## Sekunden, die eine ins Wasser gestürzte Einheit an der Oberfläche zappelt.
const DROWN_FLAIL_DURATION: float = 0.7
## Absink-Dauer danach (danach ist die Leiche weg).
const DROWN_SINK_DURATION: float = 1.1
## Wie tief die Figur beim Zappeln bereits im Wasser steht (m unter SEA_LEVEL).
const DROWN_FLOAT_DEPTH: float = 0.9
## Zusätzliche Absinktiefe (m) — Sprite-Höhe + Tiefen-Bias-Reserve.
const DROWN_SINK_DEPTH: float = 1.9
```

Farb- und Geometriewerte (Wasser, Küstensaum, Flammenquads, Gebäude-Kippung)
bleiben laut Projektkonvention **presentation-lokal** in der jeweiligen
Renderer-/Entity-Klasse (wie `Terrain.COLOR_SAND`, `UnitRenderer.BLOB_COLOR`).

## Umsetzungsschritte

1. **Animationen** (`placeholder_sprites.gd` + `unit._anim_base`) + Atlas-Test.
   Selbstständig, ohne Verhaltensänderung — `THROWN` wechselt lediglich von
   `roll` auf `airborne`.
2. **Wasser** (`terrain.gd`, `shaders/water.gdshader`, `minimap.gd`) —
   danach `--headless --import` (neue Datei!).
3. **Ertrinken, Teil 1** (Flagge, Timing-Helfer, Kernel-Hold-Guard,
   `drown()`) + Tests D3/D4 grün, **bevor** Schritt 4 beginnt.
4. **Ertrinken, Teil 2** — erzwungene Bewegung ins Wasser freigeben:
   - `_tick_knockback` (:1452): im „Zelle nicht begehbar"-Zweig **vor** der
     Klippenprobe: bei Wasser Position übernehmen, Rückstoß beenden, `drown()`.
   - `_tick_roll` (:1574): `drown()` statt `health = 0; _die()`.
   - `_end_roll` (:1641): **erste** Anweisung — bei Wasser `drown()` und
     `return`, damit der `nearest_walkable_cell`-Snap nicht mehr greift.
   - `_cliff_drop_ahead` (:1488): über Wasser den echten Fallabstand
     (`position.y - SEA_LEVEL`) liefern statt 0 — Einheiten können jetzt von
     Küstenklippen ins Meer geschleudert werden.
   - `_tick_thrown` (:1737): Parabel auf `max(ground, SEA_LEVEL)` landen,
     aber die **echte** Bodenhöhe an `_land_from_throw` übergeben (sonst
     springt die Figur für einen Frame auf den Meeresboden).
   An jeder dieser fünf Stellen einen Kommentar setzen: dies kehrt den
   „Overview-Risiko 6"-Kommentar bei unit.gd:1450 bewusst um.
5. **Fahrzeug-Anpassung** (`crewed_vehicle.gd`).
6. **Feuerramme 2D** (`status_fx_renderer.gd`, `fire_ram.gd`) — rein visuell,
   `_apply_flames()` (:632) und alle Balance-Werte bleiben unverändert.
7. *(optional)* **Gebäude-Versinken-Politur**.
8. Verifikation, `assets/README.md`, `PROGRESS.md`, Commit/Push.

## Tests

**Neu `tests/test_drowning.gd`** (Helfer `_flat_terrain`/`_make_world` aus
`tests/test_combat.gd:17-52`, Wasserkarte wie `test_combat.gd:522`):

- `test_knockback_pushes_into_water_and_drowns` — Einheit am Ufer,
  `apply_knockback` seewärts, ticken → `DEAD`, `_drowning`,
  `position.y ≈ SEA_LEVEL - DROWN_FLOAT_DEPTH`, und `position.x` liegt
  **jenseits** der alten Uferzelle (beweist, dass die Klemme weg ist).
- `test_roll_into_water_plays_drown_anim` — zusätzlich
  `anim_base_name == &"drown"`.
- `test_drowning_corpse_sinks_fast_and_expires` — nach
  `DROWN_FLAIL_DURATION` ist `corpse_sink_depth() == 0`; nach zusätzlich
  `DROWN_SINK_DURATION` gleich `DROWN_SINK_DEPTH`; Gesamtdauer
  `< Balance.CORPSE_DURATION`; `corpse_expired` genau einmal.
- `test_drowning_unit_is_never_kernel_held` — **sichert das Hauptrisiko**:
  über einen echten `UnitManager` ticken und in *jeder* Iteration prüfen,
  dass kein Corpse-Hold gesetzt ist und `_corpse_timer` streng wächst.
- `test_pathfinding_never_routes_through_water` — `find_path` über einen
  Kanal schlägt fehl oder enthält keine Zelle `<= SEA_LEVEL`; `order_move`
  endet auf Land.
- `test_end_roll_over_water_does_not_snap_back` — `_end_roll()` über Wasser
  → `DEAD`, `_drowning`, Position unverändert.
- `test_cliff_over_water_launches` — 3-m-Klippe mit Meer am Fuß:
  `_cliff_drop_ahead(dir) >= CLIFF_FALL_MIN_DROP` (vorher 0.0).
- `test_thrown_unit_uses_airborne_anim` — `THROWN` → `&"airborne"`, nach
  Landung an Land → `&"roll"`.
- `test_vehicle_drown_stays_instant` — Feuerramme: `DEAD`,
  `_drowning == false`, `_sinking == true`, `position.y >= SEA_LEVEL`.
- `test_shore_color_is_wet_sand` — reine Mathematik auf
  `Terrain._color_for_height`.

**Erweiterungen:**
- `tests/test_combat.gd::test_strike_anims_in_atlas` (:630) um `airborne`
  (2 Frames) und `drown` (3 Frames) sowie die Prüfung, dass `cast` **nur**
  bei Schamanin/Prediger im Atlas liegt.
- `tests/test_spells.gd:641` und `:1064` (Flutungstode) um
  `check(u._drowning, ...)`.

## Manuelle Prüfung

- Wasseroptik: tiefblau, undurchsichtig, kein sichtbarer Meeresboden, saubere
  Küstenlinie ohne Z-Fighting; nasser Sandsaum sichtbar.
- Einheit per Feuerball/Tornado ins Meer schleudern → Ertrinkanimation,
  Versinken, **keine treibende Leiche**.
- Einheit am Uferhang umwerfen → sie rollt ins Wasser statt an der Kante zu
  stoppen.
- Tornado-Opfer in der Luft zeigen die `airborne`-Pose (nicht mehr `roll`).
- Feuerramme: Flammenkegel als 2D-Feuer, Richtung und Länge weiterhin klar
  erkennbar, Trefferzone unverändert.
- FPS-Vergleich vor/nach der Wasseränderung (sollte nicht kosten, eher
  minimal gewinnen).

## Risiken

1. **Kernel-Corpse-Hold (höchstes Risiko).** `_tick_dead` (:1393) parkt
   Sprite-Leichen im Hold, wodurch der Objekt-Tick komplett übersprungen wird
   — eine ertrinkende Einheit würde ~6 s auf dem Wasser treiben. Guard
   `and not _drowning` + Test `test_drowning_unit_is_never_kernel_held`.
2. **SoA-Desync.** `drown()` und der Rückstoß-Wasserzweig schreiben Position
   außerhalb von `_snap_to_ground` → `_sync_soa_pos()` ist Pflicht (C1-Writer-Audit).
3. **Pose-Reihenfolge.** `_die()` friert die Animation einmalig ein; `_drowning`
   muss **vorher** gesetzt sein.
4. **Balance-Nebenwirkung.** Durch die Klippen-Änderung sterben Einheiten an
   Küsten häufiger. Gewünscht, aber in PROGRESS.md vermerken.
5. **Atlas-Wachstum.** +5 Frames × 8 Ansichten × 5 Kinds = +200 Zellen (+15 %).
   Bei echten 64×96-Sheets ~+3 Atlas-Zeilen — unkritisch bei
   `MAX_ATLAS_WIDTH 4096`, aber die Framezahlen (2 bzw. 3) nicht aufblähen.

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung durch den Nutzer bestanden
- [ ] PROGRESS.md ergänzt, Checkbox 10a in [00_overview.md](00_overview.md) abgehakt
- [ ] Commit/Push
