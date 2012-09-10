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
#ifndef _CONV_H
#define _CONV_H

enum DATAFLAG {
	FLAG_NONE = 0,
	FLAG_BIT_8_PRESENT = 1
};

byte convertFromTiming(char *val, byte flags);
double convertToTiming(byte val);

byte convertFromAFR(char *val, byte flags);
double convertToAFR(byte val);

byte convertFromRPM(char *val, byte flags);
double convertToRPM(byte val);

byte convertFromSpeed(char *val, byte flags);
double convertToSpeed(byte val);

void check_set_flags(word *mapblock, byte *flags, int bwidth, int rows, int cols);

#endif
