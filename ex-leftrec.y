
/* example left-recursive first/first conflict. */

expr : expr plus term | alt1 | alt2 ;

