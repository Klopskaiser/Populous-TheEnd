# Phase 10k — Manakurve, Feuerball, Feuerregen, Vulkan

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
> **Abhängigkeit:** [Phase 10j](10j_disc_world.md) ist abgeschlossen.

## Ziel

Vier Themen aus einem Nutzerwunsch (2026-08-06), zwei davon greifen tief in die
Wirtschaft:

1. **Manakurve** — die Erzeugung skaliert heute **linear** mit der Bevölkerung. Ab
   100 Anhängern soll jeder weitere nur noch ~¼ beitragen, logarithmisch; 500 Leute
   sollen das **Doppelte** von 100 liefern, 1000 Leute das **Dreifache**.
2. **Zauberkosten und -reichweiten** vollständig aufgelistet (unten) — die
   Bestandsaufnahme ist Teil des Auftrags, weil die Manakurve alle Kosten faktisch
   verteuert.
3. **Feuerball** — verfolgt sein Ziel, macht weniger Schaden, wirbelt dafür 4 m hoch.
4. **Feuerregen** — größer, länger, mehr Bälle, Brand, Gebäudeschaden, Panik am Rand.
5. **Vulkan** — breiter, mit echtem Krater, EIN großer Schwall, Lava läuft weiter,
   danach ein kleines Plateau oben.

---

# Teil 1 — Manakurve

## Ist-Stand

`Tribe.mana_rate()` (`scripts/core/tribe.gd:162`):

```gdscript
return float(population()) * MANA_BASE_RATE     # MANA_BASE_RATE = 0.1
```

Also **0,1 Mana/s je Kopf, linear und unbegrenzt**. 1000 Leute erzeugen heute
100 Mana/s — das Zehnfache von 100 Leuten.

## Vorschlag: die Formel

Die drei Vorgaben (¼ pro Kopf ab 100 · 2× bei 500 · 3× bei 1000) sind mit einer
**einzigen** Kurve exakt erfüllbar:

```
                        ln(1 + (n − 100)/10000)
P(n) = 1 + ─────────────────────────────────────     für n ≥ 100
                              ln(1,04)

P(n) = n / 100                                       für n < 100  (unverändert linear)
```

**Dazu die Grundrate `MANA_BASE_RATE` 0,10 → 0,11** (Nutzervorgabe: +10 % je Anhänger).

`P(n)` ist die Produktion in Vielfachen der Produktion bei 100 Anhängern. In
Code-Form als „wirksame Bevölkerung":

```gdscript
## Wirksame Bevölkerung für die Manaerzeugung. Bis MANA_SOFT_CAP linear, darüber
## logarithmisch gedämpft: 500 Anhänger liefern das Doppelte von 100, 1000 das
## Dreifache. Der Beitrag des 101. Anhängers ist noch 28 % des Beitrags des 100.
func mana_population() -> float:
    var n: int = population()
    if n <= Balance.MANA_SOFT_CAP:
        return float(n)
    return float(Balance.MANA_SOFT_CAP) * (1.0
        + log(1.0 + float(n - Balance.MANA_SOFT_CAP) / Balance.MANA_LOG_SCALE)
        / log(Balance.MANA_LOG_BASE))
```

mit `MANA_SOFT_CAP = 100`, `MANA_LOG_SCALE = 10000.0`, `MANA_LOG_BASE = 1.04`.

**Warum genau diese Zahlen:** sie sind nicht gefittet, sondern fallen aus den Vorgaben
heraus. `400/10000 = 0,04`, also ist der Logarithmus bei n = 500 **exakt** `ln(1,04)`
und der Bruch exakt 1 → **P(500) = 2,0000**. Bei n = 1000 ergibt `900/10000 = 0,09`
den Wert `ln(1,09)/ln(1,04) = 2,1972` → **P(1000) = 3,197**, also die vom Nutzer
gewünschte „leicht über 3, unter 3,5"-Spitze (~3,2).

## Was die Kurve liefert

| Anhänger | wirksame Bev. | Mana/s (Rate 0,11) | Vielfaches von 100 | Beitrag des nächsten Kopfes |
|---|---|---|---|---|
| 100 | 100,0 | 11,00 | 1,000× | 25,5 % |
| 200 | 125,4 | 13,79 | 1,254× | 25,2 % |
| 300 | 150,5 | 16,55 | 1,505× | 25,0 % |
| **500** | **200,0** | **22,00** | **2,000×** | 24,5 % |
| 700 | 248,6 | 27,34 | 2,486× | 24,1 % |
| **1000** | **319,7** | **35,17** | **3,197×** | 23,4 % |

Der Beitrag des 101. Anhängers ist **25,5 %** eines Kopfes unterhalb der Grenze und
fällt bis 1000 nur auf 23,4 % — die Kurve liegt also über ihre ganze Länge sehr nah an
der Vorgabe „¼ pro neuem Mitglied". Bemerkenswert: sie trifft das ¼ **besser** als die
erste Fassung (28 % → 18 %), weil die flachere Basis `1,04` gleichmäßiger dämpft.

Eine reine `1 + k·ln(n/100)`-Kurve kann 2× bei 500 und ~3× bei 1000 übrigens **nicht**
gleichzeitig treffen (sie liefert bei 1000 nur 2,4×) — deshalb der Versatz um die 100
im Zähler.

## Förster-Unterhalt (Nutzerentscheidung 2026-08-06)

`FORESTER_MANA_PER_WORKER` **1,5 → 0,6**, eine voll besetzte Försterei (4 Arbeiter)
kostet damit **2,4 Mana/s**. Der Unterhalt wird laut `Tribe.tick()` vom Einkommen
abgezogen, **bevor** geladen wird — das bleibt so.

Damit ist der Erstickungsfall entschärft, den die Kurve sonst erzeugt hätte (mit 1,5
hätten fünf Förstereien bei 1000 Anhängern das gesamte Einkommen aufgefressen):

| | 500 Anhänger | 1000 Anhänger |
|---|---|---|
| Einkommen | 20,0 Mana/s | 30,0 Mana/s |
| 5 volle Förstereien | 12,0 Mana/s (**60 %**) | 12,0 Mana/s (**40 %**) |

