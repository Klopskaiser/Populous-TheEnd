"""Baut die Spielmodelle der Fahrzeuge aus den gelieferten Rohmodellen.

Aufruf (Blender im Hintergrund, siehe LIESMICH.md):
    blender --background --factory-startup --python fahrzeuge_bauen.py -- <was> [<vorschau-ordner>]
    <was> = katapult | ramme | alle

Eingang:  quelle/siege_engine.glb, quelle/fire_ram.glb (unveraendert, wie geliefert)
Ausgang:  ../../assets/models/units/siege_engine.glb und fire_ram.glb
Protokoll: bau_protokoll.txt neben diesem Skript (der Store-Starter gibt nichts aus).

Was das Spiel erwartet (assets/README.md, Abschnitt Fahrzeuge):
  - Vorderseite +Z, Ursprung am Boden mittig, Meter.
  - Wheel_*  : je Rad ein Node mit Ursprung auf der Achse; das Spiel dreht ihn um X.
  - Arm      : Wurfarm mit Ursprung im Drehbolzen, Ruhelage gespannt; +X hebt die Schale.
  - Stone    : Kind von Arm, wird waehrend des Flugs ausgeblendet.
  - Winch    : Winde, dreht beim Zurueckspannen um X.
  - Flag     : Wimpel in Stammesfarbe.
"""
import bpy
import bmesh
import sys
import os
import math
import traceback
import numpy as np
from mathutils import Vector, Matrix

HIER = os.path.dirname(os.path.abspath(__file__))
QUELLE = os.path.join(HIER, 'quelle')
ZIEL = os.path.normpath(os.path.join(HIER, '..', '..', 'assets', 'models', 'units'))
ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
WAS = ARGS[0] if ARGS else 'alle'
VORSCHAU = ARGS[1] if len(ARGS) > 1 else None

# --- Stellschrauben -----------------------------------------------------------
KATAPULT_MASSSTAB = 1.0     # 1.0 = Raeder 0,59 m, 1,45 m breit, 2,4 m lang
RAMME_MASSSTAB = 1.0        # 1.0 = 2,0 m lang, 1,17 m breit
RAMME_SCHNAUZE_Z = 1.15     # Duesenspitze so weit vor dem Ursprung (FireRam.NOZZLE_OFFSET 1,2)
RAMME_SCHNITT = 0.41        # Schnittebene Rad/Rumpf, Abstand von der Mittelachse (Rohmass)
RAMME_RAD_RADIUS = 0.262    # alles ausserhalb der Ebene bis zu diesem Achsabstand ist Rad
RAMME_RAEDER = ((-0.32, -0.325), (0.685, -0.325))   # Achsen (Laenge, Hoehe) im Rohmodell
SEIL_SCHNITT = 0.8          # Katapult: Hoehe, auf der das Spannseil geteilt wird (Rohmass)
TEXTUR_MAX = 1024

_log = open(os.path.join(HIER, 'bau_protokoll.txt'), 'w', encoding='utf-8')


def log(*teile):
    _log.write(' '.join(str(t) for t in teile) + '\n')
    _log.flush()


# Der Importer legt die Meshdaten Z-oben ab: glTF (x, y, z) -> Blender (x, -z, y).
# Alle Masse in diesem Skript sind im glTF-Rohsystem der Datei notiert.
def zu_gltf(v):
    return Vector((v.x, v.z, -v.y))


def zu_blender(v):
    v = Vector(v)
    return Vector((v.x, -v.z, v.y))


