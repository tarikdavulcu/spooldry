// Drying state machine + safety supervisor tests, driven by the thermal simulator.
#include <cstdlib>

#include "DryerSim.h"
#include "TestFramework.h"

using namespace spooldry;
using sim::Rig;

static bool is(const Rig& r, DeviceState s) { return r.state() == s; }

TEST(boot_state_is_idle_with_outputs_off) {
    Rig r;
    CHECK(is(r, DeviceState::IDLE));
    CHECK(!r.out.relay);
    CHECK_EQ(r.out.heaterDuty, 0);
    CHECK_EQ((int)r.error(), (int)ErrorCode::NONE);
}

TEST(full_session_pla_preheat_dry_cooldown_complete) {
    Rig r;
    Response a = r.start(Material::PLA, 50.0f, 3600);
    CHECK_EQ((int)a.type, (int)ResponseType::ACK);
    CHECK_EQ(a.payloadLen, 8);
    const uint32_t sid = a.payload[0] | (a.payload[1] << 8) | (a.payload[2] << 16) | (a.payload[3] << 24);
    CHECK_EQ(sid, 1u);
    r.tick();
    CHECK(is(r, DeviceState::PREHEATING));
    CHECK(r.out.relay && r.out.fan);
    CHECK_EQ(r.ctl.snapshot().remainingSec, 3600u);  // timer not started during preheat
    CHECK(r.runUntil([&] { return is(r, DeviceState::DRYING); }, 3600));
    // Remaining time counts down only while drying.
    r.runSeconds(600);
    const uint32_t rem = r.ctl.snapshot().remainingSec;
    CHECK(rem <= 3000 && rem >= 2990);
    float minT = 1e9, maxT = -1e9;
    for (int i = 0; i < 4 * 1800; ++i) {
        r.tick();
        if (r.plant.chamberC < minT) minT = r.plant.chamberC;
        if (r.plant.chamberC > maxT) maxT = r.plant.chamberC;
    }
    CHECK(maxT < 52.5f);
    CHECK(minT > 46.0f);
    CHECK(r.runUntil([&] { return is(r, DeviceState::COOLDOWN); }, 1300));
    CHECK_EQ((int)r.ctl.snapshot().endReason, (int)EndReason::COMPLETED);
    CHECK_EQ(r.out.heaterDuty, 0);
    CHECK(!r.out.relay);
    CHECK(r.out.fan);
    CHECK(r.runUntil([&] { return is(r, DeviceState::COMPLETED); }, 16 * 60));
    CHECK_EQ(r.ctl.snapshot().remainingSec, 0u);
    CHECK(!r.invariantViolated);
    // Humidity dropped during the session.
    CHECK(r.plant.humidityRh() < 30.0f);
}

TEST(pa_cf_70c_reaches_target_without_overshoot_trip) {
    Rig r;
    r.plant.heatCapacityJPerK = 5000.0f;  // two spools
    CHECK_EQ((int)r.start(Material::PA_CF, 70.0f, 4 * 3600).type, (int)ResponseType::ACK);
    CHECK(r.runUntil([&] { return is(r, DeviceState::DRYING); }, 90 * 60));
    r.runSeconds(3600);
    CHECK(is(r, DeviceState::DRYING));
    CHECK(r.maxChamberC < 74.0f);
    CHECK(!r.invariantViolated);
}

TEST(stop_session_enters_cooldown_then_idle) {
    Rig r;
    r.start(Material::PETG, 60.0f, 7200);
    r.runSeconds(1200);
    Response a = r.send(Opcode::STOP_SESSION);
    CHECK_EQ((int)a.result, (int)ResultCode::OK);
    r.tick();
    CHECK(is(r, DeviceState::COOLDOWN));
    CHECK_EQ(r.out.heaterDuty, 0);
    CHECK(!r.out.relay);
    CHECK_EQ((int)r.ctl.snapshot().endReason, (int)EndReason::STOPPED_BY_USER);
    CHECK(r.runUntil([&] { return is(r, DeviceState::IDLE); }, 16 * 60));
    CHECK(!r.invariantViolated);
}

