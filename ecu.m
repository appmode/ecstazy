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

#include "common.h"

#define ECU_CHECK_INITIALISED() \
	if (ECUConfig.initialised == FALSE) { \
		debug(ECU_DBG_ANAL, "Called without initialising"); \
		return -ECU_ERR_NOT_INITIALISED; \
	}

#define ECU_CHECK_BUSY() \
	if (ECUConfig.streaming == TRUE) { \
		debug(ECU_DBG_ANAL, "Called while already streaming"); \
		return -ECU_ERR_BUSY; \
	}


struct reg_resp_data {
	byte resp_msb;
	byte resp_lsb;
};

struct {
	int serialfd;
	bool initialised;
	bool streaming;
	struct ecu_reg_mon_param *monitorParams[MAX_MONITOR_PARAMETERS];
	int monitorParamCount;
	ECUMonitorCallback mon_data_callback;
	void *mon_data_callback_arg;
	int virt_mon_cnt;
	int real_mon_cnt;
	struct reg_resp_data *resp_data;
} ECUConfig = {
	.initialised = FALSE,
	.streaming = FALSE,
	.monitorParamCount = 0
};

static double CAS_Position_Convert(word value) {return value * 12.5;}
static double CAS_Reference_Convert(word value) {return value * 8;}
static double MAF_Voltage_Convert(word value) {return value * 5;}
static double Temp_Convert(word value) {return value - 50;}
static double O2_Voltage_Convert(word value) {return value * 10;}
static double Vehicle_Speed_Convert(word value) {return value * 2;}
static double Battery_Voltage_Convert(word value) {return (value * 80) / 1000;}
static double TPS_Voltage_Convert(word value) {return value * 20;}
static double Injection_Time_Convert(word value) {return (double)value / 100;}
static double Ignition_Timing_Convert(word value) {return 110 - value;}
static double IACV_Percent_Convert(word value) {return value / 2;}

