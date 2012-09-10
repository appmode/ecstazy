# 
# Ecstazy Nissan 300ZX Diagnostic Tuning Suite
#
# Copyright (C) 2003-2009   Patrick Cole <z@amused.net>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
# Ecstazy makefile

CFLAGS  = -I. -Wall -ggdb -D_GNU_SOURCE -DDEBUG
LFLAGS  = -lncurses -lobjc -lpthread -lm
INLINEDEPFLAG = -MD

COMMON_OBJS   = common.o ecu.o conv.o rom.o array.o romulator.o wbo2.o
ECSTAZY_OBJS  = ecstazy.o color.o menu.o

BINS      = ecstazy 
LDLIBS    = $(LFLAGS)

all: $(BINS)

ecstazy: $(COMMON_OBJS) $(ECSTAZY_OBJS)
	$(CC) -o $@ $(ECSTAZY_OBJS) $(COMMON_OBJS) $(LDFLAGS) $(LDLIBS)

clean:
	rm -f $(COMMON_OBJS) $(ECSTAZY_OBJS) $(BINS) ecstazy.log *.d

distclean: clean

# -- Dark magic below this point.

# Include the dependencies that are available
The_DFiles = $(wildcard *.d)
ifneq ($(words $(The_DFiles)),0)
include $(The_DFiles)
endif 

# Dependency generation. We want to generate a .d file using gnu cpp.
# For GNU systems the compiler can spit out a .d file while it is compiling,
# this is specified with the INLINEDEPFLAG. Other systems might have a 
# makedep program that can be called after compiling, that's illistrated
# by the DEPFLAG case.
# Compile rules are expected to call this macro after calling the compiler
define DoDep
	@sed -e "1s/.*:/$(subst /,\\/,$@):/" $(basename $(@F)).d > $(@F).d
	@-rm -f $(basename $(@F)).d
endef

%.o: %.c
	$(CC) -c $(INLINEDEPFLAG) $(CFLAGS) -o $@ $<
	$(DoDep)
	
%.o: %.m
	$(CC) -c $(INLINEDEPFLAG) $(CFLAGS) -o $@ $<
	$(DoDep)
