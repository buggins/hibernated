module htestmain;

import std.typecons;
import std.algorithm;
import std.stdio;
import std.string;
import std.conv;
import std.getopt;
import hibernated.core;

import testrunner : runTests;
import hibernatetest : ConnectionParams;
import generaltest : GeneralTest;
import embeddedtest : EmbeddedTest;
import embeddedidtest : EmbeddedIdTest;
import transactiontest : TransactionTest;
import generatedtest : GeneratedTest;

void enableTraceLogging() {
    import std.logger : sharedLog, LogLevel, globalLogLevel;
    (cast() sharedLog).logLevel = LogLevel.trace;
    globalLogLevel = LogLevel.trace;
}

version (USE_CLICKHOUSE) void runNoTransactionsTest(TransactionTest test) {
  import std.exception : assertThrown;
  test.setup();
  scope(exit) test.teardown();
  Session sess = test.sessionFactory.openSession();
  scope(exit) sess.close();
  assertThrown!HibernatedException(sess.beginTransaction());
  writeln("transaction.unsupported: ok");
}

int main(string[] args) {

  // Use this to enable trace() logs, useful to inspect generated SQL.
  enableTraceLogging();

  ConnectionParams par;

  try {
		getopt(args, "host",&par.host, "port",&par.port, "database",&par.database, "user",&par.user, "password",&par.pass);
	} catch (GetOptException) {
		stderr.writefln("Could not parse args");
		return 1;
	}

  GeneralTest test1 = new GeneralTest();
  test1.setConnectionParams(par);
  runTests(test1);

  EmbeddedTest test2 = new EmbeddedTest();
  test2.setConnectionParams(par);
  runTests(test2);

  EmbeddedIdTest test3 = new EmbeddedIdTest();
  test3.setConnectionParams(par);
  runTests(test3);

  GeneratedTest test4 = new GeneratedTest();
  test4.setConnectionParams(par);
  runTests(test4);

  // TODO: Some tests that run after this have errors, find out why.
  TransactionTest test5 = new TransactionTest();
  test5.setConnectionParams(par);
  version (USE_CLICKHOUSE) {
    // ClickHouse has no transactions: beginTransaction() must refuse instead of silently not rolling back
    runNoTransactionsTest(test5);
  } else {
    runTests(test5);
  }

  writeln("All scenarios worked successfully");
  return 0;
}
