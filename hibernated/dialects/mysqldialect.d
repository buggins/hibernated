module hibernated.dialects.mysqldialect;

import hibernated.dialect;

class MySQLDialect : Dialect {
    ///The character specific to this dialect used to close a quoted identifier.
    override char closeQuote() { return '`'; }
    ///The character specific to this dialect used to begin a quoted identifier.
    override char  openQuote() { return '`'; }
}
