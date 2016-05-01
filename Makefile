
CC=gcc
CFLAGS=-g -Wall -Wextra -std=c99

YACC=bison
YFLAGS=-d

RM=rm -rf

BIN=ll1

OBJ=$(addsuffix .o,$(BIN))
SRC=$(addsuffix .c,$(BIN))
HDR=$(addsuffix .h,$(BIN))
YIN=$(addsuffix .y,$(BIN))

all: $(BIN)

$(BIN): $(OBJ)
	@echo " LD   $@"
	@$(CC) $(CFLAGS) -o $@ $^

$(OBJ): $(SRC)
	@echo " CC   $^"
	@$(CC) $(CFLAGS) -o $@ -c $^

$(SRC): $(YIN)
	@echo " YACC $^"
	@$(YACC) $(YFLAGS) -o $@ $^

clean:
	@echo " CLEAN"
	@$(RM) $(BIN) $(OBJ) $(SRC) $(HDR)
	@$(RM) $(BIN).dSYM

again: clean all

lines:
	@echo " WC"
	@wc -l $(YIN)

