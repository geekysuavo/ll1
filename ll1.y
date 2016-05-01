
/* ll1.y: a dirty hack for checking if a bison-format CFG is LL(1).
 *
 * Copyright (c) 2016 Bradley Worley <geekysuavo@gmail.com>
 * Released under the MIT License. See LICENSE.md for details.
 */

/* enable verbose errors and debugging information in bison. */
%error-verbose
%debug

%{
/* include the required standard c library headers. */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>

/* include the (bison-generated) main header file. */
#include "ll1.h"

/* define a string that we should recognize as 'epsilon'. */
#define STR_EPSILON "%empty"

/* pre-declare functions used by yyparse(). */
void yyerror (const char *msg);
int yylex (void);

/* pre-declare variables used by derp(), main(), yyparse() */
const char *yyfname, *argv0;
int yylineno;
FILE *yyin;

/* data structure for holding grammar symbol information.
 */
struct symbol {
  /* symbol @name */
  char *name;

  /* @first and @follow sets for non-terminal symbols. */
  int *first, *follow;
  int visited;

  /* whether the symbol @is_terminal or @derives_empty. */
  int is_terminal;
  int derives_empty;
};

/* data structure for holding productions of the grammar.
 */
struct production {
  /* @lhs: left-hand side one-based symbol table index.
   * @rhs: right-hand side one-based symbol table indices.
   */
  int lhs, *rhs;

  /* terminal @yield of nonterminals and whether
   * a nonterminal @derives_empty.
   */
  int yield;
  int derives_empty;

  /* @predict set for each production. */
  int *predict;
};

/* symbol table. */
struct symbol *symbols;
int n_symbols;

/* production list. */
struct production *prods;
int n_prods;

/* pre-declare symbol table functions. */
void symbols_init (void);
void symbols_free (void);
int symbols_find (char *name);
int symbols_add (char *name, int is_terminal);
void symbols_print (int is_terminal);
void symbols_print_empty (void);
void symbols_print_first (void);
void symbols_print_follow (void);

/* pre-declare production list functions. */
void prods_init (void);
void prods_free (void);
void prods_add (int lhs, int **rhsv);
void prods_print (void);
void prods_print_predict (void);

/* pre-declare functions to learn information about the grammar. */
void derives_empty (void);
void first (void);
void follow (void);
void predict (void);
void conflicts (void);

/* pre-declare symbol array functions. */
int symv_len (int *sv);
int *symv_new (int s);
int *symv_add (int *sv, int s);
void symv_print (int *sv);

/* pre-declare symbol double-array functions. */
int symvv_len (int **vv);
int **symvv_new (int *v);
int **symvv_add (int **vv, int *v);
%}

/* define the data structure used for passing attributes with symbols
 * in the parsed grammar.
 */
%union {
  /* @sym: one-based symbol table index.
   * @symv: zero-terminated array of symbol table indices.
   * @symvv: null-terminated array of symbol table index arrays.
   * @id: identifier string prior to symbol table translation.
   */
  int sym, *symv, **symvv;
  char *id;
}

/* define the set of terminal symbols to parse. */
%token EPSILON ID DERIVES END OR

/* set up attribute types of nonterminals. */
%type<sym> symbol
%type<symv> symbols
%type<symvv> productions

/* set up attribute types of terminals. */
%type<id> ID EPSILON

%%

grammar : rules ;

rules : rules rule | rule ;

rule : ID DERIVES productions END { prods_add(symbols_add($1, 0), $3); };

productions : productions OR symbols { $$ = symvv_add($1, $3); }
            | symbols                { $$ = symvv_new($1);     };

symbols : symbols symbol { $$ = symv_add($1, $2); }
        | symbol         { $$ = symv_new($1);     };

symbol : ID      { $$ = symbols_add($1, 1); }
       | EPSILON { $$ = symbols_add($1, 1); };

%%

/* derp(): write an error message to stderr and end execution.
 */
void derp (const char *fmt, ...) {
  va_list vl;

  fprintf(stderr, "%s: error: ", argv0);

  va_start(vl, fmt);
  vfprintf(stderr, fmt, vl);
  va_end(vl);

  fprintf(stderr, "\n");
  fflush(stderr);
  exit(1);
}

