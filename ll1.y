
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

struct symbol {
  char *name;

  int *first, *follow;
  int visited;

  int is_terminal;
  int derives_empty;
};

struct symbol *symbols;
int n_symbols;

struct production {
  int lineno;

  int lhs, *rhs;

  int yield;
  int derives_empty;

  int *predict;
};

struct production *prods;
int n_prods;

void symbols_init (void);
void symbols_free (void);
int symbols_find (char *name);
int symbols_add (char *name, int is_terminal);
void symbols_print (int is_terminal);
void symbols_print_empty (void);
void symbols_print_first (void);
void symbols_print_follow (void);

void prods_init (void);
void prods_free (void);
void prods_add (int lhs, int **rhsv);
void prods_print (void);
void prods_print_predict (void);

void derives_empty (void);
void first (void);
void follow (void);
void predict (void);
void conflicts (void);

int symv_len (int *sv);
int *symv_new (int s);
int *symv_add (int *sv, int s);

int symvv_len (int **vv);
int **symvv_new (int *v);
int **symvv_add (int **vv, int *v);
%}

%union {
  int sym, *symv, **symvv;
  char *id;
}

%token EPSILON ID DERIVES END OR

%type<sym> symbol
%type<symv> symbols
%type<symvv> productions

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

int symbol_is_empty (int sym) {
  return (sym >= 1 && sym <= n_symbols &&
          strcmp(symbols[sym - 1].name, STR_EPSILON) == 0);
}

void symbols_init (void) {
  symbols = NULL;
  n_symbols = 0;
}

void symbols_free (void) {
  int i;

  for (i = 0; i < n_symbols; i++) {
    free(symbols[i].name);

    if (symbols[i].first)
      free(symbols[i].first);

    if (symbols[i].follow)
      free(symbols[i].follow);
  }

  free(symbols);
}

int symbols_find (char *name) {
  int i;

  for (i = 0; i < n_symbols; i++) {
    if (strcmp(symbols[i].name, name) == 0)
      return i + 1;
  }

  return 0;
}

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

void symbols_print (int is_terminal) {
  int i;

  for (i = 0; i < n_symbols; i++) {
    if (symbols[i].is_terminal == is_terminal)
      printf("  %s\n", symbols[i].name);
  }
}

void symbols_print_empty (void) {
  char buf[32];
  int i, n;

  for (i = n = 0; i < n_symbols; i++) {
    if (strlen(symbols[i].name) > n)
      n = strlen(symbols[i].name);
  }

  snprintf(buf, 32, "  %%%ds -->* %%%%empty\n", n);

  for (i = 0; i < n_symbols; i++) {
    if (symbol_is_empty(i + 1))
      continue;

    if (symbols[i].derives_empty)
      printf(buf, symbols[i].name);
  }
}

void symbols_print_first (void) {
  int i, j, n, nwrap, nfi, *fi;
  char buf[8];

  for (i = 0; i < n_symbols; i++) {
    if (symbols[i].is_terminal)
      continue;

    fi = symbols[i].first;
    nfi = symv_len(fi);

    for (j = n = 0; j < nfi; j++) {
      if (strlen(symbols[fi[j] - 1].name) > n)
        n = strlen(symbols[fi[j] - 1].name);
    }

    n += 2;
    nwrap = 76 / n;

    snprintf(buf, 8, "%%-%ds", n);
    printf("  first(%s):\n    ", symbols[i].name);

    for (j = 0; j < nfi; j++) {
      printf(buf, symbols[fi[j] - 1].name);

      if ((j + 1) % nwrap == 0 && j < nfi - 1)
        printf("\n    ");
    }

    printf("\n\n");
  }
}

void symbols_print_follow (void) {
  int i, j, n, nwrap, nfo, *fo;
  char buf[8];

  for (i = 0; i < n_symbols; i++) {
    if (symbols[i].is_terminal)
      continue;

    fo = symbols[i].follow;
    nfo = symv_len(fo);

    if (nfo == 0)
      continue;

    for (j = n = 0; j < nfo; j++) {
      if (strlen(symbols[fo[j] - 1].name) > n)
        n = strlen(symbols[fo[j] - 1].name);
    }

    n += 2;
    nwrap = 76 / n;

    snprintf(buf, 8, "%%-%ds", n);
    printf("  follow(%s):\n    ", symbols[i].name);

    for (j = 0; j < nfo; j++) {
      printf(buf, symbols[fo[j] - 1].name);

      if ((j + 1) % nwrap == 0 && j < nfo - 1)
        printf("\n    ");
    }

    printf("\n\n");
  }
}

