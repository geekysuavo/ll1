
# ll1

The **ll1** tool performs a small set of analyses on a
[context-free grammar] (https://en.wikipedia.org/wiki/Context-free_grammar)
in order to determine whether it is
[LL1(1)] (https://en.wikipedia.org/wiki/LL_grammar), and thus suitable
for implementation _via_ a
[predictive parser] (https://en.wikipedia.org/wiki/Recursive_descent_parser)
algorithm. Running a grammar through **ll1** can help the user catch
[Left recursion] (https://en.wikipedia.org/wiki/Left_recursion) and other
[conflicts] (https://en.wikipedia.org/wiki/LL_parser#LL.281.29_Conflicts)
that could ruin your day if they pop up later during parser implementation.

## Input format

**ll1** parses a CFG in an 'un-adorned'
[GNU Bison] (https://en.wikipedia.org/wiki/GNU_bison) format. The use of
_%empty_ is absolutely mandatory for writing epsilon productions. Character
literals are also accepted as tokens, so the following grammar:

```Bison
%%
expr : expr '+' term
     | expr '-' term
     | term ;

term : term '*' factor
     | term '/' factor
     | factor ;

factor : ID | NUM ;
%%
```

would be perfectly acceptable input, even though it will cause **ll1**
to pitch a fit about predict set overlaps between productions of the
same nonterminal. _;)_

However, **ll1** will be tickled pink to accept this input:

```Bison
expr : term expr_next ;
term : factor term_next ;

expr_next : '+' expr | '-' expr | %empty ;
term_next : '*' term | '/' term | %empty ;

factor : ID | NUM ;
```

In addition to _LL(1)_ conflict reports, **ll1** will also output information
about:

 * Terminal symbols
 * Nonterminal symbols
 * Nonterminals deriving `%empty`
 * Recapitulation of the input grammar
 * _First_, _follow_ and _predict_ sets

It's neither perfect nor complete, but it helps provide some basic insights.

## Caveats

I wrote **ll1** in a day, and only passed it through valgrind a handful of
times to check for serious errors. Given the fact that most of the data
structures are patterned after the null-termination patterns of C strings,
there has to be a bug or two in there... _somewhere..._

Anyways, if you run into one, let me know and I'll push a patch.

## Licensing

The **ll1** source code is released under the
[MIT license] (https://opensource.org/licenses/MIT). See the
[LICENSE.md] (LICENSE.md) file for the complete license terms.

And as always, enjoy!

*~ Brad.*

