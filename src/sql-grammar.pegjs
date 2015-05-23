/* Helper Functions */
{
      // Parser utilities
  var _ = require('./sql-parser-util');
}

/* Start Grammar */
start
  = s:( stmt )*
  {
    return {
      'statement': s
    };
  }

/**
 * Expression definition reworked without left recursion for pegjs
 * {@link https://www.sqlite.org/lang_expr.html}
 */
expression "Expression"
  = expression_wrapped
  / expression_node
  / expression_value

expression_wrapped
  = sym_popen n:( expression_node ) sym_pclose
  { return n; }

expression_value
  = expression_cast
  / expression_exists
  / expression_case
  / expression_raise
  / expression_unary
  / bind_parameter
  / function_call
  / literal_value
  / id_column

expression_unary
  = o:( operator_unary ) e:( expression )
  {
    return {
      'type': 'expression',
      'format': 'unary',
      'variant': 'logical', // or { 'format': 'unary' }
      'expression': e,
      'modifier': o // TODO: could be { 'operator': o }
    };
  }

expression_cast
  = CAST sym_popen e:( expression ) a:( alias ) sym_pclose
  {
    return {
      'type': 'expression',
      'format': 'unary',
      'variant': 'cast',
      'expression': e,
      'modifier': a
    };
  }

expression_exists
  = ( n:( NOT )? o x:( EXISTS ) )? e:( stmt_select )
  {
    return {
      'type': 'expression',
      'format': 'unary',
      'variant': 'select',
      'expression': e,
      'modifier': _.compose([n, x])
    };
  }

expression_case
  = CASE e:( expression )? w:( expression_case_when )+ s:( expression_case_else )? END
  {
    var cond = w;
    if (_.isOkay(s)) {
      cond.push(s);
    }
    return {
      'type': 'expression',
      'format': 'binary', // TODO: Not sure about this
      'variant': 'case',
      'left': cond,
      'right': e,
      'modifier': null
    };
  }


expression_case_when
  = WHEN w:( expression ) THEN t:( expression )
  {
    return {
      'type': 'condition',
      'format': 'binary',
      'variant': 'when',
      'left': w,
      'right': t,
      'modifier': null
    };
  }

expression_case_else
  = ELSE e:( expression )
  {
    return {
      'type': 'condition',
      'format': 'else',
      'expression': e,
      'modifier': null
    };
  }

expression_raise
  = RAISE sym_popen a:( expression_raise_args ) sym_pclose
  {
    return {
      'type': 'expression',
      'format': 'unary',
      'variant': 'raise',
      'expression': a,
      'modifier': null
    };
  }

expression_raise_args
  = raise_args_ignore
  / raise_args_message

raise_args_ignore
  = f:( IGNORE )
  { return _.textNode(f); }

raise_args_message
  = f:( ROLLBACK / ABORT / FAIL ) sym_comma m:( error_message )
  { return _.textNode(f) + ', \'' + m + '\''; }

/* Expression Nodes */
expression_node
  = expression_collate
  / expression_compare
  / expression_null
  / expression_is
  / expression_between
  / expression_in
  / operation_binary

/** @note Removed expression on left-hand-side to remove recursion */
expression_collate
  = v:( expression_value ) COLLATE n:( name_collation )
  {
    return {
      'type': 'expression',
      'format': 'unary',
      'variant': 'collate',
      'expression': v,
      'modifier': {
        'type': 'name',
        'name': n // TODO: could also be { 'name': n }
      }
    };
  }

/** @note Removed expression on left-hand-side to remove recursion */
expression_compare
  = v:( expression_value ) n:( NOT )? m:( LIKE / GLOB / REGEXP / MATCH ) e:( expression ) x:( expression_escape )?
  {
    return {
      'type': 'expression',
      'format': 'binary',
      'variant': 'comparison',
      'comparison': _.compose([n, m]),
      'left': v,
      'right': e,
      'modifier': x
    };
  }

expression_escape
  = ESCAPE e:( expression )
  {
    return {
      'type': 'expression',
      'format': 'unary',
      'variant': 'escape',
      'expression': e,
      'modifier': null
    };
  }

/** @note Removed expression on left-hand-side to remove recursion */
expression_null
  = v:( expression_value ) o n:( expression_null_nodes )
  {
    return {
      'type': 'expression',
      'format': 'unary',
      'variant': 'null',
      'expression': v,
      'modifier': n
    };
  }

