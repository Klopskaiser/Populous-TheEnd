"""Prüft gelieferte Spritesheets einer Einheit gegen die Regeln des Spiels.

Gedacht für Sheets aus einem Bildgenerator: die stimmen in Raster, Größe und
Stand oft nicht miteinander überein, und das Spiel schneidet Frames unverändert
aus. Jede Abweichung ist im Spiel ein Sprung oder ein Wachsen der Figur.

Aufruf:
    python sheets_pruefen.py <ordner> [<ordner> ...]

    <ordner>  Ordner EINER Einheit (mit manifest.json; der Ordnername ist die
              Einheit: brave, warrior, firewarrior, preacher, shaman) oder ein
              Ordner, der solche Ordner enthält.

Geprüft wird (FEHLER = im Spiel sichtbar falsch, HINWEIS = ansehen):
  - Raster: Breite und Höhe sind Vielfache der Zelle, 8, 5 oder 1 Zeile
  - Größe: Figur in Frame 1 so groß wie in der Ruhepose (stand, sonst idle Frame 1)
  - Stand: Figur an derselben Stelle der Zelle wie in der Ruhepose
  - Anfang: Sheets, die aus der Ruhepose heraus spielen, beginnen in ihr
  - Ansichten: die Zeilen zeigen wirklich verschiedene Blickrichtungen
  - Rand: keine Figur stößt oben oder seitlich an den Zellenrand, kein Frame ist leer
  - Takt: Schlag- und Wurfzyklen füllen genau ihre Abklingzeit (Frames / fps)
  - Vollständigkeit: welche Animationen der Einheit fehlen

Regeln: assets/README.md, Abschnitt "Einheiten-Spritesheets". Braucht Pillow.
"""
import json
import os
import sys

from PIL import Image, ImageChops

SCHWELLE = 128                      # das Spiel verwirft Alpha unter 0,5
ANSICHTEN_8 = ['front', 'back', 'right', 'left', 'front_right', 'front_left', 'back_right', 'back_left']
ANSICHTEN_5 = ['front', 'back', 'right', 'front_right', 'back_right']
LIEGEND = ('airborne', 'dead_back', 'dead_front')
# Sheets, die aus der Ruhepose heraus gespielt werden: Frame 1 muss sie sein.
AUS_DER_RUHE = ('idle', 'punch', 'kick', 'shove', 'throw', 'cast', 'attack', 'jump')
# Sheets mit aufrechter Figur: Größe und Stand werden gegen die Ruhepose gemessen.
AUFRECHT = AUS_DER_RUHE + ('walk', 'carry', 'carry_walk')
# Zyklusdauer in Sekunden, die das Spiel erwartet (Unit.ATTACK_COOLDOWN,
# Balance.FIREWARRIOR_FIRE_COOLDOWN).
TAKT = {'punch': 0.8, 'kick': 0.8, 'shove': 0.8, 'throw': 1.5}
ALLE = ['stand', 'idle', 'walk', 'sit', 'roll', 'airborne', 'dead_back', 'dead_front', 'drown']
JE_EINHEIT = {
    'brave': ALLE + ['punch', 'kick', 'shove', 'attack', 'jump', 'carry', 'carry_walk'],
    'warrior': ALLE + ['punch', 'kick'],
    'firewarrior': ALLE + ['throw', 'kick', 'shove'],
    'preacher': ALLE + ['cast', 'punch', 'shove'],
    'shaman': ALLE + ['cast', 'punch', 'kick', 'shove'],
}
BEKANNT = set(sum(JE_EINHEIT.values(), []))
GROESSE_TOLERANZ = 0.035            # Frame 1 gegen die Ruhepose
GEHEN_TOLERANZ = (-0.10, 0.035)     # im Gehen ist die Figur etwas niedriger
STAND_TOLERANZ = 2.5                # Pixel gegen die Ruhepose
RUHE_DECKUNG = 0.85                 # ab dieser Deckung gilt Frame 1 als Ruhepose


def maske(zelle):
    return zelle.getchannel('A').point(lambda v: 255 if v >= SCHWELLE else 0)


def kasten(zelle):
    return maske(zelle).getbbox()


def deckung_masken(a, b):
    gemeinsam = ImageChops.multiply(a, b).histogram()[255]
    gesamt = ImageChops.lighter(a, b).histogram()[255]
    return gemeinsam / gesamt if gesamt else 1.0


def deckung(a, b):
    return deckung_masken(maske(a), maske(b))


