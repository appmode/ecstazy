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

static struct option long_options[] = {
	{"ecu-dev",          1, 0, 200},
	{"romulator-dev",    1, 0, 201},
	{"test",             2, 0, 't'},
	{"value",            1, 0, 'v'},
	{"read-fault-codes", 0, 0, 'f'},
	{"reset-fault-codes", 0, 0, 'F'},
	{"power-balance",    0, 0, 'p'},
	{"rom-editor",       0, 0, 'e'},
	{"rom-copy",         0, 0, 'c'},
	{"rom-print",        0, 0, 'P'},
	{"rom-read",         0, 0, 'r'},
	{"rom-write",        0, 0, 'w'},
	{"monitor",          2, 0, 'm'},
	{"version",          0, 0, 'V'},
	{"help",             0, 0, 'h'},
	{0,                  0, 0, 0}
};

enum {
	MODE_NULL = 0,
	MODE_TEST,
	MODE_RDFAULT,
	MODE_RSTFAULT,
	MODE_POWBAL,
	MODE_MON,
	MODE_ROMEDIT,
	MODE_ROMCOPY,
	MODE_ROMPRINT,
	MODE_ROMREAD,
	MODE_ROMWRITE
};

#define ECSTAZY_VERSION "0.9"
#define DEBUG_LOGFILE "./ecstazy.log"
#define DEFAULT_ECU_DEV  "/dev/ttyUSB0"
#define DEFAULT_WBO2_DEV  "/dev/ttyUSB2"
#define DEFAULT_ROMULATOR_DEV  "/dev/ttyUSB1"
#define DEFAULT_POWBAL_CYLS 6
#define INIT_TRIES          3

char *ecudev = DEFAULT_ECU_DEV;
char *romulatordev = DEFAULT_ROMULATOR_DEV;
char *wbo2dev = DEFAULT_WBO2_DEV;

typedef struct {
	char *name;
	int (*function)(byte);
	char *valdesc;
} ACTIVETESTENT;

ACTIVETESTENT available_tests[] = {
	{ "adj-coolant-temp",   (int(*)(byte)) ecu_atest_adj_coolant_temp,     "VAL = temp C" },
	{ "adj-fuel-inj",       (int(*)(byte)) ecu_atest_adj_fuel_inj_time,    "VAL = +/- 1 %%" },
	{ "adj-ignition-timing",(int(*)(byte)) ecu_atest_adj_ignition_timing,  "VAL = +/- 1 deg" },
	{ "adj-iacv-valve-open",(int(*)(byte)) ecu_atest_adj_iacv_valve_open,  "VAL = +/- 0.5 %% per 1" },
	{ "power-balance",      (int(*)(byte)) ecu_atest_power_balance,        "VAL = XXXXXXXX where X=0 or 1" },
	{ "fuel-pump-relay",    (int(*)(byte)) ecu_atest_fuel_pump_relay,      "VAL = ON/OFF" },
	{ "clear-self-learn",   (int(*)(byte)) ecu_atest_clear_self_learn,     "VAL = 0" },
	{NULL,NULL,NULL}
};

// {{{ print_help
void print_help(char *prog)
{
	ACTIVETESTENT *ptr1;
	struct ecu_reg_mon_param *ptr2;
	char tstbuf[BUFSIZ];
	char monbuf[BUFSIZ];
	char tmpbuf[BUFSIZ];
	
	tstbuf[0] = monbuf[0] = 0;

	for (ptr1 = available_tests; ptr1->name != NULL; ptr1++) {
			sprintf(tmpbuf, "      %-24s %s\n", ptr1->name, ptr1->valdesc);
			strncat(tstbuf, tmpbuf, BUFSIZ);
	}

	for (ptr2 = ecu_monitor_available_params; ptr2->id != MON_PARAM_NULL; ptr2++) {
			sprintf(tmpbuf, "      %-24s %s\n", ptr2->cmdname, ptr2->description);
			strncat(monbuf, tmpbuf, BUFSIZ);
	}

	printf("Usage: %s\n"
			"   -h, --help                  What you are seeing now\n"
			"   -V, --version               Show current program version\n"
			"   --ecu-dev=DEVICE            Serial port for the Consult ECU\n"
			"                               Default is " DEFAULT_ECU_DEV "\n"
			"   --romulator-dev=DEVICE      Serial port for the Pocket ROMulator\n"
			"                               Default is " DEFAULT_ROMULATOR_DEV "\n"
			"\n"
			"   -t TEST, --test=TEST        Run active test, where TEST equals:\n"
			"%s"
			"   -v, --value=VAL             Value for adjustment in active test\n"
			"\n"
			"   -f, --read-fault-codes      Read the DTC fault codes from the ECU\n"
			"   -F, --reset-fault-codes     Reset the DTC fault codes from the ECU\n"
			"\n"
			"   -p N, --power-balance=N     Measure power balance using active test\n"
			"                               N = Number of cylinders   DEFAULT: 6\n"
			"\n"
			"   -m S, --monitor[=S1,..]     Live stream sensor data from the ECU\n"
			"%s"
			"\n"
			"   -e, --rom-editor ROM        Inspect and edit Z32 8bit ECU ROM\n"
			"   -c, --rom-copy SRC DST MAP  Copy a map between Z32 8bit ECU ROMs\n"
			"   -P, --rom-print ROM         Print information from a Z32 8bit ECU ROM\n"
			"   -r, --rom-read ROM          Print information from a Z32 8bit ECU ROM\n"
			"   -w, --rom-write ROM         Print information from a Z32 8bit ECU ROM\n"
			"", prog, tstbuf, monbuf);
}
// }}}

