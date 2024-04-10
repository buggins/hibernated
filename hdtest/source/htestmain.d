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

int main(string[] args) {

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

  TransactionTest test4 = new TransactionTest();
  test4.setConnectionParams(par);
  runTests(test4);

  writeln("All scenarios worked successfully");
  return 0;
}