TEST(sensor_disconnected_latches_error_within_debounce) {
    Rig r;
    r.start(Material::ABS, 65.0f, 7200);
    r.runSeconds(300);
    r.plant.faults.sensorDisconnected = true;
    const uint32_t t0 = r.nowMs;
    CHECK(r.runUntil([&] { return is(r, DeviceState::ERROR); }, 10));
    CHECK((r.nowMs - t0) <= 3500);
    CHECK_EQ((int)r.error(), (int)ErrorCode::SENSOR_I2C);
    r.tick();
    CHECK_EQ(r.out.heaterDuty, 0);
    CHECK(!r.out.relay);
    CHECK(r.out.fan);  // chamber temperature unknown -> keep air moving
    // Reset refused while sensor still missing.
    CHECK_EQ((int)r.send(Opcode::RESET_SESSION).result, (int)ResultCode::SENSOR_FAULT);
    r.plant.faults.sensorDisconnected = false;
    r.tick();
    CHECK_EQ((int)r.send(Opcode::RESET_SESSION).result, (int)ResultCode::OK);
    r.tick();
    CHECK(is(r, DeviceState::IDLE));
}

TEST(sensor_crc_errors_latch_sensor_crc) {
    Rig r;
    r.start(Material::PLA, 45.0f, 3600);
    r.runSeconds(60);
    r.plant.faults.sensorCrc = true;
    CHECK(r.runUntil([&] { return is(r, DeviceState::ERROR); }, 10));
    CHECK_EQ((int)r.error(), (int)ErrorCode::SENSOR_CRC);
}

TEST(invalid_temperature_reading_is_rejected) {
    Rig r;
    r.start(Material::PLA, 45.0f, 3600);
    r.runSeconds(60);
    r.plant.faults.sensorStuckHot = true;  // decoder reports SENSOR_RANGE, value never used for control
    CHECK(r.runUntil([&] { return is(r, DeviceState::ERROR); }, 10));
    CHECK_EQ((int)r.error(), (int)ErrorCode::SENSOR_RANGE);
    CHECK(!r.invariantViolated);
}

TEST(start_refused_without_valid_sensor) {
    Rig r;
    r.plant.faults.sensorDisconnected = true;
    r.tick();
    Response a = r.start(Material::PLA, 45.0f, 3600);
    CHECK_EQ((int)a.type, (int)ResponseType::NACK);
    CHECK_EQ((int)a.result, (int)ResultCode::SENSOR_FAULT);
    r.plant.faults.sensorDisconnected = false;
    r.plant.faults.ntcOpen = true;
    r.tick();
    CHECK_EQ((int)r.start(Material::PLA, 45.0f, 3600).result, (int)ResultCode::SENSOR_FAULT);
}

TEST(over_temperature_when_heater_stuck_on_during_session) {
    Rig r;
    r.start(Material::PLA, 45.0f, 4 * 3600);
    CHECK(r.runUntil([&] { return is(r, DeviceState::DRYING); }, 3600));
    r.plant.faults.heaterStuckOn = true;  // MOSFET shorted + relay welded (hardware thermostat would also act)
    CHECK(r.runUntil([&] { return is(r, DeviceState::OVER_TEMPERATURE); }, 3600));
    CHECK_EQ((int)r.error(), (int)ErrorCode::OVER_TEMP_CHAMBER);
    CHECK(r.plant.chamberC < 45.0f + 8.0f + 3.0f);  // tripped on sustained target + 8 C, not the absolute cap
    r.tick();
    CHECK(!r.out.relay);
    CHECK_EQ(r.out.heaterDuty, 0);
    CHECK(r.out.fan);
    CHECK_EQ((int)r.ctl.snapshot().endReason, (int)EndReason::OVER_TEMPERATURE);
    CHECK_EQ((int)r.send(Opcode::RESET_SESSION).result, (int)ResultCode::OVER_TEMPERATURE_LOCK);
    CHECK_EQ((int)r.start(Material::PLA, 45.0f, 3600).result, (int)ResultCode::NOT_ALLOWED_IN_STATE);
    r.plant.faults.heaterStuckOn = false;
    CHECK(r.runUntil([&] { return r.plant.chamberC < 49.0f && r.plant.heaterOutletC < 59.0f; }, 4 * 3600));
    r.tick();
    CHECK_EQ((int)r.send(Opcode::RESET_SESSION).result, (int)ResultCode::OK);
}

