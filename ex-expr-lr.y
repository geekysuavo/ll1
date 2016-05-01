
/* simple left-recursive expression grammar. */

expr : expr '+' term
     | expr '-' term
     | term
     ;

term : term '*' factor
     | term '/' factor
     | factor
     ;

factor : ID | NUM ;