struct ecu_reg_mon_param ecu_monitor_available_params [] = {
	{ 
		MON_PARAM_CAS_POS,
		ECU_REGISTER_CAS_POSITION_MSB,
		ECU_REGISTER_CAS_POSITION_LSB,
		CAS_Position_Convert,
		"Engine Revs",
		"Revs",
		"cas-pos",
		"RPM"
	},
	{ 
		MON_PARAM_CAS_REF,
		ECU_REGISTER_CAS_REFERENCE_MSB,
		ECU_REGISTER_CAS_REFERENCE_LSB,
		CAS_Reference_Convert,
		"CAS Ref",
		"CAS",
		"cas-ref",
		"RPM"
	},
	{
		MON_PARAM_MAF_VOLT,
		ECU_REGISTER_MAF_VOLTAGE_MSB,
		ECU_REGISTER_MAF_VOLTAGE_LSB,
		MAF_Voltage_Convert,
		"Mass Airflow Voltage",
		"MAS",
		"maf-volt",
		"mV"
	},
	{
		MON_PARAM_RH_MAF_VOLT,
		ECU_REGISTER_RH_MAF_VOLTAGE_MSB,
		ECU_REGISTER_RH_MAF_VOLTAGE_LSB,
		MAF_Voltage_Convert,
		"Mass Airflow Voltage (RH)",
		"MAS RH",
		"rh-maf-volt",
		"mV"
	},
	{
		MON_PARAM_COOLANT_TEMP,
		ECU_REGISTER_COOLANT_TEMP,
		ECU_REGISTER_NULL,
		Temp_Convert,
		"Coolant Temperature",
		"Coolant",
		"coolant-temp",
		"C"
	},
	{
		MON_PARAM_LH_O2_VOLT,
		ECU_REGISTER_LH_O2_SENSOR_VOLTAGE,
		ECU_REGISTER_NULL,
		O2_Voltage_Convert,
		"O2 Sensor Voltage (LH)",
		"O2 LH",
		"o2-volt-left",
		"mV"
	},
	{
		MON_PARAM_RH_O2_VOLT,
		ECU_REGISTER_RH_O2_SENSOR_VOLTAGE,
		ECU_REGISTER_NULL,
		O2_Voltage_Convert,
		"O2 Sensor Voltage (RH)",
		"O2 RH",
		"o2-volt-right",
		"mV"
	},
	{
		MON_PARAM_SPEED,
		ECU_REGISTER_VEHICLE_SPEED,
		ECU_REGISTER_NULL,
		Vehicle_Speed_Convert,
		"Vehicle Speed",
		"Speed",
		"vehicle-spd",
		"km/h"
	},
	{
		MON_PARAM_BAT_VOLT,
		ECU_REGISTER_BATTERY_VOLTAGE,
		ECU_REGISTER_NULL,
		Battery_Voltage_Convert,
		"Battery Voltage",
		"Batt",
		"batt-voltage",
		"V"
	},
	{
		MON_PARAM_TPS_VOLT,
		ECU_REGISTER_THROTTLE_POSITION_VOLTAGE,
		ECU_REGISTER_NULL,
		TPS_Voltage_Convert,
		"TPS Voltage",
		"TPS",
		"tps-volt",
		"mV"
	},
	{
		MON_PARAM_FUEL_TEMP,
		ECU_REGISTER_FUEL_TEMP,
		ECU_REGISTER_NULL,
		Temp_Convert,
		"Fuel Rail Temperature",
		"Fuel/T",
		"fuel-temp",
		"C"
	},
	{
		MON_PARAM_INTAKE_AIR_TEMP,
		ECU_REGISTER_INTAKE_AIR_TEMP,
		ECU_REGISTER_NULL,
		Temp_Convert,
		"Intake Air Temp",
		"Intak/T",
		"intake-temp",
		"deg C"
	},
	{
		MON_PARAM_EXHAUST_GAS_TEMP,
		ECU_REGISTER_EXHAUST_GAS_TEMP,
		ECU_REGISTER_NULL,
		TPS_Voltage_Convert,
		"Exhaust Gas Temperature Voltage",
		"EGT",
		"egt-volt",
		"mV"
	},
	{
		MON_PARAM_LH_INJECTION_TIME,
		ECU_REGISTER_LH_INJECTION_TIME_MSB,
		ECU_REGISTER_LH_INJECTION_TIME_LSB,
		Injection_Time_Convert,
		"Injection Time (LH)",
		"L InjTm",
		"inj-time-left",
		"ms"
	},
	{
		MON_PARAM_IGN_TIMING,
		ECU_REGISTER_IGNITION_TIMING,
		ECU_REGISTER_NULL,
		Ignition_Timing_Convert,
		"Ignition Timing",
		"Ign Tmg",
		"ign-timing",
		"BTDC"
	},
	{
		MON_PARAM_IDLE_AIR_VALVE,
		ECU_REGISTER_IDLE_AIR_VALVE_PERCENT,
		ECU_REGISTER_NULL,
		IACV_Percent_Convert,
		"Idle Air Control Valve Opening",
		"IACV",
		"iacv-open",
		"%"
	},
	{
		MON_PARAM_LH_AF_ALPHA,
		ECU_REGISTER_LH_AIR_FUEL_ALPHA,
		ECU_REGISTER_NULL,
		NULL,
		"A/F Alpha (LH)",
		"A/F LH",
		"af-alpha-left",
		"%"
	},
	{
		MON_PARAM_RH_AF_ALPHA,
		ECU_REGISTER_RH_AIR_FUEL_ALPHA,
		ECU_REGISTER_NULL,
		NULL,
		"A/F Alpha (RH)",
		"A/F RH",
		"af-alpha-right",
		"%"
	},
	{
		MON_PARAM_LH_AF_ALPHA_SL,
		ECU_REGISTER_LH_AIR_FUEL_ALPHA_SELF_LEARN,
		ECU_REGISTER_NULL,
		NULL,
		"A/F Alpha Self Learn (LH)",
		"AF LN LH",
		"af-alpha-sl-left",
		"%"
	},
	{
		MON_PARAM_RH_AF_ALPHA_SL,
		ECU_REGISTER_RH_AIR_FUEL_ALPHA_SELF_LEARN,
		ECU_REGISTER_NULL,
		NULL,
		"A/F Alpha Self Learn (RH)",
		"AF LN RH",
		"af-alpha-sl-right",
		"%"
	},
	{
		MON_PARAM_RH_INJECTION_TIME,
		ECU_REGISTER_RH_INJECTION_TIME_MSB,
		ECU_REGISTER_RH_INJECTION_TIME_LSB,
		Injection_Time_Convert,
		"Injection Time (RH)",
		"R InjTm",
		"inj-time-right",
		"ms"
	},
	{
		MON_PARAM_WASTE_GATE_SOLENOID,
		ECU_REGISTER_WASTE_GATE_SOLENOID_PERCENT,
		ECU_REGISTER_NULL,
		NULL,
		"Wastegate Solenoid",
		"W/g Sol",
		"wastegate-sol",
		"%"
	},
	{
		MON_PARAM_TURBO_BOOST_SENSOR_VOLTAGE,
		ECU_REGISTER_TURBO_BOOST_SENSOR_VOLTAGE,
		ECU_REGISTER_NULL,
		NULL,
		"Boost Pressure",
		"Bst Pres",
		"boost-pres-volt",
		"V"
	},
	{
		MON_PARAM_ENGINE_MOUNT_ON_OFF,
		ECU_REGISTER_ENGINE_MOUNT_ON_OFF,
		ECU_REGISTER_NULL,
		NULL,
		"Engine Mount",
		"Eng Mnt",
		"eng-mount",
		"T/F"
	},
	{
		MON_PARAM_POSITION_COUNTER,
		ECU_REGISTER_POSITION_COUNTER,
		ECU_REGISTER_NULL,
		NULL,
		"Position Counter",
		"Pos Ctr",
		"pos-ctr",
		""
	},
	{
		MON_PARAM_PURG_VOL_CONT_VALVE,
		ECU_REGISTER_PURG_VOL_CONT_VALVE,
		ECU_REGISTER_NULL,
		NULL,
		"Purge Vol",
		"Prg Vol",
		"purge-vol",
		"Step"
	},
	{
		MON_PARAM_TANK_FUEL_TEMP,
		ECU_REGISTER_TANK_FUEL_TEMP,
		ECU_REGISTER_NULL,
		NULL,
		"Tank Fuel Temp",
		"TF/Temp",
		"tank-fuel-temp",
		"C"
	},
	{
		MON_PARAM_FPCM_DR_VOLTAGE,
		ECU_REGISTER_FPCM_DR_VOLTAGE,
		ECU_REGISTER_NULL,
		NULL,
		"FPCM DR",
		"FPCM",
		"fpcm-dr-volt",
		"V"
	},
	{
		MON_PARAM_FUEL_GAUGE_VOLTAGE,
		ECU_REGISTER_FUEL_GAUGE_VOLTAGE,
		ECU_REGISTER_NULL,
		NULL,
		"Fuel Gauge",
		"Fuel",
		"fuel-gauge-volt",
		"V"
	},
	{
		MON_PARAM_FR_O2_HEATER_B1,
		ECU_REGISTER_FR_O2_HEATER_B1,
		ECU_REGISTER_NULL,
		NULL,
		"Front O2 Heater Bank 1",
		"O2HtrB1",
		"front-o2-htr-b1",
		"?"
	},
	{
		MON_PARAM_FR_O2_HEATER_B2,
		ECU_REGISTER_FR_O2_HEATER_B2,
		ECU_REGISTER_NULL,
		NULL,
		"Front O2 Heater Bank 2",
		"O2HtrB2",
		"front-o2-htr-b2",
		"?"
	},
	{
		MON_PARAM_IGN_SW,
		ECU_REGISTER_IGN_SW,
		ECU_REGISTER_NULL,
		NULL,
		"Ignition Switch",
		"Ign Sw",
		"ign-switch",
		"T/F"
	},	
	{
		MON_PARAM_CAL_LD_VALUE,
		ECU_REGISTER_CAL_LD_VALUE,
		ECU_REGISTER_NULL,
		NULL,
		"Cal/LD Value",
		"Cal/LD",
		"cal-ld",
		"%"
	},
	{
		MON_PARAM_B_FUEL_SCHEDULE,
		ECU_REGISTER_B_FUEL_SCHEDULE,
		ECU_REGISTER_NULL,
		NULL,
		"B/Fuel Schedule",
		"B/Fuel",
		"back-fuel-sched",
		"mS"
	},
	{
		MON_PARAM_RR_O2_SENSOR_VOLTAGE_B1,
		ECU_REGISTER_RR_O2_SENSOR_VOLTAGE_B1,
		ECU_REGISTER_NULL,
		NULL,
		"Rear O2 Sensor Voltage Bank 1",
		"O2/RB1",
		"rear-o2-volt-b1",
		"V"
	},
	{
		MON_PARAM_RR_O2_SENSOR_VOLTAGE_B2,
		ECU_REGISTER_RR_O2_SENSOR_VOLTAGE_B2,
		ECU_REGISTER_NULL,
		NULL,
		"Rear O2 Sensor Voltage Bank 2",
		"O2/RB2",
		"rear-o2-volt-b2",
		"V"
	},
	{
		MON_PARAM_ABS_THROTTLE_POSITION,
		ECU_REGISTER_ABS_THROTTLE_POSITION,
		ECU_REGISTER_NULL,
		NULL,
		"Absolute Throttle Position",
		"AbsThrot",
		"abs-throt-pos",
		"V"
	},
	{
		MON_PARAM_MAF_GM_PER_SEC,
		ECU_REGISTER_MAF_GM_PER_SEC,
		ECU_REGISTER_NULL,
		NULL,
		"Mass Air Flow",
		"MAF",
		"maf",
		"gm/S"
	},
	{
		MON_PARAM_NULL,
		ECU_REGISTER_NULL,
		ECU_REGISTER_NULL,
		NULL,
		NULL,
		NULL
	}
};