def beste_lage(zelle, bezug):
    """Massstab und Verschiebung, mit denen sich die Zelle am besten mit dem
    Bezug deckt (skaliert um den Fußpunkt): (Deckung, Massstab, dx)."""
    fw, fh = zelle.size
    soll = maske(bezug)
    bestes = (0.0, 1.0, 0)
    for hundertstel in range(86, 115, 2):
        s = hundertstel / 100
        w, h = max(1, round(fw * s)), max(1, round(fh * s))
        klein = maske(zelle if s == 1.0 else zelle.resize((w, h), Image.BILINEAR))
        for dx in range(-9, 10):
            flaeche = Image.new('L', (fw, fh), 0)
            flaeche.paste(klein, ((fw - w) // 2 + dx, fh - h))
            d = deckung_masken(flaeche, soll)
            if d > bestes[0]:
                bestes = (d, s, dx)
    return bestes


def ansichten(zeilen):
    return {8: ANSICHTEN_8, 5: ANSICHTEN_5}.get(zeilen)


def einheit_pruefen(ordner):
    einheit = os.path.basename(os.path.normpath(ordner))
    fehler, hinweise = [], []
    with open(os.path.join(ordner, 'manifest.json'), encoding='utf-8') as f:
        manifest = json.load(f)
    fw, fh = manifest.get('frame_width', 0), manifest.get('frame_height', 0)
    if fw <= 0 or fh <= 0:
        return einheit, ['manifest.json ohne frame_width / frame_height'], []
    if fw > 64 or fh > 96:
        fehler.append('Zelle %dx%d ist größer als 64x96' % (fw, fh))
    fps = {k: v.get('fps') for k, v in manifest.get('anims', {}).items()}

    # Sheets laden und in Zellen schneiden.
    sheets = {}
    mehrzeilig = []
    for datei in sorted(os.listdir(ordner)):
        name, endung = os.path.splitext(datei)
        if endung.lower() != '.png':
            if endung.lower() not in ('.json', '.import'):
                hinweise.append('%s gehört nicht ins Spiel' % datei)
            elif endung.lower() == '.import' and not os.path.isfile(os.path.join(ordner, name)):
                hinweise.append('%s ohne die Bilddatei dazu' % datei)
            continue
        if name.endswith('_mask'):
            continue
        bild = Image.open(os.path.join(ordner, datei)).convert('RGBA')
        if name not in BEKANNT:
            hinweise.append('%s: diese Animation kennt das Spiel nicht' % datei)
            continue
        if bild.width % fw or bild.height % fh:
            teiler = [n for n in range(1, 400) if bild.width % n == 0 and abs(bild.width / n - fw) <= 8]
            passt = ', '.join('%d Frames zu %d px' % (n, bild.width // n) for n in teiler)
            fehler.append('%s: %dx%d ist kein Vielfaches der Zelle %dx%d%s' % (
                datei, bild.width, bild.height, fw, fh, ' (aufgehen würde: %s)' % passt if passt else ''))
            if teiler and bild.height % fh == 0 and bild.height // fh >= 5:
                b = bild.width // teiler[0]
                erste = [bild.crop((0, r * fh, b, (r + 1) * fh)) for r in range(3)]
                if deckung(erste[0], erste[1]) > 0.97 and deckung(erste[0], erste[2]) > 0.97:
                    fehler.append('%s: alle Zeilen zeigen dieselbe Ansicht' % datei)
            continue
        zeilen, spalten = bild.height // fh, bild.width // fw
        if name in LIEGEND:
            if zeilen != 1:
                mehrzeilig.append(datei)
            namen = ['zeile1'] + ['-'] * (zeilen - 1)
        else:
            namen = ansichten(zeilen)
            if namen is None and zeilen == 1:
                namen = ['alle']
            if namen is None:
                fehler.append('%s: %d Zeilen, erlaubt sind 8, 5 oder 1' % (datei, zeilen))
                continue
        sheets[name] = {n: [bild.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh)) for c in range(spalten)]
                        for r, n in enumerate(namen) if n != '-'}
        maskendatei = os.path.join(ordner, name + '_mask.png')
        if os.path.isfile(maskendatei) and Image.open(maskendatei).size != bild.size:
            fehler.append('%s_mask.png hat eine andere Größe als %s' % (name, datei))

    # Bezug: die Ruhepose je Ansicht.
    bezug_name = 'stand' if 'stand' in sheets else ('idle' if 'idle' in sheets else None)
    bezug = {n: z[0] for n, z in sheets[bezug_name].items()} if bezug_name else {}
    if bezug_name is None:
        hinweise.append('weder stand noch idle vorhanden: Größe und Stand lassen sich nicht messen')

    for name, je_ansicht in sheets.items():
        datei = name + '.png'
        # Leere Frames, Figur am Zellenrand.
        am_rand = 0
        for n, zellen in je_ansicht.items():
            for c, zelle in enumerate(zellen):
                k = kasten(zelle)
                if k is None:
                    fehler.append('%s: %s Frame %d ist leer' % (datei, n, c + 1))
                elif name not in LIEGEND and (k[0] == 0 or k[2] == fw or k[1] == 0):
                    am_rand += 1
        if am_rand:
            hinweise.append('%s: in %d von %d Frames stößt die Figur oben oder seitlich an den Zellenrand (abgeschnitten?)' % (
                datei, am_rand, sum(len(z) for z in je_ansicht.values())))
        # Zeigen die Zeilen verschiedene Ansichten?
        if len(je_ansicht) >= 5:
            vorn = je_ansicht['front'][0]
            if deckung(vorn, je_ansicht['right'][0]) > 0.97 and deckung(vorn, je_ansicht['back'][0]) > 0.97:
                fehler.append('%s: alle Zeilen zeigen dieselbe Ansicht' % datei)
        # Takt.
        if name in TAKT:
            frames = len(next(iter(je_ansicht.values())))
            rate = fps.get(name)
            if rate is None:
                hinweise.append('%s: kein fps im Manifest; für %.1f s Zyklus wären es %.2f' % (datei, TAKT[name], frames / TAKT[name]))
            elif abs(frames / rate - TAKT[name]) > 0.02:
                fehler.append('%s: %d Frames bei %g fps = %.2f s, das Spiel erwartet %.1f s (fps %.2f)' % (
                    datei, frames, rate, frames / rate, TAKT[name], frames / TAKT[name]))
        if name not in AUFRECHT or name == bezug_name or not bezug:
            continue
        # Größe und Stand lassen sich nur dort messen, wo Frame 1 die Ruhepose
        # ist: dann gibt es einen Massstab und eine Verschiebung, mit denen sich
        # beide Umrisse decken. Im Gehen gibt es die Pose nicht, dort zählt nur
        # die Höhe der Figur (als Hinweis).
        zu_gross, versetzt, anders, gehen = [], [], [], []
        for n, zellen in je_ansicht.items():
            if n not in bezug or kasten(bezug[n]) is None or kasten(zellen[0]) is None:
                continue
            soll = kasten(bezug[n])
            if name not in AUS_DER_RUHE:
                hoehen = sorted(kasten(z)[3] - kasten(z)[1] for z in zellen if kasten(z))
                ab = hoehen[len(hoehen) // 2] / (soll[3] - soll[1]) - 1.0
                if not GEHEN_TOLERANZ[0] <= ab <= GEHEN_TOLERANZ[1]:
                    gehen.append('%s %+.0f %%' % (n, ab * 100))
                continue
            d, s, dx = beste_lage(zellen[0], bezug[n])
            if d < RUHE_DECKUNG:
                anders.append(n)
                continue
            if abs(1.0 / s - 1.0) > GROESSE_TOLERANZ:
                zu_gross.append('%s %+.0f %%' % (n, (1.0 / s - 1.0) * 100))
            dy = kasten(zellen[0])[3] - soll[3]
            if abs(dx) > STAND_TOLERANZ or abs(dy) > STAND_TOLERANZ:
                versetzt.append('%s %+d/%+d px' % (n, -dx, dy))
        if zu_gross:
            fehler.append('%s: Figur anders groß als in %s (%s)' % (datei, bezug_name, ', '.join(zu_gross)))
        if versetzt:
            fehler.append('%s: Figur steht in Frame 1 woanders als in %s, rechts/unten (%s)' % (datei, bezug_name, ', '.join(versetzt)))
        if anders:
            wo = 'alle Ansichten' if len(anders) == len(je_ansicht) else ', '.join(anders)
            hinweise.append('%s: Frame 1 ist nicht die Ruhepose (%s); Größe und Stand dort nicht messbar' % (datei, wo))
        if gehen:
            hinweise.append('%s: Figur anders hoch als in %s (%s)' % (datei, bezug_name, ', '.join(gehen)))

    # Vollständigkeit.
    if mehrzeilig:
        hinweise.append('%s: mehrere Zeilen, das Spiel nimmt bei liegenden Posen nur Zeile 1' % ', '.join(mehrzeilig))
    if ('dead_back' in sheets) != ('dead_front' in sheets):
        fehler.append('nur eine der beiden Leichen vorhanden: das Spiel nimmt dann für beide den Platzhalter')
    if 'dead_back' in fps or 'dead_front' in fps:
        hinweise.append('manifest.json: fps für die Leichen gehört unter "dead", nicht "dead_back"/"dead_front"')
    fehlt = [a for a in JE_EINHEIT.get(einheit, []) if a not in sheets]
    if fehlt:
        hinweise.append('fehlt (Platzhalter im Spiel): ' + ', '.join(fehlt))
    return einheit, fehler, hinweise


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    ordner = []
    for pfad in sys.argv[1:]:
        if os.path.isfile(os.path.join(pfad, 'manifest.json')):
            ordner.append(pfad)
        else:
            ordner += [os.path.join(pfad, d) for d in sorted(os.listdir(pfad))
                       if os.path.isfile(os.path.join(pfad, d, 'manifest.json'))]
    schlecht = 0
    for o in ordner:
        einheit, fehler, hinweise = einheit_pruefen(o)
        print('== %s (%s)' % (einheit, o))
        for zeile in fehler:
            print('  FEHLER   ' + zeile)
        for zeile in hinweise:
            print('  HINWEIS  ' + zeile)
        if not fehler and not hinweise:
            print('  in Ordnung')
        schlecht += len(fehler)
    sys.exit(1 if schlecht else 0)


if __name__ == '__main__':
    main()
