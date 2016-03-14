%% @author: Andrey Tsirulev
%% @date: 13.08.2014

-module(vprof_wx_utils).

%% Include files
-include_lib("wx/include/wx.hrl").

%% Exported Functions

-export([
    splitter/1,
    split_vertical/4,
    split_horizontal/4
]).

%%%===================================================================
%%% API
%%%===================================================================

splitter(Parent) ->
    wxSplitterWindow:new(Parent, [{size, wxWindow:getClientSize(Parent)}]).

split_vertical(Splitter, Gravity, Child1, Child2) ->
    wxSplitterWindow:setSashGravity(Splitter, Gravity),
    wxSplitterWindow:setMinimumPaneSize(Splitter, 50),
    wxSplitterWindow:splitVertically(Splitter, Child1, Child2),
    
    Sizer = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(Sizer, Splitter, [{flag, ?wxEXPAND bor ?wxALL}, {proportion, 1}, {border, 5}]),
    wxWindow:setSizer(wxWindow:getParent(Splitter), Sizer).

split_horizontal(Splitter, Gravity, Child1, Child2) ->
    wxSplitterWindow:setSashGravity(Splitter, Gravity),
    wxSplitterWindow:setMinimumPaneSize(Splitter, 50),
    wxSplitterWindow:splitHorizontally(Splitter, Child1, Child2),
    
    Sizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(Sizer, Splitter, [{flag, ?wxEXPAND bor ?wxALL}, {proportion, 1}, {border, 5}]),
    wxWindow:setSizer(wxWindow:getParent(Splitter), Sizer).

%%%===================================================================
%%% Internal functions
%%%===================================================================





