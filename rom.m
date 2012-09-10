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

#define ROMSZ            (32768)
#define LEGEND_X_LEN     (6)
#define LEGEND_Y_LEN     (6)
#define MAX_MAP_HEIGHT   (64)
#define MAX_MAP_WIDTH    (64)

#define MAP_SIZE(mapent) (mapent->rows * mapent->cols)

#define FLUSH_EDIT_BUFFER(redata) { \
	for (y = 0; y < redata->mapent->rows; y++) { \
		for (x = 0; x < redata->mapent->cols; x++) { \
			if (*redata->editbuffer[y][x] != 0) { \
				if (redata->mapent->fconvfrom) \
					redata->mapblock[y][x] = redata->mapent->fconvfrom(redata->editbuffer[y][x], redata->flags[y][x]); \
				else \
					redata->mapblock[y][x] = atoi(redata->editbuffer[y][x]); \
				if (romu_ready) { \
          int off = redata->mapent->offset + (y * redata->mapent->cols * redata->mapent->datawidth) + (x * redata->mapent->datawidth); \
          switch (redata->mapent->datawidth) { \
            case DATA_WORD: \
              if (romu_hidden_write_with_retry(off, (redata->mapblock[y][x] >> 8) & 0xFF) < 0 || \
              		romu_hidden_write_with_retry(off+1, redata->mapblock[y][x] & 0xFF) < 0) \
								romu_ready = false; \
              break; \
            case DATA_BYTE: \
            default: \
              if (romu_hidden_write_with_retry(off, redata->mapblock[y][x]) < 0) \
								romu_ready = false; \
					} \
				} \
			} \
		} \
	} \
}

#define RESET_EDIT_BUFFER(redata) { \
	memset(redata->editbuffer, 0, MAX_MAP_HEIGHT * MAX_MAP_WIDTH * 10); \
	memset(redata->editbufpos, 0, MAX_MAP_HEIGHT * MAX_MAP_WIDTH * sizeof(int)); \
}

enum DevStatus {
	STATUS_IDLE=0,
	STATUS_CONNECTING=1,
	STATUS_STREAMING=2
};

pthread_mutex_t ecudata_mutex;
struct ecu_mon_param_data *ecudata = NULL;
int ecudata_count = 0;
enum DevStatus ecu_status = STATUS_IDLE;

float wbo2data = 0;
enum DevStatus wbo2_status = STATUS_IDLE;

FILE *log_fh = NULL;

#define LIVEDATA_LOG_FILE "/tmp/ecudata.csv"

typedef char *(*SCALEFUNC)(int,void *);
typedef word (*RAWSCALEFUNC)(int,void *);

enum MAPDATATYPE {
	DATA_BYTE = 1,
	DATA_WORD = 2
};

enum MAPDATAFORMAT {
	DFMT_INTEGER = 0,
	DFMT_FLOAT_1_DEC = 1,
	DFMT_FLOAT_2_DEC = 2
};

enum MAPSCALE {
	MAP_SCALE_NONE = -1,
	MAP_SCALE_RPM_FUEL = 0,
	MAP_SCALE_RPM_TIMING,
	MAP_SCALE_TP_FUEL,
	MAP_SCALE_TP_TIMING,
	MAP_SCALE_MAF
};

typedef struct {
	int offset;
	char *id;
	char *desc;
	double (*fconvto)(byte);
	byte (*fconvfrom)(char *, byte);
	enum MAPDATATYPE datawidth;
} ROMPARTABENT;

typedef struct {
	int offset;
	int rows;
	int cols;
	char *id;
	char *desc;
	double (*fconvto)(byte);
	byte (*fconvfrom)(char *, byte);
	enum MAPDATATYPE datawidth;
	enum MAPDATAFORMAT datafmt;
	enum MAPSCALE scaleX;
	enum MAPSCALE scaleY;
	byte usefulFlags;
} ROMMAPTABENT;

typedef struct {
	word mapblock[MAX_MAP_HEIGHT][MAX_MAP_WIDTH];
	byte flags[MAX_MAP_HEIGHT][MAX_MAP_WIDTH];
	byte rombuf[ROMSZ];
	char editbuffer[MAX_MAP_HEIGHT][MAX_MAP_WIDTH][10];
	int editbufpos[MAX_MAP_HEIGHT][MAX_MAP_WIDTH];
	ROMMAPTABENT *mapent;
	int vs_start_x;
	int vs_start_y;
	int vs_end_x;
	int vs_end_y;
	int vb_start_x;
	int vb_start_y;
	int vb_end_x;
	int vb_end_y;
} ROMEDITDATA;

int edit_rom_map(ROMEDITDATA *, ROMMAPTABENT *);
int edit_rom_param(ROMEDITDATA *, ROMPARTABENT *);
void *edit_rom_daq_thread(void *);
void show_dev_status();

/* {{{ scale index functions */

char *MAFscale[64] = {
	"0", "0.08", "0.16", "0.24", "0.32", "0.4", "0.48", "0.56", "0.64",
	"0.72", "0.8", "0.88", "0.96", "1.04", "1.12", "1.2", "1.28", "1.36", 
	"1.44", "1.52", "1.6", "1.68", "1.76", "1.84", "1.92", "2", "2.08", 
	"2.16", "2.24", "2.32", "2.4", "2.48", "2.56", "2.64", "2.72", "2.8", 
	"2.88", "2.96", "3.04", "3.12", "3.2", "3.28", "3.36", "3.44", "3.52", 
	"3.6", "3.68", "3.76", "3.84", "3.92", "4", "4.08", "4.16", "4.24", 
	"4.32", "4.4", "4.48", "4.56", "4.64", "4.72", "4.8", "4.88", "4.96", "5.04"
};

char *tp_scale_fuel_at(int index, void *data)
{
	byte *romdata = data;
	static char buf[20];
	sprintf(buf, "%02X", romdata[0x7af0 + index]);
	return buf;
}

char *rpm_scale_fuel_at(int index, void *data)
{
	byte *romdata = data;
	static char buf[20];
	sprintf(buf, "%d", romdata[0x7b00 + index] * 50);
	return buf;
}

char *tp_scale_timing_at(int index, void *data)
{
	byte *romdata = data;
	static char buf[20];
	sprintf(buf, "%02X", romdata[0x7b10 + index]);
	return buf;
}

char *rpm_scale_timing_at(int index, void *data)
{
	byte *romdata = data;
	static char buf[20];
	sprintf(buf, "%d", romdata[0x7b20 + index] * 50);
	return buf;
}

char *maf_scale_at(int index, void *data)
{
	return MAFscale[index];
}

SCALEFUNC scaleFunctions[] = {
	rpm_scale_fuel_at,
	rpm_scale_timing_at,
	tp_scale_fuel_at,
	tp_scale_timing_at,
	maf_scale_at
};

word raw_tp_scale_fuel_at(int index, void *data) { byte *romdata = data; return romdata[0x7af0 + index]; }
word raw_rpm_scale_fuel_at(int index, void *data) { byte *romdata = data; return romdata[0x7b00 + index] * 50; }
word raw_tp_scale_timing_at(int index, void *data) { byte *romdata = data; return romdata[0x7b10 + index]; }
word raw_rpm_scale_timing_at(int index, void *data) { byte *romdata = data; return romdata[0x7b20 + index] * 50; }
word raw_maf_scale_at(int index, void *data) { return atof(MAFscale[index]) * 1000; }

RAWSCALEFUNC rawScaleFunctions[] = {
	raw_rpm_scale_fuel_at,
	raw_rpm_scale_timing_at,
	raw_tp_scale_fuel_at,
	raw_tp_scale_timing_at,
	raw_maf_scale_at
};

