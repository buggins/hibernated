module testrunner;

import std.meta : AliasSeq;
import std.traits;
import std.stdio;

/**
 * When `runTests` is called on an object, methods annotated with `@Test` will be executed
 * after `@BeforeClass` methods, but before `@AfterClass` methods. The name of a test will
 * be displayed during execution.
 */
struct Test {
  string name;
}

/**
 * When `runTests` is called on an object, methods annotaetd with `@BeforeClass` will be executed
 * before any other methods. These methods typically set up test resources.
 */
struct BeforeClass { }

/**
 * When `runTests` is called on an object, methods annotaetd with `@BeforeClass` will be executed
 * before any other methods. These methdos typically tear down test resources.
 */
struct AfterClass { }

/**
 * Scans a class and executes methods in the following order.
 * 1. Class `@BeforeClass` methods.
 * 2. Base class `@BeforeClass` methods.
 * 3. Class `@Test` methods.
 * 4. Base class `@Test` methods.
 * 5. Class `@AfterClass` methods.
 * 6. Base class `@AfterClass` methods.
 */
void runTests(TestClass)(TestClass testClass) {
  // Search for member functions annotated with @BeforeClass and run them.
  static foreach (alias method; getSymbolsByUDA!(TestClass, BeforeClass)) {
    __traits(getMember, testClass, __traits(identifier, method))();
  }

  // Search for member functions annotated with @Test and run them.
  static foreach (alias method; getSymbolsByUDA!(TestClass, Test)) {
    writeln("Running Test: ", getUDAs!(method, Test)[0].name);
    __traits(getMember, testClass, __traits(identifier, method))();
  }

  // Search for member functions annotated with @AfterClass and run them.
  static foreach (alias method; getSymbolsByUDA!(TestClass, AfterClass)) {
    __traits(getMember, testClass, __traits(identifier, method))();
  }
}

unittest {
  int[] testOrder;

  class DummyTest {
    @BeforeClass
    void fanny() {
      testOrder ~= 2;
    }

    @Test("fanny test")
    void mytest() {
      testOrder ~= 4;
    }

    @AfterClass
    void foony() {
      testOrder ~= 6;
    }
  }

  class DoomyTest : DummyTest {
    @BeforeClass
    void flam() {
      testOrder ~= 1;
    }
    @Test("flam test")
    void moytest() {
      testOrder ~= 3;
    }
    @AfterClass
    void flom() {
      testOrder ~= 5;
    }
  }

  runTests(new DoomyTest());
  assert(testOrder == [1, 2, 3, 4, 5, 6]);
}
