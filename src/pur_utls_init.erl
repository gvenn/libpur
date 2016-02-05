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

-module(pur_utls_init).

-export([auto_set/4, auto_set/5]).

-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").

%%----------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% auto_set
%%----------------------------------------------------------------------------

auto_set(Props, Descriptors, Functions, ToSet) ->
    auto_set(Props, Descriptors, Functions, [], ToSet).

auto_set(Props, Descriptors, Functions, ExecContext, ToSet) ->
    case pur_utls_props:set_from_props(Props, Descriptors, ToSet) of
        {false, PartialToSet} -> 
            {false, 
             "pur_utls_props:set_from_props(...) failed.", 
             PartialToSet};
        {false, Reason, PartialToSet} -> 
            {false, Reason, PartialToSet};
        {true, NToSet} ->
            case run_through(Functions, Props, ExecContext, NToSet) of
                R = {true, _FToSet} -> R;
                R = {false, _Reason, _PartialToSet} -> R
            end
    end.

%%----------------------------------------------------------------------------
%% Internal Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% run_through
%%----------------------------------------------------------------------------

run_through(Functions, Props, Context, ToSet) ->
    case lists:foldl(fun 
                         (ToExecute, {true, _NReason, NToSet}) ->
                             case ToExecute(Props, Context, NToSet) of
                                 {true, RNToSet} -> {true, "", RNToSet};
                                 R = {false, _RNReason, _RNToSet} -> R
                             end;
                         (_ToExecute, R = {false, _NReason, _NToSet}) ->
                             R
                     end,
                     {true, "", ToSet},
                     Functions) of
        {true, _, FToSet} -> {true, FToSet};
        FR -> FR
    end.
