# Filament Drying Sources

All values in SpoolDry are **typical starting guidance** summarised (not copied) from official manufacturer pages,
last checked **October 1–2, 2026**. Manufacturers disagree (e.g. PC: 70–80 °C at Polymaker, 120 °C at 3DXTECH for pure PC);
SpoolDry shows the range and a conservative starting point within its 70 °C hardware limit. Always follow the data sheet
of the exact product.

| Manufacturer | Page | Summary used |
|---|---|---|
| Bambu Lab | <https://wiki.bambulab.com/en/filament-acc/filament/dry-filament> | Blast-oven values: PLA 50–60 °C 8 h; PETG 60–70 °C 8 h; ABS/ASA 75–85 °C 8 h; TPU 65–75 °C 8 h; PC 75–85 °C 8 h; PA/PA-CF/PAHT/PET-CF 75–85 °C 8–12 h; PVA/BVOH 75–85 °C 8–12 h; PPS(-CF/GF) 110–140 °C 8–12 h |
| Prusa Research | <https://help.prusa3d.com/article/drying-filament_332086> | PLA 45 °C 6 h; PETG 55 °C 6 h; TPU 60 °C 4–6 h; ASA 80 °C 4 h; PA11 CF 90 °C 6 h; PC Blend 85 °C 5 h; PC Blend CF 90 °C 4 h; PEI 150 °C 8 h |
| Polymaker | <https://wiki.polymaker.com/the-basics/3d-printing-materials/pc> | PC 70–80 °C 6–8 h |
| Fiberlogy | <https://fiberlogy.com/en/faq-2/> | PLA 50 °C 4 h; ABS 60 °C 4 h; ASA/PA12+CF15/PA12+GF15 80 °C 4 h; PET-G 60 °C 4 h; BVOH 50 °C 4 h; PA12 70 °C 4 h |
| 3DXTECH | <https://www.3dxtech.com/pages/filament-drying-instructions> | PLA 45 °C; PETG/TPU 65 °C; ABS/ASA/Nylon 12 80 °C; Nylon 6 & filled 90 °C; PPS 110 °C; PC 120 °C; PEI 9085 130 °C; PEEK/PEI 1010 150 °C (3–8 h) |
| Forward AM (BASF) | <https://forward-am.com/wp-content/uploads/2021/12/Ultrafuse_PA6_GF30_TDS_EN_v1.1.pdf> | Ultrafuse PA6 GF30: 100 °C, 4–16 h, hot-air or vacuum dryer |
| Raise3D | <https://support.raise3d.com/Pro3-Series/how-to-set-up-pva-filament-for-printing-26-1499.html> | PVA+: 80 °C, 8–12 h; keep < 15 % RH while printing |
| 3DXTECH (blog) | <https://www.3dxtech.com/blogs/featured/how-to-dry-filament> | storage target < 15 % RH; wet-filament symptoms |

Not cited (no official page verified in this pass): eSUN, SUNLU, FormFutura. Add them to
`FilamentDatabase.swift` with a URL once verified.