def leeren():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def laden(name):
    bpy.ops.import_scene.gltf(filepath=os.path.join(QUELLE, name))
    bpy.context.view_layer.update()
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def inseln(me):
    """Zusammenhaengende Teile: Insel je Flaeche und Kasten je Insel (glTF-Rohsystem).

    Die Vertices sind an harten Kanten und UV-Naehten doppelt, deshalb wird nach
    Position verschweisst."""
    schluessel = {}
    naht = []
    for v in me.vertices:
        k = (round(v.co.x * 1e4), round(v.co.y * 1e4), round(v.co.z * 1e4))
        naht.append(schluessel.setdefault(k, v.index))
    eltern = list(range(len(me.vertices)))

    def wurzel(x):
        while eltern[x] != x:
            eltern[x] = eltern[eltern[x]]
            x = eltern[x]
        return x

    for p in me.polygons:
        a = wurzel(naht[p.vertices[0]])
        for v in p.vertices[1:]:
            eltern[wurzel(naht[v])] = a
    je_flaeche = []
    kasten = {}
    for p in me.polygons:
        w = wurzel(naht[p.vertices[0]])
        je_flaeche.append(w)
        k = kasten.setdefault(w, [Vector((1e9,) * 3), Vector((-1e9,) * 3), 0])
        k[2] += 1
        for v in p.vertices:
            g = zu_gltf(me.vertices[v].co)
            for i in range(3):
                k[0][i] = min(k[0][i], g[i])
                k[1][i] = max(k[1][i], g[i])
    return je_flaeche, kasten


def teil(obj, flaechen, name):
    """Kopie von obj, die nur die genannten Flaechen behaelt."""
    neu = obj.copy()
    neu.data = obj.data.copy()
    neu.name = name
    neu.data.name = name
    for c in obj.users_collection:
        c.objects.link(neu)
    bm = bmesh.new()
    bm.from_mesh(neu.data)
    weg = [f for f in bm.faces if f.index not in flaechen]
    bmesh.ops.delete(bm, geom=weg, context='FACES')
    bm.to_mesh(neu.data)
    bm.free()
    return neu


def welt_anwenden(objs):
    """Knotentransformationen in die Meshdaten schreiben, Hierarchie aufloesen."""
    bpy.context.view_layer.update()
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.rotation_mode = 'XYZ'     # der Importer setzt Quaternionen
        o.matrix_world = Matrix.Identity(4)
        o.data.transform(mw)
        o.data.update()
    for o in list(bpy.context.scene.objects):
        if o.type != 'MESH':
            bpy.data.objects.remove(o)
    bpy.context.view_layer.update()


def grenzen(objs):
    mn = Vector((1e9,) * 3)
    mx = Vector((-1e9,) * 3)
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
    return mn, mx


def ursprung(o, p):
    """Objektursprung auf den Weltpunkt p legen (o hat sonst Einheitstransformation)."""
    p = Vector(p)
    o.data.transform(Matrix.Translation(-p))
    o.location = p


def anhaengen(kind, eltern):
    kind.parent = eltern
    kind.matrix_parent_inverse = Matrix.Translation(-eltern.location)


def grundfarbe(obj):
    """Pixel der Grundfarbtextur des ersten Materials als (h, w, 4)-Feld."""
    for slot in obj.material_slots:
        mat = slot.material
        if mat is None or mat.node_tree is None:
            continue
        for n in mat.node_tree.nodes:
            if n.type == 'BSDF_PRINCIPLED' and n.inputs['Base Color'].links:
                img = n.inputs['Base Color'].links[0].from_node.image
                w, h = img.size
                a = np.empty(w * h * 4, dtype=np.float32)
                img.pixels.foreach_get(a)
                return a.reshape(h, w, 4)
    return None


