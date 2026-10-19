// MotoLogger Pinout Reference (ESP32-S3 + BNO085 HSPI + MicroSD FSPI + CAN TWAI)

#define FORCE_ON    17
#define SENSE_V_DIG 8
#define SENSE_V_ANA 9

#define BLUE_LED    10
#define YELLOW_LED  11

#define CAN_RX      13
#define CAN_TX      14
#define CAN_RS      38    // Mode Control (LOW = 500 kbps Active, HIGH = Standby)

#define HI_DRIVER   21    // Switched 3V3 high driver power output (MT9700 load switch)

// Dedicated HSPI Bus for CEVA / Hillcrest BNO085 9-DoF IMU (3 MHz)
#define IMU_MISO    1     // GY-BNO08X SDA/MISO/TX (GPIO1)
#define IMU_SCK     2     // GY-BNO08X SCL/SCK/RX (GPIO2)
#define IMU_MOSI    4     // GY-BNO08X ADO / ADDR/MOSI (GPIO4 default; or pad GPIO6 if MOTOLOGGER_PCB_BREAKOUT_PADS)
#define IMU_CS      5     // GY-BNO08X CS (GPIO5 default; or pad GPIO47 if MOTOLOGGER_PCB_BREAKOUT_PADS)
#define IMU_INT     12    // GY-BNO08X H_INTN / Data-Ready Interrupt (GPIO12, Active LOW)
#define IMU_RST     48    // GY-BNO08X Hardware Reset (GPIO48, Active LOW)

// Dedicated FSPI Bus for MicroSD Card Reader (25 MHz)
#define SD_MISO     41    // SPI MISO (GPIO41)
#define SD_MOSI     40    // SPI MOSI (GPIO40)
#define SD_SCK      39    // SPI CLK (GPIO39)
#define SD_CS       45    // SPI CS for SD card reader (GPIO45)

/*
Available solderable breakout pads on the custom RejsaCAN v3.4 PCB:

Top-side breakout pads:
  GPIO01  -> IMU_MISO (BNO085)
  GPIO02  -> IMU_SCK (BNO085)
  GPIO12  -> IMU_INT (BNO085 H_INTN)
  GPIO48  -> IMU_RST (BNO085 RST)
  GPIO47  -> Alternative IMU_CS pad (used when MOTOLOGGER_PCB_BREAKOUT_PADS defined)
  GPIO21  -> 3V3 Switched power rail output
  GPIO39  -> SD_SCK
  GPIO40  -> SD_MOSI
  GPIO41  -> SD_MISO

Rear-side breakout pads:
  GPIO06  -> Alternative IMU_MOSI pad (used when MOTOLOGGER_PCB_BREAKOUT_PADS defined)
  GPIO07  -> Extra GPIO
  GPIO15  -> Extra GPIO
  GPIO16  -> Extra GPIO
  RXD     -> Second UART RX
  TXD     -> Second UART TX

Note for DevKitC-1 vs Custom PCB:
- On ESP32-S3-DevKitC-1 development kits, GPIO4 (MOSI) and GPIO5 (CS) are easily accessible on pin headers.
- On the custom RejsaCAN v3.4 PCB, compile with -D MOTOLOGGER_PCB_BREAKOUT_PADS to route MOSI to GPIO6 and CS to GPIO47 pads.
*/


