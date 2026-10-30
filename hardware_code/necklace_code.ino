// This #include statement was automatically added by the Particle IDE.
#include <TinyGPS++.h>
#include "Particle.h"
#include <Adafruit_BNO08x_Sahagun.h>
#include <cmath>   // for std::isnan
#include <cctype>

SYSTEM_MODE(AUTOMATIC);
SYSTEM_THREAD(ENABLED);

TinyGPSPlus gps;

const uint8_t  GPS_I2C_ADDR         = 0x10;      // PA1010D default I2C
const uint32_t DIAG_PRINT_PERIOD_MS = 1000;      // 1 Hz digest
const uint32_t PUBLISH_PERIOD_MS    = 30000;     // publish every 30 s
const int      I2C_CHUNK_BYTES      = 32;        // Wire max per request
const int      I2C_BURST_CHUNKS     = 10;        // ~320 B per poll

// Optional debug toggles
const bool     PRINT_EVERY_LINE     = false;     // print every NMEA line (noisy)
const bool     DEBUG_GPS            = false;      // print GPS section in digest
const bool     DEBUG_IMU            = false;      // print IMU section in digest

// ===== BNO085 IMU CONFIGURATION =====
const uint8_t  BNO085_I2C_ADDR      = 0x4A;      // BNO085 default I2C address

// ===== CONFIGURABLE FALL/IMPACT DETECTION THRESHOLDS =====
// Impact force thresholds (in g-force units, where 1g = 9.8 m/s²)
//
// Reference examples for different g-force impacts:
// ~1.5g - Brisk walking, sitting down quickly, light jog
// ~2.0g - Light push, stumble, jogging impact, bumping into something
// ~2.5g - Moderate push, tripping, jumping landing, being jostled in crowd
// ~3.0g - Hard shove, fall from standing, running collision, aggressive push
// ~4.0g - Violent push, punch impact, falling and hitting object, tackle
// ~5.0g+ - Severe assault, high-speed collision, major fall impact, car accident
//
// Adjust IMPACT_THRESHOLD_G based on your sensitivity needs:
// - Lower values (2.0-2.5g): More sensitive, catches lighter impacts, more false positives
// - Medium values (3.0-3.5g): Balanced detection, good for general safety monitoring
// - Higher values (4.0g+): Less sensitive, only severe impacts, fewer false alarms
//
const float    IMPACT_THRESHOLD_G       = 6.0;    // Trigger threshold for impact detection (less sensitive)
const float    FALL_FREEFALL_THRESH_G   = 0.05;   // Below this = freefall (very low-g only)
const uint32_t FREEFALL_CONFIRM_MS      = 1500;   // Must sustain low-g for this long to confirm freefall
const uint32_t FALL_FREEFALL_MIN_MS     = 300;    // Min freefall duration before impact counts
const uint32_t POST_IMPACT_STILL_MS     = 4000;   // Stillness duration after impact = likely fall
const uint32_t ALERT_COOLDOWN_MS        = 120000; // Prevent alert spam (120 seconds between alerts)

unsigned long lastDiag = 0;
unsigned long lastPub  = 0;

String lineBuf;
String lastGGA;
String lastRMC;

// ===== BNO085 IMU Objects =====
Adafruit_BNO08x bno08x;
sh2_SensorValue_t sensorValue;
bool bno085Ready = false;

// Detection state machine for fall/impact detection
enum DetectionState {
    DETECT_IDLE,              // Normal monitoring
    DETECT_FREEFALL,          // Freefall detected, waiting for impact
    DETECT_IMPACT,            // Impact detected, transitioning to monitoring
    DETECT_POST_IMPACT        // Monitoring for stillness after impact
};
DetectionState detectionState = DETECT_IDLE;
unsigned long stateStartTime = 0;
unsigned long lastAlertTime = 0;
unsigned long freefallStartTime = 0;  // Track when low-g started
bool freefallConfirmed = false;       // Only true after sustained low-g
float peakImpactG = 0;      // Track peak g-force during impact event

