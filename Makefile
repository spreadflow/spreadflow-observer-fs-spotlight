EXECUTABLE=spreadflow-observer-fs-spotlight
SOURCES=\
	spreadflow-observer-fs-spotlight.m\
	vendor/ObjectiveBSON/BSON/BSONSerialization.m

FRAMEWORKS=-framework Foundation
LIBRARIES=-lobjc
INCLUDES=-Ivendor/ObjectiveBSON/BSON
CFLAGS=-Wall -Werror -fobjc-arc -g
LDFLAGS=$(LIBRARIES) $(FRAMEWORKS)

CXX=clang
OBJECTS=$(SOURCES:.m=.m.o)

%.m.o: %.m
	$(CXX) $(CFLAGS) $(INCLUDES) -o $@ -c $<

$(EXECUTABLE): $(OBJECTS)
	$(CXX) $(LDFLAGS) $(OBJECTS) -o $@

all: $(EXECUTABLE)

.PHONY: clean
clean:
	rm -f $(EXECUTABLE) $(OBJECTS)