void symbols_reset_visited (void) {
  int i;

  for (i = 0; i < n_symbols; i++)
    symbols[i].visited = 0;
}

void prods_init (void) {
  prods = NULL;
  n_prods = 0;
}

void prods_free (void) {
  int i;

  for (i = 0; i < n_prods; i++) {
    free(prods[i].rhs);

    if (prods[i].predict)
      free(prods[i].predict);
  }

  free(prods);
}

void prods_add (int lhs, int **rhsv) {
  int i, *rhs, n;

  n = symvv_len(rhsv);

  for (i = 0; i < n; i++) {
    rhs = rhsv[i];

    prods = (struct production*)
      realloc(prods, ++n_prods * sizeof(struct production));

    if (!prods)
      derp("unable to resize production list");

    prods[n_prods - 1].lineno = yylineno;

    prods[n_prods - 1].lhs = lhs;
    prods[n_prods - 1].rhs = rhs;

    prods[n_prods - 1].yield = 0;
    prods[n_prods - 1].derives_empty = 0;
    prods[n_prods - 1].predict = NULL;
  }

  free(rhsv);
}

void prods_print (void) {
  int i, j, lhs, lhs_prev, *rhs;

  lhs_prev = 0;

  for (i = 0; i < n_prods; i++) {
    lhs = prods[i].lhs;
    rhs = prods[i].rhs;

    if (lhs != lhs_prev) {
      printf("\n  %s :", symbols[lhs - 1].name);
      lhs_prev = lhs;
    }
    else {
      for (j = 0; j < strlen(symbols[lhs - 1].name) + 3; j++)
        printf(" ");

      printf("|");
    }

    for (j = 0; j < symv_len(rhs); j++)
      printf(" %s", symbols[rhs[j] - 1].name);

    printf("\n");
  }
}

void prods_print_predict (void) {
  int i, j, n, nwrap, npred, lhs, *rhs, *pred;
  char buf[8];

  for (i = 0; i < n_prods; i++) {
    lhs = prods[i].lhs;
    rhs = prods[i].rhs;

    pred = prods[i].predict;
    npred = symv_len(pred);

    printf("  %s :", symbols[lhs - 1].name);
    for (j = 0; j < symv_len(rhs); j++)
      printf(" %s", symbols[rhs[j] - 1].name);

    for (j = n = 0; j < npred; j++) {
      if (strlen(symbols[pred[j] - 1].name) > n)
        n = strlen(symbols[pred[j] - 1].name);
    }

    n += 2;
    nwrap = 76 / n;

    snprintf(buf, 8, "%%-%ds", n);
    printf("\n    ");

    for (j = 0; j < npred; j++) {
      printf(buf, symbols[pred[j] - 1].name);

      if ((j + 1) % nwrap == 0 && j < npred - 1)
        printf("\n    ");
    }

    printf("\n\n");
  }
}

int symv_len (int *sv) {
  int n = 0;

  if (!sv)
    return 0;

  while (sv[n])
    n++;

  return n;
}

int *symv_new (int s) {
  int *sv = (int*) malloc(2 * sizeof(int));
  if (!sv)
    return NULL;

  sv[0] = s;
  sv[1] = 0;

  return sv;
}

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

int *symv_incl (int *sv, int s) {
  int i;

  if (!sv)
    return symv_new(s);

  for (i = 0; i < symv_len(sv); i++) {
    if (sv[i] == s)
      return sv;
  }

  return symv_add(sv, s);
}

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

int symvv_len (int **vv) {
  int n = 0;

  if (!vv)
    return 0;

  while (vv[n])
    n++;

  return n;
}

int **symvv_new (int *v) {
  int **vv = (int**) malloc(2 * sizeof(int*));
  if (!vv)
    return NULL;

  vv[0] = v;
  vv[1] = NULL;

  return vv;
}

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

void derives_empty_check_prod (int i, int **work) {
  if (prods[i].yield == 0) {
    prods[i].derives_empty = 1;

    if (symbols[prods[i].lhs - 1].derives_empty == 0) {
      symbols[prods[i].lhs - 1].derives_empty = 1;
      *work = symv_add(*work, prods[i].lhs);
    }
  }
}

