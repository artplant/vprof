%% @author: Andrey Tsirulev
%% @date: 26.01.2016

-module(vprof_functions).

-behaviour(wx_object).

-include_lib("wx/include/wx.hrl").
-include("vprof.hrl").

-export([
    start_link/3
]).

%% wx_object callbacks
-export([
    init/1,
    handle_info/2,
    terminate/2,
    code_change/3,
    handle_call/3,
    handle_event/2,
    handle_sync_event/3,
    handle_cast/2]).


-record(state, {
    parent,
    processes_grid,
    called_by_grid,
    selected_grid,
    calling_grid
}).

start_link(Notebook, Data, Parent) ->
    wx_object:start_link(?MODULE, {Notebook, Data, Parent}, []).

init({Notebook, Data, Parent}) ->
    Panel = wxPanel:new(Notebook, [{size, wxWindow:getClientSize(Notebook)}]),
    
    Splitter = vprof_wx_utils:splitter(Panel),
    GridLeft = totals_grid(Splitter, Data, Parent),
    PanelRight = wxPanel:new(Splitter, [{size, wxWindow:getClientSize(Splitter)}]),
    vprof_wx_utils:split_vertical(Splitter, 0.5, GridLeft, PanelRight),

    ProcessesGrid = processes_grid(PanelRight, Data, undefined, Parent),
    CalledByGrid = called_by_grid(PanelRight, Data, unknown),
    SelectedGrid = selected_grid(PanelRight, Data, unknown),
    CallingGrid = calling_grid(PanelRight, Data, unknown),
    
    Box = wxBoxSizer:new(?wxVERTICAL),
    wxBoxSizer:add(Box, ProcessesGrid, [{flag, ?wxEXPAND bor ?wxALL}, {proportion, 1}, {border, 2}]),
    wxBoxSizer:add(Box, CalledByGrid, [{flag, ?wxEXPAND bor ?wxALL}, {proportion, 1}, {border, 2}]),
    Item = wxBoxSizer:add(Box, 100, 50, [{flag, ?wxEXPAND bor ?wxALL}, {border, 2}]),
    wxSizerItem:setWindow(Item, SelectedGrid),
    wxSizerItem:setMinSize(Item, 50, 50),
    wxBoxSizer:add(Box, CallingGrid, [{flag, ?wxEXPAND bor ?wxALL}, {proportion, 1}, {border, 2}]),
    wxWindow:setSizer(PanelRight, Box),

    State = #state{parent = Parent, processes_grid = ProcessesGrid, called_by_grid = CalledByGrid, calling_grid = CallingGrid, selected_grid = SelectedGrid},
    
    {Panel, State}.