Förstereien bleiben also eine spürbare, aber tragbare Last — und sie werden im
**Frühspiel** relativ teurer als im Spätspiel, was zur Kurve passt.

## Ausbildung kostet Mana (neu, Nutzervorgabe 2026-08-06)

Ein Trainingsgebäude zahlt **so viel wie ein Försterarbeiter: 0,6 Mana/s** — aber
**nur, solange tatsächlich ausgebildet wird**. Wer in der Warteschlange steht, kostet
nichts.

Der Anknüpfungspunkt ist eindeutig: `TrainingBuilding` hat `trainee` (der Brave **im**
Gebäude) und `incoming` (die Schlange). Die Bedingung ist damit wörtlich
`trainee != null` — die Schlange bleibt kostenlos, ohne dass etwas Neues gezählt
werden muss.

### Nur die Ausbildung zahlt — am Klassenbaum nachgeprüft

Nutzervorgabe: *„gehe sicher, dass nur die Ausbildung Mana kostet, Fahrzeugbau und
Brave-Hütten-Bevölkerung kostet kein Mana."* Der Klassenbaum trennt das bereits
vollständig:

| Klasse | erbt von | produziert | zahlt Mana? |
|---|---|---|---|
| `WarriorCamp`, `Temple`, `FirewarriorCamp` | **`TrainingBuilding`** | Kampfeinheiten | **ja**, 0,6/s solange `trainee != null` |
| `Workshop`, `FireRamWorkshop`, `AirshipWharf` | **`Workshop` → `Building`** | Fahrzeuge | **nein** |
| `Hut` | **`Building`** | Braves | **nein** |
| `Forester` | `Building` | Setzlinge | nein (zahlt seinen **eigenen** Arbeiter-Unterhalt, unverändert) |

Entscheidend: **`trainee` existiert ausschließlich auf `TrainingBuilding`** (in
`building.gd` kommt das Wort nur in Kommentaren vor). Werkstätten und Hütten sind
**Geschwisterzweige** von `Building` mit eigenen `_tick_active`-Timern und haben gar
kein `trainee` — sie können vom Einhängepunkt also nicht erfasst werden.

**Verbindlich für die Umsetzung:** die Buchung gehört auf **`TrainingBuilding`**, nicht
auf `Building`, und sie wird **nicht** an ein generisches „produziert grade etwas"
gehängt. Sonst zahlen Fahrzeugbau und Hütten still mit.

**Wächter-Tests** (weil eine spätere Verallgemeinerung das lautlos brechen würde):
`test_vehicle_construction_costs_no_mana`,
`test_hut_brave_production_costs_no_mana`,
`test_training_costs_mana_only_while_a_trainee_is_inside`,
`test_queued_braves_cost_nothing`.

Gebucht wird über denselben Weg wie der Förster-Unterhalt (`Tribe.consume_mana`, eine
**Schuld gegen das Einkommen**, kein Abzug von einem Vorrat) — damit gilt automatisch
dieselbe Regel: reicht das Einkommen nicht, wird die Schuld vorgetragen und es lädt
kein Zauber, bis sie bezahlt ist.

| Bei 500 Anhängern (22,0 Mana/s) | Last | Anteil |
|---|---|---|
| 5 volle Förstereien | 12,0 Mana/s | 55 % |
| + 3 gleichzeitig ausbildende Lager | 1,8 Mana/s | zusammen **63 %** |
| bei 1000 Anhängern (35,2 Mana/s) | 13,8 Mana/s | **39 %** |

Die Ausbildung ist also ein spürbarer, aber kleiner Posten neben den Förstereien —
sie bestraft vor allem das **Dauertrainieren** vieler Lager parallel.

**Neue Konstante:** `TRAINING_MANA_PER_BUILDING: float = 0.6` (bewusst derselbe Wert
wie `FORESTER_MANA_PER_WORKER`, mit Kommentar auf die Vorgabe).

## Beten: bereits abgeschafft, nichts zu tun

Am Code nachgeprüft: `Tribe.mana_rate()` ist seit Phase 10c **rein** die
Bevölkerungsrate, und `ReincarnationSite` hält im Kommentar fest, dass Beten als
Feature entfallen ist. Es gibt **keine** `PRAY`-Konstante und keinen Codepfad, der
Zusatzmana erzeugt. Die Vorgabe „kein Zusatzmana möglich" ist erfüllt; der Plan hält
das nur fest, damit es nicht erneut gesucht wird.

## Offene Frage

Zählt die **Schamanin** als Anhänger? `population()` zählt heute alle Einheiten. Für
die Siegbedingung ist „Anhänger" ausdrücklich *ohne* Schamanin definiert (§7). Bei
100+ Einheiten ist der Unterschied vernachlässigbar — Vorschlag: `population()`
unverändert lassen und die Abweichung im Kommentar benennen.

---

# Teil 2 — Zauberkosten: neue Werte (Nutzervorgabe 2026-08-06)

Begründung des Nutzers: *„die Manakosten waren insgesamt zu unausgewogen."* Die
Ladungszahlen (`max_charges`) und Reichweiten bleiben **unverändert**, nur
`charge_cost`:

| # | Zauber | Kosten alt | **neu** | Faktor | Reichweite alt | **neu** | Ladungen | Speicher |
|---|---|---|---|---|---|---|---|---|
| 1 | Feuerball | 30 | **30** | — | 8,0 | 8,0 | 4 | 120 |
| 2 | Blitz | 70 | **200** | 2,9× | 12,0 | 12,0 | 4 | 800 |
| 3 | Insektenschwarm | 50 | **100** | 2,0× | 8,0 | **10,0** | 4 | 400 |
| 4 | Landbrücke | 60 | **150** | 2,5× | 9,0 | 9,0 | 4 | 600 |
| 5 | Tornado | 110 | **220** | 2,0× | 10,0 | **11,0** | 3 | 660 |
| 6 | Erdbeben | 130 | **400** | 3,1× | 10,0 | **11,0** | 2 | 800 |
| 7 | Vulkan | 180 | **1600** | 8,9× | 12,0 | 12,0 | 1 | 1600 |
| 8 | Feuerregen | 100 | **775** | 7,8× | 10,0 | **12,0** | 2 | 1550 |
| 9 | Ebene | 90 | **300** | 3,3× | 10,0 | 10,0 | 3 | 900 |
| 10 | Absinken | 60 | **350** | 5,8× | 10,0 | 10,0 | 3 | 1050 |
| 11 | Supertornado | 200 | **1200** | 6,0× | 10,0 | **12,0** | 1 | 1200 |
| **12** | **Hypnose** (neu, Teil 6) | — | **210** | — | — | **10,0** | 3 | 630 |