def loecher_schliessen(me, ebene_achse, ebene_wert, normale, pixel):
    """Offene Schnittkanten auf der Ebene (Blender-Achse = Wert) mit Flaechen fuellen.

    Die Deckflaechen bekommen einen einzigen UV-Punkt: den dunkelsten Texturpunkt
    am Schnittrand, damit sie als ruhige dunkle Flaeche erscheinen."""
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active
    # Der Importer laesst Vertices an UV-Naehten doppelt: auf der Schnittebene
    # verschweissen, sonst schliesst sich der Schnittrand nicht zu Ringen.
    auf_ebene = [v for v in bm.verts if abs(v.co[ebene_achse] - ebene_wert) < 2e-4]
    bmesh.ops.remove_doubles(bm, verts=auf_ebene, dist=1e-4)
    rand = [e for e in bm.edges if e.is_boundary
            and all(abs(v.co[ebene_achse] - ebene_wert) < 2e-4 for v in e.verts)]
    anzahl = 0
    if rand:
        punkt = None
        dunkel = 1e9
        for e in rand:
            for l in e.link_loops:
                u = l[uv].uv
                if pixel is not None:
                    h, w, _ = pixel.shape
                    f = pixel[int(u.y % 1.0 * h) % h, int(u.x % 1.0 * w) % w, :3]
                    hell = float(f[0] + f[1] + f[2])
                else:
                    hell = 0.0
                if hell < dunkel:
                    dunkel = hell
                    punkt = u.copy()
        res = bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=rand)
        for g in res['geom']:
            if isinstance(g, bmesh.types.BMFace):
                g.normal_update()
                if g.normal.dot(normale) < 0.0:
                    g.normal_flip()
                g.smooth = False
                for l in g.loops:
                    l[uv].uv = punkt
                anzahl += 1
    bm.to_mesh(me)
    bm.free()
    return len(rand), anzahl


def farbmaterial(name, farbe):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*farbe, 1.0)
    bsdf.inputs['Roughness'].default_value = 1.0
    bsdf.inputs['Metallic'].default_value = 0.0
    return mat


def fahne(fuss, hoehe=0.5):
    """Stange mit Wimpel; der Wimpel (Node 'Flag') weht nach hinten (Blender +Y)."""
    fuss = Vector(fuss)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.018, radius2=0.018, depth=hoehe)
    me = bpy.data.meshes.new('FlagPole')
    bm.to_mesh(me)
    bm.free()
    stange = bpy.data.objects.new('FlagPole', me)
    stange.location = fuss + Vector((0.0, 0.0, hoehe / 2))
    me.materials.append(farbmaterial('FlagPole', (0.16, 0.10, 0.06)))
    bpy.context.scene.collection.objects.link(stange)

    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(0.025, 0.36, 0.22), verts=bm.verts)
    me = bpy.data.meshes.new('Flag')
    bm.to_mesh(me)
    bm.free()
    tuch = bpy.data.objects.new('Flag', me)
    tuch.location = fuss + Vector((0.0, 0.18 + 0.018, hoehe - 0.11))
    me.materials.append(farbmaterial('Flag', (0.9, 0.9, 0.9)))
    bpy.context.scene.collection.objects.link(tuch)
    return stange, tuch


def texturen_verkleinern():
    for img in bpy.data.images:
        if img.size[0] > TEXTUR_MAX or img.size[1] > TEXTUR_MAX:
            log('  Textur', img.name, tuple(img.size), '->', TEXTUR_MAX)
            img.scale(TEXTUR_MAX, TEXTUR_MAX)


def ausgeben(datei):
    # Blender bettet in sRGB-JPEGs ein ICC-Profil ein, und Godot 4.7 kann solche
    # JPEGs nicht laden (Modell erscheint weiss). Als "Non-Color" markiert werden
    # dieselben Bytes ohne Profil geschrieben; ob eine Textur sRGB ist, legt in
    # glTF ohnehin das Material fest, nicht die Bilddatei. Reihenfolge beachten:
    # der Farbraumwechsel laedt das Bild neu und verwuerfe eine Verkleinerung.
    for img in bpy.data.images:
        if img.colorspace_settings.name != 'Non-Color':
            img.colorspace_settings.name = 'Non-Color'
    texturen_verkleinern()
    pfad = os.path.join(ZIEL, datei)
    try:
        bpy.ops.export_scene.gltf(filepath=pfad, export_format='GLB', export_yup=True,
                                  export_animations=False, export_image_format='JPEG',
                                  export_jpeg_quality=85)
    except TypeError as fehler:
        log('  Export ohne JPEG-Angaben:', fehler)
        bpy.ops.export_scene.gltf(filepath=pfad, export_format='GLB', export_yup=True)
    log('  geschrieben', pfad, os.path.getsize(pfad), 'Bytes')


