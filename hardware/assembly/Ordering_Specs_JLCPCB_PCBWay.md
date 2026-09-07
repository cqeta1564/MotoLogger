# MotoLogger Hardware Manufacturing & Assembly Guide

This document contains full manufacturing and ordering specifications for fabricating and assembling the **MotoLogger** hardware using **JLCPCB** or **PCBWay**.

---

## 1. Main Board Fabrication Specifications (Gerbers)

- **Gerber File:** `hardware/gerbers/MotoLogger_Clean_Gerber.zip` (Neutral silkscreen without branding)
- **Board Dimensions:** `31.5 mm x 49.5 mm` (1.24 in x 1.95 in)
- **Layer Count:** 2 Layers
- **PCB Thickness:** 1.6 mm
- **Base Material:** FR-4 (TG 150-160 recommended)
- **Copper Weight:** 1 oz (35 µm) outer layers
- **Surface Finish:** **ENIG (Immersion Gold)** strongly recommended for fine-pitch ESP32-S3 pads (or Lead-Free HASL)
- **Solder Mask Color:** Matte Black, Blue, or Purple
- **Silkscreen Color:** White
- **Min Hole Size / Tracing:** 0.3 mm hole / 6 mil trace & space (Standard capabilities)

---

## 2. SMT Assembly Specifications (PCBA)

- **Bill of Materials (BOM):** `hardware/assembly/MotoLogger_BOM.csv`
- **Part Placement / CPL:** `hardware/assembly/MotoLogger_Part_Placements.zip`
- **Assembly Side:** **Top + Bottom** (double-sided SMT assembly)
- **LCSC SMT Parts Availability:** All active components (ESP32-S3-WROOM-1-N16R8, SN65HVD230DR, LMR14006 buck regulator, MT9700 load switch) feature direct LCSC part numbers.

---

## 3. OBD2 Sandwich Plug Board (Optional)

If mounting directly into a vehicle OBD-II diagnostic port:
- **Gerber File:** `hardware/gerbers/MotoLogger_OBD2_Plug_Gerber.zip`
- **Thickness:** 1.6 mm, 2 Layers
- **Surface Finish:** ENIG (Immersion Gold) or Lead-Free HASL

---

## 4. IMU Breakout Module Attachment (BNO085)

The CEVA / Hillcrest BNO085 9-DoF IMU module connects to the designated header pads on the main board:
- **SDA:** `GPIO1`
- **SCL:** `GPIO2`
- **INT (H_INTN):** `GPIO12`
- **RST:** `GPIO48`
- **3V3:** Connected to switched 3.3V power rail (`PIN_3V3_SWITCH` / `GPIO21`)
- **GND:** Ground plane
