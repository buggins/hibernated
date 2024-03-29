/**
 * HibernateD - Object-Relation Mapping for D programming language, with interface similar to Hibernate. 
 * 
 * Hibernate documentation can be found here:
 * $(LINK http://hibernate.org/docs)$(BR)
 * 
 * Source file hibernated/core.d.
 *
 * This module is convinient way to import all declarations to use HibernateD.
 * 
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module hibernated.core;

public import ddbc.core : Connection, DataSource, DataSetReader, DataSetWriter, ResultSet, SqlType, Statement;
public import ddbc.common;

public import hibernated.annotations;
public import hibernated.session;
public import hibernated.metadata;
public import hibernated.core;
public import hibernated.type;
public import hibernated.dialect : Dialect;

version( USE_SQLITE )
{
    public import hibernated.dialects.sqlitedialect;
}
version( USE_PGSQL )
{
    public import hibernated.dialects.pgsqldialect;
}
version( USE_MYSQL )
{
    public import hibernated.dialects.mysqldialect;
}