def knoten_protokoll():
    for o in sorted(bpy.context.scene.objects, key=lambda x: x.name):
        mn, mx = grenzen([o])
        log('  Knoten %-10s Eltern %-6s Ort (%.3f %.3f %.3f) Groesse (%.3f %.3f %.3f) Flaechen %d' % (
            o.name, o.parent.name if o.parent else '-', *o.matrix_world.translation,
            *(mx - mn), len(o.data.polygons)))


def bilder(praefix, posen, ansichten=None):
    """Vorschaubilder (Workbench) der gebauten Szene in mehreren Posen."""
    if VORSCHAU is None:
        return
    os.makedirs(VORSCHAU, exist_ok=True)
    sc = bpy.context.scene
    objs = [o for o in sc.objects if o.type == 'MESH']
    mn, mx = grenzen(objs)
    mitte = (mn + mx) / 2
    groesse = max(mx - mn)
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'TEXTURE'
    sh.show_cavity = True
    sc.render.resolution_x = 900
    sc.render.resolution_y = 700
    welt = bpy.data.worlds.new('w')
    sc.world = welt
    welt.color = (0.55, 0.6, 0.65)
    kam = bpy.data.objects.new('Kamera', bpy.data.cameras.new('Kamera'))
    sc.collection.objects.link(kam)
    sc.camera = kam
    kam.data.type = 'ORTHO'
    kam.data.ortho_scale = groesse * 1.45
    ansichten = ansichten or {'vl': (35, 25), 'seite': (90, 0), 'hr': (215, 25)}
    for pose, setzen in posen:
        setzen()
        for name, (az, el) in ansichten.items():
            a, e = math.radians(az), math.radians(el)
            d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
            kam.location = mitte + d * groesse * 3
            kam.rotation_euler = (mitte - kam.location).to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(VORSCHAU, '%s_%s_%s.png' % (praefix, pose, name))
            bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(kam)


# --- Katapult -----------------------------------------------------------------

def katapult_gruppe(c, s, material):
    """Bauteil einer Insel aus Kastenmitte c und Kastengroesse s (Rohsystem:
    x Laenge mit der Schale bei +x, y quer, z hoch, Radachsen auf z = 0)."""
    if material == 1:
        # Seile: Wicklung am oberen Querholz (bleibt) und Spannseil an der Winde.
        return 'seil' if c.x < 2.0 else 'spannseil'
    if abs(c.y) > 2.4:
        return 'rad_%s%s' % ('h' if c.x > 0.67 else 'v', 'a' if c.y > 0 else 'b')
    if abs(c.x - 3.94) < 0.15 and abs(c.z) < 0.15 and abs(c.y) < 2.0:
        return 'winde'
    if c.x > 6.0 and s.x < 2.0 and c.z > 0.9:
        return 'stein'
    if s.x > 9.0:
        return 'arm'                                  # Balken
    if c.x > 4.5 and abs(c.y) < 0.5 and c.z > 0.4:
        return 'arm'                                  # Schale, Seilschelle
    if c.x < -3.0 and c.z > 2.0:
        return 'arm'                                  # Gegengewicht
    if abs(c.y) < 0.1 and abs(c.x) < 0.5 and 2.3 < c.z < 2.9:
        return 'arm'                                  # Lagerklotz und Blech am Bolzen
    return 'rumpf'


