# vprof
Visual Erlang Profiler 

# Usage

## Collect

```erlang
%% Trace target node for 2 seconds:
1> vprof:trace(2).  
ok
```

## Analyze

```erlang
%% Process data - on any node
2> vprof:profile().
vprof: Profiling vprof.trace. This may take several minutes.
<0.47.0>
vprof: End of trace in 1 seconds.
vprof: Done in 1 seconds.
Check vprof.out to see results or run
vprof:gui("vprof.out").
```

## View

```
3> vprof:gui().
```

![GUI](/guiexample.png?raw=true)