// {{{ show_version
int show_version(void)
{
	printf("Ecstazy version " ECSTAZY_VERSION " (Compiled on " __DATE__ ")\n");
	return 0;
}
// }}}

// {{{ find_active_test
ACTIVETESTENT *find_active_test(char *name)
{
	ACTIVETESTENT *p = available_tests;
	while (p->name != NULL) {
		if (strcmp(p->name, name) == 0)
			return p;
		p++;
	}
	return NULL;
}
// }}}

// {{{ run_active_test
int run_active_test(ACTIVETESTENT *atest, byte testdata)
{
	ECU_ASSERT_OK(ecu_init(ecudev, INIT_TRIES));

	ECU_CHECK_OK(atest->function(testdata));

	ECU_CHECK_OK(ecu_close());

	return 0;
}
// }}}

// {{{ read_fault_codes
int read_fault_codes()
{
	struct ecu_fault_code faults[MAX_FAULT_CODES];
	int fcount, i;

	ECU_ASSERT_OK(ecu_init(ecudev, INIT_TRIES));

	ECU_ASSERT_OK(ecu_read_fault_codes(faults, &fcount));

	if (faults[0].code == 0x55) {
		printf("ECU reports code 55, no faults detected.\n");
	} else {
		printf("Fault Codes\n");
		printf("--------------------------------\n");
		for (i = 0; i < fcount; i++)
			printf("%02X - %d starts ago\n", faults[i].code, faults[i].starts);
	}

	ECU_CHECK_OK(ecu_close());

	return 0;
}
// }}}

// {{{ reset_fault_codes
int reset_fault_codes()
{
	ECU_ASSERT_OK(ecu_init(ecudev, INIT_TRIES));
	ECU_CHECK_OK(ecu_reset_fault_codes());
	ECU_CHECK_OK(ecu_close());
	return 0;
}
// }}}

// {{{ power_balance_test
void measure_rpm_callback(struct ecu_mon_param_data rdata[MAX_MONITOR_PARAMETERS], int n, void *arg)
{
	if (n == 1)
		*((int *)arg) = rdata[0].value;
	else
		*((int *)arg) = -1;
}

int measure_rpm()
{
	int rpm = -1, n = 0, i;
	int rpmset[50000];
	int params[] = { MON_PARAM_CAS_POS };
	int start;
	int measure_time = 5; // seconds

	ECU_ASSERT_OK(ecu_start_monitor(params, sizeof(params)/sizeof(*params), measure_rpm_callback, &rpm));

	start = time(NULL);

	while (ecu_process_data_from_fd() == ECU_OK) {
		if (rpm >= 0)
			rpmset[n++] = rpm;
		if ((n + 1 >= 50000) || (start + measure_time <= time(NULL)))
			break;
		rpm = -1;
	}

	ECU_ASSERT_OK(ecu_stop_monitor());

	rpm = 0;
	for (i = 0; i < 10; i++)
		rpm += rpmset[i];
	rpm /= 10;

	return rpm;
}

