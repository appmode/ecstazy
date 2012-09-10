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

byte convertFromTiming(char *val, byte flags)
{ 
	byte timing = atoi(val);
	if (flags & FLAG_BIT_8_PRESENT)
		timing |= (1<<7);
	return timing;
}

double convertToTiming(byte val)
{ 
	byte timing = val;
	if (timing & (1<<7))
		timing &= ~(1<<7);
	return timing;
}

byte convertFromAFR(char *val, byte flags) 
{ 
	double afr = strtod(val, NULL);
	double tmp;
	byte rv;
	if (flags & FLAG_BIT_8_PRESENT) {
		tmp = 100 - ((afr / 14.70) * 100);
		if (tmp < -63) tmp = -63;
		if (tmp > 63) tmp = 63;
 		rv = 192 - tmp;
	} else {
		rv = (128 * (14.70 / afr)) - 128;
		if (rv > 127) rv = 127;
	}
	return rv;
}

double convertToAFR(byte val)
{ 
	double afr;
	
	if (val & (1<<7)) 
		afr = 14.70 * (1 + ((double) val - 192) / 100); 
	else
		afr = 14.70 / (((double) val + 128) / 128); 

	return afr;
}

double convertToRPM(byte val)
{ 
	return val * 50;
}

byte convertFromRPM(char *val, byte flags)
{ 
	return atoi(val) / 50;
}

double convertToSpeed(byte val) 
{ 
	return val * 2;
}

byte convertFromSpeed(char *val, byte flags)
{ 
	return atoi(val) / 2;
}

void check_set_flags(word *mapblock, byte *flags, int bwidth, int rows, int cols)
{
	int x,y;
	for (y = 0; y < rows; y++)
		for (x = 0; x < cols; x++) {
			*(flags + (y*bwidth) + x) = 0;
			if (*(mapblock + (y*bwidth) + x) & (1<<7))
				*(flags + (y*bwidth) + x) |= FLAG_BIT_8_PRESENT;
		}
}