// Current IMU sensor readings
float linAccelX = 0, linAccelY = 0, linAccelZ = 0;
float accelMagnitude = 0;
uint8_t stabilityClass = 0;  // 0=unknown, 1=on table, 2=stationary, 3=stable, 4=motion

// ---------- Utils ----------
static inline bool startsWithAny(const String& s, const char* const* prefixes, size_t n) {
    for (size_t i = 0; i < n; ++i) if (s.startsWith(prefixes[i])) return true;
    return false;
}

// Compute NMEA checksum (XOR of all chars between '$' and '*')
uint8_t nmeaChecksum(const String& body) {
    uint8_t cs = 0;
    for (size_t i = 0; i < body.length(); ++i) cs ^= (uint8_t)body.charAt(i);
    return cs;
}

// Convert a hex nibble value (0..15) to uppercase hex char
char hexDigit(uint8_t v) { v &= 0x0F; return (v < 10) ? ('0' + v) : ('A' + (v - 10)); }

// Validate that a line looks like a complete NMEA sentence with checksum "*HH"
bool hasCompleteChecksum(const String& line) {
    int star = line.lastIndexOf('*');
    if (star < 0 || (size_t)star + 2 >= line.length()) return false;
    // Ensure the two following chars are hex-ish
    char a = line.charAt(star + 1);
    char b = line.charAt(star + 2);
    return std::isxdigit((unsigned char)a) && std::isxdigit((unsigned char)b);
}

// Returns a sentence with optional GN->GP remap AND a corrected checksum.
// Requires input to contain '*' checksum. Adds CRLF when feeding.
String remapAndFixChecksumIfNeeded(const String& line) {
    // Split into: '$' + body (to '*') + "*HH"
    int dollar = line.indexOf('$');
    int star   = line.lastIndexOf('*');
    if (dollar != 0 || star < 0) {
        // Not a standard NMEA line; return as-is (TinyGPS++ will likely ignore)
        return line;
    }

    String body = line.substring(1, star);  // between '$' and '*'
    String talker = body.substring(0, 5);   // e.g., "GNGGA", "GNRMC", "GPGGA", ...

    // Remap only the talker for GGA/RMC if needed
    if (talker == "GNGGA")      body.replace("GNGGA", "GPGGA");
    else if (talker == "GNRMC") body.replace("GNRMC", "GPRMC");

    // Recompute checksum on the possibly modified body
    uint8_t cs = nmeaChecksum(body);

    // Build new full sentence with corrected checksum (no CRLF here)
    String fixed = "$" + body + "*";
    fixed += hexDigit((cs >> 4) & 0x0F);
    fixed += hexDigit(cs & 0x0F);
    return fixed;
}

// Feed a full (already corrected) NMEA line with CRLF to TinyGPS++
void feedSentenceToParser(const String& sentenceNoCrlf) {
    String s = sentenceNoCrlf;
    s += "\r\n";
    for (size_t i = 0; i < s.length(); ++i) gps.encode(s.charAt(i));
}

void handleFullLine(const String& rawLine) {
    if (PRINT_EVERY_LINE) { Serial.print("NMEA> "); Serial.println(rawLine); }

    // Must have checksum to be worth parsing (otherwise often partials)
    if (!hasCompleteChecksum(rawLine)) {
        // Skip partial/truncated lines to avoid parser noise
        return;
    }

    // Remap GN->GP for GGA/RMC and apply corrected checksum
    String corrected = remapAndFixChecksumIfNeeded(rawLine);

    // Feed to TinyGPS++ (with CRLF appended inside)
    feedSentenceToParser(corrected);

    // Cache latest GGA/RMC (for human digest, show raw line for transparency)
    static const char* GGAp[] = {"$GPGGA","$GNGGA","$GAGGA","$BDGGA","$GLGGA"};
    static const char* RMCp[] = {"$GPRMC","$GNRMC","$GARMC","$BDRMC","$GLRMC"};
    if (startsWithAny(rawLine, GGAp, sizeof(GGAp)/sizeof(GGAp[0])))      lastGGA = rawLine;
    else if (startsWithAny(rawLine, RMCp, sizeof(RMCp)/sizeof(RMCp[0]))) lastRMC = rawLine;
}

