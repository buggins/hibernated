module hibernated.hql;

import pegged.grammar;

mixin(grammar(`
# Basic PEG syntax: https://bford.info/pub/lang/peg.pdf
# Notes about extended PEG syntax: https://github.com/PhilippeSigaud/Pegged/wiki/Extended-PEG-Syntax
# 'txt' = Literal text to match against.
# [a-z] = A character class to match against.
# elem? = Matches an element occurring 0 or 1 times.
# elem* = Matches an element occurring 0 or more times.
# elem+ = Matches an element occurring 1 or more times.
# elem1 / elem2 = First attempts to match elem1, then elem2.
# :elem = Drop the element and its contents from the parse tree.
# &elem = Matches if elem is found, without including elem in the containing rule.
# !elem = Matches if elem is NOT found, without including elem in the containing rule.
HQL:
    Query           <-  SelectQuery  # / DeleteQuery / InsertQuery / UpdateQuery
    SubQuery        <-  SelectQuery

    SelectQuery     <-  (SelectClause :spaces)? FromClause (:spaces WhereClause)?
    # DeleteQuery   <- (DeleteKw FromClause WhereClause?)

    SelectClause    <- :SelectKw :spaces ( SelectItems ) # ( SelectItems / MapItems / ObjectItems )
    SelectItems      <- SelectItem (:spaces? ',' :spaces? SelectItem)*
    SelectItem      <- Expression (:spaces Alias)?
    Alias           <- :(AsKw spaces)? !Kw identifier

    FromClause      <- :FromKw :spaces IdentifierItem (:spaces Alias)?

    # See https://docs.jboss.org/hibernate/orm/3.3/reference/en/html/queryhql.html#queryhql-where
    WhereClause     <- WhereKw :spaces Expression

    # HQL expressions: https://docs.jboss.org/hibernate/orm/3.3/reference/en/html/queryhql.html#queryhql-expressions
    # For precedence, see: https://www.postgresql.org/docs/current/sql-syntax-lexical.html#SQL-PRECEDENCE
    Expression      <- CallExpression
                       / Unary1Expression
                       / BinaryExpression
                       / TrinaryExpression
                       / Unary2Expression
                       / ParenExpression
                       / SubQueryExpression
                       / IdentifierItem / LitItem / NamedParamItem
    BinaryExpression <- Expression :spaces BinaryOp :spaces Expression
    BinaryOp        <- '^' / '*' / '/' / '%'
                       / '+' / '-'
                       / InKw / LikeKw / ILikeKw / SimilarKw
                       / '<' / '>' / '=' / '<=' / '>=' / '<>'
                       / IsNotKw / IsKw
                       / AndKw / OrKw
    TrinaryExpression <- Expression :spaces BetweenKw :spaces Expression :spaces AndKw :spaces Expression

    # A method call, e.g. 'max(age)'.
    CallExpression  <- Func :spaces? :'(' ParameterList :')'
    Func            <- identifier
    ParameterList   <- Expression :spaces? (',' :spaces? Expression :spaces?)*
    ParenExpression <- '(' :spaces? Expression :spaces? ')'
    Unary1Expression <- ( '+' / '-' ) !NumberLit Expression
    Unary2Expression <- ( NotKw ) :spaces Expression

    SubQueryExpression <- ExistsKw :'(' SubQuery :')'
                          / Expression :spaces ( InKw / NotInKw ) :spaces? :'(' SubQuery :')'

    IdentifierItem  <- !Kw identifier ( :'.' identifier )*
    LitItem         <- StringLit / NumberLit / BoolLit / NullLit
    NamedParamItem  <- ':' identifier

    # See https://learn.microsoft.com/en-us/sql/odbc/reference/appendixes/numeric-literal-syntax?view=sql-server-ver16
    NumberLit       <- NumExpLit / SignedNumLit
    SignedNumLit    <~ [-+]? ;UnsignedNumLit
    UnsignedNumLit  <~ UnsignedInt ( '.' UnsignedInt? )?
    NumExpLit       <~ SignedNumLit [Ee] SignedInt
    SignedInt       <- [-+]? ;UnsignedInt
    UnsignedInt     <- [0-9]+

    # Use the syntactic predicate '!' to fail a match if it starts with "'".
    StringLit       <- "'" ( "''" / ( ! "'" . ) )* "'"

    BoolLit         <- TrueKw / FalseKw
    NullLit         <- NullKw

    Kw              <~ AndKw / AsKw / AvgKw / BetweenKw / CountKw / DeleteKw / ExistsKw / FalseKw / FromKw
                       / InKw / ILikeKw / IsKw / LikeKw / MaxKw / MinKw / NotKw / OrKw / SelectKw / SumKw
                       / TrueKw / WhereKw
    AndKw           <~ [Aa][Nn][Dd]
    AsKw            <~ [Aa][Ss]
    AvgKw           <~ [Aa][Vv][Gg]
    BetweenKw       <~ [Bb][Ee][Tt][Ww][Ee][Ee][Nn]
    CountKw         <~ [Cc][Oo][Uu][Nn][Tt]
    DeleteKw        <~ [Dd][Ee][Ll][Ee][Tt][Ee]
    ExistsKw        <~ [Ee][Xx][Ii][Ss][Tt][Ss]
    FalseKw         <~ [Ff][Aa][Ll][Ss][Ee]
    FromKw          <~ [Ff][Rr][Oo][Mm]
    ILikeKw         <~ [Ii][Ll][Ii][Kk][Ee]
    InKw            <~ [Ii][Nn]
    IsKw            <~ [Ii][Ss]
    IsNotKw         <~ [Ii][Ss] :spaces [Nn][Oo][Tt]
    LikeKw          <~ [Ll][Ii][Kk][Ee]
    MaxKw           <~ [Mm][Aa][Xx]
    MinKw           <~ [Mm][Ii][Nn]
    NotKw           <~ [Nn][Oo][Tt]
    NotInKw         <~ [Nn][Oo][Tt] :spaces [Ii][Nn]
    NullKw          <~ [Nn][Uu][Ll][Ll]
    OrKw            <~ [Oo][Rr]
    SelectKw        <~ [Ss][Ee][Ll][Ee][Cc][Tt]
    SimilarKw       <~ [Ss][Ii][Mm][Ii][Ll][Aa][Rr]
    SumKw           <~ [Ss][Uu][Mm]
    TrueKw          <~ [Tt][Rr][Uu][Ee]
    WhereKw         <~ [Ww][Hh][Ee][Rr][Ee]
`));