/* main(): application entry point.
 */
int main (int argc, char **argv) {
  symbols_init();
  prods_init();

  argv0 = argv[0];

  if (argc != 2)
    derp("input filename required");

  yylineno = 0;
  yyfname = argv[1];
  yyin = fopen(yyfname, "r");

  if (!yyin)
    derp("%s: %s", yyfname, strerror(errno));

  if (yyparse())
    derp("%s: parse failed", yyfname);

  fclose(yyin);

  derives_empty();
  first();
  follow();
  predict();

  printf("Terminal symbols:\n\n");
  symbols_print(1);
  printf("\n");

  printf("Non-terminal symbols:\n\n");
  symbols_print(0);
  printf("\n");

  printf("Grammar:\n");
  prods_print();
  printf("\n");

  printf("Empty derivations:\n\n");
  symbols_print_empty();
  printf("\n");

  printf("First sets:\n\n");
  symbols_print_first();

  printf("Follow sets:\n\n");
  symbols_print_follow();

  printf("Predict sets:\n\n");
  prods_print_predict();

  conflicts();

  symbols_free();
  prods_free();

  return 0;
}

/* symbol_is_empty(): return whether a symbol (specified by the one-based
 * index @sym) is the epsilon terminal.
 */
int symbol_is_empty (int sym) {
  return (sym >= 1 && sym <= n_symbols &&
          strcmp(symbols[sym - 1].name, STR_EPSILON) == 0);
}

/* symbols_init(): initialize the global symbol table.
 */
void symbols_init (void) {
  symbols = NULL;
  n_symbols = 0;
}

/* symbols_free(): deallocate the global symbol table.
 */
void symbols_free (void) {
  for (int i = 0; i < n_symbols; i++) {
    free(symbols[i].name);

    if (symbols[i].first)
      free(symbols[i].first);

    if (symbols[i].follow)
      free(symbols[i].follow);
  }

  free(symbols);
}

/* symbols_find(): get the one-based index of a symbol (by @name) in the
 * symbol table, or 0 if no such symbol exists.
 */
int symbols_find (char *name) {
  int i;

  for (i = 0; i < n_symbols; i++) {
    if (strcmp(symbols[i].name, name) == 0)
      return i + 1;
  }

  return 0;
}

/* symbols_add(): ensure that a symbol having @name and @is_terminal
 * flag exists in the symbol table. if the symbol @name exists, its
 * @is_terminal flag is updated based on the passed value. the
 * one-based symbol table index is returned.
 */
int symbols_add (char *name, int is_terminal) {
  int sym = symbols_find(name);
  if (sym) {
    symbols[sym - 1].is_terminal &= is_terminal;

    free(name);
    return sym;
  }

  symbols = (struct symbol*)
    realloc(symbols, ++n_symbols * sizeof(struct symbol));

  if (!symbols)
    derp("unable to resize symbol table");

  symbols[n_symbols - 1].name = strdup(name);
  symbols[n_symbols - 1].is_terminal = is_terminal;
  symbols[n_symbols - 1].derives_empty = 0;
  symbols[n_symbols - 1].visited = 0;
  symbols[n_symbols - 1].first = NULL;
  symbols[n_symbols - 1].follow = NULL;

  free(name);
  return n_symbols;
}

/* symbols_print(): print all symbols in the table with @is_terminal
 * flag equaling a certain value.
 */
void symbols_print (int is_terminal) {
  for (int i = 0; i < n_symbols; i++) {
    if (symbols[i].is_terminal == is_terminal)
      printf("  %s\n", symbols[i].name);
  }
}

/* symbols_print_empty(): print all symbols that may derive epsilon
 * in zero or more steps.
 */
void symbols_print_empty (void) {
  unsigned int len;
  char buf[32];
  int i;

  for (i = 0, len = 0; i < n_symbols; i++) {
    if (strlen(symbols[i].name) > len)
      len = strlen(symbols[i].name);
  }

  snprintf(buf, 32, "  %%%us -->* %%%%empty\n", len);

  for (i = 0; i < n_symbols; i++) {
    if (symbol_is_empty(i + 1))
      continue;

    if (symbols[i].derives_empty)
      printf(buf, symbols[i].name);
  }
}

