/* 
 * Ecstazy Nissan 300ZX Diagnostic Tuning Suite
 *
 * Copyright (C) 2003-2009   Patrick Cole <z@amused.net>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */
#ifndef _ECU_H
#define _ECU_H

#define ECU_DBG_OFF     (0)
#define ECU_DBG_VERBOSE (1)
#define ECU_DBG_ANAL    (2)

/* ECU Return values */

enum ECURet {
	ECU_OK = 0,
	ECU_READ_OK = 0,
	ECU_READ_TIMEOUT,
	ECU_ERR_BUSY,
	ECU_ERR_INVALID_RESPONSE,
	ECU_ERR_NO_START_BYTE,
	ECU_ERR_NO_RESPONSE,
	ECU_ERR_OPEN_SERIAL_DEV,
	ECU_ERR_CLOSE_SERIAL_DEV,
	ECU_ERR_WRITE_SERIAL_DEV,
	ECU_ERR_READ_SERIAL_DEV,
	ECU_ERR_NOT_INITIALISED,
	ECU_ERR_STATE_INVALID,
	ECU_ERR_DATA_LEN,
	ECU_ERR_PARAM_INVALID
};

#define ECU_PRINT_ERROR(ecode) \
	fprintf(stderr, "ECU ERR (%s:%d) %s\n", __FILE__, __LINE__, ecu_err_str(ecode));

#define ECU_CHECK_OK(eval) { \
	int ret = eval; \
	if (ret != ECU_OK) ECU_PRINT_ERROR(ret); \
}

#define ECU_ASSERT_OK(eval) { \
	int ret = eval; \
	if (ret != ECU_OK) { \
		ECU_PRINT_ERROR(ret); \
		exit(ret); \
	} \
}

/* ECU Commands */

enum ECUCommand {
	ECU_COMMAND_READ_FAULT_CODES              = 0xD1,
	ECU_COMMAND_RESET_FAULT_CODES             = 0xC1,
	ECU_COMMAND_READ_ECU_PART_NUMBER          = 0xD0,
	ECU_COMMAND_READ_ROM_BYTE                 = 0xC9,
	ECU_COMMAND_READ_REGISTER_PARAMETER       = 0x5A,
	ECU_COMMAND_ACTIVE_TEST                   = 0x0A,

	ECU_COMMAND_TERM                          = 0xF0,
	ECU_COMMAND_STOP_STREAM                   = 0x30
};

/* ECU Active Tests */

enum ECUActiveTest {
	ECU_ACTIVE_TEST_ADJ_COOLANT_TEMP          = 0x80,
	ECU_ACTIVE_TEST_ADJ_FUEL_INJ_TIME         = 0x81,
	ECU_ACTIVE_TEST_ADJ_IGNITION_TIMING       = 0x82,
	ECU_ACTIVE_TEST_ADJ_IAAC_VALVE_OPENING    = 0x84,
	ECU_ACTIVE_TEST_POWER_BALANCE             = 0x88,
	ECU_ACTIVE_TEST_FUEL_PUMP_RELAY           = 0x89,
	ECU_ACTIVE_TEST_CLEAR_SELF_LEARN          = 0x8B
};

enum ECUActiveTestData {
	ECU_FUEL_INJECTION_NORMAL                     = 0x64,
	/* 0x63 = -1% */
	/* 0x65 = +1% */

	ECU_IGNITION_TIMING_NORMAL                    = 0x00,
	/* 0x01 = +1 deg */
	/* 0xFF = -1 deg */

	ECU_IAAC_VALVE_OPEN_NORMAL                    = 0x00,
	/* 0x01 = +0.5% */
	/* 0xFF = -0.5% */

	ECU_POWER_BALANCE_FIRING_NORMAL               = 0x00,
	ECU_POWER_BALANCE_CYL_1_OFF                   = 0x01,
	ECU_POWER_BALANCE_CYL_2_OFF                   = 0x02,
	ECU_POWER_BALANCE_CYL_3_OFF                   = 0x03,
	ECU_POWER_BALANCE_CYL_4_OFF                   = 0x04,
	ECU_POWER_BALANCE_CYL_5_OFF                   = 0x05,
	ECU_POWER_BALANCE_CYL_6_OFF                   = 0x06,
	ECU_POWER_BALANCE_CYL_7_OFF                   = 0x07,
	ECU_POWER_BALANCE_CYL_8_OFF                   = 0x08,

	ECU_FUEL_PUMP_RELAY_ON                        = 0x00,
	ECU_FUEL_PUMP_RELAY_OFF                       = 0x01,