**Gesamtspeicher: 10 310 Mana** statt bisher 2460 — Faktor **4,2**. Zusammen mit der
gedämpften Kurve (Teil 1) ist das die eigentliche Wirtschaftsänderung dieser Phase.

## Was das für die Ladezeiten heißt

Alle aktiven Zauber laden **gleichzeitig und teilen sich das Einkommen zu gleichen
Teilen** (Phase 10c). Mit 12 Zaubern bekommt jeder ein Zwölftel:

| Eine Ladung | alle 12 aktiv @500 | **allein** @500 | **allein** @1000 |
|---|---|---|---|
| Feuerball (30) | 16 s | 1 s | 1 s |
| Hypnose (210) | 115 s | 10 s | 6 s |
| Erdbeben (400) | 218 s | 18 s | 11 s |
| Feuerregen (775) | 423 s | 35 s | 22 s |
| Supertornado (1200) | 655 s | 55 s | 34 s |
| Vulkan (1600) | 873 s | 73 s | 45 s |

Ein Vulkan wäre bei voller Zauberleiste in einer normalen Partie **nie** verfügbar. Das
ist **kein Rechenfehler, sondern die Pointe**: die hohen Zauber sind nur erreichbar,
wenn man die anderen per **Rechtsklick abschaltet** — deren Anteil geht dann an die
verbliebenen (10c-Mechanik, gespeicherte Ladungen bleiben erhalten). Damit wird der
An/Aus-Schalter der Zauberleiste vom Nebenfeature zur **zentralen strategischen
Entscheidung**.

Zwei Folgen gehören zur Umsetzung:

1. **Die Zauberleiste muss die Ladezeit sichtbar machen.** Heute zeigt sie Pips und
   einen Balken; bei 873 s bewegt der sich unmerklich. Vorschlag: Restzeit als Zahl,
   sobald sie über 30 s liegt. Ohne das ist die neue Ökonomie für den Spieler blind.
