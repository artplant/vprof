%% Model

-record(totals, {acc, cnt, data}).

-record(process, {
    pid :: string(),
    cnt :: pos_integer(),
    own :: float(),
    schedules :: non_neg_integer()
}).

-record(function, {
    mfa,
    pid,
    cnt,
    acc,
    own,
    parents,
    children
}).

-record(ref, {
    mfa,
    cnt,
    acc,
    own
}).

%% View

-record(table_column, {
    binding,
    title,
    alignment,
    auto_size = false,
    default_width,
    default_sort = false,
    default_reversed = false,
    format
}).

-record(row, {
    mfa,
    pid,
    pid_count=1,
    cnt,
    acc,
    own,
    parents,
    children
}).

