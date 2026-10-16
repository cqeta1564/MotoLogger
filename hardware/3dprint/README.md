# MotoLogger Enclosure (3D Print)

Custom enclosure models based on the **RejsaCAN v3.x Standard Housing** with integrated OBD-II connector profile and MicroSD card slot.

---

## Files

| File | Description |
| :--- | :--- |
| `BASE.stl` | Bottom housing shell with mounting posts for M2 threaded heat-set inserts, OBD-II connector aperture, and external MicroSD access slot. |
| `LID.stl` | Top housing lid with countersunk holes for M2 machine screws. |

---

## Hardware & Fasteners

- **Heat-set Threaded Inserts:** 4× M2 brass inserts (outer diameter ~3.2–3.5 mm, length 3.0–4.0 mm).
- **Machine Screws:** 4× M2 countersunk or socket-head screws (length ~6–8 mm).
- **OBD-II Connector:** Standard right-angle / horizontal PCB-mount OBD-II male plug.

---

## Recommended Print Settings

For automotive and motorcycle use (heat resistance under seat/fairing and vibration tolerance):

- **Material:** PETG, ABS, or ASA (PLA is **not recommended** due to low heat deflection temperature ~55 °C).
- **Layer Height:** 0.20 mm (0.16 mm for smoother screw chamfers).
- **Perimeters / Walls:** 3 to 4 walls for mechanical strength and solid screw bosses.
- **Top / Bottom Layers:** 4 to 5 layers.
- **Infill:** 25% – 40% (Gyroid or Grid pattern).
- **Supports:**
  - Base: Minor tree/organic supports recommended around the connector cutout and MicroSD slot overhangs.
  - Lid: Print flat face down on build plate; no supports required.

---

## Assembly Steps

1. **Insert Heat-Set Inserts:** Using a soldering iron set to ~220–250 °C (depending on filament type), gently press M2 brass threaded inserts into the 4 corner bosses on the base.
2. **Test Fit PCB:** Slide the MotoLogger / RejsaCAN v3.x PCB into the base, ensuring the MicroSD card slot aligns flush with the side cutout and the OBD-II connector pins mate into the front face.
3. **Attach Lid:** Place `LID.stl` on top and secure using 4× M2 screws. Do not overtighten into brass inserts.
