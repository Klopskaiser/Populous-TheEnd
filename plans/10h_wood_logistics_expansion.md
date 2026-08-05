# Phase 10h — Holzbereitstellung, Trageverhalten, breitere Expansion

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
> **Abhängigkeit:** [Phase 10g](10g_ai_logistics.md) ist abgeschlossen.

## Ziel

Nutzertest nach 10g: „grundsätzlich ist das jetzt besser, aber die Bereitstellung von
Holz ist mangelhaft." Vier Themen plus ein neues Spielerverhalten.

| # | Nutzeraussage | Was daraus folgt |
|---|---|---|
| 1 | „am besten ist es, Leute direkt zum Holz holen zu schicken" | Mehr und größere Fäll-Trupps, früher. |
| 2 | „das Holz in der Nähe der Baustellen haben, dass die Laufwege kurz bleiben" | Holz dorthin, wo gebaut wird — nicht dorthin, wo Bäume stehen. |
| 3 | „es müssen auch Holzlager in der Nähe von Hütten errichtet werden und zumindest immer mal wieder mit 5 Holz bestückt werden, wenn die Hütten noch ausbaubar sind" | Regale an Hütten als **Ausbau-Depots** (10f: 5 Holz je Stufe). |
| 4 | „bisher lagen riesige Stapel einfach rum, teilweise in der Nähe von Werkstätten, obwohl Hütten auch wichtig sind" | Die Ablieferung muss nach **Bedarf** priorisieren, nicht nach Nähe. |
| 5 | „die KI kann auch etwas breitflächiger expandieren, momentan ist das alles sehr eng zusammen … genug Bauplatz beanspruchen, zumindest auf den großen Karten" | Das kompakte Muster aus 10g Teil 5 ist auf **offenen** Karten zu eng. |

## Nutzer-Festlegungen (2026-08-05)

