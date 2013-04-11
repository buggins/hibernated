/**
 * DDBC - D DataBase Connector - abstraction layer for RDBMS access, with interface similar to JDBC. 
 * 
 * Source file ddbc/drivers/pgsqlddbc.d.
 *
 * DDBC library attempts to provide implementation independent interface to different databases.
 * 
 * Set of supported RDBMSs can be extended by writing Drivers for particular DBs.
 * Currently it only includes MySQL driver.
 * 
 * JDBC documentation can be found here:
 * $(LINK http://docs.oracle.com/javase/1.5.0/docs/api/java/sql/package-summary.html)$(BR)
 *
 * This module contains implementation of PostgreSQL Driver
 * 
 *
 * You can find usage examples in unittest{} sections.
 *
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module ddbc.drivers.pgsql;

import std.algorithm;
import std.conv;
import std.datetime;
import std.exception;
import std.stdio;
import std.string;
import std.variant;

version(USE_PGSQL) {
    
    
    version (Windows) {
        pragma (lib, "libpq.lib");
        //pragma (lib, "pq");
    } else version (linux) {
        pragma (lib, "pq");
    } else version (Posix) {
        pragma (lib, "pq");
    } else version (darwin) {
        pragma (lib, "pq");
    } else {
        pragma (msg, "You will need to manually link in the LIBPQ library.");
    } 

    // C interface of libpq is taken from https://github.com/adamdruppe/misc-stuff-including-D-programming-language-web-stuff/blob/master/postgres.d
    

    extern(C) {
        struct PGconn {};
        struct PGresult {};
        
        void PQfinish(PGconn*);
        PGconn* PQconnectdb(const char*);
        PGconn *PQconnectdbParams(const char **keywords, const char **values, int expand_dbname);
        
        int PQstatus(PGconn*); // FIXME check return value
        
        const (char*) PQerrorMessage(PGconn*);
        
        PGresult* PQexec(PGconn*, const char*);
        void PQclear(PGresult*);
        
        
        int PQresultStatus(PGresult*); // FIXME check return value
        char *PQcmdTuples(PGresult *res);
        
        int PQnfields(PGresult*); // number of fields in a result
        const(char*) PQfname(PGresult*, int); // name of field
        
        int PQntuples(PGresult*); // number of rows in result
        const(char*) PQgetvalue(PGresult*, int row, int column);
        
        size_t PQescapeString (char *to, const char *from, size_t length);
        
        enum int CONNECTION_OK = 0;
        enum int PGRES_COMMAND_OK = 1;
        enum int PGRES_TUPLES_OK = 2;
        
        int PQgetlength(const PGresult *res,
                        int row_number,
                        int column_number);
        int PQgetisnull(const PGresult *res,
                        int row_number,
                        int column_number);
        
        alias ulong Oid;
        
        Oid PQftype(const PGresult *res,
                    int column_number);
        Oid PQoidValue(const PGresult *res);
        
        int PQfformat(const PGresult *res,
                      int column_number);
    }
    
} else { // version(USE_PGSQL)
    immutable bool PGSQL_TESTS_ENABLED = false;
}