expression_null_nodes
  = i:( IS / NOT ) o n:( NULL ) {
    return _.compose([i, n]);
  }
  / n:( ISNULL / NOTNULL ) {
    return _.textNode(n);
  }

/** @note Removed expression on left-hand-side to remove recursion */
expression_is
  = v:( expression_value ) i:( IS ) n:( NOT )? e:( expression )
  {
    return {
      'type': 'expression',
      'format': 'binary',
      'variant': 'comparison',
      'comparison': _.compose([i, n]),
      'left': v,
      'right': e,
      'modifier': null
    };
  }

/** @note Removed expression on left-hand-side to remove recursion */
expression_between
  = v:( expression_value ) n:( NOT )? b:( BETWEEN ) e1:( expression ) AND e2:( expression )
  {
    return {
      'type': 'expression',
      'format': 'binary',
      'variant': 'comparison',
      'comparison': _.compose([n, b]),
      'left': v,
      'right': {
        'type': 'expression',
        'format': 'binary',
        'variant': 'range',
        'left': e1,
        'right': e2,
        'modifier': null
      },
      'modifier': null
    };
  }


/** @note Removed expression on left-hand-side to remove recursion */
expression_in
  = v:( expression_value ) n:( NOT )? i:( IN ) e:( expression_in_target )
  {
    return {
      'type': 'expression',
      'format': 'binary',
      'variant': 'comparison',
      'comparison': _.compose([i, n]),
      'left': v,
      'right': e,
      'modifier': x
    };
  }

expression_in_target
  = expression_list_or_select
  / id_table

expression_list_or_select
  = sym_popen e:( stmt_select / expression_list ) sym_pclose
  { return e; }

/**
 * Literal value definition
 * {@link https://www.sqlite.org/syntax/literal-value.html}
 */
literal_value "Literal Value"
  = literal_number
  / literal_string
  / literal_blob
  / literal_null
  / literal_date

literal_null
  = n:( NULL )
  {
    return {
      'type': 'literal',
      'variant': 'keyword',
      'value': _.textNode(n)
    };
  }

literal_date
  = d:( CURRENT_DATE / CURRENT_TIMESTAMP / CURRENT_TIME )
  {
    return {
      'type': 'literal',
      'variant': 'keyword',
      'value': _.textNode(d)
    };
  }

/**
 * Notes:
 *    1) SQL uses single quotes for string literals.
 *    2) Value is an identier or a string literal based on context.
 * {@link https://www.sqlite.org/lang_keywords.html}
 */
literal_string
  = s:( literal_string_single )
  {
    return {
      'type': 'literal',
      'variant': 'string',
      'value': _.textNode(s)
    };
  }

literal_string_single
  = sym_sglquote s:( literal_string_schar )* sym_sglquote
  {
    /**
      * @note Unescaped the pairs of literal single quotation marks
      */
    return _.unescape(_.textNode(s));
  }