/* timeout is in sec */
int ecu_read_byte_with_timeout(byte *b, long sec)
{
	fd_set readset;
	struct timeval tv, *tvp;
	int rv, ret;

	tv.tv_sec = sec;
	tv.tv_usec = 0;

	if (sec > 0)
		tvp = &tv;
	else
		tvp = NULL;

	while (1)
	{
		FD_ZERO(&readset);
		FD_SET(ECUConfig.serialfd, &readset);
		
		rv = select(ECUConfig.serialfd + 1, &readset, NULL, NULL, tvp);

		if (rv == 0) {
			debug(ECU_DBG_ANAL, "Read timed out after %d seconds", sec);
			return -ECU_READ_TIMEOUT;
		}
		
		if (rv > 0)
		{
			if (FD_ISSET(ECUConfig.serialfd, &readset))
			{
				ret = read(ECUConfig.serialfd, b, sizeof(byte));
				if (ret < 0)
				{
					debug_syserr(ECU_DBG_VERBOSE, "read(serialfd)");
					return -ECU_ERR_READ_SERIAL_DEV;
				}
				if (ret != sizeof(byte))
				{
					debug(ECU_DBG_VERBOSE, "Read %d bytes, but only %d were expected.", ret, sizeof(byte));
					return -ECU_ERR_DATA_LEN;
				}
				return ECU_OK;
			}
		}
	}
}