TEST(absolute_chamber_limit_trips_in_any_state) {
    Rig r;
    r.plant.chamberC = 81.0f;  // e.g. hot environment or external heat source
    r.tick();
    CHECK(is(r, DeviceState::OVER_TEMPERATURE));
    CHECK_EQ((int)r.error(), (int)ErrorCode::OVER_TEMP_CHAMBER);
    r.tick();
    CHECK(r.out.fan);
}

TEST(heater_stuck_detected_while_idle) {
    Rig r;
    r.plant.faults.heaterStuckOn = true;
    CHECK(r.runUntil([&] { return is(r, DeviceState::ERROR) || is(r, DeviceState::OVER_TEMPERATURE); }, 3 * 3600));
    CHECK_EQ((int)r.error(), (int)ErrorCode::HEATER_STUCK_ON);
    r.tick();
    CHECK(!r.out.relay);
    CHECK_EQ(r.out.heaterDuty, 0);
    // Double fault (shorted MOSFET + welded relay): firmware can only report it. The 100 C thermal
    // cutoff in the heater current path is the final barrier; the model shows the PTC self-limits.
    r.runSeconds(3600);
    CHECK(r.maxChamberC < 80.0f);
}

TEST(fan_failure_stops_heater) {
    Rig r;
    r.start(Material::PETG, 60.0f, 4 * 3600);
    r.runSeconds(900);
    r.plant.faults.fanBroken = true;
    const uint32_t t0 = r.nowMs;
    CHECK(r.runUntil([&] { return is(r, DeviceState::ERROR); }, 30));
    CHECK((r.nowMs - t0) <= 6000);
    CHECK_EQ((int)r.error(), (int)ErrorCode::FAN_FAILURE);
    r.tick();
    CHECK_EQ(r.out.heaterDuty, 0);
    CHECK(!r.out.relay);
}

TEST(fan_failure_without_tach_is_contained_by_ntc_derating) {
    HardwareFeatures hw;
    hw.fanTach = false;  // builds without tach wiring
    Rig r(hw);
    r.start(Material::PETG, 60.0f, 4 * 3600);
    r.runSeconds(600);
    r.plant.faults.fanBroken = true;
    r.runSeconds(3600);
    // Outlet derating keeps the duct below the absolute heater limit; chamber never overheats.
    CHECK(r.maxHeaterC < 141.0f);
    CHECK(r.maxChamberC < 70.0f);
    CHECK(!r.invariantViolated);
}

TEST(heating_ineffective_when_heater_disconnected) {
    Rig r;
    r.plant.faults.heaterDisconnected = true;
    r.start(Material::PA, 70.0f, 4 * 3600);
    CHECK(r.runUntil([&] { return is(r, DeviceState::ERROR); }, 15 * 60));
    CHECK_EQ((int)r.error(), (int)ErrorCode::HEATING_INEFFECTIVE);
}

TEST(preheat_timeout_with_weak_heater) {
    Rig r;
    r.plant.heatCapacityJPerK = 12000.0f;  // very heavy load: keeps rising >2 C/10 min but too slowly
    r.start(Material::PA, 70.0f, 4 * 3600);
    CHECK(r.runUntil([&] { return is(r, DeviceState::ERROR); }, 100 * 60));
    CHECK_EQ((int)r.error(), (int)ErrorCode::PREHEAT_TIMEOUT);
}