void pollGpsI2C() {
    for (int i = 0; i < I2C_BURST_CHUNKS; i++) {
        Wire.requestFrom(GPS_I2C_ADDR, (uint8_t)I2C_CHUNK_BYTES);
        while (Wire.available()) {
            char c = Wire.read();

            if (c == '\n') {
                // We have a full line (ending in \r\n); handle and reset
                handleFullLine(lineBuf);
                lineBuf = "";
            } else if (c != '\r') {
                lineBuf += c;
            }
        }
        delayMicroseconds(400);
    }
}

// ===== BNO085 IMU Polling =====
void pollBNO085() {
    if (!bno085Ready) return;

    while (bno08x.getSensorEvent(&sensorValue)) {
        switch (sensorValue.sensorId) {
            case SH2_LINEAR_ACCELERATION:
                // Linear acceleration with gravity removed (in m/s²)
                linAccelX = sensorValue.un.linearAcceleration.x;
                linAccelY = sensorValue.un.linearAcceleration.y;
                linAccelZ = sensorValue.un.linearAcceleration.z;
                // Calculate magnitude and convert to g-force (divide by 9.81)
                accelMagnitude = sqrt(linAccelX*linAccelX + linAccelY*linAccelY + linAccelZ*linAccelZ) / 9.81;
                break;

            case SH2_STABILITY_CLASSIFIER:
                // Stability: 0=unknown, 1=on table, 2=stationary, 3=stable, 4=motion
                stabilityClass = sensorValue.un.stabilityClassifier.classification;
                break;

        }
    }
}

// ===== LED Alert Flash =====
void flashAlertLED() {
    // Rapid flash pattern on D7 LED (10 flashes, 1 second total)
    for (int i = 0; i < 10; i++) {
        digitalWrite(D7, HIGH);
        delay(50);
        digitalWrite(D7, LOW);
        delay(50);
    }
}

// ===== Alert Trigger Function =====
void triggerAlert(const char* alertType) {
    unsigned long now = millis();

    // Prevent alert spam with cooldown period
    if (now - lastAlertTime < ALERT_COOLDOWN_MS && lastAlertTime != 0) {
        Serial.printlnf("Alert suppressed (cooldown): %s", alertType);
        return;
    }
    lastAlertTime = now;

    // Flash LED to indicate alert
    flashAlertLED();

    // Build JSON payload with alert info and GPS coordinates
    char payload[280];
    if (gps.location.isValid()) {
        snprintf(payload, sizeof(payload),
                 "{\"alert\":\"%s\",\"g\":%.2f,\"lat\":%.6f,\"lon\":%.6f,\"alt\":%.1f,\"sats\":%u}",
                 alertType,
                 peakImpactG,
                 gps.location.lat(),
                 gps.location.lng(),
                 gps.altitude.isValid() ? gps.altitude.meters() : 0.0,
                 gps.satellites.isValid() ? gps.satellites.value() : 0);
    } else {
        snprintf(payload, sizeof(payload),
                 "{\"alert\":\"%s\",\"g\":%.2f,\"gps\":false}",
                 alertType, peakImpactG);
    }

    Serial.printlnf("*** ALERT: %s ***", payload);
    Particle.publish("safety/alert", payload, PRIVATE, WITH_ACK);

    // Reset peak tracker
    peakImpactG = 0;
}

