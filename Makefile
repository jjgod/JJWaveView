CC = g++
CFLAGS = -Wall -I/opt/local/include
LDFLAGS = -framework Cocoa

test: test.o ArkLinePrefs.o ArkWaveView.o

ArkWaveView.o: ArkWaveView.mm
	$(CC) $(CFLAGS) $< -c -o $@