	ECU_CLEAR_SELF_LEARN_VALUE                    = 0x00
};

/* ECU Registers */

enum ECURegister {
	/* registers with known working conversions */

	ECU_REGISTER_CAS_POSITION_MSB              = 0x00,        /* Value * 12.5 (RPM) */
	ECU_REGISTER_CAS_POSITION_LSB              = 0x01,        
	ECU_REGISTER_CAS_REFERENCE_MSB             = 0x02,        /* Value * 8 (RPM) */
	ECU_REGISTER_CAS_REFERENCE_LSB             = 0x03,        
	ECU_REGISTER_MAF_VOLTAGE_MSB               = 0x04,        /* Value * 5 (mV) */
	ECU_REGISTER_MAF_VOLTAGE_LSB               = 0x05,        
	ECU_REGISTER_RH_MAF_VOLTAGE_MSB            = 0x06,        /* Value * 5 (mV) */
	ECU_REGISTER_RH_MAF_VOLTAGE_LSB            = 0x07,        
	ECU_REGISTER_COOLANT_TEMP                  = 0x08,        /* Value - 50 (deg C) */
	ECU_REGISTER_LH_O2_SENSOR_VOLTAGE          = 0x09,        /* Value * 10 (mV) */
	ECU_REGISTER_RH_O2_SENSOR_VOLTAGE          = 0x0a,        /* Value * 10 (mV) */
	ECU_REGISTER_VEHICLE_SPEED                 = 0x0b,        /* Value * 2 (km/h) */
	ECU_REGISTER_BATTERY_VOLTAGE               = 0x0c,        /* Value * 80 (mV) */
	ECU_REGISTER_THROTTLE_POSITION_VOLTAGE     = 0x0d,        /* Value * 20 (mV) */
	ECU_REGISTER_FUEL_TEMP                     = 0x0f,        /* Value - 50 (deg C) */
	ECU_REGISTER_INTAKE_AIR_TEMP               = 0x11,        /* Value - 50 (deg C) */
	ECU_REGISTER_EXHAUST_GAS_TEMP              = 0x12,        /* Value * 20 (mV)  ???? */
	ECU_REGISTER_LH_INJECTION_TIME_MSB         = 0x14,        /* Value / 100 (ms) */
	ECU_REGISTER_LH_INJECTION_TIME_LSB         = 0x15,        
	ECU_REGISTER_IGNITION_TIMING               = 0x16,        /* 110 - Value (deg BTDC) */
	ECU_REGISTER_IDLE_AIR_VALVE_PERCENT        = 0x17,        /* Value / 2 (%) */
	ECU_REGISTER_LH_AIR_FUEL_ALPHA             = 0x1a,        /* Value (%) */
	ECU_REGISTER_RH_AIR_FUEL_ALPHA             = 0x1b,        /* Value (%) */
	ECU_REGISTER_LH_AIR_FUEL_ALPHA_SELF_LEARN  = 0x1c,        /* Value (%) */
	ECU_REGISTER_RH_AIR_FUEL_ALPHA_SELF_LEARN  = 0x1d,        /* Value (%) */
	ECU_REGISTER_RH_INJECTION_TIME_MSB         = 0x22,        /* Value / 100 (ms) */
	ECU_REGISTER_RH_INJECTION_TIME_LSB         = 0x23,        /* Value / 100 (ms) */

	/* registers without known conversions */

  ECU_REGISTER_WASTE_GATE_SOLENOID_PERCENT   = 0x28,
  ECU_REGISTER_TURBO_BOOST_SENSOR_VOLTAGE    = 0x29,
  ECU_REGISTER_ENGINE_MOUNT_ON_OFF           = 0x2a,
  ECU_REGISTER_POSITION_COUNTER              = 0x2e,
  ECU_REGISTER_PURG_VOL_CONT_VALVE           = 0x25,
  ECU_REGISTER_TANK_FUEL_TEMP                = 0x26,
  ECU_REGISTER_FPCM_DR_VOLTAGE               = 0x27,
  ECU_REGISTER_FUEL_GAUGE_VOLTAGE            = 0x2f,
  ECU_REGISTER_FR_O2_HEATER_B1               = 0x30,
  ECU_REGISTER_FR_O2_HEATER_B2               = 0x31,
  ECU_REGISTER_IGN_SW                        = 0x32,
  ECU_REGISTER_CAL_LD_VALUE                  = 0x33,
  ECU_REGISTER_B_FUEL_SCHEDULE               = 0x34,
  ECU_REGISTER_RR_O2_SENSOR_VOLTAGE_B1       = 0x35,
  ECU_REGISTER_RR_O2_SENSOR_VOLTAGE_B2       = 0x36,
  ECU_REGISTER_ABS_THROTTLE_POSITION         = 0x37,
  ECU_REGISTER_MAF_GM_PER_SEC                = 0x38,