/* }}} */

ROMPARTABENT pars[] = {
	{ .offset = 0x7F2B, .datawidth = DATA_WORD,
		.fconvto = NULL, .fconvfrom = NULL,
		.id = "injector-k", .desc = "Injector K-value" },

	{ .offset = 0x7F88, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.id = "injector-latency", .desc = "Injector Latency (TS)" },

	{ .offset = 0x7F87, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.id = "latency-correction-coefficient", .desc = "Inj. Latency Correction Coefficient (DTS)" },

	{ .offset = 0x7F91, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.id = "feedback-cont", .desc = "Feedback Control" },

	{ .offset = 0x7FA5, .datawidth = DATA_BYTE,
		.fconvto = convertToSpeed, .fconvfrom = convertFromSpeed,
		.id = "speed-limiter", .desc = "Speed Limiter" },

	{ .offset = 0x7FB4, .datawidth = DATA_BYTE,
		.fconvto = convertToRPM, .fconvfrom = convertFromRPM,
		.id = "rpm-limiter", .desc = "RPM Limiter" },

	{ .offset = 0x79F6, .datawidth = DATA_BYTE,
		.fconvto = convertToRPM, .fconvfrom = convertFromRPM,
		.id = "vtc-release", .desc = "Valve Timing Release" },

	{ .id = NULL }
};

ROMMAPTABENT maps[] = {
	{ .offset = 0x7E80, .rows = 1, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_NONE,
		.id = "ttp-min", .desc = "TTP Minimum" },

	{ .offset = 0x7E90, .rows = 1, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_NONE,
		.id = "ttp-max", .desc = "TTP Maximum" },

	{ .offset = 0x7960, .rows = 1, .cols = 16, .datawidth = DATA_WORD,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_NONE,
		.id = "af-limit", .desc = "Air Flow Limit" },

	{ .offset = 0x7AF0, .rows = 1, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_NONE,
		.id = "tp-scale-fuel", .desc = "Thoeoretical Pulsewidth Scale Fuel" },

	{ .offset = 0x7B10, .rows = 1, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_NONE,
		.id = "tp-scale-timing", .desc = "Thoeoretical Pulsewidth Scale Timing" },

	{ .offset = 0x7B00, .rows = 1, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_NONE,
		.id = "rpm-scale-fuel", .desc = "RPM Scale for fuel maps" },

	{ .offset = 0x7B20, .rows = 1, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_NONE,
		.id = "rpm-scale-timing", .desc = "RPM Scale for timing maps" },

	{ .offset = 0x7E20, .rows = 1, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_NONE,
		.id = "water-temp-enrich", .desc = "Water Temp Enrichment" },

	{ .offset = 0x7A70, .rows = 64, .cols = 1, .datawidth = DATA_WORD,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_MAF,
		.id = "vq-table", .desc = "VQ Table" },

	{ .offset = 0x7B50, .rows = 1, .cols = 16, .datawidth = DATA_WORD,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_NONE,
		.id = "coil-dwell", .desc = "Coil Dwell Duty Angle" },

	{ .offset = 0x7B60, .rows = 1, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_NONE,
		.id = "coil-charge", .desc = "Coil Charge" },

	{ .offset = 0x7800, .rows = 16, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = convertToTiming, .fconvfrom = convertFromTiming,
		.scaleY = MAP_SCALE_RPM_TIMING, .scaleX = MAP_SCALE_TP_TIMING,
		.usefulFlags = FLAG_BIT_8_PRESENT,
		.id = "primary-timing", .desc = "Primary Timing Map" },

	{ .offset = 0x7C00, .rows = 16, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = convertToTiming, .fconvfrom = convertFromTiming,
		.scaleY = MAP_SCALE_RPM_TIMING, .scaleX = MAP_SCALE_TP_TIMING,
		.usefulFlags = FLAG_BIT_8_PRESENT,
		.id = "knock-timing", .desc = "Knock Timing Map" },

	{ .offset = 0x7D00, .rows = 16, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = convertToAFR, .fconvfrom = convertFromAFR, .datafmt = DFMT_FLOAT_2_DEC,
		.scaleY = MAP_SCALE_RPM_FUEL, .scaleX = MAP_SCALE_TP_FUEL,
		.usefulFlags = FLAG_BIT_8_PRESENT,
		.id = "primary-fuel", .desc = "Primary Fuel Map" },

	{ .offset = 0x7000, .rows = 16, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = convertToAFR, .fconvfrom = convertFromAFR, .datafmt = DFMT_FLOAT_2_DEC,
		.scaleY = MAP_SCALE_RPM_FUEL, .scaleX = MAP_SCALE_TP_FUEL,
		.usefulFlags = FLAG_BIT_8_PRESENT,
		.id = "knock-fuel", .desc = "Knock Fuel Map" },

	{ .offset = 0x7100, .rows = 16, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = convertToAFR, .fconvfrom = convertFromAFR, .datafmt = DFMT_FLOAT_2_DEC,
		.scaleY = MAP_SCALE_RPM_FUEL, .scaleX = MAP_SCALE_TP_FUEL,
		.usefulFlags = FLAG_BIT_8_PRESENT,
		.id = "high-gear-fuel", .desc = "High Gear Fuel Map" },

	{ .offset = 0x7200, .rows = 16, .cols = 16, .datawidth = DATA_BYTE,
		.fconvto = convertToAFR, .fconvfrom = convertFromAFR, .datafmt = DFMT_FLOAT_2_DEC,
		.scaleY = MAP_SCALE_RPM_FUEL, .scaleX = MAP_SCALE_TP_FUEL,
		.usefulFlags = FLAG_BIT_8_PRESENT,
		.id = "high-gear-knock-fuel", .desc = "High Gear Knock Fuel Map" },

	{ .offset = 0x79E3, .rows = 1, .cols = 13, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_NONE,
		.id = "knock-limit", .desc = "Knock Limit" },

	{ .offset = 0x7B30, .rows = 26, .cols = 2, .datawidth = DATA_BYTE,
		.fconvto = NULL, .fconvfrom = NULL,
		.scaleX = MAP_SCALE_NONE, .scaleY = MAP_SCALE_NONE,
		.id = "water-temp-conv", .desc = "Water Temperature Conversion Table (C to F)" },

	{ .id = NULL }
};

/* {{{ block reading functions */
void getblock(FILE *fp, byte *block, int bwidth, word offset, int x, int y)
{
	int i;

	fseek(fp, offset, SEEK_SET);

	for (i = 0; i < y; i++)
		fread(block + (i*bwidth), sizeof(byte) * x, 1, fp);
}

void extractbyteblock(byte *rombuf, word *block, int bwidth, word offset, int x, int y)
{
	int i, j;
	byte tmpbyte;

	for (i = 0; i < y; i++)
		for (j = 0; j < x; j++) {
			tmpbyte = rombuf[offset + (i*x) + j];
			block[(i*bwidth) + j] = tmpbyte;
		}
}

void extractwordblock(byte *rombuf, word *block, int bwidth, word offset, int x, int y)
{
	int i, j;
	byte b[2];
	word tmpword;

	for (i = 0; i < y; i++)
		for (j = 0; j < x; j++) {
			b[0] = rombuf[offset + (i*x*2) + (j*2)];
			b[1] = rombuf[offset + (i*x*2) + (j*2) + 1];
			tmpword = ((word)b[0] << 8) | (word)b[1];
			block[(i*bwidth) + j] = tmpword;
		}
}

