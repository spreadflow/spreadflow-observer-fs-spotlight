EXECUTABLE=spreadflow-observer-fs-spotlight
SOURCES=\
	spreadflow-observer-fs-spotlight.m\
	BSONSerialization.m

FRAMEWORKS=-framework Foundation
LIBRARIES=-lobjc
CFLAGS=-Wall -Werror -fobjc-arc -g
LDFLAGS=$(LIBRARIES) $(FRAMEWORKS)

OBJECTS=$(patsubst %.m,build/%.m.o,$(SOURCES))

all: build/$(EXECUTABLE)

build:
	@mkdir -p $@

build/%.m.o: %.m
	$(CC) $(CFLAGS) -o $@ -c $<

$(OBJECTS): | build
build/$(EXECUTABLE): $(OBJECTS)
	$(CC) $(LDFLAGS) $(OBJECTS) -o $@

.PHONY: clean
clean:
	rm -rf build
