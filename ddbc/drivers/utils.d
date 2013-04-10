/**
 * DDBC - D DataBase Connector - abstraction layer for RDBMS access, with interface similar to JDBC. 
 * 
 * Source file ddbc/drivers/mysqlddbc.d.
 *
 * DDBC library attempts to provide implementation independent interface to different databases.
 * 
 * Set of supported RDBMSs can be extended by writing Drivers for particular DBs.
 * 
 * JDBC documentation can be found here:
 * $(LINK http://docs.oracle.com/javase/1.5.0/docs/api/java/sql/package-summary.html)$(BR)
 *
 * This module contains misc utility functions which may help in implementation of DDBC drivers.
 * 
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module ddbc.drivers.utils;

string copyCString(const char* c, int actualLength = -1) {
    const(char)* a = c;
    if(a is null)
        return null;
    
    string ret;
    if(actualLength == -1)
    while(*a) {
        ret ~= *a;
        a++;
    }
    else {
        ret = a[0..actualLength].idup;
    }
    
    return ret;
}
