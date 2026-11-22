"""Gleicht ein Spritesheet in Größe und Stand an die Ruhepose der Einheit an.

Anlass: Im gelieferten idle.png des Feuerkriegers war die Figur rund 9 % größer
gezeichnet als in stand.png und throw.png und stand in den Seitenansichten 6 px
weiter links. Beim Wechsel Ruhepose -> Idle wuchs und sprang sie.

Aufruf:
    python sheet_angleichen.py <quellordner> <zielordner> <anim> [bezug=stand] [massstab]

    <quellordner>  Ordner der Einheit mit manifest.json und den PNGs, wie geliefert
    <zielordner>   dorthin wird <anim>.png geschrieben (assets/units/<einheit>)
    <anim>         das Sheet, das angeglichen wird, z. B. idle
    bezug          das Sheet, dessen erste Spalte die richtige Größe hat
    massstab       fester Massstab statt des gemessenen, z. B. 0.915

Vorgehen: Frame 1 jeder Zeile wird gegen den Bezugsframe derselben Zeile gelegt.
Gesucht wird EIN Massstab für das ganze Sheet (die Zeichnung ist einheitlich zu
groß) und je Zeile eine waagerechte Verschiebung, bei denen sich die Umrisse am
besten decken. Skaliert wird um den Fußpunkt (Zellmitte unten), dort steht die
Einheit im Spiel. Voraussetzung: das Sheet beginnt in der Ruhepose (README,
Abschnitt "Die Ruhepose").

Braucht Pillow.
"""
import json
import os
import sys

from PIL import Image

SCHWELLE = 128          # das Spiel verwirft Alpha unter 0,5


def zellen(bild, fw, fh):
    return [[bild.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
             for c in range(bild.width // fw)] for r in range(bild.height // fh)]


def versetzt(zelle, massstab, dx, fw, fh):
    """Zelle um den Fußpunkt skaliert und um dx Pixel verschoben (vormultipliziert,
    damit an den Rändern kein dunkler Saum entsteht)."""
    tx = fw / 2 - fw / 2 * massstab + dx
    ty = fh - fh * massstab
    vor = zelle.convert('RGBa')
    aus = vor.transform((fw, fh), Image.AFFINE,
                        (1 / massstab, 0, -tx / massstab, 0, 1 / massstab, -ty / massstab),
                        resample=Image.BICUBIC)
    return aus.convert('RGBA')


def maske(zelle):
    return zelle.getchannel('A').point(lambda v: 255 if v >= SCHWELLE else 0).tobytes()


def deckung(a, b):
    gemeinsam = sum(1 for x, y in zip(a, b) if x and y)
    gesamt = sum(1 for x, y in zip(a, b) if x or y)
    return gemeinsam / gesamt if gesamt else 0.0


def beste_verschiebung(zelle, bezug, massstab, fw, fh):
    bestes = (0.0, 0.0)
    for halbe in range(-20, 21):
        dx = halbe / 2
        d = deckung(maske(versetzt(zelle, massstab, dx, fw, fh)), bezug)
        if d > bestes[0]:
            bestes = (d, dx)
    return bestes


def hoehe(zelle):
    kasten = zelle.getchannel('A').point(lambda v: 255 if v >= SCHWELLE else 0).getbbox()
    return 0 if kasten is None else kasten[3] - kasten[1]


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    quelle, ziel, anim = sys.argv[1], sys.argv[2], sys.argv[3]
    bezug_name = sys.argv[4] if len(sys.argv) > 4 else 'stand'
    fest = float(sys.argv[5]) if len(sys.argv) > 5 else None
    with open(os.path.join(quelle, 'manifest.json'), encoding='utf-8') as f:
        manifest = json.load(f)
    fw, fh = manifest['frame_width'], manifest['frame_height']
    sheet = Image.open(os.path.join(quelle, anim + '.png')).convert('RGBA')
    bezug = Image.open(os.path.join(quelle, bezug_name + '.png')).convert('RGBA')
    if sheet.width % fw or sheet.height % fh:
        sys.exit('%s.png ist %dx%d und kein Vielfaches der Zelle %dx%d' % (anim, sheet.width, sheet.height, fw, fh))
    if sheet.height != bezug.height:
        sys.exit('%s und %s haben verschieden viele Zeilen' % (anim, bezug_name))
    reihen = zellen(sheet, fw, fh)
    soll = [maske(z[0]) for z in zellen(bezug, fw, fh)]

    if fest is None:
        # Ein Massstab für alle Zeilen: der mit der besten mittleren Deckung.
        bester = (0.0, 1.0)
        for tausendstel in range(850, 1101, 5):
            s = tausendstel / 1000
            mittel = sum(beste_verschiebung(reihen[r][0], soll[r], s, fw, fh)[0]
                         for r in range(len(reihen))) / len(reihen)
            if mittel > bester[0]:
                bester = (mittel, s)
        massstab = bester[1]
    else:
        massstab = fest
    print('%s -> %s: Massstab %.3f' % (anim, bezug_name, massstab))

    aus = Image.new('RGBA', sheet.size, (0, 0, 0, 0))
    for r, reihe in enumerate(reihen):
        d, dx = beste_verschiebung(reihe[0], soll[r], massstab, fw, fh)
        vorher = hoehe(reihe[0])
        for c, zelle in enumerate(reihe):
            neu = versetzt(zelle, massstab, dx, fw, fh)
            rand = neu.getchannel('A').point(lambda v: 255 if v >= SCHWELLE else 0).getbbox()
            if rand is not None and (rand[0] == 0 or rand[2] == fw or rand[1] == 0):
                print('  Achtung: Zeile %d Frame %d stößt an den Zellenrand' % (r + 1, c + 1))
            aus.paste(neu, (c * fw, r * fh))
        print('  Zeile %d: Verschiebung %+.1f px, Deckung mit %s %.1f %%, Höhe Frame 1 %d -> %d px (Bezug %d)' % (
            r + 1, dx, bezug_name, d * 100, vorher, hoehe(versetzt(reihe[0], massstab, dx, fw, fh)),
            hoehe(zellen(bezug, fw, fh)[r][0])))
    os.makedirs(ziel, exist_ok=True)
    aus.save(os.path.join(ziel, anim + '.png'))
    print('geschrieben', os.path.join(ziel, anim + '.png'))


if __name__ == '__main__':
    main()