void getwordblock(FILE *fp, word *block, int bwidth, word offset, int x, int y)
{
	int i, j;
	word tmpword;

	fseek(fp, offset, SEEK_SET);

	for (i = 0; i < y; i++)
		for (j = 0; j < x; j++) {
			fread(&tmpword, sizeof(word), 1, fp);
			block[(i*bwidth) + j] = (tmpword << 8) | (tmpword >> 8);
		}
}

byte getbyte(FILE *fp, word offset)
{
	byte b;
	fseek(fp, offset, SEEK_SET);
	fread(&b, sizeof(byte), 1, fp);
	return b;
}

word getword(FILE *fp, word offset)
{
	word w;
	fseek(fp, offset, SEEK_SET);
	fread(&w, sizeof(word), 1, fp);
	return w;
}

void printbytemapByte(
		char *title, byte *block, int x, int y,
		byte *romdata,
		SCALEFUNC fscaleX, SCALEFUNC fscaleY,
		bool hex, double (*convertFunc)(byte))
{
	int i, j;

	printf("<< %s >>\n", title);

	printf("%4s ", "");
	for (i = 0; i < x; i++)
		if (hex)
			printf("%2s ", fscaleX(i, romdata));
		else
			printf("%4s ", fscaleX(i, romdata));
	printf("\n");

	for (i = 0; i < y; i++) {
		printf("%4s ", fscaleY(i, romdata));
		for (j = 0; j < x; j++)
			if (hex)
				printf("%02X ", (convertFunc ? (int)convertFunc(*(block + (i*y) + j)) : *(block + (i*y) + j)));
			else
				printf("%4d ", (convertFunc ? (int)convertFunc(*(block + (i*y) + j)) : *(block + (i*y) + j)));
		printf("\n");
	}

	printf("<< End %s >>\n", title);
}

void printbytemapDouble(
		char *title, byte *block, int x, int y, byte *romdata,
		SCALEFUNC fscaleX, SCALEFUNC fscaleY,
		double (*convertFunc)(byte))
{
	int i, j;

	printf("<< %s >>\n", title);

	printf("%4s ", "");
	for (i = 0; i < x; i++)
		printf("%4s ", fscaleX(i, romdata));
	printf("\n");

	for (i = 0; i < y; i++) {
		printf("%4s ", fscaleY(i, romdata));
		for (j = 0; j < x; j++)
			printf("%4.1f ", (convertFunc ? convertFunc(*(block + (i*y) + j)) : (double)*(block + (i*y) + j)));
		printf("\n");
	}

	printf("<< End %s >>\n", title);
}

void printwordmap(char *title, word *block, int x, int y, byte *romdata,
		SCALEFUNC fscaleX, SCALEFUNC fscaleY)
{
	int i, j;

	printf("<< %s >>\n", title);

	printf("%4s ", "");
	for (i = 0; i < x; i++)
		printf("%4s ", fscaleX(i, romdata));
	printf("\n");

	for (i = 0; i < y; i++) {
		printf("%4s ", fscaleY(i, romdata));
		for (j = 0; j < x; j++)
			printf("%04X ", *(block + (i*y) + j));
		printf("\n");
	}

	printf("<< End %s >>\n", title);
}

void printbytetable(char *title, byte *block, int n, int div, byte *romdata, 
		SCALEFUNC fscale, double (*convertFunc)(byte))
{
	int i, j;
	int nn = n / div;

	printf("<< %s >>\n", title);

	for (i = 0; i < nn; i++) {
		if (fscale != NULL) {
			for (j = i * div; j < ((i + 1) * div); j++) {
				printf("%5s ", fscale(j, romdata));
			}
			printf("\n");
		}
		for (j = i * div; j < ((i + 1) * div); j++) {
			if (convertFunc)
				printf("%5d ", (int)convertFunc(*(block + j)));
			else
				printf("%5X ", *(block + j));
		}
		printf("\n");
		if ((i + 1) * div < nn)
			printf("\n");
	}

	printf("<< End %s >>\n", title);
}

void printwordtable(char *title, word *block, int n, int div, byte *romdata,
		SCALEFUNC fscale)
{
	int i, j;
	int nn = n / div;

	printf("<< %s >>\n", title);

	for (i = 0; i < nn; i++) {
		if (fscale != NULL) {
			for (j = i * div; j < ((i + 1) * div); j++) {
				printf("%4s ", fscale(j, romdata));
			}
			printf("\n");
		}
		for (j = i * div; j < ((i + 1) * div); j++) {
			printf("%4x ", *(block + j));
		}
		printf("\n");
		if ((i + 1) * div < nn)
			printf("\n");
	}

	printf("<< End %s >>\n", title);
}

ROMMAPTABENT *get_map_block(ROMEDITDATA *d, ROMMAPTABENT *mapent)
{
//	printf("Reading %s (%s) map ...\n", mapent->id, mapent->desc);

	memset(d->mapblock, 0, MAX_MAP_WIDTH * MAX_MAP_HEIGHT * mapent->datawidth);

	switch (mapent->datawidth) {
		case DATA_WORD:
			extractwordblock(d->rombuf, (word*) d->mapblock, MAX_MAP_WIDTH, mapent->offset, mapent->cols, mapent->rows);
			break;

		default:
		case DATA_BYTE:
			extractbyteblock(d->rombuf, (word*) d->mapblock, MAX_MAP_WIDTH, mapent->offset, mapent->cols, mapent->rows);
			break;
	}

	d->mapent = mapent;

	return mapent;
}
/* }}} */

/* {{{ equate_tp */
double equate_tp(ROMEDITDATA *d, word maf, word rpm) 
{
	double vqindex = (double)maf / 80.0;
	word vqindexfloor = floor(vqindex);
	word vqindexceil = ceil(vqindex);
	if (vqindexfloor == vqindexceil)
		vqindexceil += 1;
	double vqfrac = vqindex - vqindexfloor;
	word vqlow = WORD_PACK1(d->rombuf, 0x7a70 + (vqindexfloor * 2));
	word vqhigh = WORD_PACK1(d->rombuf, 0x7a70 + (vqindexceil * 2));
	word vqinterp = (vqlow + ((vqhigh - vqlow) * vqfrac));
	word kvalue = WORD_PACK1(d->rombuf, 0x7f2b);
	double numer = (double)vqinterp * (double)kvalue;
	double denom = ((double)rpm / 50) * 180;
	if (rpm == 0)
		return 0;
	return (numer / denom) / 6.0;
}
/* }}} */

/* {{{ scaledata */
void scaledata(char *buffer, int len, ROMEDITDATA *d)
{
	int i, j;
	double v;
	double factor = strtod(buffer, NULL);
	if (factor < 0)
		factor = -factor;
	for (i = 0; i < d->mapent->rows; i++)
		for (j = 0; j < d->mapent->cols; j++) {
			if (d->vb_start_y >= 0 &&
					d->vb_end_y >= 0 &&
					d->vb_start_x >= 0 &&
					d->vb_end_x >= 0 &&
					i >= d->vb_start_y && i <= d->vb_end_y && j >= d->vb_start_x && j <= d->vb_end_x) {
				if (d->mapent->fconvto)
					v = d->mapent->fconvto(d->mapblock[i][j]) * factor;
				else
					v = d->mapblock[i][j] * factor;
				d->editbuffer[i][j][0] = 0;
				sprintf(d->editbuffer[i][j], "%.2f", v);

				d->editbufpos[i][j] = strlen(d->editbuffer[i][j]) + 1;
			}
		}
}
/* }}} */