/* symbols_print_first(): print all symbols in the @first sets of all
 * nonterminals.
 */
void symbols_print_first (void) {
  for (int i = 0; i < n_symbols; i++) {
    if (symbols[i].is_terminal ||
        symv_len(symbols[i].first) == 0)
      continue;

    printf("  first(%s):", symbols[i].name);
    symv_print(symbols[i].first);
  }
}

/* symbols_print_follow(): print all symbols in the @follow sets of all
 * nonterminals.
 */
void symbols_print_follow (void) {
  for (int i = 0; i < n_symbols; i++) {
    if (symbols[i].is_terminal ||
        symv_len(symbols[i].follow) == 0)
      continue;

    printf("  follow(%s):", symbols[i].name);
    symv_print(symbols[i].follow);
  }
}

/* symbols_reset_visite(): reset the @visited flag of all symbols
 * to zero. used internally by @first and @follow set construction.
 */
void symbols_reset_visited (void) {
  for (int i = 0; i < n_symbols; i++)
    symbols[i].visited = 0;
}

/* prods_init(): initialize the global productions list.
 */
void prods_init (void) {
  prods = NULL;
  n_prods = 0;
}

/* prods_free(): deallocate the global productions list.
 */
void prods_free (void) {
  for (int i = 0; i < n_prods; i++) {
    free(prods[i].rhs);

    if (prods[i].predict)
      free(prods[i].predict);
  }

  free(prods);
}

/* prods_add(): add a set of productions with left-hand-side symbol index
 * @lhs and right-hand-side symbol index arrays @rhsv to the global
 * productions list.
 */
void prods_add (int lhs, int **rhsv) {
  int n = symvv_len(rhsv);

  for (int i = 0; i < n; i++) {
    int *rhs = rhsv[i];

    prods = (struct production*)
      realloc(prods, ++n_prods * sizeof(struct production));

    if (!prods)
      derp("unable to resize production list");

    prods[n_prods - 1].lhs = lhs;
    prods[n_prods - 1].rhs = rhs;

    prods[n_prods - 1].yield = 0;
    prods[n_prods - 1].derives_empty = 0;
    prods[n_prods - 1].predict = NULL;
  }

  free(rhsv);
}

/* prods_print(): print the global productions list in a format that
 * resembles the original bison grammar.
 */
void prods_print (void) {
  int lhs_prev = 0;

  for (int i = 0; i < n_prods; i++) {
    int lhs = prods[i].lhs;
    int *rhs = prods[i].rhs;

    if (lhs != lhs_prev) {
      printf("\n  %s :", symbols[lhs - 1].name);
      lhs_prev = lhs;
    }
    else {
      for (unsigned int j = 0; j < strlen(symbols[lhs - 1].name) + 3; j++)
        printf(" ");

      printf("|");
    }

    for (int j = 0; j < symv_len(rhs); j++)
      printf(" %s", symbols[rhs[j] - 1].name);

    printf("\n");
  }
}

/* prods_print_predict(): print the @predict sets of all productions.
 */
void prods_print_predict (void) {
  for (int i = 0; i < n_prods; i++) {
    int lhs = prods[i].lhs;
    int *rhs = prods[i].rhs;

    printf("  %s :", symbols[lhs - 1].name);
    for (int j = 0; j < symv_len(rhs); j++)
      printf(" %s", symbols[rhs[j] - 1].name);

    symv_print(prods[i].predict);
  }
}

/* symv_len(): get the length of a symbol array. symbols are one-based, so
 * a zero-terminator is used to mark the end of the array.
 */
int symv_len (int *sv) {
  if (!sv)
    return 0;

  int n = 0;
  while (sv[n])
    n++;

  return n;
}

/* symv_new(): construct a new symbol array from a single symbol.
 */
int *symv_new (int s) {
  int *sv = (int*) malloc(2 * sizeof(int));
  if (!sv)
    return NULL;

  sv[0] = s;
  sv[1] = 0;

  return sv;
}

/* symv_add(): create a new symbol array that contains both @sv and @s,
 * free @sv, and return the new array.
 */
