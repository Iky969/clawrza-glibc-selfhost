CC ?= gcc
CFLAGS ?= -O2 -Wall

all: hello

hello: src/hello.c
	$(CC) $(CFLAGS) -o hello src/hello.c

clean:
	rm -f hello