totals_grid(Panel, Data, Parent) ->
    GridColumns = [
        #table_column{title = "Function", auto_size = true, alignment = ?wxLIST_FORMAT_LEFT,
            format = mfa, default_width = 200, binding = #row.mfa},
        #table_column{title = "Processes", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #row.pid_count, default_reversed = true},
        #table_column{title = "Count", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #row.cnt, default_reversed = true},
        #table_column{title = "Acc time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #row.acc, default_reversed = true, default_sort = true},
        #table_column{title = "Own time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #row.own, default_reversed = true}
    ],
    Self = self(),
    OnSelect = fun(DataRow) -> Self ! {select_function, DataRow} end,
    OnActivate = fun(DataRow) -> Parent ! {open_page, DataRow#row.mfa, format_mfa(DataRow#row.mfa), vprof_function} end,
    vprof_grid:start_link(Panel, self(), Data, total_calls, GridColumns, OnSelect, OnActivate).

processes_grid(Panel, Data, MFA, Parent) ->
    Columns = [
        #table_column{title = "PID", auto_size = true, alignment = ?wxLIST_FORMAT_LEFT,
            format = string, default_width = 70, binding = #row.pid},
        #table_column{title = "Count", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #row.cnt, default_reversed = true},
        #table_column{title = "Acc time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #row.acc, default_reversed = true, default_sort = true},
        #table_column{title = "Own time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #row.own, default_reversed = true}
    ],
    OnActivate = fun(DataRow) -> Parent ! {open_page, DataRow#row.pid, DataRow#row.pid, vprof_process} end,
    vprof_grid:start_link(Panel, self(), Data, {processes, MFA}, Columns, undefined, OnActivate).

called_by_grid(Panel, Data, MFA) ->
    Columns = [
        #table_column{title = "Called By", auto_size = true, alignment = ?wxLIST_FORMAT_LEFT,
            format = mfa, default_width = 200, binding = #row.mfa},
        #table_column{title = "Processes", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #row.pid_count, default_reversed = true},
        #table_column{title = "Count", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #row.cnt, default_reversed = true},
        #table_column{title = "Acc time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #row.acc, default_reversed = true, default_sort = true},
        #table_column{title = "Own time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #row.own, default_reversed = true}
    ],
    Self = self(),
    OnActivate = fun(DataRow) -> Self ! {select_function, DataRow} end,
    vprof_grid:start_link(Panel, self(), Data, {called_by, MFA}, Columns, undefined, OnActivate).
    
selected_grid(Panel, Data, MFA) ->
    Columns = [
        #table_column{title = "Function", auto_size = true, alignment = ?wxLIST_FORMAT_LEFT,
            format = mfa, default_width = 200, binding = #row.mfa},
        #table_column{title = "Processes", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #row.pid_count, default_reversed = true},
        #table_column{title = "Count", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #row.cnt, default_reversed = true},
        #table_column{title = "Acc time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #row.acc, default_reversed = true, default_sort = true},
        #table_column{title = "Own time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #row.own, default_reversed = true}
    ],
    vprof_grid:start_link(Panel, self(), Data, {mfa, MFA}, Columns, undefined, undefined).
    
calling_grid(Panel, Data, MFA) ->
    Columns = [
        #table_column{title = "Calling", auto_size = true, alignment = ?wxLIST_FORMAT_LEFT,
            format = mfa, default_width = 200, binding = #row.mfa},
        #table_column{title = "Processes", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #row.pid_count, default_reversed = true},
        #table_column{title = "Count", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            binding = #row.cnt, default_reversed = true},
        #table_column{title = "Acc time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #row.acc, default_reversed = true, default_sort = true},
        #table_column{title = "Own time", alignment = ?wxLIST_FORMAT_RIGHT, default_width = 100, 
            format = {float, 3}, binding = #row.own, default_reversed = true}
    ],
    Self = self(),
    OnActivate = fun(DataRow) -> Self ! {select_function, DataRow} end,
    vprof_grid:start_link(Panel, self(), Data, {calling, MFA}, Columns, undefined, OnActivate).

handle_event(Event, _State) ->
    error({unhandled_event, Event}).

handle_sync_event(_Event, _Obj, _State) ->
    ok.

handle_call(Event, From, _State) ->
    error({unhandled_call, Event, From}).

handle_cast(Event, _State) ->
    error({unhandled_cast, Event}).

handle_info({select_function, DataRow}, State) ->
    vprof_grid:set_data(State#state.processes_grid, {processes, DataRow#row.mfa}),
    vprof_grid:set_data(State#state.called_by_grid, {called_by,DataRow#row.mfa}),
    vprof_grid:set_data(State#state.calling_grid, {calling, DataRow#row.mfa}),
    vprof_grid:set_data(State#state.selected_grid, {mfa, DataRow#row.mfa}),
    {noreply, State};
handle_info({error, Error}, State) ->
    handle_error(Error),
    {noreply, State};
handle_info(_Event, State) ->
    {noreply, State}.

terminate(_Event, _State) ->
    ok.

code_change(_, _, State) ->
    State.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

handle_error(Foo) ->
    Str = io_lib:format("ERROR: ~s~n",[Foo]),
    observer_lib:display_info_dialog(Str).

format_mfa({Mod,Fun,A}) ->
    io_lib:format("~p:~p/~p", [Mod,Fun,A]).