/// A sanity check on the HQL select clause.
unittest {
    // Dead simple HQL select.
    assert(HQL("FROM models.Fish").successful);
    // Select w/ numeric literals.
    assert(HQL("SELECT 2, +3, -4, 2., 3.14, -2.45, 3.2e-12 FROM models.Fish").successful);
    // Select w/ string literals.
    assert(HQL("SELECT 'ham', 'O''Henry' FROM models.Fish").successful);
    // Select w/ column names, alias-identifiers, implicit joins.
    assert(HQL("SELECT name, f.age, f.species.id FROM models.Fish f").successful);
    // Select w/ Parameters
    assert(HQL("select :name, :age FROM Ham").successful);
    // Select w/ expressions
    assert(HQL("select 1 + 2, 1 * (3 + 4), true and false, not true and false FROM Ham").successful);
}

/// A sanity check on the HQL where clause.
unittest {
    // Single values are permitted for where clauses.
    assert(HQL("FROM fish WHERE true").successful);
    // Binary expressions.
    assert(HQL("FROM fish WHERE a < b AND b like '%ham' OR c = 3 and d is NULL or e IS NOT null").successful);
    // Trinary expressions.
    assert(HQL("from fish where a between 3 and :maxA").successful);
    // SubQuery expressions.
    assert(HQL("FROM fish where name in (select name from Bird) or "
            ~ "exists ( from shark where id = fish.id )").successful);
}

/// A unittest focused on parsing of a select clause in normal form (not list, object, or map).
/// https://docs.jboss.org/hibernate/orm/3.3/reference/en/html/queryhql.html#queryhql-select
unittest {
    import std.stdio;
    ParseTree pt1 = HQL("SELECT -3.2, fish goober, max(bird) as flappy, -2.3E4 FROM models.Person AS p");
    writeln("pt1 = ", pt1);
    assert(pt1.successful);
    assert(pt1.children.length == 1 && pt1.children[0].name == "HQL.Query");

    ParseTree query = pt1.children[0];
    assert(query.children.length == 1 && query.children[0].name == "HQL.SelectQuery");

    ParseTree selectQuery = query.children[0];
    assert(selectQuery.children.length == 2);
    assert(selectQuery.children[0].name == "HQL.SelectClause");
    assert(selectQuery.children[1].name == "HQL.FromClause");

    ParseTree selectClause = selectQuery.children[0];
    assert(selectClause.children.length == 1 && selectClause.children[0].name == "HQL.SelectItems");

    ParseTree arrayItems = selectClause.children[0];
    assert(arrayItems.children.length == 4);
    // SelectItem have up to 2 matches: Expression and Alias
    assert(arrayItems.children[0].name == "HQL.SelectItem");
    assert(arrayItems.children[0].matches == ["-3.2"]);
    assert(arrayItems.children[1].matches == ["fish", "goober"]);
    assert(arrayItems.children[2].children[0].children[0].name == "HQL.CallExpression");
    ParseTree callExpression = arrayItems.children[2].children[0].children[0];
    assert(callExpression.children[0].name == "HQL.Func");
    assert(callExpression.children[0].matches == ["max"]);
    assert(callExpression.children[1].name == "HQL.ParameterList");
    assert(callExpression.children[1].matches == ["bird"]);
    assert(arrayItems.children[3].matches == ["-2.3E4"]);

    ParseTree fromClause = selectQuery.children[1];
    assert(fromClause.children.length == 2);
    assert(fromClause.children[0].name == "HQL.IdentifierItem");
    assert(fromClause.children[0].matches == ["models", "Person"]);
    assert(fromClause.children[1].name == "HQL.Alias");
    assert(fromClause.children[1].matches == ["p"]);
}
