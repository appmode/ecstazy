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
#ifndef _ARRAY_H
#define _ARRAY_H

#import <objc/Object.h>

@interface _array : Object
{
	void **memory;
	int size;
}

+ new;
- init;
- free: (void (*)(void *)) user_free_func;

- (int) length;
- resize: (int) new_size;
- set: (int) ind data: (void *) data;
- (void *) get: (int) ind;

- (void *) head;
- (void *) tail;

- sort: (int (*)(const void *, const void *)) sortf;

@end

typedef id Array;

#endif
