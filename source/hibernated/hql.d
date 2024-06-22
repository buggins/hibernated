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
    # Query           <-  ( SelectQuery / DeleteQuery / UpdateQuery ) eoi
    Query           <-  ( SelectQuery / DeleteQuery ) eoi
    SubQuery        <-  SelectQuery

    SelectQuery     <-  (SelectClause :spaces)? FromClause (:spaces WhereClause)? (:spaces OrderClause)?

    DeleteQuery     <- DeleteKw :spaces FromClause2 (:spaces WhereClause)?

    # Inserts are done by periodically flushing the cache, and shoud be implemented accordingly.
    # See: https://docs.jboss.org/hibernate/orm/3.3/reference/en/html/batch.html#batch-inserts

    # The select clause has array, map, and object forms.
    # See: https://docs.jboss.org/hibernate/orm/3.3/reference/en/html/queryhql.html#queryhql-select
    SelectClause    <- :SelectKw :spaces ( MapItems / ObjectItems / ArrayItems )
    MapItems        <- :'new' :spaces :'map' :spaces? :'(' :spaces? ArrayItems :spaces? :')'
    ObjectItems     <- :'new' :spaces IdentifierItem :spaces? :'(' :spaces? ArrayItems :spaces? :')'
    ArrayItems      <- SelectItem (:spaces? ',' :spaces? SelectItem)*

    SelectItem      <- Expression (:spaces Alias)?
    Alias           <- :(AsKw :spaces)? Identifier

    FromClause      <- :FromKw :spaces FromItem
    # A variant of the From clause where the FromKw is optional.
    FromClause2     <- (:FromKw :spaces)? FromItem

    # See https://www.postgresql.org/docs/16/sql-select.html
    # See https://docs.jboss.org/hibernate/orm/3.3/reference/en/html/queryhql.html#queryhql-joins
    FromItem        <- IdentifierItem (:spaces Alias)? (:spaces JoinItems)?
    JoinItems       <- JoinItem (:spaces JoinItem)*
    JoinItem        <- JoinType :spaces IdentifierItem (:spaces Alias)? (:spaces WithKw :spaces Expression)?
    JoinType        <- :(InnerKw spaces)? JoinKw (:spaces FetchKw)?
                       / LeftKw :spaces :(OuterKw spaces)? JoinKw (:spaces FetchKw)?
                       / RightKw :spaces :(OuterKw spaces)? JoinKw (:spaces FetchKw)?
                       / FullKw :spaces :(OuterKw spaces)? JoinKw (:spaces FetchKw)?

    # See https://docs.jboss.org/hibernate/orm/3.3/reference/en/html/queryhql.html#queryhql-where
    WhereClause     <- WhereKw :spaces Expression

    # See https://docs.jboss.org/hibernate/orm/3.3/reference/en/html/queryhql.html#queryhql-ordering
    OrderClause     <- OrderKw :spaces ByKw :spaces Expression ( :spaces OrderDir )?
    OrderDir        <- AscKw / DescKw

    # HQL expressions: https://docs.jboss.org/hibernate/orm/3.3/reference/en/html/queryhql.html#queryhql-expressions
    # For precedence, see: https://www.postgresql.org/docs/current/sql-syntax-lexical.html#SQL-PRECEDENCE
    Expression      <- Unary1Expression
                       / Binary1Expression
                       / Binary2Expression
                       / TrinaryExpression
                       / Unary2Expression
                       / ParenExpression
                       / SubQueryExpression
                       / CallExpression
                       / IdentifierItem / LitItem / NamedParamItem
    # A limited expression missing logical operators, which create ambiguity with 'between a and b'.
    LimExpression   <- Unary1Expression
                       / Binary1Expression
                       / Unary2Expression
                       / ParenExpression
                       / SubQueryExpression
                       / CallExpression
                       / IdentifierItem / LitItem / NamedParamItem
    Binary1Expression <- Expression :spaces Binary1Op :spaces Expression
    Binary1Op         <- '^' / '*' / '/' / '%'
                         / '+' / '-'
                         / InKw / LikeKw / ILikeKw / SimilarKw
                         / '<' / '>' / '=' / '<=' / '>=' / '<>'
                         / IsNotKw / IsKw
    Binary2Expression <- Expression :spaces Binary2Op :spaces Expression
    Binary2Op         <- AndKw / OrKw
    TrinaryExpression <- Expression :spaces BetweenKw :spaces LimExpression :spaces AndKw :spaces LimExpression

    # A method call, e.g. 'max(age)'.
    CallExpression  <- Func :spaces? :'(' :spaces? ParameterList :spaces? :')'
    Func            <- identifier
    ParameterList   <- Expression ( :spaces? ',' :spaces? Expression )*
    ParenExpression <- '(' :spaces? Expression :spaces? ')'
    Unary1Expression <- ( '+' / '-' ) !NumberLit Expression
    Unary2Expression <- ( NotKw ) :spaces Expression

    SubQueryExpression <- ExistsKw :spaces? :'(' :spaces? SubQuery :spaces? :')'
                          / Expression :spaces ( InKw / NotInKw ) :spaces :'(' SubQuery :')'

    Identifier      <~ ((!Kw identifier) / (Kw identifier))
    IdentifierItem  <- Identifier ( :'.' Identifier )*
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

    Kw              <~ AndKw / AsKw / AscKw / AvgKw / BetweenKw / ByKw / CountKw / DeleteKw / DescKw / ExistsKw
                       / FalseKw / FetchKw / FromKw / FullKw / InnerKw / InKw / ILikeKw / IsKw / JoinKw / LeftKw
                       / LikeKw / MaxKw / MinKw / NotKw / OrderKw / OrKw / OuterKw / RightKw / SelectKw / SumKw
                       / TrueKw / WhereKw / WithKw
    AndKw           <~ [Aa][Nn][Dd]
    AsKw            <~ [Aa][Ss]
    AscKw           <~ [Aa][Ss][Cc]
    AvgKw           <~ [Aa][Vv][Gg]
    BetweenKw       <~ [Bb][Ee][Tt][Ww][Ee][Ee][Nn]
    ByKw            <~ [Bb][Yy]
    CountKw         <~ [Cc][Oo][Uu][Nn][Tt]
    DeleteKw        <~ [Dd][Ee][Ll][Ee][Tt][Ee]
    DescKw          <~ [Dd][Ee][Ss][Cc]
    ExistsKw        <~ [Ee][Xx][Ii][Ss][Tt][Ss]
    FalseKw         <~ [Ff][Aa][Ll][Ss][Ee]
    FetchKw         <~ [Ff][Ee][Tt][Cc][Hh]
    FromKw          <~ [Ff][Rr][Oo][Mm]
    FullKw          <~ [Ff][Uu][Ll][Ll]
    ILikeKw         <~ [Ii][Ll][Ii][Kk][Ee]
    InnerKw         <~ [Ii][Nn][Nn][Ee][Rr]
    InKw            <~ [Ii][Nn]
    IsKw            <~ [Ii][Ss]
    IsNotKw         <~ [Ii][Ss] :spaces [Nn][Oo][Tt]
    JoinKw          <~ [Jj][Oo][Ii][Nn]
    LeftKw          <~ [Ll][Ee][Ff][Tt]
    LikeKw          <~ [Ll][Ii][Kk][Ee]
    MaxKw           <~ [Mm][Aa][Xx]
    MinKw           <~ [Mm][Ii][Nn]
    NotKw           <~ [Nn][Oo][Tt]
    NotInKw         <~ [Nn][Oo][Tt] :spaces [Ii][Nn]
    NullKw          <~ [Nn][Uu][Ll][Ll]
    OrKw            <~ [Oo][Rr]
    OrderKw         <~ [Oo][Rr][Dd][Ee][Rr]
    OuterKw         <~ [Oo][Uu][Tt][Ee][Rr]
    RightKw         <~ [Rr][Ii][Gg][Hh][Tt]
    SelectKw        <~ [Ss][Ee][Ll][Ee][Cc][Tt]
    SimilarKw       <~ [Ss][Ii][Mm][Ii][Ll][Aa][Rr]
    SumKw           <~ [Ss][Uu][Mm]
    TrueKw          <~ [Tt][Rr][Uu][Ee]
    UpdateKw        <~ [Uu][Pp][Dd][Aa][Tt][Ee]
    WhereKw         <~ [Ww][Hh][Ee][Rr][Ee]
    WithKw          <~ [Ww][Ii][Tt][Hh]

    # End of input, e.g. not any character.
    identifierChar  <- [a-zA-Z_0-9]
    eow             <- !identifierChar
    eoi             <- !.
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
    assert(HQL("select count(h), min(age, height) FROM Ham h").successful);
    // Invalid queries.
    assert(!HQL("FROM models.Fish floom boom").successful);
}