	ECU_REGISTER_NULL                          = 0xFF
};

#define MAX_MONITOR_PARAMETERS               20
#define MAX_FAULT_CODES                      20

enum ECUMonitorParameter {
	MON_PARAM_NULL = 0,
	MON_PARAM_CAS_POS,
	MON_PARAM_CAS_REF,
	MON_PARAM_MAF_VOLT,
	MON_PARAM_RH_MAF_VOLT,
	MON_PARAM_COOLANT_TEMP,
	MON_PARAM_LH_O2_VOLT,
	MON_PARAM_RH_O2_VOLT,
	MON_PARAM_SPEED,
	MON_PARAM_BAT_VOLT,
	MON_PARAM_TPS_VOLT,
	MON_PARAM_FUEL_TEMP,
	MON_PARAM_INTAKE_AIR_TEMP,
	MON_PARAM_EXHAUST_GAS_TEMP,
	MON_PARAM_LH_INJECTION_TIME,
	MON_PARAM_IGN_TIMING,
	MON_PARAM_IDLE_AIR_VALVE,
	MON_PARAM_LH_AF_ALPHA,
	MON_PARAM_RH_AF_ALPHA,
	MON_PARAM_LH_AF_ALPHA_SL,
	MON_PARAM_RH_AF_ALPHA_SL,
	MON_PARAM_RH_INJECTION_TIME,
	MON_PARAM_WASTE_GATE_SOLENOID,
	MON_PARAM_TURBO_BOOST_SENSOR_VOLTAGE,
	MON_PARAM_ENGINE_MOUNT_ON_OFF,
	MON_PARAM_POSITION_COUNTER,
	MON_PARAM_PURG_VOL_CONT_VALVE,
	MON_PARAM_TANK_FUEL_TEMP,
	MON_PARAM_FPCM_DR_VOLTAGE,
	MON_PARAM_FUEL_GAUGE_VOLTAGE,
	MON_PARAM_FR_O2_HEATER_B1,
	MON_PARAM_FR_O2_HEATER_B2,
	MON_PARAM_IGN_SW,
	MON_PARAM_CAL_LD_VALUE,
	MON_PARAM_B_FUEL_SCHEDULE,
	MON_PARAM_RR_O2_SENSOR_VOLTAGE_B1,
	MON_PARAM_RR_O2_SENSOR_VOLTAGE_B2,
	MON_PARAM_ABS_THROTTLE_POSITION,
	MON_PARAM_MAF_GM_PER_SEC
};

struct ecu_fault_code {
	byte code;
	byte starts;
};

struct ecu_reg_mon_param {
	int id;
	byte reg_msb;
	byte reg_lsb;
	double (*valueConvertFunc)(word value);
	char *description;
	char *shortdesc;
	char *cmdname;
	char *unit;
};

/* use this to get the list of available parameters */
extern struct ecu_reg_mon_param ecu_monitor_available_params [];

struct ecu_mon_param_data {
	struct ecu_reg_mon_param *param;
	double value;
};

typedef void (*ECUMonitorCallback)(struct ecu_mon_param_data rdata[MAX_MONITOR_PARAMETERS], int n, void *arg);

/* external prototypes */

int ecu_init(const char *dev, int init_tries);
int ecu_close();
int ecu_read_byte_with_timeout(byte *b, long sec);
int ecu_recv_byte(byte *b);
int ecu_send_byte(byte b);
int ecu_process_data_from_fd();
int ecu_get_fd();
int ecu_read_fault_codes(struct ecu_fault_code faults[MAX_FAULT_CODES], int *count);
int ecu_reset_fault_codes();
int ecu_start_monitor(int *params, int npar, ECUMonitorCallback my_data_callback, void *my_arg);
int ecu_stop_monitor();
int ecu_active_test(enum ECUActiveTest test, byte data);
int ecu_atest_adj_coolant_temp(byte temp);
int ecu_atest_adj_fuel_inj_time(signedbyte adjustment);
int ecu_atest_adj_ignition_timing(signedbyte adjustment);
int ecu_atest_adj_iacv_valve_open(signedbyte adjustment);
int ecu_atest_power_balance(byte data);
int ecu_atest_fuel_pump_relay(enum ECUActiveTestData data);
int ecu_atest_clear_self_learn(enum ECUActiveTestData data);
const char *ecu_err_str(int code);

#endif

