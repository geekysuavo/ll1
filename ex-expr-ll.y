
/* simple right-recursive (i.e. tail-recursive) expression grammar. */

expr : term expr_next ;

expr_next : '+' expr
          | '-' expr
          | %empty
          ;

term : factor term_next ;

term_next : '*' term
          | '/' term
          | %empty
          ;

factor : ID | NUM ;

