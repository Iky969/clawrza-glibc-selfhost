# In-guest rebuild kit for clawrza-glibc-selfhost.
# Everything here runs INSIDE QEMU with the distro's own gcc/make.
CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra

all: kinit spkg

kinit: kinit.c
	$(CC) $(CFLAGS) -o $@ $<

# "spkg.sh" is the source; "spkg" is the runnable copy.
spkg: spkg.sh
	cp spkg.sh spkg
	chmod 0755 spkg

clean:
	rm -f kinit spkg

.PHONY: all clean