// ===== Fall/Impact Detection State Machine =====
void checkForFallOrImpact() {
    if (!bno085Ready) return;

    unsigned long now = millis();

    // Track peak g-force during detection events
    if (accelMagnitude > peakImpactG) {
        peakImpactG = accelMagnitude;
    }

    // Freefall confirmation logic: require sustained low-g before entering freefall state
    // This prevents false triggers from sensor noise when stationary
    if (accelMagnitude < FALL_FREEFALL_THRESH_G && stabilityClass == 4) {
        // Only consider freefall if device was in motion (stabilityClass == 4)
        if (freefallStartTime == 0) {
            freefallStartTime = now;
        } else if ((now - freefallStartTime) >= FREEFALL_CONFIRM_MS && !freefallConfirmed) {
            freefallConfirmed = true;
        }
    } else {
        // Reset freefall tracking if acceleration is normal
        if (accelMagnitude >= FALL_FREEFALL_THRESH_G) {
            freefallStartTime = 0;
            freefallConfirmed = false;
        }
    }

    switch (detectionState) {
        case DETECT_IDLE:
            // Check for sudden high-g impact (push, shove, attack, or fall impact)
            if (accelMagnitude > IMPACT_THRESHOLD_G) {
                detectionState = DETECT_IMPACT;
                stateStartTime = now;
                peakImpactG = accelMagnitude;
                Serial.printlnf("IMPACT detected: %.2fg (threshold: %.1fg)", accelMagnitude, IMPACT_THRESHOLD_G);

                // Publish impact detection event
                char impactPayload[128];
                snprintf(impactPayload, sizeof(impactPayload),
                         "{\"event\":\"impact_detected\",\"g\":%.2f,\"threshold\":%.1f}",
                         accelMagnitude, IMPACT_THRESHOLD_G);
                Serial.printlnf("Publishing: %s", impactPayload);
                Particle.publish("safety/impact_detected", impactPayload, PRIVATE);
            }
                // Check for confirmed freefall (sustained low-g while in motion)
            else if (freefallConfirmed) {
                detectionState = DETECT_FREEFALL;
                stateStartTime = now;
                peakImpactG = 0;
                Serial.printlnf("FREEFALL confirmed: %.2fg (sustained %lums)", accelMagnitude, FREEFALL_CONFIRM_MS);

                // Publish freefall detection event
                char freefallPayload[128];
                snprintf(freefallPayload, sizeof(freefallPayload),
                         "{\"event\":\"freefall_detected\",\"g\":%.2f,\"duration_ms\":%lu}",
                         accelMagnitude, FREEFALL_CONFIRM_MS);
                Serial.printlnf("Publishing: %s", freefallPayload);
                Particle.publish("safety/freefall_detected", freefallPayload, PRIVATE);
            }
            break;

        case DETECT_FREEFALL:
            // If freefall ends with a strong impact, this is a classic fall pattern
            if (accelMagnitude > IMPACT_THRESHOLD_G) {
                if ((now - stateStartTime) >= FALL_FREEFALL_MIN_MS) {
                    // Valid fall pattern: freefall followed by impact
                    Serial.printlnf("FALL PATTERN: freefall->impact (%.2fg)", accelMagnitude);
                    peakImpactG = accelMagnitude;
                    detectionState = DETECT_POST_IMPACT;
                    stateStartTime = now;
                } else {
                    // Freefall too short, treat as regular impact
                    detectionState = DETECT_IMPACT;
                    stateStartTime = now;
                    peakImpactG = accelMagnitude;
                }
                freefallConfirmed = false;
                freefallStartTime = 0;
            }
                // Freefall ended normally (no impact) - false alarm, return to idle
            else if (accelMagnitude >= FALL_FREEFALL_THRESH_G && accelMagnitude <= IMPACT_THRESHOLD_G) {
                detectionState = DETECT_IDLE;
                peakImpactG = 0;
                freefallConfirmed = false;
                freefallStartTime = 0;
            }
                // Timeout: if freefall lasts too long without impact, reset
            else if ((now - stateStartTime) > 1000) {
                detectionState = DETECT_IDLE;
                peakImpactG = 0;
                freefallConfirmed = false;
                freefallStartTime = 0;
            }
            break;

        case DETECT_IMPACT:
            // Transition to post-impact monitoring
            detectionState = DETECT_POST_IMPACT;
            stateStartTime = now;
            Serial.println("Monitoring post-impact activity...");
            break;

        case DETECT_POST_IMPACT:
            // Check if person remains still after impact (indicates fall/incapacitation)
            // stabilityClass: 0=unknown, 1=on table, 2=stationary, 3=stable, 4=motion
            if ((now - stateStartTime) >= POST_IMPACT_STILL_MS) {
                if (stabilityClass <= 3 && stabilityClass > 0) {
                    // Person is still/stable after impact - likely a fall
                    triggerAlert("fall");
                } else {
                    // Person resumed movement - likely just an impact/shove
                    triggerAlert("impact");
                }
                detectionState = DETECT_IDLE;
            }
                // If significant movement detected quickly after impact, it's just a bump
            else if ((now - stateStartTime) >= 500 && stabilityClass == 4) {
                // Moving again - just a bump/shove, still alert but as "impact"
                triggerAlert("impact");
                detectionState = DETECT_IDLE;
            }
                // Timeout safety - return to idle after extended period
            else if ((now - stateStartTime) > POST_IMPACT_STILL_MS + 2000) {
                Serial.println("Post-impact timeout, returning to idle");
                detectionState = DETECT_IDLE;
                peakImpactG = 0;
            }
            break;
    }
}