int ecu_recv_byte(byte *b)
{
	return ecu_read_byte_with_timeout(b, 10);
}

int ecu_send_byte(byte b)
{
	int ret = write(ECUConfig.serialfd, &b, sizeof(byte));
	if (ret < 0)
	{
		debug_syserr(ECU_DBG_VERBOSE, "write(ECUConfig.serialfd)");
		return -ECU_ERR_WRITE_SERIAL_DEV;
	}
	if (ret != sizeof(byte))
	{
		debug(ECU_DBG_VERBOSE, "Wrote %d bytes, but only %d were sent.", ret, sizeof(byte));
		return -ECU_ERR_DATA_LEN;
	}

	return ECU_OK;
}

int ecu_init(const char *dev, int init_tries)
{
	byte b;
	int i = 0;
	struct termios term;
	
	/* open port */
	if ((ECUConfig.serialfd = open(dev, O_RDWR)) < 0)
	{
		ECUConfig.initialised = FALSE;
		debug_syserr(ECU_DBG_VERBOSE, "open(%s) failed", dev);
		return -ECU_ERR_OPEN_SERIAL_DEV;
	}

	/* set serial parameters */
	memset(&term, 0, sizeof(term));
	tcgetattr(ECUConfig.serialfd, &term);
	cfmakeraw(&term);
	term.c_iflag &= ~(INPCK|ICRNL|INPCK);
	term.c_lflag &= ~(ECHO);
	cfsetispeed(&term, B9600);
	cfsetospeed(&term, B9600);
	tcsetattr(ECUConfig.serialfd, 0, &term);

	while (i < init_tries)
	{
		debug(ECU_DBG_ANAL, "Init Iteration %d  max=%d", i, init_tries);

		/* send ECU the init sequence */
		ecu_send_byte(0xFF);
		ecu_send_byte(0xFF);
		ecu_send_byte(0xEF);

		/* look for acknowledgement of 0x10, timeout after 2 sec */
		if (ecu_read_byte_with_timeout(&b, 2) == ECU_OK)
		{
			if (b == 0x10)
			{
				debug(ECU_DBG_VERBOSE, "ECU initialised successfully.");
				ECUConfig.initialised = TRUE;
				return ECU_OK;
			}
			else // if (b == 0x00) 
			{
				debug(ECU_DBG_VERBOSE, "ECU already initialised.");
				ecu_send_byte(ECU_COMMAND_STOP_STREAM);
				/* discard remaining buffered data */
				while (ecu_read_byte_with_timeout(&b, 1) == ECU_OK)
					debug(ECU_DBG_ANAL, "Discard unwanted byte %02x", b);
				ECUConfig.initialised = TRUE;
				return ECU_OK;
			}
		}

		i++;
	}

	debug(ECU_DBG_VERBOSE, "Unable to contact ECU.");
	ECUConfig.initialised = FALSE;
	close(ECUConfig.serialfd);
	return -ECU_ERR_NO_RESPONSE;
}

