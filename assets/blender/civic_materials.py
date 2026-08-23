# -*- coding: utf-8 -*-
"""civic_materials — tous les matériaux (intérieur CIV_*, conducteur DRV_*, extérieur EXT_*), créés à la demande."""
from civic_lib import mat, tex_mat, node_of
import os
from civic_dims import PAINT
import bpy

def interior():
    M = dict(
        plastic_dark = mat("CIV_Plastic_Dark", (0.016, 0.016, 0.018), rough=0.58, grain=0.35, grain_scale=700, specular=0.4),
        plastic_grey = mat("CIV_Plastic_Grey", (0.075, 0.077, 0.082), rough=0.55, grain=0.3, grain_scale=700, specular=0.4),
        rubber       = mat("CIV_Rubber_Leather", (0.012, 0.012, 0.013), rough=0.62, grain=0.5, grain_scale=900, specular=0.5),
        cloth        = mat("CIV_Seat_Cloth", (0.055, 0.057, 0.062), rough=0.92, grain=0.9, grain_scale=1800, sheen=0.12),
        carpet       = mat("CIV_Carpet", (0.03, 0.03, 0.032), rough=1.0, grain=1.0, grain_scale=1400),
        headliner    = mat("CIV_Headliner", (0.30, 0.30, 0.295), rough=1.0, grain=0.4, grain_scale=900),
        chrome       = mat("CIV_Chrome", (0.85, 0.86, 0.88), rough=0.18, metallic=1.0),
        metal_dark   = mat("CIV_Metal_Dark", (0.18, 0.18, 0.19), rough=0.45, metallic=0.9),
        gauge_glass  = mat("CIV_Gauge_Glass", (0.02, 0.02, 0.025), rough=0.08, coat=1.0, alpha=0.25),
        gauge_face   = mat("CIV_Gauge_Face", (0.008, 0.008, 0.009), rough=0.4),
        white_mark   = mat("CIV_White_Marking", (0.85, 0.85, 0.8), rough=0.5, emission=(0.9, 0.9, 0.85), emit=0.15),
        needle       = mat("CIV_Needle_Red", (0.9, 0.06, 0.02), rough=0.4, emission=(1.0, 0.1, 0.02), emit=0.6),
        glass        = mat("CIV_Window_Glass", (0.75, 0.82, 0.88), rough=0.02, alpha=0.10, specular=0.6),
        radio        = mat("CIV_Radio_Face", (0.012, 0.012, 0.013), rough=0.3),
        display      = mat("CIV_Display", (0.2, 0.9, 0.4), rough=0.3, emission=(0.25, 1.0, 0.45), emit=2.0),
        led_red      = mat("CIV_LED_Red", (0.9, 0.05, 0.02), rough=0.3, emission=(1.0, 0.08, 0.02), emit=3.0),
        lamp_green   = mat("CIV_Lamp_Green", (0.1, 0.9, 0.2), rough=0.3, emission=(0.1, 0.9, 0.2), emit=2.5),
        lamp_blue    = mat("CIV_Lamp_Blue", (0.1, 0.4, 1.0), rough=0.3, emission=(0.1, 0.4, 1.0), emit=2.0),
        lamp_off     = mat("CIV_Lamp_Off", (0.03, 0.03, 0.03), rough=0.3),
    )
    return M

def driver():
    M = dict(
        skin  = mat("DRV_Skin", (0.48, 0.35, 0.25), rough=0.55, sss=0.25, specular=0.35),   # = poignet de la photo des mains
        hand  = tex_mat("DRV_Hand_Photo", os.path.join(os.path.dirname(os.path.abspath(__file__)), "textures", "player_hands.png"), rough=0.55, specular=0.35),
        shirt = mat("DRV_Tshirt_White", (0.86, 0.86, 0.84), rough=0.92, grain=0.5, grain_scale=1500, sheen=0.15),
        jeans = mat("DRV_Jeans_Denim", (0.10, 0.17, 0.34), rough=0.95, grain=0.8, grain_scale=1200, sheen=0.1),
        shoe  = mat("DRV_Sneaker_White", (0.82, 0.82, 0.80), rough=0.6, specular=0.4),
        sole  = mat("DRV_Sneaker_Sole", (0.62, 0.62, 0.60), rough=0.85),
        lace  = mat("DRV_Sneaker_Lace", (0.25, 0.25, 0.25), rough=0.9),
        belt  = mat("DRV_Belt_Leather", (0.03, 0.02, 0.015), rough=0.55),
        buckle = mat("DRV_Buckle", (0.75, 0.75, 0.78), rough=0.3, metallic=1.0),
        hair  = mat("DRV_Hair", (0.05, 0.032, 0.02), rough=0.7),
        eye   = mat("DRV_Eye", (0.02, 0.02, 0.02), rough=0.2),
    )
    return M

def exterior():
    M = dict(
        paint     = mat("EXT_Paint", PAINT, rough=0.38, metallic=0.25, coat=0.7),
        inner     = mat("EXT_Sheet_Inner", (0.05, 0.05, 0.052), rough=0.9),
        black     = mat("EXT_Trim_Black", (0.015, 0.015, 0.016), rough=0.7),
        chrome    = mat("EXT_Chrome", (0.85, 0.86, 0.88), rough=0.15, metallic=1.0),
        glass     = mat("CIV_Window_Glass", (0.75, 0.82, 0.88), rough=0.02, alpha=0.10, specular=0.6),
        headlight = mat("EXT_Headlight_Glass", (0.85, 0.88, 0.92), rough=0.08, alpha=0.35, coat=1.0),
        reflector = mat("EXT_Reflector", (0.9, 0.9, 0.92), rough=0.2, metallic=1.0),
        amber     = mat("EXT_Lens_Amber", (0.95, 0.45, 0.05), rough=0.15, coat=1.0, emission=(1.0, 0.5, 0.1), emit=0.15),
        red       = mat("EXT_Lens_Red", (0.75, 0.03, 0.02), rough=0.15, coat=1.0, emission=(1.0, 0.05, 0.02), emit=0.15),
        white_lens = mat("EXT_Lens_White", (0.9, 0.9, 0.88), rough=0.15, coat=1.0),
        tire      = mat("EXT_Tire", (0.018, 0.018, 0.018), rough=0.9),
        rim       = mat("EXT_Rim", (0.62, 0.62, 0.64), rough=0.35, metallic=0.85),
        plate     = mat("EXT_Plate", (0.9, 0.9, 0.86), rough=0.5),
        dark_metal = mat("EXT_Dark_Metal", (0.12, 0.12, 0.12), rough=0.6, metallic=0.6),
        well      = mat("EXT_WheelWell", (0.02, 0.02, 0.02), rough=1.0),
        asphalt   = mat("ENV_Asphalt", (0.09, 0.09, 0.09), rough=0.95),
    )
    return M
