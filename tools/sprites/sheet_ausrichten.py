"""Skaliert ein Spritesheet und richtet die Figur in jeder Zelle waagerecht aus.

Für Sheets aus dem Bildgenerator, deren Figur zu groß ist oder in der Zelle hin
und her wandert (Brave: 94 px hoch statt 84 wie der Feuerkrieger, Rückenansicht
beim Gehen 13 px links neben der Mitte). Anders als sheet_angleichen.py braucht
es keine Ruhepose als Bezug.

Aufruf:
    python sheet_ausrichten.py <quelle.png> <ziel.png> <massstab> [frame|zeile] [--stand <stand.png> fuss|schmal] [--beginn]

    massstab  z. B. 0.894 (94 -> 84 px); skaliert um den Fußpunkt (Zellmitte unten)
    frame     jeder Frame wird einzeln ausgerichtet (Gehen: die Figur soll auf
              der Stelle gehen und nicht wandern)          (Voreinstellung)
    zeile     eine Verschiebung je Zeile, aus Frame 1 (Schlag: der Körper darf
              sich im Schlag bewegen, Frame 1 steht mittig)
    --stand   schreibt zusätzlich eine Ruhepose, eine Spalte: je Zeile der Frame
              mit dem engsten Fußstand (fuss) oder der schmalsten Figur (schmal,
              z. B. die Deckung im Schlag). Notbehelf, solange kein echtes
              stand.png geliefert ist.
    --beginn  dreht jede Zeile so, dass sie mit diesem Frame beginnt (Schlag-
              und Idle-Sheets müssen in der Ruhepose beginnen)

Ausgerichtet wird die Mitte des Kopfes (oberste 15 % der Figur) auf die
Zellmitte; der Kopf ist beim Gehen und Stehen das ruhigste Teil der Figur.
Zellgröße 64 x 96 px. Braucht Pillow.
"""
import sys

from PIL import Image

FW, FH = 64, 96
SCHWELLE = 128


def maske(zelle):
    return zelle.getchannel('A').point(lambda v: 255 if v >= SCHWELLE else 0)


def kopfmitte(zelle):
    m = maske(zelle)
    k = m.getbbox()
    if k is None:
        return None
    unten = k[1] + max(4, round((k[3] - k[1]) * 0.15))
    daten = m.crop((0, k[1], FW, unten)).tobytes()
    xs = [i % FW for i, v in enumerate(daten) if v]
    return sum(xs) / len(xs)


def fussbreite(zelle):
    m = maske(zelle)
    k = m.getbbox()
    if k is None:
        return 999
    return (m.crop((0, k[3] - 12, FW, k[3])).getbbox() or (0, 0, 999, 0))[2] - \
        (m.crop((0, k[3] - 12, FW, k[3])).getbbox() or (0, 0, 0, 0))[0]


def breite(zelle):
    k = maske(zelle).getbbox()
    return 999 if k is None else k[2] - k[0]


def skaliert(zelle, s):
    """Um den Fußpunkt skaliert, vormultipliziert (kein dunkler Saum)."""
    tx, ty = FW / 2 - FW / 2 * s, FH - FH * s
    return zelle.convert('RGBa').transform(
        (FW, FH), Image.AFFINE, (1 / s, 0, -tx / s, 0, 1 / s, -ty / s),
        resample=Image.BICUBIC).convert('RGBA')


def verschoben(zelle, dx):
    aus = Image.new('RGBA', (FW, FH), (0, 0, 0, 0))
    aus.paste(zelle, (round(dx), 0))
    return aus


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    stand, art = None, 'fuss'
    if '--stand' in sys.argv:
        i = sys.argv.index('--stand')
        stand, art = sys.argv[i + 1], sys.argv[i + 2]
        args.remove(stand)
        args.remove(art)
    beginn = '--beginn' in sys.argv
    if len(args) < 3:
        sys.exit(__doc__)
    quelle, ziel, s = args[0], args[1], float(args[2])
    modus = args[3] if len(args) > 3 else 'frame'
    bild = Image.open(quelle).convert('RGBA')
    if bild.width % FW or bild.height % FH:
        sys.exit('%s ist %dx%d, kein Vielfaches von %dx%d' % (quelle, bild.width, bild.height, FW, FH))
    spalten, zeilen = bild.width // FW, bild.height // FH
    aus = Image.new('RGBA', bild.size, (0, 0, 0, 0))
    ruhe = Image.new('RGBA', (FW, bild.height), (0, 0, 0, 0))
    for r in range(zeilen):
        reihe = [skaliert(bild.crop((c * FW, r * FH, (c + 1) * FW, (r + 1) * FH)), s) for c in range(spalten)]
        if modus == 'zeile':
            dxs = [FW / 2 - (kopfmitte(reihe[0]) or FW / 2)] * spalten
        else:
            dxs = [FW / 2 - (kopfmitte(z) or FW / 2) for z in reihe]
        reihe = [verschoben(z, dx) for z, dx in zip(reihe, dxs)]
        mass = fussbreite if art == 'fuss' else breite
        eng = min(range(spalten), key=lambda c: mass(reihe[c]))
        ruhe.paste(reihe[eng], (0, r * FH))
        if beginn:
            reihe = reihe[eng:] + reihe[:eng]
        for c, z in enumerate(reihe):
            aus.paste(z, (c * FW, r * FH))
        print('  Zeile %d: Verschiebung %s px%s' % (
            r + 1, ' '.join('%+.0f' % d for d in dxs), ', Ruhepose aus Frame %d' % (eng + 1) if stand else ''))
    aus.save(ziel)
    print('geschrieben', ziel)
    if stand:
        ruhe.save(stand)
        print('geschrieben', stand)


if __name__ == '__main__':
    main()