// Helper to convert stability class to human-readable string
const char* stabilityToString(uint8_t stability) {
    switch (stability) {
        case 0: return "unknown";
        case 1: return "on_table";
        case 2: return "stationary";
        case 3: return "stable";
        case 4: return "motion";
        default: return "?";
    }
}

// Helper to convert detection state to human-readable string
const char* detectionStateToString(DetectionState state) {
    switch (state) {
        case DETECT_IDLE: return "idle";
        case DETECT_FREEFALL: return "freefall";
        case DETECT_IMPACT: return "impact";
        case DETECT_POST_IMPACT: return "post_impact";
        default: return "?";
    }
}

void printOncePerSecondDigest() {
    if (!DEBUG_GPS && !DEBUG_IMU) return;  // Skip if both disabled

    Serial.println("\n--- SAFETY MONITOR DIGEST (1 Hz) ---");

    // GPS Status
    if (DEBUG_GPS) {
        Serial.println("[GPS]");
        if (lastGGA.length()) { Serial.print("  GGA> "); Serial.println(lastGGA); }
        if (lastRMC.length()) { Serial.print("  RMC> "); Serial.println(lastRMC); }

        if (gps.location.isValid()) {
            Serial.printlnf("  Fix: YES  lat: %.6f  lon: %.6f  age(ms): %lu",
                            gps.location.lat(), gps.location.lng(), gps.location.age());
        } else {
            Serial.println("  Fix: NO   (waiting for satellites)");
        }

        if (gps.satellites.isValid()) Serial.printlnf("  Satellites: %u", gps.satellites.value());
        if (gps.hdop.isValid())       Serial.printlnf("  HDOP: %.2f", gps.hdop.value());
        if (gps.altitude.isValid())   Serial.printlnf("  Alt: %.1f m", gps.altitude.meters());
        if (gps.speed.isValid())      Serial.printlnf("  Speed: %.2f km/h", gps.speed.kmph());

        if (gps.date.isValid() && gps.time.isValid()) {
            Serial.printlnf("  UTC: %04d-%02d-%02d %02d:%02d:%02dZ",
                            gps.date.year(), gps.date.month(), gps.date.day(),
                            gps.time.hour(), gps.time.minute(), gps.time.second());
        }

        Serial.printlnf("  [Stats] chars=%lu withFix=%lu pass=%lu fail=%lu",
                        gps.charsProcessed(), gps.sentencesWithFix(),
                        gps.passedChecksum(), gps.failedChecksum());
    }

    // IMU Status
    if (DEBUG_IMU) {
        Serial.println("[IMU]");
        if (bno085Ready) {
            Serial.printlnf("  Accel: %.2fg (X:%.2f Y:%.2f Z:%.2f m/s²)",
                            accelMagnitude, linAccelX, linAccelY, linAccelZ);
            Serial.printlnf("  Stability: %s (%d)", stabilityToString(stabilityClass), stabilityClass);
            Serial.printlnf("  Detection: %s | Threshold: %.1fg",
                            detectionStateToString(detectionState), IMPACT_THRESHOLD_G);
        } else {
            Serial.println("  BNO085: NOT READY");
        }
    }

    Serial.println("------------------------------------");
}