/// Test some of HQL's alternate select forms, e.g. as a map or an object.
unittest {
    // Delcare a map, which in D could be an associative array or other implementation.
    import std.stdio;
    assert(HQL("SELECT new map(1 as turn, 2 as magic, age > 18 as is_adult ) FROM Person").successful);
    // Declare a new object (assuming a constructor exists).
    assert(HQL("SELECT new Birb(1 as turn, 2 as magic, age > 18 as is_adult ) FROM Person").successful);
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

// A sanity check on HQL order-by clause.
unittest {
    // Order by ascending.
    assert(HQL("FROM fish ORDER BY age ASC").successful);
    // Order by descending.
    assert(HQL("FROM fish ORDER BY sister.age desc").successful);
    // Implicit sort order (system determined).
    assert(HQL("FROM fish ORDER BY sister.age").successful);
    // Some invalid ordering that should be rejected.
    assert(!HQL("FROM fish ORDER BY sister.age ARSC").successful);
    assert(!HQL("FROM fish ORDER BY sister.age ASC DESC").successful);
}

// A sanity check on HQL joins and fetches.
unittest {
    assert(HQL("from Cat as cat "
            ~ "inner join cat.mate as mate "
            ~ "left outer join cat.kittens as kitten").successful);
    assert(HQL("from Cat as cat left join cat.mate.kittens as kittens").successful);
    assert(HQL("from Formula form full join form.parameter param").successful);
    // join types may be abbreviated
    assert(HQL("from Cat as cat "
            ~ "join cat.mate as mate "
            ~ "left join cat.kittens as kitten").successful);
    // extra conditions using the "with" keyword
    assert(HQL("from Cat as cat "
            ~ "left join cat.kittens as kitten "
            ~ "with kitten.bodyWeight > 10.0").successful);
    // fetch joins without aliases
    assert(HQL("from Cat as cat "
            ~ "inner join fetch cat.mate "
            ~ "left join fetch cat.kittens").successful);
    // fetch joins with aliases
    assert(HQL("from Cat as cat "
            ~ "inner join fetch cat.mate "
            ~ "left join fetch cat.kittens child "
            ~ "left join fetch child.kittens").successful);
}

// A sanity check for HQL update and delete queries.
unittest {
    assert(HQL("delete from dogs where name = :Doggo").successful);
    assert(HQL("DELETE dogs").successful);
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
    assert(selectClause.children.length == 1 && selectClause.children[0].name == "HQL.ArrayItems");

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
    assert(fromClause.children.length == 1);
    ParseTree fromItem = fromClause.children[0];
    assert(fromItem.children.length == 2);
    assert(fromItem.children[0].name == "HQL.IdentifierItem");
    assert(fromItem.children[0].matches == ["models", "Person"]);
    assert(fromItem.children[1].name == "HQL.Alias");
    assert(fromItem.children[1].matches == ["p"]);
}