int *symv_add (int *sv, int s) {
  if (!sv)
    return symv_new(s);

  int nv = symv_len(sv);
  int *snew = (int*) malloc((nv + 2) * sizeof(int));
  if (!snew) {
    free(sv);
    return NULL;
  }

  memcpy(snew, sv, nv * sizeof(int));

  snew[nv] = s;
  snew[nv + 1] = 0;

  free(sv);
  return snew;
}

/* symv_incl(): create a new array as in symv_add(), but do not add
 * duplicate symbols to the array.
 */
int *symv_incl (int *sv, int s) {
  if (!sv)
    return symv_new(s);

  for (int i = 0; i < symv_len(sv); i++) {
    if (sv[i] == s)
      return sv;
  }

  return symv_add(sv, s);
}

/* symv_intersect(): create a new array that is the intersection of the
 * sets (symbol arrays) @sva and @svb.
 */
int *symv_intersect (int *sva, int *svb) {
  int ia, ib, na, nb, *result;

  result = NULL;
  na = symv_len(sva);
  nb = symv_len(svb);

  for (ia = 0; ia < na; ia++) {
    for (ib = 0; ib < nb; ib++) {
      if (svb[ib] == sva[ia])
        result = symv_incl(result, sva[ia]);
    }
  }

  return result;
}

/* symv_print(): print the symbols (as strings) within a symbol array,
 * making sure to keep pretty pretty formatting.
 */
void symv_print (int *sv) {
  unsigned int len;
  int i, n, wrap;
  char buf[16];

  n = symv_len(sv);

  for (i = len = 0; i < n; i++) {
    if (strlen(symbols[sv[i] - 1].name) > len)
      len = strlen(symbols[sv[i] - 1].name);
  }

  len += 2;
  wrap = 76 / len;
  snprintf(buf, 16, "%%-%us", len);

  printf("\n    ");
  for (i = 0; i < n; i++) {
    printf(buf, symbols[sv[i] - 1].name);

    if ((i + 1) % wrap == 0 && i < n - 1)
      printf("\n    ");
  }

  printf("\n\n");
}

/* symvv_len(): get the length of a symbol double-array. null-terminators
 * are used to mark the end of the outer array.
 */
int symvv_len (int **vv) {
  if (!vv)
    return 0;

  int n = 0;
  while (vv[n])
    n++;

  return n;
}

/* symvv_new(): construct a new symbol double-array from a single symbol
 * array.
 */
int **symvv_new (int *v) {
  int **vv = (int**) malloc(2 * sizeof(int*));
  if (!vv)
    return NULL;

  vv[0] = v;
  vv[1] = NULL;

  return vv;
}

/* symvv_add(): create a new symbol double-array that contains both @vv
 * and @v, free @vv, and return the new double-array.
 */
int **symvv_add (int **vv, int *v) {
  int nv = symvv_len(vv);
  int **vnew = (int**) malloc((nv + 2) * sizeof(int*));
  if (!vnew) {
    free(vv);
    return NULL;
  }

  memcpy(vnew, vv, nv * sizeof(int*));

  vnew[nv] = v;
  vnew[nv + 1] = 0;

  free(vv);
  return vnew;
}

/* derives_empty_check_prod(): internal worker function for derives_empty().
 */
void derives_empty_check_prod (int i, int **work) {
  if (prods[i].yield == 0) {
    prods[i].derives_empty = 1;

    if (symbols[prods[i].lhs - 1].derives_empty == 0) {
      symbols[prods[i].lhs - 1].derives_empty = 1;
      *work = symv_add(*work, prods[i].lhs);
    }
  }
}

/* derives_empty(): determine which symbols and productions in the grammar
 * are capable of deriving epsilon in any number of steps.
 */
void derives_empty (void) {
  int i, j, k;

  int *work = NULL;
  int n_work = 0;

  for (i = 0; i < n_symbols; i++) {
    if (symbol_is_empty(i + 1))
      symbols[i].derives_empty = 1;
    else
      symbols[i].derives_empty = 0;
  }

  for (i = 0; i < n_prods; i++) {
    prods[i].yield = 0;
    prods[i].derives_empty = 0;

    for (j = 0; j < symv_len(prods[i].rhs); j++) {
      if (!symbol_is_empty(prods[i].rhs[j]))
        prods[i].yield++;
    }

    derives_empty_check_prod(i, &work);
  }

  n_work = symv_len(work);
  while (n_work) {
    k = work[0];
    work[0] = work[n_work - 1];
    work[n_work - 1] = 0;

    for (i = 0; i < n_prods; i++) {
      for (j = 0; j < symv_len(prods[i].rhs); j++) {
        if (prods[i].rhs[j] != k)
          continue;

        prods[i].yield--;
        derives_empty_check_prod(i, &work);
      }
    }

    n_work = symv_len(work);
  }

  free(work);
}