static inline void jsonNumberOrNull(char* out, size_t outSz, double v, int decimals) {
    if (std::isnan(v)) snprintf(out, outSz, "null");
    else               snprintf(out, outSz, "%.*f", decimals, v);
}

void setup() {
    Serial.begin(115200);
    Wire.begin(); // SDA=D0, SCL=D1
    delay(1200);

    // Setup LED for alerts
    pinMode(D7, OUTPUT);
    digitalWrite(D7, LOW);

    Serial.println("\n=== GPS + IMU Fall Safety Monitor ===");
    Serial.println("GPS: PA1010D (I2C 0x10)");
    Serial.println("IMU: BNO085 (I2C 0x4A)");
    Serial.println("Wiring: VIN->3V3, GND->GND, SDA->D0, SCL->D1");
    Serial.printlnf("Impact threshold: %.1fg", IMPACT_THRESHOLD_G);
    Serial.println("Digest logs once per second; publish every 30 s.\n");

    // Initialize BNO085 IMU
    Serial.print("Initializing BNO085... ");
    if (!bno08x.begin_I2C(BNO085_I2C_ADDR, &Wire)) {
        Serial.println("FAILED! Check wiring.");
        bno085Ready = false;
    } else {
        Serial.println("OK");
        bno085Ready = true;

        // Enable sensor reports
        // Linear acceleration (gravity removed) at 100Hz for impact detection
        if (!bno08x.enableReport(SH2_LINEAR_ACCELERATION, 10000)) {
            Serial.println("  WARNING: Could not enable linear acceleration report");
        }
        // Stability classifier at 20Hz for post-impact stillness detection
        if (!bno08x.enableReport(SH2_STABILITY_CLASSIFIER, 50000)) {
            Serial.println("  WARNING: Could not enable stability classifier");
        }
        Serial.println("  IMU reports enabled: LINEAR_ACCEL, STABILITY");
    }
}

void loop() {
    // Poll sensors
    pollGpsI2C();
    pollBNO085();

    // Run fall/impact detection state machine
    checkForFallOrImpact();

    // Print diagnostic digest once per second
    if (millis() - lastDiag >= DIAG_PRINT_PERIOD_MS) {
        lastDiag = millis();
        printOncePerSecondDigest();
    }

    if (millis() - lastPub >= PUBLISH_PERIOD_MS) {
        lastPub = millis();

        if (gps.location.isValid()) {
            double lat  = gps.location.lat();
            double lon  = gps.location.lng();
            double alt  = gps.altitude.isValid() ? gps.altitude.meters() : NAN;
            double hdop = gps.hdop.isValid()     ? gps.hdop.value()      : NAN;
            double spd  = gps.speed.isValid()    ? gps.speed.kmph()      : NAN;
            uint32_t sats = gps.satellites.isValid() ? gps.satellites.value() : 0;

            char alt_s[16], hdop_s[16], spd_s[16];
            jsonNumberOrNull(alt_s,  sizeof(alt_s),  alt,  1);
            jsonNumberOrNull(hdop_s, sizeof(hdop_s), hdop, 1);
            jsonNumberOrNull(spd_s,  sizeof(spd_s),  spd,  1);

            char payload[220];
            snprintf(payload, sizeof(payload),
                     "{\"fix\":true,\"lat\":%.6f,\"lon\":%.6f,\"alt_m\":%s,\"hdop\":%s,\"spd_kmph\":%s,\"sats\":%u}",
                     lat, lon, alt_s, hdop_s, spd_s, sats);

            Serial.printlnf("Publish: %s", payload);
            Particle.publish("gps/position", payload, PRIVATE, WITH_ACK);
        } else {
            Serial.println("Publish: {\"fix\":false}");
            Particle.publish("gps/position", "{\"fix\":false}", PRIVATE, WITH_ACK);
        }
    }
}