/* {{{ current_map_value */
double current_map_value(ROMEDITDATA *d, int y, int x) 
{
	double v;
	if (*d->editbuffer[y][x] != 0) {
		v = strtod(d->editbuffer[y][x], NULL);
	} else {
		if (d->mapent->fconvto)
			v	= d->mapent->fconvto(d->mapblock[y][x]);
		else
			v = d->mapblock[y][x];
	}
	return v;
}
/* }}} */

/* {{{ rom_print */
int rom_print(const char *romfile)
{
	struct stat stbuf;
	byte mapblock[16][16];
	word vqblock[64];
	word igdwellblock[16];
	byte ttpblock[8];
	byte romdata[ROMSZ];
	FILE *infp;

	if (romfile == NULL)
	{
		printf("usage: ecstazy -P <existing rom>\n");
		exit(1);
	}

	if (lstat(romfile, &stbuf) < 0) {
		fprintf(stderr, "ERROR: stat(%s): %s\n", romfile, strerror(errno));
		exit(-1);
	}

	if (stbuf.st_size != ROMSZ) {
		fprintf(stderr, "ERROR: ROM file %s must be exactly %d bytes.\n", romfile, ROMSZ);
		exit(-2);
	}

	infp = fopen(romfile, "r");

	fseek(infp, 0, SEEK_SET);
	fread(romdata, sizeof(byte), ROMSZ, infp);

	printf("Feedback control = %d\n",  getbyte(infp, 0x7F91));
	printf("Speed limiter = %d\n",  getbyte(infp, 0x7FA5) * 2);
	printf("RPM limiter = %d\n",    getbyte(infp, 0x7FB4) * 50);
	printf("Injector Latency = %d\n",    getbyte(infp, 0x7F88));
	printf("K Value = %d\n",             (getbyte(infp, 0x7F2B) << 8) | getbyte(infp, 0x7F2C)); 
	printf("VTC Release = %d\n",         getbyte(infp, 0x79F6) * 50);
	
	getblock(infp, (byte*) mapblock, 16, 0x7800, 16, 16);
	printbytemapByte("Primary Timing Map", (byte*) mapblock, 16, 16, romdata, tp_scale_timing_at, rpm_scale_timing_at, FALSE, convertToTiming);

	getblock(infp, (byte*) mapblock, 16, 0x7C00, 16, 16);
	printbytemapByte("Knock Timing Map", (byte*) mapblock, 16, 16, romdata, tp_scale_timing_at, rpm_scale_timing_at, FALSE, convertToTiming);

	getblock(infp, (byte*) mapblock, 16, 0x7D00, 16, 16);
	printbytemapDouble("Primary Fuel Map",  (byte*) mapblock, 16, 16, romdata, tp_scale_fuel_at, rpm_scale_fuel_at, convertToAFR);

	getblock(infp, (byte*) mapblock, 16, 0x7000, 16, 16);
	printbytemapDouble("Knock Fuel Map",  (byte*) mapblock, 16, 16, romdata, tp_scale_fuel_at, rpm_scale_fuel_at, convertToAFR);

	getblock(infp, (byte*) mapblock, 16, 0x7100, 16, 16);
	printbytemapDouble("High Gear Fuel Map",  (byte*) mapblock, 16, 16, romdata, tp_scale_fuel_at, rpm_scale_fuel_at, convertToAFR);

	getblock(infp, (byte*) mapblock, 16, 0x7200, 16, 16);
	printbytemapDouble("High Gear Knock Fuel Map",  (byte*) mapblock, 16, 16, romdata, tp_scale_fuel_at, rpm_scale_fuel_at, convertToAFR);

	getwordblock(infp, (word*) igdwellblock, 16, 0x7B60, 16, 1);
	printwordtable("Ignition Dwell Duty", igdwellblock, 16, 1, romdata, tp_scale_timing_at);

	getwordblock(infp, (word*) vqblock, 16, 0x7A70, 64, 1);
	printwordtable("VQ Table", vqblock, 64, 16, romdata, maf_scale_at);

	getblock(infp, (byte*) ttpblock, 16, 0x7B20, 16, 1);
	printbytetable("RPM Scale Timing", ttpblock, 16, 16, romdata, NULL, convertToRPM);

	getblock(infp, (byte*) ttpblock, 16, 0x7B10, 16, 1);
	printbytetable("TP Scale Timing", ttpblock, 16, 16, romdata, NULL, NULL);

	getblock(infp, (byte*) ttpblock, 16, 0x7B00, 16, 1);
	printbytetable("RPM Scale Fuel", ttpblock, 16, 16, romdata, NULL, convertToRPM);

	getblock(infp, (byte*) ttpblock, 16, 0x7AF0, 16, 1);
	printbytetable("TP Scale Fuel", ttpblock, 16, 16, romdata, NULL, NULL);

	getblock(infp, (byte*) ttpblock, 16, 0x7E80, 16, 1);
	printbytetable("TTP-Min Table", ttpblock, 16, 16, romdata, NULL, NULL);

	getblock(infp, (byte*) ttpblock, 16, 0x7E90, 16, 1);
	printbytetable("TTP-Max Table", ttpblock, 16, 16, romdata, NULL, NULL);

	fclose(infp);

	return 0;
}
/* }}} */

/*  {{{ edit_rom */
int edit_rom(const char *romfile)
{
	int i, j;
	int paridx[2];
	int mapidx[2];
	struct stat stbuf;
	FILE *infp;
	FILE *outfp;
	ROMEDITDATA d;
	Menu m;
	ROMPARTABENT *pp;
	ROMMAPTABENT *mp;
	pthread_t thread;
	int rc;

	if (lstat(romfile, &stbuf) < 0) {
		fprintf(stderr, "ERROR: stat(%s): %s\n", romfile, strerror(errno));
		return -1;
	}

	if (stbuf.st_size != ROMSZ) {
		fprintf(stderr, "ERROR: ROM file %s must be exactly %d bytes.\n", romfile, ROMSZ);
		return -2;
	}

	infp = fopen(romfile, "r");

	fseek(infp, 0, SEEK_SET);
	fread(d.rombuf, sizeof(byte), ROMSZ, infp);

	pthread_mutex_init(&ecudata_mutex, NULL);

	if ((rc = pthread_create(&thread, NULL, edit_rom_daq_thread, NULL))) {
    printf("ERROR; return code from pthread_create() is %d\n", rc);
    exit(-1);
  }
	
	initscr();
	start_color();
	cbreak();
	noecho();
	keypad(stdscr, TRUE);
	nonl();
	intrflush(stdscr, FALSE);
	curs_set(0);

	m = [_menu new];

	i = 0;

	paridx[0] = i;

	for (pp = pars; pp->id != NULL; pp++, i++)
		[m additem: pp->desc];

	paridx[1] = i - 1;

	[m additem: NULL];
	i++;

	mapidx[0] = i;

	for (mp = maps; mp->id != NULL; mp++, i++)
		[m additem: mp->desc];

	mapidx[1] = i - 1;

	[m additem: NULL];

	[m additem: "Quit"];

	while (1) {
		[m setDisplayFunc: show_dev_status];

		j = [m select];

		if (j == [m length] - 1)
			goto endloop;

		if (j >= mapidx[0] && j <= mapidx[1]) {
			for (mp = maps, i = 0; mp->id != NULL; mp++, i++)
				if (i == (j - mapidx[0]))
					break;

			if (i != (j - mapidx[0]) || mp->id == NULL) {
				fprintf(stderr, "ERROR: Invalid map type with index %d selected\n", j);
				return -3;
			}

			if (!get_map_block(&d, mp))
				return -4;

			edit_rom_map(&d, d.mapent);

		} else if (j >= paridx[0] && j <= paridx[1]) {
			for (pp = pars, i = 0; pp->id != NULL; pp++, i++)
				if (i == (j - paridx[0]))
					break;

			if (i != (j - paridx[0]) || pp->id == NULL) {
				fprintf(stderr, "ERROR: Invalid parameter type with index %d selected\n", j);
				return -3;
			}

			edit_rom_param(&d, pp);
		}
	}

	endloop: 

	fclose(infp);

	outfp = fopen(romfile, "w");
	fwrite(d.rombuf, sizeof(byte), ROMSZ, outfp);
	fclose(outfp);

	endwin();

	pthread_cancel(thread);
	pthread_mutex_destroy(&ecudata_mutex);

	ecu_close();
	ecu_status = STATUS_IDLE;

//	wbo2_close();
//	wbo2_status = STATUS_IDLE;

	return 0;
}
/* }}} */