def katapult_bauen():
    log('Katapult')
    leeren()
    quellen = laden('siege_engine.glb')
    quellen.sort(key=lambda o: -len(o.data.polygons))
    assert len(quellen) == 2, 'erwartet: Holz/Metall-Mesh und Seil-Mesh'
    holz, seil = quellen

    # Spannseil teilen: die Schlinge um den Arm fliegt mit, die Wicklung bleibt.
    bm = bmesh.new()
    bm.from_mesh(seil.data)
    fl = [f for f in bm.faces if zu_gltf(f.calc_center_median()).x > 2.0]
    geom = list({*fl, *(e for f in fl for e in f.edges), *(v for f in fl for v in f.verts)})
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5,
                           plane_co=zu_blender((0, 0, SEIL_SCHNITT)), plane_no=zu_blender((0, 0, 1)))
    bm.to_mesh(seil.data)
    bm.free()

    teile = {}       # Gruppe -> [Objekt, ...]
    marken = {}      # Gruppe -> Kasten (Rohsystem) der groessten Insel
    for nr, obj in enumerate((holz, seil)):
        je_flaeche, kasten = inseln(obj.data)
        log('  Mesh', obj.name, 'Inseln', len(kasten))
        gruppe_je_insel = {}
        for w, (mn, mx, n) in kasten.items():
            g = katapult_gruppe((mn + mx) / 2, mx - mn, nr)
            gruppe_je_insel[w] = g
            if g not in marken or n > marken[g][2]:
                marken[g] = (mn.copy(), mx.copy(), n)
            if g == 'rumpf' and abs(((mn + mx) / 2).z - 2.51) < 0.05 and abs(((mn + mx) / 2).y) > 1.0:
                marken.setdefault('bolzen', []).append((mn + mx) / 2)
            if g == 'rumpf' and (mx - mn).z > 4.0:
                marken.setdefault('staender', []).append((mn.copy(), mx.copy()))
        flaechen = {}
        for p in obj.data.polygons:
            g = gruppe_je_insel[je_flaeche[p.index]]
            if g == 'spannseil':
                hoch = zu_gltf(p.center).z > SEIL_SCHNITT
                g = 'armseil' if hoch else 'seil'
            flaechen.setdefault(g, set()).add(p.index)
        for g, idx in flaechen.items():
            teile.setdefault(g, []).append(teil(obj, idx, g))
            log('    %-10s %5d Flaechen' % (g, len(idx)))
    welt_roh = holz.matrix_world.copy()
    for o in (holz, seil):
        bpy.data.objects.remove(o)
    alle = [o for liste in teile.values() for o in liste]
    welt_anwenden(alle)

    def welt(p):
        return welt_roh @ zu_blender(p)

    def mitte(g):
        return (marken[g][0] + marken[g][1]) / 2

    # Ursprung: Mitte der vier Radachsen, auf dem Boden. Vorn (Gegengewicht) = -Y.
    raeder = [g for g in teile if g.startswith('rad_')]
    assert len(raeder) == 4, raeder
    achsen = [welt(mitte(g)) for g in raeder]
    zentrum = sum(achsen, Vector()) / 4
    mn, mx = grenzen(alle)
    zentrum.z = mn.z
    drehen = welt(mitte('stein')).y < zentrum.y
    log('  Zentrum', tuple(zentrum), 'um 180 Grad gedreht:', drehen)
    g_mat = Matrix.Scale(KATAPULT_MASSSTAB, 4) @ (Matrix.Rotation(math.pi, 4, 'Z') if drehen else Matrix.Identity(4)) \
        @ Matrix.Translation(-zentrum)
    for o in alle:
        o.data.transform(g_mat)

    def ziel(p):
        return g_mat @ welt(p)

    rumpf = teile['rumpf'][0]
    rumpf.name = 'Body'
    teile['seil'][0].name = 'BodyRope'
    anhaengen(teile['seil'][0], rumpf)

    # Wurfarm: Drehpunkt ist der Bolzen durch die beiden Staender.
    bolzen = sum(marken['bolzen'], Vector()) / len(marken['bolzen'])
    bolzen.y = 0.0
    arm = teile['arm'][0]
    arm.name = 'Arm'
    ursprung(arm, ziel(bolzen))
    armseil = teile['armseil'][0]
    armseil.name = 'ArmRope'
    anhaengen(armseil, arm)
    stein = teile['stein'][0]
    stein.name = 'Stone'
    ursprung(stein, ziel(mitte('stein')))
    anhaengen(stein, arm)

    winde = teile['winde'][0]
    winde.name = 'Winch'
    w = mitte('winde')
    ursprung(winde, ziel((w.x, 0.0, w.z)))

    for g in raeder:
        o = teile[g][0]
        p = ziel(mitte(g))
        o.name = 'Wheel_%s%s' % ('F' if p.y < 0 else 'R', 'L' if p.x > 0 else 'R')
        ursprung(o, p)
        log('  %s Achse (%.3f %.3f %.3f) Radius %.3f' % (o.name, *p, (marken[g][1].z - marken[g][0].z) / 2
                                                         * 0.198 * KATAPULT_MASSSTAB))

    # Wimpel auf dem Kopf eines Staenders (aussen, der Arm schwingt in der Mitte).
    st = max(marken['staender'], key=lambda k: ziel((k[0] + k[1]) / 2).x)
    kopf = ziel(((st[0].x + st[1].x) / 2, (st[0].y + st[1].y) / 2, st[1].z))
    stange, tuch = fahne(kopf - Vector((0, 0, 0.02)), 0.5)
    log('  Bolzen', tuple(round(v, 3) for v in arm.location), 'Wimpel', tuple(round(v, 3) for v in kopf))

    bpy.context.view_layer.update()
    knoten_protokoll()
    ausgeben('siege_engine.glb')

    def ruhe():
        arm.rotation_euler.x = 0.0
        stein.hide_render = False

    def wurf():
        arm.rotation_euler.x = 1.15
        stein.hide_render = True
        for o in bpy.context.scene.objects:
            if o.name.startswith('Wheel'):
                o.rotation_euler.x = 0.7
        winde.rotation_euler.x = 0.9

    bilder('katapult', [('ruhe', ruhe), ('wurf', wurf)])


