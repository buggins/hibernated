module hibernated.core;

import hibernated.annotations;
import hibernated.metadata;
import hibernated.type;

class HibernatedException : Exception {
    private Exception causedBy;
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(string msg, Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); this.causedBy = causedBy; }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); this.causedBy = causedBy; }
    Exception getCausedBy() { return causedBy; }
}