/* {{{ edit_rom_param */
int edit_rom_param(ROMEDITDATA *d, ROMPARTABENT *par)
{
	char entrybuffer[50];
	int entrybufpos = 0;
	int entryloc_x, entryloc_y;
	word val;
	int c, i;
	char prompt[50];

	switch (par->datawidth) {
		case DATA_BYTE:
			if (par->fconvto != NULL)
				snprintf(entrybuffer, 50, "%.0f", par->fconvto(d->rombuf[par->offset]));
			else
				snprintf(entrybuffer, 50, "%d", d->rombuf[par->offset]);
			break;
		case DATA_WORD:
			if (par->fconvto != NULL)
				snprintf(entrybuffer, 50, "%.0f", par->fconvto(WORD_PACK1(d->rombuf, par->offset)));
			else
				snprintf(entrybuffer, 50, "%d", WORD_PACK1(d->rombuf, par->offset));
			break;
	}
	entrybufpos = strlen(entrybuffer);

	sprintf(prompt, "%s = ", par->desc);

	curs_set(1);

	while (1) {
		erase();

		attrset(Pair(COLOR_GREEN, COLOR_BLACK)|A_BOLD);

		mvprintw(1, 0, "%s", prompt);
		entryloc_y = 1;
		entryloc_x = strlen(prompt);

		attrset(Pair(COLOR_WHITE, COLOR_BLACK)|A_BOLD);

		mvprintw(entryloc_y, entryloc_x, "                           ");
		for (i = 0; i < entrybufpos; i++)
			mvprintw(entryloc_y, entryloc_x + i, "%c", entrybuffer[i]);

		refresh();

		c = getch();

		switch (c) {
			case KEY_ENTER:
			case '\r':
			case '\n':
				entrybuffer[entrybufpos] = 0;
				if (par->fconvfrom)
					val = par->fconvfrom(entrybuffer, 0);
				else
					val = atoi(entrybuffer);
				switch (par->datawidth) {
					case DATA_BYTE:
						d->rombuf[par->offset] = val;
						if (romu_ready)
            	if (romu_hidden_write_with_retry(par->offset, d->rombuf[par->offset]) < 0)
								romu_ready = false;
						break;
					case DATA_WORD:
						d->rombuf[par->offset] = val >> 8;
						d->rombuf[par->offset + 1] = val & 0xFF;
						if (romu_ready)
            	if (romu_hidden_write_with_retry(par->offset, d->rombuf[par->offset]) < 0 || 
									romu_hidden_write_with_retry(par->offset + 1, d->rombuf[par->offset + 1]) < 0)
								romu_ready = false;
						break;
				}
				*entrybuffer = 0;
				entrybufpos = 0;
				return 0;

			case KEY_BACKSPACE:
				if (entrybufpos - 1 >= 0)
					entrybufpos--;
				entrybuffer[entrybufpos]=0;
				break;

			default:
				entrybuffer[entrybufpos++] = c;
				break;
		}
	}

	return 1;
}
/* }}} */

/* {{{ edit_rom_ecu_data_callback */
void edit_rom_ecu_data_callback(struct ecu_mon_param_data rdata[MAX_MONITOR_PARAMETERS], int n, void *arg)
{
	int i;
	pthread_mutex_lock(&ecudata_mutex);

	if (!ecudata)
		ecudata = malloc(sizeof(struct ecu_mon_param_data) * MAX_MONITOR_PARAMETERS);

	memcpy(ecudata, rdata, sizeof(struct ecu_mon_param_data) * MAX_MONITOR_PARAMETERS);
	ecudata_count = n;

	fprintf(log_fh, "%d,", (int) time(NULL));

	for (i = 0; i < n; i++) {
		fprintf(log_fh, "%f", rdata[i].value);
		if (i < (n-1))
			fprintf(log_fh, ",");
	}

	if (wbo2data)
		fprintf(log_fh, ",%.01f", wbo2data);
		
	fprintf(log_fh, "\n");

	pthread_mutex_unlock(&ecudata_mutex);
}
/* }}} */

/* {{{ edit_rom_wbo2_data_callback */
void edit_rom_wbo2_data_callback(float afr, void *arg)
{
	wbo2data = afr;
}
/* }}} */

/* {{{ edit_rom_daq_thread */
void *edit_rom_daq_thread(void *idp) 
{
	int rv;
	int maxfd = -1;
	int params[] = { 
		MON_PARAM_CAS_POS, 
		MON_PARAM_MAF_VOLT, 
		MON_PARAM_TPS_VOLT, 
		MON_PARAM_LH_INJECTION_TIME, 
		MON_PARAM_RH_INJECTION_TIME, 
		MON_PARAM_IGN_TIMING, 
		MON_PARAM_LH_AF_ALPHA,
		MON_PARAM_RH_AF_ALPHA,
		MON_PARAM_LH_AF_ALPHA_SL,
		MON_PARAM_RH_AF_ALPHA_SL,
		MON_PARAM_LH_O2_VOLT,
		MON_PARAM_RH_O2_VOLT,
		MON_PARAM_COOLANT_TEMP
	};
	fd_set readset;
	struct timeval tv;

	log_fh = fopen(LIVEDATA_LOG_FILE, "w");

	while (1) {
		/*
		if (wbo2_status == STATUS_IDLE) {
			wbo2_status = STATUS_CONNECTING;
			if (wbo2_init(wbo2dev, 10) == RET_OK && 
					wbo2_start_monitor(edit_rom_wbo2_data_callback, NULL) == RET_OK)
				wbo2_status = STATUS_STREAMING;
			else {
				wbo2_close();
				wbo2_status = STATUS_IDLE;
			}
		}
*/

		if (ecu_status == STATUS_IDLE) {
			ecu_status = STATUS_CONNECTING;
			if (ecu_init(ecudev, 10) == RET_OK &&
					ecu_start_monitor(params, sizeof(params)/sizeof(*params), edit_rom_ecu_data_callback, NULL) == RET_OK)
				ecu_status = STATUS_STREAMING;
			else {
				ecu_close();
				ecu_status = STATUS_IDLE;
			}
		}

		if (!romu_ready)
			romu_init();

		FD_ZERO(&readset);

		if (ecu_status == STATUS_STREAMING) {
			FD_SET(ecu_get_fd(), &readset);
			maxfd = ecu_get_fd();
		}

		if (wbo2_status == STATUS_STREAMING) {
			FD_SET(wbo2_get_fd(), &readset);
			maxfd = MAX(wbo2_get_fd(), maxfd);
		}

		tv.tv_sec = 5;
		tv.tv_usec = 0;

		rv = select(maxfd + 1, &readset, NULL, NULL, &tv);

		if (rv > 0) {
			if (ecu_status == STATUS_STREAMING && FD_ISSET(ecu_get_fd(), &readset))
				if (ecu_process_data_from_fd() != RET_OK) {
					ecu_close();
					ecu_status = STATUS_IDLE;
				}

			if (wbo2_status == STATUS_STREAMING && FD_ISSET(wbo2_get_fd(), &readset))
				if (wbo2_process_data_from_fd() != RET_OK) {
					wbo2_close();
					wbo2_status = STATUS_IDLE;
				}
		} else {
			/* No data in 5 seconds.  Very unusual.  Try reconnecting. */
			debug(DBG_VERBOSE, "No data from DAQ thread in 5 seconds.  Reconnecting.");

			wbo2_close();
			wbo2_status = STATUS_IDLE;

			ecu_close();
			ecu_status = STATUS_IDLE;
		}
	}

	fclose(log_fh);

	return NULL;
}
/* }}} */