TEST(ntc_open_during_session) {
    Rig r;
    r.start(Material::ABS, 65.0f, 4 * 3600);
    r.runSeconds(120);
    r.plant.faults.ntcOpen = true;
    CHECK(r.runUntil([&] { return is(r, DeviceState::ERROR); }, 10));
    CHECK_EQ((int)r.error(), (int)ErrorCode::NTC_OPEN);
}

TEST(ntc_detached_is_caught_by_plausibility) {
    Rig r;
    r.start(Material::ABS, 65.0f, 4 * 3600);
    CHECK(r.runUntil([&] { return r.plant.chamberC > 40.0f; }, 3600));
    r.plant.faults.ntcDetachedReadsAmbient = true;
    CHECK(r.runUntil([&] { return is(r, DeviceState::ERROR); }, 120));
    CHECK_EQ((int)r.error(), (int)ErrorCode::NTC_OPEN);
}

TEST(ble_disconnect_does_not_stop_session) {
    Rig r;
    r.ctl.setClientConnected(true);
    r.start(Material::PLA, 50.0f, 1800);
    r.runSeconds(60);
    r.ctl.setClientConnected(false);  // phone walked away
    CHECK(r.runUntil([&] { return is(r, DeviceState::COMPLETED); }, 3 * 3600));
    CHECK_EQ((int)r.ctl.snapshot().endReason, (int)EndReason::COMPLETED);
    CHECK(!r.invariantViolated);
}

TEST(reboot_never_resumes_and_reports_unexpected_reset) {
    DryerController c;
    c.begin(5000, ResetCause::WATCHDOG, 17, ErrorCode::NONE);
    CHECK_EQ((int)c.snapshot().state, (int)DeviceState::IDLE);
    CHECK_EQ((int)c.snapshot().error, (int)ErrorCode::UNEXPECTED_RESET);
    CHECK_EQ((int)c.lastLatchedFault(), (int)ErrorCode::UNEXPECTED_RESET);
    sim::Plant p;
    ControllerOutputs o = c.update(p.read(5250, false));
    CHECK(!o.relay);
    CHECK_EQ(o.heaterDuty, 0);
    // Session counter continues from NVS value.
    Command cmd;
    cmd.version = 1;
    cmd.opcode = Opcode::START_SESSION;
    cmd.material = Material::PLA;
    cmd.targetCentiC = 4500;
    cmd.durationSec = 3600;
    cmd.unixTime = 1790000000u;
    Response a = c.handleCommand(cmd, 5500);
    CHECK_EQ((int)a.result, (int)ResultCode::OK);
    CHECK_EQ(a.payload[0], 18);
}

TEST(lowering_target_mid_session_does_not_trip_overtemp) {
    Rig r;
    r.start(Material::PETG, 65.0f, 4 * 3600);
    CHECK(r.runUntil([&] { return is(r, DeviceState::DRYING); }, 3600));
    r.runSeconds(600);
    int16_t t = 4500;
    uint8_t p[2] = {static_cast<uint8_t>(t & 0xFF), static_cast<uint8_t>(t >> 8)};
    CHECK_EQ((int)r.send(Opcode::SET_TARGET_TEMP, p, 2).result, (int)ResultCode::OK);
    r.runSeconds(3600);
    CHECK(is(r, DeviceState::DRYING));
    CHECK(r.plant.chamberC < 48.0f);
}

