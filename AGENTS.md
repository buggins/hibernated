# AGENTS.md

Guidance for AI coding agents working on **hibernated**, an ORM for D modelled on Hibernate.

## Project at a glance

- **What:** entities mapped with annotations (`@Entity`, `@Id`, `@Generated`, relations, `@Embedded`, `@EmbeddedId`), a `Session` with HQL queries (`Query`), transactions and an entity cache. It runs on **ddbc** (`../ddbc`, the author's JDBC-like layer), which provides the drivers.
- **Repo:** `git@github.com:buggins/hibernated.git`, default branch **`master`**. The author is Vadim Lopatin (GitHub `buggins`).
- **License:** BSL-1.0 (Boost).
- **Registry:** https://code.dlang.org/packages/hibernated. The registry picks up a `vX.Y.Z` tag automatically; check that a new release appears.
- **Status:** 0.8.1 released on 2026-11-28 (`Query.setTimeout`, #141); 0.8.0 added `Session.cancelQuery()` (#139) on ddbc 0.16.
- **Releases:** there are no version constants and no CHANGELOG. A release is a `vX.Y.Z` tag on a merge commit of `master` plus a GitHub release with the notes. A release PR ("Closes #N") is needed only when something changes in the repository, such as the ddbc constraint in `dub.json`. Tag and publish only when the user asks.
- **`PLAN.md` (local and optional):** if present, it is a local, untracked file. Never `git add` it.

## Configurations and dialects

- dub configurations `full` (MySQL, SQLite, PGSQL), `MySQL`, `SQLite`, `PGSQL` and `ClickHouse` select the ddbc configuration of the same name (`subConfigurations`) and define `USE_<NAME>`. hibernated depends on ddbc `~>0.16.0`.
- Dialects (`source/hibernated/dialects/`): MySQL, PostgreSQL, SQLite, ClickHouse. A dialect quotes identifiers, maps types and adapts generated SQL through the hooks in `dialect.d`: `getCreateTableSuffix`, `getUpdatePrefix`/`getUpdateSuffix`, `getQuerySuffix`, `supportsTransactions`, `supportsGeneratedKeys` (and `generateKey`), `appendInsertToFetchGeneratedKey`. Add a hook with a neutral default rather than a dialect check in generic code.
- ClickHouse differs most (see the module comment of `clickhousedialect.d`): `ENGINE = MergeTree` ordered by the key, updates as synchronous `ALTER TABLE ... UPDATE` mutations, no transactions (beginning one throws), no foreign keys or unique constraints, client-generated keys, `Date32`/`DateTime64(0)` dates, `join_use_nulls = 1` for HQL queries.
- Dialects for SQL Server and Oracle (ddbc's MSSQL and ORACLE drivers) don't exist yet.

## Layout

```
source/hibernated/
  core.d          public imports
  annotations.d   the mapping annotations
  metadata.d      entity metadata (EntityInfo, PropertyInfo, SchemaInfoImpl), DDL (getCreateTableSQL)
  query.d         the HQL parser (QueryParser) and the SQL it generates
  session.d       Session, SessionFactory, Transaction, Query and their implementations, the entity cache,
                  lazy loading
  type.d          property types and the exception classes (HibernatedException, QueryException, ...)
  dialect.d       the abstract Dialect; dialects/*.d the concrete ones
  tests.d         unit tests (SQLite)
hdtest/           integration tests against real databases (its own dub project, depending on "../")
examples/example1 the README's example, built and run in CI
```

## Commands

```sh
dub build --config=SQLite
dub test --config=SQLite                       # unit tests
cd examples/example1 && dub                    # the example
cd hdtest && dub build --config=SQLite && ./bin/hdtest
cd hdtest && dub build --config=PGSQL && ./bin/hdtest --host=127.0.0.1 --port=5432 --database=hdtest --user=testuser --password=...
                                               # likewise --config=MySQL and --config=ClickHouse (--database=default --user=default)
```

- hdtest tests are classes derived from `HibernateTest` (`hdtest/source/hibernatetest.d`), with `@Test`, `@BeforeClass` and `@AfterClass` methods (`testrunner.d`), registered in `htestmain.d`. Each class builds its schema with its own entities (`buildSchema`).
- CI runs hdtest with SQLite, MySQL 5.7, PostgreSQL, ClickHouse latest and ClickHouse 23.8 (service containers; the public test account `testuser` / `passw0rd`). Locally, start the databases with `docker run --rm` and stop them afterwards; read passwords from the container's environment rather than writing them into files or output.
- hdtest builds hibernated through a path dependency, so it always tests the working tree.

## Design rules

1. **Minimum D frontend 2.097** (`toolchainRequirements`), the same as ddbc. Build and test with LDC 1.27.1 before pushing. Logging uses `std.logger` when it exists (2.101+), else `std.experimental.logger` (a `static if` in each module).
2. **A `Session` is used by one thread or task at a time.** `Session.cancelQuery()` is the only method that may be called from another thread or vibe.d task (#139).
   - The session's own statements are prepared and closed through `SessionImpl.prepareStatement` / `closeStatement`, which record the open statement under `statementLock`; `cancelQuery()` cancels that one through ddbc's `Statement.cancel()`. New code that runs SQL for the session must use these two, or its statement can't be cancelled.
   - Not reached: statements run in `doWork()`, and ClickHouse's key lookup on `save()`. A cancel while a statement is still being prepared may miss it.
3. **Query timeout** (`Query.setTimeout`, #141): passed to ddbc's `Statement.setQueryTimeout` for each statement a query runs, including the eager relation loads in the same call; 0 keeps the connection's setting.
4. **Transactions** (#135): a failed `commit()` leaves the transaction active (call `rollback()`); `rollback()` ends it even when it fails, and clears the session's cache (`Session.clear`), since cached entities may hold state the rollback undid; `Session.close()` rolls back an active transaction. Nothing may throw while a rollback error unwinds: LDC aborts on a second exception there.
5. **ddbc's exceptions pass through unchanged,** so callers can act on its classes (`SQLTransactionRollbackException`, `SQLTimeoutException`, `SQLNonTransientConnectionException`, SQLSTATE `57014` for a cancel).
6. **Public API:** `Session`, `Query` and the other public classes and interfaces are implemented outside hibernated too (wrappers, test doubles). In a release that promises compatibility, a new method gets a concrete default (as `Query.setTimeout` in 0.8.1) instead of being abstract.
7. **Changes need an hdtest test** for the databases they touch, run against the real servers, and a unit test in `tests.d` where SQLite is enough.

## Local environment

- WSL2 Linux. LDC 1.36 (`ldc2`, frontend 2.106) is the default compiler; DMD 2.107.1 is in `~/dlang/dmd-2.107.1/linux/bin64/dmd`; LDC 1.27.1 is downloaded into the session scratchpad when needed. Pass `--compiler=ldc2` explicitly.
- A ClickHouse server runs locally on `localhost:9000` (user `default`, no password); the `clickhoused-ch23` container gives ClickHouse 23.8 on port 19000 (`docker start clickhoused-ch23`, stop it afterwards). Other databases run in Docker per task.
- `jq` is not installed: use `gh --jq` or Python.

## Conventions

- Work goes through GitHub issues and pull requests: each fix or feature has an issue, a branch, and a PR that says `Closes #N`. The author merges; never push to `master`.
- Commit only when the user asks. **Before committing, run `/code-review`** on the changes and list its findings with your verdict and proposed action for each; ask which to apply.
- Every public symbol gets a Ddoc comment. Keep changes in the existing style of the file (tabs and spaces are mixed in older code); dfmt is not used here.
- The CI (`.github/workflows/dub.yml`): the SQLite build with DMD and LDC down to 2.097 on Linux and Windows (on Windows from DMD 2.099 / LDC 1.29), and with the latest compilers on macOS; the unit tests and the example1 build on Linux only; example1 runs with dmd-latest and ldc-latest on Linux, Windows and Intel macOS (no LDC on Windows); hdtest on Linux. Old LDCs (1.27–1.33) run on `ubuntu-22.04`, since `ubuntu-latest` (26.04) lacks `libxml2.so.2`.

## D idioms and review lessons

Learned from the review of the MySQL 8 work in mysql-native (mysql-d/mysql-native#288, 2026-11) and from the bugs fixed since in mysql-native, dbwire and the connectors. All of these work on the minimum frontend 2.097; checked with LDC 1.27.1.

- **`BigInt` and bytes: never go through hex or decimal strings.**
  - Bytes to `BigInt`: `BigInt(false, bytes)` takes any finite range of unsigned integers, most significant first.
  - `BigInt` to words or bytes: `value.getDigit!uint(i)` or `getDigit!ulong(i)` for `i` below `uintLength` or `ulongLength`, least significant first. dbwire's `WideInt.fromBigInt` does this.
  - Modular exponentiation: `std.bigint.powmod`.
  - `powmod` and the `BigInt(bool, Range)` constructor are new in Phobos 2.094 (`getDigit` and `uintLength` exist in 2.093). That's fine at our 2.097 minimum; in a project with a lower one, check first. mysql-native supports 2.085 and needed a `static if (__traits(compiles, ...))` fallback (mysql-d/mysql-native#288).
  - `format("%x", bigint)` groups digits with `_` until Phobos 2.114 (dlang/phobos#11051).
- **Enums for protocol names.** For a fixed set of wire strings such as plugin names, use a `ubyte` enum whose members are spelled exactly like the wire names; the protocol's own spelling beats camelCase here.
  - `to!string` then gives the name to send. It returns the stored literal and doesn't allocate for a valid member, but it isn't `nothrow` or `@nogc`.
  - To parse untrusted input, loop over the members: `static foreach (m; __traits(allMembers, E)) if (name == m) return __traits(getMember, E, m);`. This is `nothrow @nogc` and compares the packet slice directly, with no `idup`. Don't use `to!E(name)`, which throws `ConvException` on unknown names.
  - Each name then appears once, instead of in a parse table and a format table that can drift apart.
  - With a `string`-based enum, `to!string` returns the member's identifier, not its value.
- **Small idioms:**
  - Test byte vectors: `cast(const(ubyte)[]) std.conv.hexString!"0a1b..."` instead of hand-written hex decoding.
  - Strip leading zero bytes with `find!(b => b != 0)`.
  - Copy (`idup`) a slice only where it must outlive the buffer; an error message built inside `enforce` is lazy, so copying there is fine.
- **Function attributes** (`@safe`, `@trusted`, `pure`, `nothrow`, `@nogc`, `scope`). Sources: the D spec (function.html, attribute.html), the D blog's memory-safety series, and the D forum consensus. Behaviour checked with LDC 1.27.1 and 1.36 (2026-11-08).
  - **Inference.** Templates, `auto` functions, nested functions and lambdas infer `@safe`, `pure`, `nothrow` and `@nogc`. Other functions infer nothing, even when their body is visible.
    - Write the attributes on ordinary functions, public API first.
    - Leave them off templates. An attribute written on a template binds every instantiation (an `@safe` template rejects a `T` whose copy is `@system`).
    - Lock in what a template infers with an attributed unittest that instantiates it with plain types, e.g. `@safe pure nothrow @nogc unittest`.
  - **`@safe:` at module scope** covers everything after it, templates included; they still infer the other attributes. `pure`, `nothrow` and `@nogc` don't propagate into struct and class bodies.
  - **`@trusted` promises a safe interface.** For every argument a `@safe` caller can pass, the function must not corrupt memory or create an unsafe value, such as a dangling pointer or a `bool` other than 0 or 1. The compiler doesn't check the body.
    - Keep the trusted part as small as possible: trust the one `@system` call, e.g. `(() @trusted => v.get!T)()`, with a comment saying why it is safe.
    - A trusted lambda makes the enclosing function part of the review. Whatever the lambda relies on, such as a length checked a few lines earlier, must stay true when that function changes.
    - A `cast(ubyte[])` view of values without indirections is fine for reading. Writing arbitrary bytes into `bool` or enum values through such a view creates invalid values; normalize them before `@safe` code sees them.
  - **Never mark a template `@trusted` if its body copies, constructs or destroys a `T`.** The attribute hides `T`'s `@system` postblit, copy constructor or destructor. Checked: `V wrap(T)(ref T v) @trusted { T copy = v; ... }` compiles in `@safe` code for a struct with a `@system` postblit. Trust only the `@system` call inside, which lets inference catch `T`, or constrain `T` (`!hasIndirections!T`, `!hasElaborateCopyConstructor!T`).
  - **`nothrow`**: only `Error`s may escape.
    - Wrap calls that can't actually throw in `std.exception.assumeWontThrow`, or in `try ... catch (Exception e) assert(0, e.msg);`.
    - Never catch `Error` or `Throwable` to make code `nothrow`.
  - **`@nogc`** forbids `new`, array appending and concatenation, closures that escape, and `throw new`. Use it for leaf hot paths (codecs, parsers); error paths that throw stay outside it.
  - **`debug` statements** may break `pure`, `nothrow` and `@nogc`, which helps temporary logging. They compile only with `-debug`; don't leave them in committed code.
  - **`scope` and `return scope`** are checked only in `@safe` code compiled with `-preview=dip1000`, which is still not the default (D 2.113, August 2026).
    - Without that switch, `scope` is an unchecked promise. With it, callers may pass stack memory to a `scope` parameter, so a `@trusted` or `@system` function that keeps such a parameter has a memory bug.
    - dbwire and the four connectors are dip1000-clean on current compilers: CI runs their unit tests with `-preview=dip1000` on dmd-latest and ldc-latest (dbwire#50, clickhoused#71, postgresql-native#37, oracle-native#47, mssql-native#42). Older Phobos isn't: 2.097's `std.socket` has no `scope` annotations. Don't add `scope` speculatively.
- **No conditional members that change a layout.** A class, struct or interface must not get a field, a virtual method (one that takes a vtable slot: a public or protected method of a non-final class, an `override`, or an interface method) or an interface under a `version` or `debug` condition that the code importing the package may compile with differently: `version (unittest)`, `debug`, `version (assert)` (`-release`), `D_Coverage`, `Have_*`, or any version set through `versions`/`dflags`.
  - dub compiles each package with its own flags, and `dub test` adds `-unittest` to the root package only, so the library and the code importing it would disagree on the layout.
  - LDC 1.27–1.31 allocates a class from the library's size but copies the initializer of the size its own compilation sees: a heap overflow on every `new` (dbwire#84, `TlsTransport.readsThatSent`, found through mysql-native's TLS CI). DMD and newer LDC take the size from one place, so the bug stays hidden there.
  - Non-virtual (`private`, `package`, `final`) methods and static members are fine. Test-only helpers go in module-level `version (unittest)` blocks, and tests observe behaviour from outside (e.g. through a wrapping transport) instead of through counters in the class.
- **Destructors the GC may run.** A class destructor runs in a GC finalizer, and so does the destructor of a struct that ends up inside a GC-allocated object (an RAII handle such as `PooledConnection` kept in a user's class). The GC finalizes in any order (at exit, everything that is left) and doesn't allow allocating or locking there.
  - Such a destructor must not touch other GC-managed objects (they may already be finalized), take locks, allocate or throw.
  - When the cleanup needs any of that, start with `if (GC.inFinalizer) return;` (`core.memory`) and document that the resource then stays held, so users release it explicitly.
  - Fixed in every package (dbwire#79 `PoolLease`; clickhoused#81, postgresql-native#46, oracle-native#57, mssql-native#54 `PooledConnection` in a collected object).
- **Public API in minor and patch releases.** A new abstract method in a public class, or a method added to a public interface, breaks every implementation outside the package (wrappers, test doubles).
  - In a release that promises compatibility, give the method a concrete default in the base class, as hibernated 0.8.1 did for `Query.setTimeout` (buggins/hibernated#141). Even that breaks a subclass that already declares a method with the same name and signature (an override without `override`), so choose a name users are unlikely to have taken.
  - An interface can't get a default (only `final` methods): add the method to a new derived interface, or make a breaking release and say so in the release notes.
- **Changes to someone else's code: keep the diff small.** Keep the existing structure, and change the input instead of the cases. For example, when MySQL 8.4 inserted a `Language` column after `Type` in `SHOW PROCEDURE STATUS` (5.7, 8.0 and MariaDB don't have it; the manual doesn't list it), the fix kept the old switch on column numbers: skip column 3 when there are 12 columns, and shift the later indexes down by one.
  - Run the project's full CI on your fork after every push, review fixes included: open a draft PR inside the fork, then close it and delete its branch. mysql-native's Builds workflow tests dmd 2.085–2.093; a review fix that used Phobos 2.094 features broke them unnoticed for days.
- **Debugging heap corruption** (a crash inside the runtime, e.g. in `_d_newitemU`, `_aaGetX` or the GC):
  - Find the clobbered word and put a hardware watchpoint on it in gdb (`watch -l *(void**)0x...`); the stop shows the code that writes it.
  - For a class, compare `__traits(classInstanceSize, C)` with `typeid(C).initializer.length` in the same build. A difference means the compilations disagree on the layout (see above). This found dbwire#84 in minutes.
- **Tests of blocking behaviour must fail, not hang, when the feature breaks.** A test of a timeout, a cancel or a wait needs a slow operation that ends on its own (a query that finishes within about 20 seconds), or a watchdog that stops it after a deadline (a cancel from another thread).
  - Check every new test by removing the fix: it must fail, within a bounded time.
  - Example: with the timeout call removed, hibernated's query timeout test ran for minutes on SQLite until a watchdog cancel was added; on MySQL, which can't cancel, the slow query itself had to end on its own, after about 20 seconds (buggins/hibernated#141).
- **Check facts before writing them down.** Verify server behaviour on the real servers, since manuals lag behind. Take CI failure reasons from the job logs, not from memory. A wrong reason in a commit message had to be corrected during that review. A compiler's frontend version isn't its own version number: GDC 11 has frontend 2.076 and GDC 12 has 2.100 (LDC 1.24 is 2.094, LDC 1.27 is 2.097); check before naming a compiler as supported.
- **CI facts (November 2026):**
  - GitHub retired the `ubuntu-20.04` runners. When a matrix tests old compilers, pin a concrete image instead of `ubuntu-latest`, and prefer the oldest one still offered: `ubuntu-22.04` today (likely until mid-2027). The mysql-native reviewers asked for that as the most conservative choice, and old compilers down to dmd 2.097 / ldc 1.27 pass on it.
  - `macos-latest` is macOS 26 on arm64. There:
    - `setup-dlang` installs no DMD;
    - `setup-dlang@v1` requests `ldc2-1.28.1-osx-aarch64.tar.xz`, while LDC names the file `osx-arm64`, so the download fails with a 404.
    - A job cancelled before any step ran, with the annotation "The job was not acquired by Runner of type hosted even after multiple attempts", means GitHub had no free arm64 runner ("capacity constraints"). It isn't a failure: re-run the job.
  - `macos-15-intel` runs dmd-latest, dmd 2.098.1 and LDC 1.28.1. On macOS 15, even Intel, the dmd 2.101.2 binary doesn't run and LDC 1.31.0's dub crashes (SIGSEGV).
  - With `setup-dlang@v2.0.0`, programs built by LDC 1.30, 1.35 or 1.40.1 crash (segfault, even hello world) on `macos-latest`, `macos-15` and `macos-15-intel`. LDC 1.41.0 is the oldest that works there, so our CI tests ldc-latest and 1.41.0 on macOS, and the older LDCs on Linux.
  - `WebFreak001/dub-upgrade@v0.1.1` uses GitHub's retired cache service ("getCacheEntry failed"); v0.2.0 works.
  - A job that stops while fetching dependencies with "Failed to download package X from https://code.dlang.org/..." hit a registry outage, not a failure: re-run the job (buggins/hibernated#142).