/* {{{ show_dev_status */
void show_dev_status()
{
	char *status;
	char tmpbuf[BUFSIZ];
	int scrsz_y, scrsz_x;

	getmaxyx(stdscr, scrsz_y, scrsz_x);

		attrset(Pair(COLOR_WHITE, COLOR_BLACK)|A_BOLD);

		switch (ecu_status) {
			case 0: status = "Disconnected"; break;
			case 1: status = "Connecting"; break;
			case 2: status = "Streaming"; break;
		}

		sprintf(tmpbuf, "ECU: %s", status);
		mvprintw(scrsz_y - 3, scrsz_x - strlen(tmpbuf), "%s", tmpbuf);

		switch (wbo2_status) {
			case 0: status = "Disconnected"; break;
			case 1: status = "Connecting"; break;
			case 2: status = "Streaming"; break;
		}

		sprintf(tmpbuf, "WBO2: %s", status);
		mvprintw(scrsz_y - 2, scrsz_x - strlen(tmpbuf), "%s", tmpbuf);

		switch (romu_ready) {
			case 1: status = "Connected"; break;
			case 0: status = "Disconnected"; break;
		}

		sprintf(tmpbuf, "Romulator: %s", status);
		mvprintw(scrsz_y - 1, scrsz_x - strlen(tmpbuf), "%s", tmpbuf);

}
/* }}} */