TEST(command_state_rules) {
    Rig r;
    uint8_t off = static_cast<uint8_t>(FanMode::OFF);
    CHECK_EQ((int)r.send(Opcode::SET_FAN_MODE, &off, 1).result, (int)ResultCode::OK);  // allowed when idle
    r.start(Material::PLA, 45.0f, 3600);
    r.tick();
    CHECK(r.out.fan);  // fan forced on while heating even though mode is OFF
    CHECK_EQ((int)r.send(Opcode::SET_FAN_MODE, &off, 1).result, (int)ResultCode::NOT_ALLOWED_IN_STATE);
    CHECK_EQ((int)r.start(Material::PLA, 45.0f, 3600).result, (int)ResultCode::BUSY);
    CHECK_EQ((int)r.send(Opcode::RESET_SESSION).result, (int)ResultCode::BUSY);
    CHECK_EQ((int)r.send(Opcode::REQUEST_STATUS).result, (int)ResultCode::OK);
    CHECK_EQ((int)r.send(Opcode::IDENTIFY).result, (int)ResultCode::OK);
    r.tick();
    CHECK(r.out.identify);
    uint8_t name[] = {'D', 'r', 'y', 'e', 'r', ' ', '2'};
    CHECK_EQ((int)r.send(Opcode::SET_DEVICE_NAME, name, sizeof(name)).result, (int)ResultCode::OK);
    char got[24];
    CHECK(r.ctl.takePendingName(got, sizeof(got)));
    CHECK(std::string(got) == "Dryer 2");
    CHECK(!r.ctl.takePendingName(got, sizeof(got)));
}

TEST(set_duration_during_drying_shortens_session) {
    Rig r;
    r.start(Material::PLA, 45.0f, 4 * 3600);
    CHECK(r.runUntil([&] { return is(r, DeviceState::DRYING); }, 3600));
    r.runSeconds(1000);
    uint8_t d[4] = {0x84, 0x03, 0, 0};  // 900 s < elapsed -> complete now
    CHECK_EQ((int)r.send(Opcode::SET_DURATION, d, 4).result, (int)ResultCode::OK);
    r.tick();
    CHECK(is(r, DeviceState::COOLDOWN));
    CHECK_EQ((int)r.ctl.snapshot().endReason, (int)EndReason::COMPLETED);
}

TEST(local_button_stop_and_reset) {
    Rig r;
    r.start(Material::PLA, 45.0f, 3600);
    r.runSeconds(30);
    r.ctl.localStop(r.nowMs);
    r.tick();
    CHECK(is(r, DeviceState::COOLDOWN) || is(r, DeviceState::IDLE));  // chamber still cool -> IDLE at once
    CHECK_EQ((int)r.ctl.snapshot().endReason, (int)EndReason::STOPPED_ON_DEVICE);
    CHECK_EQ(r.out.heaterDuty, 0);
    CHECK(!r.out.relay);
    CHECK(r.ctl.localReset(r.nowMs));
}

TEST(fuzz_random_commands_and_faults_never_violate_invariants) {
    std::srand(1234);
    for (int run = 0; run < 12; ++run) {
        Rig r;
        for (int step = 0; step < 4 * 3600 * 3; ++step) {
            if (std::rand() % 400 == 0) {
                switch (std::rand() % 9) {
                    case 0: r.start(static_cast<Material>(std::rand() % kMaterialCount), 35.0f + static_cast<float>(std::rand() % 36), static_cast<uint32_t>(900 + std::rand() % 20000)); break;
                    case 1: r.send(Opcode::STOP_SESSION); break;
                    case 2: r.send(Opcode::RESET_SESSION); break;
                    case 3: { int16_t t = static_cast<int16_t>(3500 + std::rand() % 3501); uint8_t p[2] = {static_cast<uint8_t>(t & 0xFF), static_cast<uint8_t>(t >> 8)}; r.send(Opcode::SET_TARGET_TEMP, p, 2); break; }
                    case 4: { uint8_t m = static_cast<uint8_t>(std::rand() % 3); r.send(Opcode::SET_FAN_MODE, &m, 1); break; }
                    case 5: r.plant.faults.sensorDisconnected = !r.plant.faults.sensorDisconnected; break;
                    case 6: r.plant.faults.fanBroken = !r.plant.faults.fanBroken; break;
                    case 7: r.plant.faults.ntcOpen = !r.plant.faults.ntcOpen; break;
                    case 8: r.ctl.localStop(r.nowMs); break;
                }
            }
            r.tick();
            if (r.invariantViolated) break;
        }
        CHECK(!r.invariantViolated);
        CHECK(r.maxChamberC < 80.5f);
    }
}
