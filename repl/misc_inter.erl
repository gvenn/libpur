%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%   Copyright 2016 Purvey, Inc.
%%
%%   Licensed under the Apache License, Version 2.0 (the "License");
%%   you may not use this file except in compliance with the License.
%%   You may obtain a copy of the License at
%%
%%       http://www.apache.org/licenses/LICENSE-2.0
%%
%%   Unless required by applicable law or agreed to in writing, software
%%   distributed under the License is distributed on an "AS IS" BASIS,
%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%   See the License for the specific language governing permissions and
%%   limitations under the License.
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @author: Garrison M. Venn
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-module(misc_inter).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% % Execute in top repo directory
%% % To build
%% rebar3 shell
%% cd(repl).
%% c("misc_inter.erl").
%% f().
%% {TheKey, OuterContext} =
%%     misc_inter:nest_set([here], 4, [{outer_key, dict:new()}]).
%% dict:find(here, OuterContext).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-export([nest_find/2, nest_set/3]).

-include_lib("../include/pur_utls_misc.hrl").

nest_find([], Context) ->
    Context;
nest_find([NextId|RIds], Context) ->
    case dict:find(NextId, Context) of
        error -> 
            error;
        {ok, NContext} -> 
            nest_find(RIds, NContext)
    end.

nest_set([],
         _, 
         [R = {_LastContextKey, _LastContext}]) ->
    R;
nest_set([],
         Unused, 
         [{StoreKey, ToStore}, {NextKey, ToStoreIn}|RContexts]) ->
    nest_set([], 
             Unused, 
             [{NextKey, dict:store(StoreKey, ToStore, ToStoreIn)}|RContexts]);
nest_set([Key], Value, Contexts) ->
    % Could skip this step
    nest_set([], undefined, [{Key, Value}|Contexts]);
nest_set([Key|NKeys], Value, R = [{_, Context}|_]) ->
    case dict:find(Key, Context) of
        error -> error;
        {ok, NewContext} -> nest_set(NKeys, Value, [{Key, NewContext}|R])
    end.
    