/* {{{ edit_rom_map */
int edit_rom_map(ROMEDITDATA *d, ROMMAPTABENT *mapent)
{
	int c, rc;
	int cur_x, cur_y;
	int x, y, i, j;
	int fg, bg, at;
	double realval;
	int entrymode = 0;
	char entrybuffer[50];
	int entrybufpos = 0;
	int entryloc_x, entryloc_y;
	void (*entrycallback)(char *buffer, int len, ROMEDITDATA *d);
	int vs_ts_x = -1, vs_ts_y = -1;
	int vs_te_x = -1, vs_te_y = -1;
	double mtrace_value_x = -1, mtrace_value_y = -1;
	int mtrace_x[2]={-1,-1}, mtrace_y[2]={-1,-1};
	double mtrace_scale_x[2]={-1,-1}, mtrace_scale_y[2]={-1,-1};
	double mtrace_scalespan_x, mtrace_scalespan_y;
	double mtrace_mid_x, mtrace_mid_y;
	double mtrace_value[4][4];
	double mtrace_interp[2];
	double mtrace_interp_val;
	int vselect = 0;
	int scrsz_x, scrsz_y;
	fd_set readset;
	struct timeval tv;
	char tmpbuf[BUFSIZ];

	getmaxyx(stdscr, scrsz_y, scrsz_x);

	d->vs_start_x = d->vs_end_x = -1;
	d->vs_start_y = d->vs_end_y = -1;
	d->vb_start_x = d->vb_end_x = -1;
	d->vb_start_y = d->vb_end_y = -1;

	cur_x = 0;
	cur_y = 0;

	RESET_EDIT_BUFFER(d);

	check_set_flags((word*)d->mapblock, (byte*)d->flags, MAX_MAP_WIDTH, d->mapent->rows, d->mapent->cols);


	while (1) {
		erase();

		attrset(Pair(COLOR_WHITE, COLOR_BLACK)|A_BOLD);

		show_dev_status();

		attrset(Pair(COLOR_RED, COLOR_BLACK)|A_BOLD);

		for (x = 0; x < d->mapent->cols; x++) {
			if (d->mapent->scaleX != MAP_SCALE_NONE)
				mvprintw(0, LEGEND_Y_LEN + (x*LEGEND_X_LEN), "%s", scaleFunctions[d->mapent->scaleX](x, d->rombuf));
			else
				mvprintw(0, LEGEND_Y_LEN + (x*LEGEND_X_LEN), "%d", x);
		}

		attroff(A_BOLD);

		pthread_mutex_lock(&ecudata_mutex);

		if (ecudata != NULL && ecudata_count > 0 && ecu_status == STATUS_STREAMING) {
			mtrace_value_x = -1;
			mtrace_value_y = -1;

			switch (d->mapent->scaleY) {
				case MAP_SCALE_RPM_FUEL:
				case MAP_SCALE_RPM_TIMING:
					mtrace_value_y = ecudata[0].value;
					break;

				case MAP_SCALE_TP_FUEL:
				case MAP_SCALE_TP_TIMING:
					mtrace_value_y = equate_tp(d, ecudata[1].value, ecudata[0].value);
					break;

				default: break;
			}

			switch (d->mapent->scaleX) {
				case MAP_SCALE_RPM_FUEL:
				case MAP_SCALE_RPM_TIMING:
					mtrace_value_x = ecudata[0].value;
					break;

				case MAP_SCALE_TP_FUEL:
				case MAP_SCALE_TP_TIMING:
					mtrace_value_x = equate_tp(d, ecudata[1].value, ecudata[0].value);
					break;

				default: break;
			}

			mvprintw(d->mapent->rows + ecudata_count + 3, 2, "MTrace Val Y = %.02f, MTrace Val X = %.02f\n", mtrace_value_y, mtrace_value_x);

			attrset(Pair(COLOR_YELLOW, COLOR_BLACK)|A_BOLD);

			for (i = 0; i < ecudata_count; i++)
				mvprintw(d->mapent->rows + 2 + i, 2, "%-32s  %.02f %s\n", ecudata[i].param->description, ecudata[i].value, ecudata[i].param->unit);

			attrset(Pair(COLOR_MAGENTA, COLOR_BLACK)|A_BOLD);

			sprintf(tmpbuf, "%s: %.02f", "Equated TP", equate_tp(d, ecudata[1].value, ecudata[0].value));
			mvprintw(d->mapent->rows + 2, scrsz_x - 2 - strlen(tmpbuf), "%s", tmpbuf);

			sprintf(tmpbuf, "%s: %d", "RPM", (word)ecudata[0].value);
			mvprintw(d->mapent->rows + 3, scrsz_x - 2 - strlen(tmpbuf), "%s", tmpbuf);

			sprintf(tmpbuf, "%s: %d", "MAF mV", (word)ecudata[1].value);
			mvprintw(d->mapent->rows + 4, scrsz_x - 2 - strlen(tmpbuf), "%s", tmpbuf);

			if (mtrace_value_x >= 0 && mtrace_value_y >= 0) {
				for (i = 0; i < d->mapent->cols - 1; i++) {
					RAWSCALEFUNC f = rawScaleFunctions[d->mapent->scaleX];
					if (f(i, d->rombuf) <= mtrace_value_x && f(i + 1, d->rombuf) >= mtrace_value_x) {
						mtrace_x[0] = i;
						mtrace_x[1] = i + 1;
						mtrace_scale_x[0] = f(i, d->rombuf);
						mtrace_scale_x[1] = f(i + 1, d->rombuf);
					}
				}
				for (i = 0; i < d->mapent->rows - 1; i++) {
					RAWSCALEFUNC f = rawScaleFunctions[d->mapent->scaleY];
					if (f(i, d->rombuf) <= mtrace_value_y && f(i + 1, d->rombuf) >= mtrace_value_y) {
						mtrace_y[0] = i;
						mtrace_y[1] = i + 1;
						mtrace_scale_y[0] = f(i, d->rombuf);
						mtrace_scale_y[1] = f(i + 1, d->rombuf);
					}
				}

				mvprintw(d->mapent->rows + ecudata_count + 4, 2, "Map Trace Y = [%d %d], Map Trace X = [%d %d]\n", mtrace_y[0], mtrace_y[1], mtrace_x[0], mtrace_x[1]);

				if (mtrace_x[0] >= 0 && mtrace_x[1] >= 0 &&
						mtrace_y[0] >= 0 && mtrace_y[1] >= 0) {

					mtrace_mid_x = mtrace_value_x - mtrace_scale_x[0];
					mtrace_mid_y = mtrace_value_y - mtrace_scale_x[0];
					mtrace_scalespan_x = mtrace_scale_x[1] - mtrace_scale_x[0];
					mtrace_scalespan_y = mtrace_scale_y[1] - mtrace_scale_y[0];

					for (i = mtrace_y[0]; j <= mtrace_y[1]; i++)
						for (j = mtrace_x[0]; j <= mtrace_x[1]; j++)
							mtrace_value[i - mtrace_y[0]][j - mtrace_x[0]] = d->mapblock[i][j];

					mtrace_interp[0] = mtrace_value[0][0] + ((mtrace_mid_x / mtrace_scalespan_x) * (mtrace_value[0][1] - mtrace_value[0][0]));
					mtrace_interp[1] = mtrace_value[1][0] + ((mtrace_mid_x / mtrace_scalespan_x) * (mtrace_value[1][1] - mtrace_value[1][0]));
					mtrace_interp_val = mtrace_interp[0] + ((mtrace_mid_y / mtrace_scalespan_y)) * (mtrace_interp[1] - mtrace_interp[0]);

					if (d->mapent->fconvto)
						mvprintw(d->mapent->rows + ecudata_count + 5, 2, "Map Value = %.02f\n", d->mapent->fconvto(mtrace_interp_val));
					else
						mvprintw(d->mapent->rows + ecudata_count + 5, 2, "Map Value = %.02f\n", mtrace_interp_val);
				}
			}
		}

		pthread_mutex_unlock(&ecudata_mutex);

		if (wbo2data) {
			attrset(Pair(COLOR_GREEN, COLOR_BLACK)|A_BOLD);
			sprintf(tmpbuf, "%s: %.1f", "WBO2 AFR", wbo2data);
			mvprintw(d->mapent->rows + 6, scrsz_x - 2 - strlen(tmpbuf), "%s", tmpbuf);
		}

		for (y = 0; y < d->mapent->rows; y++) {
			attrset(Pair(COLOR_RED, COLOR_BLACK)|A_BOLD);

			if (d->mapent->scaleY != MAP_SCALE_NONE)
				mvprintw(y+1, 0, "%s", scaleFunctions[d->mapent->scaleY](y, d->rombuf));
			else
				mvprintw(y+1, 0, "%d", y);

			for (x = 0; x < d->mapent->cols; x++) {
				at = A_BOLD;
				bg = COLOR_BLACK;
				if (d->mapent->usefulFlags & FLAG_BIT_8_PRESENT && d->flags[y][x] & FLAG_BIT_8_PRESENT)
					fg = COLOR_GREEN;
				else
					fg = COLOR_WHITE;

				if (mtrace_x[0] >= 0 && mtrace_x[1] >= 0 &&
						mtrace_y[0] >= 0 && mtrace_y[1] >= 0 &&
						x >= mtrace_x[0] && x <= mtrace_x[1] &&
						y >= mtrace_y[0] && y <= mtrace_y[1]) {
					bg = COLOR_YELLOW;
				} else if (vselect) {
					vs_ts_x = MIN(d->vs_start_x, cur_x);
					vs_ts_y = MIN(d->vs_start_y, cur_y);
					vs_te_x = MAX(cur_x, d->vs_start_x);
					vs_te_y = MAX(cur_y, d->vs_start_y);
				}

				if (cur_y == y && cur_x == x)
					bg = COLOR_WHITE;
				else if (vselect && y >= vs_ts_y && y <= vs_te_y && x >= vs_ts_x && x <= vs_te_x)
					bg = COLOR_BLUE;
				else if (d->vb_start_y >= 0 && d->vb_end_y >= 0 && d->vb_start_x >= 0 && d->vb_end_x >= 0 &&
						y >= d->vb_start_y && y <= d->vb_end_y && x >= d->vb_start_x && x <= d->vb_end_x)
					bg = COLOR_GREEN;

				if (*d->editbuffer[y][x] != 0)
					fg = COLOR_RED;

				if (bg != COLOR_BLACK && fg == COLOR_WHITE)
					fg = COLOR_BLACK;

				attrset(Pair(fg,bg)|at);

				if (*d->editbuffer[y][x] != 0) {
					mvprintw(y+1, LEGEND_Y_LEN + (x*LEGEND_X_LEN), "%s", d->editbuffer[y][x]);
				} else {
					if (d->mapent->fconvto)
						realval = d->mapent->fconvto(d->mapblock[y][x]);
					else
						realval = d->mapblock[y][x];

					switch (d->mapent->datafmt) {
						case DFMT_INTEGER:
							mvprintw(y+1, LEGEND_Y_LEN + (x*LEGEND_X_LEN), "%d", (word)realval);
							break;
						case DFMT_FLOAT_2_DEC:
							mvprintw(y+1, LEGEND_Y_LEN + (x*LEGEND_X_LEN), "%-2.2f", realval);
							break;
						case DFMT_FLOAT_1_DEC:
							mvprintw(y+1, LEGEND_Y_LEN + (x*LEGEND_X_LEN), "%-2.1f", realval);
							break;
					}
				}
			}
		}

		if (entrymode) {
			attrset(Pair(COLOR_YELLOW, COLOR_BLACK)|A_BOLD);
			mvprintw(entryloc_y, 0, "Scale Factor (ie 0.5): ");
			refresh();
			attrset(Pair(COLOR_WHITE, COLOR_BLACK)|A_BOLD);
			for (i = 0; i < entrybufpos; i++)
				mvprintw(entryloc_y, entryloc_x + i, "%c", entrybuffer[i]);
		}
		
		refresh();

		FD_ZERO(&readset);
		FD_SET(fileno(stdin), &readset);
		tv.tv_sec = 0;
		tv.tv_usec = 75000; // 75 mS

		rc = select(fileno(stdin) + 1, &readset, NULL, NULL, &tv);

		if (rc > 0) {
			c = getch();

			if (!entrymode) {
				switch (c) {
					case KEY_DOWN:
						if (cur_y + 1 == d->mapent->rows)
							cur_y = 0;
						else
							cur_y += 1;
						break;
					
					case KEY_UP:
						if (cur_y - 1 < 0)
							cur_y = d->mapent->rows - 1;
						else
							cur_y -= 1;
						break;
	
					case KEY_LEFT:
						if (cur_x - 1 < 0)
							cur_x = d->mapent->cols - 1;
						else
							cur_x -= 1;
						break;
	
					case KEY_RIGHT:
						if (cur_x + 1 == d->mapent->cols)
							cur_x = 0;
						else
							cur_x += 1;
						break;

					case 'v':
						if (vselect) {
							d->vs_end_x = MAX(cur_x, d->vs_start_x);
							d->vs_end_y = MAX(cur_y, d->vs_start_y);
							d->vs_start_x = MIN(d->vs_start_x, cur_x);
							d->vs_start_y = MIN(d->vs_start_y, cur_y);
							d->vb_end_x = d->vs_end_x;
							d->vb_end_y = d->vs_end_y;
							d->vb_start_x = d->vs_start_x;
							d->vb_start_y = d->vs_start_y;
							d->vs_end_x = d->vs_end_y = d->vs_start_x = d->vs_start_y = -1;
							vselect = 0;
						} else {
							d->vs_start_x = cur_x;
							d->vs_start_y = cur_y;
							vselect = 1;
						}
						break;

					case 'p':
						//char pastebuffer[MAX_MAP_HEIGHT][MAX_MAP_WIDTH];
						//memset(pastebuffer, 0, MAX_MAP_HEIGHT * MAX_MAP_WIDTH);
						if (d->vb_start_y >= 0 && d->vb_start_x >= 0 && d->vb_end_y >= 0 && d->vb_end_x >= 0) {
							for (y = d->vb_start_y; y <= d->vb_end_y; y++) {
								for (x = d->vb_start_x; x <= d->vb_end_x; x++) {
									sprintf(d->editbuffer[cur_y + (y - d->vb_start_y)][cur_x + (x - d->vb_start_x)], "%.02f", current_map_value(d, y, x));
								}
							}
						}
						break;

					case 't':
						if (d->vb_start_y >= 0 && d->vb_start_x >= 0 && d->vb_end_y >= 0 && d->vb_end_x >= 0) {
							for (y = d->vb_start_y; y <= d->vb_end_y; y++) {
								for (x = d->vb_start_x; x <= d->vb_end_x; x++) {
									if (d->flags[y][x] & FLAG_BIT_8_PRESENT) {
										d->flags[y][x] &= ~FLAG_BIT_8_PRESENT;
									} else {
										d->flags[y][x] |= FLAG_BIT_8_PRESENT;
									}
									sprintf(tmpbuf, "%f", d->mapent->fconvto(d->mapblock[y][x]));
									d->mapblock[y][x] = d->mapent->fconvfrom(tmpbuf, d->flags[y][x]);
								}
							}
						} else {
							if (d->flags[cur_y][cur_x] & FLAG_BIT_8_PRESENT) {
								d->flags[cur_y][cur_x] &= ~FLAG_BIT_8_PRESENT;
							} else {
								d->flags[cur_y][cur_x] |= FLAG_BIT_8_PRESENT;
							}
							sprintf(tmpbuf, "%f", d->mapent->fconvto(d->mapblock[cur_y][cur_x]));
							d->mapblock[cur_y][cur_x] = d->mapent->fconvfrom(tmpbuf, d->flags[cur_y][cur_x]);
						}
						break;
						
					case 'w':
						FLUSH_EDIT_BUFFER(d);
						RESET_EDIT_BUFFER(d);
						break;
	
					case 'Q':
						goto endmaploop;
			
					case 'q':
						for (i = 0; i < d->mapent->rows; i++)
							for (j = 0; j < d->mapent->cols; j++) {
								int off = d->mapent->offset + (i * d->mapent->cols * d->mapent->datawidth) + (j * d->mapent->datawidth);
								switch (d->mapent->datawidth) {
									case DATA_WORD:
										d->rombuf[off] = (d->mapblock[i][j] >> 8) & 0xFF;
										d->rombuf[off+1] = d->mapblock[i][j] & 0xFF;
										break;

									case DATA_BYTE:
									default:
										memcpy(d->rombuf + off, &d->mapblock[i][j], d->mapent->datawidth);
								}
							}
						goto endmaploop;
		
					case 's':
						entrymode = 1;
						entrybufpos = 0;
						entrycallback = scaledata;
						entryloc_x = 23;
						entryloc_y = scrsz_y - 1;
						curs_set(1);
						break;
	
					case '\b':
					case KEY_BACKSPACE:
						if (d->editbufpos[cur_y][cur_x] - 1 >= 0)
							d->editbufpos[cur_y][cur_x]--;
						d->editbuffer[cur_y][cur_x][d->editbufpos[cur_y][cur_x]]=0;
		
					default:
						if (isdigit(c) || c == '.') {
							d->editbuffer[cur_y][cur_x][d->editbufpos[cur_y][cur_x]++] = c;
							d->editbuffer[cur_y][cur_x][d->editbufpos[cur_y][cur_x]] = 0;
					}
				}
			} else {
				switch (c) {
					case KEY_ENTER:
					case '\r':
					case '\n':
						entrybuffer[entrybufpos] = 0;
						entrycallback(entrybuffer, entrybufpos, d);
						*entrybuffer = 0;
						entrybufpos = 0;
						entrymode = 0;
						curs_set(0);
						break;
	
					case KEY_BACKSPACE:
						if (entrybufpos - 1 >= 0)
							entrybufpos--;
						entrybuffer[entrybufpos]=0;
						break;
	
					default:
						entrybuffer[entrybufpos++] = c;
						mvprintw(entryloc_y, entryloc_x, "                           ");
						for (i = 0; i < entrybufpos; i++)
							mvprintw(entryloc_y, entryloc_x + i, "%c", entrybuffer[i]);
						break;
				}
			}
		}
	}	

endmaploop:

	return 0;
}
/* }}} */