int power_balance_test(int cyl)
{
	int i;
	int result[9];
	int fault[8];
	int threshold = 50;

	ECU_ASSERT_OK(ecu_init(ecudev, INIT_TRIES));

	for (i = 0; i <= cyl; i++) {
		if (i == 0)
			printf("Testing normal firing... ");
		else
			printf("Testing cylinder %d...    ", i);

		fflush(stdout);

		ECU_ASSERT_OK(ecu_active_test(ECU_ACTIVE_TEST_POWER_BALANCE, i));

		result[i] = measure_rpm();

		if (i == 0)
			printf("%4d RPM\n", result[i]);
		else
			printf("%4d RPM, %4d DROP\n", result[i], result[0] - result[i]);
		
		fault[i-1] = (result[0] - result[i]) < threshold;
	}

	printf("Returning to normal firing...\n");
	ECU_ASSERT_OK(ecu_active_test(ECU_ACTIVE_TEST_POWER_BALANCE, 0));

	printf("\n\n-----> Cylinder Report <-----\n\n");

	for (i = 1; i <= cyl; i++)
		printf("Cyl %d     %s\n", i, (fault[i-1] ? "FAULTY" : "OK"));

	ECU_CHECK_OK(ecu_close());

	return 0;
}
// }}}

// {{{ monitor_sensors
void monitor_data_ready(struct ecu_mon_param_data *rdata, int n, void *arg)
{
	int i;

	erase();

	for (i = 0; i < n; i++)
		mvprintw(i, 0, "%-32s  %.02f %s\n", rdata[i].param->description, rdata[i].value, rdata[i].param->unit);

	refresh();
}

int monitor_sensors()
{
	static int default_monitor_entries[] = {
		MON_PARAM_CAS_POS,
		MON_PARAM_MAF_VOLT,
		MON_PARAM_COOLANT_TEMP,
		MON_PARAM_LH_O2_VOLT,
		MON_PARAM_RH_O2_VOLT,
		MON_PARAM_SPEED,
		MON_PARAM_BAT_VOLT,
		MON_PARAM_TPS_VOLT,
		MON_PARAM_FUEL_TEMP,
		MON_PARAM_LH_INJECTION_TIME,
		MON_PARAM_RH_INJECTION_TIME,
		MON_PARAM_IGN_TIMING,
		MON_PARAM_IDLE_AIR_VALVE,
	};
	fd_set readset;
	int ecufd, inputfd, c;
	int res;

	ECU_ASSERT_OK(ecu_init(ecudev, INIT_TRIES));

	initscr();

	ECU_CHECK_OK(ecu_start_monitor(
				default_monitor_entries, 
				sizeof(default_monitor_entries) / sizeof(int), 
				monitor_data_ready,
				NULL
	));

	ecufd = ecu_get_fd();
	inputfd = fileno(stdin);

	while (1) {
		FD_ZERO(&readset);
		FD_SET(ecufd, &readset);
		FD_SET(inputfd, &readset);

		res = select(ecufd + 1, &readset, NULL, NULL, NULL);

		if (res > 0) {
			if (FD_ISSET(inputfd, &readset)) {
				c = getch();
				switch (c) {
					default:
						printf("Got key press %d\n", c);
						break;
				}
			} else if (FD_ISSET(ecufd, &readset)) {
				ECU_ASSERT_OK(ecu_process_data_from_fd());
			}
		}
	}

	endwin();

	ECU_CHECK_OK(ecu_close());

	return 0;
}
// }}}

// {{{ rom_read
int rom_read(char *romfile)
{
  FILE *outfp;
  byte data[ROMU_BLOCK_SIZE];
  int i;
  struct stat stbuf;
	word addr;
	int tries;

  if (lstat(romfile, &stbuf) == 0) {
    fprintf(stderr, "ERROR: File %s already exists. Try a different name.\n", romfile);
    return 1;
  }

	if (romu_init() != ROMU_OK) {
    fprintf(stderr, "ERROR: Failed to initialise the romulator\n");
		return 1;
	}

	outfp = fopen(romfile, "w");

	for (i = 0; i < (ROMU_ROM_SIZE / ROMU_BLOCK_SIZE); i++) {
		addr = i * ROMU_BLOCK_SIZE;
		bzero(data, ROMU_BLOCK_SIZE);

		printf("\rReading %d-byte block at address %04xh...", ROMU_BLOCK_SIZE, addr);
		fflush(stdout);

		for (tries = 1; tries <= 7; tries++)
			if (romu_read_buffer(addr, data, ROMU_BLOCK_SIZE) == ROMU_OK)
				break;

		if (tries > 7) {
			fprintf(stderr, "Exiting: Error writing block %d...\n", i);
			return 1;
		}

		fwrite(data, 1, ROMU_BLOCK_SIZE, outfp);
		fsync(fileno(outfp));
	}

	fclose(outfp);

	return 0;
}
// }}}

