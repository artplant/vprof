-ifdef(OTP_RELEASE).
-if(?OTP_RELEASE >= 24).
-define(assignWindow, assignWindow).
-else.
-define(assignWindow, setWindow).
-endif.
-else.
-define(assignWindow, setWindow).
-endif.