2. **Die KI schaltet Zauber ab** (Nutzervorgabe: *„kann je nach rate entscheiden"*,
   und: *„sollte Manaverschwendung vermeiden — wenn eh alles voll ist was aktiv ist,
   kann sie auch teure Zauber anmachen"*). `AIController` kennt heute keine
   Deaktivierung; mit gleichverteiltem Einkommen bekäme sie einen Vulkan nie und würde
   ihr Mana in Feuerbälle streuen. Die Heuristik hat damit **zwei** Regeln:

   **(a) Verschwendung vermeiden — hat Vorrang.** Es gibt **kein Mana-Banking**
   (Phase 10c): Einkommen, das keinen Abnehmer findet, **verfällt**. Sind also alle
   aktiven Zauber voll, verliert die KI ihr gesamtes Einkommen. Dann schaltet sie
   **die teuersten noch nicht vollen Zauber zu** — Verschwendung ist immer schlechter
   als ein langsam ladender Vulkan. Das ist zugleich der natürliche Weg, wie die KI
   überhaupt an die hohen Zauber kommt: sie sammelt sie im Aufbau, wenn die billigen
   längst voll sind.

   **(b) Sonst nach Rate.** Aktiv bleibt, was in einem **Zeitbudget von 120 s**
   ladbar ist: `charge_cost / (freies Einkommen / Zahl der aktiven Zauber) <= 120 s`.
   Ein Stamm mit 35 Mana/s greift damit nach Vulkan/Supertornado, einer mit 11 Mana/s
   bleibt bei Blitz und Feuerball. Gespeicherte Ladungen bleiben in beiden Fällen
   nutzbar.

   **Prüfbar ohne Spiel:** beide Regeln sind reine Funktionen über
   (Einkommen, Kosten, Füllstände) und gehören als Statics nach `AIState` — dieselbe
   Kultur wie `AIState.next_state`.

---

# Teil 2b — Reichweiten und Wirkbereiche (Bestandsaufnahme, unverändert)

Alle Werte aus `scripts/core/balance.gd`. **Reichweite** = maximaler flacher Abstand
Schamanin ↔ Zielpunkt (`Spell.cast_range`, geprüft in `Shaman`); aus dem Wachturm
kommen `Watchtower.TOWER_RANGE_BONUS`, vom Luftschiffdeck `AIRSHIP_RANGE_BONUS` dazu.
**Mana je Ladung** = `charge_cost`; **voll** = `charge_cost × max_charges`.

Wirkbereiche bleiben unverändert (außer wo Teil 3–5 sie ausdrücklich ändern):

| # | Zauber | Wirkbereich |
|---|---|---|
| 1 | **Feuerball** | Direkt 0,8 m, Splash 2,5 m — *Schaden neu, siehe Teil 3* |
| 2 | **Blitz** | Einzelziel 240 HP / Gebäude +2 Stufen |
| 3 | **Insektenschwarm** | Radius 3,0 m, 10 s, 5 DPS + Panik 6 s |
| 4 | **Landbrücke** | Halbbreite 1,6 m |
| 5 | **Tornado** | Radius 2,2 m, 10 s, Sturzschaden 30 |
| 6 | **Erdbeben** | Radius 7,0 m, Gebäude +2 Stufen, 15 HP |
| 7 | **Vulkan** | Kegel r 5,0 m, Zone 20 s — *neu, siehe Teil 5* |
| 8 | **Feuerregen** | Streuung 5,5 m, 12 Bälle / 3 s — *neu, siehe Teil 4* |
| 9 | **Ebene** | Quadrat, halbe Kante 4,5 m |
| 10 | **Absinken** | Radius 6,0 m, 3,0 m tief |
| 11 | **Supertornado** | Radius 4,4 m, 12 m hoch, 16 s |
| 12 | **Hypnose** | Quadrat **4 × 4 m**, 30 s Kontrollwechsel — *Teil 6* |

**Zum Vergleich der alte Zustand:** Gesamtspeicher 2460 Mana bei einem linearen
Einkommen von 100 Mana/s bei 1000 Anhängern — alles war in 25 s voll. Neu sind es
10 100 Mana bei 35 Mana/s, also **289 s** für die volle Leiste. Das ist der Kern
dieser Phase in einer Zahl.

---

# Teil 3 — Feuerball: Zielverfolgung, weniger Schaden, Wirbel

## 3a — Der Ball verfolgt sein Ziel

Heute ist der Feuerball rein **punktbezogen**: `FireballSpell.execute` schickt einen
`FireballBolt` auf den Zielpunkt, egal was dort inzwischen steht. Zwischen Zielwahl
und Wirkung liegt aber die Zauberzeit von 1,0 s (`Balance.SHAMAN_CAST_TIME`) — in der
läuft ein Ziel bis zu 4 m weit.

**Neu:** beim Auslösen sucht der Zauber die nächste **feindliche** Einheit im Umkreis
`FIREBALL_ACQUIRE_RADIUS` (Vorschlag 2,0 m) um den Zielpunkt. Wird eine gefunden,
verfolgt der Bolt sie — **solange sie sich nicht weiter als
`FIREBALL_CHASE_MAX_DRIFT` (Vorschlag 6,0 m) vom ursprünglichen Zielpunkt entfernt**.
Läuft sie weiter weg oder stirbt sie, fällt der Bolt auf den festen Punkt zurück und
schlägt dort ein. Das ist genau die Nutzervorgabe „verfolgen, wenn es nicht zu weit
vom Zauberort weg ist".

Muster ist vorhanden: `Fireball` (Feuerkrieger, `scripts/units/fireball.gd`) verfolgt
seit jeher eine Einheit; `FireballBolt` fliegt eine Parabel auf einen Punkt. Die
Verfolgung wird als **Nachführen des Zielpunkts** implementiert (Parabel bleibt), nicht
als neue Flugmechanik.

## 3b — Weniger Schaden, dafür 4 m Wirbel

Alle Werte Nutzervorgabe 2026-08-06:

| Wert | heute | **neu** |
|---|---|---|
| `FIREBALL_DIRECT_DAMAGE` | 60 (1 Brave-Leben) | **20** |
| `FIREBALL_SPLASH_DAMAGE` | 30 | **10** |
| Wirbelhöhe Direkttreffer | — (nur Schub/kleiner Lift) | **4,0 m** |
| Wirbelhöhe Splash-Opfer | — | **2,0 m** |
| Sturzschaden | — | aus `CLIFF_FALL_DAMAGE_PER_M` (6,0/m): **24** bzw. **12** |

**Was das für eine Einheit bedeutet:**

| Opfer (Brave, 60 HP) | Schaden | Summe |
|---|---|---|
| Direkttreffer | 20 + 24 (Sturz aus 4 m) | **44** — überlebt mit 16 HP |
| Splash | 10 + 12 (Sturz aus 2 m) | **22** |

**Der Feuerball tötet damit keinen Braves mehr direkt** (bei 60 Schaden war er genau
ein Brave-Leben). Er wird von einer Tötungs- zu einer **Störwaffe**: er wirft eine
ganze Traube durch die Luft, unterbricht Kämpfe, Bekehrungen und Arbeit. Das ist die
gewollte Verschiebung — bei 30 Mana und 4 Ladungen ist er der billige Dauerzauber.

**Eine Wechselwirkung, die dadurch stark wird:** seit 10j stirbt jeder, der über den
Scheibenrand geschleudert wird. Ein Feuerball nahe dem Rand wird damit zur
**Tötungswaffe für eine ganze Gruppe** — Direkttreffer *und* Splash-Opfer fliegen. Das
ist emergentes Spiel und kein Fehler, gehört aber in die Doku.

**Mechanik ist vorhanden, es wird nichts Neues gebaut:**
`Unit.throw_airborne(velocity, fall_damage)` (`unit.gd:1910`) macht genau das —
Landung mit Sturzschaden, danach Weiterrollen mit der Wurfgeschwindigkeit, wie bei
jedem anderen Sturz. Der Flughöhen-Deckel `LIFT_MAX_HEIGHT` (8 m) und die
Randregel aus 10j gelten automatisch mit.

---

# Teil 4 — Feuerregen: Dauerbeschuss statt Salve

Alle Werte Nutzervorgabe 2026-08-06:

| Wert | heute | **neu** |
|---|---|---|
| `FIRESTORM_SPREAD_RADIUS` | 5,5 m | **7,2 m** (+30 %) |
| `FIRESTORM_DURATION` | 3,0 s | **20,0 s** |
| Ballabstand | fest 0,25 s | **zufällig, Mittel 0,3 s** → ~67 Bälle |
| Zielpunkte | gestreut, deterministisch | **zufällig in der Fläche** |
| Schaden je Ball | 60 / 30 | **20 / 10** |
| Hochwirbeln | ja (wie Feuerball) | **nein** |
| Brand | nein | **ja** |
| Gebäudeschaden | **nein** | **ja, 20 HP je Ball** |
| Panik außen herum | nein | **ja** |

**Zum Gebäudeschaden:** die Vorgabe lautet „ein Ball wie ein Nahkampfangriff von einem
Krieger". Ein Kriegerschlag ist `MELEE_PUNCH`/`MELEE_KICK` (6/8) × `melee_strength()`
3,0 = **18–24 HP** — die 20 HP Direktschaden des Balls liegen genau in dieser Spanne.
Es braucht also **keine neue Konstante**: der Ball trägt seinen Direktschaden auch an
Gebäude. Über die ~67 Bälle summiert das auf **~1340 HP** im Zielgebiet, also mehrere
zerstörte Gebäude (Hütte 300, Feuertempel 600). **Das ist ausdrücklich gewollt**
(*„der zauber ist stark, es ist ok, wenn dadurch alle gebäude zerstört werden"*) —
bei 775 Mana je Ladung ist er der teuerste Angriffszauber neben Vulkan und
Supertornado.

**Zu den zufälligen Abständen:** gezogen aus dem bereits vorhandenen, **aus der
Zielzelle geseedeten** `_rng` des `FirestormShower` — damit bleibt der Zauber
deterministisch und headless testbar, obwohl er zufällig *wirkt*. Vorschlag:
gleichverteilt in [0,05 s; 0,55 s] (Mittel 0,3 s), was auch echte Doppelschläge
erzeugt („es können auch Bälle kurz nacheinander fallen"). Gespawnt wird, bis
`DURATION` abgelaufen ist — `BOLT_COUNT` entfällt als fixe Zahl und wird zur
Obergrenze gegen Endlosschleifen.

**Kein Hochwirbeln:** `FireballBolt._explode` schleudert heute **jeden** im
Push-Radius. Der Feuerregen braucht dafür einen Schalter in der Bolt-Parametrisierung
(siehe unten) — ohne den würden 67 Bälle das Zielgebiet dauerhaft durch die Luft
wirbeln, und in Randnähe wäre der Zauber ein Massentöter durch den Void.

**Der Ball ist heute derselbe wie beim Feuerball-Zauber** (`FireballBolt`, geteilte
Konstanten). Da Teil 3 dessen Werte ohnehin ändert und der Feuerregen eigene braucht,
werden die Bolt-Werte **parametrisiert**: `FireballBolt.setup(...)` bekommt optionale
Schadenswerte **und Schalter für Wirbeln/Brand/Gebäudeschaden**, Standard bleibt der
Feuerball-Zauber. Sonst zieht jede Feuerregen-Anpassung den Feuerball mit — die Falle
ist real, beide teilen sich heute `FIREBALL_DIRECT_DAMAGE`.

- **Gebäudeschaden:** `FireballBolt._explode` kennt heute Einheiten, Bäume, Stapel,
  Fahrzeuge und Luftschiffe — **Gebäude nicht**. Neu: Gebäude im Splash-Radius nehmen
  den Direktschaden des Balls als **HP-Schaden** (nicht als Zerstörungsstufen), womit
  die vorhandene Vierstufen-Mechanik von `Building.take_damage` automatisch greift.
- **Brand:** `Unit.ignite(source_pos)` (`unit.gd:2255`) existiert und wird von
  Lava/Feuerramme benutzt. Getroffene Einheiten brennen künftig.
- **Panik am Rand:** Einheiten zwischen `FIRESTORM_SPREAD_RADIUS` und
  `FIRESTORM_PANIC_RADIUS` (Vorschlag 1,6 × Streuung ≈ 11,5 m) geraten in Panik
  (`Balance.PANIC_DURATION` 6 s). Der Schwarm macht das schon genauso.
  **Die Schamanin ist bereits global immun** — `Unit.is_panic_immune()` (Basis false),
  `Shaman` und `CrewedVehicle` überschreiben auf true, `Unit.panic()` prüft es. Hier
  ist **nichts zu tun**, die Vorgabe ist erfüllt.

**Perf-Pflicht:** 50 Bolts über 25 s statt 12 über 3 s heißt dauerhaft ~4 aktive
Projektile mehr, jedes mit einer Radiusabfrage beim Einschlag, plus die Panikabfrage.
`benchmark_stress` (Phase `proj`) vorher/nachher, verschränkt.

---

# Teil 5 — Vulkan: echter Krater

## Ist-Stand

`VolcanoSpell.cone_targets` legt einen **Smoothstep-Kegel** an: Radius 5,0 m, Spitze
+6,0 m, nach innen monoton steigend — ein spitzer Hügel ohne Krater. `VolcanoZone`
schickt danach **2 Lavastöße** im Abstand von 3,5 s.

## Neu

| Wert | heute | Vorschlag |
|---|---|---|
| `VOLCANO_RADIUS` | 5,0 m | **7,0 m** (breiter) |
| Gipfelhöhe `PEAK` | 6,0 m | 6,0 m (unverändert) |
| Kraterrand-Radius | — | **0,55 × Radius** = 3,85 m |
| Kratertiefe | — | **1,5 m** unter dem Rand |
| `VOLCANO_SURGE_COUNT` | 2 | **1** (ein großer Schwall) |
| Lava-Lebensdauer | `LAVA_LIFETIME` 5,0 s | **8,0 s** nur für Vulkanlava (eigene Konstante) |

**Profil** (eine Funktion, testbar ohne Szenenbaum):

```
d  = Abstand vom Zentrum
R  = VOLCANO_RADIUS,  r = VOLCANO_RIM_FRACTION * R
flanke = smoothstep(clamp((R − d) / (R − r), 0, 1))     # 0 am Fuß, 1 am Rand
mulde  = smoothstep(clamp((r − d) / r, 0, 1))           # 0 am Rand, 1 im Zentrum
h(d)   = boden + PEAK * flanke − VOLCANO_CRATER_DEPTH * mulde
```

- bei `d = R`: unverändert (Fuß)
- bei `d = r`: `boden + PEAK` — der **Rand**, der höchste Punkt
- bei `d = 0`: `boden + PEAK − 1,5` — die **Mulde**

**Ablauf des Ausbruchs:**
1. `TerrainMorph` hebt den Krater über `DURATION` (3 s) — wie heute, nur mit dem
   neuen Profil.
2. Die Lava quillt **in der Mulde** hoch (Spawnpunkt = Zentrum, nicht mehr am
   Kegelrand), steigt über den Rand und läuft dann außen hinunter. Ein Schwall,
   dafür mit erhöhter Lebensdauer, damit er weiter kommt.
3. **Wenn der Schwall über den Rand tritt, wird die Mulde aufgefüllt** — ein zweiter,
   kleiner `TerrainMorph` zieht alles innerhalb `r` auf Randhöhe. Oben bleibt ein
   kleines rundes Plateau (Radius `r` = 3,85 m), begehbar, weil eben.

**Achtung, dokumentierte Falle:** `VOLCANO_SURGE_INTERVAL` steht im Code mit einer
Warnung — größer als `LAVA_MOLTEN_TIME + LAVA_BUILDING_CONTACT_GRACE` schaltet den
**Gebäudeschaden des Vulkans still ab** (Herleitung in `plans/10c`). Mit nur noch
EINEM Schwall entfällt das Intervall als Problem, aber die Ursache bleibt: der
Gebäudeschaden hängt an **durchgehendem** Lavakontakt. Bei einem einzelnen Schwall mit
8 s Lebensdauer muss geprüft werden, dass ein überströmtes Gebäude überhaupt noch
Stufen verliert — **das ist der Regressionswächter dieses Teils**.

---

# Teil 6 — Neuer Zauber: Hypnose

**Vorgabe:** 210 Mana je Ladung. Bekehrt gegnerische Anhänger in einem kleinen Gebiet
(**4 × 4 m**) — **nicht die Schamanin** — und lässt sie für die eigene Sache kämpfen,
**steuerbar** vom neuen Kontrolleur. Der Kontrollwechsel hält **30 Sekunden**.
Hypnotisierte können ganz normal von Predigern bekehrt werden. Über ihnen steht ein
**neues Zeichen**, das die vorübergehende Kontrolle anzeigt.

## Der Unterschied zur Bekehrung — und warum er Arbeit macht

Die Bekehrung des Predigers (`Unit.convert_to_tribe`) ist **endgültig**: sie hängt die
Einheit in die Stammeslisten um und vergisst die Herkunft. Die Hypnose braucht
denselben Umhang **plus ein Gedächtnis und einen Rückweg**:

```gdscript
## Temporärer Stammeswechsel (Hypnose). Anders als convert_to_tribe MERKT sich die
## Einheit ihren Ursprungsstamm und fällt nach `duration` dorthin zurück.
func hypnotize(new_tribe: Tribe, duration: float) -> bool
func _tick_hypnosis(delta: float) -> void      # läuft ab -> _revert_hypnosis()
func is_hypnotized() -> bool
```

Wiederverwendet wird alles, was `convert_to_tribe` bereits richtig macht: `leave_crew()`,
`_end_attack()`, `_clear_building_target()`, `_dissolve_own_group()` und das
`converted`-Signal (der Renderer zieht die Stammesfarbe nach). Der Rückweg ruft
dieselbe Kette in die Gegenrichtung.

## Wer die letzten Leute hypnotisiert, gewinnt (Nutzerentscheidung 2026-08-06)

`GameState.is_tribe_defeated()` prüft *„keine lebende Einheit in `tribe.units`"*, und
`Tribe.eliminated` ist laut Phase 10d **irreversibel**. Hängt die Hypnose die letzten
Einheiten eines Stammes um, ist dieser Stamm damit **sofort und endgültig besiegt** —
auch wenn die Einheiten 30 s später zurückfielen.

**Der Nutzer will das ausdrücklich so:** *„wenn die letzten leute hypnotisiert werden,
ist ende."* Damit ist die Hypnose ein legitimer, sehr direkter Weg zum Sieg — und die
Umsetzung wird **deutlich einfacher**: die Einheit wechselt den Stamm **vollständig**
wie bei der Bekehrung (Bevölkerung, Manaerzeugung, Selektion), nur eben mit einem Timer
und einem gemerkten Ursprung. Es braucht **keine** zweite Zugehörigkeitsliste und keine
Sonderfälle in `population()`, `mana_rate()` oder der Siegprüfung.

**Zwei Nebeneffekte, die daraus folgen und bewusst akzeptiert sind:**

1. Während der Hypnose zählt die Einheit zur **Bevölkerung des Kontrolleurs** und
   erzeugt dort Mana. Wer 30 Einheiten hypnotisiert, bekommt 30 s lang deren
   Manaanteil dazu — eine kleine, aber reale Zusatzbelohnung.
2. Fällt der Ursprungsstamm (regulär oder genau durch diese Hypnose), wird der
   Kontrollwechsel **endgültig**: die Einheiten fielen sonst zu einem toten Stamm
   zurück. Das ist schon in der Regeltabelle unten festgehalten.

## Weitere Regeln (Vorschläge, bitte bestätigen)

| Frage | Regel |
|---|---|
| Ladungen / Reichweite | **3 Ladungen**, `cast_range` **10,0 m** (beides Nutzervorgabe) |
| Wer ist immun? | **nur die Schamanin** (Vorgabe). Prediger sind hypnotisierbar — anders als bei der Bekehrung, wo sie immun sind |
| Fahrzeugbesatzung | Hypnose wirft die Einheit per `leave_crew()` vom Gerät, wie die Bekehrung. Das **Fahrzeug** selbst wechselt nicht |
| Prediger bekehrt einen Hypnotisierten | Bekehrung gewinnt und ist **endgültig**: der Hypnose-Timer wird verworfen, die Einheit gehört dem Prediger-Stamm |
| Erneutes Hypnotisieren | Timer wird neu gesetzt, Kontrolleur wechselt; der **Ursprung** bleibt der ursprüngliche |
| Tod während der Hypnose | zählt als Verlust des **Ursprungsstammes**; den Mana-Bonus für einen Schamanentod gäbe es ohnehin nur bei der Schamanin, und die ist immun |
| Ursprungsstamm scheidet regulär aus | Hypnose wird **endgültig** (sonst fiele die Einheit zu einem toten Stamm zurück) |
| Einheiten in Bekehrung (`SIT`) | gültige Ziele — die Hypnose wirkt sofort und bricht die laufende Bekehrung ab |

## Das Zeichen über dem Kopf

`StatusFxRenderer` hat genau dafür ein Bitmasken-System: `FX_PANIC = 1`,
`FX_BURNING = 2`, `FX_INJURED = 4`. Neu kommt **`FX_HYPNOTIZED = 8`** dazu, plus ein
Eintrag in `_effects` (`_make_effect(FX_HYPNOTIZED, &"hypnotized", …)`) und ein
prozedurales Platzhalterbild nach dem Muster von `_panic_frame` / `_injured_frame` —
Vorschlag: eine **kreisende Spirale** in der Farbe des Kontrolleurs. Wie alle
Zustandsanzeigen **ohne Schatten** (CLAUDE.md §6) und später über
`assets/textures/effects/hypnotized.png` ersetzbar.

## Tests (`tests/test_hypnosis.gd`, neu)

`test_hypnotized_unit_obeys_the_new_controller`,
`test_control_returns_after_30_seconds`,
`test_shaman_is_immune`,
`test_preacher_can_be_hypnotized` (Gegenstück zur Bekehrungsimmunität),
`test_preacher_conversion_beats_hypnosis_and_is_permanent`,
`test_hypnotizing_the_last_units_defeats_the_origin_tribe` (**die Nutzerregel als
Wächter — nicht als Bug behandeln, wenn es jemandem später auffällt**),
`test_hypnosis_becomes_permanent_when_the_origin_tribe_falls`,
`test_mana_income_follows_the_controller_during_hypnosis`,
`test_area_is_four_by_four_metres`, `test_units_outside_the_square_are_untouched`,
`test_death_during_hypnosis_counts_for_the_origin_tribe`.

---

# Teil 7 — Ladeanzeige nach Original-Vorbild

**Nutzervorgabe:** wie im Original-Populous **zwei** Balken je Zauber — ein **blauer**
für den echten Fortschritt und ein **gelber**, der schneller läuft und immer wieder
durchläuft. Der gelbe liegt **hinter** dem blauen und füllt damit nur den noch offenen
Teil der Anzeige. Zweck: *„für die Rate, so hat man das besser einschätzen können."*

Das ist mit den neuen Kosten kein Schmuck mehr, sondern notwendig: bei 873 s
Ladezeit ist ein einzelner Balken über Minuten optisch unbewegt.

## Wie es sich einfügt

`Sidebar` baut je Zauberzelle bereits `bar_bg` (Hintergrund, 3 px) und `bar_fill`
(gold, links verankert, `anchor_right = progress`) und aktualisiert das in
`_update_spell_cell()`. Es kommt genau **ein Knoten dazu**:

| Knoten | Reihenfolge | Farbe | `anchor_right` |
|---|---|---|---|
| `bar_bg` | zuerst (ganz hinten) | leer/dunkel | — |
| **`bar_rate`** (neu) | **dazwischen** | **gelb** | `sweep` (0→1, läuft zyklisch) |
| `bar_fill` | zuletzt (vorn) | **blau statt gold** | `progress` (echter Fortschritt) |

Da spätere Kinder in Godot **über** früheren zeichnen, verdeckt der blaue Balken den
gelben automatisch auf seiner Länge — der gelbe ist also nur im **offenen Teil**
sichtbar, ohne dass irgendwo gerechnet werden muss. Genau die Original-Optik, und der
denkbar kleinste Eingriff.

`bar_fill` wechselt dabei von `UiTheme.GOLD` auf ein Blau; Gold wird die Farbe des
Ratenbalkens. Ein abgeschalteter Zauber behält seinen blauen Stand (wie heute), sein
**gelber Balken steht still** — damit liest man „pausiert" auf einen Blick.

## Die Umlaufzeit trägt die Information

Der Sinn des gelben Balkens ist die **Rate**, also muss seine Umlaufzeit an der
tatsächlichen Ladegeschwindigkeit hängen. Die Spanne ist allerdings riesig — von ~1 s
(Feuerball allein) bis ~900 s (Vulkan bei voller Leiste), also drei Größenordnungen.
Eine lineare Abbildung sättigt sofort; **logarithmisch** bleibt sie über die ganze
Spanne lesbar:

```gdscript
## Umlaufzeit des Ratenbalkens aus der Restzeit bis zur nächsten Ladung.
## Logarithmisch, weil die Restzeiten drei Groessenordnungen ueberspannen:
## linear waeren alle langsamen Zauber optisch identisch.
static func sweep_period(remaining_s: float) -> float:
    return clampf(0.35 * log(remaining_s + 1.0) / log(10.0) + 0.3, 0.3, 2.5)
```

| Restzeit bis zur nächsten Ladung | Umlauf des gelben Balkens |
|---|---|
| 1 s | 0,41 s (hektisch) |
| 10 s | 0,66 s |
| 100 s | 1,00 s |
| 900 s | 1,33 s (träge) |

Die Funktion ist **rein und statisch** — headless erschöpfend testbar, wie
`Sidebar.pip_state` und `Fireball.lift_chance_for_health`.

## Dazu die Zahl

Der Balken vermittelt das Gefühl, die **Restzeit als Zahl** die Entscheidung („lohnt
Warten?"). Vorschlag: in der Zelle einsetzen, sobald die Restzeit **> 30 s** liegt,
Format `1:23` bzw. `45 s`. Die Restzeit ist berechenbar, weil `Tribe` das Einkommen und
die Zahl der ladenden Zauber kennt:
`rest = (charge_cost − charge_mana) / (freies Einkommen / Zahl der ladenden Zauber)`.

**Achtung, ehrlich benannt:** diese Zahl ist eine **Momentaufnahme**. Sie springt,
sobald ein anderer Zauber voll wird, abgeschaltet wird oder die Bevölkerung sich
ändert — sie sagt „bei jetzigem Stand", nicht „garantiert". Das gehört als Kommentar an
den Code, damit es später nicht als Fehler gemeldet wird.

## Tests (`tests/test_ui_logic.gd`, ergänzt)

`test_sweep_period_is_monotonic_and_clamped`, `test_sweep_period_spans_the_real_range`
(1 s … 900 s liefern klar unterschiedliche Werte — der Grund für die log-Abbildung),
`test_remaining_seconds_uses_the_current_share`,
`test_switched_off_spell_keeps_its_progress_and_freezes_the_rate_bar`.

---

## Umsetzungsschritte

1. **Teil 1 + 2 (Mana und Kosten) zusammen und zuerst** — sie sind eine einzige
   Wirtschaftsänderung und einzeln nicht sinnvoll messbar (die Kurve allein macht alles
   billiger als gewollt, die Kosten allein unbezahlbar). Inklusive Förster 0,6 und der
   Messung, was die KI danach noch zaubert.
2. **Die KI-Abschaltheuristik** (Teil 2, Folge 2) — direkt danach, sonst misst jede
   spätere Messung eine KI, die ihr Mana verstreut.
3. **Teil 6 (Hypnose)** — der neue Zauber, mit der Stammes-/Ausscheidungsfrage als
   erstem Schritt (sie bestimmt die Bauform).
4. **Teil 5 (Vulkan)** — Terrain, größtes Regressionsrisiko, aber unabhängig vom Rest.
5. **Teil 3 (Feuerball)** — die Bolt-Parametrisierung ist die Vorarbeit für Teil 4.
6. **Teil 4 (Feuerregen)** inkl. `benchmark_stress`.
7. Doku: `docs/game_mechanics.md` (Zaubertabelle, Manaformel), `CLAUDE.md` §6
   (Zaubertabelle **plus** der neue Zauber 12), `plans/PROGRESS.md`, Checkbox in
   [00_overview.md](00_overview.md).

**Commit-Strategie:** ein Commit je Teil, per Pfad gestaged (**kein `git add -A`**) —
im selben Arbeitsbaum arbeiten Parallelsitzungen.

## Tests

**Neu `tests/test_mana_curve.gd`** — die Formel ist rein und erschöpfend prüfbar:
`test_below_the_soft_cap_stays_linear`, `test_500_is_exactly_double_100`,
`test_1000_is_exactly_triple_100` (beide auf 0,1 % genau — die Werte sind exakt, nicht
gefittet), `test_marginal_contribution_drops_to_about_a_quarter`,
`test_curve_is_monotonic_and_continuous_at_the_cap` (kein Sprung bei n = 100),
`test_forester_upkeep_leaves_income_at_1000` (die Entscheidung aus Teil 1 festgenagelt).

**Neu `tests/test_volcano_shape.gd`:** Rand ist der höchste Punkt, Mulde liegt
`CRATER_DEPTH` darunter, Fuß unverändert, Profil monoton zwischen Fuß und Rand;
nach dem Auffüllen ist das Plateau eben und begehbar; **ein überströmtes Gebäude
verliert weiterhin Zerstörungsstufen** (der Wächter aus der 10c-Falle).

**Ergänzt `tests/test_spells.gd`:** Feuerball verfolgt ein Ziel innerhalb des Drifts,
bricht die Verfolgung außerhalb ab, wirbelt den Direkttreffer 4 m hoch und macht
Sturzschaden bei der Landung; Feuerregen trifft Gebäude, entzündet Einheiten, setzt
Randfiguren in Panik **und lässt die Schamanin unbeeindruckt**.

**Anzupassen:** jeder Test, der `FIREBALL_DIRECT_DAMAGE` fest verdrahtet, und die
Mana-Erwartungen in `tests/test_economy.gd` — nach der Lehre aus 10h/10i: **aus
`Balance` rechnen, keine festen Zahlen**.

## Verifikation

```bash
godot --headless -s res://tests/run_tests.gd                    # Exit 0, kein SCRIPT ERROR
godot --headless --quit                                          # Ladecheck
godot --headless -s res://tests/benchmark_stress.gd              # Teil 4, Phase `proj`
godot --headless -s res://tests/benchmark_earlygame.gd -- map=bergpass sim=600
godot --headless -s res://tests/balance_lab.gd -- reps=3
```

Godot-Läufe über das **Bash**-Tool (PowerShell verschluckt stdout), Output auf
`SCRIPT ERROR` filtern. Perf verschränkt A/B — Maschinenrauschen bis 40 %.

**Die entscheidende Messung für Teil 1** ist nicht die Formel (die ist exakt), sondern
was die KI im Spätspiel noch zaubern kann: `benchmark_earlygame` über 600 s mit
Zählung der KI-Casts vor/nach. Bricht sie auf ~0 ein, ist die Förster-Entscheidung
falsch gewählt.

## Risiken

1. **Der Förster-Unterhalt kann das Spätspiel-Zaubern auf null bringen** (Rechnung in
   Teil 1). Das ist kein Randfall, sondern der Normalfall bei fünf Förstereien.
2. **Die Zauberkosten sind für das lineare Einkommen ausbalanciert** — nach dieser
   Phase sind sie im Spätspiel effektiv dreimal so teuer. Bewusst nicht mitgeändert:
   erst messen.
3. **Feuerregen-Gebäudeschaden**: 50 Bälle × 1 Stufe legt jedes Gebäude um. Der Wert
   ist die erste Zahl, die im Spieltest falsch sein wird.
4. **Vulkan-Gebäudeschaden hängt an durchgehendem Lavakontakt** — ein einzelner
   Schwall darf ihn nicht still abschalten (10c-Falle, eigener Test).
5. **Geteilte Bolt-Konstanten**: ohne die Parametrisierung aus Teil 4 zieht jede
   Feuerregen-Änderung den Feuerball mit.
6. **Parallelsitzungen** im selben Arbeitsbaum: vor Beginn `git pull`, per Pfad stagen.

## Zu entscheiden (Nutzer)

**Entschieden** (Vorgaben 2026-08-06): Manakurve und Grundrate 0,11 · Förster
0,6/Arbeiter · Ausbildungskosten 0,6/s je aktivem Lager · alle Zauberkosten ·
alle Reichweiten · KI darf Zauber abschalten · Hypnose beendet den Stamm, wenn sie
die letzten Einheiten erwischt · Beten war schon weg.

Ebenfalls entschieden: **Ladeanzeige** nach Original-Vorbild (Teil 7), **Feuerball**
20/10 mit 4 m bzw. 2 m Wirbel, **Feuerregen** vollständig (20 s, 20/10, kein Wirbeln,
Brand, Zufallsintervalle Ø 0,3 s, Zufallsziele, 20 HP Gebäudeschaden je Ball),
**Hypnose** 3 Ladungen, **Schamanin zählt** als Anhänger fürs Mana, **KI-Heuristik**
(Verschwendung vermeiden hat Vorrang, sonst 120-s-Budget).

**Nichts blockiert den Beginn.** Offen ist nur noch eine Sache, und sie steht
absichtlich am Ende der Umsetzungsreihenfolge:

| # | Frage | Stand |
|---|---|---|
| 1 | **Vulkan: Radius 7,0 m / Kratertiefe 1,5 m / Rand bei 0,55 × R** | Nutzer: *„erstmal in Ordnung so, muss ich mir anschauen"* — wird nach dem ersten sichtbaren Ergebnis beurteilt, nicht vorher |

Die Vulkanform ist der einzige Teil, dessen Wirkung man **sehen** muss, um sie zu
bewerten. Deshalb: umsetzen wie beschrieben, im Spiel zeigen, dann die drei Zahlen
drehen — sie sind reine `Balance`-Werte ohne Codeeingriff.