/* first_set(): determine the @first set of a given set of symbols.
 */
int *first_set (int *set) {
  int i, j, *result, *fi_rhs;

  if (symv_len(set) == 0)
    return symv_new(0);

  if (symbols[set[0] - 1].is_terminal)
    return symv_new(set[0]);

  result = NULL;

  if (symbols[set[0] - 1].visited == 0) {
    symbols[set[0] - 1].visited = 1;

    for (i = 0; i < n_prods; i++) {
      if (prods[i].lhs != set[0])
        continue;

      fi_rhs = first_set(prods[i].rhs);
      for (j = 0; j < symv_len(fi_rhs); j++)
        result = symv_incl(result, fi_rhs[j]);

      free(fi_rhs);
    }
  }

  if (symbols[set[0] - 1].derives_empty) {
    fi_rhs = first_set(set + 1);
    for (j = 0; j < symv_len(fi_rhs); j++)
      result = symv_incl(result, fi_rhs[j]);

    free(fi_rhs);
  }

  return result;
}

/* first(): compute the @first sets of all symbols in the grammar.
 */
void first (void) {
  for (int i = 0; i < n_symbols; i++) {
    symbols_reset_visited();

    int *set = symv_new(i + 1);
    symbols[i].first = first_set(set);
    free(set);
  }
}

/* follow_set_allempty(): worker function for follow_set().
 */
int follow_set_allempty (int *set) {
  for (int i = 0; i < symv_len(set); i++) {
    if (symbols[set[i] - 1].derives_empty == 0 ||
        symbols[set[i] - 1].is_terminal)
      return 0;
  }

  return 1;
}

/* follow_set(): determine the @follow set of a given nonterminal.
 */
int *follow_set (int sym) {
  int *result = NULL;

  if (symbols[sym - 1].visited == 0) {
    symbols[sym - 1].visited = 1;

    for (int i = 0; i < n_prods; i++) {
      for (int j = 0; j < symv_len(prods[i].rhs); j++) {
        if (prods[i].rhs[j] != sym)
          continue;

        int *tail = prods[i].rhs + (j + 1);

        if (*tail) {
          int *fi = symbols[*tail - 1].first;
          for (int k = 0; k < symv_len(fi); k++)
            result = symv_incl(result, fi[k]);
        }

        if (follow_set_allempty(tail)) {
          int *fo = follow_set(prods[i].lhs);
          for (int k = 0; k < symv_len(fo); k++)
            result = symv_incl(result, fo[k]);

          free(fo);
        }
      }
    }
  }

  return result;
}

/* follow(): compute the @follow sets of all symbols in the grammar.
 */
void follow (void) {
  for (int i = 0; i < n_symbols; i++) {
    symbols_reset_visited();

    if (symbols[i].is_terminal)
      continue;

    symbols[i].follow = follow_set(i + 1);

    int *fo = symbols[i].follow;
    int nfo = symv_len(fo);

    for (int j = 0; j < nfo; j++) {
      if (symbol_is_empty(fo[j])) {
        fo[j] = fo[nfo - 1];
        fo[nfo - 1] = 0;
        break;
      }
    }
  }
}

/* predict_set(): determine the predict set of a given production.
 */
int *predict_set (int iprod, int *set) {
  symbols_reset_visited();
  int *result = first_set(set);

  if (prods[iprod].derives_empty) {
    symbols_reset_visited();
    int *fo = follow_set(prods[iprod].lhs);

    for (int i = 0; i < symv_len(fo); i++)
      result = symv_incl(result, fo[i]);

    free(fo);
  }

  return result;
}

/* predict(): compute the @predict sets of all productions in the grammar.
 */