int ecu_start_monitor(int *params, int npar, ECUMonitorCallback my_data_callback, void *my_arg)
{
	byte b;
	int i;
	struct ecu_reg_mon_param *ptr;
	char buf[BUFSIZ], hex[20];

	ECU_CHECK_INITIALISED();
	ECU_CHECK_BUSY();

	ECUConfig.mon_data_callback = my_data_callback;
	ECUConfig.mon_data_callback_arg = my_arg;

	// put values into monitorParams
	
	ECUConfig.monitorParamCount = 0;
	for (i = 0; i < npar; i++) {
		for (ptr = ecu_monitor_available_params; ptr->id != MON_PARAM_NULL; ptr++) {
			if (params[i] == ptr->id) {
				ECUConfig.monitorParams[ECUConfig.monitorParamCount++] = ptr;
			}
		}
	}

	// TEMP: try to get ECU to stream some sensors to us
	
	ECUConfig.virt_mon_cnt = 0;
	ECUConfig.real_mon_cnt = 0;
	
	for (i = 0; i < ECUConfig.monitorParamCount; i++) {
		ptr = ECUConfig.monitorParams[i];

		ecu_send_byte(ECU_COMMAND_READ_REGISTER_PARAMETER);
		ecu_send_byte(ptr->reg_msb);
		ECUConfig.real_mon_cnt++;
		ECUConfig.virt_mon_cnt++;

		if (ptr->reg_lsb != ECU_REGISTER_NULL) 
		{
			ecu_send_byte(ECU_COMMAND_READ_REGISTER_PARAMETER);
			ecu_send_byte(ptr->reg_lsb);
			ECUConfig.real_mon_cnt++;
		}
	}

	ecu_send_byte(ECU_COMMAND_TERM);

	// allocate space for responses
	ECUConfig.resp_data = malloc(ECUConfig.virt_mon_cnt * sizeof(struct reg_resp_data));

	debug(ECU_DBG_VERBOSE, "Monitoring %d sensors (%d registers)", ECUConfig.virt_mon_cnt, ECUConfig.real_mon_cnt);

	ecu_recv_byte(&b);
	if (b != (byte)~((byte)ECU_COMMAND_READ_REGISTER_PARAMETER))
	{
		debug(ECU_DBG_VERBOSE, "Command did not execute: received: 0x%02x, wanted: 0x%02x.", 
				   b, (byte)~((byte)ECU_COMMAND_READ_REGISTER_PARAMETER));
		return -ECU_ERR_INVALID_RESPONSE;
	}

	*buf=0;
	for (i = 0; i < ((ECUConfig.real_mon_cnt * 2) - 1); i++) { /* other bit of command response */
		ecu_recv_byte(&b);
		sprintf(hex, "%02x ", b);
		strcat(buf, hex);
	}
	debug(ECU_DBG_VERBOSE, "Command response: %s", buf);

	ecu_recv_byte(&b);
	if (b != 0xFF)
	{
		debug(ECU_DBG_VERBOSE, "Failed to receive FF to mark start of data block.");
		return -ECU_ERR_NO_START_BYTE;
	}

	// ready for stream data now
	ECUConfig.streaming = TRUE;

	return ECU_OK;
}

