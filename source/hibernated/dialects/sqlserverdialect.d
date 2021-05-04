/**
 * HibernateD - Object-Relation Mapping for D programming language, with interface similar to Hibernate. 
 * 
 * Source file hibernated/dialects/sqlserverdialect.d.
 *
 * This module contains implementation of SQLServerDialect class which provides implementation specific SQL syntax information.
 * 
 * Copyright: Copyright 2021
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Samael (singingbush)
 */
module hibernated.dialects.sqlserverdialect;

import std.algorithm.iteration : uniq;
import std.array;
import hibernated.dialect;
import hibernated.dialects.odbcdialect;
import hibernated.metadata;
import hibernated.type;
import ddbc.core;


const string[] SQLSERVER_RESERVED_WORDS = uniq(ODBC_RESERVED_WORDS ~ [ "HOLDLOCK", "ROWGUIDCOL" ]).array;

class SQLServerDialect : OdbcDialect {

    this() {
        addKeywords(SQLSERVER_RESERVED_WORDS);
    }
    
    /// use the INFORMATION_SCHEMA table 
    override string getCheckTableExistsSQL(string tableName) {
        // todo: consider checking both TABLE_SCHEMA and TABLE_NAME to avoid name clash problems
        return "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = " ~ quoteSqlString(tableName);
    }
    
    override string getUniqueIndexItemSQL(string indexName, string[] columnNames) {
        return null; // todo: return "UNIQUE " ~ createFieldListSQL(columnNames);
    }
    
    /// for some of RDBMS it's necessary to pass additional clauses in query to get generated value (e.g. in Postgres - " returing id"
    override string appendInsertToFetchGeneratedKey(string query, const EntityInfo entity) {
        return null; // todo: return query ~ " RETURNING " ~ quoteIfNeeded(entity.getKeyProperty().columnName);
    }

    // returns string like "BIGINT(20) NOT NULL" or "VARCHAR(255) NULL"
    override string getColumnTypeDefinition(const PropertyInfo pi, const PropertyInfo overrideTypeFrom = null) {
        immutable Type type = overrideTypeFrom !is null ? overrideTypeFrom.columnType : pi.columnType;
        immutable SqlType sqlType = type.getSqlType();
        bool fk = pi is null;
        string nullablility = !fk && pi.nullable ? " NULL" : " NOT NULL";
        string pk = !fk && pi.key ? " PRIMARY KEY" : "";

        // todo: finish this
        return null;
    }

}