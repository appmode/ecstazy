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
#ifndef _ROMULATOR_H
#define _ROMULATOR_H

#define ROMU_OK (0)
#define ROMU_TIMEOUT (1)
#define ROMU_COMMAND_FAIL (2)
#define ROMU_BAD_CKSUM (3)
#define ROMU_INIT_FAIL (4)

#define ROMU_ROM_SIZE   (32768)
#define ROMU_BLOCK_SIZE (256)

extern int romu_ready;

int romu_init();
int romu_write_buffer(word addr, byte *buffer, word len);
int romu_read_buffer(word addr, byte *buffer, word len);
int romu_hidden_write(word addr, byte data);
int romu_hidden_write_with_retry(word addr, byte data);

#endif /* _ROMULATOR_H */