- **Trageverhalten (Spieler und KI):** Rechtsklick auf einen Holzstapel → der Brave
  nimmt ihn auf und **hält** ihn; der **nächste Rechtsklick** bestimmt, wo er ihn
  ablegt. Die automatische Ablieferung („Holz zur Holzstelle bringen") bleibt
  erhalten, gilt künftig aber für die per **`B`-Rechteck** erfassten Stapel.
- **Ablege-Countdown:** hält ein Brave Holz **ohne Befehl** länger als **30 s**,
  lässt er es an Ort und Stelle fallen. Ebenso bei Verwicklung in Nahkampf und beim
  Tod (Letzteres ist bereits vorhanden — `_on_combat_interrupt` / `_stop_all`).
- **KI-Holzverteilung:** Just-in-time ist erlaubt, **wenn** es die Kommandolast nicht
  sprengt; Lager als Hub für größere Bedarfe wären sparsamer. „Schau, was einfacher
  umzusetzen ist und weniger Performance frisst."

### Diese Frage ist entschieden — mit Belegen, nicht nach Gefühl

**Regale gewinnen.** `Building._tick_upgrade_absorb` (ebenso der Reparatur- und der
Baustellen-Absorb) zieht Holz per
`wood_pile_manager.take_from_radius(delivery_point(), ABSORB_RADIUS, need)` ein.

- **Regal an der Hütte: 0 KI-Befehle je Ausbau.** Die Engine absorbiert selbst. Kosten
  einmalig: 1 Holz, 1×1-Grundriss, ein begrenzter Platz-Scan.
- **Just-in-time: 1 Befehl je Trupp plus eine Laufstrecke je Fuhre.** Bei
  `HUT_UPGRADE_DELAY = 90 s`, vier Stufen und bis zu `AI_MAX_HUTS = 60` Hütten wäre das
  ein Dauerstrom von Aufträgen.

Also: **Regale sind die Standardmechanik**, das in 10g Teil 4 gebaute JIT
(`order_supply_wood`, `_tick_supply_runs`) bleibt als **Notfallpfad** für stehende
Baustellen ohne Holzquelle — dort gibt es kein Regal, das helfen könnte, und es ist
schon auf `AI_MAX_SUPPLY_CREWS` und den `AI_WOOD_TICK_INTERVAL` gedrosselt.

---

## Teil 1 — Trageverhalten: aufnehmen und halten

**`scripts/units/brave.gd`**

| Element | Inhalt |
|---|---|
| `carry_hold: bool` (neu) | Gesetzt von `order_pickup`: der Brave liefert **nicht** selbständig ab, sondern wartet auf ein Ziel. |
| `order_pickup(pile)` (geändert) | Setzt `carry_hold = true`. Nach dem Aufnehmen **kein** `Task.DELIVER`, sondern Halten (Idle mit Holz in der Hand). |
| `order_drop_wood(point)` (neu) | Zweiter Rechtsklick: geht zu `point` und legt das Holz dort ab (`wood_pile_manager.deposit`). Zielt der Klick auf ein eigenes Gebäude, wird dessen `delivery_point()` genommen — dann absorbiert es das Holz wie gewohnt. |
| `_tick_carry_hold(delta)` (neu) | **Ablege-Countdown:** `_carry_hold_timer` läuft, solange der Brave ohne Ziel Holz hält; bei `Balance.BRAVE_CARRY_HOLD_TIMEOUT` (30 s) fällt das Holz an Ort und Stelle. |
| `_on_combat_interrupt` / `_on_stumble` / `_stop_all` | Müssen `carry_hold` löschen und das Holz ablegen. Der Sturz-Pfad (`_on_stumble`) macht das schon; für den Nahkampf ist es zu ergänzen. |
| `has_chop_area()`-Pfad | **Unverändert** — die Flächenernte liefert weiter automatisch ab. Das ist genau die Nutzervorgabe. |

**`scripts/core/tribe_commands.gd`**: `order_drop_wood(units, point) -> int`.
`order_pickup` bleibt, verhält sich aber jetzt als „aufnehmen und halten".

**`scripts/ui/selection_manager.gd`**: der Rechtsklick-Dispatcher bekommt einen
Vorrangzweig — sind selektierte Braves **mit Holz in der Hand und `carry_hold`**
dabei, wird der Klick ein `order_drop_wood` statt eines Bewegungsbefehls.
**Reihenfolge beachten:** dieser Zweig muss vor dem Baum-, Stapel- und
Gebäude-Zweig stehen, sonst nimmt ein Klick auf einen Stapel nur neues Holz auf.

**`B`-Rechteck erfasst künftig auch Stapel.** `TreeManager.area_trees` hat sein
Gegenstück in `WoodPileManager`: neue `piles_in_area(area, poly)`. Die im Rechteck
liegenden Stapel werden als Sammelziele in den stehenden Auftrag aufgenommen, und für
sie gilt die **automatische** Ablieferung.

---

## Teil 1b — Baukosten gesenkt (Nutzervorgabe 2026-08-05)

| Gebäude | vorher | jetzt |
|---|---|---|
| Hütte (Stufe 0) | 8 | **7** |
| Hütten-Ausbaustufe (je) | 5 | **4** |
| Feuertempel | 20 | **18** |
| Katapultwerkstatt | 13 | **12** |
| Feuerrammenwerkstatt | 11 | **10** |

Kumulierter Hüttenpreis damit **7 / 11 / 15 / 19 / 23** (vorher 8/13/18/23/28), der
Wohnpalast also 23 statt 28 Holz. `CLAUDE.md` §5 ist mitgezogen.

**Sechs Tests hingen an den alten Zahlen** (Reparaturkosten, Baustellen-HP-Anteil,
Abriss-Erstattung). Sie rechnen jetzt aus `Balance.HUT_WOOD_COST` /
`HUT_UPGRADE_WOOD_COST` statt aus festen Werten — die Hüttenkosten sind inzwischen
dreimal gesunken (12 → 8 → 7), und jede feste Zahl brach dabei erneut.

---

## Teil 2 — Regale an den Hütten (Ausbau-Depots)

Analog zum Werkstatt-Regal aus 10g Teil 4, dieselbe Mechanik, anderer Anlass.

- Neuer Bauordnungs-Zweig `&"hut_rack"` (dritter Schlüssel auf `WOOD_DEPOT_SCENE`),
  **vor** den Werkstatt-Zweigen und **hinter** dem Wohnraum: ein Regal nützt nur, wenn
  Hütten stehen, die ausbauen wollen.
- Auslöser: ein **Hüttencluster** (`_settlement_anchors` liefert die Zentren schon)
  ohne Regal innerhalb `Building.ABSORB_RADIUS` eines seiner Hütten-Lieferpunkte,
  **und** mindestens eine Hütte dort mit `upgrade_stage < HUT_MAX_UPGRADE_STAGE`.
- Platz-Scan wie `_find_shop_rack_plot`: eigener, begrenzter Ringscan, **ohne**
  Baum-Anforderung und ohne das geteilte Plot-Budget zu belasten. Die
  Ausfahrkorridor-Regel entfällt (Hütten haben keine Fahrzeuge), die Regel „nicht im
  Absorptionsradius eines *anderen* Gebäudes" bleibt.
- **Bestückung:** die Fäll-Trupps liefern schon bevorzugt in Regale
  (`Brave._tick_loose_deliver`, `DEPOT_PREFER_RADIUS`). Zusätzlich hält
  `_tick_hut_racks` einen Mindestbestand von `AI_HUT_RACK_STOCK` (5 = genau ein
  Ausbau) — unterschreitet ein Regal den, wird es ein Nachschub-Ziel des vorhandenen
  `_tick_supply_runs`. Kein neuer Transportmechanismus.

---

## Teil 3 — Mehr Holz, und für das Richtige

- **Größere/mehr Fäll-Trupps:** `AI_BRAVES_PER_WOOD_CREW` 12 → 9,
  `AI_MAX_WOOD_CREWS` 4 → 6. Damit fällt der erste Trupp früher und die Zahl skaliert
  schneller mit dem Stamm.
- **Ablieferung nach Bedarf statt nach Nähe** (Punkt 4 des Reports: Stapel lagen bei
  Werkstätten, während Hütten warteten). `Brave._tick_loose_deliver` wählt heute das
  **nächste** Regal bzw. Gebäude. Neu: unter mehreren Kandidaten innerhalb
  `DEPOT_PREFER_RADIUS` gewinnt der mit dem **größten offenen Bedarf**
  (`wood_needed_total() - wood_incoming()`, Ausbaubedarf, Regal-Füllstand), bei
  Gleichstand der nähere. Das ist eine reine Zielwahl-Änderung, kein neuer Transport.
- **Werkstätten nachrangig:** eine Werkstatt mit vollem `stock_target()` zählt als
  bedarfsfrei — dann geht das Holz an Hütten und Baustellen.

---

## Teil 4 — ~~Breitere Expansion~~ → Bauplatz darf nie ausgehen

**Vom Nutzer zurückgezogen und ersetzt (2026-08-05):** „die Expansion ist auch nicht
zwingend. Es ist okay, wenn sie nahe dran Gebäude bauen. Es soll nur verhindert
werden, dass die KI keine weiteren Gebäude baut, weil ihr Bauplatz schon voll ist."

**Mit einer Sonde geprüft — und die Ursache war eine andere als „Platz voll":**
`_find_supplied_plot` verlangt `MIN_TREES_NEAR_PLOT` Bäume innerhalb
`PLOT_TREE_RADIUS`, ohne jede Rückfallebene. Eine abgeholzte Basis hat damit **keinen
gültigen Bauplatz mehr** und die KI bleibt komplett stehen. Gemessen an derselben
Welt: mit Bäumen Bauplatz `(47, 47)`, nach dem Abholzen `(-1, -1)`.

Die Anforderung war richtig, **solange** Holz nur vor Ort geholt werden konnte. Seit
10g Teil 4 und 10h Teil 2/3 wird Holz aktiv herangetragen (`order_supply_wood`,
Nachschub-Trupps, Regale im Absorptionsradius) — „Baum daneben" ist also nur noch
eine **Präferenz**, keine Voraussetzung.

Umgesetzt als **dritter, letzter Durchgang** in `_find_plot`:
`_find_supplied_plot(anchor, footprint, spacing, require_trees := false)`. Er läuft
nur, wenn die beiden bestehenden Durchgänge nichts gefunden haben — kostet also
keinen Tick, der vorher erfolgreich war, und lässt die bevorzugte Wahl unverändert.

Breitere Expansion (Suchradius/Anker/Cluster nach Arena-Weite) ist damit **entfallen**
— sie hätte die Bauplatzsuche angefasst, den historisch teuersten KI-Posten, für ein
Ziel, das der Nutzer ausdrücklich nicht braucht.

---

## Teil 5 — Mehr Startholz auf kleinen Karten

Nutzervorgabe: „auf kleinen Karten muss am Anfang 20 % mehr Holz spawnen."

`Balance.SMALL_MAP_WOOD_BONUS = 1.2`, angewendet in `main.gd` auf **Bäume und Haine**
gleichermaßen, damit sich das Verhältnis der Baumarten nicht verschiebt. Klein heißt
`td.size <= SMALL_MAP_MAX_SIZE` (= `TerrainData.SIZE`, also Insel und Plateau mit 128;
Seenland und Bergpass mit 256 bleiben unverändert). Begründung im Code: auf den
kleinen Karten liegen die Basen eng zusammen, jeder Stamm hat also weniger Wald für
sich — dieselbe Enge, die 10g Teil 5 über das Arena-Maß behandelt.

---

## Neue `Balance`-Konstanten

```gdscript
# --- Trageverhalten (10h Teil 1) ---
## Haelt ein Brave Holz OHNE Ablege-Befehl so lange, laesst er es fallen.
const BRAVE_CARRY_HOLD_TIMEOUT: float = 30.0

# --- KI: Regale an den Huetten (10h Teil 2) ---
const AI_MAX_HUT_RACKS: int = 4
## Mindestbestand eines Huetten-Regals: genau ein Ausbau (HUT_UPGRADE_WOOD_COST).
const AI_HUT_RACK_STOCK: int = 5

# --- KI: mehr Holz (10h Teil 3) ---
const AI_BRAVES_PER_WOOD_CREW_NEW: int = 9      # ersetzt 12
const AI_MAX_WOOD_CREWS_NEW: int = 6            # ersetzt 4

# --- KI: offene Karten (10h Teil 4) ---
const AI_OPEN_ARENA: float = 120.0
const AI_PLOT_SEARCH_RADIUS_OPEN: int = 60
const AI_MAX_SETTLEMENT_ANCHORS_OPEN: int = 6
const AI_SETTLEMENT_CLUSTER_RADIUS_OPEN: int = 22
```

## Umsetzungsschritte

1. **Teil 1** (Trageverhalten) — eigenständig, spielerseitig sofort prüfbar, kein
   KI-Bezug. Zuerst, weil es die einzige Steuerungsänderung ist.
2. **Teil 2** (Hütten-Regale) — der eigentliche Fix für „Hütten bleiben unausgebaut".
3. **Teil 3** (mehr Holz, Bedarf statt Nähe).
4. **Teil 4** (Expansion) — zuletzt und **mit Messung**, weil es die Bauplatzsuche
   anfasst.

## Tests

- **Teil 1** in `tests/test_wood_supply.gd`: Aufnehmen hält das Holz; zweiter
  Rechtsklick legt es am Zielpunkt ab; Klick auf ein eigenes Gebäude liefert dorthin;
  Countdown lässt es nach 30 s fallen; Nahkampf lässt es fallen;
  `B`-Rechteck-Stapel liefern weiter **automatisch** ab (Regressionswächter für den
  bewusst erhaltenen Pfad).
- **Teil 2/3** in `tests/test_ai.gd`: Bauordnung setzt ein Hütten-Regal, wenn ein
  Cluster keines hat und dort noch ausgebaut werden kann; ein Regal unter Mindestbestand
  wird Nachschub-Ziel; die Zielwahl bevorzugt den größten Bedarf vor der kürzesten
  Strecke; eine volle Werkstatt zählt nicht als Bedarf.
- **Teil 4**: die drei Profilstufen (eng / normal / offen) als reine Statics.

## Risiken

1. **Die Umbelegung des Rechtsklicks ist eine Steuerungsänderung.** Wer Holz
   aufnimmt, muss es künftig aktiv ablegen. Der 30-s-Countdown ist die Sicherung
   gegen „Braves stehen mit Holz herum"; im Spieltest ist das die erste Zahl, die
   sich falsch anfühlen kann.
2. **Reihenfolge im Rechtsklick-Dispatcher.** Steht der Ablege-Zweig zu spät, nimmt
   ein Klick auf einen Stapel nur neues Holz auf statt abzulegen — der Befehl wäre
   praktisch nicht auslösbar.
3. **Regale als Liefermagnet** (schon in 10g benannt): `_nearest_depot` bevorzugt das
   nächste Regal *mit Platz*. Mehr Regale heißt mehr Magnete; die Bedarfs-Zielwahl aus
   Teil 3 ist die Gegenmaßnahme und sollte **zusammen** mit Teil 2 im Spieltest
   beurteilt werden.
4. **Expansion kostet Bauplatzsuche.** Historisch der teuerste Posten. Teil 4 nur mit
   A/B auf beiden großen Karten.
5. **Mehr Fäll-Trupps ziehen aus demselben Idle-Pool** wie Bauarbeiter (10g Teil 1)
   und Nachschub. `AI_BUILDER_BRAVE_SHARE` gegen `AI_MAX_WOOD_CREWS` nach dem
   Spieltest gemeinsam beurteilen.

## Definition of Done

- [ ] Suite grün, Output ohne `SCRIPT ERROR`, Ladecheck fehlerfrei
- [ ] Bauplatzsuche ohne Regression (Bergpass **und** Seenland)
- [ ] Manuelle Prüfung: Trageverhalten, Hütten bauen sichtbar aus, keine
      herumliegenden Riesenstapel, Siedlung wächst auf großen Karten in die Breite
- [ ] PROGRESS.md ergänzt, Checkbox 10h in `00_overview.md`