void derives_empty (void) {
  int i, j, k, *work, n_work;

  work = NULL;
  n_work = 0;

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

void first (void) {
  int i, *set;

  for (i = 0; i < n_symbols; i++) {
    symbols_reset_visited();

    set = symv_new(i + 1);
    symbols[i].first = first_set(set);
    free(set);
  }
}

int follow_set_allempty (int *set) {
  int i;

  for (i = 0; i < symv_len(set); i++) {
    if (symbols[set[i] - 1].derives_empty == 0 ||
        symbols[set[i] - 1].is_terminal)
      return 0;
  }

  return 1;
}

int *follow_set (int sym) {
  int i, j, k, *result, *tail, *fi;

  result = NULL;

  if (symbols[sym - 1].visited == 0) {
    symbols[sym - 1].visited = 1;

    for (i = 0; i < n_prods; i++) {
      for (j = 0; j < symv_len(prods[i].rhs); j++) {
        if (prods[i].rhs[j] != sym)
          continue;

        tail = prods[i].rhs + (j + 1);

        if (*tail) {
          fi = symbols[*tail - 1].first;
          for (k = 0; k < symv_len(fi); k++)
            result = symv_incl(result, fi[k]);
        }

        if (follow_set_allempty(tail)) {
          fi = follow_set(prods[i].lhs);
          for (k = 0; k < symv_len(fi); k++)
            result = symv_incl(result, fi[k]);

          free(fi);
        }
      }
    }
  }

  return result;
}

void follow (void) {
  int i, j, nfo, *fo;

  for (i = 0; i < n_symbols; i++) {
    symbols_reset_visited();

    if (symbols[i].is_terminal)
      continue;

    symbols[i].follow = fo = follow_set(i + 1);
    nfo = symv_len(fo);

    for (j = 0; j < nfo; j++) {
      if (symbol_is_empty(fo[j])) {
        fo[j] = fo[nfo - 1];
        fo[nfo - 1] = 0;
        break;
      }
    }
  }
}

int *predict_set (int iprod, int *set) {
  int i, *result, *fo;

  symbols_reset_visited();
  result = first_set(set);

  if (prods[iprod].derives_empty) {
    symbols_reset_visited();
    fo = follow_set(prods[iprod].lhs);

    for (i = 0; i < symv_len(fo); i++)
      result = symv_incl(result, fo[i]);

    free(fo);
  }

  return result;
}

void predict (void) {
  int i, j, k, lhs, npred, *pred;

  for (i = 0; i < n_symbols; i++) {
    lhs = i + 1;

    if (symbols[i].is_terminal)
      continue;

    for (j = 0; j < n_prods; j++) {
      if (prods[j].lhs != lhs)
        continue;

      prods[j].predict = pred = predict_set(j, prods[j].rhs);
      npred = symv_len(pred);

      for (k = 0; k < npred; k++) {
        if (symbol_is_empty(pred[k])) {
          pred[k] = pred[npred - 1];
          pred[npred - 1] = 0;
          break;
        }
      }
    }
  }
}

void conflicts_print (int id1, int id2, int *overlap) {
  int i, n, nwrap;
  char buf[8];

  printf("  %s :", symbols[prods[id1].lhs - 1].name);
  for (i = 0; i < symv_len(prods[id1].rhs); i++)
    printf(" %s", symbols[prods[id1].rhs[i] - 1].name);

  printf("\n  %s :", symbols[prods[id2].lhs - 1].name);
  for (i = 0; i < symv_len(prods[id2].rhs); i++)
    printf(" %s", symbols[prods[id2].rhs[i] - 1].name);

  for (i = n = 0; i < symv_len(overlap); i++) {
    if (strlen(symbols[overlap[i] - 1].name) > n)
      n = strlen(symbols[overlap[i] - 1].name);
  }

  n += 2;
  nwrap = 76 / n;

  snprintf(buf, 8, "%%-%ds", n);
  printf("\n    ");

  for (i = 0; i < symv_len(overlap); i++) {
    printf(buf, symbols[overlap[i] - 1].name);

    if ((i + 1) % nwrap == 0 && i < symv_len(overlap) - 1)
      printf("\n    ");
  }

  printf("\n\n");
}

void conflicts (void) {
  int i, j1, j2, *pred1, *pred2, *u;
  int header = 0;

  for (i = 0; i < n_symbols; i++) {
    if (symbols[i].is_terminal)
      continue;

    for (j1 = 0; j1 < n_prods; j1++) {
      pred1 = prods[j1].predict;
      if (prods[j1].lhs != i + 1)
        continue;

      for (j2 = j1 + 1; j2 < n_prods; j2++) {
        pred2 = prods[j2].predict;
        if (prods[j2].lhs != i + 1)
          continue;

        u = symv_intersect(pred1, pred2);

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

void yyerror (const char *msg) {
  fprintf(stderr, "%s: error: %s:%d: %s\n", argv0, yyfname, yylineno, msg);
}

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

