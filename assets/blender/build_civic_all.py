# -*- coding: utf-8 -*-
"""
build_civic_all — reconstruit tout (intérieur, conducteur, extérieur), vérifie, rend, sauvegarde, exporte.

Usage (Blender > Scripting > Run Script, ou via MCP) :
    import build_civic_all; build_civic_all.main()              # tout
    build_civic_all.main(render=False, export=False)            # reconstruction seule
Modules : civic_dims (cotes), civic_lib (helpers), civic_materials, build_civic_interior / _driver / _exterior.
Sorties : assets/blender/civic_interior.blend, assets/models/civic_{interior,driver,exterior}.glb, assets/blender/renders/*.png
"""
import bpy, os, sys, importlib, time

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else r"C:\Users\victo\Documents\nouveau-projet-de-jeu\assets\blender"
if HERE not in sys.path: sys.path.insert(0, HERE)
PROJECT = os.path.dirname(os.path.dirname(HERE))
MODELS = os.path.join(PROJECT, "assets", "models"); RENDERS = os.path.join(HERE, "renders")
BLEND = os.path.join(HERE, "civic_interior.blend")

MODULES = ("civic_dims", "civic_lib", "civic_materials", "build_civic_interior", "civic_hand", "build_civic_driver", "build_civic_exterior")

def _reload():
    for m in MODULES:
        if m in sys.modules: importlib.reload(sys.modules[m])
        else: importlib.import_module(m)

VIEWS = [   # (caméra, fichier, préfixes à masquer)
    ("CAM_DriverPOV", "civic_driver_pov.png", ["DRV_Head", "DRV_Hair", "DRV_Eye"]),   # la caméra est dans la tête
    ("CAM_Driver34", "civic_driver_34.png", []),
    ("CAM_Main", "civic_interior_rear_view.png", []),
    ("CAM_Door", "civic_driver_door_view.png", ["DOOR_R_", "QTR_R_", "PILLAR_B_R", "BELT_R_", "ROOF_Rail_R", "EXT_", "ENV_"]),
    ("CAM_ExtFront34", "civic_exterior_front34.png", []),
    ("CAM_ExtRear34", "civic_exterior_rear34.png", []),
    ("CAM_ExtSide", "civic_exterior_side.png", []),
]

def main(build=True, check=True, render=True, export=True, save=True, views=None, pct=100):
    _reload()
    import civic_lib as L, build_civic_interior as BI, build_civic_driver as BD, build_civic_exterior as BE
    report = {}; t0 = time.time()
    if build:
        report["interior"] = BI.build(); report["driver"] = BD.build(); report["exterior"] = BE.build()
        col = bpy.data.collections.get("Collection")
        if col and not col.objects and not col.children: bpy.data.collections.remove(col)
        for o in bpy.data.objects:
            if o.type == 'CAMERA': o.data.display_size = 0.15
        L.hide_cutters()
    if check:
        report["poke_through"] = L.poke_check("EXT_Body", ("Civic_Interior", "Civic_Driver"))
    if render:
        report["renders"] = L.render_views(views or VIEWS, RENDERS, pct=pct)
    if save:
        L.save_blend(BLEND); report["blend"] = BLEND
    if export:
        os.makedirs(MODELS, exist_ok=True)
        report["glb"] = {name: L.export_glb(col, os.path.join(MODELS, f"{name}.glb")) for name, col in (("civic_interior", "Civic_Interior"), ("civic_driver", "Civic_Driver"), ("civic_exterior", "Civic_Exterior"))}
        L.hide_cutters()
    report["seconds"] = round(time.time() - t0, 1)
    return report

if __name__ == "__main__":
    print(main())