int ecu_stop_monitor()
{
	byte b;

	ECU_CHECK_INITIALISED();

	if (ECUConfig.streaming == TRUE) {
		ecu_send_byte(ECU_COMMAND_STOP_STREAM);

		/* Eat up and stray data */
		while (ecu_read_byte_with_timeout(&b, 1) == ECU_OK)
			debug(ECU_DBG_ANAL, "Discard unwanted byte %02x", b);

		ECUConfig.streaming = FALSE;

		return ECU_OK;
	}

	return -ECU_ERR_STATE_INVALID;
}

/* 
 * Examples:
 *
 * ecu_active_test(ECU_ACTIVE_TEST_ADJ_COOLANT_TEMP,  50);
 * ecu_active_test(ECU_ACTTVE_TEST_ADJ_FUEL_INJ_TIME, FUEL_INJECTION_NORMAL + 1);
 * ecu_active_test(ECU_ACTTVE_TEST_ADJ_FUEL_INJ_TIME, FUEL_INJECTION_NORMAL - 1);
 * ecu_active_test(ECU_ACTTVE_TEST_POWER_BALANCE,     ECU_POWER_BALANCE_CYL_1_OFF);
 * ecu_active_test(ECU_ACTTVE_TEST_POWER_BALANCE,     ECU_POWER_BALANCE_NORMAL);
 * 
 **/
int ecu_active_test(enum ECUActiveTest test, byte data)
{
	byte b;

	ECU_CHECK_INITIALISED();
	ECU_CHECK_BUSY();

	debug(ECU_DBG_ANAL, "Starting active test %.02X | data = %.02X", test, data);

	ecu_send_byte(ECU_COMMAND_ACTIVE_TEST);
	ecu_send_byte(test);
	ecu_send_byte(data);
	ecu_send_byte(ECU_COMMAND_TERM);

	ecu_recv_byte(&b);
	if (b != (byte)~((byte)ECU_COMMAND_ACTIVE_TEST))
	{
		debug(ECU_DBG_VERBOSE, "Command did not execute: received: 0x%02x, wanted: 0x%02x.", 
				   b, (byte)~((byte)ECU_COMMAND_ACTIVE_TEST));
		return -ECU_ERR_INVALID_RESPONSE;
	}

	sleep(3);

	ecu_send_byte(ECU_COMMAND_STOP_STREAM);

	while (ecu_read_byte_with_timeout(&b, 1) == ECU_OK)
		debug(ECU_DBG_ANAL, "Discard unwanted byte %02x", b);

	return ECU_OK;
}

int ecu_atest_adj_coolant_temp(byte temp)
{
	if (temp <= 150)
		return ecu_active_test(ECU_ACTIVE_TEST_ADJ_COOLANT_TEMP, temp);
	else
		return -ECU_ERR_PARAM_INVALID;
}

int ecu_atest_adj_fuel_inj_time(signedbyte adjustment)
{
	if (adjustment + ECU_FUEL_INJECTION_NORMAL <= 0xFF &&
			adjustment + ECU_FUEL_INJECTION_NORMAL >= 0x00)
		return ecu_active_test(ECU_ACTIVE_TEST_ADJ_COOLANT_TEMP, ECU_FUEL_INJECTION_NORMAL + adjustment);
	else
		return -ECU_ERR_PARAM_INVALID;
}

/*
 * range = -127 deg to +127 deg
 * steps = 1 unit per 1 deg
 */
int ecu_atest_adj_ignition_timing(signedbyte adjustment)
{
	byte realadjustment;

	if (adjustment < 0)
		realadjustment = (0xFF + adjustment);
	else
		realadjustment = adjustment;

	return ecu_active_test(ECU_ACTIVE_TEST_ADJ_IGNITION_TIMING, realadjustment);
}

/*
 * range = -63% to +63%
 * steps = 1 unit per 0.5%
 */
int ecu_atest_adj_iacv_valve_open(signedbyte adjustment)
{
	byte realadjustment;

	if (adjustment < 0)
		realadjustment = (0xFF + adjustment);
	else
		realadjustment = adjustment;

	return ecu_active_test(ECU_ACTIVE_TEST_ADJ_IGNITION_TIMING, realadjustment);
}