void predict (void) {
  for (int i = 0; i < n_symbols; i++) {
    int lhs = i + 1;

    if (symbols[i].is_terminal)
      continue;

    for (int j = 0; j < n_prods; j++) {
      if (prods[j].lhs != lhs)
        continue;

      prods[j].predict = predict_set(j, prods[j].rhs);

      int *pred = prods[j].predict;
      int npred = symv_len(pred);

      for (int k = 0; k < npred; k++) {
        if (symbol_is_empty(pred[k])) {
          pred[k] = pred[npred - 1];
          pred[npred - 1] = 0;
          break;
        }
      }
    }
  }
}

/* conflicts_print(): print information about a predict set overlap
 * for a single pair of productions indexed by @id1 and @id2.
 */
void conflicts_print (int id1, int id2, int *overlap) {
  printf("  %s :", symbols[prods[id1].lhs - 1].name);
  for (int i = 0; i < symv_len(prods[id1].rhs); i++)
    printf(" %s", symbols[prods[id1].rhs[i] - 1].name);

  printf("\n  %s :", symbols[prods[id2].lhs - 1].name);
  for (int i = 0; i < symv_len(prods[id2].rhs); i++)
    printf(" %s", symbols[prods[id2].rhs[i] - 1].name);

  symv_print(overlap);
}

/* conflicts(): print all LL(1) conflicts in a grammar, if any.
 */
void conflicts (void) {
  int header = 0;

  for (int i = 0; i < n_symbols; i++) {
    if (symbols[i].is_terminal)
      continue;

    for (int j1 = 0; j1 < n_prods; j1++) {
      int *pred1 = prods[j1].predict;
      if (prods[j1].lhs != i + 1)
        continue;

      for (int j2 = j1 + 1; j2 < n_prods; j2++) {
        int *pred2 = prods[j2].predict;
        if (prods[j2].lhs != i + 1)
          continue;

        int *u = symv_intersect(pred1, pred2);

        if (symv_len(u)) {
          if (!header) {
            printf("Conflicts:\n\n");
            header = 1;
          }

          conflicts_print(j1, j2, u);
        }

        free(u);
      }
    }
  }

  if (header)
    printf("There were conflicts.\nGrammar is not LL(1)\n  :(\n\n");
  else
    printf("No conflicts, grammar is LL(1)\n  :D :D :D\n\n");
}

/* yyerror(): error reporting function called by bison on parse errors.
 */
void yyerror (const char *msg) {
  fprintf(stderr, "%s: error: %s:%d: %s\n", argv0, yyfname, yylineno, msg);
}

/* yylex(): lexical analysis function that breaks the input grammar file
 * into a stream of tokens for the bison parser.
 */
int yylex (void) {
  int c, ntext;
  char *text;

  while (1) {
    c = fgetc(yyin);
    text = NULL;
    ntext = 0;

    switch (c) {
      case EOF: return c;

      case ':': return DERIVES;
      case ';': return END;
      case '|': return OR;

      case '\n':
        yylineno++;
        break;
    }

    if (c == '\'') {
      text = (char*) malloc((++ntext + 1) * sizeof(char));
      if (!text)
        derp("unable to allocate token buffer");

      text[0] = fgetc(yyin);
      text[1] = '\0';

      c = fgetc(yyin);
      yylval.id = text;
      if (c == '\'' || text[0] != '\'')
        return ID;

      free(text);
    }

    if (c == '%' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) {
      text = (char*) malloc((++ntext + 1) * sizeof(char));
      if (!text)
        derp("unable to allocate token buffer");

      text[0] = c;
      text[1] = '\0';

      c = fgetc(yyin);
      while ((c >= 'a' && c <= 'z') ||
             (c >= 'A' && c <= 'Z') ||
             (c >= '0' && c <= '9') ||
              c == '_') {
        text = (char*) realloc(text, (++ntext + 1) * sizeof(char));
        if (!text)
          derp("unable to reallocate token buffer");

        text[ntext - 1] = c;
        text[ntext] = '\0';

        c = fgetc(yyin);
      }

      fseek(yyin, -1, SEEK_CUR);

      yylval.id = text;
      if (text[0] == '%') {
        if (strcmp(text, STR_EPSILON) == 0)
          return EPSILON;
        else
          free(text);
      }
      else
        return ID;
    }
  }
}