/* {{{ copy_rom_map */
int copy_rom_map(const char *srcfile, const char *dstfile, const char *maptype)
{
	struct stat stbuf;
	byte mapblock[MAX_MAP_HEIGHT][MAX_MAP_WIDTH];
	byte rombuf[ROMSZ];
	FILE *infp;
	FILE *outfp;
	ROMMAPTABENT *mapent;
	int i;

	if (lstat(srcfile, &stbuf) < 0) {
		fprintf(stderr, "ERROR: stat(%s): %s\n", srcfile, strerror(errno));
		exit(-1);
	}

	if (stbuf.st_size != ROMSZ) {
		fprintf(stderr, "ERROR: Source ROM file %s must be exactly %d bytes.\n", srcfile, ROMSZ);
		exit(-2);
	}

	if (lstat(dstfile, &stbuf) < 0) {
		fprintf(stderr, "ERROR: stat(%s): %s\n", dstfile, strerror(errno));
		exit(-1);
	}
	if (stbuf.st_size != ROMSZ) {
		fprintf(stderr, "ERROR: Dest ROM file %s must be exactly %d bytes.\n", dstfile, ROMSZ);
		exit(-2);
	}

	for (mapent = maps; mapent->id != NULL; mapent++)
		if (strcmp(maptype, mapent->id) == 0)
			break;

	if (mapent->id == NULL) {
		fprintf(stderr, "ERROR: Map type %s is not valid.\n", maptype);
		return -3;
	}

	printf("Copying %s map from %s to %s ...\n", mapent->id, srcfile, dstfile);

	infp = fopen(srcfile, "r");
	getblock(infp, (byte*) mapblock, MAX_MAP_WIDTH, mapent->offset, mapent->cols, mapent->rows);
	fclose(infp);

	infp = fopen(dstfile, "r");
	fread(rombuf, sizeof(byte), ROMSZ, infp);
	fclose(infp);

	for (i = 0; i < mapent->rows; i++)
		memcpy(rombuf + mapent->offset + (i * mapent->cols), mapblock[i], mapent->cols);

	outfp = fopen(dstfile, "w");
	fwrite(rombuf, sizeof(byte), ROMSZ, outfp);
	fclose(outfp);

	return 0;
}
/* }}} */