/* bit field */
int ecu_atest_power_balance(byte data)
{
	byte newdata = data & (
		ECU_POWER_BALANCE_CYL_1_OFF | ECU_POWER_BALANCE_CYL_2_OFF |
		ECU_POWER_BALANCE_CYL_3_OFF | ECU_POWER_BALANCE_CYL_4_OFF |
		ECU_POWER_BALANCE_CYL_5_OFF | ECU_POWER_BALANCE_CYL_6_OFF |
		ECU_POWER_BALANCE_CYL_7_OFF | ECU_POWER_BALANCE_CYL_8_OFF);
	return ecu_active_test(ECU_ACTIVE_TEST_POWER_BALANCE, newdata);
}

int ecu_atest_fuel_pump_relay(enum ECUActiveTestData data)
{
	switch (data) {
		case ECU_FUEL_PUMP_RELAY_ON:
		case ECU_FUEL_PUMP_RELAY_OFF:
			return ecu_active_test(ECU_ACTIVE_TEST_FUEL_PUMP_RELAY, data);
		default:
			return -ECU_ERR_PARAM_INVALID;
	}
}

int ecu_atest_clear_self_learn(enum ECUActiveTestData data)
{
	return ecu_active_test(ECU_ACTIVE_TEST_CLEAR_SELF_LEARN, ECU_CLEAR_SELF_LEARN_VALUE);
}
int ecu_get_fd()
{
	return ECUConfig.serialfd;
}

int ecu_close()
{
	debug(ECU_DBG_VERBOSE, "Closing ECU connection");
	if (ECUConfig.initialised == TRUE) {
		if (ECUConfig.streaming == TRUE) {
			debug(ECU_DBG_VERBOSE, "Stopping sensor stream");
			ecu_send_byte(ECU_COMMAND_STOP_STREAM);
			ECUConfig.streaming = FALSE;
		}
		if (close(ECUConfig.serialfd) < 0) {
			debug_syserr(ECU_DBG_VERBOSE, "Close serial port failed");
			ECUConfig.initialised = FALSE;
			return -ECU_ERR_CLOSE_SERIAL_DEV;
		} else {
			ECUConfig.initialised = FALSE;
			return ECU_OK;
		}
	} else {
		debug(ECU_DBG_VERBOSE, "Called without ECU being initialised");
		return -ECU_ERR_NOT_INITIALISED;
	}
}

int ecu_process_data_from_fd()
{
	int i;
	byte b;
	word w1;
	double v;
	byte dataCount;
	static struct ecu_mon_param_data rdata[MAX_MONITOR_PARAMETERS];
	struct ecu_reg_mon_param *ptr;

	ECU_CHECK_INITIALISED();

	if (ecu_recv_byte(&dataCount) != ECU_OK)
	{
		debug(ECU_DBG_VERBOSE, "Failed to receive stream byte count.");
		return -ECU_ERR_INVALID_RESPONSE;
	}

	if (dataCount != ECUConfig.real_mon_cnt)
	{
		debug(ECU_DBG_VERBOSE,
			"The number of data items the ECU is streaming (%d) is not the same as what we expected (%d).", dataCount, ECUConfig.real_mon_cnt);
		return -ECU_ERR_INVALID_RESPONSE;
	}

	//printf("dataCount = %d\n", dataCount);

	for (i = 0; i < ECUConfig.virt_mon_cnt; i++)
	{
		if (ecu_recv_byte(&(ECUConfig.resp_data[i].resp_msb)) != ECU_OK)
		{
			debug(ECU_DBG_VERBOSE, "Short read from ECU. Data was expected, but not received.");
			return -ECU_ERR_NO_RESPONSE;
		}

		if (ECUConfig.monitorParams[i]->reg_lsb != ECU_REGISTER_NULL)
		{
			if (ecu_recv_byte(&(ECUConfig.resp_data[i].resp_lsb)) != ECU_OK)
			{
				debug(ECU_DBG_VERBOSE, "Short read from ECU. Data was expected, but not received.");
				return -ECU_ERR_NO_RESPONSE;
			}
		}
	}

	ecu_recv_byte(&b);
	if (b != 0xFF)
	{
		debug(ECU_DBG_VERBOSE, "No data block end byte = FF, instead = %02x.", b);
		return -ECU_ERR_INVALID_RESPONSE;
	}

	memset(rdata, 0, sizeof(rdata));

	for (i = 0; i < ECUConfig.monitorParamCount; i++)
	{
		ptr = ECUConfig.monitorParams[i];
		if (ptr->reg_lsb != ECU_REGISTER_NULL)
		{
			w1 = ECUConfig.resp_data[i].resp_msb;
			w1 <<= 8;
			w1 |= ECUConfig.resp_data[i].resp_lsb;
		}
		else
			w1 = ECUConfig.resp_data[i].resp_msb;
	
		if (ptr->valueConvertFunc)
			v = ptr->valueConvertFunc(w1);
		else
			v = w1;

		rdata[i].value = v;
		rdata[i].param = ptr;
	}

	ECUConfig.mon_data_callback(rdata, ECUConfig.monitorParamCount, ECUConfig.mon_data_callback_arg);

	return ECU_OK;
}