literal_string_schar
  = "''"
  / [^\']

literal_blob
  = [x]i b:( literal_string_single )
  {
    return {
      'type': 'literal',
      'variant': 'blob',
      'value': _.textNode(b)
    };
  }

literal_number
  = literal_number_decimal
  / literal_number_hex

literal_number_decimal
  = d:( number_decimal_node ) e:( number_decimal_exponent )?
  {
    return {
      'type': 'literal',
      'variant': 'decimal',
      'value': _.compose([d, e], '')
    };
  }

number_decimal_node
  = number_decimal_full
  / number_decimal_fraction

number_decimal_full
  = f:( number_digit )+ b:( number_decimal_fraction )?
  { return _.compose([f, b], ''); }

number_decimal_fraction
  = t:( sym_dot ) d:( number_digit )+
  { return _.compose([t, d], ''); }

/* TODO: Not sure about "E"i or just "E" */
number_decimal_exponent
  = e:( "E"i ) s:( [\+\-] )? d:( number_digit )+
  { return _.compose([e, s, d], ''); }

literal_number_hex
  = f:( "0x"i ) b:( number_hex )*
  {
    return {
      'type': 'literal',
      'variant': 'hexidecimal',
      'value': _.compose([f, b], '')
    };
  }

number_hex
  = [0-9a-f]i

number_digit
  = [0-9]

/**
 * Bind Parameters have several syntax variations:
 * 1) "?" ( [0-9]+ )?
 * 2) [\$\@\:] name_char+
 * {@link https://www.sqlite.org/c3ref/bind_parameter_name.html}
 */
bind_parameter "Bind Parameter"
  = bind_parameter_numbered
  / bind_parameter_named
  / bind_parameter_tcl

/**
 * Bind parameters start at index 1 instead of 0.
 */
bind_parameter_numbered
  = q:( sym_quest ) id:( [1-9] [0-9]* )? o
  {
    return {
      'type': 'variable',
      'format': 'numbered',
      'name': _.compose([q, id], '')
    };
  }

bind_parameter_named
  = s:( [\:\@] ) name:( name_char )+ o
  {
    return {
      'type': 'variable',
      'format': 'named',
      'name': _.compose([s, name], '')
    };
  }

bind_parameter_tcl
  = d:( "$" ) name:( name_char / [\:] )+ o suffix:( bind_parameter_named_suffix )?
  {
    return {
      'type': 'variable',
      'format': 'tcl',
      'name': _.compose([_.compose([d, name], ''), suffix])
    };
  }

bind_parameter_named_suffix
  = q1:( sym_dblquote ) n:( !sym_dblquote any )* q2:( sym_dblquote )
  { return _.compose([q1, n, q2], ''); }

/** @note Removed expression on left-hand-side to remove recursion */
/* TODO: Need to refactor this so that expr1 AND expr2 is grouped/associated correctly */
operation_binary
  = v:( expression_value ) o o:( operator_binary ) o e:( expression )
  {
    return {
      'type': 'expression',
      'format': 'binary',
      'variant': 'operation',
      'operation': o,
      'left': v,
      'right': e,
      'modifier': null
    };
  }

expression_list "Expression List"
  = f:( expression ) rest:( expression_list_rest )*
  {
    return _.compose([f, rest], []);
  }

expression_list_rest
  = sym_comma e:( expression )
  { return e; }

function_call
  = n:( name_function ) sym_popen a:( function_call_args )? sym_pclose
  {
    return _.extend({
      'type': 'function',
      'name': n,
      'distinct': false,
      'expression': []
    }, a);
  }

function_call_args
  = ( d:( DISTINCT )? e:( expression_list ) ) {
    return {
      'distinct': _.isOkay(d),
      'expression': e
    };
  }
  / s:( select_star ) {
    return {
      'distinct': false,
      'expression': [{
        'type': 'identifier',
        'variant': 'star',
        'value': s
      }]
    };
  }

error_message "Error Message"
  = literal_string

stmt "Statement"
  = stmt_crud
  / stmt_create
  / stmt_drop

stmt_crud
  = w:( clause_with )? o s:( stmt_crud_types )
  {
    return _.extend(s, w);
  }

clause_with "WITH Clause"
  = WITH r:( RECURSIVE )? f:( expression_table ) o r:( clause_with_loop )*
  {
    // TODO: final format
    return {
      'type': 'with',
      'recursive': isOkay(r),
      'expression': _.compose([f, r], [])
    };
  }

clause_with_loop
  = sym_comma e:( expression_table )
  { return e; }

expression_table "Table Expression"
  = n:( name_table ) o a:( sym_popen name_column ( sym_comma name_column )* sym_pclose )? o AS s:( stmt_select )

stmt_crud_types
  = stmt_select
  / stmt_insert
  / stmt_update
  / stmt_delete

/** {@link https://www.sqlite.org/lang_select.html} */
stmt_select "SELECT Statement"
  = s:( select_loop ) o o:( select_order )? o l:( select_limit )?
  {
    return _.extend(s, {
      'order': o,
      'limit': l
    });
  }

select_order
  = ORDER BY o d:( select_order_list )
  { return d; }

select_limit
  = LIMIT o e:( expression ) o d:( select_limit_offset )?
  {
    return {
      'start': e,
      'offset': d
    };
  }

select_limit_offset
  = o:( OFFSET / sym_comma ) o e:( expression )
  { return e; }

select_loop
  = s:( select_parts ) o u:( select_loop_union )*
  {
    if ( _.isOkay(u) ) {
      // TODO: compound query
    }
    return s;
  }

select_loop_union
  = c:( operator_compound ) o s:( select_parts )
  {
    // TODO: compound query
  }

select_parts
  = select_parts_core
  / select_parts_values

select_parts_core
  = s:( select_core_select ) o f:( select_core_from )? o w:( select_core_where )? o g:( select_core_group )? o
  {
    // TODO: Not final syntax!
    return _.extend({
      'type': 'statement',
      'variant': 'select',
      'from': f,
      'where': w,
      'group': g
    }, s);
  }

select_core_select
  = SELECT d:( DISTINCT / ALL )? t:( select_target )
  {
    return {
      'result': t,
      'modifier': d
    };
  }

select_target
  = f:( select_node ) o r:( select_target_loop )*
  {
    return _.compose([f, r], []);
  }

select_target_loop
  = sym_comma n:( select_node )
  { return n; }

select_core_from
  = FROM s:( select_source )
  { return s; }

select_core_where
  = WHERE e:( expression )
  { return _.makeArray(e); }

select_core_group
  = GROUP BY e:( expression ) h:( select_core_having )?
  {
    // TODO: format
    return {
      'expression': _.makeArray(e),
      'having': h
    };
  }

select_core_having
  = HAVING e:( expression )
  { return e; }

select_node
  = select_node_star
  / select_node_aliased

select_node_star
  = q:( select_node_star_qualified )? s:( select_star )
  {
    // TODO: format
    return {
      'expression': _.compose([q, s], '')
    };
  }

select_node_star_qualified
  = n:( name_table ) s:( sym_dot )
  { return _.compose([n, s], ''); }

select_node_aliased
  = e:( expression ) a:( alias )?
  {
    // TODO: format
    return _.extend(e, {
      'alias': a
    });
  }

select_source
  = select_join_loop
  / select_source_loop

select_source_loop
  = f:( table_or_sub ) t:( source_loop_tail )*
  { return _.compose([f, t], []); }

source_loop_tail
  = sym_comma t:( table_or_sub )
  { return t; }

/* TODO: Need to create rules for second pattern */
table_or_sub
  = table_or_sub_sub
  / table_or_sub_table

table_or_sub_table
  = d:( table_or_sub_table_id ) i:( table_or_sub_index )?
  {
    return _.extend(d, {
      'index': i
    });
  }

table_or_sub_table_id
  = n:( id_table ) o a:( alias )?
  {
    return _.extend(n, {
      'alias': a
    });
  }

table_or_sub_index
  = i:( table_or_sub_index_node )
  {
    return {
      'type': 'index',
      'index': i
    };
  }

table_or_sub_index_node
  = ( INDEXED BY n:( name_index ) ) {
    return _.textNode(n);
  }
  / n:( NOT INDEXED ) {
    return _.textNode(n);
  }

table_or_sub_sub
  = sym_popen o l:( select_join_loop / select_source_loop ) o sym_pclose
  { return l; }

alias
  = AS n:( name )
  { return n; }

select_join_loop
  = t:( table_or_sub ) o j:( select_join_clause )*
  {
    // TODO: format
    return {
      'type': 'join',
      'source': t,
      'join': j
    };
  }

select_join_clause
  = o:( join_operator ) o n:( table_or_sub ) o c:( join_condition )?
  {
    // TODO: format
    return _.extend({
      'type': o,
      'source': n,
      'on': null,
      'using': null
    }, c);
  }

join_operator
  = n:( NATURAL )? o t:( ( LEFT (o OUTER )? ) / INNER / CROSS )? o j:( JOIN )
  { return _.compose([n, t, j]); }

join_condition
  = c:( join_condition_on / join_condition_using )
  { return c; }

join_condition_on
  = ON e:( expression )
  {
    return {
      'on': e
    };
  }

/* TODO: should it be name_column or id_column ? */
join_condition_using
  = USING f:( id_column ) o b:( join_condition_using_loop )*
  {
    return {
      'using': _.compose([f, b], [])
    };
  }

/* TODO: should it be name_column or id_column ? */
join_condition_using_loop
  = sym_comma o n:( id_column )
  { return n; }

select_parts_values
  = VALUES sym_popen o l:( expression_list ) o sym_pclose
  {
    // TODO: format
    return {
      'type': 'statement',
      'variant': 'values',
      'values': l
    };
  }

select_order_list
  = f:( select_order_list_item ) o b:( select_order_list_loop )?
  {
    return _.compose([f, b], []);
  }

select_order_list_loop
  = sym_comma o i:( select_order_list_item )
  { return i; }

select_order_list_item
  = e:( expression ) o c:( select_order_list_collate )? o d:( select_order_list_dir )?
  {
    // TODO: Not final format
    return {
      'direction': _.textNode(d),
      'expression': e,
      'modifier': c
    };
  }

select_order_list_collate
  = COLLATE n:( id_collation )
  { return n; }

select_order_list_dir
  = t:( ASC / DESC )
  { return _.textNode(t); }

select_star "All Columns"
  = sym_star

operator_compound "Compound Operator"
  = ( UNION ( ALL )? )
  / INTERSECT
  / EXCEPT

/* Unary and Binary Operators */

operator_unary "Unary Operator"
  = sym_tilde
  / sym_minus
  / sym_plus
  / NOT

/* TODO: Needs return format refactoring */
operator_binary "Binary Operator"
  = o:( binary_concat
  / ( binary_multiply / binary_mod )
  / ( binary_plus / binary_minus )
  / ( binary_left / binary_right / binary_and / binary_or )
  / ( binary_lt / binary_lte / binary_gt / binary_gte )
  / ( binary_assign / binary_equal / binary_notequal / ( IS ( NOT )? ) / IN / LIKE / GLOB / MATCH / REGEXP )
  / AND
  / OR )
  { return _.textNode(o); }

binary_concat "Or"
  = sym_pipe sym_pipe

binary_plus "Add"
  = sym_plus

binary_minus "Subtract"
  = sym_minus

binary_multiply "Multiply"
  = sym_star

binary_mod "Modulo"
  = sym_mod

binary_left "Shift Left"
  = binary_lt binary_lt

binary_right "Shift Right"
  = binary_gt binary_gt

binary_and "Logical AND"
  = sym_amp

binary_or "Logical OR"
  = sym_pipe

binary_lt "Less Than"
  = sym_lt

binary_gt "Greater Than"
  = sym_gt

binary_lte "Less Than Or Equal"
  = binary_lt sym_equal

binary_gte "Greater Than Or Equal"
  = binary_gt sym_equal

binary_assign "Assignment"
  = sym_equal

binary_equal "Equal"
  = binary_assign binary_assign

binary_notequal "Not Equal"
  = ( sym_excl binary_equal )
  / ( binary_lt binary_gt )

/* Database, Table and Column IDs */

id_database
  = n:( name_database )
  {
    return {
      'type': 'identifier',
      'variant': 'database',
      'name': n
    };
  }

id_table
  = d:( id_table_qualified )? n:( name_table )
  {
    return {
      'type': 'identifier',
      'variant': 'table',
      'name': _.compose([d, n], '')
    };
  }

id_table_qualified
  = n:( name_database ) d:( sym_dot )
  { return _.compose([n, d], ''); }

id_column
  = d:( id_table_qualified )? t:( id_column_qualified )? n:( name_column )
  {
    return {
      'type': 'identifier',
      'variant': 'column',
      'name': _.compose([d, t, n], '')
    };
  }

id_column_qualified
  = t:( name_table ) d:( sym_dot )
  { return _.compose([t, d], ''); }

id_collation
  = name_collation

/* TODO: FIX all name_* symbols */
name_database "Database Name"
  = name

name_table "Table Name"
  = name

name_column "Column Name"
  = name

name_collation "Collation Name"
  = name

name_index "Index Name"
  = name

name_function "Function Name"
  = name

name_type "Type Name"
  = name

/** {@link https://www.sqlite.org/lang_insert.html} */
stmt_insert "INSERT Statement"
  = ( ( INSERT ( OR ( REPLACE / ROLLBACK / ABORT / FAIL / IGNORE ) )? ) / REPLACE )
  ( INTO ( id_table ) ( sym_popen name_column ( sym_comma name_column )* sym_pclose )? )
  insert_parts

/* TODO: LEFT OFF HERE */
insert_parts
  = ( VALUES sym_popen expression_list sym_pclose)
  / ( stmt_select )
  / ( DEFAULT VALUES )

/* TODO: Complete */
stmt_update "UPDATE Statement"
  = any

/* TODO: Complete */
stmt_delete "DELETE Statement"
  = any

/* TODO: Complete */
stmt_create "CREATE Statement"
  = any

/* TODO: Complete */
stmt_drop "DROP Statement"
  = any

/* Naming rules */

/* TODO: Replace me! */
name_char
  = [a-z0-9\-\_]i

name
  = name_bracketed
  / name_backticked
  / name_dblquoted
  / name_unquoted

name_unquoted
  = n:( name_char )+
  ! ( reserved_words )
  { return _.textNode(n); }

/** @note Non-standard legacy format */
name_bracketed
  = sym_bopen o n:( name_unquoted ) o sym_bclose
  { return n; }

name_dblquoted
  = sym_dblquote n:( !sym_dblquote name_char )+ sym_dblquote
  { return _.textNode(n); }

/** @note Non-standard legacy format */
name_backticked
  = sym_backtick n:( !sym_backtick name_char ) sym_backtick
  { return _.textNode(n); }

/* Symbols */

sym_bopen "Open Bracket"
  = "[" o
sym_bclose "Close Bracket"
  = "]" o
sym_popen "Open Parenthesis"
  = "(" o
sym_pclose "Close Parenthesis"
  = ")" o
sym_comma "Comma"
  = "," o
sym_dot "Period"
  = "." o
sym_star "Asterisk"
  = "*" o
sym_quest "Question Mark"
  = "?" o
sym_sglquote "Single Quote"
  = "'" o
sym_dblquote "Double Quote"
  = '"' o
sym_backtick "Backtick"
  = "`" o
sym_tilde "Tilde"
  = "~" o
sym_plus "Plus"
  = "+" o
sym_minus "Minus"
  = "-" o
sym_equal "Equal"
  = "=" o
sym_amp "Ampersand"
  = "&" o
sym_pipe "Pipe"
  = "|" o
sym_mod "Modulo"
  = "%" o
sym_lt "Less Than"
  = "<" o
sym_gt "Greater Than"
  = ">" o
sym_excl "Exclamation"
  = "!" o

/* Keywords */

ABORT "ABORT Keyword"
  = "ABORT"i e
ACTION "ACTION Keyword"
  = "ACTION"i e
ADD "ADD Keyword"
  = "ADD"i e
AFTER "AFTER Keyword"
  = "AFTER"i e
ALL "ALL Keyword"
  = "ALL"i e
ALTER "ALTER Keyword"
  = "ALTER"i e
ANALYZE "ANALYZE Keyword"
  = "ANALYZE"i e
AND "AND Keyword"
  = "AND"i e
AS "AS Keyword"
  = "AS"i e
ASC "ASC Keyword"
  = "ASC"i e
ATTACH "ATTACH Keyword"
  = "ATTACH"i e
AUTOINCREMENT "AUTOINCREMENT Keyword"
  = "AUTOINCREMENT"i e
BEFORE "BEFORE Keyword"
  = "BEFORE"i e
BEGIN "BEGIN Keyword"
  = "BEGIN"i e
BETWEEN "BETWEEN Keyword"
  = "BETWEEN"i e
BY "BY Keyword"
  = "BY"i e
CASCADE "CASCADE Keyword"
  = "CASCADE"i e
CASE "CASE Keyword"
  = "CASE"i e
CAST "CAST Keyword"
  = "CAST"i e
CHECK "CHECK Keyword"
  = "CHECK"i e
COLLATE "COLLATE Keyword"
  = "COLLATE"i e
COLUMN "COLUMN Keyword"
  = "COLUMN"i e
COMMIT "COMMIT Keyword"
  = "COMMIT"i e
CONFLICT "CONFLICT Keyword"
  = "CONFLICT"i e
CONSTRAINT "CONSTRAINT Keyword"
  = "CONSTRAINT"i e
CREATE "CREATE Keyword"
  = "CREATE"i e
CROSS "CROSS Keyword"
  = "CROSS"i e
CURRENT_DATE "CURRENT_DATE Keyword"
  = "CURRENT_DATE"i e
CURRENT_TIME "CURRENT_TIME Keyword"
  = "CURRENT_TIME"i e
CURRENT_TIMESTAMP "CURRENT_TIMESTAMP Keyword"
  = "CURRENT_TIMESTAMP"i e
DATABASE "DATABASE Keyword"
  = "DATABASE"i e
DEFAULT "DEFAULT Keyword"
  = "DEFAULT"i e
DEFERRABLE "DEFERRABLE Keyword"
  = "DEFERRABLE"i e
DEFERRED "DEFERRED Keyword"
  = "DEFERRED"i e
DELETE "DELETE Keyword"
  = "DELETE"i e
DESC "DESC Keyword"
  = "DESC"i e
DETACH "DETACH Keyword"
  = "DETACH"i e
DISTINCT "DISTINCT Keyword"
  = "DISTINCT"i e
DROP "DROP Keyword"
  = "DROP"i e
EACH "EACH Keyword"
  = "EACH"i e
ELSE "ELSE Keyword"
  = "ELSE"i e
END "END Keyword"
  = "END"i e
ESCAPE "ESCAPE Keyword"
  = "ESCAPE"i e
EXCEPT "EXCEPT Keyword"
  = "EXCEPT"i e
EXCLUSIVE "EXCLUSIVE Keyword"
  = "EXCLUSIVE"i e
EXISTS "EXISTS Keyword"
  = "EXISTS"i e
EXPLAIN "EXPLAIN Keyword"
  = "EXPLAIN"i e
FAIL "FAIL Keyword"
  = "FAIL"i e
FOR "FOR Keyword"
  = "FOR"i e
FOREIGN "FOREIGN Keyword"
  = "FOREIGN"i e
FROM "FROM Keyword"
  = "FROM"i e
FULL "FULL Keyword"
  = "FULL"i e
GLOB "GLOB Keyword"
  = "GLOB"i e
GROUP "GROUP Keyword"
  = "GROUP"i e
HAVING "HAVING Keyword"
  = "HAVING"i e
IF "IF Keyword"
  = "IF"i e
IGNORE "IGNORE Keyword"
  = "IGNORE"i e
IMMEDIATE "IMMEDIATE Keyword"
  = "IMMEDIATE"i e
IN "IN Keyword"
  = "IN"i e
INDEX "INDEX Keyword"
  = "INDEX"i e
INDEXED "INDEXED Keyword"
  = "INDEXED"i e
INITIALLY "INITIALLY Keyword"
  = "INITIALLY"i e
INNER "INNER Keyword"
  = "INNER"i e
INSERT "INSERT Keyword"
  = "INSERT"i e
INSTEAD "INSTEAD Keyword"
  = "INSTEAD"i e
INTERSECT "INTERSECT Keyword"
  = "INTERSECT"i e
INTO "INTO Keyword"
  = "INTO"i e
IS "IS Keyword"
  = "IS"i e
ISNULL "ISNULL Keyword"
  = "ISNULL"i e
JOIN "JOIN Keyword"
  = "JOIN"i e
KEY "KEY Keyword"
  = "KEY"i e
LEFT "LEFT Keyword"
  = "LEFT"i e
LIKE "LIKE Keyword"
  = "LIKE"i e
LIMIT "LIMIT Keyword"
  = "LIMIT"i e
MATCH "MATCH Keyword"
  = "MATCH"i e
NATURAL "NATURAL Keyword"
  = "NATURAL"i e
NO "NO Keyword"
  = "NO"i e
NOT "NOT Keyword"
  = "NOT"i e
NOTNULL "NOTNULL Keyword"
  = "NOTNULL"i e
NULL "NULL Keyword"
  = "NULL"i e
OF "OF Keyword"
  = "OF"i e
OFFSET "OFFSET Keyword"
  = "OFFSET"i e
ON "ON Keyword"
  = "ON"i e
OR "OR Keyword"
  = "OR"i e
ORDER "ORDER Keyword"
  = "ORDER"i e
OUTER "OUTER Keyword"
  = "OUTER"i e
PLAN "PLAN Keyword"
  = "PLAN"i e
PRAGMA "PRAGMA Keyword"
  = "PRAGMA"i e
PRIMARY "PRIMARY Keyword"
  = "PRIMARY"i e
QUERY "QUERY Keyword"
  = "QUERY"i e
RAISE "RAISE Keyword"
  = "RAISE"i e
RECURSIVE "RECURSIVE Keyword"
  = "RECURSIVE"i e
REFERENCES "REFERENCES Keyword"
  = "REFERENCES"i e
REGEXP "REGEXP Keyword"
  = "REGEXP"i e
REINDEX "REINDEX Keyword"
  = "REINDEX"i e
RELEASE "RELEASE Keyword"
  = "RELEASE"i e
RENAME "RENAME Keyword"
  = "RENAME"i e
REPLACE "REPLACE Keyword"
  = "REPLACE"i e
RESTRICT "RESTRICT Keyword"
  = "RESTRICT"i e
RIGHT "RIGHT Keyword"
  = "RIGHT"i e
ROLLBACK "ROLLBACK Keyword"
  = "ROLLBACK"i e
ROW "ROW Keyword"
  = "ROW"i e
SAVEPOINT "SAVEPOINT Keyword"
  = "SAVEPOINT"i e
SELECT "SELECT Keyword"
  = "SELECT"i e
SET "SET Keyword"
  = "SET"i e
TABLE "TABLE Keyword"
  = "TABLE"i e
TEMP "TEMP Keyword"
  = "TEMP"i e
TEMPORARY "TEMPORARY Keyword"
  = "TEMPORARY"i e
THEN "THEN Keyword"
  = "THEN"i e
TO "TO Keyword"
  = "TO"i e
TRANSACTION "TRANSACTION Keyword"
  = "TRANSACTION"i e
TRIGGER "TRIGGER Keyword"
  = "TRIGGER"i e
UNION "UNION Keyword"
  = "UNION"i e
UNIQUE "UNIQUE Keyword"
  = "UNIQUE"i e
UPDATE "UPDATE Keyword"
  = "UPDATE"i e
USING "USING Keyword"
  = "USING"i e
VACUUM "VACUUM Keyword"
  = "VACUUM"i e
VALUES "VALUES Keyword"
  = "VALUES"i e
VIEW "VIEW Keyword"
  = "VIEW"i e
VIRTUAL "VIRTUAL Keyword"
  = "VIRTUAL"i e
WHEN "WHEN Keyword"
  = "WHEN"i e
WHERE "WHERE Keyword"
  = "WHERE"i e
WITH "WITH Keyword"
  = "WITH"i e
WITHOUT "WITHOUT Keyword"
  = "WITHOUT"i e

reserved_words
  = ABORT / ACTION / ADD / AFTER / ALL / ALTER / ANALYZE / AND / AS / ASC /
  ATTACH / AUTOINCREMENT / BEFORE / BEGIN / BETWEEN / BY / CASCADE / CASE /
  CAST / CHECK / COLLATE / COLUMN / COMMIT / CONFLICT / CONSTRAINT / CREATE /
  CROSS / CURRENT_DATE / CURRENT_TIME / CURRENT_TIMESTAMP / DATABASE / DEFAULT /
  DEFERRABLE / DEFERRED / DELETE / DESC / DETACH / DISTINCT / DROP / EACH /
  ELSE / END / ESCAPE / EXCEPT / EXCLUSIVE / EXISTS / EXPLAIN / FAIL / FOR /
  FOREIGN / FROM / FULL / GLOB / GROUP / HAVING / IF / IGNORE / IMMEDIATE / IN /
  INDEX / INDEXED / INITIALLY / INNER / INSERT / INSTEAD / INTERSECT / INTO /
  IS / ISNULL / JOIN / KEY / LEFT / LIKE / LIMIT / MATCH / NATURAL / NO / NOT /
  NOTNULL / NULL / OF / OFFSET / ON / OR / ORDER / OUTER / PLAN / PRAGMA /
  PRIMARY / QUERY / RAISE / RECURSIVE / REFERENCES / REGEXP / REINDEX /
  RELEASE / RENAME / REPLACE / RESTRICT / RIGHT / ROLLBACK / ROW / SAVEPOINT /
  SELECT / SET / TABLE / TEMP / TEMPORARY / THEN / TO / TRANSACTION / TRIGGER /
  UNION / UNIQUE / UPDATE / USING / VACUUM / VALUES / VIEW / VIRTUAL / WHEN /
  WHERE / WITH / WITHOUT

/* Generic rules */

any "Anything"
  = .

o "Optional Whitespace"
  = _*

e "Enforced Whitespace"
  = _+

_ "Whitespace"
  = [ \f\n\r\t\v]

/* TODO: Everything with this symbol */
_TODO_
  = "TODO" e