// {{{ rom_write
int rom_write(char *romfile)
{
  FILE *infp;
  byte data[ROMU_BLOCK_SIZE];
  int i, br;
  struct stat stbuf;
	word addr;
	int tries;

  if (lstat(romfile, &stbuf) < 0) {
    fprintf(stderr, "ERROR: stat(%s) failed: %s\n", romfile, strerror(errno));
    return 1;
  }

  if (stbuf.st_size != ROMU_ROM_SIZE) {
    fprintf(stderr, "ERROR: ROM file %s must be exactly %d bytes.\n", romfile, ROMU_ROM_SIZE);
    return 2;
  }

	if (romu_init() != ROMU_OK) {
    fprintf(stderr, "ERROR: Failed to initialise the romulator\n");
		return 1;
	}

	infp = fopen(romfile, "r");

	for (i = 0; i < (ROMU_ROM_SIZE / ROMU_BLOCK_SIZE); i++) {
		addr = i * ROMU_BLOCK_SIZE;
		bzero(data, ROMU_BLOCK_SIZE);

		printf("\rWriting %d-byte block at address %04xh...", ROMU_BLOCK_SIZE, addr);
		fflush(stdout);

    if ((br = fread(data, 1, ROMU_BLOCK_SIZE, infp)) != ROMU_BLOCK_SIZE)
    {
      printf("fread from ROM returned %d bytes, but we wanted %d\n", br, ROMU_BLOCK_SIZE);
      exit(1);
    }

		for (tries = 1; tries <= 7; tries++)
			if (romu_write_buffer(addr, data, ROMU_BLOCK_SIZE) == ROMU_OK)
				break;

		if (tries > 7) {
			fprintf(stderr, "Exiting: Error writing block %d...\n", i);
			return 1;
		}
	}

	fclose(infp);

	return 0;
}
// }}}

// {{{ main
int main(int argc, char **argv)
{
	int c;
	int mode = 0;
	ACTIVETESTENT *atest;
	byte testdata;
	int pbcyl = DEFAULT_POWBAL_CYLS;

	_debug_setup_logfile(DEBUG_LOGFILE);

	while (1) {
		int option_index = 0;

		c = getopt_long(argc, argv, "t:v:fFpem::hcPrwV", long_options, &option_index);

		if (c == -1)
			break;

		switch (c) {
			case 200: ecudev = optarg; break;
			case 201: romulatordev = optarg; break;

			case 't':
				mode = MODE_TEST; 
				atest = find_active_test(optarg);
				if (atest == NULL) {
					fprintf(stderr, "ERR: Unknown active test '%s' specified.\n", optarg);
					return 1;
				}
				break;
			case 'f': mode = MODE_RDFAULT; break;
			case 'F': mode = MODE_RSTFAULT; break;
			case 'p': mode = MODE_POWBAL; break;
			case 'm': mode = MODE_MON; break;
			case 'e': mode = MODE_ROMEDIT; break;
			case 'c': mode = MODE_ROMCOPY; break;
			case 'P': mode = MODE_ROMPRINT; break;
			case 'r': mode = MODE_ROMREAD; break;
			case 'w': mode = MODE_ROMWRITE; break;

			case 'v':
				testdata = atoi(optarg);
				break;

			case 'h':
				print_help(argv[0]);
				return 0;

			case 'V':
				show_version();
				return 0;
		}
	}
					
	switch (mode) {
		case MODE_TEST:
			return run_active_test(atest, testdata);

		case MODE_RDFAULT:
			return read_fault_codes();

		case MODE_RSTFAULT:
			return reset_fault_codes();

		case MODE_POWBAL:
			return power_balance_test(pbcyl);

		case MODE_MON:
			return monitor_sensors();

		case MODE_ROMEDIT:
			if (optind + 1 > argc) {
				fprintf(stderr, "Usage: %s -r <rom file>\n", argv[0]);
				return 1;
			} else
				return edit_rom(argv[optind]);

		case MODE_ROMCOPY:
			if (optind + 3 > argc) {
				fprintf(stderr, "Usage: %s -c <src file> <dst file> <map type>\n", argv[0]);
				return 1;
			} else
				return copy_rom_map(argv[optind], argv[optind+1], argv[optind+2]);

		case MODE_ROMPRINT:
			if (optind + 1 > argc) {
				fprintf(stderr, "Usage: %s -P <rom file>\n", argv[0]);
				return 1;
			} else
				return rom_print(argv[optind]);

		case MODE_ROMREAD:
			if (optind + 1 > argc) {
				fprintf(stderr, "Usage: %s --rom-read <rom file>\n", argv[0]);
				return 1;
			} else
				return rom_read(argv[optind]);

		case MODE_ROMWRITE:
			if (optind + 1 > argc) {
				fprintf(stderr, "Usage: %s --rom-write <rom file>\n", argv[0]);
				return 1;
			} else
				return rom_write(argv[optind]);

		default:
			print_help(argv[0]);
	}

	return 0;
}
// }}}