# --- Feuerramme ---------------------------------------------------------------

def ramme_bauen():
    log('Feuerramme')
    leeren()
    quellen = laden('fire_ram.glb')
    assert len(quellen) == 1
    roh = quellen[0]
    pixel = grundfarbe(roh)

    # Rohsystem: x Laenge (Kopf bei -x), y hoch, z quer. Die Raeder haengen fest
    # am Rumpf (ein einziges verschmolzenes Netz) und werden an zwei Ebenen
    # knapp ausserhalb des Rahmens abgeschnitten.
    bm = bmesh.new()
    bm.from_mesh(roh.data)
    log('  offene Kanten im Rohmodell:', sum(1 for e in bm.edges if e.is_boundary))
    for seite in (1, -1):
        fl = [f for f in bm.faces if all(zu_gltf(v.co).y < 0.02 for v in f.verts)]
        geom = list({*fl, *(e for f in fl for e in f.edges), *(v for f in fl for v in f.verts)})
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5,
                               plane_co=zu_blender((0, 0, seite * RAMME_SCHNITT)),
                               plane_no=zu_blender((0, 0, seite)))
    bm.to_mesh(roh.data)
    bm.free()

    flaechen = {'rumpf': set()}
    for p in roh.data.polygons:
        c = zu_gltf(p.center)
        g = 'rumpf'
        if abs(c.z) > RAMME_SCHNITT and c.y < 0.02:
            for nr, (ax, ay) in enumerate(RAMME_RAEDER):
                if math.hypot(c.x - ax, c.y - ay) < RAMME_RAD_RADIUS:
                    g = 'rad_%d%s' % (nr, 'a' if c.z > 0 else 'b')
        flaechen.setdefault(g, set()).add(p.index)
    teile = {g: teil(roh, idx, g) for g, idx in flaechen.items()}
    for g, idx in flaechen.items():
        log('    %-8s %5d Flaechen' % (g, len(idx)))

    # Schnittflaechen schliessen (im Rohsystem: Ebene z = +-SCHNITT -> Blender y).
    for g, o in teile.items():
        for seite in (1, -1):
            if g != 'rumpf' and (g.endswith('a')) != (seite > 0):
                continue
            aussen = zu_blender((0, 0, seite))
            normale = aussen if g == 'rumpf' else -aussen
            rand, neu = loecher_schliessen(o.data, 1, -seite * RAMME_SCHNITT, normale, pixel)
            log('    %-8s Seite %+d: %d Randkanten, %d Deckflaechen' % (g, seite, rand, neu))

    achsen = {}
    for g, o in teile.items():
        if g.startswith('rad_'):
            mn = Vector((1e9,) * 3)
            mx = Vector((-1e9,) * 3)
            for v in o.data.vertices:
                p = zu_gltf(v.co)
                for i in range(3):
                    mn[i] = min(mn[i], p[i])
                    mx[i] = max(mx[i], p[i])
            achsen[g] = ((mn + mx) / 2, mx - mn)
            log('    %-8s Mitte (%.3f %.3f %.3f) Groesse (%.3f %.3f %.3f)' % (g, *achsen[g][0], *achsen[g][1]))
    kopf_roh = min((zu_gltf(v.co) for v in roh.data.vertices), key=lambda p: p.x)
    welt_roh = roh.matrix_world.copy()
    bpy.data.objects.remove(roh)
    alle = list(teile.values())
    welt_anwenden(alle)

    def welt(p):
        return welt_roh @ zu_blender(p)

    mn, mx = grenzen(alle)
    drehen = welt(kopf_roh).y > (mn.y + mx.y) / 2      # Kopf muss nach -Y (= +Z im Spiel)
    vorn = mx.y if drehen else mn.y
    zentrum = Vector(((mn.x + mx.x) / 2, vorn, mn.z))
    g_mat = Matrix.Translation((0.0, -RAMME_SCHNAUZE_Z, 0.0)) @ Matrix.Scale(RAMME_MASSSTAB, 4) \
        @ (Matrix.Rotation(math.pi, 4, 'Z') if drehen else Matrix.Identity(4)) @ Matrix.Translation(-zentrum)
    log('  Zentrum', tuple(zentrum), 'um 180 Grad gedreht:', drehen)
    for o in alle:
        o.data.transform(g_mat)

    def ziel(p):
        return g_mat @ welt(p)

    rumpf = teile['rumpf']
    rumpf.name = 'Body'
    for g, (c, s) in achsen.items():
        o = teile[g]
        p = ziel(c)
        o.name = 'Wheel_%s%s' % ('F' if p.y < 0 else 'R', 'L' if p.x > 0 else 'R')
        ursprung(o, p)
        log('  %s Achse (%.3f %.3f %.3f) Radius %.3f' % (o.name, *p, max(s.x, s.y) / 2 * RAMME_MASSSTAB))

    # Wimpel auf dem Kopf eines der beiden Pfosten des Buegels.
    hoechster = max((v.co for v in rumpf.data.vertices if v.co.x > 0.3), key=lambda c: c.z)
    fahne(Vector(hoechster) - Vector((0, 0, 0.03)), 0.45)

    bpy.context.view_layer.update()
    knoten_protokoll()
    ausgeben('fire_ram.glb')

    raeder = [o for o in bpy.context.scene.objects if o.name.startswith('Wheel')]

    def pose(winkel, abstand=0.0):
        def setzen():
            for o in raeder:
                o.rotation_euler.x = winkel
                o.delta_location.x = abstand * (1 if o.location.x > 0 else -1)
        return setzen

    bilder('ramme', [('ruhe', pose(0.0)), ('dreh1', pose(0.9)), ('dreh2', pose(2.4)), ('offen', pose(0.0, 0.3))],
           {'vl': (35, 25), 'seite': (90, 0), 'hr': (215, 25), 'unten': (60, -35)})


try:
    os.makedirs(ZIEL, exist_ok=True)
    if WAS in ('katapult', 'alle'):
        katapult_bauen()
    if WAS in ('ramme', 'alle'):
        ramme_bauen()
    log('fertig')
except Exception:
    log(traceback.format_exc())
_log.close()