int ecu_read_fault_codes(struct ecu_fault_code faults[MAX_FAULT_CODES], int *count)
{
	byte b, len, i;
	int ret;

	*count = 0;

	ecu_send_byte(ECU_COMMAND_READ_FAULT_CODES);

	ecu_recv_byte(&b);
	if (b != (byte)~((byte)ECU_COMMAND_READ_FAULT_CODES))
	{
		debug(ECU_DBG_VERBOSE, "Command did not execute: received: 0x%02x, wanted: 0x%02x.", 
				   b, (byte)~((byte)ECU_COMMAND_READ_FAULT_CODES));
		return -ECU_ERR_INVALID_RESPONSE;
	}

	ecu_send_byte(ECU_COMMAND_TERM);

	ecu_recv_byte(&b);
	if (b != 0xFF)
	{
		debug(ECU_DBG_VERBOSE, "Command did not execute: received: 0x%02x, wanted SOF: 0x%02x.", 
				   b, 0xFF);
		return -ECU_ERR_INVALID_RESPONSE;
	}

	if ((ret = ecu_recv_byte(&len)) != ECU_OK) {
		debug(ECU_DBG_VERBOSE, "Unable to read the response data length");
		return ret;
	}

	/* read one set */
	for (i = 0; i < len; i++) {
		if ((ret = ecu_recv_byte(&faults[i].code)) != ECU_OK) {
			debug(ECU_DBG_VERBOSE, "Failed reading fault code number %d");
			return ret;
		}
		if ((ret = ecu_recv_byte(&faults[i].starts)) != ECU_OK) {
			debug(ECU_DBG_VERBOSE, "Failed reading fault code number %d");
			return ret;
		}
	}

	*count = len;

	ecu_send_byte(ECU_COMMAND_STOP_STREAM);

	return ECU_OK;
}

int ecu_reset_fault_codes()
{
	byte b;

	ecu_send_byte(ECU_COMMAND_RESET_FAULT_CODES);

	ecu_recv_byte(&b);
	if (b != (byte)~((byte)ECU_COMMAND_RESET_FAULT_CODES))
	{
		debug(ECU_DBG_VERBOSE, "Command did not execute: received: 0x%02x, wanted: 0x%02x.", 
				   b, (byte)~((byte)ECU_COMMAND_RESET_FAULT_CODES));
		return -ECU_ERR_INVALID_RESPONSE;
	}

	ecu_send_byte(ECU_COMMAND_TERM);
	ecu_send_byte(ECU_COMMAND_STOP_STREAM);

	/* Eat up and stray data */
	while (ecu_read_byte_with_timeout(&b, 1) != ECU_OK);

	return ECU_OK;
}

const char *ecu_err_str(int code)
{
	if (code < 0)
		code = -code;
	switch (code) {
		case ECU_OK:                    return "No error";
		case ECU_ERR_BUSY:              return "Attempt to use ECU while it is in monitor mode";
		case ECU_ERR_INVALID_RESPONSE:  return "Invalid response code received from ECU";
		case ECU_ERR_NO_START_BYTE:     return "No start byte received from ECU";
		case ECU_ERR_NO_RESPONSE:       return "No response received from ECU";
		case ECU_ERR_OPEN_SERIAL_DEV:   return "Serial device open failed";
		case ECU_ERR_CLOSE_SERIAL_DEV:  return "Serial device close failed";
		case ECU_ERR_WRITE_SERIAL_DEV:  return "Write to serial device failed";
		case ECU_ERR_READ_SERIAL_DEV:   return "Read from serial device failed";
		case ECU_ERR_NOT_INITIALISED:   return "ECU was not initialised before call";
		case ECU_ERR_PARAM_INVALID:     return "One or more passed parameters were invalid or out of range";
		case ECU_ERR_STATE_INVALID:     return "ECU current state is invalid for the requested command";
		default:                        return "Unknown ECU error";
	}
}
